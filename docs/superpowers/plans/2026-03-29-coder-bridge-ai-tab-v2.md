# Coder-Bridge AI Tab V2 重构实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 AI Tab 从平铺 session 列表重构为"目录分组 + Session 列表"结构，修正窗口绑定逻辑，删除已废弃功能。

**Architecture:** 一级按 cwdNormalized 分组显示目录名，二级展示 session 行（shortID + hostApp + status + query）。窗口绑定严格区分手动绑定（强排他）和 fallback 匹配（无证据时 .none），删除 topic/isHidden 等已废弃字段。

**Tech Stack:** Swift 5, AppKit, NSStackView, CGWindowList

**Spec 文档:** `docs/superpowers/specs/2026-03-29-coder-bridge-ai-tab-v2-design.md`

**编译验证:** `make build`
**安装验证:** `make install`

---

### Task 1: CoderSession 模型清理 + SessionGroup 新增

**Files:**
- Modify: `FocusPilot/Models/CoderSession.swift`

- [ ] **Step 1: 完整重写 CoderSession.swift**

用以下内容替换 `FocusPilot/Models/CoderSession.swift` 全部内容：

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
    case high, none
}

// MARK: - CoderSession

struct CoderSession: Identifiable {
    let sessionID: String               // UUID，Claude 会话唯一标识，不是窗口 ID
    var tool: CoderTool
    var cwd: String
    var cwdNormalized: String
    var hostApp: String
    var status: SessionStatus
    var lifecycle: SessionLifecycle
    var lastSeq: Int
    var lastUpdate: Date
    var lastInteraction: Date?

    // 窗口绑定（运行时）
    var manualWindowID: CGWindowID?      // 用户手动绑定，优先级最高，失效时自动清空
    var resolvedWindowID: CGWindowID?    // 最近一次 fallback 结果（弱记录，不用于强占用）

    var id: String { sessionID }

    var shortID: String {
        String(sessionID.prefix(8))
    }

    var cwdBasename: String {
        let homePath = NSHomeDirectory()
        if cwd == homePath || cwd == homePath + "/" { return "~" }
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? "~" : name
    }

    var sortDate: Date {
        lastInteraction ?? lastUpdate
    }

    var sortTier: Int {
        lifecycle == .ended ? 2 : 1
    }

    var isActionable: Bool {
        switch (status, lifecycle) {
        case (.idle, .active),
             (.done, .active), (.done, .ended),
             (.error, .active), (.error, .ended):
            return true
        default:
            return false
        }
    }

    var statusText: String {
        let base: String
        switch status {
        case .registered: base = "已连接"
        case .working:    base = "执行中"
        case .idle:       base = "等待输入"
        case .done:       base = "已完成"
        case .error:      base = "出错"
        }
        return lifecycle == .ended ? "\(base) · 已结束" : base
    }

    func statusDotColor(theme: ThemeColors) -> NSColor {
        switch status {
        case .idle:       return theme.nsAccent
        case .done:       return .systemGreen
        case .error:      return .systemRed
        case .working:    return theme.nsAccent
        case .registered: return theme.nsAccent
        }
    }

    var statusDotHasGlow: Bool {
        switch status {
        case .idle, .done, .error: return true
        default: return false
        }
    }

    var rowAlpha: CGFloat {
        switch (status, lifecycle) {
        case (_, .active): return 1.0
        case (.done, .ended), (.error, .ended), (.working, .ended): return 0.7
        default: return 0.5
        }
    }

    /// hostApp 的显示名（用于 UI）
    var hostAppDisplayName: String {
        switch hostApp {
        case "cursor":   return "Cursor"
        case "vscode":   return "VSCode"
        case "terminal": return "Terminal"
        case "iterm2":   return "iTerm2"
        case "wezterm":  return "WezTerm"
        case "warp":     return "Warp"
        default:         return hostApp
        }
    }
}

// MARK: - SessionGroup

