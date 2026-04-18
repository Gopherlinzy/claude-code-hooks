#!/usr/bin/env node
var __create = Object.create;
var __defProp = Object.defineProperty;
var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
var __getOwnPropNames = Object.getOwnPropertyNames;
var __getProtoOf = Object.getPrototypeOf;
var __hasOwnProp = Object.prototype.hasOwnProperty;
var __copyProps = (to, from, except, desc) => {
  if (from && typeof from === "object" || typeof from === "function") {
    for (let key of __getOwnPropNames(from))
      if (!__hasOwnProp.call(to, key) && key !== except)
        __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
  }
  return to;
};
var __toESM = (mod, isNodeMode, target) => (target = mod != null ? __create(__getProtoOf(mod)) : {}, __copyProps(
  // If the importer is in node compatibility mode or this is not an ESM
  // file that has been converted to a CommonJS file using a Babel-
  // compatible transform (i.e. "__esModule" has not been set), then set
  // "default" to the CommonJS "module.exports" for node compatibility.
  isNodeMode || !mod || !mod.__esModule ? __defProp(target, "default", { value: mod, enumerable: true }) : target,
  mod
));

// openrouter-statusline.ts
var fs = __toESM(require("fs"));
var path = __toESM(require("path"));
var child_process = __toESM(require("child_process"));
var os = __toESM(require("os"));
// 动态读取 token：先尝试从最新的 settings.json 中读取
function getLatestToken() {
  const settingsPath = process.env.CLAUDE_CONFIG_DIR ? path.join(process.env.CLAUDE_CONFIG_DIR, "settings.json") : path.join(os.homedir(), ".claude", "settings.json");
  try {
    if (fs.existsSync(settingsPath)) {
      const settings = JSON.parse(fs.readFileSync(settingsPath, "utf-8"));
      if (settings.env && settings.env.ANTHROPIC_AUTH_TOKEN) {
        return settings.env.ANTHROPIC_AUTH_TOKEN;
      }
    }
  } catch {}
  // Fallback 到环境变量
  return process.env.OPENROUTER_API_KEY || process.env.ANTHROPIC_AUTH_TOKEN;
}

var OPENROUTER_API_KEY = getLatestToken();
var PROVIDER_CACHE_TTL = 6e4;
var HUD_MODEL_TTL = 12e4;
if (!OPENROUTER_API_KEY) {
  process.exit(0);
}

