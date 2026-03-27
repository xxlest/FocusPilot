#!/bin/bash

# Gemini CLI adapter for Coder-Bridge
# TODO: Implement when Gemini CLI hook API is available

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ADAPTER_DIR/../core/registry.sh"

# Gemini CLI hook data parser (placeholder)
parse_gemini_hook() {
    local hook_data="$1"
    SESSION_ID=""
    CWD="$PWD"

    if [[ -n "$hook_data" ]]; then
        SESSION_ID=$(echo "$hook_data" | python3 -c "import json,sys; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null || echo "")
        CWD=$(echo "$hook_data" | python3 -c "import json,sys; print(json.load(sys.stdin).get('cwd','$PWD'))" 2>/dev/null || echo "$PWD")
    fi
}

handle_session_start() {
    parse_gemini_hook "$1"
    [[ -n "$SESSION_ID" ]] && register_session "gemini" "$SESSION_ID" "$CWD"
}

handle_stop() {
    parse_gemini_hook "$1"
    [[ -n "$SESSION_ID" ]] && update_session_status "gemini" "$SESSION_ID" "complete"
}

handle_session_end() {
    parse_gemini_hook "$1"
    [[ -n "$SESSION_ID" ]] && unregister_session "gemini" "$SESSION_ID"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    EVENT_TYPE="${1:-}"
    HOOK_INPUT=""
    [[ ! -t 0 ]] && HOOK_INPUT=$(cat 2>/dev/null || true)

    case "$EVENT_TYPE" in
        SessionStart)   handle_session_start "$HOOK_INPUT" ;;
        Stop)           handle_stop "$HOOK_INPUT" ;;
        SessionEnd)     handle_session_end "$HOOK_INPUT" ;;
        *)              echo "Unknown event: $EVENT_TYPE" >&2; exit 1 ;;
    esac
fi
