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

# Configuration - use .replit-tools structure
WORKSPACE="/home/runner/workspace"
REPLIT_TOOLS="${WORKSPACE}/.replit-tools"

# Allow env vars to override (for custom config locations)
CLAUDE_PERSISTENT="${CLAUDE_CONFIG_DIR:-${REPLIT_TOOLS}/.claude-persistent}"
CLAUDE_VERSIONS="${REPLIT_TOOLS}/.claude-versions"
LOGS_DIR="${REPLIT_TOOLS}/.logs"
SCRIPTS_DIR="${REPLIT_TOOLS}/scripts"
AUTH_REFRESH_SCRIPT="${SCRIPTS_DIR}/claude-auth-refresh.sh"

# Target locations (ephemeral, need symlinks)
CLAUDE_SYMLINK="${HOME}/.claude"
LOCAL_BIN="${HOME}/.local/bin"
LOCAL_SHARE_CLAUDE="${HOME}/.local/share/claude"

# Version file
VERSION_FILE="${REPLIT_TOOLS}/.version"
PACKAGE_NAME="replit-tools"

# Logging helper
log() {
    if [[ $- == *i* ]]; then
        echo "$1"
    fi
}

# =============================================================================
# Step 0: Show version, check for updates, and auto-update if available
# =============================================================================
auto_update_scripts() {
    local latest_ver="$1"
    local tmp_dir=$(mktemp -d)

    # Download and extract latest package
    if npm pack "${PACKAGE_NAME}@${latest_ver}" --pack-destination="${tmp_dir}" >/dev/null 2>&1; then
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

if [[ $- == *i* ]]; then
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
            else
                echo "   ⚠️  Auto-update failed, continuing with v${CURRENT_VERSION}"
            fi
        else
            echo "📦 DATA Tools v${CURRENT_VERSION}"
        fi
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
# Step 4: Find latest Claude version and create binary symlink
# =============================================================================

# Check multiple locations for Claude binary (handles race conditions on container restart)
find_claude_binary() {
    local found_binary=""
    local found_version=""

    # Priority 1: Our persistent versions directory
    if [ -d "${CLAUDE_VERSIONS}" ]; then
        local ver=$(ls -1 "${CLAUDE_VERSIONS}" 2>/dev/null | grep -v '^\.' | sort -V | tail -n1)
        if [ -n "${ver}" ] && [ -f "${CLAUDE_VERSIONS}/${ver}" ]; then
            found_binary="${CLAUDE_VERSIONS}/${ver}"
            found_version="${ver}"
        fi
    fi

    # Priority 2: Check if claude command already works (might be from previous install)
    if [ -z "${found_binary}" ]; then
        local existing_claude=$(command -v claude 2>/dev/null)
        if [ -n "${existing_claude}" ] && [ -x "${existing_claude}" ]; then
            # Follow symlinks to find actual binary
            local real_path=$(readlink -f "${existing_claude}" 2>/dev/null)
            if [ -f "${real_path}" ]; then
                found_binary="${real_path}"
                found_version=$(basename "${real_path}")
            fi
        fi
    fi

    # Priority 3: Default install location (not through our symlink)
    if [ -z "${found_binary}" ]; then
        local default_loc="${HOME}/.local/share/claude/versions"
        # Check if this is a real directory, not our symlink
        if [ -d "${default_loc}" ] && [ ! -L "${default_loc}" ]; then
            local ver=$(ls -1 "${default_loc}" 2>/dev/null | grep -v '^\.' | sort -V | tail -n1)
            if [ -n "${ver}" ] && [ -f "${default_loc}/${ver}" ]; then
                found_binary="${default_loc}/${ver}"
                found_version="${ver}"
            fi
        fi
    fi

    # Return results via global variables
    FOUND_CLAUDE_BINARY="${found_binary}"
    FOUND_CLAUDE_VERSION="${found_version}"
}

# Find any existing Claude installation
find_claude_binary

if [ -n "${FOUND_CLAUDE_BINARY}" ]; then
    CLAUDE_BINARY="${FOUND_CLAUDE_BINARY}"
    LATEST_VERSION="${FOUND_CLAUDE_VERSION}"

    # Ensure binary is in our persistent directory
    if [ ! -f "${CLAUDE_VERSIONS}/${LATEST_VERSION}" ]; then
        cp -p "${CLAUDE_BINARY}" "${CLAUDE_VERSIONS}/${LATEST_VERSION}" 2>/dev/null || true
        chmod 755 "${CLAUDE_VERSIONS}/${LATEST_VERSION}" 2>/dev/null || true
        CLAUDE_BINARY="${CLAUDE_VERSIONS}/${LATEST_VERSION}"
        log "✅ Claude ${LATEST_VERSION} synced to persistent storage"
    fi

    # Create or update the binary symlink
    if [ ! -L "${LOCAL_BIN}/claude" ] || [ "$(readlink -f "${LOCAL_BIN}/claude")" != "${CLAUDE_VERSIONS}/${LATEST_VERSION}" ]; then
        rm -f "${LOCAL_BIN}/claude" 2>/dev/null || true
        ln -sf "${CLAUDE_VERSIONS}/${LATEST_VERSION}" "${LOCAL_BIN}/claude"
        log "✅ Claude binary symlink: ~/.local/bin/claude -> ${CLAUDE_VERSIONS}/${LATEST_VERSION}"
    fi
else
    # Claude not installed - install it
    log "⚠️  Claude Code not found, installing..."

    # Install Claude Code using the official installer
    if curl -fsSL https://claude.ai/install.sh | bash 2>/dev/null; then
        # After install, find and sync the binary
        find_claude_binary
        if [ -n "${FOUND_CLAUDE_BINARY}" ]; then
            LATEST_VERSION="${FOUND_CLAUDE_VERSION}"
            if [ ! -f "${CLAUDE_VERSIONS}/${LATEST_VERSION}" ]; then
                cp -p "${FOUND_CLAUDE_BINARY}" "${CLAUDE_VERSIONS}/${LATEST_VERSION}" 2>/dev/null || true
                chmod 755 "${CLAUDE_VERSIONS}/${LATEST_VERSION}" 2>/dev/null || true
            fi
            ln -sf "${CLAUDE_VERSIONS}/${LATEST_VERSION}" "${LOCAL_BIN}/claude"
            log "✅ Claude Code ${LATEST_VERSION} installed"
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
