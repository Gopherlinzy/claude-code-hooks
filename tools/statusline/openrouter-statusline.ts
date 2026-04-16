#!/usr/bin/env node

/**
 * OpenRouter StatusLine for --extra-cmd
 * 显示 provider（generation 接口）+ model（claude-hud 实时）+ 余额
 *
 * 刷新策略：
 *   - model_id 变化（/model 切换）→ 立即更新显示 + 触发 generation 接口刷新 provider
 *   - 超过 TTL（60s）→ 重新调 generation 接口刷新 provider
 *   - 其余情况 → 用缓存
 *
 * 设计原则：
 *   - model 名称：始终从 claude-hud-current-model.json 读（实时感知 /model 切换）
 *   - provider：从 generation 接口读，TTL 缓存（provider 变化不频繁）
 *   - 两者解耦，model 变化不依赖 generation 接口返回的 model 字段
 */

import * as fs from "fs";
import * as path from "path";
import * as child_process from "child_process";
import * as os from "os";

// ── 类型定义 ─────────────────────────────────────────────────────────────────

interface CostState {
  seen_ids: string[];
  total_cost: number;
  total_cache_discount: number;
  last_provider: string;
  last_model: string;
  // 缓存策略字段
  cached_model_id?: string;  // 上次写入时的 hud model_id（用于变化检测）
  last_fetched_at?: number;  // 上次调 generation 接口的时间戳
}

interface ModelState {
  model_id: string;
  display_name: string;
  updated_at: number;
}

// ── 常量 ─────────────────────────────────────────────────────────────────────

const OPENROUTER_API_KEY =
  process.env.OPENROUTER_API_KEY || process.env.ANTHROPIC_AUTH_TOKEN;

/** provider 缓存有效期（ms） */
const PROVIDER_CACHE_TTL = 60_000;

/** claude-hud model 文件有效期（ms） */
const HUD_MODEL_TTL = 120_000;

if (!OPENROUTER_API_KEY) {
  process.exit(0);
}

// ── 工具函数 ─────────────────────────────────────────────────────────────────

async function fetchWithTimeout(
  url: string,
  headers: Record<string, string> = {},
  timeoutMs = 3000
): Promise<string> {
  return new Promise((resolve) => {
    const curlArgs = ["-s", "--max-time", String(Math.ceil(timeoutMs / 1000)), url];
    for (const [key, val] of Object.entries(headers)) {
      curlArgs.push("-H", `${key}: ${val}`);
    }

    const timeout = setTimeout(() => {
      try { process.kill(child.pid!); } catch {}
      resolve("");
    }, timeoutMs);

    const child = child_process.spawn("curl", curlArgs);
    let stdout = "";
    child.stdout?.on("data", (d) => { stdout += d.toString(); });
    child.on("close", () => { clearTimeout(timeout); resolve(stdout); });
    child.on("error", () => { clearTimeout(timeout); resolve(""); });
  });
}

/**
 * 清理 claude-hud 写入的 model_id：
 *   - 去除 ANSI escape（\x1B[1m 等）
 *   - 去除 literal [Nm] 残留（/model 命令输出混入的终端控制码）
 */
