import AppKit

// MARK: - 悬浮球视图
// 40x40px 圆形半透明毛玻璃质感，支持拖拽、贴边吸附、贴边半隐藏、hover 弹出快捷面板

final class FloatingBallView: NSView {

    // MARK: - 状态

    /// 是否正在拖拽中
    private var isDragging = false
    /// 拖拽起始点（窗口坐标系）
    private var dragStartPoint: CGPoint = .zero
    /// 拖拽起始时窗口位置
    private var windowStartOrigin: CGPoint = .zero
    /// 是否贴边半隐藏中
    private var isHalfHidden = false
    /// hover 计时器（300ms 后触发快捷面板）
    private var hoverTimer: Timer?
    /// 追踪区域
    private var trackingArea: NSTrackingArea?
    /// 角标数量
    private var badgeCount: Int = 0
    /// 单击检测计时器（区分单击和双击）
    private var clickTimer: Timer?
    /// 当前点击次数
    private var clickCount: Int = 0

    // MARK: - 子视图

    /// 毛玻璃背景
    private let visualEffectView: NSVisualEffectView = {
        let view = NSVisualEffectView()
        view.material = .popover
        view.state = .active
        view.blendingMode = .behindWindow
        view.wantsLayer = true
        view.layer?.cornerRadius = Constants.Ball.defaultSize / 2
        view.layer?.masksToBounds = true
        return view
    }()

    /// 渐变覆盖层（增强立体感）
    private let gradientOverlay: NSView = {
        let view = NSView()
        view.wantsLayer = true
        let gradient = CAGradientLayer()
        gradient.colors = [
            NSColor.white.withAlphaComponent(0.15).cgColor,
            NSColor.white.withAlphaComponent(0.02).cgColor,
            NSColor.black.withAlphaComponent(0.05).cgColor,
        ]
        gradient.locations = [0.0, 0.5, 1.0]
        gradient.startPoint = CGPoint(x: 0.5, y: 1.0)
        gradient.endPoint = CGPoint(x: 0.5, y: 0.0)
        view.layer = gradient
        return view
    }()

    /// 图钉图标
    private let iconView: NSImageView = {
        let imageView = NSImageView()
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        if let image = NSImage(systemSymbolName: "pin", accessibilityDescription: "PinTop") {
            let configured = image.withSymbolConfiguration(config) ?? image
            imageView.image = configured
        }
        imageView.contentTintColor = .labelColor
        imageView.imageScaling = .scaleProportionallyDown
        imageView.wantsLayer = true
        return imageView
    }()

