#!/usr/bin/env node

/**
 * OpenRouter StatusLine for --extra-cmd
 * 只显示成本 + 余额信息，不显示模型（由 claude-hud 显示）
 * 用于 claude-hud 的 --extra-cmd 参数
 */

import * as fs from "fs";
import * as path from "path";
import * as child_process from "child_process";

interface CostState {
  seen_ids: string[];
  total_cost: number;
  total_cache_discount: number;
  last_provider: string;
  last_model: string;
}

interface ModelState {
  model_id: string;
  display_name: string;
  updated_at: number;
}

const OPENROUTER_API_KEY =
  process.env.OPENROUTER_API_KEY || process.env.ANTHROPIC_AUTH_TOKEN;

if (!OPENROUTER_API_KEY) {
  // --extra-cmd 模式：无 API Key 时直接退出（不输出，让 claude-hud 输出）
  process.exit(0);
}

async function fetchWithTimeout(
  url: string,
  headers: Record<string, string> = {},
  timeoutMs = 2000
): Promise<string> {
  return new Promise((resolve) => {
    const curlArgs = ["curl", "-s", "--max-time", "2", url];
    for (const [key, val] of Object.entries(headers)) {
      curlArgs.push("-H", `${key}: ${val}`);
    }

    const timeout = setTimeout(() => {
      process.kill(child.pid!);
      resolve("");
    }, timeoutMs);

    const child = child_process.spawn("curl", curlArgs.slice(1));
    let stdout = "";

    child.stdout?.on("data", (data) => {
      stdout += data.toString();
    });

    child.on("close", () => {
      clearTimeout(timeout);
      resolve(stdout);
    });

    child.on("error", () => {
      clearTimeout(timeout);
      resolve("");
    });
  });
}

async function getBalance(): Promise<string | null> {
  try {
    const resp = await fetchWithTimeout("https://openrouter.ai/api/v1/key", {
      Authorization: `Bearer ${OPENROUTER_API_KEY}`,
    });

    if (!resp) return null;

    const data = JSON.parse(resp);
    const remaining = data.data?.limit_remaining || 0;
    const limit = data.data?.limit || 0;

    if (limit > 0) {
      const percentage = Math.round((remaining / limit) * 100);
      // 生成进度条（10字符）
      const filled = Math.round((percentage / 100) * 10);
      const empty = 10 - filled;
      let bar = "";
      for (let i = 0; i < filled; i++) bar += "▓";
      for (let i = 0; i < empty; i++) bar += "░";

      return `💰 ${remaining.toFixed(2)}/${limit.toFixed(0)} ${bar} ${percentage}%`;
    }
  } catch (e) {}
  return null;
}

async function getSessionCostFromFile(sessionId: string): Promise<string | null> {
  try {
    const tmpdir = process.env.TMPDIR || "/tmp";
    const sf = path.join(tmpdir, `claude-openrouter-cost-${sessionId}.json`);

    if (!fs.existsSync(sf)) return null;

    const state: CostState = JSON.parse(fs.readFileSync(sf, "utf-8"));

    if (state.total_cost > 0) {
      return `💸 $${state.total_cost.toFixed(2)}`;
    }
  } catch (e) {}
  return null;
}

/** 从 claude-hud 写入的临时文件获取当前真实模型（/model 切换后立即更新） */
function getCurrentModel(): ModelState | null {
  try {
    // macOS: os.tmpdir() 返回 /var/folders/.../T，但 index.js 用的是 node:os tmpdir()
    const possiblePaths = [
      process.env.TMPDIR,
      "/tmp",
      "/var/tmp",
    ].filter(Boolean);

    for (const dir of possiblePaths) {
      const f = path.join(dir!, "claude-hud-current-model.json");
      if (fs.existsSync(f)) {
        const state: ModelState = JSON.parse(fs.readFileSync(f, "utf-8"));
        // 文件超过 60 秒认为过期
        if (Date.now() - state.updated_at < 60_000) return state;
      }
    }
  } catch (e) {}
  return null;
}

/** 将 model_id 格式化为可读名称（与 cache 中的 last_model 格式一致） */
function formatModelLabel(modelId: string): string {
  // OpenRouter vendor/model 格式
  const part = modelId.split("/").pop() || modelId;
  // 去掉末尾的日期版本号（如 -20251001）
  return part.replace(/-\d{8}$/, "").replace(/-\d+$/, "");
}

async function tryGetSessionData(): Promise<{ sessionCost?: string } | null> {
  // 尝试从最近的缓存文件获取会话数据
  try {
    const { execSync } = require("child_process");

    // 尝试多个 TMPDIR 位置
    const possibleTmpdirs = [
      process.env.TMPDIR,
      process.env.TMP,
      process.env.TEMP,
      "/tmp",
      "/var/tmp",
    ].filter(Boolean);

    let latestFile: string | null = null;
    let latestTime = 0;

    for (const tmpdir of possibleTmpdirs) {
      try {
        const files = execSync(`find ${tmpdir} -maxdepth 1 -name 'claude-openrouter-cost-*.json' -type f 2>/dev/null | head -50`, {
          encoding: "utf-8",
        }).trim().split("\n").filter((f: string) => f);

        for (const file of files) {
          const stat = fs.statSync(file);
          if (stat.mtimeMs > latestTime) {
            latestTime = stat.mtimeMs;
            latestFile = file;
          }
        }
      } catch (e) {}
    }

    if (!latestFile || !fs.existsSync(latestFile)) return null;

    const state: CostState = JSON.parse(fs.readFileSync(latestFile, "utf-8"));

    if (state.total_cost > 0) {
      // 优先使用 claude-hud 写入的当前模型（实时感知 /model 切换）
      const currentModel = getCurrentModel();
      let providerModel: string;
      if (currentModel?.model_id) {
        // 模型名用实时的，provider 仍从 generation 缓存取
        const modelLabel = formatModelLabel(currentModel.model_id);
        providerModel = state.last_provider
          ? `${state.last_provider}: ${modelLabel}`
          : modelLabel;
      } else if (state.last_provider && state.last_model) {
        // 降级：两者都用缓存（切换模型后下一次 generation 才更新）
        const model = formatModelLabel(state.last_model);
        providerModel = `${state.last_provider}: ${model}`;
      } else {
        providerModel = "";
      }
      const sessionCost = providerModel
        ? `${providerModel} - $${state.total_cost.toFixed(2)}`
        : `$${state.total_cost.toFixed(2)}`;
      return { sessionCost };
    }
  } catch (e) {}
  return null;
}

async function main() {
  const balance = await getBalance();
  if (!balance) {
    process.exit(0);
  }

  // 尝试获取会话成本
  const sessionData = await tryGetSessionData();
  const sessionCost = sessionData?.sessionCost || "";

  // 输出格式：成本 | 余额（模型由 claude-hud 显示，这里不重复）
  const parts = [sessionCost, balance].filter(Boolean);
  const output = parts.join(" | ");

  // 输出为 JSON（claude-hud --extra-cmd 需要）
  console.log(JSON.stringify({ label: output.trim() }));
}

main().catch(() => {
  process.exit(0);
});
