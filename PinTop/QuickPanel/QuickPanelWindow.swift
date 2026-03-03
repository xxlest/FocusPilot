import AppKit

// MARK: - 快捷面板窗口
// NSPanel 子类，悬浮球 hover 后弹出的快捷面板
// 无标题栏、有阴影、毛玻璃背景，窗口层级比悬浮球低一级
// 支持钉住模式、拖拽调整大小

final class QuickPanelWindow: NSPanel {

    // MARK: - 属性

    /// 收起延迟计时器（鼠标离开 500ms 后收起）
    private var dismissTimer: Timer?

    /// 面板内容视图
    private let panelView = QuickPanelView()

    /// 面板是否被钉住（钉住时不自动收起）
    var isPanelPinned = false

    // MARK: - Resize 状态

    private enum ResizeEdge {
        case right, bottom, bottomRight
    }

    private var isResizing = false
    private var resizeEdge: ResizeEdge?
    private var resizeStartMouseLocation: CGPoint = .zero
    private var resizeStartFrame: NSRect = .zero

    /// resize 热区宽度
    private let resizeHandleSize: CGFloat = 5
    private let resizeCornerSize: CGFloat = 10

    // MARK: - 面板拖动状态

    private var isDraggingPanel = false
    private var dragPanelStartMouseLocation: CGPoint = .zero
    private var dragPanelStartFrame: NSRect = .zero

    /// 防止联动拖动递归
    private var isSyncMoving = false

    // MARK: - 初始化

    init() {
        let savedSize = ConfigStore.shared.panelSize
        let frame = NSRect(x: 0, y: 0, width: savedSize.width, height: savedSize.height)

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configureWindow()
        setupNotifications()
    }