struct SessionGroup {
    let cwdNormalized: String
    var displayName: String
    var sessions: [CoderSession]
}

// MARK: - CoderSessionPreference（本轮不扩展）

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

// MARK: - HostAppMapping

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

变更说明：
- 删除：`isHidden`, `topic`, `MatchConfidence.low`（只保留 `.high` 和 `.none`）
- 新增：`resolvedWindowID`, `shortID`, `hostAppDisplayName`, `SessionGroup`
- 保留：`isActionable`, `sortTier`, `sortDate`, `statusText`, `statusDotColor`, `CoderSessionPreference`（不动）

- [ ] **Step 2: 编译（预期失败，因为其他文件还引用旧字段）**

Run: `make build 2>&1 | head -20`

记录报错的文件和行号，确认只有预期的编译错误（topic, isHidden, .low 等引用）。

- [ ] **Step 3: Commit（模型层先提交）**

```bash
git add FocusPilot/Models/CoderSession.swift
git commit -m "refactor(models): CoderSession V2 — 删 topic/isHidden，加 SessionGroup/shortID/resolvedWindowID

- MatchConfidence 去掉 .low（fallback 无证据时一律 .none）
- 新增 SessionGroup 分组结构
- 新增 hostAppDisplayName 计算属性
- 保留 isActionable/CoderSessionPreference"
```

---

### Task 2: CoderBridgeService 重构

**Files:**
- Modify: `FocusPilot/Services/CoderBridgeService.swift`

- [ ] **Step 1: 完整重写 CoderBridgeService.swift**

用以下内容替换全部内容：

