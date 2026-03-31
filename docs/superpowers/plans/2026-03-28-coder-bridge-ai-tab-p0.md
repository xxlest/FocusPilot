# Coder-Bridge AI Tab P0 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 FocusPilot 快捷面板新增 AI Tab，通过 DistributedNotification 接收 coder-bridge 会话事件，展示 AI 编码工具会话列表并支持点击切换到对应宿主窗口。

**Architecture:** coder-bridge shell 脚本通过 Claude Code hooks 采集会话生命周期事件，经 macOS DistributedNotificationCenter 发送给 FocusPilot。FocusPilot 维护纯运行时的 CoderSession 列表，在快捷面板 AI Tab 中展示，并通过前台窗口初始关联 + cwd basename 回退匹配实现点击切换。

**Tech Stack:** Swift 5, AppKit, DistributedNotificationCenter, CGWindowList, Bash shell scripts

**Spec 文档:** `docs/superpowers/specs/2026-03-28-coder-bridge-ai-tab-design.md`

**编译验证:** `make build`（编译到 /tmp/focuspilot-build/）
**安装验证:** `make install`（编译+签名+安装+启动）

---

### Task 1: 更新 coder-bridge shell 脚本适配新协议

**Files:**
- Modify: `coder-bridge/lib/coder-bridge/core/registry.sh`
- Modify: `coder-bridge/lib/coder-bridge/adapters/claude.sh`

现有的 registry.sh 使用旧协议（action/sessionId/cwd），需要改成新协议（event/sid/seq/tool/cwd/cwdNormalized/status/hostApp/ts）。claude.sh 需要适配新的事件分发逻辑。

- [ ] **Step 1: 重写 registry.sh 的 send_to_focuspilot 函数和 hostApp 归一化**

```bash
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
```

Replace the entire content of `coder-bridge/lib/coder-bridge/core/registry.sh` with the above.

- [ ] **Step 2: 重写 claude.sh 适配新协议**

```bash
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
```

Replace the entire content of `coder-bridge/lib/coder-bridge/adapters/claude.sh` with the above.

- [ ] **Step 3: 手动验证 shell 脚本语法**

Run: `bash -n coder-bridge/lib/coder-bridge/core/registry.sh && bash -n coder-bridge/lib/coder-bridge/adapters/claude.sh && echo "OK"`

Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add coder-bridge/lib/coder-bridge/core/registry.sh coder-bridge/lib/coder-bridge/adapters/claude.sh
git commit -m "refactor(coder-bridge): 重写 registry.sh 和 claude.sh 适配新 IPC 协议

- send_to_focuspilot 改用新字段（event/sid/seq/status/hostApp/cwdNormalized）
- 新增 normalize_host_app() 归一化 TERM_PROGRAM
- 新增 compute_cwd_normalized() 优先 git repo root
- 新增 seq 单调递增计数器（防乱序）
- claude.sh Stop hook 映射为 done 状态"
```

---

### Task 2: 新增 CoderSession 数据模型

**Files:**
- Create: `FocusPilot/Models/CoderSession.swift`

- [ ] **Step 1: 创建 CoderSession.swift**

```swift
import AppKit

// MARK: - Enums

enum CoderTool: String {
    case claude, codex, gemini

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex:  return "Codex"
        case .gemini: return "Gemini"
        }
    }

    /// SF Symbol name for tool icon
    var symbolName: String {
        switch self {
        case .claude: return "hexagon"
        case .codex:  return "diamond"
        case .gemini: return "sparkle"
        }
    }
}

enum SessionStatus: String {
    case registered, working, idle, done, error
}

enum SessionLifecycle: String {
    case active, ended
}

enum MatchConfidence: String {
    case high, low, none
}

// MARK: - CoderSession

struct CoderSession: Identifiable {
    let sessionID: String
    var tool: CoderTool
    var cwd: String
    var cwdNormalized: String
    var hostApp: String
    var status: SessionStatus
    var lifecycle: SessionLifecycle
    var lastSeq: Int
    var lastUpdate: Date
    var isHidden: Bool

    // 运行时窗口关联
    var initialCandidateWindowID: CGWindowID?
    var candidateWindowID: CGWindowID?
    var matchConfidence: MatchConfidence

    var id: String { sessionID }

    var preferenceKey: String {
        "\(tool.rawValue):\(cwdNormalized):\(hostApp)"
    }

    /// cwd 最后一级目录名，用作默认 displayName
    var cwdBasename: String {
        (cwd as NSString).lastPathComponent
    }