    deinit {
        dismissTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 窗口配置

    private func configureWindow() {
        // 窗口层级：比悬浮球低一级
        level = NSWindow.Level(rawValue: Int(Constants.quickPanelLevel))

        // 无标题栏、有阴影、毛玻璃背景
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear

        // 不出现在 Cmd+Tab 切换器中
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isExcludedFromWindowsMenu = true

        // 不能成为 key window，防止抢焦点
        isMovable = false
        isMovableByWindowBackground = false

        // 启用 mouseMoved 事件（resize 光标切换需要）
        acceptsMouseMovedEvents = true

        // 毛玻璃背景视图
        let effectView = NSVisualEffectView()
        effectView.material = .menu
        effectView.state = .active
        effectView.blendingMode = .behindWindow
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = Constants.Panel.cornerRadius
        effectView.layer?.masksToBounds = true

        // 把面板内容视图添加到毛玻璃背景上
        contentView = effectView
        panelView.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(panelView)

        NSLayoutConstraint.activate([
            panelView.topAnchor.constraint(equalTo: effectView.topAnchor),
            panelView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
            panelView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            panelView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
        ])
    }

    // MARK: - 通知监听

    private func setupNotifications() {
        // 监听悬浮球鼠标离开
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(ballMouseExited),
            name: Constants.Notifications.ballMouseExited,
            object: nil
        )
        // 监听浮球拖动，联动移动面板
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBallDragMoved(_:)),
            name: Constants.Notifications.ballDragMoved,
            object: nil
        )
    }

    @objc private func handleBallDragMoved(_ notification: Notification) {
        guard isPanelPinned, !isSyncMoving else { return }
        guard let deltaX = notification.userInfo?["deltaX"] as? CGFloat,
              let deltaY = notification.userInfo?["deltaY"] as? CGFloat else { return }
        isSyncMoving = true
        var newFrame = frame
        newFrame.origin.x += deltaX
        newFrame.origin.y += deltaY
        setFrame(newFrame, display: true)
        isSyncMoving = false
    }

    @objc private func ballMouseExited() {
        guard !isPanelPinned else { return }
        // 如果面板可见，启动收起计时器
        if isVisible {
            startDismissTimer()
        }
    }

    // MARK: - 窗口属性

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // MARK: - 显示/隐藏

    /// 根据悬浮球位置和屏幕空间自动判断展开方向
    func show(relativeTo ballFrame: CGRect) {
        // 取消收起计时器
        dismissTimer?.invalidate()
        dismissTimer = nil

        // 使用已存储的面板宽度
        let savedSize = ConfigStore.shared.panelSize
        var currentFrame = frame
        currentFrame.size.width = savedSize.width
        setFrame(currentFrame, display: false)

        // 刷新面板数据
        panelView.reloadData()

        // 计算面板位置
        let panelFrame = calculatePosition(relativeTo: ballFrame)
        setFrame(panelFrame, display: false)

        // 设置初始状态（从悬浮球方向滑出的起始位置）
        alphaValue = 0
        let slideOffset: CGFloat = 10
        let startFrame = offsetFrame(panelFrame, towards: ballFrame, by: slideOffset)
        setFrame(startFrame, display: false)

        orderFront(nil)

        // 滑出动画 150ms ease-out，最终透明度使用用户设置的面板透明度
        let targetOpacity = ConfigStore.shared.preferences.panelOpacity
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Constants.Panel.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(panelFrame, display: true)
            self.animator().alphaValue = targetOpacity
        })
    }

    /// 收起面板
    func hide() {
        dismissTimer?.invalidate()
        dismissTimer = nil

        // 收起动画 150ms ease-in
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Constants.Panel.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            // 防止 show/hide 竞态：如果动画期间又被 show()，不执行收起逻辑（浮点精度安全）
            guard self.alphaValue < 0.01 else { return }
            self.orderOut(nil)
            self.alphaValue = ConfigStore.shared.preferences.panelOpacity
            self.isPanelPinned = false
            self.panelView.resetToNormalMode()
            AppMonitor.shared.stopWindowRefresh()
        })
    }

    // MARK: - 钉住模式

    /// 切换面板钉住状态
    func togglePanelPin() {
        isPanelPinned.toggle()
        if isPanelPinned {
            cancelDismissTimer()
        }
        // 通知 panelView 更新钉住按钮状态
        NotificationCenter.default.post(
            name: Constants.Notifications.panelPinStateChanged,
            object: nil,
            userInfo: ["isPinned": isPanelPinned]
        )
    }

    // MARK: - 收起计时器

    /// 启动 500ms 收起延迟
    func startDismissTimer() {
        guard !isPanelPinned else { return }
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: Constants.Panel.dismissDelay, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    /// 取消收起计时器（鼠标重新进入时调用）
    func cancelDismissTimer() {
        dismissTimer?.invalidate()
        dismissTimer = nil
    }

    // MARK: - 事件分发拦截（修复 resize 热区被子视图吞没的问题）

    /// 非激活面板的 contentView 子视图（scrollView 等）会吞没 resize 热区的鼠标事件，
    /// 通过重写 sendEvent 在事件分发前拦截 resize 操作
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            let location = event.locationInWindow
            // 优先检测 resize 热区
            if resizeEdgeAt(location) != nil {
                mouseDown(with: event)
                return
            }
            // 检测 topBar 区域拖动（窗口顶部 24px）
            if location.y > frame.height - 24 {
                // 检查是否点击在按钮上（按钮点击不应被拖动拦截）
                if let hitView = contentView?.hitTest(location),
                   hitView is NSButton || hitView.superview is NSButton {
                    break // 让按钮正常处理点击
                }
                isDraggingPanel = true
                dragPanelStartMouseLocation = NSEvent.mouseLocation
                dragPanelStartFrame = frame
                return
            }
        case .leftMouseDragged:
            if isResizing {
                mouseDragged(with: event)
                return
            }
            if isDraggingPanel {
                handlePanelDrag()
                return
            }
        case .leftMouseUp:
            if isResizing {
                mouseUp(with: event)
                return
            }
            if isDraggingPanel {
                isDraggingPanel = false
                return
            }
        case .mouseMoved:
            // 在 sendEvent 层拦截 mouseMoved，确保 resize 光标不被子视图吞没
            let location = event.locationInWindow
            if let edge = resizeEdgeAt(location) {
                switch edge {
                case .right:       NSCursor.resizeLeftRight.set()
                case .bottom:      NSCursor.resizeUpDown.set()
                case .bottomRight: NSCursor.resizeLeftRight.set()
                }
                return
            } else {
                NSCursor.arrow.set()
            }
        default:
            break
        }
        super.sendEvent(event)
    }

    /// 处理面板拖动
    private func handlePanelDrag() {
        let currentMouse = NSEvent.mouseLocation
        // 计算增量 delta（相对上一帧）
        let deltaX = currentMouse.x - dragPanelStartMouseLocation.x
        let deltaY = currentMouse.y - dragPanelStartMouseLocation.y
        // 更新参考点为当前位置，下一帧计算增量
        dragPanelStartMouseLocation = currentMouse

        var newFrame = frame
        newFrame.origin.x += deltaX
        newFrame.origin.y += deltaY
        setFrame(newFrame, display: true)

        // 面板钉住时，同步拖动浮球
        if isPanelPinned {
            NotificationCenter.default.post(
                name: Constants.Notifications.panelDragMoved,
                object: nil,
                userInfo: ["deltaX": deltaX, "deltaY": deltaY]
            )
        }
    }

    // MARK: - Resize 鼠标事件

    override func mouseMoved(with event: NSEvent) {
        let location = event.locationInWindow
        if let edge = resizeEdgeAt(location) {
            switch edge {
            case .right:
                NSCursor.resizeLeftRight.set()
            case .bottom:
                NSCursor.resizeUpDown.set()
            case .bottomRight:
                NSCursor.resizeLeftRight.set()
            }
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let location = event.locationInWindow
        if let edge = resizeEdgeAt(location) {
            isResizing = true
            resizeEdge = edge
            resizeStartMouseLocation = NSEvent.mouseLocation
            resizeStartFrame = frame
        } else {
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isResizing, let edge = resizeEdge else {
            super.mouseDragged(with: event)
            return
        }

        let currentMouse = NSEvent.mouseLocation
        let deltaX = currentMouse.x - resizeStartMouseLocation.x
        let deltaY = currentMouse.y - resizeStartMouseLocation.y

        // 计算最大高度（屏幕可见区域的 60%）
        let maxHeight = (screen?.visibleFrame.height ?? 800) * Constants.Panel.maxHeightRatio

        var newFrame = resizeStartFrame

        switch edge {
        case .right:
            let newWidth = max(Constants.Panel.minWidth, min(resizeStartFrame.width + deltaX, Constants.Panel.maxWidth))
            newFrame.size.width = newWidth
        case .bottom:
            let newHeight = max(Constants.Panel.minHeight, min(resizeStartFrame.height - deltaY, maxHeight))
            newFrame.size.height = newHeight
            newFrame.origin.y = resizeStartFrame.origin.y + (resizeStartFrame.height - newHeight)
        case .bottomRight:
            let newWidth = max(Constants.Panel.minWidth, min(resizeStartFrame.width + deltaX, Constants.Panel.maxWidth))
            let newHeight = max(Constants.Panel.minHeight, min(resizeStartFrame.height - deltaY, maxHeight))
            newFrame.size.width = newWidth
            newFrame.size.height = newHeight
            newFrame.origin.y = resizeStartFrame.origin.y + (resizeStartFrame.height - newHeight)
        }

        setFrame(newFrame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        if isResizing {
            isResizing = false
            resizeEdge = nil
            NSCursor.arrow.set()
            // 保存面板大小
            ConfigStore.shared.panelSize = PanelSize(width: frame.width, height: frame.height)
            ConfigStore.shared.save()
        } else {
            super.mouseUp(with: event)
        }
    }

    /// 判断鼠标位置是否在 resize 热区
    private func resizeEdgeAt(_ location: CGPoint) -> ResizeEdge? {
        let w = frame.width

        let inRightEdge = location.x >= w - resizeHandleSize
        let inBottomEdge = location.y <= resizeHandleSize
        // 右下角使用更大的热区（10px），方便拖拽
        let inCornerRight = location.x >= w - resizeCornerSize
        let inCornerBottom = location.y <= resizeCornerSize

        if inCornerRight && inCornerBottom {
            return .bottomRight
        } else if inRightEdge {
            return .right
        } else if inBottomEdge {
            return .bottom
        }
        return nil
    }

    // MARK: - 鼠标追踪（用于 resize cursor）

    override func becomeKey() {
        super.becomeKey()
    }

    // MARK: - 位置计算

    /// 根据悬浮球位置和屏幕空间计算面板弹出位置
    private func calculatePosition(relativeTo ballFrame: CGRect) -> NSRect {
        guard let screen = screenContaining(ballFrame: ballFrame) else {
            return NSRect(x: ballFrame.maxX, y: ballFrame.minY, width: frame.width, height: frame.height)
        }

        let screenFrame = screen.visibleFrame
        let panelSize = NSSize(width: frame.width, height: frame.height)
        let gap = Constants.Panel.gapToBall

        // 判断悬浮球在屏幕的哪一侧
        let ballCenterX = ballFrame.midX
        let ballCenterY = ballFrame.midY

        var origin = CGPoint.zero

        // 水平方向：优先向右展开
        if ballCenterX < screenFrame.midX {
            // 悬浮球在左半边，向右展开
            origin.x = ballFrame.maxX + gap
        } else {
            // 悬浮球在右半边，向左展开
            origin.x = ballFrame.minX - gap - panelSize.width
        }

        // 垂直方向：面板顶部与悬浮球顶部对齐，但要确保不超出屏幕
        origin.y = ballCenterY - panelSize.height / 2

        // 边界修正
        origin.x = max(screenFrame.minX, min(origin.x, screenFrame.maxX - panelSize.width))
        origin.y = max(screenFrame.minY, min(origin.y, screenFrame.maxY - panelSize.height))

        return NSRect(origin: origin, size: panelSize)
    }

    /// 根据悬浮球位置找到其所在屏幕，避免多显示器场景下错误使用主屏幕
    private func screenContaining(ballFrame: CGRect) -> NSScreen? {
        let center = CGPoint(x: ballFrame.midX, y: ballFrame.midY)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
            return screen
        }
        return NSScreen.main
    }

    /// 计算滑出动画的起始偏移
    private func offsetFrame(_ target: NSRect, towards ballFrame: CGRect, by offset: CGFloat) -> NSRect {
        var shifted = target
        if target.midX > ballFrame.midX {
            shifted.origin.x -= offset
        } else {
            shifted.origin.x += offset
        }
        return shifted
    }
}
