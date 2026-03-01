import AppKit

// MARK: - App 配置（持久化）

struct AppConfig: Codable, Identifiable, Equatable {
    var id: String { bundleID }
    let bundleID: String
    var displayName: String
    var order: Int
    var isFavorite: Bool

    // 自定义解码：兼容旧数据（无 isFavorite 字段时默认 false，忽略旧 pinnedKeywords）
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        displayName = try container.decode(String.self, forKey: .displayName)
        order = try container.decode(Int.self, forKey: .order)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }

    init(bundleID: String, displayName: String, order: Int, isFavorite: Bool = false) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.order = order
        self.isFavorite = isFavorite
    }

    private enum CodingKeys: String, CodingKey {
        case bundleID, displayName, order, isFavorite
    }
}

// MARK: - 运行中的 App 信息（运行时）

class RunningApp: Identifiable, ObservableObject {
    var id: String { bundleID }
    let bundleID: String
    let localizedName: String
    let icon: NSImage
    /// 实际运行中的进程引用（未运行时为 nil）
    let nsApp: NSRunningApplication?
    @Published var windows: [WindowInfo]
    /// 标记该 App 是否真正在运行（未运行的已配置 App 此值为 false）
    @Published var isRunning: Bool

    init(bundleID: String, localizedName: String, icon: NSImage,
         nsApp: NSRunningApplication?, windows: [WindowInfo] = [],
         isRunning: Bool = false) {
        self.bundleID = bundleID
        self.localizedName = localizedName
        self.icon = icon
        self.nsApp = nsApp
        self.windows = windows
        self.isRunning = isRunning
    }
}

// MARK: - 已安装 App 信息

struct InstalledApp: Identifiable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let icon: NSImage
    let url: URL
}

// MARK: - 窗口信息（运行时）

struct WindowInfo: Identifiable, Equatable {
    let id: CGWindowID
    let ownerBundleID: String
    let ownerPID: pid_t
    var title: String
    var bounds: CGRect
    var isMinimized: Bool
    var isFullScreen: Bool

    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - 悬浮球位置（持久化）

struct BallPosition: Codable {
    var x: CGFloat
    var y: CGFloat
    var edge: ScreenEdge

    static let `default` = BallPosition(x: 50, y: 300, edge: .left)
}

enum ScreenEdge: String, Codable {
    case top, bottom, left, right
}

// MARK: - 面板大小（持久化）

struct PanelSize: Codable {
    var width: CGFloat
    var height: CGFloat

    static let `default` = PanelSize(width: 280, height: 400)
}

// MARK: - 偏好设置（持久化）

struct Preferences: Codable {
    var ballSize: CGFloat = 40
    var ballOpacity: CGFloat = 0.8
    var colorTheme: ColorTheme = .system
    var launchAtLogin: Bool = false
    var hotkeyBallToggle: String = "⌘⇧B"
}

enum ColorTheme: String, Codable, CaseIterable {
    case system = "跟随系统"
    case light = "浅色"
    case dark = "深色"
}
