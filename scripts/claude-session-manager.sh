#!/bin/bash
# =============================================================================
# Claude Session Manager - Interactive Multi-Terminal Support
# =============================================================================
# Prompts user to choose: resume a session, start new, or skip.
# Supports multiple terminals with independent session tracking.
# =============================================================================

WORKSPACE="/home/runner/workspace"
SESSIONS_DIR="${WORKSPACE}/.claude-sessions"
LOCK_DIR="/tmp/.claude-locks"

mkdir -p "${SESSIONS_DIR}" "${LOCK_DIR}" 2>/dev/null

# Get terminal identifier
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

# Get recent sessions with full details
get_recent_sessions() {
    local history="${HOME}/.claude/history.jsonl"
    local projects_dir="${HOME}/.claude/projects/-home-runner-workspace"

    if [ -f "${history}" ]; then
        # Collect all session data with full metadata
        node -e "
            const fs = require('fs');
            const path = require('path');
            const readline = require('readline');

            const historyFile = '${history}';
            const projectsDir = '${projects_dir}';

            const sessionData = new Map();

            // Read history to get session metadata
            const lines = fs.readFileSync(historyFile, 'utf8').trim().split('\n');

            for (const line of lines) {
                try {
                    const j = JSON.parse(line);
                    if (!j.sessionId) continue;

                    if (!sessionData.has(j.sessionId)) {
                        sessionData.set(j.sessionId, {
                            id: j.sessionId,
                            firstSeen: j.timestamp,
                            lastSeen: j.timestamp,
                            firstPrompt: j.display || '',
                            lastPrompt: j.display || '',
                            messageCount: 0,
                            project: j.project || ''
                        });
                    }

                    const data = sessionData.get(j.sessionId);
                    if (j.timestamp < data.firstSeen) {
                        data.firstSeen = j.timestamp;
                        data.firstPrompt = j.display || data.firstPrompt;
                    }
                    if (j.timestamp > data.lastSeen) {
                        data.lastSeen = j.timestamp;
                        data.lastPrompt = j.display || data.lastPrompt;
                    }
                } catch(e) {}
            }

            // Enrich with .jsonl file data (message counts, file sizes)
            for (const [id, data] of sessionData) {
                const jsonlPath = path.join(projectsDir, id + '.jsonl');
                const agentPath = path.join(projectsDir, 'agent-' + id.substring(0,7) + '.jsonl');

                let filePath = null;
                let fileSize = 0;

                if (fs.existsSync(jsonlPath)) {
                    filePath = jsonlPath;
                } else if (fs.existsSync(agentPath)) {
                    filePath = agentPath;
                }

                if (filePath) {
                    try {
                        const stat = fs.statSync(filePath);
                        fileSize = stat.size;
                        const content = fs.readFileSync(filePath, 'utf8');
                        const msgLines = content.trim().split('\n').filter(l => l.trim());
                        data.messageCount = msgLines.length;
                        data.fileSize = fileSize;
                        data.filePath = filePath;
                    } catch(e) {}
                }
            }

            // Sort by lastSeen descending and output
            const sorted = Array.from(sessionData.values())
                .sort((a, b) => (b.lastSeen || 0) - (a.lastSeen || 0))
                .slice(0, 10);

            sorted.forEach((s, i) => {
                const formatTime = (ts) => {
                    if (!ts) return 'unknown';
                    const d = new Date(ts);
                    const utc = d.toISOString().replace('T', ' ').substring(0, 19) + ' UTC';
                    // MST is UTC-7
                    const mst = new Date(ts - 7*60*60*1000).toISOString().replace('T', ' ').substring(0, 19) + ' MST';
                    return utc + ' / ' + mst;
                };

                const timeAgo = (ts) => {
                    if (!ts) return '';
                    const mins = Math.round((Date.now() - ts) / 1000 / 60);
                    if (mins < 60) return mins + 'm ago';
                    if (mins < 1440) return Math.round(mins/60) + 'h ago';
                    return Math.round(mins/1440) + 'd ago';
                };

                const sizeStr = (bytes) => {
                    if (!bytes) return '0B';
                    if (bytes < 1024) return bytes + 'B';
                    if (bytes < 1024*1024) return (bytes/1024).toFixed(1) + 'KB';
                    return (bytes/1024/1024).toFixed(1) + 'MB';
                };

                console.log('SESSION|' + (i+1));
                console.log('ID|' + s.id);
                console.log('MESSAGES|' + (s.messageCount || '?'));
                console.log('SIZE|' + sizeStr(s.fileSize));
                console.log('LAST_ACTIVE|' + timeAgo(s.lastSeen));
                console.log('STARTED|' + formatTime(s.firstSeen));
                console.log('LAST_SEEN|' + formatTime(s.lastSeen));
                console.log('FIRST_PROMPT|' + (s.firstPrompt || '').substring(0, 80).replace(/\\n/g, ' ').trim());
                console.log('LAST_PROMPT|' + (s.lastPrompt || '').substring(0, 80).replace(/\\n/g, ' ').trim());
                console.log('---');
            });
        " 2>/dev/null
    fi
}

