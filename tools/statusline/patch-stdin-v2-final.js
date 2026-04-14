#!/usr/bin/env node
/**
 * claude-hud stdin.js 补丁 v2 - 改进版
 * 支持环变量和更准确的版本号解析
 */

const fs = require('fs');
const path = require('path');
const os = require('os');

const CLAUDE_CONFIG_DIR = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
const PLUGIN_DIR = path.join(CLAUDE_CONFIG_DIR, 'plugins/cache/claude-hud/claude-hud');

function findStdinJs() {
    if (!fs.existsSync(PLUGIN_DIR)) {
        console.error(`❌ claude-hud plugin not found at ${PLUGIN_DIR}`);
        process.exit(1);
    }

    let stdinJsFile = null;
    const versions = [];

    try {
        const dirs = fs.readdirSync(PLUGIN_DIR);
        dirs.forEach(dir => {
            const distPath = path.join(PLUGIN_DIR, dir, 'dist/stdin.js');
            if (fs.existsSync(distPath)) {
                versions.push(distPath);
            }
        });
    } catch (e) {
        console.error(`❌ Error reading plugin directory: ${e.message}`);
        process.exit(1);
    }

    if (versions.length === 0) {
        console.error('❌ stdin.js not found in claude-hud');
        process.exit(1);
    }

    stdinJsFile = versions.sort().pop();
    console.log(`✅ Found: ${stdinJsFile}`);
    return stdinJsFile;
}

function isPatched(content) {
    return content.includes('// PATCH v2: from env or improved parsing');
}

function findFunctionRange(content, funcName) {
    const idx = content.indexOf('export function ' + funcName);
    if (idx === -1) return null;

    let braceCount = 0;
    let inFunction = false;
    let endIdx = idx;
    for (let i = idx; i < content.length; i++) {
        if (content[i] === '{') {
            inFunction = true;
            braceCount++;
        } else if (content[i] === '}' && inFunction) {
            braceCount--;
            if (braceCount === 0) {
                endIdx = i + 1;
                break;
            }
        }
    }
    return { startIdx: idx, endIdx: endIdx };
}

