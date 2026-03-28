import AppKit

/// 管理 AI 编码工具会话的服务
/// 通过 DistributedNotificationCenter 接收 coder-bridge 事件
/// 维护纯运行时的 CoderSession 列表
class CoderBridgeService: NSObject {
    static let shared = CoderBridgeService()

    /// 当前活跃的 AI 会话列表（运行时，不持久化）
    private(set) var sessions: [CoderSession] = []

    /// 清理定时器
    private var cleanupTimer: Timer?

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
                // 如果 session 不存在（已打开的会话），自动创建后再更新
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
            matchConfidence: .none,
            lastInteraction: nil,
            taskName: nil,
            manualWindowID: nil
        )

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

    func resolveWindowForSession(_ session: CoderSession) -> (CGWindowID?, MatchConfidence) {
        // 第零层：用户手动绑定（优先级最高）
        if let manual = session.manualWindowID {
            if windowExists(manual) {
                return (manual, .high)
            } else {
                // 失效，自动清空
                if let index = sessions.firstIndex(where: { $0.sessionID == session.sessionID }) {
                    sessions[index].manualWindowID = nil
                }
            }
        }

        // 第一层：初始关联仍有效？
        if let initial = session.initialCandidateWindowID, windowExists(initial) {
            return (initial, .high)
        }

        let candidateWindows = findWindowsForHostApp(session.hostApp)

        if candidateWindows.isEmpty {
            return (nil, .none)
        }

        let basename = session.cwdBasename
        for (wid, title) in candidateWindows {
            if title.contains(basename) {
                return (wid, .high)
            }
        }

        if let first = candidateWindows.first {
            return (first.0, .low)
        }

        return (nil, .none)
    }

    private func windowExists(_ windowID: CGWindowID) -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return windowList.contains { ($0[kCGWindowNumber as String] as? CGWindowID) == windowID }
    }

    private func findWindowsForHostApp(_ hostApp: String) -> [(CGWindowID, String)] {
        guard let bundleID = HostAppMapping.bundleID(for: hostApp) else {
            return []
        }

        guard let runningApp = AppMonitor.shared.runningApps.first(where: { $0.bundleID == bundleID }) else {
            return []
        }

        return runningApp.windows.map { ($0.id, $0.title) }
    }

    // MARK: - Session Queries

    /// 获取 session 的显示名（preference 优先，否则 cwdBasename）
    func displayName(for session: CoderSession) -> String {
        if let pref = ConfigStore.shared.sessionPreferences[session.preferenceKey],
           !pref.displayName.isEmpty {
            return pref.displayName
        }
        return session.cwdBasename
    }

    /// 定位 session 对应的 transcript 文件路径
    func transcriptPath(for session: CoderSession) -> String? {
        let claudeProjectsDir = NSHomeDirectory() + "/.claude/projects"
        let fm = FileManager.default
        guard fm.fileExists(atPath: claudeProjectsDir) else { return nil }

        // sanitized-cwd：把 / 替换为 -，去掉开头的 -
        let sanitized = session.cwdNormalized
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let jsonlPath = claudeProjectsDir + "/" + sanitized + "/" + session.sessionID + ".jsonl"
        if fm.fileExists(atPath: jsonlPath) { return jsonlPath }

        // 兜底：遍历 projects 目录找匹配的 sessionID
        if let dirs = try? fm.contentsOfDirectory(atPath: claudeProjectsDir) {
            for dir in dirs {
                let candidate = claudeProjectsDir + "/" + dir + "/" + session.sessionID + ".jsonl"
                if fm.fileExists(atPath: candidate) { return candidate }
            }
        }
        return nil
    }

    /// 从 transcript 文件中提取最近一条用户 query 的摘要
    func latestQuerySummary(for session: CoderSession, maxLength: Int = 40) -> String? {
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
                  let type = json["type"] as? String,
                  type == "user",
                  let message = json["message"] as? [String: Any],
                  let role = message["role"] as? String,
                  role == "user" else {
                continue
            }

            var text = ""
            if let contentStr = message["content"] as? String {
                text = contentStr
            } else if let contentArr = message["content"] as? [[String: Any]] {
                for block in contentArr {
                    if let blockType = block["type"] as? String, blockType == "text",
                       let blockText = block["text"] as? String {
                        text = blockText
                        break
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

    var sortedVisibleSessions: [CoderSession] {
        sessions
            .filter { !$0.isHidden }
            .sorted { a, b in
                if a.sortTier != b.sortTier {
                    return a.sortTier < b.sortTier
                }
                return a.sortDate > b.sortDate
            }
    }

    var actionableCount: Int {
        sessions.filter { !$0.isHidden && $0.isActionable }.count
    }

    // MARK: - Session Actions

    func updateLastInteraction(sid: String) {
        guard let index = sessions.firstIndex(where: { $0.sessionID == sid }) else { return }
        sessions[index].lastInteraction = Date()
        postSessionChanged()
    }

    func updateTaskName(sid: String, taskName: String?) {
        guard let index = sessions.firstIndex(where: { $0.sessionID == sid }) else { return }
        sessions[index].taskName = taskName
        postSessionChanged()
    }

    func bindSessionToWindow(sid: String, windowID: CGWindowID) {
        guard let index = sessions.firstIndex(where: { $0.sessionID == sid }) else { return }
        sessions[index].initialCandidateWindowID = windowID
        sessions[index].candidateWindowID = windowID
        sessions[index].matchConfidence = .high
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

            let elapsed = now.timeIntervalSince(session.lastUpdate)

            if (session.status == .done || session.status == .error) && elapsed > 1800 {
                changed = true
                return true
            }
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