```swift
import AppKit

class CoderBridgeService: NSObject {
    static let shared = CoderBridgeService()

    private(set) var sessions: [CoderSession] = []
    private var cleanupTimer: Timer?

    /// 折叠的目录组（UI 状态）
    var collapsedGroups: Set<String> = []

    private override init() {
        super.init()
    }

    // MARK: - Lifecycle

    func start() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleDistributedNotification(_:)),
            name: NSNotification.Name("com.focuscopilot.coder-bridge"),
            object: nil
        )
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
                if self?.sessions.contains(where: { $0.sessionID == sid }) != true {
                    self?.handleSessionStart(sid: sid, seq: 0, toolStr: toolStr, cwd: cwd, cwdNormalized: cwdNormalized, hostApp: hostApp)
                }
                self?.handleSessionUpdate(sid: sid, seq: seq, statusStr: statusStr)
            case "session.end":
                self?.handleSessionEnd(sid: sid, seq: seq)
            default:
                break
            }
        }
    }

    private func handleSessionStart(sid: String, seq: Int, toolStr: String, cwd: String, cwdNormalized: String, hostApp: String) {
        if sessions.contains(where: { $0.sessionID == sid }) { return }

        let session = CoderSession(
            sessionID: sid,
            tool: CoderTool(rawValue: toolStr) ?? .claude,
            cwd: cwd,
            cwdNormalized: cwdNormalized,
            hostApp: hostApp,
            status: .registered,
            lifecycle: .active,
            lastSeq: seq,
            lastUpdate: Date(),
            lastInteraction: nil,
            manualWindowID: nil,
            resolvedWindowID: nil
        )

        sessions.append(session)
        postSessionChanged()
    }

    private func handleSessionUpdate(sid: String, seq: Int, statusStr: String) {
        guard let index = sessions.firstIndex(where: { $0.sessionID == sid }) else { return }
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
        if seq <= sessions[index].lastSeq { return }

        sessions[index].lifecycle = .ended
        sessions[index].lastSeq = seq
        sessions[index].lastUpdate = Date()
        postSessionChanged()
    }

    // MARK: - Window Resolution

    /// 只统计 active session 的 manualWindowID（手动绑定 = 强占用）
    private var occupiedWindowIDs: Set<CGWindowID> {
        Set(sessions.compactMap { s in
            guard s.lifecycle == .active else { return nil }
            return s.manualWindowID
        })
    }

    func resolveWindowForSession(_ session: CoderSession) -> (CGWindowID?, MatchConfidence) {
        // 第一优先：用户手动绑定
        if let manual = session.manualWindowID {
            if windowExists(manual) {
                return (manual, .high)
            } else {
                if let index = sessions.firstIndex(where: { $0.sessionID == session.sessionID }) {
                    sessions[index].manualWindowID = nil
                }
            }
        }

        // fallback：排除已被手动绑定占用的窗口
        let occupied = occupiedWindowIDs
        let candidateWindows = findWindowsForHostApp(session.hostApp)
            .filter { !occupied.contains($0.0) }

        if candidateWindows.isEmpty {
            return (nil, .none)
        }

        // basename 匹配：仅当唯一命中且未占用时才 .high
        let basename = session.cwdBasename
        let matches = candidateWindows.filter { $0.1.contains(basename) }
        if matches.count == 1 {
            let wid = matches[0].0
            // 存弱记录（不用于强占用仲裁）
            if let index = sessions.firstIndex(where: { $0.sessionID == session.sessionID }) {
                sessions[index].resolvedWindowID = wid
            }
            return (wid, .high)
        }

        // 其他情况一律 .none — 宁可不绑定也不要绑错
        return (nil, .none)
    }

    private func windowExists(_ windowID: CGWindowID) -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return windowList.contains { ($0[kCGWindowNumber as String] as? CGWindowID) == windowID }
    }

    private func findWindowsForHostApp(_ hostApp: String) -> [(CGWindowID, String)] {
        guard let bundleID = HostAppMapping.bundleID(for: hostApp) else { return [] }
        guard let runningApp = AppMonitor.shared.runningApps.first(where: { $0.bundleID == bundleID }) else { return [] }
        return runningApp.windows.map { ($0.id, $0.title) }
    }

    // MARK: - Session Queries

    /// 按目录分组，组内排序，组间按最新 sortDate 排序
    var groupedSessions: [SessionGroup] {
        // 按 cwdNormalized 分组
        var groupMap: [String: [CoderSession]] = [:]
        for session in sessions {
            groupMap[session.cwdNormalized, default: []].append(session)
        }

        // 检测同名目录需要消歧
        var basenameCount: [String: Int] = [:]
        for key in groupMap.keys {
            let basename = (key as NSString).lastPathComponent
            basenameCount[basename, default: 0] += 1
        }

        var groups: [SessionGroup] = []
        for (cwdNormalized, sessions) in groupMap {
            let basename = (cwdNormalized as NSString).lastPathComponent
            let displayName: String
            if basenameCount[basename, default: 1] > 1 {
                // 同名消歧：补父级目录
                let parent = ((cwdNormalized as NSString).deletingLastPathComponent as NSString).lastPathComponent
                displayName = "\(basename) (\(parent))"
            } else {
                displayName = basename.isEmpty ? "~" : basename
            }

            // 组内排序：active 在前 + sortDate 倒排
            let sorted = sessions.sorted { a, b in
                if a.sortTier != b.sortTier { return a.sortTier < b.sortTier }
                return a.sortDate > b.sortDate
            }

            groups.append(SessionGroup(cwdNormalized: cwdNormalized, displayName: displayName, sessions: sorted))
        }

        // 组间排序：按组内最新 sortDate 倒排
        groups.sort { a, b in
            let aDate = a.sessions.first?.sortDate ?? .distantPast
            let bDate = b.sessions.first?.sortDate ?? .distantPast
            return aDate > bDate
        }

        return groups
    }

    var actionableCount: Int {
        sessions.filter { $0.isActionable }.count
    }

    /// 定位 session 对应的 transcript 文件路径
    func transcriptPath(for session: CoderSession) -> String? {
        let claudeProjectsDir = NSHomeDirectory() + "/.claude/projects"
        let fm = FileManager.default
        guard fm.fileExists(atPath: claudeProjectsDir) else { return nil }

        let sanitized = session.cwdNormalized.replacingOccurrences(of: "/", with: "-")
        let jsonlPath = claudeProjectsDir + "/" + sanitized + "/" + session.sessionID + ".jsonl"
        if fm.fileExists(atPath: jsonlPath) { return jsonlPath }

        if let dirs = try? fm.contentsOfDirectory(atPath: claudeProjectsDir) {
            for dir in dirs {
                let candidate = claudeProjectsDir + "/" + dir + "/" + session.sessionID + ".jsonl"
                if fm.fileExists(atPath: candidate) { return candidate }
            }
        }
        return nil
    }

    /// 从 transcript 提取最近一条用户 query 摘要
    func latestQuerySummary(for session: CoderSession, maxLength: Int = 50) -> String? {
        guard let path = transcriptPath(for: session),
              let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        let lines = content.components(separatedBy: "\n").reversed()
        for line in lines {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = json["type"] as? String, type == "user",
                  let message = json["message"] as? [String: Any],
                  let role = message["role"] as? String, role == "user" else { continue }

            var text = ""
            if let contentStr = message["content"] as? String {
                text = contentStr
            } else if let contentArr = message["content"] as? [[String: Any]] {
                for block in contentArr {
                    if let bt = block["type"] as? String, bt == "text", let t = block["text"] as? String {
                        text = t; break
                    }
                }
            }
            if text.isEmpty { continue }

            text = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            if text.count > maxLength { text = String(text.prefix(maxLength)) + "..." }
            return text
        }
        return nil
    }

    // MARK: - Session Actions

    func updateLastInteraction(sid: String) {
        guard let index = sessions.firstIndex(where: { $0.sessionID == sid }) else { return }
        sessions[index].lastInteraction = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.postSessionChanged()
        }
    }

    func sessionOccupyingWindow(_ windowID: CGWindowID, excludingSid: String) -> String? {
        sessions.first(where: {
            $0.sessionID != excludingSid && $0.lifecycle == .active && $0.manualWindowID == windowID
        })?.sessionID
    }

    func bindSessionToWindow(sid: String, windowID: CGWindowID) {
        guard let index = sessions.firstIndex(where: { $0.sessionID == sid }) else { return }

        if let occupierSid = sessionOccupyingWindow(windowID, excludingSid: sid),
           let occupierIndex = sessions.firstIndex(where: { $0.sessionID == occupierSid }) {
            sessions[occupierIndex].manualWindowID = nil
        }

        sessions[index].manualWindowID = windowID
        postSessionChanged()
    }

    func removeSession(_ sid: String) {
        sessions.removeAll { $0.sessionID == sid }
        postSessionChanged()
    }

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
            if now.timeIntervalSince(session.lastUpdate) > 120 {
                changed = true; return true
            }
            return false
        }
        if changed { postSessionChanged() }
    }

    // MARK: - Notification

    private func postSessionChanged() {
        NotificationCenter.default.post(name: Constants.Notifications.coderBridgeSessionChanged, object: nil)
    }
}
```

