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

// MARK: - 快捷键配置（持久化）

struct HotkeyConfig: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    // Carbon 键码常量（避免在 Models 中 import Carbon）
    static let kVK_ANSI_A: UInt32 = 0x00
    static let kVK_ANSI_B: UInt32 = 0x0B
    static let kVK_ANSI_P: UInt32 = 0x23
    static let kVK_Escape: UInt32 = 0x35
    static let kVK_Space: UInt32 = 0x31
    static let kVK_Return: UInt32 = 0x24
    static let kVK_Tab: UInt32 = 0x30
    static let kVK_Delete: UInt32 = 0x33

    // Carbon 修饰键常量
    static let cmdKeyFlag: UInt32 = 0x0100
    static let shiftKeyFlag: UInt32 = 0x0200
    static let optionKeyFlag: UInt32 = 0x0800
    static let controlKeyFlag: UInt32 = 0x1000

    // 默认值（⌘⇧B 同时切换悬浮球+面板）
    static let toggleDefault = HotkeyConfig(keyCode: kVK_ANSI_B, carbonModifiers: cmdKeyFlag | shiftKeyFlag)

    // 主看板快捷键默认值（⌘Esc）
    static let kanbanDefault = HotkeyConfig(keyCode: kVK_Escape, carbonModifiers: cmdKeyFlag)

    /// 显示字符串（如 "⌘⇧B"）
    var displayString: String {
        var parts: [String] = []
        if carbonModifiers & Self.controlKeyFlag != 0 { parts.append("⌃") }
        if carbonModifiers & Self.optionKeyFlag != 0 { parts.append("⌥") }
        if carbonModifiers & Self.shiftKeyFlag != 0 { parts.append("⇧") }
        if carbonModifiers & Self.cmdKeyFlag != 0 { parts.append("⌘") }
        parts.append(Self.keyCodeToString(keyCode))
        return parts.joined()
    }

    /// 从 NSEvent 修饰键转换为 Carbon 修饰键
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= cmdKeyFlag }
        if flags.contains(.shift) { result |= shiftKeyFlag }
        if flags.contains(.option) { result |= optionKeyFlag }
        if flags.contains(.control) { result |= controlKeyFlag }
        return result
    }

    /// Carbon 键码转显示字符
    static func keyCodeToString(_ keyCode: UInt32) -> String {
        // 字母键 A-Z
        let letterMap: [UInt32: String] = [
            0x00: "A", 0x0B: "B", 0x08: "C", 0x02: "D", 0x0E: "E",
            0x03: "F", 0x05: "G", 0x04: "H", 0x22: "I", 0x26: "J",
            0x28: "K", 0x25: "L", 0x2E: "M", 0x2D: "N", 0x1F: "O",
            0x23: "P", 0x0C: "Q", 0x0F: "R", 0x01: "S", 0x11: "T",
            0x20: "U", 0x09: "V", 0x0D: "W", 0x07: "X", 0x10: "Y",
            0x06: "Z",
        ]
        if let letter = letterMap[keyCode] { return letter }

        // 数字键 0-9
        let numberMap: [UInt32: String] = [
            0x1D: "0", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4",
            0x17: "5", 0x16: "6", 0x1A: "7", 0x1C: "8", 0x19: "9",
        ]
        if let num = numberMap[keyCode] { return num }

        // 特殊键
        switch keyCode {
        case 0x35: return "Esc"
        case 0x31: return "Space"
        case 0x24: return "↩"
        case 0x30: return "⇥"
        case 0x33: return "⌫"
        case 0x75: return "⌦"
        case 0x7E: return "↑"
        case 0x7D: return "↓"
        case 0x7B: return "←"
        case 0x7C: return "→"
        case 0x7A: return "F1"
        case 0x78: return "F2"
        case 0x63: return "F3"
        case 0x76: return "F4"
        case 0x60: return "F5"
        case 0x61: return "F6"
        case 0x62: return "F7"
        case 0x64: return "F8"
        case 0x65: return "F9"
        case 0x6D: return "F10"
        case 0x67: return "F11"
        case 0x6F: return "F12"
        default: return "(\(keyCode))"
        }
    }
}

// MARK: - 偏好设置（持久化）

