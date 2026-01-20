# replit-claude-persist

**Persist Claude Code sessions, authentication, and history across Replit container restarts.**

When Replit containers restart, everything outside `/home/runner/workspace/` is wiped - including your Claude conversations, auth tokens, and installed binaries. This tool fixes that.

## Features

- **Session Persistence** - Conversations survive container restarts
- **Interactive Session Picker** - Choose which session to resume on shell start
- **Multi-Terminal Support** - Each terminal tracks its own session
- **Auth Persistence** - Keep your Claude authentication working
- **Binary Caching** - Claude binary persists (faster startup)
- **Bash History** - Command history survives restarts too

## Installation

### Option 1: npx (easiest)

```bash
npx replit-claude-persist
```

### Option 2: curl

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/replit-claude-persist/main/install.sh | bash
```

### Option 3: Manual

```bash
npm install -g replit-claude-persist
replit-claude-persist
```

## What You'll See

After installation, opening a new shell shows:

```
✅ Claude authentication: valid (23h remaining)
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

Press `r` to see detailed session info:

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

## How It Works

The tool creates symlinks from ephemeral locations to persistent workspace storage:

```
~/.claude      →  /workspace/.claude-persistent/
~/.codex       →  /workspace/.codex-persistent/
~/.local/bin/  →  /workspace/.local/share/claude/versions/
```

On every shell start, `.config/bashrc` ensures symlinks exist and shows the session picker.

## Commands

| Command | Description |
|---------|-------------|
| `cr` | Continue last session |
| `claude-menu` | Show session picker again |
| `claude-new` | Start fresh session |
| `claude-pick` | Claude's built-in picker |

## Configuration

### Disable the menu

```bash
export CLAUDE_NO_PROMPT=true
```

Add to `.config/bashrc` to make permanent.

### Fix auth permanently

```bash
claude setup-token
```

Creates a long-lived token that doesn't expire.

## Files Created

```
workspace/
├── .claude-persistent/     # Conversations, credentials
├── .codex-persistent/      # Codex CLI data
├── .claude-sessions/       # Per-terminal session tracking
├── .local/share/claude/    # Claude binary versions
├── .persistent-home/       # Bash history
├── .config/bashrc          # Shell startup config
└── scripts/
    ├── setup-claude-code.sh
    └── claude-session-manager.sh
```

## Troubleshooting

### Menu not appearing

```bash
source /home/runner/workspace/.config/bashrc
```

### Auth expired

```bash
claude login
# Or for permanent fix:
claude setup-token
```

### Symlinks broken

```bash
source /home/runner/workspace/scripts/setup-claude-code.sh
```

## License

MIT
