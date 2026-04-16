#!/usr/bin/env node

/**
 * OpenRouter StatusLine for --extra-cmd
 * 显示 provider + model（从 generation 接口实时拉取）+ 余额
 *
 * 刷新策略：
 *   - model_id 变化（/model 切换）→ 立即调 generation 接口
 *   - 超过 TTL（60s）→ 重新调 generation 接口
 *   - 其余情况 → 用缓存
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
  // 新增：用于变化检测和缓存策略
  cached_model_id?: string;      // 上次拉取时 claude-hud 的 model_id（含 OpenRouter 格式）
  last_fetched_at?: number;      // 上次调 generation 接口的时间戳
}

interface ModelState {
  model_id: string;
  display_name: string;
  updated_at: number;
}

interface GenerationData {
  provider_name: string;
  model: string;
}

// ── 常量 ─────────────────────────────────────────────────────────────────────

const OPENROUTER_API_KEY =
  process.env.OPENROUTER_API_KEY || process.env.ANTHROPIC_AUTH_TOKEN;

/** generation 接口缓存有效期（ms） */
const PROVIDER_CACHE_TTL = 60_000;

/** claude-hud-current-model.json 有效期（ms） */
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

/** 将 OpenRouter model_id 格式化为短名称，去掉日期版本号 */
function formatModelLabel(modelId: string): string {
  const part = modelId.split("/").pop() || modelId;
  return part.replace(/-\d{8}$/, "").replace(/-\d+$/, "");
}

// ── 核心逻辑 ─────────────────────────────────────────────────────────────────

/** 读取 claude-hud 写入的当前模型文件 */
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

/** 找到最近修改的 session cost 缓存文件 */
function findLatestCostFile(): { file: string; state: CostState } | null {
  const dirs = [
    process.env.TMPDIR,
    process.env.TMP,
    process.env.TEMP,
    os.tmpdir(),
    "/tmp",
    "/var/tmp",
  ].filter(Boolean);

  let latestFile = "";
  let latestTime = 0;

  for (const dir of dirs) {
    try {
      const entries = fs.readdirSync(dir!);
      for (const entry of entries) {
        if (!entry.startsWith("claude-openrouter-cost-") || !entry.endsWith(".json")) continue;
        const full = path.join(dir!, entry);
        const stat = fs.statSync(full);
        if (stat.mtimeMs > latestTime) {
          latestTime = stat.mtimeMs;
          latestFile = full;
        }
      }
    } catch {}
  }

  if (!latestFile) return null;

  try {
    const state: CostState = JSON.parse(fs.readFileSync(latestFile, "utf-8"));
    return { file: latestFile, state };
  } catch {
    return null;
  }
}

/** 调 OpenRouter generation 接口，取最新一次的 provider_name + model */
async function fetchLatestGeneration(seen_ids: string[]): Promise<GenerationData | null> {
  if (!seen_ids || seen_ids.length === 0) return null;

  // 取最后一个 gen id（最近的一次 generation）
  const genId = seen_ids[seen_ids.length - 1];

  try {
    const resp = await fetchWithTimeout(
      `https://openrouter.ai/api/v1/generation?id=${genId}`,
      { Authorization: `Bearer ${OPENROUTER_API_KEY}` },
      3000
    );
    if (!resp) return null;

    const data = JSON.parse(resp);
    const gen = data?.data;
    if (!gen) return null;

    // provider_name 直接在顶层，也在 provider_responses[0].provider_name
    const provider =
      gen.provider_name ||
      gen.provider_responses?.[0]?.provider_name ||
      "";
    const model = gen.model || "";

    if (!provider && !model) return null;
    return { provider_name: provider, model };
  } catch {
    return null;
  }
}

/** 判断是否需要重新调 generation 接口 */
function needsRefresh(state: CostState, currentModelId: string | undefined): boolean {
  // 1. model_id 变了（/model 切换）
  if (currentModelId && state.cached_model_id !== undefined) {
    // claude-hud model_id 可能含 ANSI 污染，做宽松比较（截取干净部分）
    const cleanCurrent = currentModelId.replace(/\x1B\[[0-9;]*m/g, "").trim();
    const cleanCached = state.cached_model_id.replace(/\x1B\[[0-9;]*m/g, "").trim();
    if (cleanCurrent !== cleanCached) return true;
  }

  // 2. 从未拉取过
  if (!state.last_fetched_at) return true;

  // 3. 超过 TTL
  if (Date.now() - state.last_fetched_at > PROVIDER_CACHE_TTL) return true;

  return false;
}

/** 获取余额信息（实时） */
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

    if (limit > 0) {
      const pct = Math.round((remaining / limit) * 100);
      const filled = Math.round((pct / 100) * 10);
      const bar = "▓".repeat(filled) + "░".repeat(10 - filled);
      return `💰 ${remaining.toFixed(2)}/${limit.toFixed(0)} ${bar} ${pct}%`;
    }
  } catch {}
  return null;
}

// ── 主流程 ────────────────────────────────────────────────────────────────────

async function main() {
  // 余额和 session 数据并行拉取，减少总耗时
  const [balance, costResult] = await Promise.all([
    getBalance(),
    (async () => findLatestCostFile())(),
  ]);

  if (!balance) process.exit(0);

  // 拼装 provider: model 标签
  let providerModel = "";

  if (costResult) {
    const { file, state } = costResult;
    const hudModel = getHudModelState();
    const currentModelId = hudModel?.model_id;

    if (needsRefresh(state, currentModelId)) {
      // 调 generation 接口拉取最新 provider + model
      const gen = await fetchLatestGeneration(state.seen_ids);

      if (gen) {
        state.last_provider = gen.provider_name;
        state.last_model = gen.model;
        state.cached_model_id = currentModelId ?? state.cached_model_id ?? "";
        state.last_fetched_at = Date.now();

        // 写回缓存
        try {
          fs.writeFileSync(file, JSON.stringify(state, null, 2), "utf-8");
        } catch {}
      }
    }

    // 组合输出
    const provider = state.last_provider || "";
    const model = state.last_model ? formatModelLabel(state.last_model) : "";
    if (provider && model) providerModel = `${provider}: ${model}`;
    else if (model) providerModel = model;
    else if (provider) providerModel = provider;
  }

  const parts = [providerModel, balance].filter(Boolean);
  console.log(JSON.stringify({ label: parts.join(" | ") }));
}

main().catch(() => process.exit(0));
