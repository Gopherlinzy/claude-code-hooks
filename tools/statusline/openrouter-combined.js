#!/usr/bin/env node
"use strict";
/**
 * OpenRouter StatusLine - 三合一方案
 * 功能：余额 + 模型 + 成本追踪
 *
 * 编译：npx tsc openrouter-combined.ts --target es2020 --module commonjs --outDir .
 * 运行：node openrouter-combined.js < /dev/stdin
 */
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
const fs = __importStar(require("fs"));
const path = __importStar(require("path"));
const child_process = __importStar(require("child_process"));
const OPENROUTER_API_KEY = process.env.OPENROUTER_API_KEY || process.env.ANTHROPIC_AUTH_TOKEN;
if (!OPENROUTER_API_KEY) {
    console.log(JSON.stringify({ label: "⚙️ No API Key" }));
    process.exit(0);
}
async function fetchWithCurl(url, headers = {}) {
    return new Promise((resolve) => {
        const curlArgs = ["curl", "-s", "--max-time", "2", url];
        for (const [key, val] of Object.entries(headers)) {
            curlArgs.push("-H", `${key}: ${val}`);
        }
        child_process.execFile("curl", curlArgs.slice(1), { timeout: 3000 }, (error, stdout) => {
            if (error)
                resolve("");
            else
                resolve(stdout || "");
        });
    });
}
async function getBalance() {
    try {
        const resp = await fetchWithCurl("https://openrouter.ai/api/v1/key", {
            Authorization: `Bearer ${OPENROUTER_API_KEY}`,
        });
        if (!resp)
            return null;
        const data = JSON.parse(resp);
        const remaining = data.data?.limit_remaining || 0;
        const limit = data.data?.limit || 0;
        if (limit > 0) {
            return `${remaining.toFixed(0)}/${limit.toFixed(0)}`;
        }
    }
    catch (e) { }
    return null;
}
async function getSessionCost(stdinStr) {
    try {
        const stdinData = JSON.parse(stdinStr);
        const sid = stdinData.session_id;
        const tpath = stdinData.transcript_path;
        if (!sid || !tpath)
            return null;
        const tmpdir = process.env.TMPDIR || "/tmp";
        const sf = path.join(tmpdir, `claude-openrouter-cost-${sid}.json`);
        // 加载状态
        let state = {
            seen_ids: [],
            total_cost: 0,
            total_cache_discount: 0,
            last_provider: "",
            last_model: "",
        };
        if (fs.existsSync(sf)) {
            try {
                state = JSON.parse(fs.readFileSync(sf, "utf-8"));
            }
            catch { }
        }
        // 从 transcript 提取 gen-id
        if (fs.existsSync(tpath)) {
            const content = fs.readFileSync(tpath, "utf-8");
            const genIds = [...new Set(content.match(/"id":"(gen-[^"]*)"/g)?.map((m) => m.replace(/"id":"/, "").replace(/"$/, "")) || [])].sort();
            for (const gid of genIds) {
                if (state.seen_ids.includes(gid))
                    continue;
                try {
                    const resp = await fetchWithCurl(`https://openrouter.ai/api/v1/generation?id=${gid}`, { Authorization: `Bearer ${OPENROUTER_API_KEY}` });
                    if (!resp)
                        continue;
                    const gen = JSON.parse(resp);
                    const genData = gen.data || {};
                    state.total_cost += genData.total_cost || 0;
                    state.total_cache_discount += genData.cache_discount || 0;
                    if (genData.provider_name)
                        state.last_provider = genData.provider_name;
                    if (genData.model)
                        state.last_model = genData.model;
                    state.seen_ids.push(gid);
                }
                catch { }
            }
        }
        // 保存状态
        try {
            fs.writeFileSync(sf, JSON.stringify(state, null, 2));
        }
        catch { }
        // 返回格式化输出
        if (state.last_provider && state.last_model) {
            let model = state.last_model.split("/").pop() || state.last_model;
            model = model.replace(/-\d+$/, ""); // 去掉版本号
            return `${state.last_provider}: ${model} - $${state.total_cost.toFixed(4)} - cache: $${state.total_cache_discount.toFixed(2)}`;
        }
    }
    catch (e) { }
    return null;
}
async function main() {
    // 读取 stdin
    let stdinData = "";
    for await (const chunk of process.stdin) {
        stdinData += chunk.toString();
    }
    const balance = await getBalance();
    const session = stdinData ? await getSessionCost(stdinData) : null;
    // 组建输出
    let output = "";
    if (session) {
        output = session;
        if (balance)
            output = `${output} | 💰 ${balance}`;
    }
    else if (balance) {
        output = `💰 ${balance}`;
    }
    // 始终输出 JSON（--extra-cmd 需要 JSON 格式）
    if (output) {
        console.log(JSON.stringify({ label: output }));
    }
    else {
        console.log(JSON.stringify({ label: "💰 Loading..." }));
    }
}
main().catch(() => {
    console.log(JSON.stringify({ label: "💰 Error" }));
});
