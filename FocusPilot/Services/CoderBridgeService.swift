import AppKit

class CoderBridgeService: NSObject {
    static let shared = CoderBridgeService()

    private(set) var sessions: [CoderSession] = []
    private var cleanupTimer: Timer?
    private var queryCache: [String: (summary: String, timestamp: Date)] = [:]

    enum BindingState {
        case manual           // manualWindowID != nil
        case autoValid        // manualWindowID == nil, autoWindowID != nil, 无冲突
        case autoConflicted   // manualWindowID == nil, autoWindowID != nil, 有冲突（仅 terminal）
        case missing          // 两个 ID 都是 nil
    }

    func bindingState(for session: CoderSession) -> BindingState {
        if session.manualWindowID != nil { return .manual }
        if session.autoWindowID != nil {
            return isAutoWindowConflicted(for: session) ? .autoConflicted : .autoValid
        }
        return .missing
    }

    /// 统一策略入口：该 session 的宿主 app 是否允许多 session 共享同一窗口
    func allowsSharedBinding(for session: CoderSession) -> Bool {
        ConfigStore.shared.preferences.multiBindApps.contains(session.hostApp)
    }

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
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
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
        let hostKindStr = userInfo["hostKind"] as? String ?? "terminal"
        let hostKind = HostKind(rawValue: hostKindStr) ?? .terminal

