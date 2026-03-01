import AppKit
import ApplicationServices

// 辅助功能权限管理
class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published var accessibilityGranted: Bool = false

    private var pollTimer: Timer?
    private var backgroundCheckTimer: Timer?

    private init() {
        accessibilityGranted = AXIsProcessTrusted()
        startBackgroundCheck()
    }

    deinit {
        stopPolling()
        stopBackgroundCheck()
    }

    // MARK: - 权限检查

    /// 检查辅助功能权限
    func checkAccessibility() -> Bool {
        accessibilityGranted = AXIsProcessTrusted()
        return accessibilityGranted
    }

    /// 请求辅助功能权限（弹出系统引导）
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - 轮询检测

    /// 开始轮询权限状态（用于权限引导页面）
    func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: Constants.permissionPollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            let granted = AXIsProcessTrusted()
            guard granted != self.accessibilityGranted else { return }
            DispatchQueue.main.async {
                self.accessibilityGranted = granted
                // 权限状态变化时清除 AX 可用性缓存
                WindowService.shared.invalidateAXCache()
                if granted {
                    // 通知权限已恢复，由监听方刷新窗口列表（解耦 AppMonitor）
                    NotificationCenter.default.post(name: Constants.Notifications.accessibilityGranted, object: nil)
                    self.stopPolling()
                }
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - 后台持续检测（应对 codesign 导致权限失效等场景）

    /// 启动后台权限检测，每 3 秒检查一次权限状态变化
    private func startBackgroundCheck() {
        guard backgroundCheckTimer == nil else { return }
        backgroundCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let granted = AXIsProcessTrusted()
            guard granted != self.accessibilityGranted else { return }
            DispatchQueue.main.async {
                self.accessibilityGranted = granted
                // 权限状态变化时清除 AX 可用性缓存
                WindowService.shared.invalidateAXCache()
                if granted {
                    // 权限恢复，通知监听方刷新窗口列表
                    NotificationCenter.default.post(name: Constants.Notifications.accessibilityGranted, object: nil)
                    AppMonitor.shared.refreshRunningApps()
                }
            }
        }
    }

    private func stopBackgroundCheck() {
        backgroundCheckTimer?.invalidate()
        backgroundCheckTimer = nil
    }
}
