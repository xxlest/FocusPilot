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

        let session = CoderSession(
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
            lastInteraction: nil,
            topic: nil,
            manualWindowID: nil
        )

        // 不做自动初始绑定（存在 race condition：用户可能已切走窗口）
        // 窗口绑定仅通过：
        //   1. 用户手动"绑定到当前窗口"（写入 manualWindowID）
        //   2. 点击时回退匹配（cwd basename 匹配窗口标题）

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

    /// 已被其他 active session 的 manualWindowID 占用的窗口 ID 集合
    private var occupiedWindowIDs: Set<CGWindowID> {
        Set(sessions.compactMap { s in
            s.lifecycle == .active ? s.manualWindowID : nil
        })
    }

    func resolveWindowForSession(_ session: CoderSession) -> (CGWindowID?, MatchConfidence) {
        // 第一优先：用户手动绑定（manualWindowID）
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

        // 回退匹配：按 hostApp 找候选窗口，排除已被其他 session 占用的窗口
        let occupied = occupiedWindowIDs
        let candidateWindows = findWindowsForHostApp(session.hostApp)
            .filter { !occupied.contains($0.0) }

        if candidateWindows.isEmpty {
            return (nil, .none)
        }

        // 按 cwd basename 匹配窗口标题
        let basename = session.cwdBasename
        for (wid, title) in candidateWindows {
            if title.contains(basename) {
                return (wid, .high)
            }
        }

        // 只有一个未占用候选窗口时才返回 .low，多个时返回 .none（无法区分）
        if candidateWindows.count == 1 {
            return (candidateWindows[0].0, .low)
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
        // 延迟 0.5 秒再刷新排序，让窗口切换先完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.postSessionChanged()
        }
    }

    func updateTopic(sid: String, topic: String?) {
        guard let index = sessions.firstIndex(where: { $0.sessionID == sid }) else { return }
        sessions[index].topic = topic
        postSessionChanged()
    }

    /// 检查窗口是否已被其他 active session 占用，返回占用者的 sessionID
    func sessionOccupyingWindow(_ windowID: CGWindowID, excludingSid: String) -> String? {
        sessions.first(where: {
            $0.sessionID != excludingSid && $0.lifecycle == .active && $0.manualWindowID == windowID
        })?.sessionID
    }

    func bindSessionToWindow(sid: String, windowID: CGWindowID) {
        guard let index = sessions.firstIndex(where: { $0.sessionID == sid }) else { return }

        // 冲突检测：如果已被其他 session 占用，清除旧绑定
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

            let elapsed = now.timeIntervalSince(session.lastUpdate)

            // 所有 ended 会话统一 2 分钟后自动移除
            if elapsed > 120 {
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
