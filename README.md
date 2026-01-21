# DATA Tools

**One command to set up Claude Code and Codex CLI on Replit with full persistence and automatic token refresh.**

When Replit containers restart, everything outside `/home/runner/workspace/` is wiped - including installed CLIs, conversations, auth tokens, and command history. DATA Tools fixes all of that.

## Quick Start

```bash
npx replit-tools
```

That's it. The installer will:

1. **Install Claude Code** (if not already installed)
2. **Install OpenAI Codex CLI** (if not already installed)
3. **Detect existing config** and preserve your data
4. **Set up persistence** so everything survives restarts
5. **Auto-refresh OAuth tokens** before they expire
6. **Launch the session picker** so you can start working immediately

## What Gets Installed

| Tool | Source | Purpose |
|------|--------|---------|
| **Claude Code** | `curl https://claude.ai/install.sh` | Anthropic's CLI for Claude |
| **Codex CLI** | `npm i -g @openai/codex` | OpenAI's coding assistant |

Both are installed only if not already present. Existing installations are preserved.

## What Gets Persisted

| Data | Location | Survives Restart? |
|------|----------|-------------------|
| Claude conversations | `.claude-persistent/` | Yes |
| Claude credentials | `.claude-persistent/` | Yes |
| Claude binary | `.local/share/claude/versions/` | Yes |
| Codex data | `.codex-persistent/` | Yes |
| Bash history | `.persistent-home/` | Yes |
| Per-terminal sessions | `.claude-sessions/` | Yes |

## Automatic Token Refresh

Claude OAuth tokens expire every **8-12 hours**. DATA Tools automatically refreshes them:

- **On every shell start**: Checks token expiry and refreshes if < 2 hours remaining
- **When expired**: Attempts automatic refresh using the stored refresh token
- **Transparent**: You'll see `🔄 Token expires in 1h, refreshing...` then `✅ Token refreshed (11h remaining)`

This means you can leave overnight and come back to a working session - no more `claude login` every morning.

### Manual Token Commands

```bash
# Check token status
/home/runner/workspace/scripts/claude-auth-refresh.sh --status

# Force refresh now
/home/runner/workspace/scripts/claude-auth-refresh.sh --force

# Or use a permanent API token (never expires)
claude setup-token
```

## The Session Picker

After installation (and on every new shell), you'll see:

```
✅ Claude authentication: valid (11h remaining)
✅ Claude Code ready: 2.0.71 (Claude Code)

╭─────────────────────────────────────────────────────────╮
│  Claude Session Manager                                 │
╰─────────────────────────────────────────────────────────╯
  (2 Claude instance(s) running in other terminals)

  [c] Continue last session for this terminal
      └─ b3dcb95c...
  [r] Resume a specific session (pick from list)
  [n] Start new session
  [s] Skip - just give me a shell

  Choice [c/r/n/s]: _
```

### Session Details

Press `r` to see full session metadata:

```
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  [1]
  ID:       b3dcb95c-cebb-4082-b671-988c8d36578e
  Messages: 237  |  Size: 912.1KB
  Active:   2m ago
  Started:  2026-01-18 18:22:12 UTC
  First:    "Can you help me fix this bug..."
  Latest:   "Thanks, that worked!"
```

Each session shows:
- Full UUID
- Message count and file size
- Time since last activity
- Start and last activity timestamps
- First and latest prompts (truncated)

## Multi-Terminal Support

Each terminal tracks its own session independently:

```
Terminal pts/0 → Session abc123... (your migration work)
Terminal pts/1 → Session def456... (your docs work)
Terminal pts/2 → Session ghi789... (your debugging)
```

Press `c` to continue YOUR terminal's last session. Other terminals are unaffected.

## How It Works

The installer creates symlinks from ephemeral locations to persistent workspace storage:

```
~/.claude             →  /workspace/.claude-persistent/
~/.codex              →  /workspace/.codex-persistent/
~/.local/share/claude →  /workspace/.local/share/claude/
~/.local/bin/claude   →  /workspace/.local/share/claude/versions/X.X.X
```

Three layers ensure setup runs on every restart:
1. `.replit` onBoot hook (runs at container boot)
2. `.config/bashrc` (runs on every shell start)
3. Scripts in `workspace/scripts/` (called by above)

