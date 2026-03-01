import AppKit
import ApplicationServices

// 窗口标记状态管理（纯视觉标记，不控制窗口层级）
class PinManager: ObservableObject {
    static let shared = PinManager()

    // 便捷通知名（供外部监听使用）
    static let pinnedWindowsChanged = Constants.Notifications.pinnedWindowsChanged

    @Published var pinnedWindows: [PinnedWindow] = []

    var pinnedCount: Int { pinnedWindows.count }

    private init() {}

    // MARK: - Pin/Unpin 操作

    /// Pin 一个窗口（纯标记，不控制层级），返回是否成功
    func pin(window: WindowInfo) -> Bool {
        guard !isPinned(window.id) else { return false }

        let pinned = PinnedWindow(
            id: window.id,
            ownerBundleID: window.ownerBundleID,
            title: window.title,
            order: pinnedCount,
            ownerPID: window.ownerPID
        )

        pinnedWindows.append(pinned)

        NSLog("[FocusCopilot] pin: 窗口 %d (%@) 已标记", window.id, window.title)

        notifyChange()

        return true
    }

    /// Unpin 一个窗口
    func unpin(windowID: CGWindowID) {
        guard let index = pinnedWindows.firstIndex(where: { $0.id == windowID }) else { return }

        pinnedWindows.remove(at: index)

        // 重新排序剩余窗口
        for i in pinnedWindows.indices {
            pinnedWindows[i].order = i
        }

        notifyChange()
    }

    /// Unpin 所有窗口
    func unpinAll() {
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

    /// 重新排列顺序
    func reorder(_ ids: [CGWindowID]) {
        var reordered: [PinnedWindow] = []
        for (index, id) in ids.enumerated() {
            if var window = pinnedWindows.first(where: { $0.id == id }) {
                window.order = index
                reordered.append(window)
            }
        }
        pinnedWindows = reordered
        notifyChange()
    }

    func isPinned(_ windowID: CGWindowID) -> Bool {
        pinnedWindows.contains { $0.id == windowID }
    }

    // MARK: - 通知

    private func notifyChange() {
        NotificationCenter.default.post(name: Constants.Notifications.pinnedWindowsChanged, object: nil)
    }
}