    /// 是否需要用户处理（actionable）
    var isActionable: Bool {
        switch (status, lifecycle) {
        case (.idle, .active),
             (.done, .active),
             (.done, .ended),
             (.error, .active),
             (.error, .ended):
            return true
        default:
            return false
        }
    }

    /// 排序档位（1=最高优先级）
    var sortTier: Int {
        switch (status, lifecycle) {
        case (.idle, .active),
             (.done, .active), (.done, .ended),
             (.error, .active), (.error, .ended):
            return 1
        case (.working, .active), (.registered, .active), (.working, .ended):
            return 2
        default:
            return 3
        }
    }

    /// 状态显示文字
    var statusText: String {
        let base: String
        switch status {
        case .registered: base = "已连接"
        case .working:    base = "执行中"
        case .idle:       base = "等待输入"
        case .done:       base = "已完成"
        case .error:      base = "出错"
        }
        if lifecycle == .ended {
            return "\(base) · 已结束"
        }
        return base
    }

    /// 状态圆点颜色
    func statusDotColor(theme: ThemeColors) -> NSColor {
        switch status {
        case .idle:       return theme.nsAccent
        case .done:       return .systemGreen
        case .error:      return .systemRed
        case .working:    return theme.nsAccent
        case .registered: return theme.nsTextTertiary
        }
    }

    /// 状态圆点是否有光晕
    var statusDotHasGlow: Bool {
        switch status {
        case .idle, .done, .error: return true
        default: return false
        }
    }

    /// 行透明度
    var rowAlpha: CGFloat {
        switch (status, lifecycle) {
        case (_, .active): return 1.0
        case (.done, .ended), (.error, .ended), (.working, .ended): return 0.7
        default: return 0.5
        }
    }
}

// MARK: - CoderSessionPreference (P0 只用 displayName)

struct CoderSessionPreference: Codable {
    let key: String
    var displayName: String
    var isPinned: Bool

    init(key: String, displayName: String, isPinned: Bool = false) {
        self.key = key
        self.displayName = displayName
        self.isPinned = isPinned
    }
}

// MARK: - hostApp → bundleID mapping

enum HostAppMapping {
    static let hostToBundleID: [String: String] = [
        "terminal": "com.apple.Terminal",
        "iterm2":   "com.googlecode.iterm2",
        "wezterm":  "com.github.wez.wezterm",
        "warp":     "dev.warp.Warp-Stable",
        "vscode":   "com.microsoft.VSCode",
        "cursor":   "com.todesktop.230313mzl4w4u92",
    ]

    static func bundleID(for hostApp: String) -> String? {
        hostToBundleID[hostApp]
    }

    static func hostApp(for bundleID: String) -> String? {
        hostToBundleID.first(where: { $0.value == bundleID })?.key
    }
}
```

- [ ] **Step 2: 编译验证**

Run: `make build`

Expected: 编译成功，无错误

- [ ] **Step 3: Commit**

```bash
git add FocusPilot/Models/CoderSession.swift
git commit -m "feat(models): 新增 CoderSession 数据模型

- CoderSession 运行时结构体（status + lifecycle 双维度）
- CoderTool / SessionStatus / SessionLifecycle / MatchConfidence 枚举
- CoderSessionPreference 用户偏好持久化结构
- HostAppMapping hostApp→bundleID 双向映射表
- isActionable / sortTier / statusText / statusDotColor 等计算属性"
```

---

### Task 3: 新增 CoderBridgeService

**Files:**
- Create: `FocusPilot/Services/CoderBridgeService.swift`
- Modify: `FocusPilot/Helpers/Constants.swift`

- [ ] **Step 1: 在 Constants.swift 的 Notifications 枚举中新增通知名**

在 `Constants.Notifications` 枚举末尾（`focusGuidedStepChanged` 之后）添加：

```swift
        /// Coder-Bridge 会话状态变化
        static let coderBridgeSessionChanged = Notification.Name("FocusPilot.coderBridgeSessionChanged")
```

在 `Constants.Keys` 枚举末尾添加：

```swift
        static let sessionPreferences = "FocusPilot.sessionPreferences"
```

- [ ] **Step 2: 创建 CoderBridgeService.swift**

```swift
import AppKit

/// 管理 AI 编码工具会话的服务
/// 通过 DistributedNotificationCenter 接收 coder-bridge 事件
/// 维护纯运行时的 CoderSession 列表
class CoderBridgeService {
    static let shared = CoderBridgeService()