struct Preferences: Codable {
    var ballSize: CGFloat = 35
    var ballOpacity: CGFloat = 0.8
    var panelOpacity: CGFloat = 0.9
    var appTheme: AppTheme = .defaultWhite
    var launchAtLogin: Bool = false
    var hotkeyToggle: HotkeyConfig = .toggleDefault
    var hotkeyKanban: HotkeyConfig = .kanbanDefault
    var autoRetractOnHover: Bool = true
    var panelAnimationSpeed: CGFloat = 0.25  // 面板弹出动画时长（秒），0.1-0.6

    // 自定义解码：兼容旧数据（保留旧字段 CodingKey 以避免解码崩溃）
    private enum CodingKeys: String, CodingKey {
        case ballSize, ballOpacity, panelOpacity, appTheme
        case launchAtLogin, hotkeyToggle, hotkeyKanban
        case autoRetractOnHover, panelAnimationSpeed
        // 旧字段（解码时忽略，兼容升级）
        case colorTheme, ballColorStyle, ballCustomColorHex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ballSize = try container.decodeIfPresent(CGFloat.self, forKey: .ballSize) ?? 35
        ballOpacity = try container.decodeIfPresent(CGFloat.self, forKey: .ballOpacity) ?? 0.8
        panelOpacity = try container.decodeIfPresent(CGFloat.self, forKey: .panelOpacity) ?? 0.9
        appTheme = try container.decodeIfPresent(AppTheme.self, forKey: .appTheme) ?? .defaultWhite
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        hotkeyToggle = (try? container.decode(HotkeyConfig.self, forKey: .hotkeyToggle)) ?? .toggleDefault
        hotkeyKanban = (try? container.decode(HotkeyConfig.self, forKey: .hotkeyKanban)) ?? .kanbanDefault
        autoRetractOnHover = try container.decodeIfPresent(Bool.self, forKey: .autoRetractOnHover) ?? true
        panelAnimationSpeed = try container.decodeIfPresent(CGFloat.self, forKey: .panelAnimationSpeed) ?? 0.25
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ballSize, forKey: .ballSize)
        try container.encode(ballOpacity, forKey: .ballOpacity)
        try container.encode(panelOpacity, forKey: .panelOpacity)
        try container.encode(appTheme, forKey: .appTheme)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(hotkeyToggle, forKey: .hotkeyToggle)
        try container.encode(hotkeyKanban, forKey: .hotkeyKanban)
        try container.encode(autoRetractOnHover, forKey: .autoRetractOnHover)
        try container.encode(panelAnimationSpeed, forKey: .panelAnimationSpeed)
    }

    init() {}
}

// MARK: - Notion 风格主题

enum AppTheme: String, Codable, CaseIterable {
    case defaultWhite = "默认白"
    case warmIvory    = "暖象牙"
    case mintGreen    = "薄荷绿"
    case lightBlue    = "淡天蓝"
    case classicDark  = "经典深"
    case deepOcean    = "深海蓝"
    case inkGreen     = "墨绿"
    case pureBlack    = "纯黑"

    /// 该主题是否为深色
    var isDark: Bool {
        switch self {
        case .defaultWhite, .warmIvory, .mintGreen, .lightBlue: return false
        case .classicDark, .deepOcean, .inkGreen, .pureBlack:   return true
        }
    }

