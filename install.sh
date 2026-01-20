#!/bin/bash
# =============================================================================
# Replit Claude Persistence Installer
# =============================================================================
# One-line install:
#   curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/replit-claude-persist/main/install.sh | bash
#
# Or with npx:
#   npx replit-claude-persist
# =============================================================================

set -e

WORKSPACE="/home/runner/workspace"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo ""
echo "╭─────────────────────────────────────────────────────────╮"
echo "│  Replit Claude Persistence Installer                    │"
echo "╰─────────────────────────────────────────────────────────╯"
echo ""

# Check we're on Replit
if [ ! -d "/home/runner/workspace" ]; then
    echo -e "${RED}ERROR: This script must be run on Replit${NC}"
    echo "       /home/runner/workspace not found"
    exit 1
fi

cd "$WORKSPACE"

echo "📁 Creating directories..."
mkdir -p .claude-persistent
mkdir -p .codex-persistent
mkdir -p .claude-sessions
mkdir -p .local/share/claude/versions
mkdir -p .persistent-home
mkdir -p .config
mkdir -p scripts
mkdir -p logs

echo "📝 Installing scripts..."

# setup-claude-code.sh
cat > scripts/setup-claude-code.sh << 'SCRIPT_EOF'
#!/bin/bash
# Claude Code Setup Script for Replit
set -e

WORKSPACE="/home/runner/workspace"
CLAUDE_PERSISTENT="${WORKSPACE}/.claude-persistent"
CLAUDE_LOCAL_SHARE="${WORKSPACE}/.local/share/claude"
CLAUDE_VERSIONS="${CLAUDE_LOCAL_SHARE}/versions"
CLAUDE_SYMLINK="${HOME}/.claude"
LOCAL_BIN="${HOME}/.local/bin"
LOCAL_SHARE_CLAUDE="${HOME}/.local/share/claude"

log() {
    if [[ $- == *i* ]]; then
        echo "$1"
    fi
}

mkdir -p "${CLAUDE_PERSISTENT}"
mkdir -p "${CLAUDE_VERSIONS}"
mkdir -p "${LOCAL_BIN}"
mkdir -p "${HOME}/.local/share"

# Symlink ~/.claude
if [ ! -L "${CLAUDE_SYMLINK}" ] || [ "$(readlink -f "${CLAUDE_SYMLINK}")" != "${CLAUDE_PERSISTENT}" ]; then
    rm -rf "${CLAUDE_SYMLINK}" 2>/dev/null || true
    ln -sf "${CLAUDE_PERSISTENT}" "${CLAUDE_SYMLINK}"
    log "✅ Claude history symlink: ~/.claude -> ${CLAUDE_PERSISTENT}"
fi

# Symlink ~/.local/share/claude
if [ ! -L "${LOCAL_SHARE_CLAUDE}" ] || [ "$(readlink -f "${LOCAL_SHARE_CLAUDE}")" != "${CLAUDE_LOCAL_SHARE}" ]; then
    rm -rf "${LOCAL_SHARE_CLAUDE}" 2>/dev/null || true
    ln -sf "${CLAUDE_LOCAL_SHARE}" "${LOCAL_SHARE_CLAUDE}"
fi

# Find and symlink binary
LATEST_VERSION=""
if [ -d "${CLAUDE_VERSIONS}" ]; then
    LATEST_VERSION=$(ls -1 "${CLAUDE_VERSIONS}" 2>/dev/null | sort -V | tail -n1)
fi

if [ -n "${LATEST_VERSION}" ] && [ -f "${CLAUDE_VERSIONS}/${LATEST_VERSION}" ]; then
    CLAUDE_BINARY="${CLAUDE_VERSIONS}/${LATEST_VERSION}"
    if [ ! -L "${LOCAL_BIN}/claude" ] || [ "$(readlink -f "${LOCAL_BIN}/claude")" != "${CLAUDE_BINARY}" ]; then
        rm -f "${LOCAL_BIN}/claude" 2>/dev/null || true
        ln -sf "${CLAUDE_BINARY}" "${LOCAL_BIN}/claude"
        log "✅ Claude binary symlink: ~/.local/bin/claude -> ${CLAUDE_BINARY}"
    fi