    /// 当前活跃的 AI 会话列表（运行时，不持久化）
    private(set) var sessions: [CoderSession] = []

    /// 清理定时器
    private var cleanupTimer: Timer?

    private init() {}

    // MARK: - Lifecycle

    func start() {
        // 监听 coder-bridge 的 DistributedNotification
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleDistributedNotification(_:)),
            name: NSNotification.Name("com.focuscopilot.coder-bridge"),
            object: nil
        )

        // 启动清理定时器（每 60 秒检查一次）
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.cleanupEndedSessions()
        }
    }

    // MARK: - Event Handling

    @objc private func handleDistributedNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }

        let event = userInfo["event"] as? String ?? ""
        let sid = userInfo["sid"] as? String ?? ""
        let seqStr = userInfo["seq"] as? String ?? "0"
        let seq = Int(seqStr) ?? 0
        let toolStr = userInfo["tool"] as? String ?? ""
        let cwd = userInfo["cwd"] as? String ?? ""
        let cwdNormalized = userInfo["cwdNormalized"] as? String ?? cwd
        let statusStr = userInfo["status"] as? String ?? ""
        let hostApp = userInfo["hostApp"] as? String ?? ""

        guard !sid.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            switch event {
            case "session.start":
                self?.handleSessionStart(sid: sid, seq: seq, toolStr: toolStr, cwd: cwd, cwdNormalized: cwdNormalized, hostApp: hostApp)
            case "session.update":
                self?.handleSessionUpdate(sid: sid, seq: seq, statusStr: statusStr)
            case "session.end":
                self?.handleSessionEnd(sid: sid, seq: seq)
            default:
                break
            }
        }
    }

    private func handleSessionStart(sid: String, seq: Int, toolStr: String, cwd: String, cwdNormalized: String, hostApp: String) {
        // 拒绝已存在的 sid（不复用）
        if sessions.contains(where: { $0.sessionID == sid }) {
            return
        }

        let tool = CoderTool(rawValue: toolStr) ?? .claude

        var session = CoderSession(
            sessionID: sid,
            tool: tool,
            cwd: cwd,
            cwdNormalized: cwdNormalized,
            hostApp: hostApp,
            status: .registered,
            lifecycle: .active,
            lastSeq: seq,
            lastUpdate: Date(),
            isHidden: false,
            initialCandidateWindowID: nil,
            candidateWindowID: nil,
            matchConfidence: .none
        )

        // 前台窗口初始关联
        session.initialCandidateWindowID = resolveFrontmostWindow(hostApp: hostApp)
        if session.initialCandidateWindowID != nil {
            session.candidateWindowID = session.initialCandidateWindowID
            session.matchConfidence = .high
        }

        sessions.append(session)
        postSessionChanged()
    }

    private func handleSessionUpdate(sid: String, seq: Int, statusStr: String) {
        guard let index = sessions.firstIndex(where: { $0.sessionID == sid }) else { return }

        // 乱序防护
        if seq <= sessions[index].lastSeq { return }

        if let newStatus = SessionStatus(rawValue: statusStr) {
            sessions[index].status = newStatus
        }
        sessions[index].lastSeq = seq
        sessions[index].lastUpdate = Date()

        postSessionChanged()
    }

    private func handleSessionEnd(sid: String, seq: Int) {
        guard let index = sessions.firstIndex(where: { $0.sessionID == sid }) else { return }

        // 乱序防护
        if seq <= sessions[index].lastSeq { return }

        sessions[index].lifecycle = .ended
        sessions[index].lastSeq = seq
        sessions[index].lastUpdate = Date()

        postSessionChanged()
    }

    // MARK: - Window Resolution

    /// 获取当前前台应用的最前窗口 ID（用于 session.start 初始关联）
    private func resolveFrontmostWindow(hostApp: String) -> CGWindowID? {
        guard !hostApp.isEmpty,
              let expectedBundleID = HostAppMapping.bundleID(for: hostApp),
              let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.bundleIdentifier == expectedBundleID else {
            return nil
        }

        // 用 CGWindowList 获取该 app 的最前窗口
        let pid = frontApp.processIdentifier
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for windowInfo in windowList {
            guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid,
                  let layer = windowInfo[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID else {
                continue
            }
            return windowID  // 第一个匹配的就是最前的
        }

        return nil
    }

    /// 为 session 执行回退匹配（initialCandidateWindowID 失效时）
    func resolveWindowForSession(_ session: CoderSession) -> (CGWindowID?, MatchConfidence) {
        // 第一层：初始关联仍有效？
        if let initial = session.initialCandidateWindowID, windowExists(initial) {
            return (initial, .high)
        }

        // 第二层：回退匹配
        let candidateWindows = findWindowsForHostApp(session.hostApp)

        if candidateWindows.isEmpty {
            return (nil, .none)
        }

        // P0 规则 1: cwd basename 命中窗口标题
        let basename = session.cwdBasename
        for (wid, title) in candidateWindows {
            if title.contains(basename) {
                return (wid, .high)
            }
        }

        // P0 规则 2/3: 取窗口列表第一个可见候选（CGWindowList 按 z-order 排列，第一个即最前窗口）
        if let first = candidateWindows.first {
            return (first.0, .low)
        }

        return (nil, .none)
    }

    /// 检查 windowID 是否仍存在于当前窗口列表
    private func windowExists(_ windowID: CGWindowID) -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return windowList.contains { ($0[kCGWindowNumber as String] as? CGWindowID) == windowID }
    }

    /// 获取指定宿主 app 的所有可见窗口 (windowID, title)
    private func findWindowsForHostApp(_ hostApp: String) -> [(CGWindowID, String)] {
        guard let bundleID = HostAppMapping.bundleID(for: hostApp) else {
            return []
        }

        // 从 AppMonitor 的 runningApps 中找
        guard let runningApp = AppMonitor.shared.runningApps.first(where: { $0.bundleID == bundleID }) else {
            return []
        }

        return runningApp.windows.map { ($0.id, $0.title) }
    }

    // MARK: - Session Queries

    /// 获取排序后的可见 session 列表
    var sortedVisibleSessions: [CoderSession] {
        sessions
            .filter { !$0.isHidden }
            .sorted { a, b in
                if a.sortTier != b.sortTier {
                    return a.sortTier < b.sortTier
                }
                return a.lastUpdate > b.lastUpdate
            }
    }

    /// actionable 会话数量（用于 Tab 角标）
    var actionableCount: Int {
        sessions.filter { !$0.isHidden && $0.isActionable }.count
    }

    // MARK: - Session Actions

    /// 移除指定 session
    func removeSession(_ sid: String) {
        sessions.removeAll { $0.sessionID == sid }
        postSessionChanged()
    }

    /// 移除所有已结束的 session
    func removeEndedSessions() {
        sessions.removeAll { $0.lifecycle == .ended }
        postSessionChanged()
    }

    // MARK: - Cleanup

    private func cleanupEndedSessions() {
        let now = Date()
        var changed = false

        sessions.removeAll { session in
            guard session.lifecycle == .ended else { return false }

            let elapsed = now.timeIntervalSince(session.lastUpdate)

            // done/error + ended → 30 分钟超时
            if (session.status == .done || session.status == .error) && elapsed > 1800 {
                changed = true
                return true
            }
            // 其他 + ended → 5 分钟超时
            if elapsed > 300 {
                changed = true
                return true
            }
            return false
        }

        if changed {
            postSessionChanged()
        }
    }

    // MARK: - Notification

    private func postSessionChanged() {
        NotificationCenter.default.post(
            name: Constants.Notifications.coderBridgeSessionChanged,
            object: nil
        )
    }
}
```

- [ ] **Step 3: 编译验证**

Run: `make build`

Expected: 编译成功，无错误

- [ ] **Step 4: Commit**

```bash
git add FocusPilot/Services/CoderBridgeService.swift FocusPilot/Helpers/Constants.swift
git commit -m "feat(services): 新增 CoderBridgeService 管理 AI 会话

