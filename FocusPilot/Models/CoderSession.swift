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

    var initialCandidateWindowID: CGWindowID?
    var candidateWindowID: CGWindowID?
    var matchConfidence: MatchConfidence

    var lastInteraction: Date?           // 用户点击此 session 的时间，nil 表示未操作过
    var topic: String?                   // 主题：用户手动编辑过则固定，否则自动取 query 摘要
    var autoTopic: String?               // 自动主题：首次 query 时初始化一次，后续不自动覆盖
    var manualWindowID: CGWindowID?      // 用户手动绑定的窗口，优先级最高，失效时自动清空

    var id: String { sessionID }

    var preferenceKey: String {
        "\(tool.rawValue):\(cwdNormalized):\(hostApp)"
    }

    var cwdBasename: String {
        let homePath = NSHomeDirectory()
        if cwd == homePath || cwd == homePath + "/" {
            return "~"
        }
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? "~" : name
    }

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

    var sortTier: Int {
        if lifecycle == .ended { return 2 }
        return 1
    }

    /// 排序用的时间：lastInteraction 优先，无则退回 lastUpdate
    var sortDate: Date {
        lastInteraction ?? lastUpdate
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
        if lifecycle == .ended {
            return "\(base) · 已结束"
        }
        return base
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
}

// MARK: - CoderSessionPreference

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
