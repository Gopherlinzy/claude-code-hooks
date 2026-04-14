# 🪄 Claude HUD StatusLine Tools

Enhance your Claude Code statusline with real-time API credit monitoring and custom metrics.

## 🔧 claude-hud Display Patch

Fixes two bugs in claude-hud's default model/provider display:

| Before | After |
|--------|-------|
| `[sonnet 4]` | `[Claude Sonnet 4.6 \| Claude API]` |
| `[Claude Haiku 4.0]` | `[Claude Haiku 4.5 \| OpenRouter]` |
| `[Unknown]` | `[glm-5.1 \| z-ai]` |

**What it fixes:**
- Model version truncated (4.6 shown as 4 or 4.0)
- Provider not shown (OpenRouter, Claude API, custom base URL)
- Non-Claude models (glm, gpt, llama…) not recognized
- OpenRouter `vendor/model` format (`anthropic/claude-sonnet-4-5`) not parsed

### Install the patch

**Step 1 — Copy the patch script**

```bash
mkdir -p ~/.claude/scripts/claude-hooks/statusline
curl -fsSL https://raw.githubusercontent.com/Gopherlinzy/claude-code-hooks/main/tools/statusline/patch-stdin-v2-final.js \
  -o ~/.claude/scripts/claude-hooks/statusline/patch-stdin-v2-final.js
chmod +x ~/.claude/scripts/claude-hooks/statusline/patch-stdin-v2-final.js
```

> 🇨🇳 **GitHub slow?** Replace `raw.githubusercontent.com/Gopherlinzy` with `ghfast.top/https://raw.githubusercontent.com/Gopherlinzy`

**Step 2 — Apply**

```bash
node ~/.claude/scripts/claude-hooks/statusline/patch-stdin-v2-final.js --apply
```

Expected output:
```
✅ getModelName() patched
✅ getProviderLabel() patched
✅ Patch v2 applied!
```

**Step 3 — Restart Claude Code**

The patch takes effect on next launch.

### Other patch commands

```bash
# Check whether patch is applied
node ~/.claude/scripts/claude-hooks/statusline/patch-stdin-v2-final.js --status

# Roll back to original
node ~/.claude/scripts/claude-hooks/statusline/patch-stdin-v2-final.js --revert
```

### How provider detection works

The patch reads `ANTHROPIC_BASE_URL` to identify the actual provider:

| `ANTHROPIC_BASE_URL` | Provider shown |
|---|---|
| `api.anthropic.com` (or not set) | `Claude API` |
| `openrouter.ai/…` | `OpenRouter` |
| `api.z-ai.com/…` | `z-ai` |
| `api.aihubmix.com/…` | `aihubmix` |
| AWS Bedrock model ID | `Bedrock` |

For OpenRouter, the `vendor/model` format is understood:

| `ANTHROPIC_MODEL` | Displayed as |
|---|---|
| `anthropic/claude-sonnet-4-5` | `Claude Sonnet 4.5 \| OpenRouter` |
| `z-ai/glm-5.1` | `glm-5.1 \| OpenRouter` |
| `meta-llama/llama-3.3-70b-instruct` | `llama-3.3-70b-instruct \| OpenRouter` |

### settings.json — statusLine command

After installing claude-hud (`/plugin install claude-hud`) and running setup (`/claude-hud:setup`), your `~/.claude/settings.json` should contain a `statusLine` block. If it doesn't, or you want to configure it manually:

```bash
# Auto-generate the correct command for your system
~/.claude/scripts/claude-hooks/setup-statusline.sh
```

Or paste this template into `~/.claude/settings.json` (replacing `NODE_PATH` and `PLUGIN_DIR`):

```json
{
  "statusLine": {
    "command": "bash -c 'plugin_dir=$(ls -d \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | sort -V | tail -1); exec node \"${plugin_dir}dist/index.js\" --extra-cmd \"bash ~/.claude/scripts/claude-hooks/statusline/openrouter-status.sh\"'",
    "type": "command"
  }
}
```

> **Windows (Git Bash):** prefix `node` with `bash -c 'node …'` and use forward slashes. The `setup-statusline.sh` script handles this automatically.

#### With patch applied, no OpenRouter key needed

If you only want model + provider labels and don't use OpenRouter credits, you can omit `--extra-cmd` entirely:

```json
{
  "statusLine": {
    "command": "bash -c 'plugin_dir=$(ls -d \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | sort -V | tail -1); exec node \"${plugin_dir}dist/index.js\"'",
    "type": "command"
  }
}
```

The patch fixes the display inside claude-hud itself — no extra script required.

## Available Tools

### OpenRouter Credit Monitor

Display your OpenRouter API balance in the claude-hud statusline with a visual progress bar.