else
    log "⚠️  Claude Code not found, installing..."
    if command -v npm &> /dev/null; then
        npm install -g @anthropic-ai/claude-code 2>/dev/null || true
        if command -v claude &> /dev/null; then
            INSTALLED_PATH=$(which claude)
            if [ -f "${INSTALLED_PATH}" ] && [ ! -L "${INSTALLED_PATH}" ]; then
                VERSION=$(claude --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)
                if [ -n "${VERSION}" ]; then
                    cp "${INSTALLED_PATH}" "${CLAUDE_VERSIONS}/${VERSION}"
                    chmod +x "${CLAUDE_VERSIONS}/${VERSION}"
                    ln -sf "${CLAUDE_VERSIONS}/${VERSION}" "${LOCAL_BIN}/claude"
                    log "✅ Claude Code ${VERSION} installed"
                fi
            fi
        fi
    fi
fi

# Ensure PATH
if [[ ":$PATH:" != *":${LOCAL_BIN}:"* ]]; then
    export PATH="${LOCAL_BIN}:$PATH"
fi

# Check auth
CREDENTIALS_FILE="${CLAUDE_PERSISTENT}/.credentials.json"
if [ -f "${CREDENTIALS_FILE}" ]; then
    if command -v node &> /dev/null; then
        AUTH_INFO=$(node -e "
            try {
                const creds = require('${CREDENTIALS_FILE}');
                const oauth = creds.claudeAiOauth;
                const apiKey = creds.primaryApiKey;
                if (apiKey) console.log('apikey');
                else if (oauth && oauth.expiresAt) console.log(oauth.expiresAt);
            } catch(e) {}
        " 2>/dev/null)

        if [ "${AUTH_INFO}" = "apikey" ]; then
            log "✅ Claude authentication: long-lived token (no expiration)"
        elif [ -n "${AUTH_INFO}" ]; then
            CURRENT_TIME=$(node -e "console.log(Date.now())" 2>/dev/null)
            if [ -n "${CURRENT_TIME}" ] && [ "${AUTH_INFO}" -gt "${CURRENT_TIME}" ]; then
                HOURS_LEFT=$(node -e "console.log(Math.floor((${AUTH_INFO} - ${CURRENT_TIME}) / 1000 / 60 / 60))" 2>/dev/null)
                if [ "${HOURS_LEFT}" -lt 2 ]; then
                    log "⚠️  Claude authentication: expires in ${HOURS_LEFT}h"
                else
                    log "✅ Claude authentication: valid (${HOURS_LEFT}h remaining)"
                fi
            else
                log "⚠️  Claude authentication: expired, run 'claude login'"
            fi
        fi
    fi
else
    log "⚠️  No Claude credentials. Run 'claude login'"
fi

if [[ $- == *i* ]] && [ -n "${LATEST_VERSION}" ]; then
    if command -v claude &> /dev/null; then
        CLAUDE_VERSION=$(claude --version 2>/dev/null | head -1)
        log "✅ Claude Code ready: ${CLAUDE_VERSION}"
    fi
fi
SCRIPT_EOF

# claude-session-manager.sh
cat > scripts/claude-session-manager.sh << 'SCRIPT_EOF'
#!/bin/bash
# Claude Session Manager - Interactive Multi-Terminal Support

WORKSPACE="/home/runner/workspace"
SESSIONS_DIR="${WORKSPACE}/.claude-sessions"
LOCK_DIR="/tmp/.claude-locks"

mkdir -p "${SESSIONS_DIR}" "${LOCK_DIR}" 2>/dev/null

get_terminal_id() {
    local tty_name=$(tty 2>/dev/null | sed 's|/dev/||' | tr '/' '-')
    if [ -n "$tty_name" ] && [ "$tty_name" != "not" ]; then
        echo "$tty_name"
    else
        echo "shell-$$"
    fi
}

TERMINAL_ID=$(get_terminal_id)
STATE_FILE="${SESSIONS_DIR}/${TERMINAL_ID}.json"

get_recent_sessions() {
    local history="${HOME}/.claude/history.jsonl"
    local projects_dir="${HOME}/.claude/projects/-home-runner-workspace"

    if [ -f "${history}" ]; then
        node -e "
            const fs = require('fs');
            const path = require('path');
            const historyFile = '${history}';
            const projectsDir = '${projects_dir}';
            const sessionData = new Map();
            const lines = fs.readFileSync(historyFile, 'utf8').trim().split('\n');

            for (const line of lines) {
                try {
                    const j = JSON.parse(line);
                    if (!j.sessionId) continue;
                    if (!sessionData.has(j.sessionId)) {
                        sessionData.set(j.sessionId, {
                            id: j.sessionId, firstSeen: j.timestamp, lastSeen: j.timestamp,
                            firstPrompt: j.display || '', lastPrompt: j.display || '',
                            messageCount: 0, project: j.project || ''
                        });
                    }
                    const data = sessionData.get(j.sessionId);
                    if (j.timestamp < data.firstSeen) { data.firstSeen = j.timestamp; data.firstPrompt = j.display || data.firstPrompt; }
                    if (j.timestamp > data.lastSeen) { data.lastSeen = j.timestamp; data.lastPrompt = j.display || data.lastPrompt; }
                } catch(e) {}
            }

            for (const [id, data] of sessionData) {
                const jsonlPath = path.join(projectsDir, id + '.jsonl');
                if (fs.existsSync(jsonlPath)) {
                    try {
                        const stat = fs.statSync(jsonlPath);
                        data.fileSize = stat.size;
                        data.messageCount = fs.readFileSync(jsonlPath, 'utf8').trim().split('\n').filter(l => l.trim()).length;
                    } catch(e) {}
                }
            }

            const sorted = Array.from(sessionData.values()).sort((a, b) => (b.lastSeen || 0) - (a.lastSeen || 0)).slice(0, 10);
            sorted.forEach((s, i) => {
                const formatTime = (ts) => { if (!ts) return 'unknown'; const d = new Date(ts); return d.toISOString().replace('T', ' ').substring(0, 19) + ' UTC'; };
                const timeAgo = (ts) => { if (!ts) return ''; const mins = Math.round((Date.now() - ts) / 1000 / 60); if (mins < 60) return mins + 'm ago'; if (mins < 1440) return Math.round(mins/60) + 'h ago'; return Math.round(mins/1440) + 'd ago'; };
                const sizeStr = (bytes) => { if (!bytes) return '0B'; if (bytes < 1024) return bytes + 'B'; if (bytes < 1024*1024) return (bytes/1024).toFixed(1) + 'KB'; return (bytes/1024/1024).toFixed(1) + 'MB'; };
                console.log('SESSION|' + (i+1));
                console.log('ID|' + s.id);
                console.log('MESSAGES|' + (s.messageCount || '?'));
                console.log('SIZE|' + sizeStr(s.fileSize));
                console.log('LAST_ACTIVE|' + timeAgo(s.lastSeen));
                console.log('STARTED|' + formatTime(s.firstSeen));
                console.log('FIRST_PROMPT|' + (s.firstPrompt || '').substring(0, 80).replace(/\n/g, ' ').trim());
                console.log('LAST_PROMPT|' + (s.lastPrompt || '').substring(0, 80).replace(/\n/g, ' ').trim());
                console.log('---');
            });
        " 2>/dev/null
    fi
}

show_sessions() {
    local data=$(get_recent_sessions)
    [ -z "$data" ] && echo "  No sessions found." && return
    echo "$data" | while IFS='|' read -r key value; do
        case "$key" in
            SESSION) echo ""; echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; echo "  [$value]" ;;
            ID) echo "  ID:       $value" ;;
            MESSAGES) printf "  Messages: %s" "$value" ;;
            SIZE) printf "  |  Size: %s\n" "$value" ;;
            LAST_ACTIVE) echo "  Active:   $value" ;;
            STARTED) echo "  Started:  $value" ;;
            FIRST_PROMPT) [ -n "$value" ] && echo "  First:    \"$value\"" ;;
            LAST_PROMPT) [ -n "$value" ] && echo "  Latest:   \"$value\"" ;;
        esac
    done
    echo ""
}

