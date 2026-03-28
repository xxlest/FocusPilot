#!/bin/bash

# Session registry for Coder-Bridge
# Manages AI coding tool sessions and communicates with FocusPilot via DistributedNotification

REGISTRY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$REGISTRY_DIR/../utils/detect.sh"

# DistributedNotification name (FocusPilot listens on this)
NOTIFICATION_NAME="com.focuscopilot.coder-bridge"

# Session state directory (for seq counter files)
SESSION_DIR="$HOME/.coder-bridge/sessions"

# --- hostApp normalization ---

normalize_host_app() {
    case "${TERM_PROGRAM:-}" in
        Apple_Terminal)     echo "terminal" ;;
        iTerm.app|iTerm2)   echo "iterm2" ;;
        WezTerm)            echo "wezterm" ;;
        WarpTerminal)       echo "warp" ;;
        vscode)             echo "vscode" ;;
        cursor)             echo "cursor" ;;
        *)                  echo "" ;;
    esac
}

# --- cwdNormalized computation ---

compute_cwd_normalized() {
    local cwd="$1"
    local normalized
    normalized=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
    if [[ -z "$normalized" ]]; then
        normalized=$(realpath "$cwd" 2>/dev/null || echo "$cwd")
    fi
    echo "$normalized"
}

# --- seq counter (per session, monotonically increasing) ---

ensure_session_dir() {
    mkdir -p "$SESSION_DIR"
}

next_seq() {
    local sid="$1"
    ensure_session_dir
    local seq_file="$SESSION_DIR/${sid}.seq"
    local current=0
    if [[ -f "$seq_file" ]]; then
        current=$(cat "$seq_file" 2>/dev/null || echo "0")
    fi
    local next=$((current + 1))
    echo "$next" > "$seq_file"
    echo "$next"
}

cleanup_seq() {
    local sid="$1"
    rm -f "$SESSION_DIR/${sid}.seq"
}

# --- DistributedNotification sender ---

send_to_focuspilot() {
    local event="$1"     # session.start | session.update | session.end
    local sid="$2"
    local seq="$3"
    local tool="$4"
    local cwd="$5"
    local cwd_normalized="$6"
    local status="$7"    # registered | working | idle | done | error
    local host_app="$8"
    local ts
    ts=$(date +%s)

    swift -e '
import Foundation
DistributedNotificationCenter.default().post(
    name: .init("'"$NOTIFICATION_NAME"'"),
    object: nil,
    userInfo: [
        "event": "'"$event"'",
        "sid": "'"$sid"'",
        "seq": "'"$seq"'",
        "tool": "'"$tool"'",
        "cwd": "'"$cwd"'",
        "cwdNormalized": "'"$cwd_normalized"'",
        "status": "'"$status"'",
        "hostApp": "'"$host_app"'",
        "ts": "'"$ts"'"
    ],
    deliverImmediately: true
)
' 2>/dev/null
}

# --- High-level session operations ---

session_start() {
    local tool="$1"
    local sid="$2"
    local cwd="$3"

    local host_app
    host_app=$(normalize_host_app)
    local cwd_normalized
    cwd_normalized=$(compute_cwd_normalized "$cwd")
    local seq
    seq=$(next_seq "$sid")

    send_to_focuspilot "session.start" "$sid" "$seq" "$tool" "$cwd" "$cwd_normalized" "registered" "$host_app"
}

session_update() {
    local tool="$1"
    local sid="$2"
    local cwd="$3"
    local status="$4"   # working | idle | done | error

    local host_app
    host_app=$(normalize_host_app)
    local cwd_normalized
    cwd_normalized=$(compute_cwd_normalized "$cwd")
    local seq
    seq=$(next_seq "$sid")

    send_to_focuspilot "session.update" "$sid" "$seq" "$tool" "$cwd" "$cwd_normalized" "$status" "$host_app"
}

session_end() {
    local tool="$1"
    local sid="$2"
    local cwd="$3"

    local host_app
    host_app=$(normalize_host_app)
    local cwd_normalized
    cwd_normalized=$(compute_cwd_normalized "$cwd")
    local seq
    seq=$(next_seq "$sid")

    send_to_focuspilot "session.end" "$sid" "$seq" "$tool" "$cwd" "$cwd_normalized" "" "$host_app"

    # Clean up seq file
    cleanup_seq "$sid"
}