# Display formatted session list
show_sessions() {
    local data=$(get_recent_sessions)
    if [ -z "$data" ]; then
        echo "  No sessions found."
        return
    fi

    local current_num=""

    echo "$data" | while IFS='|' read -r key value; do
        case "$key" in
            SESSION)
                current_num="$value"
                echo ""
                echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo "  [$value]"
                ;;
            ID)
                echo "  ID:       $value"
                ;;
            MESSAGES)
                printf "  Messages: %s" "$value"
                ;;
            SIZE)
                printf "  |  Size: %s\n" "$value"
                ;;
            LAST_ACTIVE)
                echo "  Active:   $value"
                ;;
            STARTED)
                echo "  Started:  $value"
                ;;
            LAST_SEEN)
                echo "  Last:     $value"
                ;;
            FIRST_PROMPT)
                if [ -n "$value" ]; then
                    echo "  First:    \"$value\""
                fi
                ;;
            LAST_PROMPT)
                if [ -n "$value" ]; then
                    echo "  Latest:   \"$value\""
                fi
                ;;
        esac
    done
    echo ""
}

# Count running Claude instances
count_claude_instances() {
    pgrep -x "claude" 2>/dev/null | wc -l
}

# Save session state
save_session_state() {
    local session_id="$1"
    local flags="${2:---dangerously-skip-permissions}"
    mkdir -p "${SESSIONS_DIR}"
    cat > "${STATE_FILE}" << EOF
{
    "sessionId": "${session_id}",
    "flags": "${flags}",
    "terminalId": "${TERMINAL_ID}",
    "timestamp": $(date +%s)
}
EOF
}

# Get last session for this terminal
get_terminal_last_session() {
    if [ -f "${STATE_FILE}" ]; then
        node -e "try{console.log(require('${STATE_FILE}').sessionId||'')}catch(e){}" 2>/dev/null
    fi
}

# Interactive session picker
claude_prompt() {
    # Only in interactive shells
    [[ $- != *i* ]] && return 0

    # Check if claude exists
    if ! command -v claude &>/dev/null; then
        return 0
    fi

    local running=$(count_claude_instances)
    local last_session=$(get_terminal_last_session)

    echo ""
    echo "╭─────────────────────────────────────────────────────────╮"
    echo "│  Claude Session Manager                                 │"
    echo "╰─────────────────────────────────────────────────────────╯"

    if [ "$running" -gt 0 ]; then
        echo "  ($running Claude instance(s) running in other terminals)"
    fi
    echo ""

    # Show options
    echo "  [c] Continue last session for this terminal"
    if [ -n "$last_session" ]; then
        echo "      └─ ${last_session:0:8}..."
    fi
    echo "  [r] Resume a specific session (pick from list)"
    echo "  [n] Start new session"
    echo "  [s] Skip - just give me a shell"
    echo ""

    # Read choice with timeout
    local choice
    read -t 30 -n 1 -p "  Choice [c/r/n/s]: " choice
    echo ""

    case "$choice" in
        c|C|"")
            # Continue last session (default on Enter or timeout)
            if [ -n "$last_session" ]; then
                echo ""
                echo "  Resuming session ${last_session:0:8}..."
                claude -r "$last_session" --dangerously-skip-permissions
                save_session_state "$(tail -1 "${HOME}/.claude/history.jsonl" 2>/dev/null | grep -oP '"sessionId":"[^"]+"' | cut -d'"' -f4)"
            else
                echo ""
                echo "  No previous session for this terminal, starting new..."
                claude --dangerously-skip-permissions
                save_session_state "$(tail -1 "${HOME}/.claude/history.jsonl" 2>/dev/null | grep -oP '"sessionId":"[^"]+"' | cut -d'"' -f4)"
            fi
            ;;
        r|R)
            # Show session list with full details
            echo ""
            echo "  Recent Sessions"
            show_sessions

            # Get session IDs for selection
            local session_ids=$(get_recent_sessions | grep "^ID|" | cut -d'|' -f2)

            read -p "  Enter number (or 'q' to cancel): " session_num

            if [ "$session_num" = "q" ] || [ -z "$session_num" ]; then
                echo "  Cancelled."
                return 0
            fi

            local selected_id=$(echo "$session_ids" | sed -n "${session_num}p")
            if [ -n "$selected_id" ]; then
                echo ""
                echo "  Resuming session: $selected_id"
                claude -r "$selected_id" --dangerously-skip-permissions
                save_session_state "$selected_id"
            else
                echo "  Invalid selection."
            fi
            ;;
        n|N)
            # Start new session
            echo ""
            echo "  Starting new Claude session..."
            claude --dangerously-skip-permissions
            save_session_state "$(tail -1 "${HOME}/.claude/history.jsonl" 2>/dev/null | grep -oP '"sessionId":"[^"]+"' | cut -d'"' -f4)"
            ;;
        s|S)
            # Skip - just shell
            echo ""
            echo "  Okay, just a shell. Type 'claude' or 'cr' when you want Claude."
            ;;
        *)
            echo ""
            echo "  Unknown option. Type 'claude' to start manually."
            ;;
    esac
}

# Aliases for manual use
alias cr='claude -c --dangerously-skip-permissions'
alias claude-resume='claude -c --dangerously-skip-permissions'
alias claude-pick='claude -r --dangerously-skip-permissions'
alias claude-new='claude --dangerously-skip-permissions'

# Export for manual use
export -f get_recent_sessions
export -f save_session_state
export TERMINAL_ID

# Show the interactive prompt by default.
# Press 's' to skip and just get a shell.
# Set CLAUDE_NO_PROMPT=true to disable entirely.

alias claude-menu='claude_prompt'

if [ "${CLAUDE_NO_PROMPT}" != "true" ]; then
    claude_prompt
fi
