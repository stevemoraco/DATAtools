#!/bin/bash
# =============================================================================
# Claude Code Setup Script for Replit
# =============================================================================
# This script ensures Claude Code is properly set up after container restarts.
# It handles:
#   1. Symlink for conversation history persistence (~/.claude)
#   2. Symlink for Claude binary (~/.local/bin/claude)
#   3. Authentication persistence (credentials stored in workspace)
#   4. Auto-installation if Claude is missing
#   5. Automatic OAuth token refresh before expiration
#
# Run this script on every container restart via .config/bashrc or .replit
# =============================================================================

# NOTE: Do NOT use 'set -e' here - this script is sourced into bashrc
# and any error would exit the user's shell, causing restart loops

# Configuration - use .replit-tools structure
WORKSPACE="/home/runner/workspace"
REPLIT_TOOLS="${WORKSPACE}/.replit-tools"

# Allow env vars to override (for custom config locations)
# Note: Credentials are at workspace root (.claude-persistent), NOT inside .replit-tools
CLAUDE_PERSISTENT="${CLAUDE_CONFIG_DIR:-${WORKSPACE}/.claude-persistent}"
CLAUDE_VERSIONS="${REPLIT_TOOLS}/.claude-versions"
CODEX_PERSISTENT="${CODEX_HOME:-${REPLIT_TOOLS}/.codex-persistent}"
SSH_PERSISTENT="${REPLIT_TOOLS}/.ssh-persistent"
LOGS_DIR="${REPLIT_TOOLS}/.logs"
SCRIPTS_DIR="${REPLIT_TOOLS}/scripts"
AUTH_REFRESH_SCRIPT="${SCRIPTS_DIR}/claude-auth-refresh.sh"

# Target locations (ephemeral, need symlinks)
CLAUDE_SYMLINK="${HOME}/.claude"
CODEX_SYMLINK="${HOME}/.codex"
SSH_SYMLINK="${HOME}/.ssh"
LOCAL_BIN="${HOME}/.local/bin"
LOCAL_SHARE_CLAUDE="${HOME}/.local/share/claude"

# Version file
VERSION_FILE="${REPLIT_TOOLS}/.version"
PACKAGE_NAME="data-remote"

# Force Claude re-detection: bash setup-claude-code.sh --refresh  OR  CLAUDE_FORCE_REFRESH=1
CLAUDE_FORCE_REFRESH="${CLAUDE_FORCE_REFRESH:-0}"
[ "${1:-}" = "--refresh" ] && CLAUDE_FORCE_REFRESH=1

# Logging helper - prints in interactive shells, or when run manually with --refresh
log() {
    if [[ $- == *i* ]] || [ "${CLAUDE_FORCE_REFRESH:-0}" = "1" ]; then
        echo "$1"
    fi
}

# =============================================================================
# Step 0: Show version, check for updates, and auto-update if available
# =============================================================================
auto_update_scripts() {
    local latest_ver="$1"
    local tmp_dir=$(mktemp -d)

    # Download and extract latest package (--prefer-online bypasses cache)
    if npm pack "${PACKAGE_NAME}@${latest_ver}" --pack-destination="${tmp_dir}" --prefer-online >/dev/null 2>&1; then
        local tarball="${tmp_dir}/${PACKAGE_NAME}-${latest_ver}.tgz"
        if [ -f "${tarball}" ]; then
            tar -xzf "${tarball}" -C "${tmp_dir}" 2>/dev/null

            # Copy updated scripts
            if [ -d "${tmp_dir}/package/scripts" ]; then
                cp -f "${tmp_dir}/package/scripts/"*.sh "${SCRIPTS_DIR}/" 2>/dev/null
                chmod 755 "${SCRIPTS_DIR}/"*.sh 2>/dev/null
            fi

            # Update version file
            echo "${latest_ver}" > "${VERSION_FILE}"

            rm -rf "${tmp_dir}"
            return 0
        fi
    fi

    rm -rf "${tmp_dir}" 2>/dev/null
    return 1
}

