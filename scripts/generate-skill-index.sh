#!/usr/bin/env bash
# generate-skill-index.sh — 扫描 ~/.cchooks/skills/*/SKILL.md，生成精简索引
# 安全约束：Iris 风控 P0/P2 修正
#   - YAML frontmatter 解析（awk）
#   - 200字符硬截断
#   - 白名单字符过滤：只保留 [a-zA-Z0-9 .,_\-:/]

set -euo pipefail

SKILLS_DIR="${CC_SKILLS_DIR:-${HOME}/.cchooks/skills}"
CACHE_DIR="${HOME}/.cchooks/cache"
INDEX_FILE="${CACHE_DIR}/skills-index.md"
SENTINEL_FILE="${CACHE_DIR}/skills-index.sentinel"

mkdir -p "${CACHE_DIR}"

# === Lazy 缓存检查（基于文件变更 + skill 数量） ===
SKILL_PATHS=()
while IFS= read -r -d '' path; do
    SKILL_PATHS+=("$path")
done < <(find "${SKILLS_DIR}" -name "SKILL.md" -print0 2>/dev/null | sort -z)

CURRENT_COUNT="${#SKILL_PATHS[@]}"

# 读取上次记录的 skill 数量
PREV_COUNT=0
if [[ -f "${SENTINEL_FILE}" ]]; then
    PREV_COUNT="$(cat "${SENTINEL_FILE}" 2>/dev/null || echo 0)"
fi

# 判断是否需要重建：数量变化 OR 有 SKILL.md 比缓存更新
NEED_REBUILD=false

if [[ "${CURRENT_COUNT}" != "${PREV_COUNT}" ]]; then
    NEED_REBUILD=true
elif [[ ! -f "${INDEX_FILE}" ]]; then
    NEED_REBUILD=true
elif [[ "${CURRENT_COUNT}" -gt 0 ]]; then
    # 用 find -newer 检查是否有 SKILL.md 比索引更新
    NEWER_COUNT="$(find "${SKILLS_DIR}" -name "SKILL.md" -newer "${INDEX_FILE}" 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "${NEWER_COUNT}" -gt 0 ]]; then
        NEED_REBUILD=true
    fi
fi

if [[ "${NEED_REBUILD}" = false ]]; then
    echo "[generate-skill-index] Cache is up-to-date (${CURRENT_COUNT} skills). Skipping rebuild."
    exit 0
fi

echo "[generate-skill-index] Rebuilding index (${CURRENT_COUNT} skills)..."

# === 生成索引 ===
{
    echo "# OpenClaw Skills Available"
    echo ""
    echo "Below is a directory of available skills. When a task matches a skill, read its full SKILL.md with cat <path> before proceeding."
    echo ""

    for skill_path in "${SKILL_PATHS[@]}"; do
        # 提取 skill 名称（父目录名）
        skill_name="$(basename "$(dirname "${skill_path}")")"

        # 安全过滤 skill 名称（白名单）
        skill_name="$(echo "${skill_name}" | tr -cd 'a-zA-Z0-9 .,_\-:/')"

        # 解析 YAML frontmatter 中的 description 字段
        raw_desc="$(awk "/^---$/{n++; next} n==1 && /^description:/{sub(/^description:[[:space:]]*/,\"\"); print; exit}" "${skill_path}" 2>/dev/null || true)"

        # 安全过滤描述（白名单字符：只保留 [a-zA-Z0-9 .,_\-:/]）
        safe_desc="$(echo "${raw_desc}" | tr -cd 'a-zA-Z0-9 .,_\-:/')"

        # 200字符硬截断
        safe_desc="${safe_desc:0:200}"

        # 如果描述为空，使用占位符
        if [[ -z "${safe_desc}" ]]; then
            safe_desc="No description available."
        fi

        echo "- **${skill_name}**: ${safe_desc} → \`${skill_path}\`"
    done

    echo ""
    echo "_To use a skill: run cat <path> to read its full instructions, then follow them._"
} > "${INDEX_FILE}"

# 更新 sentinel（保存当前 skill 数量）
echo "${CURRENT_COUNT}" > "${SENTINEL_FILE}"

echo "[generate-skill-index] Done. Index written to ${INDEX_FILE} (${CURRENT_COUNT} skills)."
