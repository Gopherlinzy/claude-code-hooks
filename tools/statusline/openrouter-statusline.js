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
            const percentage = Math.round((remaining / limit) * 100);
            // 生成进度条（10字符）
            const filled = Math.round((percentage / 100) * 10);
            const empty = 10 - filled;
            let bar = "";
            for (let i = 0; i < filled; i++)
                bar += "▓";
            for (let i = 0; i < empty; i++)
                bar += "░";
            return `💰 ${remaining.toFixed(2)}/${limit.toFixed(0)} ${bar} ${percentage}%`;
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
        if (state.total_cost > 0) {
            return `$${state.total_cost.toFixed(2)}`;
        }
    }
    catch (e) { }
    return null;
}
/** 从 claude-hud 写入的临时文件获取当前真实模型（/model 切换后立即更新） */
function getCurrentModel() {
    try {
        const possiblePaths = [process.env.TMPDIR, "/tmp", "/var/tmp"].filter(Boolean);
        for (const dir of possiblePaths) {
            const f = path.join(dir, "claude-hud-current-model.json");
            if (fs.existsSync(f)) {
                const state = JSON.parse(fs.readFileSync(f, "utf-8"));
                // 文件超过 60 秒认为过期
                if (Date.now() - state.updated_at < 60_000)
                    return state;
            }
        }
    }
    catch (e) { }
    return null;
}
/** 将 model_id 格式化为可读名称 */
function formatModelLabel(modelId) {
    const part = modelId.split("/").pop() || modelId;
    return part.replace(/-\d{8}$/, "").replace(/-\d+$/, "");
}
async function tryGetSessionData() {
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
        let latestFile = null;
        let latestTime = 0;
        for (const tmpdir of possibleTmpdirs) {
            try {
                const files = execSync(`find ${tmpdir} -maxdepth 1 -name 'claude-openrouter-cost-*.json' -type f 2>/dev/null | head -50`, {
                    encoding: "utf-8",
                }).trim().split("\n").filter((f) => f);
                for (const file of files) {
                    const stat = fs.statSync(file);
                    if (stat.mtimeMs > latestTime) {
                        latestTime = stat.mtimeMs;
                        latestFile = file;
                    }
                }
            }
            catch (e) { }
        }
        if (!latestFile || !fs.existsSync(latestFile))
            return null;
        const state = JSON.parse(fs.readFileSync(latestFile, "utf-8"));
        if (state.total_cost > 0) {
            // 优先使用 claude-hud 写入的当前模型（实时感知 /model 切换）
            const currentModel = getCurrentModel();
            let providerModel;
            if (currentModel?.model_id) {
                // 模型名用实时的，provider 仍从 generation 缓存取
                const modelLabel = formatModelLabel(currentModel.model_id);
                providerModel = state.last_provider
                    ? `${state.last_provider}: ${modelLabel}`
                    : modelLabel;
            }
            else if (state.last_provider && state.last_model) {
                // 降级：两者都用缓存（切换模型后下一次 generation 才更新）
                const model = formatModelLabel(state.last_model);
                providerModel = `${state.last_provider}: ${model}`;
            }
            else {
                providerModel = "";
            }
            const sessionCost = providerModel
                ? `${providerModel} - $${state.total_cost.toFixed(2)}`
                : `$${state.total_cost.toFixed(2)}`;
            return { sessionCost };
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
    // 尝试获取会话成本，用于显示 provider 和模型信息
    const sessionData = await tryGetSessionData();
    const modelInfo = sessionData ? sessionData.sessionCost.split(" - ")[0] : "";

    // 输出格式：provider: model | 余额（只显示实时的）
    const parts = [modelInfo, balance].filter(Boolean);
    const output = parts.join(" | ");
    // 输出为 JSON（claude-hud --extra-cmd 需要）
    console.log(JSON.stringify({ label: output }));
}
main().catch(() => {
    process.exit(0);
});