    /// 角标视图（药丸形状）
    private let badgeLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 9, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.backgroundColor = .systemRed
        label.isBezeled = false
        label.isEditable = false
        label.wantsLayer = true
        label.layer?.cornerRadius = 8
        label.layer?.masksToBounds = true
        label.layer?.borderWidth = 1.5
        label.layer?.borderColor = NSColor.white.withAlphaComponent(0.8).cgColor
        label.isHidden = true
        return label
    }()

    // MARK: - 初始化

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
        setupNotifications()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
        setupNotifications()
    }

    deinit {
        hoverTimer?.invalidate()
        clickTimer?.invalidate()
        if let area = trackingArea {
            removeTrackingArea(area)
        }
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 视图设置

    private func setupView() {
        wantsLayer = true
        let size = CGFloat(Constants.Ball.defaultSize)

        // 外层投影光晕
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.3).cgColor
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        layer?.shadowOpacity = 0.5

        // 毛玻璃背景
        visualEffectView.frame = NSRect(x: 0, y: 0, width: size, height: size)
        addSubview(visualEffectView)

        // 渐变覆盖层
        gradientOverlay.frame = NSRect(x: 0, y: 0, width: size, height: size)
        gradientOverlay.layer?.cornerRadius = size / 2
        gradientOverlay.layer?.masksToBounds = true
        addSubview(gradientOverlay)

        // 图钉图标（居中）
        let iconSize: CGFloat = 22
        iconView.frame = NSRect(
            x: (size - iconSize) / 2,
            y: (size - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        addSubview(iconView)

        // 角标（右上角偏外，药丸形状）
        let badgeWidth: CGFloat = 20
        let badgeHeight: CGFloat = 16
        badgeLabel.frame = NSRect(x: size - badgeWidth + 4, y: size - badgeHeight + 4, width: badgeWidth, height: badgeHeight)
        badgeLabel.layer?.cornerRadius = badgeHeight / 2
        addSubview(badgeLabel)

        // 添加鼠标追踪区域
        updateTrackingArea()
    }

    // MARK: - 布局更新

    /// 当窗口大小变化时更新子视图布局
    func updateLayout(size: CGFloat) {
        visualEffectView.frame = NSRect(x: 0, y: 0, width: size, height: size)
        visualEffectView.layer?.cornerRadius = size / 2

        gradientOverlay.frame = NSRect(x: 0, y: 0, width: size, height: size)
        gradientOverlay.layer?.cornerRadius = size / 2

        let iconSize: CGFloat = 22
        iconView.frame = NSRect(
            x: (size - iconSize) / 2,
            y: (size - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )

        let badgeWidth: CGFloat = 20
        let badgeHeight: CGFloat = 16
        badgeLabel.frame = NSRect(x: size - badgeWidth + 4, y: size - badgeHeight + 4, width: badgeWidth, height: badgeHeight)

        needsDisplay = true
    }

    // MARK: - 追踪区域

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        updateTrackingArea()
    }

    private func updateTrackingArea() {
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: - 通知监听

    private func setupNotifications() {
        // 监听 Pin 窗口变化，更新角标
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pinnedWindowsDidChange),
            name: PinManager.pinnedWindowsChanged,
            object: nil
        )
    }

    @objc private func pinnedWindowsDidChange() {
        let count = PinManager.shared.pinnedCount
        updateBadge(count)
    }

    // MARK: - 角标

    /// 更新角标显示 + 图标样式
    func updateBadge(_ count: Int) {
        badgeCount = count
        if count > 0 {
            badgeLabel.stringValue = "\(count)"
            badgeLabel.isHidden = false
            // 有置顶窗口时：pin.fill + 主题色
            let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
            if let image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "PinTop") {
                iconView.image = image.withSymbolConfiguration(config) ?? image
            }
            iconView.contentTintColor = .systemBlue
        } else {
            badgeLabel.isHidden = true
            // 无置顶窗口时：pin + 默认色
            let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
            if let image = NSImage(systemSymbolName: "pin", accessibilityDescription: "PinTop") {
                iconView.image = image.withSymbolConfiguration(config) ?? image
            }
            iconView.contentTintColor = .labelColor
        }
        needsDisplay = true
    }

    // MARK: - 鼠标事件：hover

    override func mouseEntered(with event: NSEvent) {
        // 如果正在拖拽中，不触发 hover
        guard !isDragging else { return }

        // 如果贴边半隐藏，先滑出
        if isHalfHidden {
            slideOut()
        }

        // hover 放大动画
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().layer?.setAffineTransform(CGAffineTransform(scaleX: 1.08, y: 1.08))
        }
        // 图标轻微放大
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.iconView.animator().layer?.setAffineTransform(CGAffineTransform(scaleX: 1.15, y: 1.15))
        }

        // 启动 300ms hover 计时器
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: Constants.Ball.hoverDelay, repeats: false) { [weak self] _ in
            self?.triggerQuickPanel()
        }
    }

    override func mouseExited(with event: NSEvent) {
        // 取消 hover 计时器
        hoverTimer?.invalidate()
        hoverTimer = nil

        // 恢复原始大小
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().layer?.setAffineTransform(.identity)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.iconView.animator().layer?.setAffineTransform(.identity)
        }

        // 通知快捷面板鼠标已离开悬浮球
        NotificationCenter.default.post(
            name: NSNotification.Name("FloatingBall.mouseExited"),
            object: nil
        )
    }

    /// 触发快捷面板显示
    private func triggerQuickPanel() {
        guard let window = window else { return }
        NotificationCenter.default.post(
            name: NSNotification.Name("FloatingBall.showQuickPanel"),
            object: nil,
            userInfo: ["ballFrame": NSValue(rect: window.frame)]
        )
    }

    // MARK: - 鼠标事件：拖拽 + 点击

    override func mouseDown(with event: NSEvent) {
        isDragging = false
        dragStartPoint = event.locationInWindow
        windowStartOrigin = window?.frame.origin ?? .zero
        clickCount += 1
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window else { return }

        // 拖拽开始后取消 hover 计时器并关闭面板
        if !isDragging {
            isDragging = true
            hoverTimer?.invalidate()
            hoverTimer = nil
            clickCount = 0
            // 通知关闭快捷面板
            NotificationCenter.default.post(
                name: NSNotification.Name("FloatingBall.dragStarted"),
                object: nil
            )
        }

        let currentPoint = event.locationInWindow
        let deltaX = currentPoint.x - dragStartPoint.x
        let deltaY = currentPoint.y - dragStartPoint.y

        var newOrigin = CGPoint(
            x: windowStartOrigin.x + deltaX,
            y: windowStartOrigin.y + deltaY
        )

        // 限制在当前屏幕可见区域
        if let screen = window.screen ?? NSScreen.main {
            let visibleFrame = screen.visibleFrame
            let ballSize = window.frame.size
            newOrigin.x = max(visibleFrame.minX, min(newOrigin.x, visibleFrame.maxX - ballSize.width))
            newOrigin.y = max(visibleFrame.minY, min(newOrigin.y, visibleFrame.maxY - ballSize.height))
        }

        window.setFrameOrigin(newOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            // 拖拽结束：吸附到最近边缘 + 检测贴边半隐藏
            isDragging = false
            snapToEdge()
            return
        }

        // 处理点击（区分单击/双击）
        let currentClickCount = clickCount

        // 取消之前的单击计时器
        clickTimer?.invalidate()

        if currentClickCount >= 2 {
            // 双击：隐藏悬浮球
            clickCount = 0
            handleDoubleClick()
        } else {
            // 等待 250ms 判断是否还有第二次点击
            clickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
                self?.clickCount = 0
                self?.handleSingleClick()
            }
        }
    }

    // MARK: - 点击处理

    /// 单击：打开主看板
    private func handleSingleClick() {
        NotificationCenter.default.post(
            name: NSNotification.Name("FloatingBall.openMainKanban"),
            object: nil
        )
    }

    /// 双击：隐藏悬浮球
    private func handleDoubleClick() {
        hide()
    }

    // MARK: - 贴边吸附

    /// 拖拽结束后吸附到最近的屏幕边缘
    private func snapToEdge() {
        guard let window = window,
              let screen = window.screen ?? NSScreen.main else { return }

        let visibleFrame = screen.visibleFrame
        let ballFrame = window.frame
        let center = CGPoint(
            x: ballFrame.midX,
            y: ballFrame.midY
        )

        // 计算到四个边缘的距离
        let distLeft = center.x - visibleFrame.minX
        let distRight = visibleFrame.maxX - center.x
        let distTop = visibleFrame.maxY - center.y
        let distBottom = center.y - visibleFrame.minY

        let minDist = min(distLeft, distRight, distTop, distBottom)
        var targetOrigin = ballFrame.origin
        var edge: ScreenEdge

        switch minDist {
        case distLeft:
            targetOrigin.x = visibleFrame.minX
            edge = .left
        case distRight:
            targetOrigin.x = visibleFrame.maxX - ballFrame.width
            edge = .right
        case distTop:
            targetOrigin.y = visibleFrame.maxY - ballFrame.height
            edge = .top
        default:
            targetOrigin.y = visibleFrame.minY
            edge = .bottom
        }

        // 吸附动画
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrameOrigin(targetOrigin)
        }, completionHandler: { [weak self] in
            self?.checkHalfHide(edge: edge)
            self?.savePosition(edge: edge)
        })
    }

    // MARK: - 贴边半隐藏

    /// 检查是否需要贴边半隐藏
    private func checkHalfHide(edge: ScreenEdge) {
        guard let window = window,
              let screen = window.screen ?? NSScreen.main else { return }

        let visibleFrame = screen.visibleFrame
        let ballFrame = window.frame
        let threshold: CGFloat = 2 // 距离边缘 2px 以内触发半隐藏

        var shouldHide = false
        switch edge {
        case .left:
            shouldHide = ballFrame.minX <= visibleFrame.minX + threshold
        case .right:
            shouldHide = ballFrame.maxX >= visibleFrame.maxX - threshold
        case .top:
            shouldHide = ballFrame.maxY >= visibleFrame.maxY - threshold
        case .bottom:
            shouldHide = ballFrame.minY <= visibleFrame.minY + threshold
        }

        if shouldHide {
            slideIn(edge: edge)
        }
    }

    /// 贴边时滑入一半（半隐藏）
    private func slideIn(edge: ScreenEdge) {
        guard let window = window else { return }

        let ballSize = window.frame.size
        let halfWidth = ballSize.width / 2
        let halfHeight = ballSize.height / 2
        var target = window.frame.origin

        switch edge {
        case .left:
            target.x -= halfWidth
        case .right:
            target.x += halfWidth
        case .top:
            target.y += halfHeight
        case .bottom:
            target.y -= halfHeight
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrameOrigin(target)
        }, completionHandler: { [weak self] in
            self?.isHalfHidden = true
        })
    }

    /// 鼠标靠近时滑出
    private func slideOut() {
        guard let window = window else { return }

        let position = ConfigStore.shared.ballPosition
        let target = CGPoint(x: position.x, y: position.y)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrameOrigin(target)
        })

        isHalfHidden = false
    }

    // MARK: - 位置持久化

    private func savePosition(edge: ScreenEdge) {
        guard let window = window else { return }
        let origin = window.frame.origin
        ConfigStore.shared.ballPosition = BallPosition(x: origin.x, y: origin.y, edge: edge)
        ConfigStore.shared.save()
    }

    // MARK: - 显示/隐藏

    func hide() {
        guard let window = window as? FloatingBallWindow else { return }
        window.hide()
    }

    func show() {
        guard let window = window as? FloatingBallWindow else { return }
        window.show()
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 圆形裁剪路径
        let path = NSBezierPath(ovalIn: bounds)
        path.addClip()

        // 半透明背景（增强毛玻璃效果）
        NSColor.controlBackgroundColor.withAlphaComponent(0.2).setFill()
        path.fill()

        // 渐变边框：顶部高光 + 底部暗边
        let insetRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let borderPath = NSBezierPath(ovalIn: insetRect)
        borderPath.lineWidth = 1.0

        // 上半部分高光
        NSGraphicsContext.saveGraphicsState()
        let topClip = NSRect(x: bounds.minX, y: bounds.midY, width: bounds.width, height: bounds.height / 2)
        NSBezierPath(rect: topClip).addClip()
        NSColor.white.withAlphaComponent(0.3).setStroke()
        borderPath.stroke()
        NSGraphicsContext.restoreGraphicsState()

        // 下半部分暗边
        NSGraphicsContext.saveGraphicsState()
        let bottomClip = NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height / 2)
        NSBezierPath(rect: bottomClip).addClip()
        NSColor.black.withAlphaComponent(0.1).setStroke()
        borderPath.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    override var isFlipped: Bool { false }
}