    /// 主题颜色集
    var colors: ThemeColors {
        switch self {
        case .defaultWhite:
            return ThemeColors(
                background: NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
                sidebarBackground: NSColor(calibratedRed: 0.965, green: 0.965, blue: 0.965, alpha: 1.0), // #F7F7F7
                accent: NSColor(calibratedRed: 0.898, green: 0.224, blue: 0.208, alpha: 1.0), // #E53935
                textPrimary: NSColor(calibratedRed: 0.145, green: 0.145, blue: 0.145, alpha: 1.0),
                textSecondary: NSColor(calibratedRed: 0.455, green: 0.455, blue: 0.455, alpha: 1.0),
                textTertiary: NSColor(calibratedRed: 0.627, green: 0.627, blue: 0.627, alpha: 1.0),
                rowHighlight: NSColor(calibratedRed: 0.898, green: 0.224, blue: 0.208, alpha: 0.08),
                separator: NSColor(calibratedRed: 0.898, green: 0.898, blue: 0.898, alpha: 1.0), // #E5E5E5
                favoriteStar: NSColor(calibratedRed: 0.95, green: 0.77, blue: 0.06, alpha: 1.0)
            )
        case .warmIvory:
            return ThemeColors(
                background: NSColor(calibratedRed: 0.984, green: 0.973, blue: 0.957, alpha: 1.0), // #FBF8F4
                sidebarBackground: NSColor(calibratedRed: 0.957, green: 0.941, blue: 0.918, alpha: 1.0), // #F4F0EA
                accent: NSColor(calibratedRed: 0.851, green: 0.467, blue: 0.024, alpha: 1.0), // #D97706
                textPrimary: NSColor(calibratedRed: 0.18, green: 0.16, blue: 0.14, alpha: 1.0),
                textSecondary: NSColor(calibratedRed: 0.48, green: 0.44, blue: 0.40, alpha: 1.0),
                textTertiary: NSColor(calibratedRed: 0.65, green: 0.60, blue: 0.56, alpha: 1.0),
                rowHighlight: NSColor(calibratedRed: 0.851, green: 0.467, blue: 0.024, alpha: 0.08),
                separator: NSColor(calibratedRed: 0.88, green: 0.85, blue: 0.80, alpha: 1.0),
                favoriteStar: NSColor(calibratedRed: 0.95, green: 0.77, blue: 0.06, alpha: 1.0)
            )
        case .mintGreen:
            return ThemeColors(
                background: NSColor(calibratedRed: 0.941, green: 0.992, blue: 0.957, alpha: 1.0), // #F0FDF4
                sidebarBackground: NSColor(calibratedRed: 0.906, green: 0.965, blue: 0.925, alpha: 1.0), // #E7F6EC
                accent: NSColor(calibratedRed: 0.086, green: 0.639, blue: 0.290, alpha: 1.0), // #16A34A
                textPrimary: NSColor(calibratedRed: 0.10, green: 0.18, blue: 0.12, alpha: 1.0),
                textSecondary: NSColor(calibratedRed: 0.30, green: 0.44, blue: 0.34, alpha: 1.0),
                textTertiary: NSColor(calibratedRed: 0.48, green: 0.60, blue: 0.52, alpha: 1.0),
                rowHighlight: NSColor(calibratedRed: 0.086, green: 0.639, blue: 0.290, alpha: 0.08),
                separator: NSColor(calibratedRed: 0.80, green: 0.90, blue: 0.84, alpha: 1.0),
                favoriteStar: NSColor(calibratedRed: 0.95, green: 0.77, blue: 0.06, alpha: 1.0)
            )
        case .lightBlue:
            return ThemeColors(
                background: NSColor(calibratedRed: 0.937, green: 0.965, blue: 1.0, alpha: 1.0), // #EFF6FF
                sidebarBackground: NSColor(calibratedRed: 0.902, green: 0.933, blue: 0.973, alpha: 1.0), // #E6EEF8
                accent: NSColor(calibratedRed: 0.145, green: 0.388, blue: 0.922, alpha: 1.0), // #2563EB
                textPrimary: NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.22, alpha: 1.0),
                textSecondary: NSColor(calibratedRed: 0.30, green: 0.38, blue: 0.50, alpha: 1.0),
                textTertiary: NSColor(calibratedRed: 0.48, green: 0.55, blue: 0.65, alpha: 1.0),
                rowHighlight: NSColor(calibratedRed: 0.145, green: 0.388, blue: 0.922, alpha: 0.08),
                separator: NSColor(calibratedRed: 0.82, green: 0.87, blue: 0.94, alpha: 1.0),
                favoriteStar: NSColor(calibratedRed: 0.95, green: 0.77, blue: 0.06, alpha: 1.0)
            )
        case .classicDark:
            return ThemeColors(
                background: NSColor(calibratedRed: 0.110, green: 0.110, blue: 0.118, alpha: 1.0), // #1C1C1E
                sidebarBackground: NSColor(calibratedRed: 0.075, green: 0.075, blue: 0.075, alpha: 1.0), // #131313
                accent: NSColor(calibratedRed: 0.322, green: 0.612, blue: 0.792, alpha: 1.0), // #529CCA
                textPrimary: NSColor(calibratedRed: 0.90, green: 0.90, blue: 0.90, alpha: 1.0),
                textSecondary: NSColor(calibratedRed: 0.60, green: 0.60, blue: 0.60, alpha: 1.0),
                textTertiary: NSColor(calibratedRed: 0.42, green: 0.42, blue: 0.42, alpha: 1.0),
                rowHighlight: NSColor(calibratedRed: 0.322, green: 0.612, blue: 0.792, alpha: 0.12),
                separator: NSColor(calibratedRed: 0.22, green: 0.22, blue: 0.22, alpha: 1.0),
                favoriteStar: NSColor(calibratedRed: 0.95, green: 0.77, blue: 0.06, alpha: 1.0)
            )
        case .deepOcean:
            return ThemeColors(
                background: NSColor(calibratedRed: 0.059, green: 0.106, blue: 0.176, alpha: 1.0), // #0F1B2D
                sidebarBackground: NSColor(calibratedRed: 0.043, green: 0.082, blue: 0.145, alpha: 1.0), // #0B1525
                accent: NSColor(calibratedRed: 0.376, green: 0.647, blue: 0.980, alpha: 1.0), // #60A5FA
                textPrimary: NSColor(calibratedRed: 0.88, green: 0.92, blue: 0.96, alpha: 1.0),
                textSecondary: NSColor(calibratedRed: 0.50, green: 0.58, blue: 0.68, alpha: 1.0),
                textTertiary: NSColor(calibratedRed: 0.35, green: 0.42, blue: 0.52, alpha: 1.0),
                rowHighlight: NSColor(calibratedRed: 0.376, green: 0.647, blue: 0.980, alpha: 0.12),
                separator: NSColor(calibratedRed: 0.14, green: 0.20, blue: 0.30, alpha: 1.0),
                favoriteStar: NSColor(calibratedRed: 0.95, green: 0.77, blue: 0.06, alpha: 1.0)
            )
        case .inkGreen:
            return ThemeColors(
                background: NSColor(calibratedRed: 0.051, green: 0.122, blue: 0.090, alpha: 1.0), // #0D1F17
                sidebarBackground: NSColor(calibratedRed: 0.035, green: 0.094, blue: 0.067, alpha: 1.0), // #091811
                accent: NSColor(calibratedRed: 0.290, green: 0.871, blue: 0.502, alpha: 1.0), // #4ADE80
                textPrimary: NSColor(calibratedRed: 0.88, green: 0.95, blue: 0.90, alpha: 1.0),
                textSecondary: NSColor(calibratedRed: 0.50, green: 0.62, blue: 0.54, alpha: 1.0),
                textTertiary: NSColor(calibratedRed: 0.35, green: 0.46, blue: 0.40, alpha: 1.0),
                rowHighlight: NSColor(calibratedRed: 0.290, green: 0.871, blue: 0.502, alpha: 0.12),
                separator: NSColor(calibratedRed: 0.12, green: 0.22, blue: 0.16, alpha: 1.0),
                favoriteStar: NSColor(calibratedRed: 0.95, green: 0.77, blue: 0.06, alpha: 1.0)
            )
        case .pureBlack:
            return ThemeColors(
                background: NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.0, alpha: 1.0), // #000000
                sidebarBackground: NSColor(calibratedRed: 0.047, green: 0.047, blue: 0.047, alpha: 1.0), // #0C0C0C
                accent: NSColor(calibratedRed: 0.655, green: 0.545, blue: 0.980, alpha: 1.0), // #A78BFA
                textPrimary: NSColor(calibratedRed: 0.92, green: 0.92, blue: 0.95, alpha: 1.0),
                textSecondary: NSColor(calibratedRed: 0.58, green: 0.58, blue: 0.63, alpha: 1.0),
                textTertiary: NSColor(calibratedRed: 0.40, green: 0.40, blue: 0.44, alpha: 1.0),
                rowHighlight: NSColor(calibratedRed: 0.655, green: 0.545, blue: 0.980, alpha: 0.12),
                separator: NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.18, alpha: 1.0),
                favoriteStar: NSColor(calibratedRed: 0.95, green: 0.77, blue: 0.06, alpha: 1.0)
            )
        }
    }

    /// 悬浮球渐变色（从 accent 自动派生）
    var ballGradientColors: (light: NSColor, medium: NSColor, dark: NSColor) {
        let accent = colors.nsAccent
        let light = accent.blended(withFraction: 0.3, of: .white) ?? accent
        let dark = accent.blended(withFraction: 0.4, of: .black) ?? accent
        return (light, accent, dark)
    }

    /// 面板毛玻璃材质
    var panelMaterial: Int {
        // NSVisualEffectView.Material 的 rawValue: .light=1, .dark=2
        isDark ? 2 : 1
    }

    /// 显示名称
    var displayName: String { rawValue }

    /// 浅色主题列表
    static var lightThemes: [AppTheme] {
        [.defaultWhite, .warmIvory, .mintGreen, .lightBlue]
    }

    /// 深色主题列表
    static var darkThemes: [AppTheme] {
        [.classicDark, .deepOcean, .inkGreen, .pureBlack]
    }
}

