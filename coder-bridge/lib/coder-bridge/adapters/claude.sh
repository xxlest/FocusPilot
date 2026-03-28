#!/bin/bash

# Claude Code adapter for Coder-Bridge
# Parses Claude Code hook stdin JSON and dispatches to registry

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ADAPTER_DIR/../core/registry.sh"

# Parse Claude Code hook data from stdin
parse_claude_hook() {
    local hook_data="$1"

    if [[ -z "$hook_data" ]]; then
        return 1
    fi

    SESSION_ID=$(echo "$hook_data" | python3 -c "import json,sys; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null || echo "")
    CWD=$(echo "$hook_data" | python3 -c "import json,sys; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || echo "$PWD")
    STOP_HOOK_ACTIVE=$(echo "$hook_data" | python3 -c "import json,sys; print(json.load(sys.stdin).get('stop_hook_active',False))" 2>/dev/null || echo "False")
}

# Hook handlers

handle_session_start() {
    local hook_data="$1"
    parse_claude_hook "$hook_data"
    [[ -n "$SESSION_ID" ]] && session_start "claude" "$SESSION_ID" "$CWD"
}

handle_stop() {
    local hook_data="$1"
    parse_claude_hook "$hook_data"

    # Skip if stop_hook_active (avoid infinite loop)
    [[ "$STOP_HOOK_ACTIVE" == "True" ]] && return 0

    # Stop hook = Claude finished responding → done
    [[ -n "$SESSION_ID" ]] && session_update "claude" "$SESSION_ID" "$CWD" "done"
}

handle_notification() {
    local hook_data="$1"
    parse_claude_hook "$hook_data"
    # Notification hook = Claude waiting for user input → idle
    [[ -n "$SESSION_ID" ]] && session_update "claude" "$SESSION_ID" "$CWD" "idle"
}

handle_session_end() {
    local hook_data="$1"
    parse_claude_hook "$hook_data"
    [[ -n "$SESSION_ID" ]] && session_end "claude" "$SESSION_ID" "$CWD"
}

# Main dispatch
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    EVENT_TYPE="${1:-}"
    HOOK_INPUT=""
    [[ ! -t 0 ]] && HOOK_INPUT=$(cat 2>/dev/null || true)

    case "$EVENT_TYPE" in
        SessionStart)   handle_session_start "$HOOK_INPUT" ;;
        Stop)           handle_stop "$HOOK_INPUT" ;;
        Notification)   handle_notification "$HOOK_INPUT" ;;
        SessionEnd)     handle_session_end "$HOOK_INPUT" ;;
        *)              echo "Unknown event: $EVENT_TYPE" >&2; exit 1 ;;
    esac
fi
