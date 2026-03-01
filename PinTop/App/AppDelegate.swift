import AppKit
import SwiftUI

/// 应用生命周期管理
/// 负责初始化各服务、创建悬浮球、注册快捷键、设置菜单栏图标
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - 窗口引用

    private var floatingBallWindow: FloatingBallWindow?
    private var quickPanelWindow: QuickPanelWindow?
    private var mainKanbanWindow: MainKanbanWindow?

    // MARK: - 菜单栏

    private var statusItem: NSStatusItem?

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

        // 创建并显示悬浮球
        setupFloatingBall()

        // 注册全局快捷键并设置回调
        setupHotkeys()

        // 设置菜单栏图标
        setupStatusBar()

        // 设置 Dock 品牌图标
        setupDockIcon()
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
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 移除所有通知观察者
        NotificationCenter.default.removeObserver(self)

        // 清除所有 Pin 状态
        PinManager.shared.unpinAll()

        // 停止 App 监控
        AppMonitor.shared.stopMonitoring()

        // 注销快捷键
        HotkeyManager.shared.unregisterAll()
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
            name: NSNotification.Name("FloatingBall.showQuickPanel"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenMainKanban),
            name: NSNotification.Name("FloatingBall.openMainKanban"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBallDragStarted),
            name: NSNotification.Name("FloatingBall.dragStarted"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleToggleBall),
            name: NSNotification.Name("FloatingBall.toggleBall"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleToggleQuickPanel(_:)),
            name: NSNotification.Name("FloatingBall.toggleQuickPanel"),
            object: nil
        )
    }

    @objc private func handleShowQuickPanel(_ notification: Notification) {
        if let value = notification.userInfo?["ballFrame"] as? NSValue {
            showQuickPanel(relativeTo: value.rectValue)
            // 启动窗口刷新定时器
            AppMonitor.shared.startWindowRefresh()
        }
    }

    @objc private func handleOpenMainKanban() {
        showMainKanban()
    }

    @objc private func handleBallDragStarted() {
        quickPanelWindow?.hide()
    }

    @objc private func handleToggleBall() {
        toggleFloatingBall()
    }

    /// 单击浮球：切换快捷面板钉住状态
    @objc private func handleToggleQuickPanel(_ notification: Notification) {
        guard let value = notification.userInfo?["ballFrame"] as? NSValue else { return }
        let ballFrame = value.rectValue

        if let panel = quickPanelWindow, panel.isVisible, panel.isPanelPinned {
            // 面板已显示且已钉住 → 取消钉住 + 关闭面板
            panel.togglePanelPin()
            panel.hide()
        } else {
            // 面板未显示或未钉住 → 弹出面板 + 自动钉住
            showQuickPanel(relativeTo: ballFrame)
            // 启动窗口刷新定时器
            AppMonitor.shared.startWindowRefresh()
            // 自动钉住面板
            if let panel = quickPanelWindow, !panel.isPanelPinned {
                panel.togglePanelPin()
            }
        }
    }

    // MARK: - 快捷键

    private func setupHotkeys() {
        HotkeyManager.shared.registerAll()
        HotkeyManager.shared.onAction = { [weak self] action in
            switch action {
            case .pinToggle:
                // Pin/Unpin 当前活跃窗口
                let windows = WindowService.shared.listAllWindows()
                if let frontWindow = windows.first {
                    PinManager.shared.togglePin(window: frontWindow)
                }
            case .ballToggle:
                self?.toggleFloatingBall()
            }
        }
    }

    // MARK: - 快捷面板

    /// 显示快捷面板
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
        }
    }

    // MARK: - 菜单栏

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = createStatusBarIcon(hasPinnedWindows: false)
        }

        // 监听 Pin 状态变化，更新状态栏图标
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateStatusBarIcon),
            name: PinManager.pinnedWindowsChanged,
            object: nil
        )

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示/隐藏悬浮球", action: #selector(menuToggleBall), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "打开主看板", action: #selector(menuShowKanban), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出 Focus Copilot", action: #selector(menuQuit), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    // MARK: - 状态栏图标

    /// 根据 Pin 状态更新状态栏图标
    @objc private func updateStatusBarIcon() {
        let hasPinned = !PinManager.shared.pinnedWindows.isEmpty
        statusItem?.button?.image = createStatusBarIcon(hasPinnedWindows: hasPinned)
    }

    /// 自绘状态栏图标：上方小图钉 + 下方 FC 文字
    /// - Parameter hasPinnedWindows: 是否有置顶窗口（有则红色着色，无则模板图标跟随系统深浅色）
    /// - Returns: 状态栏图标
    private func createStatusBarIcon(hasPinnedWindows: Bool) -> NSImage {
        let iconSize: CGFloat = 16
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        guard let pinSymbol = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Focus Copilot"),
              let configured = pinSymbol.withSymbolConfiguration(symbolConfig) else {
            return NSImage()
        }

        let image = NSImage(size: NSSize(width: iconSize, height: iconSize))
        image.lockFocus()

        if hasPinnedWindows {
            // 有标记窗口时：红色着色
            NSColor.systemRed.set()
            let rect = NSRect(
                x: (iconSize - configured.size.width) / 2,
                y: (iconSize - configured.size.height) / 2,
                width: configured.size.width,
                height: configured.size.height
            )
            configured.draw(in: rect)
            rect.fill(using: .sourceIn)
        } else {
            // 无标记窗口时：居中绘制
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
        }

        image.unlockFocus()

        // 无标记时设为模板图标，跟随系统深浅色
        image.isTemplate = !hasPinnedWindows

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

    /// 程序化绘制 FC+图钉品牌 Dock 图标（蓝色渐变圆角矩形底 + 白色图钉 + 白色 FC）
    private func setupDockIcon() {
        let iconSize: CGFloat = 128
        let icon = NSImage(size: NSSize(width: iconSize, height: iconSize))
        icon.lockFocus()

        // 1. 圆角矩形背景（Dock 图标标准形状）
        let bgRect = NSRect(x: 0, y: 0, width: iconSize, height: iconSize)
        let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: iconSize * 0.22, yRadius: iconSize * 0.22)
        let gradient = NSGradient(
            starting: NSColor(calibratedRed: 0.2, green: 0.5, blue: 0.9, alpha: 1.0),
            ending: NSColor(calibratedRed: 0.1, green: 0.3, blue: 0.7, alpha: 1.0)
        )
        gradient?.draw(in: bgPath, angle: 90)

        // 2. 上方白色图钉图标
        let pinFontSize = iconSize * 0.35
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: pinFontSize, weight: .semibold)
        if let pinSymbol = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil),
           let configured = pinSymbol.withSymbolConfiguration(symbolConfig) {
            let tinted = NSImage(size: configured.size)
            tinted.lockFocus()
            NSColor.white.set()
            let symbolRect = NSRect(origin: .zero, size: configured.size)
            configured.draw(in: symbolRect)
            symbolRect.fill(using: .sourceIn)
            tinted.unlockFocus()

            let pinX = (iconSize - tinted.size.width) / 2
            let pinY = iconSize * 0.85 - tinted.size.height
            tinted.draw(
                in: NSRect(x: pinX, y: pinY, width: tinted.size.width, height: tinted.size.height),
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0
            )
        }

        // 3. 下方白色 FC 文字
        let fcFontSize = iconSize * 0.28
        let fcFont = NSFont.systemFont(ofSize: fcFontSize, weight: .bold)
        let fcAttributes: [NSAttributedString.Key: Any] = [
            .font: fcFont,
            .foregroundColor: NSColor.white,
        ]
        let fcString = NSAttributedString(string: "FC", attributes: fcAttributes)
        let fcSize = fcString.size()
        let fcX = (iconSize - fcSize.width) / 2
        let fcY = iconSize * 0.05
        fcString.draw(at: NSPoint(x: fcX, y: fcY))

        icon.unlockFocus()

        NSApplication.shared.applicationIconImage = icon
    }
}
