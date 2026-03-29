#!/usr/bin/env bash
# guard-large-files.sh — PreToolUse Hook: 拦截大文件和自动生成文件
# 从 stdin 读取 CC 传入的 JSON，检查 tool_input 中的文件路径
# 安全原则：任何解析失败都 exit 0 放行，绝不阻断正常工作流

set -uo pipefail

# === 读取 stdin JSON ===
INPUT=$(cat)

# === 提取文件路径（兼容 file_path 和 path 两种字段名）===
FILE_PATH=$(echo "${INPUT}" | jq -r '.tool_input.file_path // .tool_input.path // .tool_input.filePath // empty' 2>/dev/null)

# 如果提取不到路径，直接放行
if [ -z "${FILE_PATH}" ]; then
    exit 0
fi

# === 规则 1：拦截自动生成文件 ===
BASENAME=$(basename "${FILE_PATH}")
case "${BASENAME}" in
    *_gen.go|*.pb.go|*.pb.validate.go)
        echo '{"hookSpecificOutput":{"permissionDecision":"deny"},"systemMessage":"⛔ 这是自动生成的文件（gen/pb），直接读取会浪费上下文。请改读对应的接口定义文件（如 domain/entity/ 或 .proto 文件）。"}'
        exit 0
        ;;
    *.min.js|*.min.css)
        echo '{"hookSpecificOutput":{"permissionDecision":"deny"},"systemMessage":"⛔ 这是压缩后的前端资源文件，读取无意义。请读取源文件。"}'
        exit 0
        ;;
esac

# === 规则 2：拦截噪音目录 ===
case "${FILE_PATH}" in
    */vendor/*|*/node_modules/*|*/dist/*|*/.git/*)
        echo '{"hookSpecificOutput":{"permissionDecision":"deny"},"systemMessage":"⛔ 此文件位于噪音目录（vendor/node_modules/dist/.git），不应直接读取。请读取项目源代码。"}'
        exit 0
        ;;
esac

# === 规则 3：超大文件警告（仅当文件存在时检查）===
if [ -f "${FILE_PATH}" ]; then
    LINE_COUNT=$(wc -l < "${FILE_PATH}" 2>/dev/null || echo "0")
    LINE_COUNT=$(echo "${LINE_COUNT}" | tr -d '[:space:]')
    if [ "${LINE_COUNT}" -gt 1000 ] 2>/dev/null; then
        echo "{\"systemMessage\":\"⚠️ 此文件有 ${LINE_COUNT} 行，超过 1000 行。建议只读取关键函数或接口定义部分，避免浪费上下文空间。\"}"
        exit 0
    fi
fi

# === 默认放行 ===
exit 0
