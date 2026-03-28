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
    let sessionID: String
    var tool: CoderTool
    var cwd: String
    var cwdNormalized: String
    var hostApp: String
    var status: SessionStatus
    var lifecycle: SessionLifecycle
    var lastSeq: Int
    var lastUpdate: Date
    var lastInteraction: Date?
    var isRead: Bool = false             // done 状态时是否已读（点击过则已读）

    var autoWindowID: CGWindowID?       // session.start 时自动采样（弱绑定，不参与占用仲裁）
    var manualWindowID: CGWindowID?

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

    func statusTextColor(theme: ThemeColors) -> NSColor {
        if lifecycle == .ended { return NSColor(calibratedWhite: 0.35, alpha: 1.0) }
        switch status {
        case .working:    return .systemGreen
        case .idle:       return NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.04, alpha: 1.0)
        case .done:       return isRead ? NSColor(calibratedWhite: 0.35, alpha: 1.0) : .systemGreen
        case .error:      return .systemRed
        case .registered: return theme.nsTextSecondary
        }
    }

    func statusDotColor(theme: ThemeColors) -> NSColor {
        switch status {
        case .working:    return .systemGreen
        case .idle:       return NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.04, alpha: 1.0) // 黄色
        case .done:       return isRead ? NSColor(calibratedWhite: 0.35, alpha: 1.0) : .systemGreen
        case .error:      return .systemRed
        case .registered: return NSColor(calibratedWhite: 0.35, alpha: 1.0) // 灰色
        }
    }

    var statusDotHasGlow: Bool {
        switch status {
        case .working, .idle, .error: return true
        case .done: return !isRead
        default: return false
        }
    }

    var rowAlpha: CGFloat {
        if lifecycle == .ended { return 0.4 }
        if status == .done && isRead { return 0.6 }
        return 1.0
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

    static func displayName(for hostApp: String) -> String {
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
