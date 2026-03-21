import AppKit
import SwiftUI
import Combine

/// 应用生命周期管理
/// 负责初始化各服务、创建悬浮球、注册快捷键、设置菜单栏图标
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - 窗口引用

    private var floatingBallWindow: FloatingBallWindow?
    private var quickPanelWindow: QuickPanelWindow?
    private var mainKanbanWindow: MainKanbanWindow?

    // MARK: - 菜单栏

    private var statusItem: NSStatusItem?

    // MARK: - 偏好设置观察

    private var preferencesObserver: AnyCancellable?

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 加载配置
        ConfigStore.shared.load()

        // 启动 App 监控
        AppMonitor.shared.startMonitoring()

        // 检查辅助功能权限，未授权则提示用户
        if !PermissionManager.shared.checkAccessibility() {
            PermissionManager.shared.requestAccessibility()
            PermissionManager.shared.startPolling()
        }

        // 预创建快捷面板（避免首次点击时的创建延迟）
        quickPanelWindow = QuickPanelWindow()

        // 创建并显示悬浮球
        setupFloatingBall()

        // 注册全局快捷键并设置回调（必须在 applyPreferences 之前，避免双重注册）
        setupHotkeys()

        // 初始化快捷键变化检测基准值（防止 applyPreferences 首次调用时重复注册）
        lastHotkey = ConfigStore.shared.preferences.hotkeyToggle

        // 应用偏好设置（大小、透明度、主题）并监听后续变化
        applyPreferences(ConfigStore.shared.preferences)
        observePreferences()

        // 设置菜单栏图标
        setupStatusBar()

        // 设置 Dock 品牌图标
        setupDockIcon()

        // 启动时自动展开快捷面板并钉住
        if let ball = floatingBallWindow {
            showPanelFromBallCenter(ballFrame: ball.frame)
            AppMonitor.shared.startWindowRefresh()
            if let panel = quickPanelWindow, !panel.isPanelPinned {
                panel.togglePanelPin()
            }
        }
    }

    /// 点击 Dock 图标时的行为
    /// 没有可见窗口时打开主看板，有可见窗口时聚焦主看板
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag {
            // 有可见窗口：聚焦主看板
            mainKanbanWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // 没有可见窗口：打开主看板
            showMainKanban()
        }
        // 悬浮球+面板未显示时，恢复到上次保存位置并弹出
        if !(quickPanelWindow?.isVisible ?? false) {
            showAll(atMousePosition: false)
        }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 移除所有通知观察者
        NotificationCenter.default.removeObserver(self)

        // 停止 App 监控
        AppMonitor.shared.stopMonitoring()

        // 注销快捷键
        HotkeyManager.shared.unregister()
    }

    // MARK: - 悬浮球

    private func setupFloatingBall() {
        floatingBallWindow = FloatingBallWindow()
        floatingBallWindow?.restorePosition()
        floatingBallWindow?.show()

        // 监听悬浮球的通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowQuickPanel(_:)),
            name: Constants.Notifications.ballShowQuickPanel,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenMainKanban),
            name: Constants.Notifications.ballOpenMainKanban,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBallDragStarted),
            name: Constants.Notifications.ballDragStarted,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleToggleBall),
            name: Constants.Notifications.ballToggle,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleToggleQuickPanel(_:)),
            name: Constants.Notifications.ballToggleQuickPanel,
            object: nil
        )
    }

    @objc private func handleShowQuickPanel(_ notification: Notification) {
        if let value = notification.userInfo?["ballFrame"] as? NSValue {
            let ballFrame = value.rectValue
            // 面板左上角对齐悬浮球中心（融合展开）
            showPanelFromBallCenter(ballFrame: ballFrame)
            AppMonitor.shared.startWindowRefresh()
        }
    }

    @objc private func handleOpenMainKanban() {
        toggleMainKanban()
    }

    @objc private func handleBallDragStarted() {
        // 面板钉住时不关闭（悬浮球和面板融合拖动）
        if let panel = quickPanelWindow, panel.isPanelPinned {
            return
        }
        quickPanelWindow?.hide()
    }

    @objc private func handleToggleBall() {
        toggleFloatingBall()
    }

    /// 单击浮球：切换快捷面板（面板左上角对齐悬浮球中心）
    @objc private func handleToggleQuickPanel(_ notification: Notification) {
        guard let value = notification.userInfo?["ballFrame"] as? NSValue else { return }
        let ballFrame = value.rectValue

        if let panel = quickPanelWindow, panel.isVisible, panel.isPanelPinned {
            // 面板已显示且已钉住 → 取消钉住 + 关闭面板
            panel.togglePanelPin()
            panel.hide()
        } else if let panel = quickPanelWindow, panel.isVisible, !panel.isPanelPinned {
            // 面板已在 hover 模式下可见 → 直接钉住
            panel.togglePanelPin()
        } else {
            // 面板未显示 → 面板左上角对齐悬浮球中心展开 + 自动钉住
            showPanelFromBallCenter(ballFrame: ballFrame)
            AppMonitor.shared.startWindowRefresh()
            if let panel = quickPanelWindow, !panel.isPanelPinned {
                panel.togglePanelPin()
            }
        }
    }

    // MARK: - 快捷键

    private func setupHotkeys() {
        HotkeyManager.shared.onToggle = { [weak self] in
            self?.toggleAllViaHotkey()
        }
        HotkeyManager.shared.register()
    }

    /// 快捷键统一切换悬浮球+面板（面板左上角出现在鼠标光标位置）
    private func toggleAllViaHotkey() {
        let isVisible = quickPanelWindow?.isVisible ?? false

        if isVisible {
            // 隐藏面板+悬浮球
            quickPanelWindow?.hide()
            floatingBallWindow?.orderOut(nil)
            ConfigStore.shared.isBallVisible = false
        } else {
            showAll(atMousePosition: true)
        }
    }

    /// 显示悬浮球+面板+钉住
    /// - Parameter atMousePosition: true=悬浮球定位到鼠标位置（快捷键），false=恢复上次保存位置（Dock）
    private func showAll(atMousePosition: Bool) {
        // 确保面板已创建
        if quickPanelWindow == nil {
            quickPanelWindow = QuickPanelWindow()
        }

        if let ball = floatingBallWindow {
            if atMousePosition {
                // 悬浮球中心 = 鼠标位置
                let mouseLocation = NSEvent.mouseLocation
                let ballSize = ball.frame.size
                let ballOrigin = CGPoint(
                    x: mouseLocation.x - ballSize.width / 2,
                    y: mouseLocation.y - ballSize.height / 2
                )
                ball.setFrameOrigin(ballOrigin)
            } else {
                // 恢复上次保存的位置
                ball.restorePosition()
            }
            ball.show()
            ConfigStore.shared.isBallVisible = true

            // 面板从悬浮球中心展开 + 自动钉住
            showPanelFromBallCenter(ballFrame: ball.frame)
            AppMonitor.shared.startWindowRefresh()
            if let panel = quickPanelWindow, !panel.isPanelPinned {
                panel.togglePanelPin()
            }
        }
    }

    // MARK: - 快捷面板

    /// 面板从悬浮球中心展开（面板左上角=悬浮球中心）
    private func showPanelFromBallCenter(ballFrame: CGRect) {
        if quickPanelWindow == nil {
            quickPanelWindow = QuickPanelWindow()
        }
        // 悬浮球中心点即为面板左上角
        let ballCenter = CGPoint(x: ballFrame.midX, y: ballFrame.midY)
        quickPanelWindow?.showAtPosition(topLeft: ballCenter, ballFrame: ballFrame)
    }

    /// 显示快捷面板（旧方法保留兼容）
    func showQuickPanel(relativeTo ballFrame: CGRect) {
        if quickPanelWindow == nil {
            quickPanelWindow = QuickPanelWindow()
        }
        quickPanelWindow?.show(relativeTo: ballFrame)
    }

    /// 隐藏快捷面板
    func hideQuickPanel() {
        quickPanelWindow?.hide()
    }

    // MARK: - 主看板

    /// 显示或聚焦主看板
    func showMainKanban() {
        if mainKanbanWindow == nil {
            mainKanbanWindow = MainKanbanWindow()
        }
        mainKanbanWindow?.show()
    }

    /// 切换主看板显示/隐藏
    func toggleMainKanban() {
        if let window = mainKanbanWindow, window.isVisible {
            window.close()
        } else {
            showMainKanban()
        }
    }

    // MARK: - 偏好设置应用

    /// 监听偏好设置变化，实时应用到悬浮球
    /// 注意：@Published 在 willSet 阶段发布，此时 ConfigStore.shared.preferences 仍为旧值。
    /// 使用 receive(on:) 延迟到下一个 RunLoop 迭代，确保下游代码从 ConfigStore.shared 读取到新值。
    private func observePreferences() {
        preferencesObserver = ConfigStore.shared.$preferences
            .dropFirst() // 跳过初始值（已在 applyPreferences 中处理）
            .receive(on: DispatchQueue.main)
            .sink { [weak self] prefs in
                self?.applyPreferences(prefs)
            }
    }

    /// 用于检测快捷键配置变化的旧值
    private var lastHotkey: HotkeyConfig?

    /// 上次应用的主题（用于检测主题变化）
    private var lastTheme: AppTheme?

    /// 将偏好设置应用到悬浮球和面板（大小、透明度、主题、快捷键）
    private func applyPreferences(_ prefs: Preferences) {
        // 悬浮球大小
        floatingBallWindow?.updateSize(prefs.ballSize)

        // 悬浮球透明度
        floatingBallWindow?.alphaValue = prefs.ballOpacity

        // 悬浮球颜色（从主题 accent 派生渐变色）
        if let ballView = floatingBallWindow?.contentView as? FloatingBallView {
            ballView.updateColorStyle(gradientColors: prefs.appTheme.ballGradientColors)
        }

        // 面板透明度（仅在面板可见时直接应用，避免干扰 show/hide 动画）
        if let panel = quickPanelWindow, panel.isVisible {
            panel.alphaValue = prefs.panelOpacity
        }

        // 快捷键变化时重新注册（直接传入 prefs 值，避免 @Published willSet 时序问题）
        if prefs.hotkeyToggle != lastHotkey {
            lastHotkey = prefs.hotkeyToggle
            HotkeyManager.shared.reregister(config: prefs.hotkeyToggle)
        }
        // 主题变化时：更新 NSApp.appearance + 刷新 QuickPanel + 发送通知
        let theme = prefs.appTheme
        if theme != lastTheme {
            lastTheme = theme

            // 设置系统外观（SwiftUI 自动适配）
            NSApp.appearance = theme.isDark
                ? NSAppearance(named: .darkAqua)
                : NSAppearance(named: .aqua)

            // 主看板窗口同步 appearance
            mainKanbanWindow?.appearance = NSApp.appearance

            // 刷新快捷面板主题
            quickPanelWindow?.applyTheme()

            // 发送主题变更通知（SwiftUI 视图可监听此通知作为刷新后备）
            NotificationCenter.default.post(name: Constants.Notifications.themeChanged, object: nil)
        }
    }

    // MARK: - 悬浮球显隐

    /// 切换悬浮球可见性
    func toggleFloatingBall() {
        if let ball = floatingBallWindow {
            if ball.isVisible {
                ball.orderOut(nil)
                ConfigStore.shared.isBallVisible = false
            } else {
                ball.show()
                ConfigStore.shared.isBallVisible = true
            }
            // 通知快捷面板更新悬浮球显隐按钮文案
            NotificationCenter.default.post(
                name: Constants.Notifications.ballVisibilityChanged,
                object: nil
            )
        }
    }

    // MARK: - 菜单栏

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = createStatusBarIcon()
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示/隐藏悬浮球", action: #selector(menuToggleBall), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "打开主看板", action: #selector(menuShowKanban), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出 Focus Copilot", action: #selector(menuQuit), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    // MARK: - 状态栏图标

    /// 自绘状态栏图标：图钉图标（模板图标，跟随系统深浅色）
    private func createStatusBarIcon() -> NSImage {
        let iconSize: CGFloat = 16
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        guard let pinSymbol = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Focus Copilot"),
              let configured = pinSymbol.withSymbolConfiguration(symbolConfig) else {
            return NSImage()
        }

        let image = NSImage(size: NSSize(width: iconSize, height: iconSize))
        image.lockFocus()

        configured.draw(
            in: NSRect(
                x: (iconSize - configured.size.width) / 2,
                y: (iconSize - configured.size.height) / 2,
                width: configured.size.width,
                height: configured.size.height
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )

        image.unlockFocus()
        image.isTemplate = true

        return image
    }

    // MARK: - 菜单操作

    @objc private func menuToggleBall() {
        toggleFloatingBall()
    }

    @objc private func menuShowKanban() {
        showMainKanban()
    }

    @objc private func menuQuit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Dock 图标

    /// Dock 图标：白色圆角正方形背景 + Enso 品牌 Logo
    private func setupDockIcon() {
        let canvasSize: CGFloat = 256

        let squirclePadding = canvasSize * 0.08
        let squircleSize = canvasSize - squirclePadding * 2
        let cornerRadius = squircleSize * 0.2237
        let logoPadding = squircleSize * 0.18
        let logoSize = squircleSize - logoPadding * 2

        let squircleRect = NSRect(
            x: squirclePadding, y: squirclePadding,
            width: squircleSize, height: squircleSize
        )
        let squirclePath = NSBezierPath(roundedRect: squircleRect, xRadius: cornerRadius, yRadius: cornerRadius)

        let gradientColors = ConfigStore.shared.preferences.appTheme.ballGradientColors
        let logo = FloatingBallView.brandLogo(size: logoSize, gradientColors: gradientColors)

        let icon = NSImage(size: NSSize(width: canvasSize, height: canvasSize))
        icon.lockFocus()

        // 1. Squircle 外部微阴影
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = max(canvasSize * 0.01, 1.5)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
        shadow.set()
        NSColor.white.setFill()
        squirclePath.fill()
        NSGraphicsContext.restoreGraphicsState()

        // 2. 白色 Squircle 背景
        NSColor.white.setFill()
        squirclePath.fill()

        // 3. 极细描边
        NSColor.black.withAlphaComponent(0.06).setStroke()
        squirclePath.lineWidth = max(canvasSize * 0.002, 0.5)
        squirclePath.stroke()

        // 4. 球体 Logo 居中
        let logoX = squirclePadding + logoPadding
        let logoY = squirclePadding + logoPadding
        let logoRect = NSRect(x: logoX, y: logoY, width: logoSize, height: logoSize)
        logo.draw(in: logoRect, from: .zero, operation: .sourceOver, fraction: 1.0)

        icon.unlockFocus()

        NSApplication.shared.applicationIconImage = icon
    }
}