function applyPatch(stdinJsFile) {
    console.log('📝 Reading stdin.js...');
    let content = fs.readFileSync(stdinJsFile, 'utf-8');

    if (isPatched(content)) {
        console.log('⚠️  Already patched with v2');
        return;
    }

    const backupFile = `${stdinJsFile}.backup.v2.${Date.now()}`;
    fs.copyFileSync(stdinJsFile, backupFile);
    console.log(`💾 Backup created: ${backupFile}`);

    console.log('🔧 Patching getModelName()...');

    const getModelNameRange = findFunctionRange(content, 'getModelName');
    if (!getModelNameRange) {
        console.error('❌ Could not find getModelName function');
        return;
    }

    const newGetModelName = `export function getModelName(stdin) {
    // PATCH v2: from env or improved parsing
    // Priority: model.id (standard) > display_name (may contain extra info) > env > raw

    const modelId = stdin.model?.id?.trim();
    if (modelId) {
        const normalizedBedrockLabel = normalizeBedrockModelLabel(modelId);
        if (normalizedBedrockLabel) return normalizedBedrockLabel;

        const improved = normalizeClaudeModelLabel(modelId);
        if (improved) return improved;
    }

    const displayName = stdin.model?.display_name?.trim();
    if (displayName) {
        const improved = normalizeClaudeModelLabel(displayName);
        if (improved) return improved;
        // Strip context suffix like "(1M context)" before returning
        return displayName.replace(/\\s*\\([^)]+\\)\\s*$/, '').trim() || displayName;
    }

    // Fallback to env
    const envModel = process.env.ANTHROPIC_MODEL ||
                     process.env.ANTHROPIC_DEFAULT_SONNET_MODEL ||
                     process.env.ANTHROPIC_DEFAULT_OPUS_MODEL ||
                     process.env.ANTHROPIC_DEFAULT_HAIKU_MODEL;
    if (envModel) {
        const improved = normalizeClaudeModelLabel(envModel);
        return improved || envModel;
    }

    return modelId || 'Unknown';
}

// PATCH v2: better version parsing - handles 4.5, 4-5, 4.6 and display_name formats
function normalizeClaudeModelLabel(modelName) {
    if (!modelName) return null;
    const norm = modelName.toLowerCase().trim();

    // Format 1: claude-{family}-{version}  (model.id style)
    // e.g. claude-sonnet-4, claude-haiku-4.5, claude-opus-4-1, claude-sonnet-4-20250514
    let match = norm.match(/claude-([a-z]+)-(.*)/);
    if (match) {
        const family = match[1];
        let version = match[2].replace(/-\\d{8}$/, ''); // Remove date suffix like -20250514
        const parts = version.split(/[-.]/).filter(Boolean);
        if (parts.length > 0) {
            const familyCapital = family.charAt(0).toUpperCase() + family.slice(1);
            return 'Claude ' + familyCapital + ' ' + parts[0] + '.' + (parts[1] || '0');
        }
    }

    // Format 2: {Family} {Major}[.{Minor}] [(context)]  (display_name style)
    // e.g. "Sonnet 4 (1M context)", "Haiku 4.5", "Opus 4.1"
    match = norm.match(/^(haiku|sonnet|opus)\\s+(\\d+)(?:\\.(\\d+))?/);
    if (match) {
        const family = match[1];
        const major = match[2];
        const minor = match[3] || '0';
        const familyCapital = family.charAt(0).toUpperCase() + family.slice(1);
        return 'Claude ' + familyCapital + ' ' + major + '.' + minor;
    }

    return null;
}`;

    content = content.substring(0, getModelNameRange.startIdx) + newGetModelName + content.substring(getModelNameRange.endIdx);
    console.log('✅ getModelName() patched');

    console.log('🔧 Patching getProviderLabel()...');

    const getProviderRange = findFunctionRange(content, 'getProviderLabel');
    if (!getProviderRange) {
        console.error('❌ Could not find getProviderLabel function');
        return;
    }

    const newGetProviderLabel = `export function getProviderLabel(stdin) {
    // PATCH v2: with env fallback
    const modelId = stdin.model?.id?.trim() ||
                    process.env.ANTHROPIC_MODEL ||
                    process.env.ANTHROPIC_DEFAULT_SONNET_MODEL;
    if (!modelId) return null;

    if (isBedrockModelId(modelId)) {
        return 'Bedrock';
    }

    if (modelId.includes('openrouter') || /^[a-z-]+\\//.test(modelId)) {
        return 'OpenRouter';
    }

    if (modelId.startsWith('claude-') && !modelId.includes('/')) {
        return 'Claude API';
    }

    return null;
}`;

    content = content.substring(0, getProviderRange.startIdx) + newGetProviderLabel + content.substring(getProviderRange.endIdx);
    console.log('✅ getProviderLabel() patched');

    fs.writeFileSync(stdinJsFile, content, 'utf-8');

    console.log('✅ Patch v2 applied!');
    console.log('');
    console.log('改进：');
    console.log('  1. ✅ 精确版本号解析 (4.5 代替 4.0)');
    console.log('  2. ✅ 环境变量回退支持 (ANTHROPIC_MODEL)');
    console.log('  3. ✅ 多种格式支持 (4.6, 4-6, 4.6.0)');
    console.log('');
    console.log('💡 重启 Claude Code 查看效果');
}

function revertPatch(stdinJsFile) {
    const dir = path.dirname(stdinJsFile);
    const backupFiles = fs.readdirSync(dir)
        .filter(f => f.startsWith(path.basename(stdinJsFile) + '.backup.'))
        .map(f => path.join(dir, f))
        .sort()
        .reverse();

    if (backupFiles.length === 0) {
        console.error('❌ No backup found');
        process.exit(1);
    }

    const latestBackup = backupFiles[0];
    fs.copyFileSync(latestBackup, stdinJsFile);
    console.log('✅ Reverted to: ' + latestBackup);
}

function showStatus(stdinJsFile) {
    const content = fs.readFileSync(stdinJsFile, 'utf-8');
    if (isPatched(content)) {
        console.log('✅ Patch v2 is applied');
        console.log('');
        console.log('Features:');
        console.log('  ✅ Accurate version: 4.5 instead of 4.0');
        console.log('  ✅ Env variable fallback (ANTHROPIC_MODEL)');
        console.log('  ✅ Provider detection (OpenRouter, Claude API, Bedrock)');
    } else {
        console.log('❌ Patch v2 is NOT applied');
        console.log('');
        console.log('Run: node patch-stdin-v2-final.js --apply');
    }
}

const cmd = process.argv[2] || '--help';
const stdinJsFile = findStdinJs();

switch (cmd) {
    case '--apply':
        applyPatch(stdinJsFile);
        break;
    case '--revert':
        revertPatch(stdinJsFile);
        break;
    case '--status':
        showStatus(stdinJsFile);
        break;
    default:
        console.log('claude-hud Patch v2 Final - 精确模型名和供应商显示');
        console.log('');
        console.log('使用: node patch-stdin-v2-final.js [命令]');
        console.log('');
        console.log('命令:');
        console.log('  --apply   应用v2补丁');
        console.log('  --revert  回滚补丁');
        console.log('  --status  显示状态');
        console.log('');
        console.log('示例:');
        console.log('  node patch-stdin-v2-final.js --apply');
}