- DistributedNotification 监听 coder-bridge 事件
- session.start 时前台宿主窗口初始关联
- session.update 乱序防护（seq 检查）
- 回退匹配（cwd basename + 最近活跃兜底）
- 清理定时器（30 分钟/5 分钟超时移除）
- Constants 新增 coderBridgeSessionChanged 通知名和 sessionPreferences key"
```

---

### Task 4: AppDelegate 集成 CoderBridgeService

**Files:**
- Modify: `FocusPilot/App/AppDelegate.swift`

- [ ] **Step 1: 在 applicationDidFinishLaunching 中初始化 CoderBridgeService**

在 `AppDelegate.applicationDidFinishLaunching` 方法中，`AppMonitor.shared.startMonitoring()` 之后添加一行：

```swift
        // 启动 AI 会话桥接服务
        CoderBridgeService.shared.start()
```

- [ ] **Step 2: 编译验证**

Run: `make build`

Expected: 编译成功，无错误

- [ ] **Step 3: Commit**

```bash
git add FocusPilot/App/AppDelegate.swift
git commit -m "feat(AppDelegate): 初始化 CoderBridgeService

- 在 AppMonitor 之后启动 CoderBridgeService.shared.start()
- 开始监听 coder-bridge DistributedNotification"
```

---

### Task 5: QuickPanel AI Tab UI - Tab 按钮和切换逻辑

**Files:**
- Modify: `FocusPilot/QuickPanel/QuickPanelView.swift`

这是最大的一个 Task，但拆分成清晰的步骤。需要修改 QuickPanelView 中的以下部分：
1. QuickPanelTab 枚举加 `.ai` case
2. 新增 AI Tab 按钮 + 角标
3. buildContent() 加 `.ai` 分支
4. 新增 buildAITabContent() 方法
5. 新增通知监听

- [ ] **Step 1: 扩展 QuickPanelTab 枚举**

在 `QuickPanelView.swift` 顶部的 `QuickPanelTab` 枚举中新增 `ai` case：

```swift
enum QuickPanelTab: String {
    case running    = "running"
    case favorites  = "favorites"
    case ai         = "ai"
}
```

- [ ] **Step 2: 新增 AI Tab 按钮和角标 label**

在 `favoritesTabButton` 定义之后，添加 AI Tab 按钮和角标：

```swift
    private lazy var aiTabButton: NSButton = {
        let btn = NSButton(title: "AI", target: self, action: #selector(switchToAITab))
        btn.bezelStyle = .recessed
        btn.isBordered = false
        btn.font = .systemFont(ofSize: 11)
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 4
        btn.contentTintColor = ConfigStore.shared.currentThemeColors.nsTextSecondary
        return btn
    }()

    private lazy var aiTabIndicator: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 1
        return view
    }()

    /// AI Tab 角标（显示 actionable 数量）
    private lazy var aiBadgeLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 9, weight: .medium)
        label.textColor = .white
        label.wantsLayer = true
        label.layer?.cornerRadius = 6
        label.layer?.backgroundColor = ConfigStore.shared.currentThemeColors.nsAccent.cgColor
        label.alignment = .center
        label.isHidden = true
        return label
    }()
