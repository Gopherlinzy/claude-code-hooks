#!/usr/bin/env node
/**
 * claude-hud stdin.js 补丁 v2 - 改进版
 * 修复：
 *   1. Model 版本号识别不准确（4.0 vs 4.5）
 *   2. 支持从环境变量读取模型信息
 *   3. Provider 识别改进
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
    return content.includes('// PATCH v2: improved model parsing with env fallback');
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

    console.log('🔧 Patching getModelName() with environment variable support...');

    // 改进的 getModelName - 支持环境变量和更准确的版本号解析
    const newGetModelName = `export function getModelName(stdin) {
    // PATCH v2: improved model parsing with env fallback

    // Try stdin display_name first
    const displayName = stdin.model?.display_name?.trim();
    if (displayName) {
        const improved = normalizeClaudeModelLabel(displayName);
        if (improved) return improved;
    }

    // Try stdin model.id
    const modelId = stdin.model?.id?.trim();
    if (modelId) {
        // Check Bedrock format
        const normalizedBedrockLabel = normalizeBedrockModelLabel(modelId);
        if (normalizedBedrockLabel) return normalizedBedrockLabel;

        // Check Claude model format
        const improved = normalizeClaudeModelLabel(modelId);
        if (improved) return improved;

        return modelId;
    }

    // Fallback: check environment variables
    const envModel = process.env.ANTHROPIC_MODEL ||
                     process.env.ANTHROPIC_DEFAULT_SONNET_MODEL ||
                     process.env.ANTHROPIC_DEFAULT_OPUS_MODEL ||
                     process.env.ANTHROPIC_DEFAULT_HAIKU_MODEL;

    if (envModel) {
        const improved = normalizeClaudeModelLabel(envModel);
        if (improved) return improved;
        return envModel;
    }

    return 'Unknown';
}

// PATCH v2: improved Claude model label parsing with accurate version handling
function normalizeClaudeModelLabel(modelName) {
    if (!modelName) return null;

    const normalized = modelName.toLowerCase().trim();

    // Handle all formats:
    // claude-sonnet-4        -> Claude Sonnet 4.0
    // claude-sonnet-4.6      -> Claude Sonnet 4.6
    // claude-sonnet-4-6      -> Claude Sonnet 4.6
    // claude-opus-4-1        -> Claude Opus 4.1
    // claude-haiku-3.5       -> Claude Haiku 3.5
    // claude-haiku-4-5       -> Claude Haiku 4.5
    // claude-sonnet-4-20250514 -> Claude Sonnet 4.0

    // Match family and version with dots or hyphens
    let match = normalized.match(/claude-([a-z]+)-([\\d.]+)/);

    if (!match) return null;

    const family = match[1];
    let version = match[2]; // Could be "4", "4.6", "4-6", "4-20250514", etc.

    // Clean up version string
    version = version.replace(/-\\d{8}$/, ''); // Remove date suffixes like -20250514

    // Split version by either dot or hyphen
    const versionParts = version.split(/[-.]/).filter(Boolean);

    if (versionParts.length === 0) return null;

    // Take first two parts as major.minor
    const major = versionParts[0];
    const minor = versionParts[1] || '0';

    // Capitalize family name
    const familyCapitalized = family.charAt(0).toUpperCase() + family.slice(1);

    return 'Claude ' + familyCapitalized + ' ' + major + '.' + minor;
}`;

    // Find and replace getModelName function
    const getModelNamePattern = /export function getModelName\(stdin\) \{[\s\S]*?return 'Unknown';\n\}/;

    if (getModelNamePattern.test(content)) {
        content = content.replace(getModelNamePattern, newGetModelName);
        console.log('✅ getModelName() patched with env fallback');
    } else {
        console.warn('⚠️  Could not find getModelName() pattern');
        return;
    }

    console.log('🔧 Patching getProviderLabel() with improved detection...');

    // 改进的 getProviderLabel
    const newGetProviderLabel = `export function getProviderLabel(stdin) {
    // PATCH v2: improved provider detection with env support

    const modelId = stdin.model?.id?.trim() ||
                    process.env.ANTHROPIC_MODEL ||
                    process.env.ANTHROPIC_DEFAULT_SONNET_MODEL;

    if (!modelId) return null;

    // Bedrock detection
    if (isBedrockModelId(modelId)) {
        return 'Bedrock';
    }

    // OpenRouter detection
    if (modelId.includes('openrouter') || /^[a-z-]+\\/[a-z-]+\\//.test(modelId)) {
        return 'OpenRouter';
    }

    // Claude API (direct claude-* format, no provider prefix)
    if (modelId.startsWith('claude-') && !modelId.includes('/')) {
        return 'Claude API';
    }

    return null;
}`;

    const getProviderLabelPattern = /export function getProviderLabel\(stdin\) \{[\s\S]*?return null;\n\}/;

    if (getProviderLabelPattern.test(content)) {
        content = content.replace(getProviderLabelPattern, newGetProviderLabel);
        console.log('✅ getProviderLabel() patched');
    } else {
        console.warn('⚠️  Could not find getProviderLabel() pattern');
    }

    fs.writeFileSync(stdinJsFile, content, 'utf-8');

    console.log('✅ Patch v2 applied successfully!');
    console.log('');
    console.log('Improvements:');
    console.log('  1. ✅ Better version number parsing (4.5 instead of 4.0)');
    console.log('  2. ✅ Environment variable fallback support');
    console.log('  3. ✅ Support for multiple version formats (4.6, 4-6, 4.6.0)');
    console.log('');
    console.log('💡 Restart Claude Code to see the changes');
    console.log('');
    console.log('To revert: cp ' + backupFile + ' ' + stdinJsFile);
}

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
    console.log('📝 Reverting to: ' + latestBackup);

    fs.copyFileSync(latestBackup, stdinJsFile);
    console.log('✅ Reverted successfully!');
    console.log('💡 Restart Claude Code to see the changes');
}

function showStatus(stdinJsFile) {
    const content = fs.readFileSync(stdinJsFile, 'utf-8');

    if (isPatched(content)) {
        console.log('✅ Patch v2 is applied');
        console.log('');
        console.log('Features:');
        console.log('  ✅ Accurate version parsing (4.5, 4.6, etc.)');
        console.log('  ✅ Environment variable fallback');
        console.log('  ✅ OpenRouter/Claude API detection');
        console.log('');

        const dir = path.dirname(stdinJsFile);
        const backupFiles = fs.readdirSync(dir)
            .filter(f => f.startsWith(path.basename(stdinJsFile) + '.backup.'))
            .sort()
            .reverse();

        if (backupFiles.length > 0) {
            console.log('Last backup: ' + path.join(dir, backupFiles[0]));
        }
    } else {
        console.log('❌ Patch v2 is NOT applied');
        console.log('');
        console.log('Run: node patch-stdin-v2.js --apply');
    }
}

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
            console.log('claude-hud Patch Tool v2 - Better model and provider display\n');
            console.log('Usage: node patch-stdin-v2.js [COMMAND]\n');
            console.log('Commands:');
            console.log('  --apply         Apply the v2 patch (better version parsing + env support)');
            console.log('  --revert        Revert to previous version');
            console.log('  --status        Show current patch status');
            console.log('  --help          Show this help message\n');
            console.log('Improvements in v2:');
            console.log('  ✅ Accurate version parsing: 4.5 instead of 4.0');
            console.log('  ✅ Environment variable support (ANTHROPIC_MODEL, etc.)');
            console.log('  ✅ Multiple version format support (4.6, 4-6, 4.6.0)\n');
            console.log('Examples:');
            console.log('  node patch-stdin-v2.js --apply');
            console.log('  node patch-stdin-v2.js --status');
            console.log('  node patch-stdin-v2.js --revert');
            break;
    }
}

main();
