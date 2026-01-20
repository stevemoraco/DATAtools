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
#
# Run this script on every container restart via .config/bashrc or .replit
# =============================================================================

set -e

# Configuration
WORKSPACE="/home/runner/workspace"
CLAUDE_PERSISTENT="${WORKSPACE}/.claude-persistent"
CLAUDE_LOCAL_SHARE="${WORKSPACE}/.local/share/claude"
CLAUDE_VERSIONS="${CLAUDE_LOCAL_SHARE}/versions"

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
    LATEST_VERSION=$(ls -1 "${CLAUDE_VERSIONS}" 2>/dev/null | sort -V | tail -n1)
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

    # Install Claude Code using npm
    if command -v npm &> /dev/null; then
        npm install -g @anthropic-ai/claude-code 2>/dev/null || {
            log "❌ Failed to install Claude Code via npm"
            log "   Try running: npm install -g @anthropic-ai/claude-code"
        }

        # After npm install, the binary should be available
        # Move it to our persistent location
        if command -v claude &> /dev/null; then
            INSTALLED_PATH=$(which claude)
            if [ -f "${INSTALLED_PATH}" ] && [ ! -L "${INSTALLED_PATH}" ]; then
                # Get version
                VERSION=$(claude --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)
                if [ -n "${VERSION}" ]; then
                    cp "${INSTALLED_PATH}" "${CLAUDE_VERSIONS}/${VERSION}"
                    chmod +x "${CLAUDE_VERSIONS}/${VERSION}"
                    rm -f "${LOCAL_BIN}/claude" 2>/dev/null || true
                    ln -sf "${CLAUDE_VERSIONS}/${VERSION}" "${LOCAL_BIN}/claude"
                    log "✅ Claude Code ${VERSION} installed and persisted"
                fi
            fi
        fi
    else
        log "❌ npm not found, cannot install Claude Code"
    fi
fi

# =============================================================================
# Step 5: Ensure PATH includes ~/.local/bin
# =============================================================================
if [[ ":$PATH:" != *":${LOCAL_BIN}:"* ]]; then
    export PATH="${LOCAL_BIN}:$PATH"
fi

# =============================================================================
# Step 6: Verify authentication
# =============================================================================
CREDENTIALS_FILE="${CLAUDE_PERSISTENT}/.credentials.json"
if [ -f "${CREDENTIALS_FILE}" ]; then
    # Check if credentials are valid (not expired)
    if command -v node &> /dev/null; then
        AUTH_INFO=$(node -e "
            try {
                const creds = require('${CREDENTIALS_FILE}');
                const oauth = creds.claudeAiOauth;
                const apiKey = creds.primaryApiKey;
                if (apiKey) {
                    // Long-lived API key - doesn't expire
                    console.log('apikey');
                } else if (oauth && oauth.expiresAt) {
                    console.log(oauth.expiresAt);
                }
            } catch(e) {}
        " 2>/dev/null)

        if [ "${AUTH_INFO}" = "apikey" ]; then
            log "✅ Claude authentication: long-lived token (no expiration)"
        elif [ -n "${AUTH_INFO}" ]; then
            CURRENT_TIME=$(node -e "console.log(Date.now())" 2>/dev/null)
            if [ -n "${CURRENT_TIME}" ] && [ "${AUTH_INFO}" -gt "${CURRENT_TIME}" ]; then
                # Calculate time remaining
                HOURS_LEFT=$(node -e "console.log(Math.floor((${AUTH_INFO} - ${CURRENT_TIME}) / 1000 / 60 / 60))" 2>/dev/null)
                if [ "${HOURS_LEFT}" -lt 2 ]; then
                    log "⚠️  Claude authentication: expires in ${HOURS_LEFT}h - run 'claude login' soon"
                else
                    log "✅ Claude authentication: valid (${HOURS_LEFT}h remaining)"
                fi
            else
                log "⚠️  Claude authentication: expired, run 'claude login' to re-authenticate"
                log "   💡 Tip: Run 'claude setup-token' for a long-lived token that won't expire"
            fi
        fi
    else
        log "✅ Claude credentials file exists (persisted in workspace)"
    fi
else
    log "⚠️  No Claude credentials found. Run 'claude login' to authenticate"
    log "   💡 Tip: Run 'claude setup-token' for a long-lived token that won't expire"
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