```

- [ ] **Step 3: 在 topBar 布局中添加 AI Tab 按钮**

找到 `topBar.addSubview(favoritesTabIndicator)` 这行，在其后添加：

```swift
        topBar.addSubview(aiTabButton)
        topBar.addSubview(aiTabIndicator)
        topBar.addSubview(aiBadgeLabel)
```

然后找到 favoritesTabButton 的 Auto Layout 约束（或手动 frame 设置），在其后添加 aiTabButton 的约束。具体位置需要参考现有 tab 按钮的布局方式，将 aiTabButton 放在 favoritesTabButton 右侧，间距与现有 tab 一致。

AI Tab 按钮需要添加一个分隔符（复用现有 tabSeparator 的样式），放在 favoritesTabButton 和 aiTabButton 之间。

- [ ] **Step 4: 新增 tab 切换 handler**

在 `switchToFavoritesTab()` 之后添加：

```swift
    @objc private func switchToAITab() { switchTab(.ai) }
```

- [ ] **Step 5: 在 switchTab 方法中处理 .ai case**

找到 `switchTab()` 方法，在其中处理 AI Tab 的指示器样式。按照现有 `runningTabIndicator` / `favoritesTabIndicator` 的模式，为 `aiTabIndicator` 设置选中/未选中样式。

- [ ] **Step 6: 在 buildContent() 中添加 .ai 分支**

```swift
    private func buildContent() {
        switch currentTab {
        case .running:
            buildRunningTabContent()
        case .favorites:
            buildFavoritesTabContent()
        case .ai:
            buildAITabContent()
        }
    }
```

- [ ] **Step 7: 实现 buildAITabContent()**

```swift
    private func buildAITabContent() {
        let sessions = CoderBridgeService.shared.sortedVisibleSessions

        if sessions.isEmpty {
            // 空状态
            let emptyView = NSView()
            emptyView.translatesAutoresizingMaskIntoConstraints = false

            let label = createLabel("还没有 AI 编码会话\n启动一个 AI 编码工具后\n会自动显示在这里", size: 11, color: ConfigStore.shared.currentThemeColors.nsTextTertiary)
            label.alignment = .center
            label.maximumNumberOfLines = 3
            label.translatesAutoresizingMaskIntoConstraints = false
            emptyView.addSubview(label)

            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: emptyView.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: emptyView.centerYAnchor),
                emptyView.heightAnchor.constraint(equalToConstant: 100),
            ])

            contentStack.addArrangedSubview(emptyView)
            return
        }

        for session in sessions {
            let row = createSessionRow(session: session)
            contentStack.addArrangedSubview(row)
        }
    }