function cleanHudModelId(modelId: string): string {
  return modelId
    .replace(/\x1B\[[0-9;]*m/g, "")   // 标准 ANSI escape
    .replace(/\[\d+m\]/g, "")          // literal [1m] 形式（无 ESC 前缀）
    .replace(/\[[\d;]+m/g, "")         // literal [1;2m 形式
    .trim();
}

/** OpenRouter vendor/model 格式 → 短名称，去掉日期版本号 */
function formatModelLabel(modelId: string): string {
  const part = modelId.split("/").pop() || modelId;
  return part.replace(/-\d{8}$/, "").replace(/-\d+$/, "");
}

// ── 数据读取 ─────────────────────────────────────────────────────────────────

/** 读取 claude-hud 写入的当前模型（实时，/model 切换后立即更新） */
function getHudModelState(): ModelState | null {
  const dirs = [process.env.TMPDIR, os.tmpdir(), "/tmp", "/var/tmp"].filter(Boolean);
  for (const dir of dirs) {
    try {
      const f = path.join(dir!, "claude-hud-current-model.json");
      if (!fs.existsSync(f)) continue;
      const state: ModelState = JSON.parse(fs.readFileSync(f, "utf-8"));
      if (Date.now() - state.updated_at < HUD_MODEL_TTL) return state;
    } catch {}
  }
  return null;
}

/** 找最近修改的 session cost 缓存文件 */
function findLatestCostFile(): { file: string; state: CostState } | null {
  const dirs = [
    process.env.TMPDIR, process.env.TMP, process.env.TEMP,
    os.tmpdir(), "/tmp", "/var/tmp",
  ].filter(Boolean);

  let latestFile = "";
  let latestTime = 0;

  for (const dir of dirs) {
    try {
      for (const entry of fs.readdirSync(dir!)) {
        if (!entry.startsWith("claude-openrouter-cost-") || !entry.endsWith(".json")) continue;
        const full = path.join(dir!, entry);
        const mtime = fs.statSync(full).mtimeMs;
        if (mtime > latestTime) { latestTime = mtime; latestFile = full; }
      }
    } catch {}
  }

  if (!latestFile) return null;
  try {
    return { file: latestFile, state: JSON.parse(fs.readFileSync(latestFile, "utf-8")) };
  } catch { return null; }
}

// ── Generation 接口（仅用于拉取 provider） ────────────────────────────────────

/** 用最新 gen_id 查询 provider_name（不依赖返回的 model 字段） */
async function fetchProviderFromGeneration(seen_ids: string[]): Promise<string | null> {
  if (!seen_ids?.length) return null;

  const genId = seen_ids[seen_ids.length - 1];
  try {
    const resp = await fetchWithTimeout(
      `https://openrouter.ai/api/v1/generation?id=${genId}`,
      { Authorization: `Bearer ${OPENROUTER_API_KEY}` },
      3000
    );
    if (!resp) return null;

    const gen = JSON.parse(resp)?.data;
    if (!gen) return null;

    return (
      gen.provider_name ||
      gen.provider_responses?.[0]?.provider_name ||
      null
    );
  } catch { return null; }
}

/** 判断是否需要重新查询 provider */
function needsProviderRefresh(state: CostState, currentModelId: string | undefined): boolean {
  // model_id 变了 → 立即刷新
  if (currentModelId !== undefined && state.cached_model_id !== undefined) {
    const a = cleanHudModelId(currentModelId);
    const b = cleanHudModelId(state.cached_model_id);
    if (a !== b) return true;
  }
  // 从未拉取过
  if (!state.last_fetched_at) return true;
  // 超过 TTL
  if (Date.now() - state.last_fetched_at > PROVIDER_CACHE_TTL) return true;

  return false;
}

// ── 余额 ─────────────────────────────────────────────────────────────────────

async function getBalance(): Promise<string | null> {
  try {
    const resp = await fetchWithTimeout(
      "https://openrouter.ai/api/v1/key",
      { Authorization: `Bearer ${OPENROUTER_API_KEY}` },
      3000
    );
    if (!resp) return null;

    const data = JSON.parse(resp);
    const remaining = data.data?.limit_remaining || 0;
    const limit = data.data?.limit || 0;
    if (limit <= 0) return null;

    const pct = Math.round((remaining / limit) * 100);
    const filled = Math.round((pct / 100) * 10);
    const bar = "▓".repeat(filled) + "░".repeat(10 - filled);
    return `💰 ${remaining.toFixed(2)}/${limit.toFixed(0)} ${bar} ${pct}%`;
  } catch { return null; }
}

// ── 主流程 ────────────────────────────────────────────────────────────────────

async function main() {
  const [balance, costResult] = await Promise.all([
    getBalance(),
    Promise.resolve(findLatestCostFile()),
  ]);

  if (!balance) process.exit(0);

  let providerModel = "";

  if (costResult) {
    const { file, state } = costResult;
    const hudModel = getHudModelState();
    const currentModelId = hudModel?.model_id;  // 含 ANSI，用于变化检测
    const cleanModel = currentModelId ? cleanHudModelId(currentModelId) : "";

    // 判断是否需要刷新 provider
    if (needsProviderRefresh(state, currentModelId)) {
      const provider = await fetchProviderFromGeneration(state.seen_ids);

      // 只更新 provider 和缓存元数据，不覆盖 last_model（model 由 hud 来源）
      if (provider) state.last_provider = provider;
      state.cached_model_id = currentModelId ?? state.cached_model_id ?? "";
      state.last_fetched_at = Date.now();

      try { fs.writeFileSync(file, JSON.stringify(state, null, 2), "utf-8"); } catch {}
    }

    // 组合显示：
    //   model → claude-hud 实时值（cleanModel），降级用 state.last_model
    //   provider → state.last_provider（generation 接口拉取）
    const displayModel = cleanModel || (state.last_model ? formatModelLabel(state.last_model) : "");
    const displayProvider = state.last_provider || "";

    if (displayModel && displayProvider) {
      providerModel = `${displayProvider}: ${displayModel}`;
    } else if (displayModel) {
      providerModel = displayModel;
    } else if (displayProvider) {
      providerModel = displayProvider;
    }
  }

  const parts = [providerModel, balance].filter(Boolean);
  console.log(JSON.stringify({ label: parts.join(" | ") }));
}

main().catch(() => process.exit(0));
