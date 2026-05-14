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

# Get recent sessions with full details (both Claude and Codex combined, sorted by last seen)
get_recent_sessions() {
    local history="${HOME}/.claude/history.jsonl"
    local projects_dir="${HOME}/.claude/projects/-home-runner-workspace"
    local codex_sessions_dir="${HOME}/.codex/sessions"

    node -e "
        const fs = require('fs');
        const path = require('path');

        const historyFile = '${history}';
        const projectsDir = '${projects_dir}';
        const codexSessionsDir = '${codex_sessions_dir}';

        const sessionData = new Map();

        const isRealPrompt = (txt) => {
            if (!txt) return false;
            const t = txt.trim();
            if (!t) return false;
            if (/^[✅❌📦🔗⚠️🚀🎉🔧📝]/.test(t)) return false;
            if (/Claude (history|binary|versions) symlink/.test(t)) return false;
            if (t.startsWith('# AGENTS.md')) return false;
            return true;
        };

        // --- Claude sessions ---
        if (fs.existsSync(historyFile)) {
            const lines = fs.readFileSync(historyFile, 'utf8').trim().split('\n');
            const entries = [];
            for (const line of lines) {
                try {
                    const j = JSON.parse(line);
                    if (j.sessionId && j.timestamp) entries.push(j);
                } catch(e) {}
            }
            entries.sort((a, b) => a.timestamp - b.timestamp);
            for (const j of entries) {
                const key = 'claude:' + j.sessionId;
                if (!sessionData.has(key)) {
                    sessionData.set(key, {
                        tool: 'claude',
                        id: j.sessionId,
                        firstSeen: j.timestamp,
                        lastSeen: j.timestamp,
                        firstPrompt: '',
                        lastPrompt: '',
                        messageCount: 0
                    });
                }
                const data = sessionData.get(key);
                if (j.timestamp < data.firstSeen) data.firstSeen = j.timestamp;
                if (j.timestamp > data.lastSeen) data.lastSeen = j.timestamp;
                if (isRealPrompt(j.display)) {
                    if (!data.firstPrompt) data.firstPrompt = j.display;
                    data.lastPrompt = j.display;
                }
            }

            for (const [key, data] of Array.from(sessionData)) {
                if (data.tool !== 'claude') continue;
                if (!data.firstPrompt) { sessionData.delete(key); continue; }
                const jsonlPath = path.join(projectsDir, data.id + '.jsonl');
                const agentPath = path.join(projectsDir, 'agent-' + data.id.substring(0,7) + '.jsonl');
                let filePath = fs.existsSync(jsonlPath) ? jsonlPath : (fs.existsSync(agentPath) ? agentPath : null);
                if (filePath) {
                    try {
                        const stat = fs.statSync(filePath);
                        data.fileSize = stat.size;
                        const content = fs.readFileSync(filePath, 'utf8');
                        data.messageCount = content.trim().split('\n').filter(l => l.trim()).length;
                    } catch(e) {}
                }
            }
        }

        // --- Codex sessions (walk YYYY/MM/DD tree, filter to cwd) ---
        const cwd = '/home/runner/workspace';
        if (fs.existsSync(codexSessionsDir)) {
            const walk = (dir) => {
                let results = [];
                try {
                    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
                        const full = path.join(dir, entry.name);
                        if (entry.isDirectory()) results = results.concat(walk(full));
                        else if (entry.isFile() && entry.name.endsWith('.jsonl')) results.push(full);
                    }
                } catch(e) {}
                return results;
            };
            const files = walk(codexSessionsDir);
            for (const f of files) {
                try {
                    const content = fs.readFileSync(f, 'utf8');
                    const lines = content.trim().split('\n');
                    if (!lines.length) continue;

                    const meta = JSON.parse(lines[0]);
                    if (meta.type !== 'session_meta' || !meta.payload) continue;
                    if (meta.payload.cwd !== cwd) continue;

                    const id = meta.payload.id;
                    const firstTs = Date.parse(meta.payload.timestamp || meta.timestamp);

                    let lastTs = firstTs;
                    let firstPrompt = '';
                    let lastPrompt = '';
                    let msgCount = 0;
                    for (const ln of lines) {
                        try {
                            const j = JSON.parse(ln);
                            if (j.timestamp) lastTs = Math.max(lastTs, Date.parse(j.timestamp));
                            // event_msg.user_message = actual user-typed input only (no AGENTS.md, no env_context)
                            if (j.type === 'event_msg' && j.payload && j.payload.type === 'user_message') {
                                const text = (j.payload.message || '').trim();
                                if (text) {
                                    if (!firstPrompt) firstPrompt = text;
                                    lastPrompt = text;
                                    msgCount++;
                                }
                            }
                        } catch(e) {}
                    }

                    // Skip sessions with no real user-typed input
                    if (msgCount === 0 || !firstPrompt) continue;
                    // Skip sub-agent sessions: first message is an agent system prompt
                    if (/^(you are |you're |\\*\\*role\\*\\*|<role>|## role)/i.test(firstPrompt)) continue;
                    // Skip if first message is suspiciously long single-shot agent task (no follow-ups)
                    if (msgCount === 1 && firstPrompt.length > 500) continue;

                    const stat = fs.statSync(f);
                    sessionData.set('codex:' + id, {
                        tool: 'codex',
                        id,
                        firstSeen: firstTs,
                        lastSeen: lastTs,
                        firstPrompt,
                        lastPrompt,
                        messageCount: msgCount,
                        fileSize: stat.size
                    });
                } catch(e) {}
            }
        }

        // Sort by lastSeen descending
        const sorted = Array.from(sessionData.values())
            .sort((a, b) => (b.lastSeen || 0) - (a.lastSeen || 0))
            .slice(0, 10);

        const formatTime = (ts) => {
            if (!ts) return 'unknown';
            const utc = new Date(ts).toISOString().replace('T', ' ').substring(0, 19) + ' UTC';
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

        sorted.forEach((s, i) => {
            console.log('SESSION|' + (i+1));
            console.log('TOOL|' + s.tool);
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
            TOOL)
                if [ "$value" = "codex" ]; then
                    echo -e "  Tool:     \033[1;38;5;208mcodex\033[0m"
                else
                    echo -e "  Tool:     \033[1;38;5;33mclaude\033[0m"
                fi
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

# Count running Claude/Codex instances
count_claude_instances() {
    pgrep -x "claude" 2>/dev/null | wc -l
}
count_codex_instances() {
    pgrep -x "codex" 2>/dev/null | wc -l
}

# Save session state (tool = "claude" or "codex")
save_session_state() {
    local session_id="$1"
    local tool="${2:-claude}"
    mkdir -p "${SESSIONS_DIR}"
    cat > "${STATE_FILE}" << EOF
{
    "sessionId": "${session_id}",
    "tool": "${tool}",
    "terminalId": "${TERMINAL_ID}",
    "timestamp": $(date +%s)
}
EOF
}

# Get last session for this terminal (prints "<tool>|<sessionId>")
get_terminal_last_session() {
    if [ -f "${STATE_FILE}" ]; then
        node -e "try{const s=require('${STATE_FILE}');console.log((s.tool||'claude')+'|'+(s.sessionId||''))}catch(e){}" 2>/dev/null
    fi
}

# Recent sessions within configured window (max 9). Prints "NUM|TOOL|ID|AGO|SNIPPET" per line.
# Window read from ${REPLIT_TOOLS}/config.json: recentWindowHours (default 48)
get_recent_24h_sessions() {
    local history="${HOME}/.claude/history.jsonl"
    local projects_dir="${HOME}/.claude/projects/-home-runner-workspace"
    local codex_sessions_dir="${HOME}/.codex/sessions"
    local config_path="${REPLIT_TOOLS}/config.json"

    node -e "
        const fs = require('fs');
        const path = require('path');
        let hours = 48;
        try {
            if (fs.existsSync('${config_path}')) {
                const cfg = JSON.parse(fs.readFileSync('${config_path}', 'utf8'));
                if (typeof cfg.recentWindowHours === 'number' && cfg.recentWindowHours > 0) hours = cfg.recentWindowHours;
            }
        } catch(e) {}
        const cutoff = Date.now() - hours*60*60*1000;
        const cwd = '/home/runner/workspace';
        const sessions = new Map();

        // Heuristic: skip captured shell output / non-real prompts
        const isRealPrompt = (txt) => {
            if (!txt) return false;
            const t = txt.trim();
            if (!t) return false;
            // Skip messages that are obviously captured shell output
            if (/^[✅❌📦🔗⚠️🚀🎉🔧📝]/.test(t)) return false;
            if (/Claude (history|binary|versions) symlink/.test(t)) return false;
            if (t.startsWith('# AGENTS.md')) return false;
            return true;
        };

        // Claude
        const historyFile = '${history}';
        if (fs.existsSync(historyFile)) {
            const lines = fs.readFileSync(historyFile, 'utf8').trim().split('\n');
            // Sort by timestamp ascending so we can pick first real prompt per session
            const entries = [];
            for (const line of lines) {
                try {
                    const j = JSON.parse(line);
                    if (j.sessionId && j.timestamp) entries.push(j);
                } catch(e) {}
            }
            entries.sort((a, b) => a.timestamp - b.timestamp);
            for (const j of entries) {
                const key = 'claude:' + j.sessionId;
                if (!sessions.has(key)) {
                    sessions.set(key, { tool: 'claude', id: j.sessionId, firstSeen: j.timestamp, lastSeen: j.timestamp, firstPrompt: '' });
                }
                const s = sessions.get(key);
                if (j.timestamp < s.firstSeen) s.firstSeen = j.timestamp;
                if (j.timestamp > s.lastSeen) s.lastSeen = j.timestamp;
                // Set firstPrompt only on first real user prompt encountered
                if (!s.firstPrompt && isRealPrompt(j.display)) s.firstPrompt = j.display;
            }
            // Drop sessions with no real user prompt
            for (const [key, s] of Array.from(sessions)) {
                if (s.tool === 'claude' && !s.firstPrompt) sessions.delete(key);
            }
        }

        // Codex
        const codexDir = '${codex_sessions_dir}';
        if (fs.existsSync(codexDir)) {
            const walk = (d) => {
                let r = [];
                try {
                    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
                        const f = path.join(d, e.name);
                        if (e.isDirectory()) r = r.concat(walk(f));
                        else if (e.isFile() && e.name.endsWith('.jsonl')) r.push(f);
                    }
                } catch(e) {}
                return r;
            };
            for (const f of walk(codexDir)) {
                try {
                    const stat = fs.statSync(f);
                    if (stat.mtimeMs < cutoff) continue;
                    const content = fs.readFileSync(f, 'utf8');
                    const lns = content.trim().split('\n');
                    if (!lns.length) continue;
                    const meta = JSON.parse(lns[0]);
                    if (meta.type !== 'session_meta' || !meta.payload) continue;
                    if (meta.payload.cwd !== cwd) continue;
                    const id = meta.payload.id;
                    const firstTs = Date.parse(meta.payload.timestamp || meta.timestamp);

                    let lastTs = firstTs;
                    let firstPrompt = '';
                    let realMsgCount = 0;
                    for (const ln of lns) {
                        try {
                            const j = JSON.parse(ln);
                            if (j.timestamp) lastTs = Math.max(lastTs, Date.parse(j.timestamp));
                            // event_msg.user_message = actual user-typed input only
                            if (j.type === 'event_msg' && j.payload && j.payload.type === 'user_message') {
                                const text = (j.payload.message || '').trim();
                                if (text) {
                                    if (!firstPrompt) firstPrompt = text;
                                    realMsgCount++;
                                }
                            }
                        } catch(e) {}
                    }

                    // Skip sub-agent / programmatic sessions
                    if (realMsgCount === 0 || !firstPrompt) continue;
                    // Skip sub-agent sessions: first message is an agent system prompt
                    if (/^(you are |you're |\\*\\*role\\*\\*|<role>|## role)/i.test(firstPrompt)) continue;
                    if (realMsgCount === 1 && firstPrompt.length > 500) continue;

                    sessions.set('codex:' + id, { tool: 'codex', id, firstSeen: firstTs, lastSeen: lastTs, firstPrompt });
                } catch(e) {}
            }
        }

        const normTs = (t) => typeof t === 'number' ? t : (Date.parse(t) || 0);
        const snippet = (s, n = 40) => {
            const clean = (s || '').replace(/\s+/g, ' ').trim();
            return clean.length > n ? clean.slice(0, n - 1) + '…' : clean;
        };
        const ago = (ts) => {
            const mins = Math.round((Date.now() - ts) / 60000);
            if (mins < 1) return 'just now';
            if (mins < 60) return mins + 'm ago';
            const h = Math.round(mins / 60);
            return h + 'h ago';
        };
        const sorted = Array.from(sessions.values())
            .map(s => ({ ...s, lastSeen: normTs(s.lastSeen) }))
            .filter(s => s.lastSeen >= cutoff)
            .sort((a, b) => b.lastSeen - a.lastSeen)
            .slice(0, 9);

        sorted.forEach((s, i) => {
            console.log((i+1) + '|' + s.tool + '|' + s.id + '|' + ago(s.lastSeen) + '|' + snippet(s.firstPrompt, 13));
        });
    " 2>/dev/null
}

# Latest Codex session ID for this cwd (fallback when no terminal state exists)
get_latest_codex_session() {
    node -e "
        const fs = require('fs');
        const path = require('path');
        const dir = '${HOME}/.codex/sessions';
        const cwd = '/home/runner/workspace';
        if (!fs.existsSync(dir)) process.exit(0);
        const walk = (d) => {
            let r = [];
            try {
                for (const e of fs.readdirSync(d, { withFileTypes: true })) {
                    const f = path.join(d, e.name);
                    if (e.isDirectory()) r = r.concat(walk(f));
                    else if (e.isFile() && e.name.endsWith('.jsonl')) r.push(f);
                }
            } catch(e) {}
            return r;
        };
        let best = null;
        for (const f of walk(dir)) {
            try {
                const first = fs.readFileSync(f, 'utf8').split('\n', 1)[0];
                const meta = JSON.parse(first);
                if (meta.type !== 'session_meta' || !meta.payload) continue;
                if (meta.payload.cwd !== cwd) continue;
                const ts = fs.statSync(f).mtimeMs;
                if (!best || ts > best.ts) best = { id: meta.payload.id, ts };
            } catch(e) {}
        }
        if (best) console.log(best.id);
    " 2>/dev/null
}

# Run a CLI command and update session state on clean exit
run_tool_with_retry() {
    local cmd="$1"
    local session_desc="$2"
    local tool="${3:-claude}"

    echo ""
    echo "  ${session_desc}..."

    eval "$cmd"
    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        if [ "$tool" = "codex" ]; then
            local cid=$(get_latest_codex_session)
            [ -n "$cid" ] && save_session_state "$cid" "codex"
        else
            save_session_state "$(tail -1 "${HOME}/.claude/history.jsonl" 2>/dev/null | grep -oP '"sessionId":"[^"]+"' | cut -d'"' -f4)" "claude"
        fi
    fi

    return $exit_code
}

# Interactive session picker (loops until user exits to shell)
claude_prompt() {
    # Only in interactive shells
    [[ $- != *i* ]] && return 0

    # Need at least one of the tools
    local has_claude=0
    local has_codex=0
    command -v claude &>/dev/null && has_claude=1
    command -v codex &>/dev/null && has_codex=1
    if [ "$has_claude" -eq 0 ] && [ "$has_codex" -eq 0 ]; then
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
        local claude_running=$(count_claude_instances)
        local codex_running=$(count_codex_instances)
        local last_entry=$(get_terminal_last_session)
        local last_tool="${last_entry%%|*}"
        local last_session="${last_entry#*|}"
        [ "$last_tool" = "$last_entry" ] && last_tool=""

        # Colored command key (shown first)
        echo ""
        echo "  ┌─────────────────────────────┐"
        echo -e "  │ \033[95mAt \033[1;38;5;33m~/workspace\033[0;97m\$\033[95m prompt:\033[0m     │"
        echo -e "  │ \033[96mclaude-menu\033[0m = show menu     │"
        echo -e "  │ \033[96mcm\033[0m = menu shortcut          │"
        echo -e "  │ \033[96mj\033[0m  = login to claude        │"
        echo -e "  │ \033[96mk\033[0m  = login to codex         │"
        echo "  ├─────────────────────────────┤"
        echo -e "  │ \033[1;38;5;208mIn Claude:\033[0m                  │"
        echo -e "  │ \033[92mCtrl+C x2\033[0m = back to menu    │"
        echo -e "  │ \033[92mCtrl+C x3\033[0m = exit to shell   │"
        echo "  └─────────────────────────────┘"

        # Recent Sessions (last 24h) - numbered for instant resume
        local recent_24h=$(get_recent_24h_sessions)
        local recent_tools=()
        local recent_ids=()
        if [ -n "$recent_24h" ]; then
            # Read configured window for label
            local window_hours=48
            if [ -f "${REPLIT_TOOLS}/config.json" ] && command -v node &>/dev/null; then
                window_hours=$(node -e "try{const c=require('${REPLIT_TOOLS}/config.json');console.log(c.recentWindowHours||48)}catch(e){console.log(48)}" 2>/dev/null)
            fi
            local window_label
            if [ "$window_hours" -ge 8760 ]; then
                window_label="$((window_hours / 8760))y"
            elif [ "$window_hours" -ge 720 ]; then
                window_label="$((window_hours / 720))mo"
            elif [ "$window_hours" -ge 168 ]; then
                window_label="$((window_hours / 168))w"
            elif [ "$window_hours" -ge 24 ]; then
                window_label="$((window_hours / 24))d"
            else
                window_label="${window_hours}h"
            fi
            echo ""
            echo -e "  \033[1mRecent (last $window_label):\033[0m"
            while IFS='|' read -r num tool id when snippet; do
                [ -z "$num" ] && continue
                recent_tools[$num]="$tool"
                recent_ids[$num]="$id"
                local label_color="\033[1;38;5;208m"
                local label="cld"
                if [ "$tool" = "codex" ]; then
                    label_color="\033[1;38;5;44m"
                    label="cdx"
                fi
                printf "  \033[1;97m[%s]\033[0m ${label_color}%s\033[0m  \033[2m%-8s\033[0m  %s\n" "$num" "$label" "$when" "$snippet"
            done <<< "$recent_24h"
        fi

        echo ""
        echo "  ┌─────────────────────────────┐"
        echo "  │    DATA Session Manager     │"
        echo "  └─────────────────────────────┘"

        local running_note=""
        [ "$claude_running" -gt 0 ] && running_note="${claude_running} claude"
        if [ "$codex_running" -gt 0 ]; then
            [ -n "$running_note" ] && running_note="${running_note}, "
            running_note="${running_note}${codex_running} codex"
        fi
        [ -n "$running_note" ] && echo "  (${running_note} running)"
        echo ""

        # Show options
        echo "  [c] Continue last session"
        if [ -n "$last_session" ]; then
            echo "      └─ ${last_tool}:${last_session:0:8}..."
        fi
        [ -n "$recent_24h" ] && echo "  [1-9] Resume numbered above"
        echo "  [r] Resume (full list)"
        echo "  [n] New Claude session"
        echo "  [m] New Codex session"
        echo "  [j] Login to Claude"
        echo "  [k] Login to Codex"
        echo "  [s] Skip - just shell"
        echo ""

        # Read choice with timeout
        local choice
        read -t 60 -n 1 -p "  Choice: " choice
        echo ""

        case "$choice" in
            [1-9])
                local sel_tool="${recent_tools[$choice]}"
                local sel_id="${recent_ids[$choice]}"
                if [ -n "$sel_id" ]; then
                    if [ "$sel_tool" = "codex" ]; then
                        run_tool_with_retry "codex --dangerously-bypass-approvals-and-sandbox resume '$sel_id'" "Resuming codex session ${sel_id:0:8}" "codex"
                    else
                        run_tool_with_retry "claude -r '$sel_id' --dangerously-skip-permissions" "Resuming claude session ${sel_id:0:8}" "claude"
                    fi
                    echo ""
                    echo "  Exited. Returning to menu..."
                    sleep 1
                else
                    echo "  No session at position $choice."
                    sleep 1
                fi
                ;;
            c|C|"")
                # Continue whichever tool was most recent in this shell
                if [ -n "$last_session" ]; then
                    if [ "$last_tool" = "codex" ]; then
                        run_tool_with_retry "codex --dangerously-bypass-approvals-and-sandbox resume '$last_session'" "Resuming codex session ${last_session:0:8}" "codex"
                    else
                        run_tool_with_retry "claude -r '$last_session' --dangerously-skip-permissions" "Resuming claude session ${last_session:0:8}" "claude"
                    fi
                else
                    run_tool_with_retry "claude --dangerously-skip-permissions" "No previous session, starting new Claude" "claude"
                fi
                echo ""
                echo "  Exited. Returning to menu..."
                sleep 1
                ;;
            r|R)
                # Combined session list (claude + codex)
                echo ""
                echo "  Recent Sessions"
                show_sessions

                # Parallel arrays of tools and ids (index-aligned to SESSION numbers)
                local data=$(get_recent_sessions)
                local tools_list=$(echo "$data" | grep "^TOOL|" | cut -d'|' -f2)
                local ids_list=$(echo "$data" | grep "^ID|" | cut -d'|' -f2)

                read -t 60 -p "  Enter number (or 'q' to cancel): " session_num

                if [ "$session_num" = "q" ] || [ -z "$session_num" ]; then
                    echo "  Cancelled, returning to menu..."
                    continue
                fi

                local selected_tool=$(echo "$tools_list" | sed -n "${session_num}p")
                local selected_id=$(echo "$ids_list" | sed -n "${session_num}p")
                if [ -n "$selected_id" ]; then
                    if [ "$selected_tool" = "codex" ]; then
                        run_tool_with_retry "codex --dangerously-bypass-approvals-and-sandbox resume '$selected_id'" "Resuming codex session $selected_id" "codex"
                    else
                        run_tool_with_retry "claude -r '$selected_id' --dangerously-skip-permissions" "Resuming claude session $selected_id" "claude"
                    fi
                    echo ""
                    echo "  Exited. Returning to menu..."
                    sleep 1
                else
                    echo "  Invalid selection."
                fi
                ;;
            n|N)
                run_tool_with_retry "claude --dangerously-skip-permissions" "Starting new Claude session" "claude"
                echo ""
                echo "  Exited. Returning to menu..."
                sleep 1
                ;;
            m|M)
                run_tool_with_retry "codex --dangerously-bypass-approvals-and-sandbox" "Starting new Codex session" "codex"
                echo ""
                echo "  Exited. Returning to menu..."
                sleep 1
                ;;
            j|J|l|L)
                echo ""
                echo "  Starting Claude login..."
                echo ""
                rm -f "${REPLIT_TOOLS}/.auth-refresh-failed" 2>/dev/null
                claude /login --dangerously-skip-permissions
                echo ""
                echo "  Login complete. Returning to menu..."
                sleep 1
                ;;
            k|K)
                echo ""
                echo "  Starting Codex login..."
                echo ""
                codex login --device-auth
                echo ""
                echo "  Login complete. Returning to menu..."
                sleep 1
                ;;
            s|S)
                echo ""
                echo "  Okay, just a shell. Type 'claude-menu' to return here."
                return 0
                ;;
            *)
                echo ""
                echo "  Unknown option. Choose 1-9, c, r, n, m, j, k, or s."
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
alias j='claude /login --dangerously-skip-permissions'
alias claude-login='claude /login --dangerously-skip-permissions'
alias k='codex login --device-auth'
alias codex-login='codex login --device-auth'
alias codex-new='codex --dangerously-bypass-approvals-and-sandbox'
alias codex-resume='codex --dangerously-bypass-approvals-and-sandbox resume'

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
