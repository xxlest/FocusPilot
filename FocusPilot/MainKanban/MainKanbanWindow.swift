import AppKit
import SwiftUI

/// 主看板窗口
/// 尺寸 800x600，最小 640x480，居中显示，普通窗口层级
/// 关闭主看板 = 仅隐藏窗口，不退出 App
class MainKanbanWindow: NSWindow, NSWindowDelegate {

    init() {
        let contentRect = NSRect(x: 0, y: 0, width: 800, height: 600)
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        title = "Focus Copilot"
        // 隐藏标题栏中的导航标题（不显示侧边栏当前激活项名称）
        subtitle = ""
        minSize = NSSize(width: 640, height: 480)
        center()

        // 普通窗口层级
        level = .normal

        isReleasedWhenClosed = false

        // 设置自身为 delegate，拦截关闭事件
        delegate = self

        // 嵌入 SwiftUI 视图
        let hostingController = NSHostingController(rootView: MainKanbanView())
        contentViewController = hostingController
    }

    // MARK: - NSWindowDelegate

    /// 关闭主看板时仅隐藏窗口，不退出 App
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        orderOut(nil)
        return false
    }

    /// 显示并聚焦窗口
    func show() {
        if !isVisible {
            center()
        }
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