变更说明：
- 删除：`displayName(for:)`, `updateTopic()`, `sortedVisibleSessions`（被 `groupedSessions` 替代）
- 新增：`groupedSessions`（分组+同名消歧+排序）, `collapsedGroups`
- 修正：`resolveWindowForSession` 去掉 `.low`，basename 匹配必须唯一命中才 `.high`，否则 `.none`
- 修正：`actionableCount` 去掉 `isHidden` 过滤
- 保留：`latestQuerySummary`, `transcriptPath`, `bindSessionToWindow`, `sessionOccupyingWindow`

- [ ] **Step 2: 编译验证**

Run: `make build`

Expected: 可能有 QuickPanel 文件的编译错误（引用旧方法），这些在 Task 3-5 中修复。

- [ ] **Step 3: Commit**

```bash
git add FocusPilot/Services/CoderBridgeService.swift
git commit -m "refactor(service): CoderBridgeService V2 — 分组逻辑 + fallback 收紧

- 新增 groupedSessions 按 cwdNormalized 分组 + 同名消歧
- resolveWindowForSession: basename 必须唯一命中才 .high，否则 .none
- occupiedWindowIDs 仅统计 manualWindowID
- 删除 displayName/updateTopic/sortedVisibleSessions"
```

---

### Task 3: QuickPanelView — buildAITabContent 改为分组展示

