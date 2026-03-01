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
            case .unpinAll:
                PinManager.shared.unpinAll()
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
            } else {
                ball.show()
            }
        }
    }

    // MARK: - 菜单栏

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "PinTop")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示/隐藏悬浮球", action: #selector(menuToggleBall), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "打开主看板", action: #selector(menuShowKanban), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出 PinTop", action: #selector(menuQuit), keyEquivalent: "q"))

        statusItem?.menu = menu
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
}
