import AppKit

enum Constants {
    // MARK: - 悬浮球
    enum Ball {
        static let defaultSize: CGFloat = 40
        static let minSize: CGFloat = 30
        static let maxSize: CGFloat = 60
        static let defaultOpacity: CGFloat = 0.8
        static let hoverDelay: TimeInterval = 0.15   // hover 150ms 后弹出
    }

    // MARK: - 快捷面板
    enum Panel {
        static let width: CGFloat = 280               // 面板宽度
        static let minWidth: CGFloat = 220             // 面板最小宽度
        static let maxWidth: CGFloat = 500             // 面板最大宽度
        static let minHeight: CGFloat = 200            // 面板最小高度
        static let cornerRadius: CGFloat = 12          // 圆角半径
        static let showDuration: TimeInterval = 0.25        // 弹出动画 250ms（缩放+滑出+淡入）
        static let hideDuration: TimeInterval = 0.12         // 收起动画 120ms
        static let dismissDelay: TimeInterval = 0.5    // 离开 500ms 后收起
        static let gapToBall: CGFloat = 4              // 面板与悬浮球间距（安全区域）
        static let maxHeightRatio: CGFloat = 0.6       // 面板最大高度 = 屏幕 60%
        static let maxApps: Int = 8                    // 关注 App 上限（"全部"Tab 不受限）
        static let maxWindowsPerApp: Int = 10          // 每个 App 最多显示 10 个窗口
        static let appRowHeight: CGFloat = 26          // App 行高度（紧凑布局）
        static let windowRowHeight: CGFloat = 22       // 窗口行高度（紧凑布局）
        static let windowIndent: CGFloat = 28          // 窗口列表缩进
    }

    // MARK: - 偏好设置范围
    static let ballSizeRange: ClosedRange<CGFloat> = 30...60
    static let ballOpacityRange: ClosedRange<CGFloat> = 0.3...1.0
    // MARK: - App 配置（关注上限，"全部"Tab 不受限）
    static let maxApps: Int = Panel.maxApps

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

    // MARK: - UserDefaults Keys
    enum Keys {
        static let appConfigs = "FocusCopilot.appConfigs"
        static let preferences = "FocusCopilot.preferences"
        static let ballPosition = "FocusCopilot.ballPosition"
        static let onboardingCompleted = "FocusCopilot.onboardingCompleted"
        static let windowRenames = "FocusCopilot.windowRenames"
        static let panelSize = "FocusCopilot.panelSize"
        static let lastPanelTab = "FocusCopilot.lastPanelTab"
        static let focusTimerSettings = "FocusCopilot.focusTimerSettings"
    }

    // MARK: - 通知名称
    enum Notifications {
        // 系统级通知
        static let appStatusChanged = Notification.Name("FocusCopilot.appStatusChanged")
        static let windowsChanged = Notification.Name("FocusCopilot.windowsChanged")
        static let ballVisibilityChanged = Notification.Name("FocusCopilot.ballVisibilityChanged")
        static let accessibilityGranted = Notification.Name("FocusCopilot.accessibilityGranted")

        // 悬浮球通知
        static let ballShowQuickPanel = Notification.Name("FloatingBall.showQuickPanel")
        static let ballToggle = Notification.Name("FloatingBall.toggleBall")
        static let ballOpenMainKanban = Notification.Name("FloatingBall.openMainKanban")
        static let ballDragStarted = Notification.Name("FloatingBall.dragStarted")
        static let ballDragMoved = Notification.Name("FloatingBall.dragMoved")
        static let ballMouseExited = Notification.Name("FloatingBall.mouseExited")
        static let ballToggleQuickPanel = Notification.Name("FloatingBall.toggleQuickPanel")

        // 快捷面板通知
        static let panelPinStateChanged = Notification.Name("QuickPanel.pinStateChanged")
        static let panelDragMoved = Notification.Name("QuickPanel.dragMoved")

        // 主题变更通知
        static let themeChanged = Notification.Name("FocusCopilot.themeChanged")

        // FocusByTime 计时器通知
        static let focusTimerChanged = Notification.Name("FocusCopilot.focusTimerChanged")
        /// 工作阶段结束 → 需要弹对话框提示休息
        static let focusWorkCompleted = Notification.Name("FocusCopilot.focusWorkCompleted")
        /// 休息阶段结束 → 需要弹对话框提示开始工作
        static let focusRestCompleted = Notification.Name("FocusCopilot.focusRestCompleted")
    }
}
