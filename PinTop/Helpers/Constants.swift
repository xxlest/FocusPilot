import AppKit

enum Constants {
    // MARK: - 悬浮球
    enum Ball {
        static let defaultSize: CGFloat = 40
        static let minSize: CGFloat = 30
        static let maxSize: CGFloat = 60
        static let defaultOpacity: CGFloat = 0.8
        static let hoverDelay: TimeInterval = 0.3    // hover 300ms 后弹出
    }

    // MARK: - 快捷面板
    enum Panel {
        static let width: CGFloat = 280               // 面板宽度
        static let minWidth: CGFloat = 220             // 面板最小宽度
        static let maxWidth: CGFloat = 500             // 面板最大宽度
        static let minHeight: CGFloat = 200            // 面板最小高度
        static let cornerRadius: CGFloat = 12          // 圆角半径
        static let animationDuration: TimeInterval = 0.15  // 弹出/收起动画 150ms
        static let dismissDelay: TimeInterval = 0.5    // 离开 500ms 后收起
        static let gapToBall: CGFloat = 4              // 面板与悬浮球间距（安全区域）
        static let maxHeightRatio: CGFloat = 0.6       // 面板最大高度 = 屏幕 60%
        static let maxApps: Int = 8                    // 快捷面板最多 8 个 App
        static let maxWindowsPerApp: Int = 10          // 每个 App 最多显示 10 个窗口
        static let bottomBarHeight: CGFloat = 36       // 底部操作栏高度
        static let appRowHeight: CGFloat = 32          // App 行高度
        static let windowRowHeight: CGFloat = 28       // 窗口行高度
        static let windowIndent: CGFloat = 28          // 窗口列表缩进
    }

    // MARK: - 偏好设置范围
    static let ballSizeRange: ClosedRange<CGFloat> = 30...60
    static let ballOpacityRange: ClosedRange<CGFloat> = 0.3...1.0
    static let borderColors: [String] = ["blue", "red", "green", "orange", "purple", "yellow"]

    // MARK: - Pin（供服务层使用的扁平常量）
    static let maxPinnedWindows: Int = 6               // 最多 6 个置顶窗口
    static let maxApps: Int = 8                        // 快捷面板最多 8 个 App

    // MARK: - 主看板
    static let kanbanWidth: CGFloat = 800
    static let kanbanHeight: CGFloat = 600
    static let kanbanMinWidth: CGFloat = 640
    static let kanbanMinHeight: CGFloat = 480
    static let sidebarWidth: CGFloat = 180

    // MARK: - 性能
    static let windowRefreshInterval: TimeInterval = 1.0  // 窗口列表刷新间隔 1s
    static let permissionPollInterval: TimeInterval = 1.0  // 权限检测轮询间隔

    // MARK: - 窗口层级
    static let floatingBallLevel = CGWindowLevelForKey(.statusWindow) + 100
    static let quickPanelLevel = CGWindowLevelForKey(.statusWindow) + 50
    static let pinnedWindowBaseLevel = CGWindowLevelForKey(.floatingWindow) + 10

    // MARK: - UserDefaults Keys
    enum Keys {
        static let appConfigs = "PinTop.appConfigs"
        static let preferences = "PinTop.preferences"
        static let ballPosition = "PinTop.ballPosition"
        static let onboardingCompleted = "PinTop.onboardingCompleted"
        static let windowRenames = "PinTop.windowRenames"
        static let panelSize = "PinTop.panelSize"
    }

    // MARK: - 通知名称
    enum Notifications {
        static let appStatusChanged = Notification.Name("PinTop.appStatusChanged")
        static let windowsChanged = Notification.Name("PinTop.windowsChanged")
        static let pinnedWindowsChanged = Notification.Name("PinTop.pinnedWindowsChanged")
        static let ballVisibilityChanged = Notification.Name("PinTop.ballVisibilityChanged")
        static let accessibilityGranted = Notification.Name("PinTop.accessibilityGranted")
    }
}