```

- [ ] **Step 8: 添加 CoderBridgeService 通知监听**

在 `setupNotifications()` 方法末尾添加：

```swift
        // Coder-Bridge 会话状态变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(coderBridgeSessionsDidChange),
            name: Constants.Notifications.coderBridgeSessionChanged,
            object: nil
        )
```

添加对应 handler：

```swift
    @objc private func coderBridgeSessionsDidChange() {
        updateAIBadge()
        if currentTab == .ai {
            forceReload()
        }
    }
```

- [ ] **Step 9: 实现 updateAIBadge()**

```swift
    private func updateAIBadge() {
        let count = CoderBridgeService.shared.actionableCount
        if count > 0 {
            aiBadgeLabel.stringValue = " \(count) "
            aiBadgeLabel.isHidden = false
        } else {
            aiBadgeLabel.isHidden = true
        }
    }
```

- [ ] **Step 10: 在 buildStructuralKey() 中包含 AI Tab 状态**

找到 `buildStructuralKey()` 方法，在其中为 `.ai` Tab 添加结构化 key 信息。当 `currentTab == .ai` 时，将 session 列表的 sid + status + lifecycle 拼入 key。

```swift
        if currentTab == .ai {
            let sessionKeys = CoderBridgeService.shared.sortedVisibleSessions
                .map { "\($0.sessionID):\($0.status.rawValue):\($0.lifecycle.rawValue)" }
                .joined(separator: "|")
            parts.append("AI:\(sessionKeys)")
        }
```

- [ ] **Step 11: 编译验证**

Run: `make build`

Expected: 编译成功，无错误

- [ ] **Step 12: Commit**

```bash
git add FocusPilot/QuickPanel/QuickPanelView.swift
git commit -m "feat(QuickPanel): 新增 AI Tab 基础 UI