# Skip update check if we just re-sourced after an update
if [[ $- == *i* ]] && [ -z "${_REPLIT_TOOLS_UPDATED}" ]; then
    CURRENT_VERSION=""
    if [ -f "${VERSION_FILE}" ]; then
        CURRENT_VERSION=$(cat "${VERSION_FILE}" 2>/dev/null)
    fi

    if [ -n "${CURRENT_VERSION}" ]; then
        # Check for updates (with timeout, don't block shell startup)
        LATEST_VERSION=$(timeout 3 npm view "${PACKAGE_NAME}" version 2>/dev/null || echo "")

        if [ -n "${LATEST_VERSION}" ] && [ "${LATEST_VERSION}" != "${CURRENT_VERSION}" ]; then
            echo "📦 DATA Tools v${CURRENT_VERSION} → v${LATEST_VERSION}"
            echo "   ⬆️  Auto-updating..."

            if auto_update_scripts "${LATEST_VERSION}"; then
                echo "   ✅ Updated to v${LATEST_VERSION}"
                # Re-source the updated script so new code runs
                export _REPLIT_TOOLS_UPDATED=1
                source "${SCRIPTS_DIR}/setup-claude-code.sh"
                unset _REPLIT_TOOLS_UPDATED
                return 0 2>/dev/null || exit 0
            else
                echo "   ⚠️  Auto-update failed, continuing with v${CURRENT_VERSION}"
            fi
        else
            echo "📦 DATA Tools v${CURRENT_VERSION}"
        fi
    fi
elif [[ $- == *i* ]] && [ -n "${_REPLIT_TOOLS_UPDATED}" ]; then
    # Show version after re-source
    if [ -f "${VERSION_FILE}" ]; then
        echo "📦 DATA Tools v$(cat "${VERSION_FILE}" 2>/dev/null)"
    fi
fi

# =============================================================================
# Step 1: Ensure persistent directories exist
# =============================================================================
mkdir -p "${CLAUDE_PERSISTENT}"
mkdir -p "${CLAUDE_VERSIONS}"
mkdir -p "${LOCAL_BIN}"
mkdir -p "${HOME}/.local/share"
mkdir -p "${LOGS_DIR}"

# =============================================================================
# Step 2: Create ~/.claude symlink for conversation history & credentials
# =============================================================================
if [ ! -L "${CLAUDE_SYMLINK}" ] || [ "$(readlink -f "${CLAUDE_SYMLINK}")" != "${CLAUDE_PERSISTENT}" ]; then
    rm -rf "${CLAUDE_SYMLINK}" 2>/dev/null || true
    ln -sf "${CLAUDE_PERSISTENT}" "${CLAUDE_SYMLINK}"
    log "✅ Claude history symlink: ~/.claude -> ${CLAUDE_PERSISTENT}"
fi

# =============================================================================
# Step 2.5: Create ~/.codex and ~/.ssh symlinks (persistent across container restarts)
# =============================================================================
mkdir -p "${CODEX_PERSISTENT}"
if [ ! -L "${CODEX_SYMLINK}" ] || [ "$(readlink -f "${CODEX_SYMLINK}")" != "${CODEX_PERSISTENT}" ]; then
    if [ -d "${CODEX_SYMLINK}" ] && [ ! -L "${CODEX_SYMLINK}" ]; then
        cp -rn "${CODEX_SYMLINK}"/. "${CODEX_PERSISTENT}/" 2>/dev/null || true
        rm -rf "${CODEX_SYMLINK}" 2>/dev/null || true
    else
        rm -rf "${CODEX_SYMLINK}" 2>/dev/null || true
    fi
    ln -sf "${CODEX_PERSISTENT}" "${CODEX_SYMLINK}"
    log "✅ Codex symlink: ~/.codex -> ${CODEX_PERSISTENT}"
fi

mkdir -p "${SSH_PERSISTENT}"
chmod 700 "${SSH_PERSISTENT}" 2>/dev/null
if [ ! -L "${SSH_SYMLINK}" ] || [ "$(readlink -f "${SSH_SYMLINK}")" != "${SSH_PERSISTENT}" ]; then
    if [ -d "${SSH_SYMLINK}" ] && [ ! -L "${SSH_SYMLINK}" ]; then
        cp -rn "${SSH_SYMLINK}"/. "${SSH_PERSISTENT}/" 2>/dev/null || true
        rm -rf "${SSH_SYMLINK}" 2>/dev/null || true
    else
        rm -rf "${SSH_SYMLINK}" 2>/dev/null || true
    fi
    ln -sf "${SSH_PERSISTENT}" "${SSH_SYMLINK}"
    log "✅ SSH symlink: ~/.ssh -> ${SSH_PERSISTENT}"
