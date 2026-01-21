#!/bin/bash
# Claude OAuth Token Auto-Refresh
# Automatically refreshes Claude Code OAuth tokens before expiration
# Part of DATA Tools - https://github.com/stevemoraco/DATAtools

# Use .replit-tools structure
WORKSPACE="/home/runner/workspace"
REPLIT_TOOLS="${WORKSPACE}/.replit-tools"
CREDENTIALS_FILE="${CLAUDE_CONFIG_DIR:-${REPLIT_TOOLS}/.claude-persistent}/.credentials.json"
LOG_FILE="${REPLIT_TOOLS}/.logs/auth-refresh.log"

# OAuth configuration
OAUTH_ENDPOINT="https://console.anthropic.com/v1/oauth/token"
CLIENT_ID="9d1c250a-e61b-44d9-88ed-5944d1962f5e"
REFRESH_THRESHOLD_HOURS=2  # Refresh when less than 2 hours remaining

# Ensure log directory exists
mkdir -p "${REPLIT_TOOLS}/.logs" 2>/dev/null

# Logging function
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" >> "$LOG_FILE" 2>/dev/null
}

# Check if jq is available, if not use node for JSON parsing
parse_json() {
    local json="$1"
    local key="$2"

    if command -v jq &>/dev/null; then
        echo "$json" | jq -r ".$key" 2>/dev/null
    else
        # Fallback to node
        echo "$json" | node -e "
            let data = '';
            process.stdin.on('data', chunk => data += chunk);
            process.stdin.on('end', () => {
                try {
                    const obj = JSON.parse(data);
                    const keys = '$key'.split('.');
                    let val = obj;
                    for (const k of keys) val = val[k];
                    console.log(val);
                } catch(e) { console.log(''); }
            });
        " 2>/dev/null
    fi
}

# Get current timestamp in milliseconds
get_current_time_ms() {
    echo $(($(date +%s) * 1000))
}

# Check token status and return remaining time in hours
check_token_status() {
    if [ ! -f "$CREDENTIALS_FILE" ]; then
        echo "no_file"
        return 1
    fi

    local creds=$(cat "$CREDENTIALS_FILE" 2>/dev/null)
    if [ -z "$creds" ]; then
        echo "empty_file"
        return 1
    fi

    local expires_at=$(parse_json "$creds" "claudeAiOauth.expiresAt")
    if [ -z "$expires_at" ] || [ "$expires_at" = "null" ]; then
        echo "no_expiry"
        return 1
    fi

    local current_time=$(get_current_time_ms)
    local remaining_ms=$((expires_at - current_time))
    local remaining_hours=$((remaining_ms / 1000 / 60 / 60))

    if [ $remaining_ms -le 0 ]; then
        echo "expired"
        return 1
    fi

    echo "$remaining_hours"
    return 0
}

# Refresh the OAuth token
refresh_token() {
    local creds=$(cat "$CREDENTIALS_FILE" 2>/dev/null)
    local refresh_token=$(parse_json "$creds" "claudeAiOauth.refreshToken")

    if [ -z "$refresh_token" ] || [ "$refresh_token" = "null" ]; then
        log "ERROR: No refresh token found"
        return 1
    fi

    log "Attempting token refresh..."

    # Make the refresh request
    local response=$(curl -s -X POST "$OAUTH_ENDPOINT" \
        -H "Content-Type: application/json" \
        -d "{\"grant_type\":\"refresh_token\",\"refresh_token\":\"$refresh_token\",\"client_id\":\"$CLIENT_ID\"}" \
        2>/dev/null)

    if [ -z "$response" ]; then
        log "ERROR: No response from OAuth endpoint"
        return 1
    fi

    # Check for error in response
    local error=$(parse_json "$response" "error")
    if [ -n "$error" ] && [ "$error" != "null" ]; then
        log "ERROR: OAuth refresh failed: $error"
        return 1
    fi

    # Extract new tokens
    local new_access_token=$(parse_json "$response" "access_token")
    local new_refresh_token=$(parse_json "$response" "refresh_token")
    local expires_in=$(parse_json "$response" "expires_in")

    if [ -z "$new_access_token" ] || [ "$new_access_token" = "null" ]; then
        log "ERROR: No access token in response"
        return 1
    fi

    # Calculate new expiry time (expires_in is in seconds)
    local current_time=$(get_current_time_ms)
    local new_expires_at=$((current_time + expires_in * 1000))

    # Use the new refresh token if provided, otherwise keep the old one
    if [ -z "$new_refresh_token" ] || [ "$new_refresh_token" = "null" ]; then
        new_refresh_token="$refresh_token"
    fi

    # Backup the old credentials
    cp "$CREDENTIALS_FILE" "${CREDENTIALS_FILE}.backup" 2>/dev/null

    # Update credentials file using node (more reliable for JSON manipulation)
    node -e "
        const fs = require('fs');
        const creds = JSON.parse(fs.readFileSync('$CREDENTIALS_FILE', 'utf8'));
        creds.claudeAiOauth.accessToken = '$new_access_token';
        creds.claudeAiOauth.refreshToken = '$new_refresh_token';
        creds.claudeAiOauth.expiresAt = $new_expires_at;
        fs.writeFileSync('$CREDENTIALS_FILE', JSON.stringify(creds));
    " 2>/dev/null

    if [ $? -eq 0 ]; then
        log "SUCCESS: Token refreshed, expires in $((expires_in / 3600)) hours"
        return 0
    else
        # Restore backup on failure
        mv "${CREDENTIALS_FILE}.backup" "$CREDENTIALS_FILE" 2>/dev/null
        log "ERROR: Failed to update credentials file"
        return 1
    fi
}

# Main function - called from setup script
auto_refresh_if_needed() {
    local status=$(check_token_status)

    case "$status" in
        "no_file"|"empty_file"|"no_expiry")
            # No credentials, user needs to login
            return 1
            ;;
        "expired")
            echo "⚠️  Token expired, attempting refresh..."
            if refresh_token; then
                echo "✅ Token refreshed successfully"
                return 0
            else
                echo "❌ Token refresh failed - run: claude login"
                return 1
            fi
            ;;
        *)
            # status is remaining hours
            local remaining=$status
            if [ "$remaining" -lt "$REFRESH_THRESHOLD_HOURS" ]; then
                echo "🔄 Token expires in ${remaining}h, refreshing..."
                if refresh_token; then
                    local new_status=$(check_token_status)
                    echo "✅ Token refreshed (${new_status}h remaining)"
                    return 0
                else
                    echo "⚠️  Refresh failed, ${remaining}h remaining"
                    return 0  # Don't fail, token still works
                fi
            else
                # Token is fine, no refresh needed
                return 0
            fi
            ;;
    esac
}

# Command line interface
case "${1:-}" in
    --status)
        status=$(check_token_status)
        case "$status" in
            "no_file") echo "❌ No credentials file found" ;;
            "empty_file") echo "❌ Credentials file is empty" ;;
            "no_expiry") echo "❌ No expiry timestamp found" ;;
            "expired") echo "❌ Token has expired" ;;
            *) echo "✅ Token valid (${status}h remaining)" ;;
        esac
        ;;
    --force)
        echo "Forcing token refresh..."
        if refresh_token; then
            echo "✅ Token refreshed"
        else
            echo "❌ Refresh failed"
            exit 1
        fi
        ;;
    --auto)
        auto_refresh_if_needed
        ;;
    *)
        # Default: auto refresh if needed (silent unless action taken)
        auto_refresh_if_needed
        ;;
esac