**Files:**
- Modify: `FocusPilot/QuickPanel/QuickPanelView.swift`

- [ ] **Step 1: 替换 buildAITabContent 方法**

找到现有的 `private func buildAITabContent()` 方法（约在 1853-1876 行），替换为：

```swift
    private func buildAITabContent() {
        let groups = CoderBridgeService.shared.groupedSessions

        if groups.isEmpty {
            let label = createLabel(
                "还没有 AI 编码会话\n启动一个 AI 编码工具后\n会自动显示在这里",
                size: 11,
                color: ConfigStore.shared.currentThemeColors.nsTextTertiary
            )
            label.alignment = .center
            label.maximumNumberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            label.translatesAutoresizingMaskIntoConstraints = false
            contentStack.addArrangedSubview(label)
            label.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
            return
        }

        let theme = ConfigStore.shared.currentThemeColors

        for group in groups {
            // 目录组行
            let isCollapsed = CoderBridgeService.shared.collapsedGroups.contains(group.cwdNormalized)
            let groupRow = HoverableRowView()
            groupRow.translatesAutoresizingMaskIntoConstraints = false
            groupRow.heightAnchor.constraint(equalToConstant: Constants.Panel.appRowHeight).isActive = true

            let groupStack = NSStackView()
            groupStack.orientation = .horizontal
            groupStack.alignment = .centerY
            groupStack.spacing = Constants.Design.Spacing.sm
            groupStack.translatesAutoresizingMaskIntoConstraints = false
            groupRow.addSubview(groupStack)
            NSLayoutConstraint.activate([
                groupStack.leadingAnchor.constraint(equalTo: groupRow.leadingAnchor, constant: Constants.Design.Spacing.sm),
                groupStack.trailingAnchor.constraint(equalTo: groupRow.trailingAnchor, constant: -Constants.Design.Spacing.sm),
                groupStack.centerYAnchor.constraint(equalTo: groupRow.centerYAnchor),
            ])

            // 折叠箭头
            let chevronName = isCollapsed ? "chevron.right" : "chevron.down"
            if let chevronImage = Self.cachedSymbol(name: chevronName, size: 10, weight: .medium) {
                let chevron = NSImageView(image: chevronImage)
                chevron.contentTintColor = theme.nsTextSecondary
                chevron.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    chevron.widthAnchor.constraint(equalToConstant: 14),
                    chevron.heightAnchor.constraint(equalToConstant: 14),
                ])
                groupStack.addArrangedSubview(chevron)
            }

            // 目录名
            let dirLabel = createLabel(group.displayName, size: 12, color: theme.nsTextPrimary)
            dirLabel.font = .systemFont(ofSize: 12, weight: .medium)
            groupStack.addArrangedSubview(dirLabel)

            // spacer
            groupStack.addArrangedSubview(createSpacer())

            // session 数量
            let countLabel = createLabel("(\(group.sessions.count))", size: 11, color: theme.nsTextTertiary)
            groupStack.addArrangedSubview(countLabel)

            // 点击折叠/展开
            let cwdKey = group.cwdNormalized
            groupRow.clickHandler = { [weak self] in
                if CoderBridgeService.shared.collapsedGroups.contains(cwdKey) {
                    CoderBridgeService.shared.collapsedGroups.remove(cwdKey)
                } else {
                    CoderBridgeService.shared.collapsedGroups.insert(cwdKey)
                }
                self?.forceReload()
            }

            contentStack.addArrangedSubview(groupRow)

            // session 列表（未折叠时显示）
            if !isCollapsed {
                for session in group.sessions {
                    let row = createSessionRow(session: session)
                    contentStack.addArrangedSubview(row)
                }
            }
        }
    }
```