count_claude_instances() { pgrep -x "claude" 2>/dev/null | wc -l; }

save_session_state() {
    local session_id="$1"
    local flags="${2:---dangerously-skip-permissions}"
    mkdir -p "${SESSIONS_DIR}"
    cat > "${STATE_FILE}" << EOF
{"sessionId": "${session_id}", "flags": "${flags}", "terminalId": "${TERMINAL_ID}", "timestamp": $(date +%s)}
EOF
}

get_terminal_last_session() {
    [ -f "${STATE_FILE}" ] && node -e "try{console.log(require('${STATE_FILE}').sessionId||'')}catch(e){}" 2>/dev/null
}

claude_prompt() {
    [[ $- != *i* ]] && return 0
    command -v claude &>/dev/null || return 0

    local running=$(count_claude_instances)
    local last_session=$(get_terminal_last_session)

    echo ""
    echo "╭─────────────────────────────────────────────────────────╮"
    echo "│  Claude Session Manager                                 │"
    echo "╰─────────────────────────────────────────────────────────╯"
    [ "$running" -gt 0 ] && echo "  ($running Claude instance(s) running in other terminals)"
    echo ""
    echo "  [c] Continue last session for this terminal"
    [ -n "$last_session" ] && echo "      └─ ${last_session:0:8}..."
    echo "  [r] Resume a specific session (pick from list)"
    echo "  [n] Start new session"
    echo "  [s] Skip - just give me a shell"
    echo ""

    local choice
    read -t 30 -n 1 -p "  Choice [c/r/n/s]: " choice
    echo ""

    case "$choice" in
        c|C|"")
            if [ -n "$last_session" ]; then
                echo ""; echo "  Resuming session ${last_session:0:8}..."
                claude -r "$last_session" --dangerously-skip-permissions
                save_session_state "$(tail -1 "${HOME}/.claude/history.jsonl" 2>/dev/null | grep -oP '"sessionId":"[^"]+"' | cut -d'"' -f4)"
            else
                echo ""; echo "  No previous session, starting new..."
                claude --dangerously-skip-permissions
                save_session_state "$(tail -1 "${HOME}/.claude/history.jsonl" 2>/dev/null | grep -oP '"sessionId":"[^"]+"' | cut -d'"' -f4)"
            fi ;;
        r|R)
            echo ""; echo "  Recent Sessions"; show_sessions
            local session_ids=$(get_recent_sessions | grep "^ID|" | cut -d'|' -f2)
            read -p "  Enter number (or 'q' to cancel): " session_num
            [ "$session_num" = "q" ] || [ -z "$session_num" ] && echo "  Cancelled." && return 0
            local selected_id=$(echo "$session_ids" | sed -n "${session_num}p")
            if [ -n "$selected_id" ]; then
                echo ""; echo "  Resuming session: $selected_id"
                claude -r "$selected_id" --dangerously-skip-permissions
                save_session_state "$selected_id"
            else echo "  Invalid selection."; fi ;;
        n|N)
            echo ""; echo "  Starting new Claude session..."
            claude --dangerously-skip-permissions
            save_session_state "$(tail -1 "${HOME}/.claude/history.jsonl" 2>/dev/null | grep -oP '"sessionId":"[^"]+"' | cut -d'"' -f4)" ;;
        s|S) echo ""; echo "  Okay, just a shell. Type 'claude' or 'cr' when ready." ;;
        *) echo ""; echo "  Unknown option. Type 'claude' to start manually." ;;
    esac
}

