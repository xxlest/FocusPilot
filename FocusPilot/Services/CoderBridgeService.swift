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
            matchConfidence: .none
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

    var actionableCount: Int {
        sessions.filter { !$0.isHidden && $0.isActionable }.count
    }

    // MARK: - Session Actions

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
