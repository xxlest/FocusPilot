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

    // 默认值
    static let ballToggleDefault = HotkeyConfig(keyCode: kVK_ANSI_B, carbonModifiers: cmdKeyFlag | shiftKeyFlag)
    static let panelToggleDefault = HotkeyConfig(keyCode: kVK_Escape, carbonModifiers: cmdKeyFlag)

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
    var ballSize: CGFloat = 40
    var ballOpacity: CGFloat = 0.8
    var panelOpacity: CGFloat = 0.9
    var colorTheme: ColorTheme = .system
    var ballColorStyle: BallColorStyle = .orange
    var ballCustomColorHex: String = "#FF8800"
    var launchAtLogin: Bool = false
    var hotkeyBallToggle: HotkeyConfig = .ballToggleDefault
    var hotkeyPanelToggle: HotkeyConfig = .panelToggleDefault

    // 自定义解码：兼容旧数据
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ballSize = try container.decodeIfPresent(CGFloat.self, forKey: .ballSize) ?? 40
        ballOpacity = try container.decodeIfPresent(CGFloat.self, forKey: .ballOpacity) ?? 0.8
        panelOpacity = try container.decodeIfPresent(CGFloat.self, forKey: .panelOpacity) ?? 0.9
        colorTheme = try container.decodeIfPresent(ColorTheme.self, forKey: .colorTheme) ?? .system
        ballColorStyle = try container.decodeIfPresent(BallColorStyle.self, forKey: .ballColorStyle) ?? .orange
        ballCustomColorHex = try container.decodeIfPresent(String.self, forKey: .ballCustomColorHex) ?? "#FF8800"
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        // 快捷键：兼容旧版本（旧版 hotkeyBallToggle 是 String 类型，解码会失败，使用默认值）
        hotkeyBallToggle = (try? container.decode(HotkeyConfig.self, forKey: .hotkeyBallToggle)) ?? .ballToggleDefault
        hotkeyPanelToggle = (try? container.decode(HotkeyConfig.self, forKey: .hotkeyPanelToggle)) ?? .panelToggleDefault
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