- [ ] **Step 2: 更新 buildStructuralKey 中 AI Tab 的 key 构建**

找到 `buildStructuralKey()` 方法中对 `.ai` Tab 的处理，替换为：

```swift
        if currentTab == .ai {
            let groups = CoderBridgeService.shared.groupedSessions
            let sessionKeys = groups.flatMap { g in
                g.sessions.map { "\(g.cwdNormalized):\($0.sessionID):\($0.status.rawValue):\($0.lifecycle.rawValue)" }
            }.joined(separator: "|")
            let collapsed = CoderBridgeService.shared.collapsedGroups.sorted().joined(separator: ",")
            parts.append("AI:\(sessionKeys):C:\(collapsed)")
        }
```

- [ ] **Step 3: 编译验证**

Run: `make build`

- [ ] **Step 4: Commit**

```bash
git add FocusPilot/QuickPanel/QuickPanelView.swift
git commit -m "feat(QuickPanel): buildAITabContent 改为目录分组展示

- 一级目录组行（折叠箭头+目录名+session数量）
- 二级 session 行（缩进，复用 createSessionRow）
- 目录组折叠/展开通过 collapsedGroups 管理"
```

---

### Task 4: QuickPanelRowBuilder — createSessionRow + handleSessionClick 重写

**Files:**
- Modify: `FocusPilot/QuickPanel/QuickPanelRowBuilder.swift`

- [ ] **Step 1: 替换 createSessionRow 和 handleSessionClick**

找到现有的 `func createSessionRow(session:)` 和 `private func handleSessionClick(_:)` 方法，替换为：

```swift
    // MARK: - AI Session Row (V2: shortID + hostApp + status + query)

    func createSessionRow(session: CoderSession) -> NSView {
        let theme = ConfigStore.shared.currentThemeColors
        let row = HoverableRowView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let verticalStack = NSStackView()
        verticalStack.orientation = .vertical
        verticalStack.alignment = .leading
        verticalStack.spacing = 2
        verticalStack.translatesAutoresizingMaskIntoConstraints = false

        // === 第一行：● Claude · shortID    hostApp  状态 ===
        let firstLine = NSStackView()
        firstLine.orientation = .horizontal
        firstLine.alignment = .centerY
        firstLine.spacing = 4
        firstLine.translatesAutoresizingMaskIntoConstraints = false

        // 状态圆点（6px）
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
        firstLine.addArrangedSubview(dot)

        // "Claude · a1b2c3d4"
        let idText = "\(session.tool.displayName) · \(session.shortID)"
        let idLabel = createLabel(idText, size: 11, color: theme.nsTextPrimary)
        firstLine.addArrangedSubview(idLabel)

        // spacer
        firstLine.addArrangedSubview(createSpacer())

        // hostApp 显示名
        if !session.hostApp.isEmpty {
            let hostLabel = createLabel(session.hostAppDisplayName, size: 10, color: theme.nsTextTertiary)
            firstLine.addArrangedSubview(hostLabel)
        }

        // 状态文字
        let statusLabel = createLabel(session.statusText, size: 10, color: theme.nsTextSecondary)
        firstLine.addArrangedSubview(statusLabel)

        verticalStack.addArrangedSubview(firstLine)

        // === 第二行：query 摘要 ===
        let queryText: String
        if let query = CoderBridgeService.shared.latestQuerySummary(for: session, maxLength: 60) {
            queryText = "\"\(query)\""
        } else {
            queryText = "等待输入..."
        }
        let queryLabel = createLabel(queryText, size: 10, color: theme.nsTextTertiary)
        queryLabel.lineBreakMode = .byTruncatingTail
        queryLabel.translatesAutoresizingMaskIntoConstraints = false
        verticalStack.addArrangedSubview(queryLabel)

        // 布局（缩进 windowIndent 与现有窗口行对齐）
        row.addSubview(verticalStack)
        NSLayoutConstraint.activate([
            verticalStack.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: Constants.Panel.windowIndent),
            verticalStack.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -Constants.Design.Spacing.sm),
            verticalStack.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])

        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        row.alphaValue = session.rowAlpha

        row.clickHandler = { [weak self] in
            self?.handleSessionClick(session)
        }

        row.contextMenuProvider = { [weak self] in
            self?.createSessionContextMenu(session: session)
        }

        return row
    }

    private func handleSessionClick(_ session: CoderSession) {
        CoderBridgeService.shared.updateLastInteraction(sid: session.sessionID)
        let (windowID, confidence) = CoderBridgeService.shared.resolveWindowForSession(session)

        if let wid = windowID, confidence == .high {
            let allWindows = AppMonitor.shared.runningApps.flatMap { $0.windows }
            if let windowInfo = allWindows.first(where: { $0.id == wid }) {
                WindowService.shared.activateWindow(windowInfo)
                (self.window as? QuickPanelWindow)?.yieldLevel()
                return
            }
        }

        // .none: 只激活宿主 App
        if !session.hostApp.isEmpty,
           let bundleID = HostAppMapping.bundleID(for: session.hostApp),
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: appURL, configuration: config)
            (self.window as? QuickPanelWindow)?.yieldLevel()
        }
    }
```

