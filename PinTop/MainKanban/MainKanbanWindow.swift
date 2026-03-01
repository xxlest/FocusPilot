import AppKit
import SwiftUI

/// 主看板窗口
/// 尺寸 800x600，最小 640x480，居中显示，普通窗口层级
class MainKanbanWindow: NSWindow {

    init() {
        let contentRect = NSRect(x: 0, y: 0, width: 800, height: 600)
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        title = "PinTop"
        minSize = NSSize(width: 640, height: 480)
        center()

        // 普通窗口层级
        level = .normal

        // 关闭时隐藏而非销毁
        isReleasedWhenClosed = false

        // 嵌入 SwiftUI 视图
        let hostingController = NSHostingController(rootView: MainKanbanView())
        contentViewController = hostingController
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