## Smart Detection

The installer checks for:

- **`CLAUDE_CONFIG_DIR`** - Respects custom Claude config directory if set in Replit Secrets
- **`CODEX_HOME`** - Respects custom Codex config directory
- **Existing persistent config** - Uses your existing config if present
- **Replit Secrets** - Detects `ANTHROPIC_API_KEY` and `OPENAI_API_KEY`
- **Existing installations** - Won't reinstall Claude or Codex if already present
- **Existing data in ~/.claude** - Moves it to persistent storage instead of overwriting

### Supported Environment Variables

**Claude Code:**

| Variable | Purpose |
|----------|---------|
| `CLAUDE_CONFIG_DIR` | Custom directory for Claude config/data |
| `CLAUDE_WORKSPACE_DIR` | Alternative name (both are valid) |
| `CLAUDE_DATA_DIR` | Alternative name |
| `CLAUDE_HOME` | Alternative name |
| `ANTHROPIC_API_KEY` | Claude API authentication |

**OpenAI Codex CLI:**

| Variable | Purpose |
|----------|---------|
| `CODEX_HOME` | Custom directory for Codex config/data (official) |
| `CODEX_CONFIG_DIR` | Alternative name |
| `CODEX_DATA_DIR` | Alternative name |
| `OPENAI_API_KEY` | Codex API authentication |

If you set these in your Replit Secrets to paths inside `/home/runner/workspace/`, DATA Tools will use those directories for persistence instead of the defaults.

## Installation Options

### Option 1: npx (recommended)

```bash
npx replit-tools
```

### Option 2: curl

```bash
curl -fsSL https://raw.githubusercontent.com/stevemoraco/DATAtools/main/install.sh | bash
```

### Option 3: Global install

```bash
npm install -g replit-tools
replit-tools
```

## Commands

After installation, these aliases are available:

| Command | Description |
|---------|-------------|
| `cr` | Continue last Claude session |
| `claude-resume` | Same as `cr` |
| `claude-pick` | Claude's built-in session picker |
| `claude-menu` | Show the session manager menu again |

## Configuration

### Disable the session picker menu

```bash
export CLAUDE_NO_PROMPT=true
```

Add to `.config/bashrc` to make permanent.

### Use a permanent API token

```bash
claude setup-token
```

Creates a long-lived API token that never expires (recommended for unattended use).

## Files Created

```
workspace/
├── .claude-persistent/     # Claude conversations & credentials
├── .codex-persistent/      # Codex CLI data
├── .claude-sessions/       # Per-terminal session tracking
├── .local/share/claude/    # Claude binary versions
├── .persistent-home/       # Bash history
├── .config/bashrc          # Shell startup config
├── logs/                   # Auth refresh logs
├── scripts/
│   ├── setup-claude-code.sh      # Main setup script
│   ├── claude-session-manager.sh # Interactive session picker
│   └── claude-auth-refresh.sh    # OAuth token auto-refresh
└── .gitignore              # Updated to ignore credential dirs
```

## Troubleshooting

### Claude or Codex not found after restart

```bash
source /home/runner/workspace/scripts/setup-claude-code.sh
```

### Session picker not appearing

```bash
source /home/runner/workspace/.config/bashrc
```

### Auth keeps expiring

The auto-refresh should handle this, but if it fails:

```bash
# Check why refresh failed
cat /home/runner/workspace/logs/auth-refresh.log

# Manual refresh
/home/runner/workspace/scripts/claude-auth-refresh.sh --force

# Or use permanent token (recommended)
claude setup-token
```

### Symlinks broken

```bash
npx replit-tools
```

Running the installer again is safe - it preserves existing data.

## Security

The installer adds these to `.gitignore`:
- `.claude-persistent/` (contains credentials)
- `.codex-persistent/` (contains credentials)

Your API keys and conversation history won't be committed to git.

## Why "DATA Tools"?

**D**eveloper **A**ssistant **T**ool **A**utomation - everything you need to run AI coding assistants on Replit, persisted and ready to go.

## Repository

GitHub: [stevemoraco/DATAtools](https://github.com/stevemoraco/DATAtools)

## License

MIT
