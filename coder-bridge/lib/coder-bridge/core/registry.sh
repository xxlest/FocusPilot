#!/bin/bash

# Session registry for Coder-Bridge
# Manages AI coding tool sessions and communicates with FocusPilot via DistributedNotification

REGISTRY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$REGISTRY_DIR/../utils/detect.sh"

# DistributedNotification name (FocusPilot listens on this)
NOTIFICATION_NAME="com.focuscopilot.coder-bridge"

# Session state directory
SESSION_DIR="$HOME/.coder-bridge/sessions"

# --- DistributedNotification sender ---

send_to_focuspilot() {
    local action="$1"    # start | stop | complete | idle | error | unregister
    local tool="$2"      # claude | codex | gemini
    local session_id="$3"
    local cwd="$4"
    local extra="$5"     # optional JSON fragment

    swift -e '
import Foundation
DistributedNotificationCenter.default().post(
    name: .init("'"$NOTIFICATION_NAME"'"),
    object: nil,
    userInfo: [
        "action": "'"$action"'",
        "tool": "'"$tool"'",
        "sessionId": "'"$session_id"'",
        "cwd": "'"$cwd"'",
        "extra": "'"${extra:-{}}"'",
        "timestamp": "\(Int(Date().timeIntervalSince1970))"
    ],
    deliverImmediately: true
)
' 2>/dev/null
}

# --- Local session file management ---

ensure_session_dir() {
    mkdir -p "$SESSION_DIR"
}

register_session() {
    local tool="$1"
    local session_id="$2"
    local cwd="$3"
    local pid="${4:-$$}"

    ensure_session_dir

    local session_file="$SESSION_DIR/${tool}_${session_id}.json"
    cat > "$session_file" <<EOF
{
    "tool": "$tool",
    "sessionId": "$session_id",
    "cwd": "$cwd",
    "pid": $pid,
    "status": "running",
    "startTime": $(date +%s),
    "lastUpdate": $(date +%s)
}
EOF

    send_to_focuspilot "start" "$tool" "$session_id" "$cwd"
}

update_session_status() {
    local tool="$1"
    local session_id="$2"
    local status="$3"   # running | idle | complete | error

    local session_file="$SESSION_DIR/${tool}_${session_id}.json"

    if [[ -f "$session_file" ]]; then
        local cwd
        cwd=$(python3 -c "import json,sys; print(json.load(open('$session_file'))['cwd'])" 2>/dev/null || echo "")

        # Update status and lastUpdate timestamp
        python3 -c "
import json, time
with open('$session_file', 'r') as f:
    data = json.load(f)
data['status'] = '$status'
data['lastUpdate'] = int(time.time())
with open('$session_file', 'w') as f:
    json.dump(data, f, indent=4)
" 2>/dev/null

        send_to_focuspilot "$status" "$tool" "$session_id" "$cwd"
    fi
}

unregister_session() {
    local tool="$1"
    local session_id="$2"

    local session_file="$SESSION_DIR/${tool}_${session_id}.json"

    if [[ -f "$session_file" ]]; then
        local cwd
        cwd=$(python3 -c "import json,sys; print(json.load(open('$session_file'))['cwd'])" 2>/dev/null || echo "")

        rm -f "$session_file"
        send_to_focuspilot "unregister" "$tool" "$session_id" "$cwd"
    fi
}

# --- Query helpers ---

list_sessions() {
    local tool_filter="${1:-}"  # optional: claude | codex | gemini

    ensure_session_dir

    for f in "$SESSION_DIR"/*.json; do
        [[ -f "$f" ]] || continue
        if [[ -z "$tool_filter" ]] || [[ "$(basename "$f")" == "${tool_filter}_"* ]]; then
            cat "$f"
            echo ""
        fi
    done
}

cleanup_stale_sessions() {
    ensure_session_dir

    for f in "$SESSION_DIR"/*.json; do
        [[ -f "$f" ]] || continue

        local pid
        pid=$(python3 -c "import json; print(json.load(open('$f'))['pid'])" 2>/dev/null || echo "0")

        if [[ "$pid" -gt 0 ]] && ! kill -0 "$pid" 2>/dev/null; then
            local tool session_id
            tool=$(python3 -c "import json; print(json.load(open('$f'))['tool'])" 2>/dev/null)
            session_id=$(python3 -c "import json; print(json.load(open('$f'))['sessionId'])" 2>/dev/null)
            rm -f "$f"
            send_to_focuspilot "unregister" "$tool" "$session_id" ""
        fi
    done
}