- QuickPanelTab 扩展 .ai case
- AI Tab 按钮 + 角标 + 选中指示器
- buildAITabContent() 展示 session 列表或空状态
- 监听 coderBridgeSessionChanged 通知刷新
- updateAIBadge() actionable 计数角标"
```

---

### Task 6: QuickPanel Session 行构建

**Files:**
- Modify: `FocusPilot/QuickPanel/QuickPanelRowBuilder.swift`

- [ ] **Step 1: 在 QuickPanelRowBuilder.swift 中新增 createSessionRow()**

在文件末尾（最后一个 `}` 之前）添加以下方法：

```swift
    // MARK: - AI Session Row

    func createSessionRow(session: CoderSession) -> HoverableRowView {
        let theme = ConfigStore.shared.currentThemeColors
        let row = HoverableRowView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = Constants.Design.Spacing.sm
        stack.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: Constants.Design.Spacing.sm),
            stack.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -Constants.Design.Spacing.sm),
            stack.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])

        // 1. 状态圆点（6px）
        let dot = NSView()
        dot.wantsLayer = true
        dot.translatesAutoresizingMaskIntoConstraints = false
        let dotColor = session.statusDotColor(theme: theme)
        dot.layer?.backgroundColor = dotColor.cgColor
        dot.layer?.cornerRadius = 3
        if session.statusDotHasGlow {
            dot.layer?.shadowColor = dotColor.cgColor
            dot.layer?.shadowRadius = 3
            dot.layer?.shadowOpacity = 0.5
            dot.layer?.shadowOffset = .zero
        }
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
        ])
        stack.addArrangedSubview(dot)

        // 2. 工具图标（14px）
        if let toolImage = Self.cachedSymbol(name: session.tool.symbolName, size: 14, weight: .regular) {
            let toolIcon = NSImageView(image: toolImage)
            toolIcon.contentTintColor = theme.nsTextSecondary
            toolIcon.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                toolIcon.widthAnchor.constraint(equalToConstant: 14),
                toolIcon.heightAnchor.constraint(equalToConstant: 14),
            ])
            stack.addArrangedSubview(toolIcon)
        }

        // 3. displayName
        let displayName = session.cwdBasename  // P0 使用 cwd basename
        let nameLabel = createLabel(displayName, size: 12, color: theme.nsTextPrimary)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(nameLabel)

        // spacer
        stack.addArrangedSubview(createSpacer())

        // 4. 宿主 App 图标（16px）
        if !session.hostApp.isEmpty,
           let bundleID = HostAppMapping.bundleID(for: session.hostApp),
           let appPath = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let appIcon = NSWorkspace.shared.icon(forFile: appPath.path)
            appIcon.size = NSSize(width: 16, height: 16)
            let hostIconView = NSImageView(image: appIcon)
            hostIconView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hostIconView.widthAnchor.constraint(equalToConstant: 16),
                hostIconView.heightAnchor.constraint(equalToConstant: 16),
            ])
            stack.addArrangedSubview(hostIconView)
        }

        // 5. 状态文字
        let statusLabel = createLabel(session.statusText, size: 11, color: theme.nsTextSecondary)
        stack.addArrangedSubview(statusLabel)

        // 行透明度
        row.alphaValue = session.rowAlpha

        // 点击处理
        row.clickHandler = { [weak self] in
            self?.handleSessionClick(session)
        }

        // 右键菜单（P0 只有"移除已结束的会话"）
        row.contextMenuProvider = { [weak self] in
            self?.createSessionContextMenu(session: session)
        }

        return row
    }

    private func handleSessionClick(_ session: CoderSession) {
        let (windowID, confidence) = CoderBridgeService.shared.resolveWindowForSession(session)

        if let wid = windowID {
            let allWindows = AppMonitor.shared.runningApps.flatMap { $0.windows }
            if let windowInfo = allWindows.first(where: { $0.id == wid }) {
                WindowService.shared.activateWindow(windowInfo)
                (self.window as? QuickPanelWindow)?.yieldLevel()

                // .low 时短暂闪烁行背景提示"已切换到最近窗口"
                if confidence == .low, let row = self.contentStack.arrangedSubviews.first(where: {
                    ($0 as? HoverableRowView)?.windowInfo == nil  // session row 没有 windowInfo
                }) as? HoverableRowView {
                    row.wantsLayer = true
                    let flashColor = ConfigStore.shared.currentThemeColors.nsAccent.withAlphaComponent(0.15).cgColor
                    row.layer?.backgroundColor = flashColor
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        NSAnimationContext.runAnimationGroup({ ctx in
                            ctx.duration = Constants.Design.Anim.normal
                            row.layer?.backgroundColor = NSColor.clear.cgColor
                        })
                    }
                }
                return
            }
        }

        // .none: 只激活宿主 App
        if !session.hostApp.isEmpty,
           let bundleID = HostAppMapping.bundleID(for: session.hostApp),
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
            (self.window as? QuickPanelWindow)?.yieldLevel()
        }
    }
```

- [ ] **Step 2: 编译验证**

Run: `make build`

Expected: 编译成功，无错误

- [ ] **Step 3: Commit**

```bash
git add FocusPilot/QuickPanel/QuickPanelRowBuilder.swift
git commit -m "feat(QuickPanel): 新增 createSessionRow() 构建 AI 会话行