fi
# Re-tighten SSH key permissions (SSH refuses keys with loose perms)
for f in "${SSH_PERSISTENT}"/*; do
    [ -f "$f" ] || continue
    bn=$(basename "$f")
    case "$bn" in
        known_hosts|config|*.pub) chmod 644 "$f" 2>/dev/null ;;
        *) chmod 600 "$f" 2>/dev/null ;;
    esac
done

# =============================================================================
# Step 2.6: Apply user-config persistence + sync append-only mirror archive
# =============================================================================
# Config at ${REPLIT_TOOLS}/config.json:
#   {
#     "recentWindowHours": 48,        // recent sessions list window
#     "persistenceDays": 365250,      // Claude cleanupPeriodDays + Codex history bytes
#     "mirror": { "enabled": true }   // append-only backup mirror of sessions
#   }
# The mirror is at ${REPLIT_TOOLS}/.session-archive/ — append-only: files only grow,
# never shrink. If Claude/Codex deletes a session, the mirror still has it.
if command -v node &>/dev/null; then
    PERSIST_OUTPUT=$(REPLIT_TOOLS_DIR="${REPLIT_TOOLS}" CLAUDE_PERSISTENT_DIR="${CLAUDE_PERSISTENT}" CODEX_PERSISTENT_DIR="${CODEX_PERSISTENT}" node -e '
        const fs = require("fs");
        const path = require("path");

        // Load config with defaults
        const configPath = process.env.REPLIT_TOOLS_DIR + "/config.json";
        const defaults = { recentWindowHours: 48, persistenceDays: 365250, mirror: { enabled: true } };
        let config = defaults;
        try {
            if (fs.existsSync(configPath)) {
                const loaded = JSON.parse(fs.readFileSync(configPath, "utf8"));
                config = { ...defaults, ...loaded, mirror: { ...defaults.mirror, ...(loaded.mirror || {}) } };
            } else {
                fs.writeFileSync(configPath, JSON.stringify(defaults, null, 2) + "\n");
                console.log("Created config at " + configPath);
            }
        } catch(e) { config = defaults; }

        const persistDays = Math.max(1, parseInt(config.persistenceDays, 10) || 365250);
        // Claude needs days; Codex max_bytes scales with days (rough: 1 MiB per day, min 100 MiB)
        const codexMaxBytes = Math.max(104857600, persistDays * 1048576);

        // --- Claude settings.json ---
        const claudeSettingsPath = process.env.CLAUDE_PERSISTENT_DIR + "/settings.json";
        try {
            let s = {};
            if (fs.existsSync(claudeSettingsPath)) {
                try { s = JSON.parse(fs.readFileSync(claudeSettingsPath, "utf8")); } catch(e) { s = {}; }
            }
            if (s.cleanupPeriodDays !== persistDays) {
                s.cleanupPeriodDays = persistDays;
                fs.writeFileSync(claudeSettingsPath, JSON.stringify(s, null, 2) + "\n");
                console.log("Claude cleanupPeriodDays = " + persistDays);
            }
        } catch(e) { console.error("Could not update Claude settings: " + e.message); }

        // --- Codex config.toml ---
        const codexConfigPath = process.env.CODEX_PERSISTENT_DIR + "/config.toml";
        try {
            let c = "";
            if (fs.existsSync(codexConfigPath)) c = fs.readFileSync(codexConfigPath, "utf8");
            const desired = String(codexMaxBytes);
            let updated = false;
            // Codex requires persistence field when [history] section is present
            if (!/\[history\]/.test(c)) {
                c = (c.trimEnd() + "\n\n[history]\npersistence = \"save-all\"\nmax_bytes = " + desired + "\n").trimStart();
                updated = true;
            } else {
                // Ensure persistence field exists
                if (!/(\[history\][\s\S]*?)persistence\s*=/.test(c)) {
                    c = c.replace(/\[history\](\s*)/, "[history]$1persistence = \"save-all\"\n");
                    updated = true;
                }
                // Ensure max_bytes is set correctly
                if (/max_bytes\s*=\s*(\d+)/.test(c)) {
                    const cur = c.match(/max_bytes\s*=\s*(\d+)/)[1];
                    if (cur !== desired) {
                        c = c.replace(/(\[history\][\s\S]*?max_bytes\s*=\s*)\d+/, "$1" + desired);
                        updated = true;
                    }
                } else {
                    c = c.replace(/(\[history\][\s\S]*?persistence\s*=\s*"[^"]*"\s*\n)/, "$1max_bytes = " + desired + "\n");
                    updated = true;
                }
            }
            if (updated) {
                fs.writeFileSync(codexConfigPath, c);
                console.log("Codex history.max_bytes = " + desired);
            }
        } catch(e) { console.error("Could not update Codex config: " + e.message); }

        // --- Append-only mirror sync ---
        if (config.mirror && config.mirror.enabled) {
            const mirrorBase = process.env.REPLIT_TOOLS_DIR + "/.session-archive";
            const syncTree = (srcDir, mirrorDir) => {
                if (!fs.existsSync(srcDir)) return { copied: 0, grew: 0 };
                let copied = 0, grew = 0;
                const walk = (rel) => {
                    const srcPath = rel ? path.join(srcDir, rel) : srcDir;
                    const mirrorPath = rel ? path.join(mirrorDir, rel) : mirrorDir;
                    let stat;
                    try { stat = fs.statSync(srcPath); } catch(e) { return; }
                    if (stat.isDirectory()) {
                        try { fs.mkdirSync(mirrorPath, { recursive: true }); } catch(e){}
                        let entries = [];
                        try { entries = fs.readdirSync(srcPath); } catch(e) { return; }
                        for (const e of entries) walk(rel ? path.join(rel, e) : e);
                    } else if (stat.isFile()) {
                        let mirrorSize = 0;
                        if (fs.existsSync(mirrorPath)) mirrorSize = fs.statSync(mirrorPath).size;
                        if (stat.size > mirrorSize) {
                            try {
                                fs.mkdirSync(path.dirname(mirrorPath), { recursive: true });
                                fs.copyFileSync(srcPath, mirrorPath);
                                if (mirrorSize === 0) copied++; else grew++;
                            } catch(e){}
                        }
                    }
                };
                walk("");
                return { copied, grew };
            };
            try {
                fs.mkdirSync(mirrorBase, { recursive: true });
                const c1 = syncTree(process.env.CLAUDE_PERSISTENT_DIR + "/projects", mirrorBase + "/claude/projects");
                const c2 = syncTree(process.env.CLAUDE_PERSISTENT_DIR + "/history.jsonl", mirrorBase + "/claude/history.jsonl");
                const c3 = syncTree(process.env.CODEX_PERSISTENT_DIR + "/sessions", mirrorBase + "/codex/sessions");
                const c4 = syncTree(process.env.CODEX_PERSISTENT_DIR + "/history.jsonl", mirrorBase + "/codex/history.jsonl");
                const total = c1.copied + c2.copied + c3.copied + c4.copied;
                const grew = c1.grew + c2.grew + c3.grew + c4.grew;
                if (total > 0 || grew > 0) console.log("Archive mirror: +" + total + " new, " + grew + " updated");
            } catch(e) { console.error("Mirror sync failed: " + e.message); }
        }
    ' 2>&1)
    if [ -n "${PERSIST_OUTPUT}" ]; then
        while IFS= read -r line; do log "✅ ${line}"; done <<< "${PERSIST_OUTPUT}"
    fi
fi

# =============================================================================
# Step 3: Create ~/.local/share/claude symlink for installed versions
# =============================================================================
SHARE_VERSIONS="${LOCAL_SHARE_CLAUDE}/versions"
mkdir -p "${LOCAL_SHARE_CLAUDE}"

if [ ! -L "${SHARE_VERSIONS}" ] || [ "$(readlink -f "${SHARE_VERSIONS}")" != "${CLAUDE_VERSIONS}" ]; then
    rm -rf "${SHARE_VERSIONS}" 2>/dev/null || true
    ln -sf "${CLAUDE_VERSIONS}" "${SHARE_VERSIONS}"
    log "✅ Claude versions symlink: ~/.local/share/claude/versions -> ${CLAUDE_VERSIONS}"
fi

# =============================================================================
# Step 4: Detect newest Claude binary across ALL install locations, promote it
# =============================================================================
# Bug history: npm installs claude to node_modules/@anthropic-ai/claude-code/
# which the old finder never checked, so ~/.local/bin/claude stayed pinned to an
# old .claude-versions entry while Replit's agent UI launched the newer
# node_modules binary directly. Now we scan everything, compare by real
# --version output (not filename), promote the winner, and GC stale copies.

CLAUDE_DETECT_CACHE="${CLAUDE_VERSIONS}/.detect-cache"

# Get semver by EXECUTING the binary (never trust filenames). Empty if invalid.
claude_bin_version() {
    local bin="$1"
    [ -f "$bin" ] || return 1
    local v
    v=$("$bin" --version 2>/dev/null | awk '{print $1}')
    if [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$v"; return 0
    fi
    return 1
}

# All places a Claude binary might live (npm, bun, official installer, our store)
claude_candidate_paths() {
    echo "${WORKSPACE}/node_modules/@anthropic-ai/claude-code/bin/claude.exe"
    echo "${WORKSPACE}/node_modules/.bin/claude"
    echo "${HOME}/.npm-global/bin/claude"
    echo "${HOME}/.bun/bin/claude"
    if [ -d "${HOME}/.local/share/claude/versions" ] && [ ! -L "${HOME}/.local/share/claude/versions" ]; then
        find "${HOME}/.local/share/claude/versions" -maxdepth 1 -type f 2>/dev/null
    fi
    if [ -d "${CLAUDE_VERSIONS}" ]; then
        find "${CLAUDE_VERSIONS}" -maxdepth 1 -type f ! -name '.*' 2>/dev/null
    fi
    # command -v claude, but ONLY if it does not resolve to our own managed symlink
    local cmdclaude our_target real
    cmdclaude=$(command -v claude 2>/dev/null)
    our_target=$(readlink -f "${LOCAL_BIN}/claude" 2>/dev/null)
    if [ -n "$cmdclaude" ]; then
        real=$(readlink -f "$cmdclaude" 2>/dev/null)
        [ -n "$real" ] && [ "$real" != "$our_target" ] && echo "$real"
    fi
}

# Cheap fingerprint of candidate paths (mtime+size) to short-circuit unchanged runs
claude_detect_fingerprint() {
    {
        local rp
        while IFS= read -r c; do
            [ -z "$c" ] && continue
            rp=$(readlink -f "$c" 2>/dev/null)
            [ -f "$rp" ] && stat -c '%n:%Y:%s' "$rp" 2>/dev/null
        done < <(claude_candidate_paths)
        readlink -f "${LOCAL_BIN}/claude" 2>/dev/null
    } | md5sum 2>/dev/null | awk '{print $1}'
}

# Detect newest version across all candidates, promote into .claude-versions, relink
detect_and_promote_claude() {
    local best_ver="" best_path="" seen="" rp v
    while IFS= read -r c; do
        [ -z "$c" ] && continue
        rp=$(readlink -f "$c" 2>/dev/null)
        [ -z "$rp" ] && continue
        [ -f "$rp" ] || continue
        case "$seen" in *"|${rp}|"*) continue ;; esac
        seen="${seen}|${rp}|"
        v=$(claude_bin_version "$rp") || continue
        if [ -z "$best_ver" ] || [ "$(printf '%s\n%s\n' "$best_ver" "$v" | sort -V | tail -n1)" = "$v" ]; then
            if [ "$v" != "$best_ver" ] || [ -z "$best_path" ]; then
                best_ver="$v"; best_path="$rp"
            fi
        fi
    done < <(claude_candidate_paths)

    [ -z "$best_ver" ] && return 1

    mkdir -p "${CLAUDE_VERSIONS}"
    if [ ! -f "${CLAUDE_VERSIONS}/${best_ver}" ]; then
        cp -p "${best_path}" "${CLAUDE_VERSIONS}/${best_ver}" 2>/dev/null || true
        chmod 755 "${CLAUDE_VERSIONS}/${best_ver}" 2>/dev/null || true
    fi

    local new_target="${CLAUDE_VERSIONS}/${best_ver}"
    local cur_target
    cur_target=$(readlink -f "${LOCAL_BIN}/claude" 2>/dev/null)
    if [ "$cur_target" != "$new_target" ]; then
        mkdir -p "${LOCAL_BIN}"
        ln -sfn "${new_target}" "${LOCAL_BIN}/claude"
        if [ -n "$cur_target" ] && [ -f "$cur_target" ]; then
            log "✅ Claude $(basename "$cur_target") → ${best_ver}"
        else
            log "✅ Claude ${best_ver} active (~/.local/bin/claude)"
        fi
    fi
    LATEST_VERSION="${best_ver}"
    return 0
}

# Keep only the newest 3 versions in our store (each binary is ~230 MB)
gc_claude_versions() {
    [ -d "${CLAUDE_VERSIONS}" ] || return 0
    local cur_target all count to_delete v p
    cur_target=$(readlink -f "${LOCAL_BIN}/claude" 2>/dev/null)
    all=$(find "${CLAUDE_VERSIONS}" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V)
    count=$(printf '%s\n' "$all" | grep -c .)
    [ "$count" -le 3 ] && return 0
    to_delete=$(printf '%s\n' "$all" | head -n $((count - 3)))
    for v in $to_delete; do
        p="${CLAUDE_VERSIONS}/${v}"
        [ "$(readlink -f "$p")" = "$cur_target" ] && continue
        rm -f "$p" 2>/dev/null && log "🗑️  Removed old Claude ${v}"
    done
}

# Run detection (cheap short-circuit unless paths changed or --refresh given)
run_claude_detection() {
    local fp cached cur
    fp=$(claude_detect_fingerprint)
    cached=""
    [ -f "${CLAUDE_DETECT_CACHE}" ] && cached=$(cat "${CLAUDE_DETECT_CACHE}" 2>/dev/null)

    if [ "${CLAUDE_FORCE_REFRESH}" != "1" ] && [ -n "$fp" ] && [ "$fp" = "$cached" ]; then
        cur=$(readlink -f "${LOCAL_BIN}/claude" 2>/dev/null)
        if [ -f "$cur" ]; then
            LATEST_VERSION=$(basename "$cur")
            return 0   # nothing changed since last run
        fi
    fi

    if detect_and_promote_claude; then
        gc_claude_versions
    else
        log "⚠️  Claude Code not found, installing..."
        if curl -fsSL https://claude.ai/install.sh | bash 2>/dev/null; then
            detect_and_promote_claude && gc_claude_versions
        else
            log "❌ Failed to install Claude Code"
            log "   Try running: curl -fsSL https://claude.ai/install.sh | bash"
        fi
    fi
    # Persist post-promotion fingerprint so the next shell short-circuits
    claude_detect_fingerprint > "${CLAUDE_DETECT_CACHE}" 2>/dev/null
}

run_claude_detection

# =============================================================================
# Step 5: Ensure PATH includes ~/.local/bin
# =============================================================================
if [[ ":$PATH:" != *":${LOCAL_BIN}:"* ]]; then
    export PATH="${LOCAL_BIN}:$PATH"
fi

# =============================================================================
# Step 6: Auto-refresh OAuth token if needed (with loop prevention)
# =============================================================================
CREDENTIALS_FILE="${CLAUDE_PERSISTENT}/.credentials.json"
AUTH_FAILED_MARKER="${REPLIT_TOOLS}/.auth-refresh-failed"

# Clear failed marker if it's more than 1 hour old (allow retry after cooldown)
if [ -f "${AUTH_FAILED_MARKER}" ]; then
    marker_age=$(( $(date +%s) - $(stat -c %Y "${AUTH_FAILED_MARKER}" 2>/dev/null || echo "0") ))
    if [ "${marker_age}" -gt 3600 ]; then
        rm -f "${AUTH_FAILED_MARKER}" 2>/dev/null
    fi
fi

# Skip auth refresh if we already failed recently (file-based lock prevents loops)
if [ ! -f "${AUTH_FAILED_MARKER}" ] && [ -f "${CREDENTIALS_FILE}" ] && [ -f "${AUTH_REFRESH_SCRIPT}" ]; then
        # Source the auth refresh script to get the function
        source "${AUTH_REFRESH_SCRIPT}"

        # Check and refresh if needed (this handles all the logic)
        if command -v node &> /dev/null; then
            AUTH_INFO=$(node -e "
                try {
                    const creds = require('${CREDENTIALS_FILE}');
                    const oauth = creds.claudeAiOauth;
                    const apiKey = creds.primaryApiKey;
                    if (apiKey) {
                        console.log('apikey:permanent');
                    } else if (oauth && oauth.expiresAt) {
                        const now = Date.now();
                        const remaining = Math.floor((oauth.expiresAt - now) / 1000 / 60 / 60);
                        const hasRefresh = oauth.refreshToken ? 'yes' : 'no';
                        console.log('oauth:' + remaining + ':' + hasRefresh);
                    } else {
                        console.log('none');
                    }
                } catch(e) { console.log('error'); }
            " 2>/dev/null)

            IFS=':' read -r auth_type remaining has_refresh <<< "${AUTH_INFO}"

            if [ "${auth_type}" = "apikey" ]; then
                log "✅ Claude authentication: API key (permanent)"
            elif [ "${auth_type}" = "oauth" ]; then
                if [ "${remaining}" -le 0 ]; then
                    # Token expired - try to refresh once
                    if [ "${has_refresh}" = "yes" ]; then
                        log "⚠️  Token expired, attempting refresh..."
                        if refresh_token 2>/dev/null; then
                            NEW_REMAINING=$(node -e "
                                try {
                                    const creds = require('${CREDENTIALS_FILE}');
                                    const remaining = Math.floor((creds.claudeAiOauth.expiresAt - Date.now()) / 1000 / 60 / 60);
                                    console.log(remaining);
                                } catch(e) { console.log('0'); }
                            " 2>/dev/null)
                            log "✅ Claude authentication: refreshed (${NEW_REMAINING}h remaining)"
                        else
                            log "❌ Token refresh failed - run 'claude login' when ready"
                            touch "${AUTH_FAILED_MARKER}"
                        fi
                    else
                        log "❌ Token expired (no refresh token) - run 'claude login' when ready"
                        touch "${AUTH_FAILED_MARKER}"
                    fi
                elif [ "${remaining}" -lt 2 ]; then
                    # Less than 2 hours - refresh proactively
                    if [ "${has_refresh}" = "yes" ]; then
                        log "🔄 Token expires in ${remaining}h, refreshing..."
                        if refresh_token 2>/dev/null; then
                            NEW_REMAINING=$(node -e "
                                try {
                                    const creds = require('${CREDENTIALS_FILE}');
                                    const remaining = Math.floor((creds.claudeAiOauth.expiresAt - Date.now()) / 1000 / 60 / 60);
                                    console.log(remaining);
                                } catch(e) { console.log('0'); }
                            " 2>/dev/null)
                            log "✅ Claude authentication: refreshed (${NEW_REMAINING}h remaining)"
                        else
                            log "⚠️  Refresh failed, ${remaining}h remaining"
                        fi
                    else
                        log "⚠️  Claude authentication: ${remaining}h remaining (no refresh token)"
                    fi
                else
                    log "✅ Claude authentication: valid (${remaining}h remaining)"
                fi
            elif [ "${auth_type}" = "none" ] || [ "${auth_type}" = "error" ]; then
                log "⚠️  No valid auth - run 'claude login' when ready"
            fi
        fi
elif [ -f "${AUTH_FAILED_MARKER}" ]; then
    log "⏭️  Skipping auth check (refresh failed recently, retry in 1h or run 'claude login')"
elif [ ! -f "${CREDENTIALS_FILE}" ]; then
    log "⚠️  No credentials - run 'claude login' when ready"
fi

# =============================================================================
# Summary (only in interactive shells)
# =============================================================================
if [[ $- == *i* ]] && [ -n "${LATEST_VERSION}" ]; then
    if command -v claude &> /dev/null; then
        CLAUDE_VERSION=$(claude --version 2>/dev/null | head -1)
        log "✅ Claude Code ready: ${CLAUDE_VERSION}"
    fi
fi
