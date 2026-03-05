import SwiftUI

/// Focus Copilot 应用入口
/// 使用 NSApplicationDelegateAdaptor 连接 AppDelegate，主要逻辑在 AppDelegate 中
/// 不显示主窗口，悬浮球通过 AppDelegate 手动创建
@main
struct FocusPilotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 不创建任何窗口，所有窗口由 AppDelegate 管理
        Settings {
            EmptyView()
        }
    }
}
