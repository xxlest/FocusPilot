import AppKit

// MARK: - App 配置（持久化）

struct AppConfig: Codable, Identifiable, Equatable {
    var id: String { bundleID }
    let bundleID: String
    var displayName: String
    var order: Int

    // 自定义解码：兼容旧数据（忽略旧 isFavorite / pinnedKeywords 字段）
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        displayName = try container.decode(String.self, forKey: .displayName)
        order = try container.decode(Int.self, forKey: .order)
    }

    init(bundleID: String, displayName: String, order: Int) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.order = order
    }

    private enum CodingKeys: String, CodingKey {
        case bundleID, displayName, order
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
    var panelOpacity: CGFloat = 0.9
    var colorTheme: ColorTheme = .system
    var ballColorStyle: BallColorStyle = .orange
    var ballCustomColorHex: String = "#FF8800"
    var launchAtLogin: Bool = false
    var hotkeyBallToggle: String = "⌘⇧B"

    // 自定义解码：兼容旧数据（旧版本没有 panelOpacity 字段）
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ballSize = try container.decodeIfPresent(CGFloat.self, forKey: .ballSize) ?? 40
        ballOpacity = try container.decodeIfPresent(CGFloat.self, forKey: .ballOpacity) ?? 0.8
        panelOpacity = try container.decodeIfPresent(CGFloat.self, forKey: .panelOpacity) ?? 0.9
        colorTheme = try container.decodeIfPresent(ColorTheme.self, forKey: .colorTheme) ?? .system
        ballColorStyle = try container.decodeIfPresent(BallColorStyle.self, forKey: .ballColorStyle) ?? .orange
        ballCustomColorHex = try container.decodeIfPresent(String.self, forKey: .ballCustomColorHex) ?? "#FF8800"
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        hotkeyBallToggle = try container.decodeIfPresent(String.self, forKey: .hotkeyBallToggle) ?? "⌘⇧B"
    }

    init() {}
}

enum ColorTheme: String, Codable, CaseIterable {
    case system = "跟随系统"
    case light = "浅色"
    case dark = "深色"
}

// MARK: - 悬浮球颜色风格

enum BallColorStyle: String, Codable, CaseIterable {
    case orange = "经典橙"
    case blue = "海洋蓝"
    case green = "翡翠绿"
    case purple = "星空紫"
    case pink = "樱花粉"
    case gray = "石墨灰"
    case custom = "自定义"

    /// 获取该风格的三级渐变色（浅、中、深）
    var gradientColors: (light: NSColor, medium: NSColor, dark: NSColor) {
        switch self {
        case .orange:
            return (
                NSColor(calibratedRed: 1.0, green: 0.65, blue: 0.3, alpha: 1.0),
                NSColor(calibratedRed: 0.9, green: 0.45, blue: 0.1, alpha: 1.0),
                NSColor(calibratedRed: 0.6, green: 0.25, blue: 0.05, alpha: 1.0)
            )
        case .blue:
            return (
                NSColor(calibratedRed: 0.4, green: 0.7, blue: 1.0, alpha: 1.0),
                NSColor(calibratedRed: 0.2, green: 0.5, blue: 0.9, alpha: 1.0),
                NSColor(calibratedRed: 0.1, green: 0.3, blue: 0.6, alpha: 1.0)
            )
        case .green:
            return (
                NSColor(calibratedRed: 0.4, green: 0.85, blue: 0.55, alpha: 1.0),
                NSColor(calibratedRed: 0.2, green: 0.7, blue: 0.35, alpha: 1.0),
                NSColor(calibratedRed: 0.1, green: 0.45, blue: 0.2, alpha: 1.0)
            )
        case .purple:
            return (
                NSColor(calibratedRed: 0.7, green: 0.5, blue: 1.0, alpha: 1.0),
                NSColor(calibratedRed: 0.5, green: 0.3, blue: 0.85, alpha: 1.0),
                NSColor(calibratedRed: 0.3, green: 0.15, blue: 0.6, alpha: 1.0)
            )
        case .pink:
            return (
                NSColor(calibratedRed: 1.0, green: 0.6, blue: 0.7, alpha: 1.0),
                NSColor(calibratedRed: 0.9, green: 0.4, blue: 0.55, alpha: 1.0),
                NSColor(calibratedRed: 0.65, green: 0.2, blue: 0.35, alpha: 1.0)
            )
        case .gray:
            return (
                NSColor(calibratedRed: 0.65, green: 0.65, blue: 0.68, alpha: 1.0),
                NSColor(calibratedRed: 0.45, green: 0.45, blue: 0.48, alpha: 1.0),
                NSColor(calibratedRed: 0.25, green: 0.25, blue: 0.28, alpha: 1.0)
            )
        case .custom:
            // custom 模式使用 customHex，这里返回默认橙色作为 fallback
            return BallColorStyle.orange.gradientColors
        }
    }

    /// 从自定义 hex 颜色生成三级渐变
    static func customGradientColors(hex: String) -> (light: NSColor, medium: NSColor, dark: NSColor) {
        let base = NSColor.fromHex(hex) ?? NSColor.orange
        let light = base.blended(withFraction: 0.3, of: .white) ?? base
        let dark = base.blended(withFraction: 0.4, of: .black) ?? base
        return (light, base, dark)
    }
}

// MARK: - NSColor Hex 扩展

extension NSColor {
    /// 从 hex 字符串创建颜色（如 "#FF8800" 或 "FF8800"）
    static func fromHex(_ hex: String) -> NSColor? {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") { hexString.removeFirst() }
        guard hexString.count == 6, let rgb = UInt64(hexString, radix: 16) else { return nil }
        return NSColor(
            calibratedRed: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: 1.0
        )
    }

    /// 转为 hex 字符串
    var hexString: String {
        guard let rgb = usingColorSpace(.deviceRGB) else { return "#FF8800" }
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
