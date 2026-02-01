#!/bin/bash
# =============================================================================
# Claude Session Manager - Interactive Multi-Terminal Support
# =============================================================================
# Prompts user to choose: resume a session, start new, or skip.
# Supports multiple terminals with independent session tracking.
# =============================================================================

WORKSPACE="/home/runner/workspace"
REPLIT_TOOLS="${WORKSPACE}/.replit-tools"
SESSIONS_DIR="${REPLIT_TOOLS}/.claude-sessions"
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
                echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━"
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

# Run Claude and handle exit codes (returns to menu on failure)
run_claude_with_retry() {
    local cmd="$1"
    local session_desc="$2"

    echo ""
    echo "  ${session_desc}..."

    # Run Claude
    eval "$cmd"
    local exit_code=$?

    # Save session state on success
    if [ $exit_code -eq 0 ]; then
        save_session_state "$(tail -1 "${HOME}/.claude/history.jsonl" 2>/dev/null | grep -oP '"sessionId":"[^"]+"' | cut -d'"' -f4)"
    fi

    return $exit_code
}

# Interactive session picker (loops until user exits to shell)
claude_prompt() {
    # Only in interactive shells
    [[ $- != *i* ]] && return 0

    # Check if claude exists
    if ! command -v claude &>/dev/null; then
        return 0
    fi

    # LOOP PREVENTION: Track if we've already prompted this terminal session
    # Include the shell PID so new shells always get the menu
    local prompt_marker="${REPLIT_TOOLS}/.prompt-active-${TERMINAL_ID}-$$"

    # Clean up old markers from crashed/closed shells
    # Remove markers older than 1 hour or from PIDs that no longer exist
    find "${REPLIT_TOOLS}" -name ".prompt-active-*" -mmin +60 -delete 2>/dev/null
    for marker in "${REPLIT_TOOLS}"/.prompt-active-*; do
        if [ -f "$marker" ]; then
            local marker_pid=$(basename "$marker" | rev | cut -d'-' -f1 | rev)
            if [ -n "$marker_pid" ] && ! kill -0 "$marker_pid" 2>/dev/null; then
                rm -f "$marker" 2>/dev/null
            fi
        fi
    done

    # If THIS shell already showed the prompt, skip (prevents re-sourcing issues)
    if [ -f "$prompt_marker" ]; then
        return 0
    fi

    # Mark that we're showing the prompt for THIS shell session
    touch "$prompt_marker" 2>/dev/null

    # Cleanup function to remove marker when shell exits
    trap "rm -f '$prompt_marker' 2>/dev/null" EXIT

    # Main menu loop - keeps showing until user chooses shell
    while true; do
        local running=$(count_claude_instances)
        local last_session=$(get_terminal_last_session)

        # Colored command key (shown first)
        echo ""
        echo "  ┌─────────────────────────────┐"
        echo -e "  │ \033[95mAt \033[94m~/workspace\033[1;97m\$\033[0;95m prompt:\033[0m     │"
        echo -e "  │ \033[96mclaude-menu\033[0m = show menu     │"
        echo -e "  │ \033[96mcm\033[0m = menu shortcut          │"
        echo -e "  │ \033[96ml\033[0m  = login to claude        │"
        echo "  ├─────────────────────────────┤"
        echo -e "  │ \033[1;38;5;208mIn Claude:\033[0m                  │"
        echo -e "  │ \033[92mCtrl+C x2\033[0m = back to menu    │"
        echo -e "  │ \033[92mCtrl+C x3\033[0m = exit to shell   │"
        echo "  └─────────────────────────────┘"

        echo ""
        echo "  ┌─────────────────────────────┐"
        echo "  │   Claude Session Manager    │"
        echo "  └─────────────────────────────┘"

        if [ "$running" -gt 0 ]; then
            echo "  ($running running)"
        fi
        echo ""

        # Show options
        echo "  [c] Continue last session"
        if [ -n "$last_session" ]; then
            echo "      └─ ${last_session:0:8}..."
        fi
        echo "  [r] Resume (pick from list)"
        echo "  [n] Start new session"
        echo "  [l] Login to Claude"
        echo "  [s] Skip - just shell"
        echo ""

        # Read choice with timeout
        local choice
        read -t 60 -n 1 -p "  Choice [c/r/n/l/s]: " choice
        echo ""

        case "$choice" in
            c|C|"")
                # Continue last session (default on Enter or timeout)
                if [ -n "$last_session" ]; then
                    run_claude_with_retry "claude -r '$last_session' --dangerously-skip-permissions" "Resuming session ${last_session:0:8}"
                else
                    run_claude_with_retry "claude --dangerously-skip-permissions" "No previous session, starting new"
                fi
                # After Claude exits, loop back to menu
                echo ""
                echo "  Claude exited. Returning to menu..."
                sleep 1
                ;;
            r|R)
                # Show session list with full details
                echo ""
                echo "  Recent Sessions"
                show_sessions

                # Get session IDs for selection
                local session_ids=$(get_recent_sessions | grep "^ID|" | cut -d'|' -f2)

                read -t 60 -p "  Enter number (or 'q' to cancel): " session_num

                if [ "$session_num" = "q" ] || [ -z "$session_num" ]; then
                    echo "  Cancelled, returning to menu..."
                    continue
                fi

                local selected_id=$(echo "$session_ids" | sed -n "${session_num}p")
                if [ -n "$selected_id" ]; then
                    run_claude_with_retry "claude -r '$selected_id' --dangerously-skip-permissions" "Resuming session $selected_id"
                    echo ""
                    echo "  Claude exited. Returning to menu..."
                    sleep 1
                else
                    echo "  Invalid selection."
                fi
                ;;
            n|N)
                # Start new session
                run_claude_with_retry "claude --dangerously-skip-permissions" "Starting new Claude session"
                echo ""
                echo "  Claude exited. Returning to menu..."
                sleep 1
                ;;
            l|L)
                # Login to Claude
                echo ""
                echo "  Starting Claude login..."
                echo ""

                # Clear the auth failed marker so setup script will retry
                rm -f "${REPLIT_TOOLS}/.auth-refresh-failed" 2>/dev/null

                claude /login --dangerously-skip-permissions

                echo ""
                echo "  Login complete. Returning to menu..."
                sleep 1
                ;;
            s|S)
                # Skip - just shell
                echo ""
                echo "  Okay, just a shell. Type 'claude-menu' to return here."
                # Keep the marker so re-sourcing bashrc won't re-show menu
                # The trap will clean it up when shell exits
                return 0
                ;;
            *)
                echo ""
                echo "  Unknown option. Please choose c, r, n, l, or s."
                sleep 1
                ;;
        esac
    done
}

