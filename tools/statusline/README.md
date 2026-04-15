# 🪄 Claude HUD StatusLine Tools

Enhance your Claude Code statusline with real-time OpenRouter API credit monitoring and session cost tracking.

## ⚡ Quick Start

**Display OpenRouter credit balance in claude-hud statusline:**

```
Amazon Bedrock: claude-4.5-haiku - $4.78 | 💰 334.83/500 ▓▓▓▓▓▓▓░░░ 67%
```

Shows:
- **Session cost**: `Amazon Bedrock: claude-4.5-haiku - $4.78` (provider, model, cost)
- **Account balance**: `334.83/500` (remaining / total limit)
- **Progress bar**: `▓▓▓▓▓▓▓░░░` (10 chars, 10% per block)
- **Percentage**: `67%`

## 🏗️ Architecture

### How It Works

```
┌─────────────────┐
│  Claude Code    │
│   (claude-hud)  │
└────────┬────────┘
         │
         │ calls --extra-cmd
         │
┌────────▼────────────────────────────────┐
│ openrouter-statusline.js (Node.js)      │
├─────────────────────────────────────────┤
│ • Fetch balance: /api/v1/key             │
│ • Read cached costs: /tmp/claude-..json  │
│ • Format output: { label: "..." }        │
└────────┬────────────────────────────────┘
         │
         │ Returns JSON
         │
┌────────▼─────────────────┐
│ claude-hud displays       │
│ in statusline             │
└──────────────────────────┘
```

### Data Flow

1. **Balance** — Fetched from `https://openrouter.ai/api/v1/key` API
2. **Session costs** — Read from cached files in `$TMPDIR/claude-openrouter-cost-*.json`
3. **Progress bar** — Calculated from `remaining / limit`

## 🔧 Installation

### Prerequisites

- `OPENROUTER_API_KEY` environment variable set
- claude-hud plugin installed (`/plugin install claude-hud`)
- Node.js available

### Step 1: Copy the script

```bash
mkdir -p ~/.claude/scripts/claude-hooks/statusline
cp tools/statusline/openrouter-statusline.js ~/.claude/scripts/claude-hooks/statusline/
chmod +x ~/.claude/scripts/claude-hooks/statusline/openrouter-statusline.js
```

Or use the installer:
```bash
./install.sh
# Select "Statusline tools" when prompted
```

### Step 2: Configure claude-hud

Edit `~/.claude/settings.json` and update (or create) the `statusLine` section:

```json
{
  "statusLine": {
    "command": "bash -c 'plugin_dir=$(ls -d \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | sort -V | tail -1); exec node \"${plugin_dir}dist/index.js\" --extra-cmd \"node ~/.claude/scripts/claude-hooks/statusline/openrouter-statusline.js\"'",
    "type": "command"
  }
}
```

**Windows (Git Bash):** Prefix `node` with `bash -c 'node …'`:
```json
{
  "statusLine": {
    "command": "bash -c 'plugin_dir=$(ls -d \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}\"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | sort -V | tail -1); exec bash -c \"node \\\"${plugin_dir}dist/index.js\\\" --extra-cmd \\\"bash ~/.claude/scripts/claude-hooks/statusline/openrouter-statusline.js\\\"\"'",
    "type": "command"
  }
}
```

### Step 3: Restart Claude Code

Changes take effect on next launch.

## ⚙️ Source Code Modification

Two patches to claude-hud are required for full functionality.

### Patch 1: Remove Output Length Limit (`extra-cmd.js`)

By default, `--extra-cmd` truncates output at **50 characters**. One-liner fix:

```bash
PLUGIN_DIR=$(ls -d ~/.claude/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | sort -V | tail -1)

# macOS
sed -i '' 's/const MAX_LABEL_LENGTH = 50/const MAX_LABEL_LENGTH = 999/' \
  "${PLUGIN_DIR}dist/extra-cmd.js"

# Linux
sed -i 's/const MAX_LABEL_LENGTH = 50/const MAX_LABEL_LENGTH = 999/' \
  "${PLUGIN_DIR}dist/extra-cmd.js"

# Verify
grep "MAX_LABEL_LENGTH" "${PLUGIN_DIR}dist/extra-cmd.js"
# Should show: const MAX_LABEL_LENGTH = 999;
```

### Patch 2: Write Current Model to Tmp File (`index.js`)

This enables `/model` switching to immediately update the model name in statusline.
claude-hud has stdin data (with current model) but `--extra-cmd` can't access it.
This patch writes the current model to `/tmp/claude-hud-current-model.json` before calling extra-cmd.

```bash
node - << 'PATCH_EOF'
const fs = require('fs'), os = require('os'), path = require('path');
const dir = path.join(os.homedir(), '.claude/plugins/cache/claude-hud/claude-hud');
const ver = fs.readdirSync(dir).filter(f => !f.startsWith('.')).sort().pop();
const file = path.join(dir, ver, 'dist/index.js');
let content = fs.readFileSync(file, 'utf-8');
const MARKER = '        const extraCmd = deps.parseExtraCmdArg();';
const PATCH = `        // 把当前模型写入临时文件，让 extra-cmd 实时感知 /model 切换
        try {
            const { writeFileSync } = await import('node:fs');
            const { join } = await import('node:path');
            const { tmpdir } = await import('node:os');
            writeFileSync(join(tmpdir(), 'claude-hud-current-model.json'), JSON.stringify({
                model_id: stdin.model?.id ?? '',
                display_name: stdin.model?.display_name ?? '',
                updated_at: Date.now(),
            }));
        } catch (_) {}
