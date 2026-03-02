import AppKit
import Combine

// App 运行状态监控服务
class AppMonitor: ObservableObject {
    static let shared = AppMonitor()

    // 便捷通知名（供外部监听使用）
    static let windowsChanged = Constants.Notifications.windowsChanged
    static let appStatusChanged = Constants.Notifications.appStatusChanged

    /// 运行中的 App（所有 regular App，带窗口信息）
    @Published var runningApps: [RunningApp] = []

    /// 已安装的 App 列表
    @Published var installedApps: [InstalledApp] = []

    private var launchObserver: Any?
    private var terminateObserver: Any?
    private var accessibilityObserver: Any?
    private var windowRefreshTimer: Timer?

    private init() {}

    // MARK: - 监听控制

    func startMonitoring() {
        let workspace = NSWorkspace.shared

        // 监听 App 启动
        launchObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshRunningApps()
        }

        // 监听 App 退出
        terminateObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshRunningApps()
        }

        // 监听辅助功能权限恢复（codesign 后权限失效→用户重新授权）
        accessibilityObserver = NotificationCenter.default.addObserver(
            forName: Constants.Notifications.accessibilityGranted,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshRunningApps()
        }

        // 初始刷新
        refreshRunningApps()
        scanInstalledApps()
    }

    func stopMonitoring() {
        if let obs = launchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            launchObserver = nil
        }
        if let obs = terminateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            terminateObserver = nil
        }
        if let obs = accessibilityObserver {
            NotificationCenter.default.removeObserver(obs)
            accessibilityObserver = nil
        }
        stopWindowRefresh()
    }

    // MARK: - 窗口刷新定时器（面板显示时启动）

    func startWindowRefresh() {
        guard windowRefreshTimer == nil else { return }
        // 同步权限状态（codesign 后权限可能变化）
        PermissionManager.shared.checkAccessibility()
        windowRefreshTimer = Timer.scheduledTimer(withTimeInterval: Constants.windowRefreshInterval, repeats: true) { [weak self] _ in
            self?.refreshAllWindows()
        }
        // 立即刷新一次
        refreshAllWindows()
    }

    func stopWindowRefresh() {
        windowRefreshTimer?.invalidate()
        windowRefreshTimer = nil
    }

    // MARK: - 刷新逻辑

    /// 刷新运行中的 App 列表（遍历所有 regular App，不依赖 ConfigStore）
    func refreshRunningApps() {
        let selfBundleID = Bundle.main.bundleIdentifier ?? "com.focuscopilot.FocusCopilot"
        let workspace = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != selfBundleID }
            .sorted { ($0.localizedName ?? "").localizedCompare($1.localizedName ?? "") == .orderedAscending }

        var updated: [RunningApp] = []

        for nsApp in workspace {
            let bundleID = nsApp.bundleIdentifier!
            let windows = WindowService.shared.listWindows(for: nsApp.processIdentifier)
            let app = RunningApp(
                bundleID: bundleID,
                localizedName: nsApp.localizedName ?? bundleID,
                icon: nsApp.icon ?? NSImage(named: NSImage.applicationIconName)!,
                nsApp: nsApp,
                windows: windows,
                isRunning: true
            )
            updated.append(app)
        }

        runningApps = updated
        NotificationCenter.default.post(name: Constants.Notifications.appStatusChanged, object: nil)
    }

    /// 刷新所有已配置 App 的窗口列表
    func refreshAllWindows() {
        for app in runningApps {
            let running = NSRunningApplication.runningApplications(
                withBundleIdentifier: app.bundleID
            ).first(where: { $0.activationPolicy == .regular }) != nil

            app.isRunning = running
            if running {
                app.windows = WindowService.shared.listWindows(for: app.bundleID)
            } else {
                app.windows = []
            }
        }
        NotificationCenter.default.post(name: Constants.Notifications.windowsChanged, object: nil)
    }

    /// 刷新指定 App 的窗口
    func refreshWindows(for bundleID: String) {
        if let app = runningApps.first(where: { $0.bundleID == bundleID }) {
            app.windows = WindowService.shared.listWindows(for: bundleID)
            NotificationCenter.default.post(name: Constants.Notifications.windowsChanged, object: nil)
        }
    }

    // MARK: - 已安装 App 扫描

    func scanInstalledApps() {
        var apps: [InstalledApp] = []
        let directories = [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]

        for dir in directories {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil
            ) else { continue }

            for url in contents where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url),
                      let bundleID = bundle.bundleIdentifier else { continue }

                let name = FileManager.default.displayName(atPath: url.path)
                let icon = NSWorkspace.shared.icon(forFile: url.path)

                apps.append(InstalledApp(
                    bundleID: bundleID,
                    name: name,
                    icon: icon,
                    url: url
                ))
            }
        }

        installedApps = apps.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    // MARK: - 辅助

    /// 检查指定 App 是否正在运行
    func isRunning(_ bundleID: String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first(where: { $0.activationPolicy == .regular }) != nil
    }

    /// 获取 App 图标
    private func iconForBundle(_ bundleID: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(named: NSImage.applicationIconName)!
    }
}