# Aliases for manual use
alias cr='claude -c --dangerously-skip-permissions'
alias claude-resume='claude -c --dangerously-skip-permissions'
alias claude-pick='claude -r --dangerously-skip-permissions'
alias claude-new='claude --dangerously-skip-permissions'
alias l='claude /login --dangerously-skip-permissions'
alias claude-login='claude /login --dangerously-skip-permissions'

# Export for manual use
export -f get_recent_sessions
export -f save_session_state
export TERMINAL_ID

# Show the interactive prompt by default.
# Press 's' to skip and just get a shell.
# Set CLAUDE_NO_PROMPT=true to disable entirely.

# Reset prompt marker and show menu
claude_menu() {
    # Clear the marker that claude_prompt uses to prevent re-showing
    # This allows manual invocation to always show the menu
    local prompt_marker="${REPLIT_TOOLS}/.prompt-active-${TERMINAL_ID}-$$"
    rm -f "$prompt_marker" 2>/dev/null
    # Also clear any old-style markers for this terminal
    rm -f "${REPLIT_TOOLS}/.prompt-shown-${TERMINAL_ID}" 2>/dev/null
    rm -f "${REPLIT_TOOLS}/.prompt-active-${TERMINAL_ID}-"* 2>/dev/null
    claude_prompt
}
alias claude-menu='claude_menu'
alias cm='claude_menu'

# Auto-show menu when sourced (unless disabled)
[ "${CLAUDE_NO_PROMPT}" != "true" ] && claude_prompt

# NOTE: aliases defined above AFTER this script is sourced
# This ensures all aliases are defined even if user Ctrl+C's out of the prompt
