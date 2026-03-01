import AppKit
import ApplicationServices

// 窗口置顶状态管理
class PinManager: ObservableObject {
    static let shared = PinManager()

    // 便捷通知名（供外部监听使用）
    static let pinnedWindowsChanged = Constants.Notifications.pinnedWindowsChanged

    @Published var pinnedWindows: [PinnedWindow] = []

    var pinnedCount: Int { pinnedWindows.count }

    // AX 观察器，用于监听窗口生命周期事件
    private var axObservers: [CGWindowID: (observer: AXObserver, pid: pid_t, pointer: UnsafeMutablePointer<CGWindowID>)] = [:]

    private init() {}

    // MARK: - Pin/Unpin 操作

    /// Pin 一个窗口，返回是否成功
    func pin(window: WindowInfo) -> Bool {
        guard PermissionManager.shared.accessibilityGranted else { return false }
        guard pinnedCount < Constants.maxPinnedWindows else { return false }
        guard !isPinned(window.id) else { return false }

        let pinned = PinnedWindow(
            id: window.id,
            ownerBundleID: window.ownerBundleID,
            title: window.title,
            order: pinnedCount,
            ownerPID: window.ownerPID
        )

        pinnedWindows.append(pinned)

        // 设置窗口层级（后 pin 的窗口层级更高，显示在最上面）
        let level = Constants.pinnedWindowBaseLevel + Int32(pinnedCount)
        WindowService.shared.setWindowLevel(window.id, level: level)

        // 补充 AXRaise 确保窗口提升到前台
        WindowService.shared.axRaiseWindow(window.id)

        // 强制将窗口提升到所有窗口之上
        WindowService.shared.orderWindowAbove(window.id)

        // 激活目标 App，确保窗口获得焦点
        if let app = NSRunningApplication(processIdentifier: window.ownerPID) {
            app.activate()
        }

        NSLog("[PinTop] pin: 窗口 %d (%@) 已置顶，目标层级 %d", window.id, window.title, level)

        // 注册 AX 观察器监听窗口关闭/最小化
        observeWindow(windowID: window.id, pid: window.ownerPID)

        notifyChange()

        // Pin 音效
        if ConfigStore.shared.preferences.pinSoundEnabled {
            NSSound(named: "Tink")?.play()
        }

        return true
    }

    /// Unpin 一个窗口
    func unpin(windowID: CGWindowID) {
        guard let index = pinnedWindows.firstIndex(where: { $0.id == windowID }) else { return }

        // 恢复窗口层级为普通
        WindowService.shared.setWindowLevel(windowID, level: Int32(CGWindowLevelForKey(.normalWindow)))

        // 注销 AX 观察器
        removeObserver(for: windowID)

        pinnedWindows.remove(at: index)

        // Unpin 音效
        if ConfigStore.shared.preferences.pinSoundEnabled {
            NSSound(named: "Tink")?.play()
        }

        // 重新排序剩余窗口（保持后 pin 层级更高）
        for i in pinnedWindows.indices {
            pinnedWindows[i].order = i
            let level = Constants.pinnedWindowBaseLevel + Int32(i + 1)
            WindowService.shared.setWindowLevel(pinnedWindows[i].id, level: level)
        }

        notifyChange()
    }

    /// Unpin 所有窗口
    func unpinAll() {
        let windowIDs = pinnedWindows.map { $0.id }
        for id in windowIDs {
            WindowService.shared.setWindowLevel(id, level: Int32(CGWindowLevelForKey(.normalWindow)))
            removeObserver(for: id)
        }
        pinnedWindows.removeAll()
        notifyChange()
    }

    /// 切换 Pin 状态
    func togglePin(window: WindowInfo) {
        if isPinned(window.id) {
            unpin(windowID: window.id)
        } else {
            _ = pin(window: window)
        }
    }

    /// 重新排列层级
    func reorder(_ ids: [CGWindowID]) {
        var reordered: [PinnedWindow] = []
        for (index, id) in ids.enumerated() {
            if var window = pinnedWindows.first(where: { $0.id == id }) {
                window.order = index
                reordered.append(window)
                let level = Constants.pinnedWindowBaseLevel + Int32(index + 1)
                WindowService.shared.setWindowLevel(id, level: level)
            }
        }
        pinnedWindows = reordered
        notifyChange()
    }

    func isPinned(_ windowID: CGWindowID) -> Bool {
        pinnedWindows.contains { $0.id == windowID }
    }

    // MARK: - AX 窗口观察

    private func observeWindow(windowID: CGWindowID, pid: pid_t) {
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon = refcon else { return }
            let windowID = refcon.load(as: CGWindowID.self)
            let notifName = notification as String

            DispatchQueue.main.async {
                // 窗口关闭、最小化时自动 Unpin
                if notifName == kAXUIElementDestroyedNotification as String ||
                   notifName == kAXWindowMiniaturizedNotification as String {
                    PinManager.shared.unpin(windowID: windowID)
                }
                // 窗口 resize 时检查是否进入全屏，若全屏则自动 Unpin
                if notifName == kAXWindowResizedNotification as String {
                    var fullScreenValue: AnyObject?
                    let result = AXUIElementCopyAttributeValue(element, "AXFullScreen" as CFString, &fullScreenValue)
                    if result == .success,
                       let isFullScreen = fullScreenValue as? Bool,
                       isFullScreen {
                        PinManager.shared.unpin(windowID: windowID)
                    }
                }
            }
        }

        let status = AXObserverCreate(pid, callback, &observer)
        guard status == .success, let observer = observer else { return }

        // 通过 CGWindowID 精确匹配 AX 窗口，避免同名窗口误匹配
        guard let axWindow = WindowService.shared.findAXWindow(pid: pid, windowID: windowID) else { return }

        // 存储 windowID 用于回调
        let ptr = UnsafeMutablePointer<CGWindowID>.allocate(capacity: 1)
        ptr.pointee = windowID

        AXObserverAddNotification(observer, axWindow, kAXUIElementDestroyedNotification as CFString, ptr)
        AXObserverAddNotification(observer, axWindow, kAXWindowMiniaturizedNotification as CFString, ptr)
        AXObserverAddNotification(observer, axWindow, kAXWindowResizedNotification as CFString, ptr)

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)

        axObservers[windowID] = (observer: observer, pid: pid, pointer: ptr)
    }

    private func removeObserver(for windowID: CGWindowID) {
        guard let entry = axObservers.removeValue(forKey: windowID) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(entry.observer), .defaultMode)
        entry.pointer.deallocate()
    }

    // MARK: - 通知

    private func notifyChange() {
        NotificationCenter.default.post(name: Constants.Notifications.pinnedWindowsChanged, object: nil)
    }
}
