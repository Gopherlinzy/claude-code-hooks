#!/usr/bin/env node
// merge-hooks.js — 将 claude-code-hooks 深度合并进 settings.json
// Usage: node merge-hooks.js <settings.json> <hooks-patch.json> <output.json>
'use strict';

const fs = require('fs');

const [,, settingsPath, patchPath, outputPath] = process.argv;
if (!settingsPath || !patchPath || !outputPath) {
  console.error('Usage: node merge-hooks.js <settings.json> <hooks-patch.json> <output.json>');
  process.exit(1);
}

// 读取现有 settings（不存在则空对象）
let settings = {};
try {
  const raw = fs.readFileSync(settingsPath, 'utf8');
  // 剥离 BOM
  const clean = raw.replace(/^\uFEFF/, '');
  if (clean.trim()) {
    settings = JSON.parse(clean);
  }
} catch (e) {
  if (e.code !== 'ENOENT') {
    console.error(`Error reading ${settingsPath}: ${e.message}`);
    process.exit(2);
  }
  // 文件不存在 — 从空对象开始
}

// 读取 patch
let patch;
try {
  patch = JSON.parse(fs.readFileSync(patchPath, 'utf8'));
} catch (e) {
  console.error(`Error reading ${patchPath}: ${e.message}`);
  process.exit(2);
}

// 确保 hooks 对象存在
if (!settings.hooks) settings.hooks = {};

// 深度合并：按 (eventType, matcher) 做唯一键匹配
for (const [eventType, patchEntries] of Object.entries(patch.hooks || {})) {
  if (!Array.isArray(settings.hooks[eventType])) {
    settings.hooks[eventType] = [];
  }

  for (const patchEntry of patchEntries) {
    // 找到同 matcher 的现有条目
    const existingIdx = settings.hooks[eventType].findIndex(
      e => e.matcher === patchEntry.matcher
    );

    if (existingIdx >= 0) {
      const existing = settings.hooks[eventType][existingIdx];
      if (!Array.isArray(existing.hooks)) existing.hooks = [];

      // 合并 hooks 数组：按 command 路径去重
      for (const patchHook of (patchEntry.hooks || [])) {
        const hookIdx = existing.hooks.findIndex(
          h => h.command === patchHook.command
        );
        if (hookIdx >= 0) {
          // 更新已有条目（覆盖 timeout 等属性）
          existing.hooks[hookIdx] = { ...existing.hooks[hookIdx], ...patchHook };
        } else {
          // 追加新条目
          existing.hooks.push(patchHook);
        }
      }
    } else {
      // 追加整个新 entry
      settings.hooks[eventType].push(patchEntry);
    }
  }
}

// 写入输出（2 空格缩进 + 尾换行）
fs.writeFileSync(outputPath, JSON.stringify(settings, null, 2) + '\n', 'utf8');
console.log('OK');
