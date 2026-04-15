#!/usr/bin/env node

/**
 * OpenRouter StatusLine - 三合一方案
 * 功能：余额 + 模型 + 成本追踪
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

async function getBalance(): Promise<string | null> {
  try {
    const resp = await fetchWithCurl("https://openrouter.ai/api/v1/key", {
      Authorization: `Bearer ${OPENROUTER_API_KEY}`,
    });

    if (!resp) return null;

    const data = JSON.parse(resp);
    const remaining = data.data?.limit_remaining || 0;
    const limit = data.data?.limit || 0;

    if (limit > 0) {
      return `${remaining.toFixed(0)}/${limit.toFixed(0)}`;
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
      model = model.replace(/-\d+$/, ""); // 去掉版本号
      return `${state.last_provider}: ${model} - $${state.total_cost.toFixed(4)} - cache: $${state.total_cache_discount.toFixed(2)}`;
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

  // 组建输出（优化长度）
  let parts: string[] = [];

  // 优先添加模型信息（从 stdin）
  if (stdinData?.model?.display_name) {
    parts.push(`[${stdinData.model.display_name}]`);
  }

  // 添加会话成本（简化格式）
  if (session) {
    // 简化成本显示：只保留 Provider 和 cost，去掉 cache 折扣
    const shortSession = session
      .replace(/ - cache: \$[\d.]+/g, "") // 去掉 cache 部分
      .substring(0, 40); // 限制长度
    parts.push(shortSession);
  }

  // 添加余额
  if (balance) {
    parts.push(`💰 ${balance}`);
  }

  const output = parts.join(" | ");

  // 始终输出 JSON 格式
  if (output) {
    console.log(JSON.stringify({ label: output }));
  } else {
    console.log(JSON.stringify({ label: "💰 Loading..." }));
  }
}

main().catch(() => {
  console.log(JSON.stringify({ label: "💰 Error" }));
});