alias cr='claude -c --dangerously-skip-permissions'
alias claude-resume='claude -c --dangerously-skip-permissions'
alias claude-pick='claude -r --dangerously-skip-permissions'
alias claude-new='claude --dangerously-skip-permissions'
alias claude-menu='claude_prompt'

export -f get_recent_sessions save_session_state
export TERMINAL_ID

[ "${CLAUDE_NO_PROMPT}" != "true" ] && claude_prompt
SCRIPT_EOF

chmod +x scripts/setup-claude-code.sh
chmod +x scripts/claude-session-manager.sh

# Create .config/bashrc
echo "📝 Creating .config/bashrc..."
cat > .config/bashrc << 'BASHRC_EOF'
#!/bin/bash
# Replit Claude Persistence - Auto-generated bashrc

# Claude Code Setup
SETUP_SCRIPT="/home/runner/workspace/scripts/setup-claude-code.sh"
[ -f "${SETUP_SCRIPT}" ] && source "${SETUP_SCRIPT}"

# Codex Persistence
CODEX_PERSISTENT="/home/runner/workspace/.codex-persistent"
mkdir -p "${CODEX_PERSISTENT}"
[ ! -L "${HOME}/.codex" ] && ln -sf "${CODEX_PERSISTENT}" "${HOME}/.codex"