// MARK: - 主题颜色集

struct ThemeColors {
    let nsBackground: NSColor
    let nsSidebarBackground: NSColor
    let nsAccent: NSColor
    let nsTextPrimary: NSColor
    let nsTextSecondary: NSColor
    let nsTextTertiary: NSColor
    let nsRowHighlight: NSColor
    let nsSeparator: NSColor
    let nsFavoriteStar: NSColor

    init(background: NSColor, sidebarBackground: NSColor, accent: NSColor, textPrimary: NSColor, textSecondary: NSColor,
         textTertiary: NSColor, rowHighlight: NSColor, separator: NSColor, favoriteStar: NSColor) {
        self.nsBackground = background
        self.nsSidebarBackground = sidebarBackground
        self.nsAccent = accent
        self.nsTextPrimary = textPrimary
        self.nsTextSecondary = textSecondary
        self.nsTextTertiary = textTertiary
        self.nsRowHighlight = rowHighlight
        self.nsSeparator = separator
        self.nsFavoriteStar = favoriteStar
    }
}

// MARK: - ThemeColors SwiftUI 扩展

import SwiftUI

extension ThemeColors {
    var swBackground: Color { Color(nsColor: nsBackground) }
    var swSidebarBackground: Color { Color(nsColor: nsSidebarBackground) }
    var swAccent: Color { Color(nsColor: nsAccent) }
    var swTextPrimary: Color { Color(nsColor: nsTextPrimary) }
    var swTextSecondary: Color { Color(nsColor: nsTextSecondary) }
    var swTextTertiary: Color { Color(nsColor: nsTextTertiary) }
    var swRowHighlight: Color { Color(nsColor: nsRowHighlight) }
    var swSeparator: Color { Color(nsColor: nsSeparator) }
    var swFavoriteStar: Color { Color(nsColor: nsFavoriteStar) }
}