// ===== Token 变更检测：自动清除旧缓存 =====
(function() {
  const tmpDir = process.env.TMPDIR || os.tmpdir();
  const tokenHashFile = path.join(tmpDir, "claude-openrouter-token-hash.json");
  const tokenHash = OPENROUTER_API_KEY.substring(0, 16).toLowerCase();

  let lastHash = null;
  try {
    if (fs.existsSync(tokenHashFile)) {
      const cached = JSON.parse(fs.readFileSync(tokenHashFile, "utf-8"));
      lastHash = cached.hash;
    }
  } catch {}

  if (lastHash && lastHash !== tokenHash) {
    try {
      for (const file of fs.readdirSync(tmpDir)) {
        // token 变更时只清 provider 缓存，保留 cost 文件（含 seen_ids/last_model）
        if ((file.startsWith("claude-openrouter-") || file.startsWith("claude-hud-")) && !file.includes("token-hash") && !file.startsWith("claude-openrouter-cost-")) {
          fs.unlinkSync(path.join(tmpDir, file));
        }
      }
      // 重置 cost 文件中的 provider 缓存字段，避免显示旧 token 的 provider
      for (const file of fs.readdirSync(tmpDir)) {
        if (!file.startsWith("claude-openrouter-cost-") || !file.endsWith(".json")) continue;
        const full = path.join(tmpDir, file);
        try {
          const state = JSON.parse(fs.readFileSync(full, "utf-8"));
          state.last_provider = "";
          state.last_fetched_at = 0;
          fs.writeFileSync(full, JSON.stringify(state, null, 2), "utf-8");
        } catch {}
      }
    } catch {}
  }

  try {
    fs.writeFileSync(tokenHashFile, JSON.stringify({ hash: tokenHash, ts: Date.now() }));
  } catch {}
})();
async function fetchWithTimeout(url, headers = {}, timeoutMs = 3e3) {
  return new Promise((resolve) => {
    const curlArgs = ["-s", "--max-time", String(Math.ceil(timeoutMs / 1e3)), url];
    for (const [key, val] of Object.entries(headers)) {
      curlArgs.push("-H", `${key}: ${val}`);
    }
    const timeout = setTimeout(() => {
      try {
        process.kill(child.pid);
      } catch {
      }
      resolve("");
    }, timeoutMs);
    const child = child_process.spawn("curl", curlArgs);
    let stdout = "";
    child.stdout?.on("data", (d) => {
      stdout += d.toString();
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
function cleanHudModelId(modelId) {
  return modelId.replace(/\x1B\[[0-9;]*m/g, "").replace(/\[\d+m\]/g, "").replace(/\[[\d;]+m/g, "").trim();
}
function formatModelLabel(modelId) {
  const part = modelId.split("/").pop() || modelId;
  return part.replace(/-\d{8}$/, "").replace(/-\d+$/, "");
}
function getHudModelState() {
  const dirs = [process.env.TMPDIR, os.tmpdir(), "/tmp", "/var/tmp"].filter(Boolean);
  for (const dir of dirs) {
    try {
      const f = path.join(dir, "claude-hud-current-model.json");
      if (!fs.existsSync(f)) continue;
      const state = JSON.parse(fs.readFileSync(f, "utf-8"));
      if (Date.now() - state.updated_at < HUD_MODEL_TTL) return state;
    } catch {
    }
  }
  return null;
}
function findLatestCostFile() {
  const dirs = [
    process.env.TMPDIR,
    process.env.TMP,
    process.env.TEMP,
    os.tmpdir(),
    "/tmp",
    "/var/tmp"
  ].filter(Boolean);
  let latestFile = "";
  let latestTime = 0;
  for (const dir of dirs) {
    try {
      for (const entry of fs.readdirSync(dir)) {
        if (!entry.startsWith("claude-openrouter-cost-") || !entry.endsWith(".json")) continue;
        const full = path.join(dir, entry);
        const mtime = fs.statSync(full).mtimeMs;
        if (mtime > latestTime) {
          latestTime = mtime;
          latestFile = full;
        }
      }
    } catch {
    }
  }
  if (!latestFile) return null;
  try {
    return { file: latestFile, state: JSON.parse(fs.readFileSync(latestFile, "utf-8")) };
  } catch {
    return null;
  }
}
async function fetchProviderFromGeneration(seen_ids) {
  if (!seen_ids?.length) return null;
  const genId = seen_ids[seen_ids.length - 1];
  try {
    const resp = await fetchWithTimeout(
      `https://openrouter.ai/api/v1/generation?id=${genId}`,
      { Authorization: `Bearer ${OPENROUTER_API_KEY}` },
      3e3
    );
    if (!resp) return null;
    const gen = JSON.parse(resp)?.data;
    if (!gen) return null;
    return gen.provider_name || gen.provider_responses?.[0]?.provider_name || null;
  } catch {
    return null;
  }
}
function needsProviderRefresh(state, currentModelId) {
  if (currentModelId !== void 0 && state.cached_model_id !== void 0) {
    const a = cleanHudModelId(currentModelId);
    const b = cleanHudModelId(state.cached_model_id);
    if (a !== b) return true;
  }
  if (!state.last_fetched_at) return true;
  if (Date.now() - state.last_fetched_at > PROVIDER_CACHE_TTL) return true;
  return false;
}
async function getBalance() {
  try {
    const resp = await fetchWithTimeout(
      "https://openrouter.ai/api/v1/key",
      { Authorization: `Bearer ${OPENROUTER_API_KEY}` },
      3e3
    );
    if (!resp) return null;
    const data = JSON.parse(resp);
    const remaining = data.data?.limit_remaining || 0;
    const limit = data.data?.limit || 0;
    if (limit <= 0) return null;
    const pct = Math.round(remaining / limit * 100);
    const filled = Math.round(pct / 100 * 10);
    const bar = "\u2593".repeat(filled) + "\u2591".repeat(10 - filled);
    return `\u{1F4B0} ${remaining.toFixed(2)}/${limit.toFixed(0)} ${bar} ${pct}%`;
  } catch {
    return null;
  }
}
async function main() {
  const [balance, costResult] = await Promise.all([
    getBalance(),
    Promise.resolve(findLatestCostFile())
  ]);
  if (!balance) process.exit(0);
  let providerModel = "";
  if (costResult) {
    const { file, state } = costResult;
    const hudModel = getHudModelState();
    const currentModelId = hudModel?.model_id;
    const cleanModel = currentModelId ? cleanHudModelId(currentModelId) : "";
    if (needsProviderRefresh(state, currentModelId)) {
      const provider = await fetchProviderFromGeneration(state.seen_ids);
      if (provider) state.last_provider = provider;
      state.cached_model_id = currentModelId ?? state.cached_model_id ?? "";
      state.last_fetched_at = Date.now();
      try {
        fs.writeFileSync(file, JSON.stringify(state, null, 2), "utf-8");
      } catch {
      }
    }
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