**Features:**
- Real-time credit balance and limit display
- Visual progress bar (10 characters, 10% per block)
- 60-second smart cache (minimize API calls)
- Graceful error handling (no key, network offline, auth failed)
- Lightweight and fast (~100ms with cache)

**Output Format:**
```
💰 394.34/500 ▓▓▓▓▓▓▓░░░ 79%
```

Shows:
- `💰` — Emoji indicator
- `394.34/500` — Remaining credits / Total limit
- `▓▓▓▓▓▓▓░░░` — Visual progress bar (79% → 7 filled blocks)
- `79%` — Percentage

## Installation

### Option 1: Via claude-code-hooks Install Script

```bash
./install.sh
# Select "Statusline tools" when prompted
```

The installer will:
1. Copy scripts to `~/.claude/scripts/claude-hooks/statusline/`
2. Guide you through configuration
3. Update your `settings.json` automatically

### Option 2: Manual Setup

```bash
# Copy the script
cp tools/statusline/openrouter-status.sh ~/.claude/scripts/claude-hooks/statusline/

# Make it executable
chmod +x ~/.claude/scripts/claude-hooks/statusline/openrouter-status.sh

# Ensure OPENROUTER_API_KEY is set in your environment
echo $OPENROUTER_API_KEY  # should show your key
```

## Configuration

### Add to Claude Code Settings

Edit `~/.claude/settings.json` and update the `statusLine` section to include the `--extra-cmd` parameter:

```json
{
  "statusLine": {
    "command": "bash -c 'plugin_dir=$(ls -d \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | awk -F/ '\"'\"'{ print $(NF-1) \"\\t\" $(0) }'\"'\"' | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1 | cut -f2-); exec \"/path/to/node\" \"${plugin_dir}dist/index.js\" --extra-cmd \"bash ~/.claude/scripts/claude-hooks/statusline/openrouter-status.sh\"'",
    "type": "command"
  }
}
```

Or use the installer which handles this automatically.

### Environment Variables

Make sure `OPENROUTER_API_KEY` is available in your shell:

```bash
# Add to ~/.zshrc or ~/.bashrc
export OPENROUTER_API_KEY="sk-or-v1-..."
```

## How It Works

1. **claude-hud** calls `openrouter-status.sh` via `--extra-cmd` parameter
2. Script checks for valid cache (60-second TTL)
3. If cache miss, calls `https://openrouter.ai/api/v1/key` API
4. Parses `limit_remaining` and `limit` from response
5. Calculates percentage and generates progress bar
6. Returns JSON: `{ "label": "💰 394.34/500 ▓▓▓▓▓▓▓░░░ 79%" }`
7. claude-hud displays in statusline

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Shows `No Key` | Set `OPENROUTER_API_KEY` environment variable |
| Shows `Auth Failed` | Check your API key is valid |
| Shows `Offline` | Network connectivity issue, check curl works |
| Shows `☐` | Cache file corrupted, try: `rm ~/.claude/openrouter-cache.json` |
| Slow updates | Cache is working, wait 60 seconds for fresh fetch |

## Customization

### Change Cache TTL

Edit `openrouter-status.sh`:
```bash
CACHE_TTL=30  # Change from 60 to 30 seconds
```

### Change Display Format

Example: Show only percentage
```bash
label=$(printf "💰 %d%%\n" "$percent")
```

Example: Add usage data
```bash
usage=$(echo "$response" | jq -r '.data.usage // 0')
label=$(printf "💰 %.2f/%.0f %s %d%% | Used: %.2f\n" "$remaining" "$limit" "$bar" "$percent" "$usage")
```

### Low Credit Warning

```bash
# After calculating percent:
if (( $(echo "$remaining < 10" | bc -l 2>/dev/null) )); then
  emoji="🪫"  # Low battery emoji
else
  emoji="💰"
fi
label=$(printf "%s %.2f/%.0f %s %d%%\n" "$emoji" "$remaining" "$limit" "$bar" "$percent")
```

## API Details

Uses OpenRouter's `GET /api/v1/key` endpoint:

```bash
curl https://openrouter.ai/api/v1/key \
  -H "Authorization: Bearer $OPENROUTER_API_KEY"
```

**Response Fields Used:**
- `data.limit_remaining` — Credits remaining
- `data.limit` — Total credit limit
- `data.usage` — Total credits used (optional)
- `data.usage_daily` — Daily usage (optional)

All calls cached for 60 seconds to stay under rate limits.

## Performance Impact

- **With cache hit**: ~1ms (reads local JSON file)
- **With cache miss**: ~500-800ms (API call + parsing)
- **Default**: Cache for 60 seconds → ~1ms most of the time
- **Network overhead**: Minimal, curl timeout set to 2 seconds

## License

Same as claude-code-hooks main project.