# Bash History Persistence
PERSISTENT_HOME="/home/runner/workspace/.persistent-home"
mkdir -p "${PERSISTENT_HOME}"
export HISTFILE="${PERSISTENT_HOME}/.bash_history"
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTCONTROL=ignoredups
[ -f "${HISTFILE}" ] && history -r "${HISTFILE}"

# Session Manager (interactive menu)
SESSION_MANAGER="/home/runner/workspace/scripts/claude-session-manager.sh"
[ -f "${SESSION_MANAGER}" ] && source "${SESSION_MANAGER}"

# Aliases
alias cr='claude -c --dangerously-skip-permissions'
alias claude-resume='claude -c --dangerously-skip-permissions'
alias claude-pick='claude -r --dangerously-skip-permissions'
BASHRC_EOF

# Update .replit if it exists
echo "📝 Updating .replit configuration..."
if [ -f .replit ]; then
    # Check if onBoot already exists
    if ! grep -q "setup-claude-code.sh" .replit; then
        echo "" >> .replit
        echo '# Claude persistence (added by installer)' >> .replit
        echo 'onBoot = "source /home/runner/workspace/scripts/setup-claude-code.sh 2>/dev/null || true"' >> .replit
    fi
else
    cat > .replit << 'REPLIT_EOF'
# Claude persistence
onBoot = "source /home/runner/workspace/scripts/setup-claude-code.sh 2>/dev/null || true"
REPLIT_EOF
fi

echo ""
echo -e "${GREEN}✅ Installation complete!${NC}"
echo ""
echo "What happens now:"
echo "  • New shells will show the Claude session picker"
echo "  • Your conversations persist across container restarts"
echo "  • Claude binary is cached (faster startup)"
echo "  • Bash history is preserved"
echo ""
echo "To test, open a new shell or run:"
echo "  source ~/.config/bashrc"
echo ""
echo "Options:"
echo "  Press 'c' - Continue last session"
echo "  Press 'r' - Pick from session list"
echo "  Press 'n' - New session"
echo "  Press 's' - Skip (just a shell)"
echo ""
echo "To disable the menu: export CLAUDE_NO_PROMPT=true"
echo ""
