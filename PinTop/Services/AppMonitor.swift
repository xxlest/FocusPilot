import AppKit
import ApplicationServices
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

    // P2: 自适应刷新 — 用 DispatchSourceTimer 替代 Timer
    private var windowRefreshTimer: DispatchSourceTimer?
    /// 连续无变化次数（用于动态调整刷新间隔）
    private var consecutiveNoChange: Int = 0
    /// 上一次窗口快照（用于检测变化）
    private var lastWindowSnapshot: [String: [CGWindowID]] = [:]
    /// 当前定时器间隔（避免无变化时重复重建定时器）
    private var currentTimerInterval: TimeInterval = 0

    // P1: AX 后台化 — 刷新代数，防止过期回调覆盖新数据
    private var refreshGeneration: UInt64 = 0

    private init() {}

    // MARK: - 监听控制

    func startMonitoring() {
        let workspace = NSWorkspace.shared

        // 监听 App 启动
        launchObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.resetAdaptiveInterval()
            self?.refreshRunningApps()
        }

        // 监听 App 退出
        terminateObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.resetAdaptiveInterval()
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
        WindowService.shared.invalidateAXCache()
        // 重置自适应状态
        consecutiveNoChange = 0
        scheduleRefreshTimer(interval: Constants.windowRefreshInterval)
        // 立即刷新一次
        refreshAllWindows()
    }

    func stopWindowRefresh() {
        windowRefreshTimer?.cancel()
        windowRefreshTimer = nil
        consecutiveNoChange = 0
        currentTimerInterval = 0
    }

    // MARK: - P2: 自适应刷新间隔

    /// 根据 consecutiveNoChange 计算当前刷新间隔
    private var adaptiveInterval: TimeInterval {
        if consecutiveNoChange < 3 {
            return 1.0
        } else if consecutiveNoChange < 8 {
            return 2.0
        } else {
            return 3.0
        }
    }

    /// 创建/重建 DispatchSourceTimer
    private func scheduleRefreshTimer(interval: TimeInterval) {
        // 间隔未变化时不重建
        guard interval != currentTimerInterval else { return }
        windowRefreshTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.refreshAllWindows()
        }
        timer.resume()
        windowRefreshTimer = timer
        currentTimerInterval = interval
    }

    /// 重置自适应间隔（App 启动/退出等事件触发时调用）
    private func resetAdaptiveInterval() {
        consecutiveNoChange = 0
        if windowRefreshTimer != nil {
            currentTimerInterval = 0  // 强制重建
            scheduleRefreshTimer(interval: 1.0)
        }
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
    /// P0: 单次 CGWindowList 查询 + P1: AX 后台两阶段刷新 + P2: 自适应间隔
    func refreshAllWindows() {
        // P0: 一次性获取所有可见窗口
        guard let allWindows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return }

        // P0: 按 PID 分组
        var windowsByPID: [pid_t: [[String: Any]]] = [:]
        for info in allWindows {
            if let pid = info[kCGWindowOwnerPID as String] as? pid_t {
                windowsByPID[pid, default: []].append(info)
            }
        }

        // Phase 1: 用 CG 标题快速构建 WindowInfo → 发通知 → UI 先渲染
        var currentSnapshot: [String: [CGWindowID]] = [:]
        for app in runningApps {
            let pid = app.nsApp?.processIdentifier ?? -1
            // 直接用已持有的进程引用判断运行状态（避免 N 次系统调用）
            let running = app.nsApp?.isTerminated == false

            app.isRunning = running
            if running, let cgWindows = windowsByPID[pid] {
                app.windows = WindowService.shared.buildWindowInfo(for: pid, from: cgWindows)
            } else {
                app.windows = []
            }
            currentSnapshot[app.bundleID] = app.windows.map { $0.id }
        }

        // 清理已关闭窗口的标题缓存
        let activeIDs = Set(runningApps.flatMap { $0.windows.map { $0.id } })
        WindowService.shared.pruneCache(keeping: activeIDs)

        NotificationCenter.default.post(name: Constants.Notifications.windowsChanged, object: nil)

        // P2: 检测变化，调整刷新间隔
        if currentSnapshot == lastWindowSnapshot {
            consecutiveNoChange += 1
        } else {
            consecutiveNoChange = 0
            lastWindowSnapshot = currentSnapshot
        }
        if windowRefreshTimer != nil {
            scheduleRefreshTimer(interval: adaptiveInterval)
        }

        // Phase 2: 异步 AX 标题补全
        refreshGeneration += 1
        let gen = refreshGeneration
        // 只为有窗口的 PID 构建 AX 映射
        var pidWindowMap: [pid_t: [[String: Any]]] = [:]
        for app in runningApps where app.isRunning && !app.windows.isEmpty {
            let pid = app.nsApp?.processIdentifier ?? -1
            if let cgWindows = windowsByPID[pid] {
                pidWindowMap[pid] = cgWindows
            }
        }

        guard !pidWindowMap.isEmpty else { return }

        WindowService.shared.buildAXTitleMapAsync(for: pidWindowMap) { [weak self] axMap in
            guard let self = self else { return }
            // 检查代数，过期则丢弃
            guard gen == self.refreshGeneration else { return }
            // 应用 AX 标题到缓存
            let changed = WindowService.shared.applyAXTitles(axMap)
            guard changed else { return }
            // 标题有变化，用缓存后的标题重建 WindowInfo
            for app in self.runningApps where app.isRunning && !app.windows.isEmpty {
                let pid = app.nsApp?.processIdentifier ?? -1
                if let cgWindows = windowsByPID[pid] {
                    app.windows = WindowService.shared.buildWindowInfo(for: pid, from: cgWindows)
                }
            }
            NotificationCenter.default.post(name: Constants.Notifications.windowsChanged, object: nil)
        }
    }

    /// 刷新指定 App 的窗口
    func refreshWindows(for bundleID: String) {
        if let app = runningApps.first(where: { $0.bundleID == bundleID }) {
            app.windows = WindowService.shared.listWindows(for: bundleID)
            NotificationCenter.default.post(name: Constants.Notifications.windowsChanged, object: nil)
        }
    }

    // MARK: - 已安装 App 扫描

    /// 后台线程扫描已安装 App（避免阻塞主线程）
    func scanInstalledApps() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
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

            let sorted = apps.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            DispatchQueue.main.async {
                self?.installedApps = sorted
            }
        }
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