enum ColorTheme: String, Codable, CaseIterable {
    case system = "跟随系统"
    case light = "浅色"
    case dark = "深色"
}

// MARK: - 悬浮球颜色风格

enum BallColorStyle: String, Codable, CaseIterable {
    case blue = "海洋蓝"
    case orange = "经典橙"
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
                NSColor(calibratedRed: 1.0, green: 0.6, blue: 0.2, alpha: 1.0),
                NSColor(calibratedRed: 1.0, green: 0.45, blue: 0.0, alpha: 1.0),
                NSColor(calibratedRed: 0.7, green: 0.25, blue: 0.0, alpha: 1.0)
            )
        case .blue:
            return (
                NSColor(calibratedRed: 0.3, green: 0.7, blue: 1.0, alpha: 1.0),
                NSColor(calibratedRed: 0.1, green: 0.5, blue: 1.0, alpha: 1.0),
                NSColor(calibratedRed: 0.0, green: 0.3, blue: 0.75, alpha: 1.0)
            )
        case .green:
            return (
                NSColor(calibratedRed: 0.2, green: 0.9, blue: 0.5, alpha: 1.0),
                NSColor(calibratedRed: 0.0, green: 0.75, blue: 0.35, alpha: 1.0),
                NSColor(calibratedRed: 0.0, green: 0.5, blue: 0.2, alpha: 1.0)
            )
        case .purple:
            return (
                NSColor(calibratedRed: 0.7, green: 0.4, blue: 1.0, alpha: 1.0),
                NSColor(calibratedRed: 0.55, green: 0.2, blue: 0.95, alpha: 1.0),
                NSColor(calibratedRed: 0.35, green: 0.1, blue: 0.7, alpha: 1.0)
            )
        case .pink:
            return (
                NSColor(calibratedRed: 1.0, green: 0.45, blue: 0.6, alpha: 1.0),
                NSColor(calibratedRed: 1.0, green: 0.25, blue: 0.45, alpha: 1.0),
                NSColor(calibratedRed: 0.75, green: 0.1, blue: 0.3, alpha: 1.0)
            )
        case .gray:
            return (
                NSColor(calibratedRed: 0.6, green: 0.62, blue: 0.68, alpha: 1.0),
                NSColor(calibratedRed: 0.4, green: 0.42, blue: 0.48, alpha: 1.0),
                NSColor(calibratedRed: 0.2, green: 0.22, blue: 0.28, alpha: 1.0)
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