- 状态圆点（6px + 光晕）+ 工具图标 + displayName + 宿主图标 + 状态文字
- handleSessionClick 实现两层匹配（初始关联 → 回退匹配 → 激活宿主 App）
- 右键菜单 provider 预留"
```

---

### Task 7: QuickPanel 右键菜单 - P0 移除功能

**Files:**
- Modify: `FocusPilot/QuickPanel/QuickPanelMenuHandler.swift`

- [ ] **Step 1: 在 QuickPanelMenuHandler.swift 中新增 session 右键菜单**

在文件末尾（最后一个 `}` 之前）添加：

```swift
    // MARK: - AI Session Context Menu

    func createSessionContextMenu(session: CoderSession) -> NSMenu? {
        let menu = NSMenu()

        if session.lifecycle == .ended {
            let removeItem = NSMenuItem(title: "移除此会话", action: #selector(handleRemoveSession(_:)), keyEquivalent: "")
            removeItem.target = self
            removeItem.representedObject = session.sessionID
            menu.addItem(removeItem)

            menu.addItem(NSMenuItem.separator())

            let removeAllItem = NSMenuItem(title: "移除所有已结束会话", action: #selector(handleRemoveAllEndedSessions), keyEquivalent: "")
            removeAllItem.target = self
            menu.addItem(removeAllItem)
        }

        return menu.items.isEmpty ? nil : menu
    }

    @objc func handleRemoveSession(_ sender: NSMenuItem) {
        guard let sid = sender.representedObject as? String else { return }
        CoderBridgeService.shared.removeSession(sid)
    }

    @objc func handleRemoveAllEndedSessions() {
        CoderBridgeService.shared.removeEndedSessions()
    }
```

- [ ] **Step 2: 编译验证**

Run: `make build`

Expected: 编译成功，无错误

- [ ] **Step 3: Commit**

```bash
git add FocusPilot/QuickPanel/QuickPanelMenuHandler.swift
git commit -m "feat(QuickPanel): AI 会话右键菜单 - 移除已结束的会话

- P0 只对 lifecycle==ended 的会话显示右键菜单
- 调用 CoderBridgeService.removeEndedSessions()"
```

---

### Task 8: 端到端集成验证

**Files:** 无新增文件

- [ ] **Step 1: 编译安装**

Run: `make install`

Expected: 编译成功，签名完成，FocusPilot 启动

- [ ] **Step 2: 验证 AI Tab 可见**

手动操作：
1. 打开 FocusPilot 快捷面板
2. 确认顶部出现三个 Tab：`活跃` | `关注` | `AI`
3. 点击 `AI` Tab
4. 确认显示空状态文案："还没有 AI 编码会话"

- [ ] **Step 3: 验证 DistributedNotification 接收**

在终端中手动发送一个测试事件：

```bash
swift -e '
import Foundation
DistributedNotificationCenter.default().post(
    name: .init("com.focuscopilot.coder-bridge"),
    object: nil,
    userInfo: [
        "event": "session.start",
        "sid": "test-001",
        "seq": "1",
        "tool": "claude",
        "cwd": "/Users/bruce/Workspace/2-Code/01-work/FocusPilot",
        "cwdNormalized": "/Users/bruce/Workspace/2-Code/01-work/FocusPilot",
        "status": "registered",
        "hostApp": "cursor",
        "ts": "\(Int(Date().timeIntervalSince1970))"
    ],
    deliverImmediately: true
)
RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
'
```

Expected: AI Tab 中出现一条 session 行，显示 `[●] [⬡] FocusPilot [Cursor图标] 已连接`

- [ ] **Step 4: 验证状态更新**

发送 session.update 事件将状态改为 idle：

```bash
swift -e '
import Foundation
DistributedNotificationCenter.default().post(
    name: .init("com.focuscopilot.coder-bridge"),
    object: nil,
    userInfo: [
        "event": "session.update",
        "sid": "test-001",
        "seq": "2",
        "tool": "claude",
        "cwd": "/Users/bruce/Workspace/2-Code/01-work/FocusPilot",
        "cwdNormalized": "/Users/bruce/Workspace/2-Code/01-work/FocusPilot",
        "status": "idle",
        "hostApp": "cursor",
        "ts": "\(Int(Date().timeIntervalSince1970))"
    ],
    deliverImmediately: true
)
RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
'
```

Expected:
- session 行状态文字变为"等待输入"
- 状态圆点变蓝+光晕
- AI Tab 角标显示 `1`

- [ ] **Step 5: 验证 session.end**

```bash
swift -e '
import Foundation
DistributedNotificationCenter.default().post(
    name: .init("com.focuscopilot.coder-bridge"),
    object: nil,
    userInfo: [
        "event": "session.end",
        "sid": "test-001",
        "seq": "3",
        "tool": "claude",
        "cwd": "/Users/bruce/Workspace/2-Code/01-work/FocusPilot",
        "cwdNormalized": "/Users/bruce/Workspace/2-Code/01-work/FocusPilot",
        "status": "",
        "hostApp": "cursor",
        "ts": "\(Int(Date().timeIntervalSince1970))"
    ],
    deliverImmediately: true
)
RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
'
```

Expected: session 行透明度降低，状态文字变为"等待输入 · 已结束"

- [ ] **Step 6: Commit（如有修复）**

如果端到端测试发现需要修复的问题，修复后提交：

```bash
git add -A
git commit -m "fix(coder-bridge): 端到端集成修复

- [具体修复内容]"
```

---

### Task 9: 更新项目文档

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: 更新 CLAUDE.md 架构描述**

在 CLAUDE.md 的文件结构部分添加 `CoderSession.swift` 和 `CoderBridgeService.swift`，在架构描述中添加 coder-bridge 相关说明。更新版本号为 V4.0。

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: 更新 CLAUDE.md 架构描述（V4.0 coder-bridge）"
```
