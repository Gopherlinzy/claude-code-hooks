#!/usr/bin/env node
/**
 * claude-hud stdin.js 补丁工具 - 改进 model 和 provider 显示
 *
 * 问题：
 *   1. Model 显示不完整：Claude Sonnet 4.6 显示为 Sonnet 4
 *   2. Provider 不显示：OpenRouter/Claude API 无法显示供应商
 *
 * 用法：
 *   node patch-stdin-inline.js [--apply|--revert|--status]
 */

const fs = require('fs');
const path = require('path');
const os = require('os');

const CLAUDE_CONFIG_DIR = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
const PLUGIN_DIR = path.join(CLAUDE_CONFIG_DIR, 'plugins/cache/claude-hud/claude-hud');

// 找到最新版本的 stdin.js
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

    // 返回最后一个版本（最新）
    stdinJsFile = versions.sort().pop();
    console.log(`✅ Found: ${stdinJsFile}`);
    return stdinJsFile;
}

// 检查是否已打补丁
function isPatched(content) {
    return content.includes('// PATCH: improved model name parsing');
}

// 应用补丁
function applyPatch(stdinJsFile) {
    console.log('📝 Reading stdin.js...');
    let content = fs.readFileSync(stdinJsFile, 'utf-8');

    if (isPatched(content)) {
        console.log('⚠️  Already patched');
        return;
    }

    // 备份原文件
    const backupFile = `${stdinJsFile}.backup.${Date.now()}`;
    fs.copyFileSync(stdinJsFile, backupFile);
    console.log(`💾 Backup created: ${backupFile}`);

    console.log('🔧 Patching getModelName()...');

    // 补丁 1：改进 getModelName 函数
    // 匹配原始函数并替换
    const getModelNamePattern = /export function getModelName\(stdin\) \{[\s\S]*?return normalizedBedrockLabel \?\? modelId;\n\}/;

    const newGetModelName = `export function getModelName(stdin) {
    // PATCH: improved model name parsing
    const displayName = stdin.model?.display_name?.trim();
    if (displayName) {
        // Parse claude-sonnet-4 or claude-opus-4-1 formats
        const improved = normalizeClaudeModelLabel(displayName);
        if (improved) {
            return improved;
        }
        return displayName;
    }
    const modelId = stdin.model?.id?.trim();
    if (!modelId) {
        return 'Unknown';
    }
    const normalizedBedrockLabel = normalizeBedrockModelLabel(modelId);
    return normalizedBedrockLabel ?? modelId;
}

// PATCH: helper function to parse claude model names
function normalizeClaudeModelLabel(modelName) {
    const normalized = modelName.toLowerCase();

    // Handle: claude-sonnet-4, claude-opus-4, claude-haiku-3, etc.
    // Also handle: claude-opus-4-1, claude-sonnet-4-20250514
    const match = normalized.match(/claude-([a-z]+)-(\\d+)(?:-(\\d+))?/);
    if (!match) return null;

    const family = match[1];
    const majorVersion = match[2];
    const minorVersion = match[3] || '0';

    // Capitalize family name
    const familyCapitalized = family.charAt(0).toUpperCase() + family.slice(1);

    // Format: "Claude Sonnet 4.0" or "Claude Opus 4.1"
    return \`Claude \${familyCapitalized} \${majorVersion}.\${minorVersion}\`;
}`;

    if (getModelNamePattern.test(content)) {
        content = content.replace(getModelNamePattern, newGetModelName);
        console.log('✅ getModelName() patched');
    } else {
        console.warn('⚠️  Could not find getModelName() pattern, skipping...');
    }

    console.log('🔧 Patching getProviderLabel()...');

    // 补丁 2：改进 getProviderLabel 函数
    const getProviderLabelPattern = /export function getProviderLabel\(stdin\) \{[\s\S]*?return null;\n\}/;

    const newGetProviderLabel = `export function getProviderLabel(stdin) {
    // PATCH: improved provider label detection
    const modelId = stdin.model?.id?.trim();
    if (!modelId) return null;

    // Bedrock detection
    if (isBedrockModelId(modelId)) {
        return 'Bedrock';
    }

    // OpenRouter detection
    // Examples: openrouter/meta-llama/llama-2-70b-chat, anthropic/claude-3-sonnet
    if (modelId.includes('openrouter') || /^[^/]+\\/[^/]+\\//.test(modelId)) {
        return 'OpenRouter';
    }

    // Claude API (claude.ai) - direct claude-* without provider prefix
    if (modelId.startsWith('claude-') && !modelId.includes('/')) {
        return 'Claude API';
    }

    return null;
}`;

    if (getProviderLabelPattern.test(content)) {
        content = content.replace(getProviderLabelPattern, newGetProviderLabel);
        console.log('✅ getProviderLabel() patched');
    } else {
        console.warn('⚠️  Could not find getProviderLabel() pattern, skipping...');
    }

    // 写入修改后的文件
    fs.writeFileSync(stdinJsFile, content, 'utf-8');

    console.log('✅ Patch applied successfully!');
    console.log('');
    console.log('Changes:');
    console.log('  1. ✅ Improved model name parsing (Claude Sonnet 4.0 instead of Sonnet 4)');
    console.log('  2. ✅ Added OpenRouter provider detection');
    console.log('  3. ✅ Added Claude API provider detection');
    console.log('');
    console.log('💡 Restart Claude Code to see the changes');
    console.log('');
    console.log(`To revert: cp ${backupFile} ${stdinJsFile}`);
}