注意：`handleSessionClick` 中不再有 `.low` 分支和 flash 提示。只有 `.high`（手动绑定或唯一 basename 匹配）才切窗口，否则只激活宿主 App。

- [ ] **Step 2: 编译验证**

Run: `make build`

- [ ] **Step 3: Commit**

```bash
git add FocusPilot/QuickPanel/QuickPanelRowBuilder.swift
git commit -m "feat(QuickPanel): session 行 V2 — shortID + hostApp + status + query

- 第一行：● Claude · a1b2c3d4  Cursor  执行中
- 第二行：query 摘要或'等待输入...'
- 缩进 windowIndent（28px）与窗口行对齐
- handleSessionClick: 只有 .high 才切窗口，.none 只激活宿主 App"
```

---

### Task 5: QuickPanelMenuHandler — 右键菜单重写

**Files:**
- Modify: `FocusPilot/QuickPanel/QuickPanelMenuHandler.swift`

- [ ] **Step 1: 替换 AI Session 右键菜单部分**

找到 `// MARK: - AI Session 右键菜单` 到文件末尾 `}` 之前的所有代码，替换为：

```swift
    // MARK: - AI Session 右键菜单

    func createSessionContextMenu(session: CoderSession) -> NSMenu? {
        let menu = NSMenu()

        // 绑定到当前窗口
        let bindItem = NSMenuItem(title: "绑定到当前窗口", action: #selector(handleBindToCurrentWindow(_:)), keyEquivalent: "")
        bindItem.target = self
        bindItem.representedObject = session.sessionID
        menu.addItem(bindItem)

        // 复制 Session ID
        let copyItem = NSMenuItem(title: "复制 Session ID", action: #selector(handleCopySessionID(_:)), keyEquivalent: "")
        copyItem.target = self
        copyItem.representedObject = session.sessionID
        menu.addItem(copyItem)

        if session.lifecycle == .ended {
            menu.addItem(NSMenuItem.separator())

            let removeItem = NSMenuItem(title: "移除此会话", action: #selector(handleRemoveSession(_:)), keyEquivalent: "")
            removeItem.target = self
            removeItem.representedObject = session.sessionID
            menu.addItem(removeItem)

            let removeAllItem = NSMenuItem(title: "移除所有已结束会话", action: #selector(handleRemoveAllEndedSessions), keyEquivalent: "")
            removeAllItem.target = self
            menu.addItem(removeAllItem)
        }

        return menu
    }

    @objc func handleBindToCurrentWindow(_ sender: NSMenuItem) {
        guard let sid = sender.representedObject as? String else { return }

        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let frontBundleID = frontApp.bundleIdentifier else { return }

        let pid = frontApp.processIdentifier
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return }

        var targetWindowID: CGWindowID?
        var targetTitle = ""
        for windowInfo in windowList {
            guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid,
                  let layer = windowInfo[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let wid = windowInfo[kCGWindowNumber as String] as? CGWindowID else { continue }
            targetWindowID = wid
            targetTitle = windowInfo[kCGWindowName as String] as? String ?? ""
            break
        }

        guard let wid = targetWindowID else { return }

        let appName = frontApp.localizedName ?? frontBundleID
        let displayTitle = targetTitle.isEmpty ? appName : "\(appName) — \(targetTitle)"

        let alert = NSAlert()
        alert.messageText = "绑定到当前窗口"

        if let occupierSid = CoderBridgeService.shared.sessionOccupyingWindow(wid, excludingSid: sid) {
            let occupierSession = CoderBridgeService.shared.sessions.first(where: { $0.sessionID == occupierSid })
            let occupierName = occupierSession?.shortID ?? "其他会话"
            alert.informativeText = "「\(displayTitle)」当前已被会话 \(occupierName) 绑定。\n确定替换绑定？（旧绑定将被清除）"
        } else {
            alert.informativeText = "确定将此会话绑定到「\(displayTitle)」？"
        }

        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        if alert.runModal() == .alertFirstButtonReturn {
            CoderBridgeService.shared.bindSessionToWindow(sid: sid, windowID: wid)
            forceReload()
        }
    }

    @objc func handleCopySessionID(_ sender: NSMenuItem) {
        guard let sid = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sid, forType: .string)
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

- [ ] **Step 3: Commit**

```bash
git add FocusPilot/QuickPanel/QuickPanelMenuHandler.swift
git commit -m "feat(QuickPanel): 右键菜单 V2 — 绑定当前窗口 + 复制 Session ID