        guard !sid.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            switch event {
            case "session.start":
                self?.handleSessionStart(sid: sid, seq: seq, toolStr: toolStr, cwd: cwd, cwdNormalized: cwdNormalized, hostApp: hostApp, hostKind: hostKind)
            case "session.update":
                if self?.sessions.contains(where: { $0.sessionID == sid }) != true {
                    self?.handleSessionStart(sid: sid, seq: 0, toolStr: toolStr, cwd: cwd, cwdNormalized: cwdNormalized, hostApp: hostApp, hostKind: hostKind)
                }
                self?.handleSessionUpdate(sid: sid, seq: seq, statusStr: statusStr)
            case "session.end":
                self?.handleSessionEnd(sid: sid, seq: seq)
            default:
                break
            }
        }
    }

    private func handleSessionStart(sid: String, seq: Int, toolStr: String, cwd: String, cwdNormalized: String, hostApp: String, hostKind: HostKind) {
        if sessions.contains(where: { $0.sessionID == sid }) { return }

        var session = CoderSession(
            sessionID: sid,
            tool: CoderTool(rawValue: toolStr) ?? .claude,
            cwd: cwd,
            cwdNormalized: cwdNormalized,
            hostApp: hostApp,
            hostKind: hostKind,
            status: .registered,
            lifecycle: .active,
            lastSeq: seq,
            lastUpdate: Date(),
            lastInteraction: nil,
            autoWindowID: nil,
            manualWindowID: nil
        )

        // 自动采样：前台 app 与 hostApp 一致时记录弱绑定
        session.autoWindowID = resolveFrontmostWindow(hostApp: hostApp)

        sessions.append(session)
        postSessionChanged()
    }

    private func handleSessionUpdate(sid: String, seq: Int, statusStr: String) {
        guard let index = sessions.firstIndex(where: { $0.sessionID == sid }) else { return }
        if seq <= sessions[index].lastSeq { return }

        if let newStatus = SessionStatus(rawValue: statusStr) {
            let oldStatus = sessions[index].status
            // 状态变化且进入 actionable 状态时重置已读/忽略标记
            if newStatus != oldStatus {
                switch newStatus {
                case .done:
                    sessions[index].isRead = false
                case .idle, .error:
                    sessions[index].isRead = false
                    sessions[index].isDismissed = false
                default:
                    break
                }
            }
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

    /// 获取当前前台宿主窗口（用于 session.start 自动采样）
    private func resolveFrontmostWindow(hostApp: String) -> CGWindowID? {
        guard !hostApp.isEmpty,
              let expectedBundleID = HostAppMapping.bundleID(for: hostApp),
              let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.bundleIdentifier == expectedBundleID else {
            return nil
        }

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
            return windowID
        }

        return nil
    }

    /// 只统计独占类（非白名单）active session 的 manualWindowID（手动绑定 = 强占用）
    private var occupiedWindowIDs: Set<CGWindowID> {
        Set(sessions.compactMap { s in
            guard s.lifecycle == .active, !allowsSharedBinding(for: s) else { return nil }
            return s.manualWindowID
        })
    }

    /// 检查某个 autoWindowID 是否与其他 active session 冲突（多个 session 指向同一窗口）
    func isAutoWindowConflicted(for session: CoderSession) -> Bool {
        // 白名单内的 app：多 session 共享同窗口是正常的
        if allowsSharedBinding(for: session) { return false }

        guard let auto = session.autoWindowID else { return false }
        let count = sessions.filter {
            $0.sessionID != session.sessionID && $0.lifecycle == .active && $0.autoWindowID == auto
        }.count
        return count > 0
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

        // 第二优先：自动采样弱绑定（冲突时跳过）
        if let auto = session.autoWindowID {
            if !windowExists(auto) {
                // 失效，清空
                if let index = sessions.firstIndex(where: { $0.sessionID == session.sessionID }) {
                    sessions[index].autoWindowID = nil
                }
            } else if !isAutoWindowConflicted(for: session) {
                // 有效且无冲突
                return (auto, .high)
            }
            // 有效但冲突 → 跳过，不使用
        }

        // fallback：排除已被手动绑定占用的窗口（白名单 app 不排除，多 session 可共享）
        let occupied = occupiedWindowIDs
        let candidateWindows = findWindowsForHostApp(session.hostApp)
            .filter { allowsSharedBinding(for: session) || !occupied.contains($0.0) }

        if candidateWindows.isEmpty {
            return (nil, .none)
        }

        // basename 匹配：仅当唯一命中且未占用时才 .high
        let basename = session.cwdBasename
        let matches = candidateWindows.filter { $0.1.contains(basename) }
        if matches.count == 1 {
            return (matches[0].0, .high)
        }

        // 其他情况一律 .none
        return (nil, .none)
    }

    func windowExists(_ windowID: CGWindowID) -> Bool {
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

    // MARK: - Pinning

    /// 置顶的目录组（cwdNormalized），按置顶顺序排列
    var pinnedGroups: [String] = []

    /// 置顶的 session（sessionID），按置顶顺序排列（组内置顶）
    var pinnedSessions: [String] = []

    func pinGroup(_ cwdNormalized: String) {
        pinnedGroups.removeAll { $0 == cwdNormalized }
        pinnedGroups.insert(cwdNormalized, at: 0)
        postSessionChanged()
    }

    func pinSession(_ sid: String) {
        pinnedSessions.removeAll { $0 == sid }
        pinnedSessions.insert(sid, at: 0)
        postSessionChanged()
    }

    // MARK: - Session Queries

    /// 按目录分组，保持注册顺序，支持置顶
    var groupedSessions: [SessionGroup] {
        // 按注册顺序收集目录组（保持首次出现的顺序）
        var orderedKeys: [String] = []
        var groupMap: [String: [CoderSession]] = [:]
        for session in sessions {
            if groupMap[session.cwdNormalized] == nil {
                orderedKeys.append(session.cwdNormalized)
            }
            groupMap[session.cwdNormalized, default: []].append(session)
        }

        // 同名消歧
        var basenameCount: [String: Int] = [:]
        for key in orderedKeys {
            let basename = (key as NSString).lastPathComponent
            basenameCount[basename, default: 0] += 1
        }

        var groups: [SessionGroup] = []
        for cwdNormalized in orderedKeys {
            guard let sessions = groupMap[cwdNormalized] else { continue }
            let basename = (cwdNormalized as NSString).lastPathComponent
            let displayName: String
            if basenameCount[basename, default: 1] > 1 {
                let parent = ((cwdNormalized as NSString).deletingLastPathComponent as NSString).lastPathComponent
                displayName = "\(basename) (\(parent))"
            } else {
                displayName = basename.isEmpty ? "~" : basename
            }

            // 组内排序：置顶的在前，其余保持注册顺序
            let sorted = sessions.sorted { a, b in
                let aPinned = pinnedSessions.firstIndex(of: a.sessionID)
                let bPinned = pinnedSessions.firstIndex(of: b.sessionID)
                if let ai = aPinned, let bi = bPinned { return ai < bi }
                if aPinned != nil { return true }
                if bPinned != nil { return false }
                return false // 保持注册顺序
            }

            groups.append(SessionGroup(cwdNormalized: cwdNormalized, displayName: displayName, sessions: sorted))
        }

        // 组间排序：置顶的在前，其余保持注册顺序
        groups.sort { a, b in
            let aPinned = pinnedGroups.firstIndex(of: a.cwdNormalized)
            let bPinned = pinnedGroups.firstIndex(of: b.cwdNormalized)
            if let ai = aPinned, let bi = bPinned { return ai < bi }
            if aPinned != nil { return true }
            if bPinned != nil { return false }
            return false // 保持注册顺序
        }

        return groups
    }

    var actionableCount: Int {
        sessions.filter { $0.isActionable }.count
    }

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

    func latestQuerySummary(for session: CoderSession, maxLength: Int = 50) -> String? {
        // 缓存 5 秒内有效
        if let cached = queryCache[session.sessionID],
           Date().timeIntervalSince(cached.timestamp) < 5 {
            return cached.summary
        }

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
            queryCache[session.sessionID] = (summary: text, timestamp: Date())
            return text
        }
        return nil
    }

    // MARK: - Session Actions

    /// 最近一次成功切换的 session ID（用于 UI 高亮）
    var activeSessionID: String?

    func markAsRead(sid: String) {
        guard let index = sessions.firstIndex(where: { $0.sessionID == sid }) else { return }
        guard sessions[index].isActionable else { return }
        sessions[index].isRead = true
        postSessionChanged()
    }

    func dismissSession(sid: String) {
        guard let index = sessions.firstIndex(where: { $0.sessionID == sid }) else { return }
        guard sessions[index].lifecycle == .active, !sessions[index].isDismissed else { return }
        sessions[index].isDismissed = true
        postSessionChanged()
    }

    func updateLastInteraction(sid: String) {
        guard let index = sessions.firstIndex(where: { $0.sessionID == sid }) else { return }
        sessions[index].lastInteraction = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.postSessionChanged()
        }
    }

    func sessionOccupyingWindow(_ windowID: CGWindowID, excludingSid: String) -> String? {
        sessions.first(where: {
            $0.sessionID != excludingSid && $0.lifecycle == .active && !allowsSharedBinding(for: $0) && $0.manualWindowID == windowID
        })?.sessionID
    }

    func bindSessionToWindow(sid: String, windowID: CGWindowID) {
        guard let index = sessions.firstIndex(where: { $0.sessionID == sid }) else { return }

        // 仅独占类（非白名单）才驱逐已有绑定
        if !allowsSharedBinding(for: sessions[index]) {
            if let occupierSid = sessionOccupyingWindow(windowID, excludingSid: sid),
               let occupierIndex = sessions.firstIndex(where: { $0.sessionID == occupierSid }) {
                sessions[occupierIndex].manualWindowID = nil
            }
        }

        sessions[index].manualWindowID = windowID
        postSessionChanged()
    }

    func clearManualWindowID(sid: String) {
        guard let index = sessions.firstIndex(where: { $0.sessionID == sid }) else { return }
        sessions[index].manualWindowID = nil
        postSessionChanged()
    }

    func clearAutoWindowID(sid: String) {
        guard let index = sessions.firstIndex(where: { $0.sessionID == sid }) else { return }
        sessions[index].autoWindowID = nil
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
            // 已结束的 session：2 分钟后清除
            if session.lifecycle == .ended {
                if now.timeIntervalSince(session.lastUpdate) > 120 {
                    changed = true; return true
                }
                return false
            }
            // 僵尸 session：状态停留在 registered 超过 30 秒未收到后续事件
            if session.status == .registered && now.timeIntervalSince(session.lastUpdate) > 30 {
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
