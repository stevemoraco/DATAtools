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

set -e

# Configuration
WORKSPACE="/home/runner/workspace"
CLAUDE_PERSISTENT="${CLAUDE_CONFIG_DIR:-${WORKSPACE}/.claude-persistent}"
CLAUDE_LOCAL_SHARE="${WORKSPACE}/.local/share/claude"
CLAUDE_VERSIONS="${CLAUDE_LOCAL_SHARE}/versions"
AUTH_REFRESH_SCRIPT="${WORKSPACE}/scripts/claude-auth-refresh.sh"

# Target locations (ephemeral, need symlinks)
CLAUDE_SYMLINK="${HOME}/.claude"
LOCAL_BIN="${HOME}/.local/bin"
LOCAL_SHARE_CLAUDE="${HOME}/.local/share/claude"

# Logging helper
log() {
    if [[ $- == *i* ]]; then
        echo "$1"
    fi
}

# =============================================================================
# Step 1: Ensure persistent directories exist
# =============================================================================
mkdir -p "${CLAUDE_PERSISTENT}"
mkdir -p "${CLAUDE_VERSIONS}"
mkdir -p "${LOCAL_BIN}"
mkdir -p "${HOME}/.local/share"
mkdir -p "${WORKSPACE}/logs"

# =============================================================================
# Step 2: Create ~/.claude symlink for conversation history & credentials
# =============================================================================
if [ ! -L "${CLAUDE_SYMLINK}" ] || [ "$(readlink -f "${CLAUDE_SYMLINK}")" != "${CLAUDE_PERSISTENT}" ]; then
    rm -rf "${CLAUDE_SYMLINK}" 2>/dev/null || true
    ln -sf "${CLAUDE_PERSISTENT}" "${CLAUDE_SYMLINK}"
    log "✅ Claude history symlink: ~/.claude -> ${CLAUDE_PERSISTENT}"
fi

# =============================================================================
# Step 3: Create ~/.local/share/claude symlink for installed versions
# =============================================================================
if [ ! -L "${LOCAL_SHARE_CLAUDE}" ] || [ "$(readlink -f "${LOCAL_SHARE_CLAUDE}")" != "${CLAUDE_LOCAL_SHARE}" ]; then
    rm -rf "${LOCAL_SHARE_CLAUDE}" 2>/dev/null || true
    ln -sf "${CLAUDE_LOCAL_SHARE}" "${LOCAL_SHARE_CLAUDE}"
    log "✅ Claude versions symlink: ~/.local/share/claude -> ${CLAUDE_LOCAL_SHARE}"
fi

# =============================================================================
# Step 4: Find latest Claude version and create binary symlink
# =============================================================================
LATEST_VERSION=""
if [ -d "${CLAUDE_VERSIONS}" ]; then
    LATEST_VERSION=$(ls -1 "${CLAUDE_VERSIONS}" 2>/dev/null | grep -v '^\.' | sort -V | tail -n1)
fi

if [ -n "${LATEST_VERSION}" ] && [ -f "${CLAUDE_VERSIONS}/${LATEST_VERSION}" ]; then
    CLAUDE_BINARY="${CLAUDE_VERSIONS}/${LATEST_VERSION}"

    # Create or update the binary symlink
    if [ ! -L "${LOCAL_BIN}/claude" ] || [ "$(readlink -f "${LOCAL_BIN}/claude")" != "${CLAUDE_BINARY}" ]; then
        rm -f "${LOCAL_BIN}/claude" 2>/dev/null || true
        ln -sf "${CLAUDE_BINARY}" "${LOCAL_BIN}/claude"
        log "✅ Claude binary symlink: ~/.local/bin/claude -> ${CLAUDE_BINARY}"
    fi
else
    # Claude not installed - install it
    log "⚠️  Claude Code not found, installing..."

    # Install Claude Code using the official installer
    if curl -fsSL https://claude.ai/install.sh | bash 2>/dev/null; then
        # After install, find the new version
        if [ -d "${CLAUDE_VERSIONS}" ]; then
            LATEST_VERSION=$(ls -1 "${CLAUDE_VERSIONS}" 2>/dev/null | grep -v '^\.' | sort -V | tail -n1)
            if [ -n "${LATEST_VERSION}" ]; then
                ln -sf "${CLAUDE_VERSIONS}/${LATEST_VERSION}" "${LOCAL_BIN}/claude"
                log "✅ Claude Code ${LATEST_VERSION} installed"
            fi
        fi
    else
        log "❌ Failed to install Claude Code"
        log "   Try running: curl -fsSL https://claude.ai/install.sh | bash"
    fi
fi

# =============================================================================
# Step 5: Ensure PATH includes ~/.local/bin
# =============================================================================
if [[ ":$PATH:" != *":${LOCAL_BIN}:"* ]]; then
    export PATH="${LOCAL_BIN}:$PATH"
fi

# =============================================================================
# Step 6: Auto-refresh OAuth token if needed
# =============================================================================
CREDENTIALS_FILE="${CLAUDE_PERSISTENT}/.credentials.json"
if [ -f "${CREDENTIALS_FILE}" ] && [ -f "${AUTH_REFRESH_SCRIPT}" ]; then
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
                }
            } catch(e) { console.log('error'); }
        " 2>/dev/null)

        IFS=':' read -r auth_type remaining has_refresh <<< "${AUTH_INFO}"

        if [ "${auth_type}" = "apikey" ]; then
            log "✅ Claude authentication: API key (permanent)"
        elif [ "${auth_type}" = "oauth" ]; then
            if [ "${remaining}" -le 0 ]; then
                # Token expired - try to refresh
                if [ "${has_refresh}" = "yes" ]; then
                    log "⚠️  Token expired, attempting refresh..."
                    if refresh_token 2>/dev/null; then
                        # Re-check the new expiry
                        NEW_REMAINING=$(node -e "
                            try {
                                const creds = require('${CREDENTIALS_FILE}');
                                const remaining = Math.floor((creds.claudeAiOauth.expiresAt - Date.now()) / 1000 / 60 / 60);
                                console.log(remaining);
                            } catch(e) { console.log('0'); }
                        " 2>/dev/null)
                        log "✅ Claude authentication: refreshed (${NEW_REMAINING}h remaining)"
                    else
                        log "❌ Token refresh failed - run: claude login"
                    fi
                else
                    log "❌ Token expired (no refresh token) - run: claude login"
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
        elif [ "${auth_type}" = "error" ]; then
            log "⚠️  Could not read credentials"
        fi
    fi
elif [ ! -f "${CREDENTIALS_FILE}" ]; then
    log "⚠️  No Claude credentials found. Run 'claude login' to authenticate"
    log "   💡 Tip: Run 'claude setup-token' for a long-lived token"
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
