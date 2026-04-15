#!/usr/bin/env node

/**
 * OpenRouter StatusLine - 三合一方案
 * 功能：成本 + 余额 + 百分比（无模型前缀）
 *
 * 编译：npx tsc openrouter-combined.ts --target es2020 --module commonjs --outDir .
 * 运行：node openrouter-combined.js < /dev/stdin
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

interface StdinData {
  session_id?: string;
  transcript_path?: string;
  model?: { id?: string; display_name?: string };
  cost?: { total_cost_usd?: number };
  context_window?: { used_percentage?: number };
  [key: string]: any;
}

const OPENROUTER_API_KEY =
  process.env.OPENROUTER_API_KEY || process.env.ANTHROPIC_AUTH_TOKEN;

if (!OPENROUTER_API_KEY) {
  console.log(JSON.stringify({ label: "⚙️ No API Key" }));
  process.exit(0);
}

async function fetchWithCurl(
  url: string,
  headers: Record<string, string> = {}
): Promise<string> {
  return new Promise((resolve) => {
    const curlArgs = ["curl", "-s", "--max-time", "2", url];
    for (const [key, val] of Object.entries(headers)) {
      curlArgs.push("-H", `${key}: ${val}`);
    }

    child_process.execFile(
      "curl",
      curlArgs.slice(1),
      { timeout: 3000 },
      (error, stdout) => {
        if (error) resolve("");
        else resolve(stdout || "");
      }
    );
  });
}

async function getBalance(): Promise<{ amount: string; percentage: number } | null> {
  try {
    const resp = await fetchWithCurl("https://openrouter.ai/api/v1/key", {
      Authorization: `Bearer ${OPENROUTER_API_KEY}`,
    });

    if (!resp) return null;

    const data = JSON.parse(resp);
    const remaining = data.data?.limit_remaining || 0;
    const limit = data.data?.limit || 0;

    if (limit > 0) {
      const percentage = Math.round((remaining / limit) * 100);
      return {
        amount: `${remaining.toFixed(2)}/${limit.toFixed(0)}`,
        percentage,
      };
    }
  } catch (e) {}
  return null;
}

async function getSessionCost(stdinStr: string): Promise<string | null> {
  try {
    const stdinData: StdinData = JSON.parse(stdinStr);
    const sid = stdinData.session_id;
    const tpath = stdinData.transcript_path;

    if (!sid || !tpath) return null;

    const tmpdir = process.env.TMPDIR || "/tmp";
    const sf = path.join(tmpdir, `claude-openrouter-cost-${sid}.json`);

    // 加载状态
    let state: CostState = {
      seen_ids: [],
      total_cost: 0,
      total_cache_discount: 0,
      last_provider: "",
      last_model: "",
    };

    if (fs.existsSync(sf)) {
      try {
        state = JSON.parse(fs.readFileSync(sf, "utf-8"));
      } catch {}
    }

    // 从 transcript 提取 gen-id
    if (fs.existsSync(tpath)) {
      const content = fs.readFileSync(tpath, "utf-8");
      const genIds = [...new Set(
        content.match(/"id":"(gen-[^"]*)"/g)?.map((m: string) => m.replace(/"id":"/, "").replace(/"$/, "")) || []
      )].sort();

      for (const gid of genIds) {
        if (state.seen_ids.includes(gid)) continue;

        try {
          const resp = await fetchWithCurl(
            `https://openrouter.ai/api/v1/generation?id=${gid}`,
            { Authorization: `Bearer ${OPENROUTER_API_KEY}` }
          );

          if (!resp) continue;

          const gen = JSON.parse(resp);
          const genData = gen.data || {};

          state.total_cost += genData.total_cost || 0;
          state.total_cache_discount += genData.cache_discount || 0;
          if (genData.provider_name) state.last_provider = genData.provider_name;
          if (genData.model) state.last_model = genData.model;

          state.seen_ids.push(gid);
        } catch {}
      }
    }

    // 保存状态
    try {
      fs.writeFileSync(sf, JSON.stringify(state, null, 2));
    } catch {}

    // 返回格式化输出
    if (state.last_provider && state.last_model) {
      let model = state.last_model.split("/").pop() || state.last_model;
      model = model.replace(/-\d+$/, "");
      return `${state.last_provider}: ${model} - $${state.total_cost.toFixed(2)}`;
    }
  } catch (e) {}
  return null;
}

async function main() {
  // 读取 stdin
  let stdinStr = "";
  for await (const chunk of process.stdin) {
    stdinStr += chunk.toString();
  }

  let stdinData: StdinData | null = null;
  try {
    stdinData = JSON.parse(stdinStr);
  } catch {}

  const balance = await getBalance();
  const session = stdinData ? await getSessionCost(stdinStr) : null;

  // 组建输出
  let parts: string[] = [];

  // 添加会话成本（不添加模型前缀）
  if (session) {
    parts.push(session);
  }

  // 添加余额（含进度条）
  if (balance) {
    // 生成进度条（10个字符）
    const filled = Math.round((balance.percentage / 100) * 10);
    const empty = 10 - filled;
    let bar = "";
    for (let i = 0; i < filled; i++) bar += "▓";
    for (let i = 0; i < empty; i++) bar += "░";

    parts.push(`💰 ${balance.amount} ${bar} ${balance.percentage}%`);
  }

  const output = parts.join(" | ");

  // 输出 JSON
  if (output) {
    console.log(JSON.stringify({ label: output }));
  } else {
    console.log(JSON.stringify({ label: "💰 Loading..." }));
  }
}

main().catch(() => {
  console.log(JSON.stringify({ label: "💰 Error" }));
});