- 绑定冲突提示（显示占用者 shortID）
- 复制完整 sessionID 到剪贴板
- 删除编辑主题相关代码"
```

---

### Task 6: 端到端验证

- [ ] **Step 1: 编译安装**

Run: `make install`

Expected: 编译成功，FocusPilot 启动

- [ ] **Step 2: 验证目录分组**

1. 在两个不同项目目录下各开一个 Claude Code
2. AI Tab 应显示两个目录组，每组下有一条 session
3. 折叠/展开目录组

- [ ] **Step 3: 验证多 session 不收敛到同一窗口**

1. 在同一个 Cursor 中开两个 Claude Code（同目录）
2. 两条 session 应在同一个目录组下
3. 点击第一条 → 应激活宿主 App（.none，因为多窗口无法区分）
4. 点击第二条 → 同样激活宿主 App
5. 不应出现两条都切到同一个窗口的情况

- [ ] **Step 4: 验证手动绑定 + 冲突替换**

1. 右键 session A → "绑定到当前窗口" → 确认
2. 点击 session A → 应切到绑定的窗口
3. 右键 session B → "绑定到当前窗口"（绑定到 A 已占用的窗口）
4. 应出现冲突提示，确认后 A 的绑定被清除

- [ ] **Step 5: 验证复制 Session ID**

1. 右键某条 session → "复制 Session ID"
2. 粘贴到文本编辑器，确认是完整 UUID

- [ ] **Step 6: Commit（如有修复）+ Push**

```bash
git add -A
git commit -m "fix: V2 端到端集成修复"
git push
```
