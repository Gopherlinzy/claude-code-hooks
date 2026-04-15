#!/usr/bin/env node
"use strict";
/**
 * OpenRouter StatusLine for --extra-cmd
 * 只显示成本 + 余额信息，不显示模型（由 claude-hud 显示）
 * 用于 claude-hud 的 --extra-cmd 参数
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
    // --extra-cmd 模式：无 API Key 时直接退出（不输出，让 claude-hud 输出）
    process.exit(0);
}
async function fetchWithTimeout(url, headers = {}, timeoutMs = 2000) {
    return new Promise((resolve) => {
        const curlArgs = ["curl", "-s", "--max-time", "2", url];
        for (const [key, val] of Object.entries(headers)) {
            curlArgs.push("-H", `${key}: ${val}`);
        }
        const timeout = setTimeout(() => {
            process.kill(child.pid);
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
async function getBalance() {
    try {
        const resp = await fetchWithTimeout("https://openrouter.ai/api/v1/key", {
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
async function getSessionCostFromFile(sessionId) {
    try {
        const tmpdir = process.env.TMPDIR || "/tmp";
        const sf = path.join(tmpdir, `claude-openrouter-cost-${sessionId}.json`);
        if (!fs.existsSync(sf))
            return null;
        const state = JSON.parse(fs.readFileSync(sf, "utf-8"));
        if (state.last_provider && state.last_model) {
            let model = state.last_model.split("/").pop() || state.last_model;
            model = model.replace(/-\d+$/, "");
            return `${state.last_provider}: ${model} - $${state.total_cost.toFixed(2)} | `;
        }
    }
    catch (e) { }
    return null;
}
async function tryGetSessionData() {
    // 尝试从最近的 Claude Code 会话获取数据
    // 这是 --extra-cmd 模式的备选方案
    try {
        const claudeDir = path.join(process.env.HOME || "", ".claude", "projects");
        if (!fs.existsSync(claudeDir))
            return null;
        // 获取最近修改的会话文件夹
        const projects = fs.readdirSync(claudeDir);
        let latestSession = { time: 0, id: "" };
        for (const proj of projects) {
            const projPath = path.join(claudeDir, proj);
            const stat = fs.statSync(projPath);
            if (stat.mtimeMs > latestSession.time) {
                latestSession = { time: stat.mtimeMs, id: proj };
            }
        }
        if (latestSession.id) {
            const sessionCost = await getSessionCostFromFile(latestSession.id);
            return { sessionId: latestSession.id, sessionCost };
        }
    }
    catch (e) { }
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
    // 输出格式：成本 | 余额
    // 不输出模型信息（那是 claude-hud 的职责）
    const output = `${sessionCost}💰 ${balance}`;
    // 输出为 JSON（claude-hud --extra-cmd 需要）
    console.log(JSON.stringify({ label: output.trim() }));
}
main().catch(() => {
    process.exit(0);
});