// 回滚补丁
function revertPatch(stdinJsFile) {
    const dir = path.dirname(stdinJsFile);
    const backupFiles = fs.readdirSync(dir)
        .filter(f => f.startsWith(path.basename(stdinJsFile) + '.backup.'))
        .map(f => path.join(dir, f))
        .sort()
        .reverse();

    if (backupFiles.length === 0) {
        console.error('❌ No backup found, cannot revert');
        process.exit(1);
    }

    const latestBackup = backupFiles[0];
    console.log(`📝 Reverting to: ${latestBackup}`);

    fs.copyFileSync(latestBackup, stdinJsFile);
    console.log('✅ Reverted successfully!');
    console.log('💡 Restart Claude Code to see the changes');
}

// 查看补丁状态
function showStatus(stdinJsFile) {
    const content = fs.readFileSync(stdinJsFile, 'utf-8');

    if (isPatched(content)) {
        console.log('✅ Patch is applied');
        console.log('');
        console.log('Features enabled:');
        console.log('  • Improved model name parsing');
        console.log('  • OpenRouter provider detection');
        console.log('  • Claude API provider detection');
        console.log('');

        // 显示备份文件
        const dir = path.dirname(stdinJsFile);
        const backupFiles = fs.readdirSync(dir)
            .filter(f => f.startsWith(path.basename(stdinJsFile) + '.backup.'))
            .sort()
            .reverse();

        if (backupFiles.length > 0) {
            console.log(`Last backup: ${path.join(dir, backupFiles[0])}`);
        }
    } else {
        console.log('❌ Patch is NOT applied');
        console.log('');
        console.log('Run: node patch-stdin-inline.js --apply');
    }
}

// 主程序
function main() {
    const command = process.argv[2] || '--help';
    const stdinJsFile = findStdinJs();

    switch (command) {
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
            console.log(`claude-hud Patch Tool - Fix statusline model and provider display

Usage: node patch-stdin-inline.js [COMMAND]

Commands:
  --apply         Apply the patch (fixes model name and provider display)
  --revert        Revert to previous version
  --status        Show current patch status
  --help          Show this help message

Examples:
  node patch-stdin-inline.js --apply
  node patch-stdin-inline.js --status
  node patch-stdin-inline.js --revert

Fixes:
  ✅ Model name parsing: Claude Sonnet 4.0 (instead of Sonnet 4)
  ✅ Provider detection: OpenRouter, Claude API, Bedrock
`);
            break;
    }
}

main();
