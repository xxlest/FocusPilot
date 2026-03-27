#!/bin/bash

# Claude Code adapter for Coder-Bridge
# Parses Claude Code hook stdin JSON and dispatches to registry/notifier

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ADAPTER_DIR/../core/registry.sh"
source "$ADAPTER_DIR/../core/notifier.sh"

# Parse Claude Code hook data from stdin
parse_claude_hook() {
    local hook_data="$1"

    if [[ -z "$hook_data" ]]; then
        return 1
    fi

    # Extract fields from JSON
    SESSION_ID=$(echo "$hook_data" | python3 -c "import json,sys; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null || echo "")
    CWD=$(echo "$hook_data" | python3 -c "import json,sys; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || echo "$PWD")
    STOP_HOOK_ACTIVE=$(echo "$hook_data" | python3 -c "import json,sys; print(json.load(sys.stdin).get('stop_hook_active',False))" 2>/dev/null || echo "False")
    AUTO_ACCEPTED=$(echo "$hook_data" | python3 -c "import json,sys; print(json.load(sys.stdin).get('autoAccepted',False))" 2>/dev/null || echo "False")
}

# Hook handlers

handle_session_start() {
    local hook_data="$1"
    parse_claude_hook "$hook_data"

    if [[ -n "$SESSION_ID" ]]; then
        register_session "claude" "$SESSION_ID" "$CWD"
    fi
}

handle_stop() {
    local hook_data="$1"
    parse_claude_hook "$hook_data"

    # Skip if stop_hook_active (avoid infinite loop)
    if [[ "$STOP_HOOK_ACTIVE" == "True" ]]; then
        return 0
    fi

    if [[ -n "$SESSION_ID" ]]; then
        update_session_status "claude" "$SESSION_ID" "complete"
    fi
}

handle_notification() {
    local hook_data="$1"
    parse_claude_hook "$hook_data"

    if [[ -n "$SESSION_ID" ]]; then
        update_session_status "claude" "$SESSION_ID" "idle"
    fi
}

handle_session_end() {
    local hook_data="$1"
    parse_claude_hook "$hook_data"

    if [[ -n "$SESSION_ID" ]]; then
        unregister_session "claude" "$SESSION_ID"
    fi
}

# Main dispatch (called from hook config)
# Usage: claude.sh <event_type>
#   event_type: SessionStart | Stop | Notification | SessionEnd

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    EVENT_TYPE="${1:-}"

    # Read stdin
    HOOK_INPUT=""
    if [[ ! -t 0 ]]; then
        HOOK_INPUT=$(cat 2>/dev/null || true)
    fi

    case "$EVENT_TYPE" in
        SessionStart)   handle_session_start "$HOOK_INPUT" ;;
        Stop)           handle_stop "$HOOK_INPUT" ;;
        Notification)   handle_notification "$HOOK_INPUT" ;;
        SessionEnd)     handle_session_end "$HOOK_INPUT" ;;
        *)              echo "Unknown event: $EVENT_TYPE" >&2; exit 1 ;;
    esac
fi
