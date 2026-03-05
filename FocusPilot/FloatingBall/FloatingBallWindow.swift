import AppKit

// MARK: - 悬浮球窗口
// NSPanel 子类，作为悬浮球的承载窗口
// 层级高于所有应用窗口，始终显示在所有桌面空间

final class FloatingBallWindow: NSPanel {

    // MARK: - 初始化

    init() {
        // 悬浮球默认大小
        let size = CGFloat(Constants.Ball.defaultSize)
        let frame = NSRect(x: 0, y: 0, width: size, height: size)

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configureWindow()
    }

    // MARK: - 窗口配置

    private func configureWindow() {
        // 窗口层级：高于所有应用窗口（包括 Pin 的窗口）
        level = NSWindow.Level(rawValue: Int(Constants.floatingBallLevel))

        // 无标题栏、无阴影、透明背景
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        hasShadow = false
        isOpaque = false
        backgroundColor = .clear

        // 始终显示在所有桌面空间
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // 不出现在 Cmd+Tab 切换器中
        hidesOnDeactivate = false
        isExcludedFromWindowsMenu = true

        // 可移动、忽略鼠标事件（由视图处理）
        isMovable = false
        isMovableByWindowBackground = false

        // 允许鼠标事件透传（非悬浮球区域）
        ignoresMouseEvents = false

        // 设置悬浮球视图
        let ballView = FloatingBallView()
        contentView = ballView
    }

    // MARK: - 鼠标事件透传

    // 非悬浮球区域的点击穿透到下层窗口
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // MARK: - 显示/隐藏

    func show() {
        orderFront(nil)
    }

    func hide() {
        orderOut(nil)
    }

    // MARK: - 位置管理

    /// 移动到指定位置（屏幕坐标）
    func moveTo(_ point: CGPoint) {
        setFrameOrigin(point)
    }

    /// 恢复到上次保存的位置
    func restorePosition() {
        let position = ConfigStore.shared.ballPosition
        let point = CGPoint(x: position.x, y: position.y)
        moveTo(point)
    }

    /// 更新窗口大小（当偏好设置中球体大小变化时）
    func updateSize(_ size: CGFloat) {
        let origin = frame.origin
        setFrame(NSRect(x: origin.x, y: origin.y, width: size, height: size), display: true)

        // 同步更新子视图布局（cornerRadius、icon 居中等）
        if let ballView = contentView as? FloatingBallView {
            ballView.updateLayout(size: size)
        }
    }
}
