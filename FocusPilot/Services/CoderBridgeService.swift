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
            if let index = sessions.firstIndex(where: { $0.sessionID == session.sessionID }) {
                sessions[index].resolvedWindowID = wid
            }
            return (wid, .high)
        }

        // 其他情况一律 .none
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
        var groupMap: [String: [CoderSession]] = [:]
        for session in sessions {
            groupMap[session.cwdNormalized, default: []].append(session)
        }

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
                let parent = ((cwdNormalized as NSString).deletingLastPathComponent as NSString).lastPathComponent
                displayName = "\(basename) (\(parent))"
            } else {
                displayName = basename.isEmpty ? "~" : basename
            }

            let sorted = sessions.sorted { a, b in
                if a.sortTier != b.sortTier { return a.sortTier < b.sortTier }
                return a.sortDate > b.sortDate
            }

            groups.append(SessionGroup(cwdNormalized: cwdNormalized, displayName: displayName, sessions: sorted))
        }

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