`;
if (content.includes('claude-hud-current-model')) {
  console.log('✅ already patched, skipping');
  process.exit(0);
}
if (!content.includes(MARKER)) {
  console.error('❌ insert marker not found — claude-hud version may have changed');
  process.exit(1);
}
fs.writeFileSync(file, content.replace(MARKER, PATCH + MARKER));
console.log('✅ index.js patched');
PATCH_EOF
```

Verify:
```bash
PLUGIN_DIR=$(ls -d ~/.claude/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | sort -V | tail -1)
grep -c "claude-hud-current-model" "${PLUGIN_DIR}dist/index.js" \
  && echo "✅ patch applied" || echo "❌ patch missing"
```

> **After claude-hud upgrades:** Both patches must be re-applied, as the plugin update overwrites the dist files.

## 📝 Configuration Details

### Environment Variables

```bash
# Required
export OPENROUTER_API_KEY="sk-or-v1-..."

# Optional - auto-detected if not set
export TMPDIR  # temp directory for cache files
```

### Output Format

The statusline displays in this format:

```
{session_cost} | {balance_with_bar}
```

**Example outputs:**

- With session cost:
  ```
  Amazon Bedrock: claude-4.5-haiku - $4.78 | 💰 334.83/500 ▓▓▓▓▓▓▓░░░ 67%
  ```

- Without session cost (no generation yet):
  ```
  💰 334.83/500 ▓▓▓▓▓▓▓░░░ 67%
  ```

- No API key (graceful fallback):
  ```
  (no extra info displayed)
  ```

## 🛠️ Customizing Source Code

### Edit the TypeScript Source

If you want to customize the output format or behavior, modify `openrouter-statusline.ts`:

```bash
# Edit the source
nano tools/statusline/openrouter-statusline.ts
```

### Key Functions

**`getBalance()`** — Fetches balance from OpenRouter API
```typescript
async function getBalance(): Promise<string | null>
```

**`tryGetSessionData()`** — Reads cached session costs from disk
```typescript
async function tryGetSessionData(): Promise<{sessionCost?: string} | null>
```

**`main()`** — Combines data and formats output
```typescript
async function main() {
  const balance = await getBalance();
  const sessionData = await tryGetSessionData();
  // Format and output...
}
```

### Compile After Changes

```bash
cd tools/statusline/
npx tsc openrouter-statusline.ts --target es2020 --module commonjs
```

This generates `openrouter-statusline.js`.

### Copy Updated Script

```bash
cp tools/statusline/openrouter-statusline.js ~/.claude/scripts/claude-hooks/statusline/
```

## 🔍 How It Tracks Costs

### Session Cost Caching

The script maintains a JSON cache file for each session:

```
$TMPDIR/claude-openrouter-cost-{session_id}.json
```

**Cache structure:**

```json
{
  "seen_ids": ["gen-001", "gen-002"],
  "total_cost": 4.78,
  "total_cache_discount": 0.15,
  "last_provider": "Amazon Bedrock",
  "last_model": "anthropic/claude-4.5-haiku"
}
```

**How it works:**

1. Script reads cache file for current session
2. Extracts generation IDs from transcript
3. For each unseen ID, calls `/api/v1/generation?id={id}` to get cost
4. Updates total cost and cache file
5. Displays last provider + model + total cost

**Cache benefits:**

- Avoids duplicate API calls for same generation
- Tracks costs across multiple API calls in one session
- Minimal overhead (~100ms with cache hits)

## 📊 Performance

- **Cache hit**: ~1ms (read local JSON)
- **Cache miss**: ~500-800ms (2 API calls)
- **Default behavior**: 60+ second cache → mostly hits
- **On new generation**: ~1 second to display updated cost

## 🐛 Troubleshooting

| Issue | Solution |
|-------|----------|
| OpenRouter info not showing | Check `OPENROUTER_API_KEY` is set: `echo $OPENROUTER_API_KEY` |
| Output truncated (shows "…") | Modify claude-hud `MAX_LABEL_LENGTH` to 999 (see above) |
| No session cost, only balance | First call hasn't completed yet, or generation ID not captured |
| Cache permission error | Check `/tmp` or `$TMPDIR` is writable: `ls -la $TMPDIR` |
| Timeout errors | Network issue or OpenRouter API slow, usually recovers in 60 seconds |

### Debug Mode

Enable debug output:

```bash
DEBUG=claude-hud node ~/.claude/scripts/claude-hooks/statusline/openrouter-statusline.js
```

## 📚 Related Files

- `openrouter-statusline.ts` — TypeScript source (edit this for customization)
- `openrouter-statusline.js` — Compiled JavaScript (what claude-hud runs)
- `openrouter-statusline.d.ts` — TypeScript type definitions
- `examples/` — Example statusline implementations for other APIs

## 📖 Documentation

- `INDEX.md` — Feature overview and navigation
- `QUICK_REFERENCE.md` — Quick lookup for output formats
- `ADDING_FEATURES.md` — Guide for adding new statusline features
- `examples/` — Example implementations (GitHub, Git, Weather, System, Aggregate)

## 🔗 API References

### OpenRouter Endpoints Used

**Get Account Balance:**
```bash
curl https://openrouter.ai/api/v1/key \
  -H "Authorization: Bearer $OPENROUTER_API_KEY"
```

Response fields:
- `data.limit_remaining` — Credits remaining
- `data.limit` — Total limit
- `data.usage` — Total used (optional)

**Get Generation Cost:**
```bash
curl "https://openrouter.ai/api/v1/generation?id={id}" \
  -H "Authorization: Bearer $OPENROUTER_API_KEY"
```

Response fields:
- `data.total_cost` — Cost in USD
- `data.cache_discount` — Discount applied
- `data.provider_name` — Provider name
- `data.model` — Model identifier

## 📄 License

Same as claude-code-hooks main project.
