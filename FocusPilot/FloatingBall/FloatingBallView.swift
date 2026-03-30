import AppKit

// MARK: - 悬浮球视图
// 40x40px 圆形半透明毛玻璃质感，支持拖拽、贴边吸附、贴边半隐藏、hover 弹出快捷面板

final class FloatingBallView: NSView {

    // MARK: - 状态

    /// 是否正在拖拽中
    private var isDragging = false
    /// 拖拽起始点（屏幕坐标系）
    private var dragStartPoint: CGPoint = .zero
    /// 拖拽起始时窗口位置
    private var windowStartOrigin: CGPoint = .zero
    /// 是否贴边半隐藏中
    private var isHalfHidden = false
    /// hover 计时器（300ms 后触发快捷面板）
    private var hoverTimer: Timer?
    /// 追踪区域
    private var trackingArea: NSTrackingArea?
    /// 面板是否被钉住（钉住时不响应 hover）
    private var isPanelPinned = false
    /// 防止联动拖动递归
    private var isSyncMoving = false
    /// 钉住状态右上角图钉角标
    private var pinBadgeView: NSView?
    /// 上一帧窗口位置（用于联动面板计算增量）
    private var lastWindowOrigin: CGPoint = .zero
    /// 上次拖拽联动通知时间（节流用）
    private var lastDragNotifyTime: CFTimeInterval = 0

    /// FocusByTime 进度环图层
    private var progressRingLayer: CAShapeLayer?
    /// 进度环背景轨道图层
    private var progressTrackLayer: CAShapeLayer?

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

    /// 渐变覆盖层（柔和立体感）
    private let gradientOverlay: NSView = {
        let view = NSView()
        view.wantsLayer = true
        let gradient = CAGradientLayer()
        gradient.colors = [
            NSColor.white.withAlphaComponent(0.12).cgColor,
            NSColor.white.withAlphaComponent(0.04).cgColor,
            NSColor.clear.cgColor,
            NSColor.black.withAlphaComponent(0.03).cgColor,
        ]
        gradient.locations = [0.0, 0.35, 0.65, 1.0]
        gradient.startPoint = CGPoint(x: 0.3, y: 1.0)
        gradient.endPoint = CGPoint(x: 0.7, y: 0.0)
        view.layer = gradient
        return view
    }()

    /// 品牌 Logo 图标
    private let iconView: NSImageView = {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyDown
        imageView.wantsLayer = true
        return imageView
    }()

    /// 角标视图（圆形红底白字，与 AI 面板角标风格一致）
    private let badgeLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 9, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.drawsBackground = false
        label.isBezeled = false
        label.isEditable = false
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor.systemRed.cgColor
        label.layer?.cornerRadius = 7
        label.layer?.masksToBounds = true
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
        if let area = trackingArea {
            removeTrackingArea(area)
        }
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 视图设置

    private func setupView() {
        wantsLayer = true
        let size = CGFloat(Constants.Ball.defaultSize)

        // 确保视图自身图层透明（避免方形背景）
        layer?.backgroundColor = NSColor.clear.cgColor

        // 外层投影光晕（使用主题 accent 色发光）
        let accentColor = ConfigStore.shared.preferences.appTheme.colors.nsAccent
        layer?.shadowColor = accentColor.withAlphaComponent(0.4).cgColor
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -1.5)
        layer?.shadowOpacity = 0.4
        // 圆形阴影路径（避免方框阴影）
        layer?.shadowPath = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: size, height: size), transform: nil)

        // 毛玻璃背景
        visualEffectView.frame = NSRect(x: 0, y: 0, width: size, height: size)
        addSubview(visualEffectView)

        // 渐变覆盖层
        gradientOverlay.frame = NSRect(x: 0, y: 0, width: size, height: size)
        gradientOverlay.layer?.cornerRadius = size / 2
        gradientOverlay.layer?.masksToBounds = true
        addSubview(gradientOverlay)

        // 品牌 Logo 图标（居中，尺寸按比例缩放）
        let iconSize = size * 0.7
        let colors = currentGradientColors()
        iconView.image = createBrandLogo(size: iconSize, gradientColors: colors)
        iconView.frame = NSRect(
            x: (size - iconSize) / 2,
            y: (size - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        // 圆形裁剪（去除方框）
        iconView.layer?.cornerRadius = iconSize / 2
        iconView.layer?.masksToBounds = true
        addSubview(iconView)

        // 角标（右上角偏外，圆形）
        let badgeSize: CGFloat = 14
        badgeLabel.frame = NSRect(x: size - badgeSize + 3, y: size - badgeSize + 3, width: badgeSize, height: badgeSize)
        badgeLabel.layer?.cornerRadius = 7
        addSubview(badgeLabel)

        // 添加鼠标追踪区域
        updateTrackingArea()

        // 启动呼吸脉搏动画
        startBreathingAnimation()

        // 设置钉住状态图钉角标（初始隐藏）
        setupPinBadge()

        // 设置 FocusByTime 进度环（初始隐藏）
        setupProgressRing(size: size)
    }

    // MARK: - 布局更新

    /// 当窗口大小变化时更新子视图布局
    func updateLayout(size: CGFloat) {
        visualEffectView.frame = NSRect(x: 0, y: 0, width: size, height: size)
        visualEffectView.layer?.cornerRadius = size / 2

        gradientOverlay.frame = NSRect(x: 0, y: 0, width: size, height: size)
        gradientOverlay.layer?.cornerRadius = size / 2

        // 图标按比例缩放 + 圆形裁剪 + 重绘
        let iconSize = size * 0.7
        iconView.frame = NSRect(
            x: (size - iconSize) / 2,
            y: (size - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        iconView.layer?.cornerRadius = iconSize / 2
        iconView.layer?.masksToBounds = true
        let colors = currentGradientColors()
        iconView.image = createBrandLogo(size: iconSize, gradientColors: colors)

        let bSize: CGFloat = 14
        badgeLabel.frame = NSRect(x: size - bSize + 3, y: size - bSize + 3, width: bSize, height: bSize)

        // 同步更新圆形阴影路径
        layer?.shadowPath = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: size, height: size), transform: nil)

        // 同步更新进度环尺寸
        updateProgressRingSize(size: size)

        // 同步更新钉住角标位置（右上角）
        if let badge = pinBadgeView {
            let badgeSize = badge.frame.width
            badge.frame = NSRect(
                x: size - badgeSize + 2,
                y: size - badgeSize + 2,
                width: badgeSize,
                height: badgeSize
            )
        }

        needsDisplay = true
    }

    // MARK: - 呼吸脉搏动画

    /// 启动 idle 状态下的呼吸光晕动画（双属性联动：shadowOpacity + shadowRadius）
    private func startBreathingAnimation() {
        guard let layer = layer else { return }
        layer.removeAnimation(forKey: "breathingAnimation")

        let opacityAnim = CABasicAnimation(keyPath: "shadowOpacity")
        opacityAnim.fromValue = 0.35
        opacityAnim.toValue = 0.12

        let radiusAnim = CABasicAnimation(keyPath: "shadowRadius")
        radiusAnim.fromValue = 10.0
        radiusAnim.toValue = 5.0

        let group = CAAnimationGroup()
        group.animations = [opacityAnim, radiusAnim]
        group.duration = 2.5
        group.autoreverses = true
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(group, forKey: "breathingAnimation")
    }

    /// 停止呼吸动画
    private func stopBreathingAnimation() {
        layer?.removeAnimation(forKey: "breathingAnimation")
    }

    // MARK: - 钉住状态图钉角标

    /// 创建右上角图钉角标（红底白色 pin.fill 图标，初始隐藏）
    private func setupPinBadge() {
        let badgeSize: CGFloat = 16
        let ballSize = CGFloat(Constants.Ball.defaultSize)

        let badge = NSView(frame: NSRect(
            x: ballSize - badgeSize + 2,
            y: ballSize - badgeSize + 2,
            width: badgeSize,
            height: badgeSize
        ))
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor.systemRed.cgColor
        badge.layer?.cornerRadius = badgeSize / 2
        badge.layer?.borderWidth = 1.5
        badge.layer?.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        badge.isHidden = true

        // 白色 pin.fill 图标
        let iconSize: CGFloat = 8
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .bold)
        if let pinSymbol = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig) {
            let imageView = NSImageView(frame: NSRect(
                x: (badgeSize - pinSymbol.size.width) / 2,
                y: (badgeSize - pinSymbol.size.height) / 2,
                width: pinSymbol.size.width,
                height: pinSymbol.size.height
            ))
            imageView.image = pinSymbol
            imageView.contentTintColor = .white
            badge.addSubview(imageView)
        }

        addSubview(badge)
        pinBadgeView = badge
    }

    /// 切换钉住角标的显示/隐藏
    private func updatePinBadge(isPinned: Bool) {
        pinBadgeView?.isHidden = !isPinned
    }

    // MARK: - FocusByTime 进度环

    /// 创建进度环图层（弧形，从顶部 12 点钟方向顺时针）
    private func setupProgressRing(size: CGFloat) {
        let center = CGPoint(x: size / 2, y: size / 2)
        let radius = size / 2 - 2  // 距离边缘 2px
        let lineWidth: CGFloat = 2.0
        let startAngle = CGFloat.pi / 2        // 12 点钟（macOS 坐标系）
        let endAngle = startAngle + CGFloat.pi * 2

        let ringPath = CGMutablePath()
        ringPath.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)

        // 背景轨道（半透明白色）
        let track = CAShapeLayer()
        track.path = ringPath
        track.fillColor = nil
        track.strokeColor = NSColor.white.withAlphaComponent(0.10).cgColor
        track.lineWidth = lineWidth
        track.isHidden = true
        layer?.addSublayer(track)
        progressTrackLayer = track

        // 前景进度（accent 色）
        let ring = CAShapeLayer()
        ring.path = ringPath
        ring.fillColor = nil
        ring.strokeColor = ConfigStore.shared.preferences.appTheme.colors.nsAccent.cgColor
        ring.lineWidth = lineWidth
        ring.lineCap = .round
        ring.strokeStart = 0
        ring.strokeEnd = 0
        ring.isHidden = true
        layer?.addSublayer(ring)
        progressRingLayer = ring
    }

    /// 更新进度环 + 悬浮球整体视觉状态（由通知触发）
    private func updateProgressRing() {
        let timer = FocusTimerService.shared
        let isActive = timer.status != .idle
        let accentColor = ConfigStore.shared.preferences.appTheme.colors.nsAccent

        progressTrackLayer?.isHidden = !isActive
        progressRingLayer?.isHidden = !isActive

        if isActive {
            // 进度值
            progressRingLayer?.strokeEnd = timer.progress

            // 颜色：工作=accent，休息=绿色
            let phaseColor: NSColor = timer.phase == .work ? accentColor : .systemGreen
            progressRingLayer?.strokeColor = phaseColor.cgColor

            // 进度环加粗（更醒目）
            progressTrackLayer?.lineWidth = 2.5
            progressRingLayer?.lineWidth = 2.5

            // 悬浮球光晕颜色跟随阶段（工作=accent，休息=绿色）
            layer?.shadowColor = phaseColor.withAlphaComponent(0.7).cgColor
            layer?.shadowRadius = 10
            layer?.shadowOpacity = 0.5
        } else {
            // idle 状态：恢复默认 accent 光晕
            progressTrackLayer?.lineWidth = 2.0
            progressRingLayer?.lineWidth = 2.0
            layer?.shadowColor = accentColor.withAlphaComponent(0.4).cgColor
            layer?.shadowRadius = 10
            layer?.shadowOpacity = 0.4
        }
    }

    /// 更新进度环尺寸（ball size 变化时调用）
    private func updateProgressRingSize(size: CGFloat) {
        let center = CGPoint(x: size / 2, y: size / 2)
        let radius = size / 2 - 2
        let startAngle = CGFloat.pi / 2
        let endAngle = startAngle + CGFloat.pi * 2

        let ringPath = CGMutablePath()
        ringPath.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)

        progressTrackLayer?.path = ringPath
        progressRingLayer?.path = ringPath
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
        // 监听面板钉住状态变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelPinStateChanged(_:)),
            name: Constants.Notifications.panelPinStateChanged,
            object: nil
        )
        // 监听面板拖动，联动移动浮球
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePanelDragMoved(_:)),
            name: Constants.Notifications.panelDragMoved,
            object: nil
        )
        // 悬浮球窗口被完全遮挡时暂停呼吸动画，节省 GPU
        // 注意：不能用 NSApplication.didResignActive，因为本 App 的窗口都是 nonactivating
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowOcclusionStateChanged),
            name: NSWindow.didChangeOcclusionStateNotification,
            object: nil
        )
        // FocusByTime 计时器状态变化 → 更新进度环
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFocusTimerChanged),
            name: Constants.Notifications.focusTimerChanged,
            object: nil
        )
        // AI 会话状态变化 → 更新角标
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(coderBridgeSessionsDidChange),
            name: Constants.Notifications.coderBridgeSessionChanged,
            object: nil
        )
    }

    @objc private func handleFocusTimerChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.updateProgressRing()
        }
    }

    @objc private func windowOcclusionStateChanged() {
        guard let window = window else { return }
        if window.occlusionState.contains(.visible) {
            // 窗口可见：恢复呼吸动画
            if layer?.animation(forKey: "breathingAnimation") == nil {
                startBreathingAnimation()
            }
        } else {
            // 窗口完全被遮挡：暂停呼吸动画
            layer?.removeAnimation(forKey: "breathingAnimation")
        }
    }

    @objc private func handlePanelDragMoved(_ notification: Notification) {
        guard isPanelPinned, !isSyncMoving else { return }
        guard let deltaX = notification.userInfo?["deltaX"] as? CGFloat,
              let deltaY = notification.userInfo?["deltaY"] as? CGFloat else { return }
        guard let window = window else { return }
        isSyncMoving = true
        var newOrigin = window.frame.origin
        newOrigin.x += deltaX
        newOrigin.y += deltaY
        window.setFrameOrigin(newOrigin)
        isSyncMoving = false
    }

    @objc private func panelPinStateChanged(_ notification: Notification) {
        isPanelPinned = notification.userInfo?["isPinned"] as? Bool ?? false
        updatePinBadge(isPinned: isPanelPinned)
        updateAIBadge()
    }

    @objc private func coderBridgeSessionsDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.updateAIBadge()
        }
    }

    // MARK: - 角标

    /// 更新 AI 消息数角标（非固定模式下显示 actionableCount）
    private func updateAIBadge() {
        guard !isPanelPinned else {
            badgeLabel.isHidden = true
            return
        }
        let count = CoderBridgeService.shared.actionableCount
        if count > 0 {
            badgeLabel.stringValue = "\(count)"
            badgeLabel.isHidden = false
        } else {
            badgeLabel.isHidden = true
        }
    }

    // MARK: - 品牌 Logo 绘制

    /// 程序化绘制品牌 Logo：立体球形背景 + 上方白色图钉 + 下方白色 FC 文字
    /// - Parameter size: Logo 尺寸（正方形边长）
    /// - Returns: 绘制好的品牌 Logo 图片
    /// 获取当前悬浮球颜色风格的渐变色（从主题 accent 派生）
    private func currentGradientColors() -> (light: NSColor, medium: NSColor, dark: NSColor) {
        return ConfigStore.shared.preferences.appTheme.ballGradientColors
    }

    /// 刷新悬浮球颜色（外部调用，偏好设置变化时）
    /// - Parameter gradientColors: 直接传入渐变色，避免 @Published willSet 时序问题
    func updateColorStyle(gradientColors: (light: NSColor, medium: NSColor, dark: NSColor)? = nil) {
        // 图标尺寸从当前 iconView frame 取（跟随 ball size 缩放）
        let size = iconView.frame.width > 0 ? iconView.frame.width : CGFloat(Constants.Ball.defaultSize) * 0.7
        let colors = gradientColors ?? currentGradientColors()
        iconView.image = createBrandLogo(size: size, gradientColors: colors)
        // 同步更新光晕颜色（跟随主题 accent）
        let accentColor = ConfigStore.shared.preferences.appTheme.colors.nsAccent
        layer?.shadowColor = accentColor.withAlphaComponent(0.4).cgColor
    }

    /// 静态版本：供外部（如 SwiftUI 侧边栏）调用生成品牌 Logo
    static func brandLogo(size: CGFloat, gradientColors: (light: NSColor, medium: NSColor, dark: NSColor)) -> NSImage {
        return createBrandLogoImage(size: size, gradientColors: gradientColors)
    }

    private func createBrandLogo(size: CGFloat, gradientColors: (light: NSColor, medium: NSColor, dark: NSColor)) -> NSImage {
        return Self.createBrandLogoImage(size: size, gradientColors: gradientColors)
    }

    private static func createBrandLogoImage(size: CGFloat, gradientColors: (light: NSColor, medium: NSColor, dark: NSColor)) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        let circleRect = NSRect(x: 0, y: 0, width: size, height: size)
        let circlePath = NSBezierPath(ovalIn: circleRect)
        let center = CGPoint(x: size / 2, y: size / 2)

        // 1. 径向渐变背景（从中心亮到边缘暗，更立体）
        let bgGradient = NSGradient(colorsAndLocations:
            (gradientColors.light, 0.0),
            (gradientColors.medium, 0.5),
            (gradientColors.dark, 1.0)
        )
        bgGradient?.draw(in: circlePath, relativeCenterPosition: NSPoint(x: -0.15, y: 0.2))

        // 2. 球形高光：左上方椭圆高光（模拟 3D 球体反射）
        NSGraphicsContext.saveGraphicsState()
        circlePath.addClip()
        let highlightRect = NSRect(x: size * 0.08, y: size * 0.45, width: size * 0.55, height: size * 0.50)
        let highlightPath = NSBezierPath(ovalIn: highlightRect)
        let highlightGradient = NSGradient(colorsAndLocations:
            (NSColor.white.withAlphaComponent(0.22), 0.0),
            (NSColor.white.withAlphaComponent(0.06), 0.6),
            (NSColor.clear, 1.0)
        )
        highlightGradient?.draw(in: highlightPath, angle: 90)
        NSGraphicsContext.restoreGraphicsState()

        // 3. 底部暗区（增强球形立体感）
        NSGraphicsContext.saveGraphicsState()
        circlePath.addClip()
        let shadowRect = NSRect(x: size * 0.1, y: -size * 0.15, width: size * 0.8, height: size * 0.45)
        let shadowPath = NSBezierPath(ovalIn: shadowRect)
        let shadowGradient = NSGradient(colorsAndLocations:
            (NSColor.black.withAlphaComponent(0.12), 0.0),
            (NSColor.clear, 1.0)
        )
        shadowGradient?.draw(in: shadowPath, angle: 90)
        NSGraphicsContext.restoreGraphicsState()

        // 4. 内边缘光（薄白色描边增强质感）
        let innerGlow = NSBezierPath(ovalIn: NSRect(x: 0.5, y: 0.5, width: size - 1, height: size - 1))
        NSColor.white.withAlphaComponent(0.15).setStroke()
        innerGlow.lineWidth = 0.5
        innerGlow.stroke()

        // 5. 禅圆 Ensō（一笔未闭合弧线，起笔墨滴 + 粗→细渐变 + 收笔散点）
        NSGraphicsContext.saveGraphicsState()
        circlePath.addClip()

        let ensoRadius = size * 0.30          // 禅圆半径
        let segments = 28                      // 分段数（越多越平滑）
        let arcDegrees: CGFloat = 300          // 弧线覆盖角度（留 60° 缺口）
        let startAngle: CGFloat = 120          // 起笔位置（约 4 点钟方向）
        let maxWidth = size * 0.09             // 起笔最粗
        let minWidth = size * 0.02             // 收笔最细

        let startRad = startAngle * .pi / 180
        let endRad = (startAngle + arcDegrees) * .pi / 180
        let arcPerSegment = arcDegrees / CGFloat(segments)

        // 5a. 弧线主体（分段绘制，线宽粗→细）
        for i in 0..<segments {
            let t = CGFloat(i) / CGFloat(segments)
            let angle0 = startAngle + arcPerSegment * CGFloat(i)
            let angle1 = startAngle + arcPerSegment * CGFloat(i + 1)

            let rad0 = angle0 * .pi / 180
            let rad1 = angle1 * .pi / 180

            let seg = NSBezierPath()
            seg.move(to: NSPoint(
                x: center.x + ensoRadius * cos(rad0),
                y: center.y + ensoRadius * sin(rad0)
            ))
            seg.line(to: NSPoint(
                x: center.x + ensoRadius * cos(rad1),
                y: center.y + ensoRadius * sin(rad1)
            ))

            let easedT = 1.0 - pow(1.0 - t, 2.0)
            let lineWidth = maxWidth - (maxWidth - minWidth) * easedT
            let alpha = 0.88 - 0.15 * easedT
            NSColor.white.withAlphaComponent(alpha).setStroke()

            seg.lineWidth = lineWidth
            seg.lineCapStyle = .round
            seg.stroke()
        }

        // 5b. 起笔墨滴（画在弧线之上，明显大于笔触宽度）
        let inkDropCenter = NSPoint(
            x: center.x + ensoRadius * cos(startRad),
            y: center.y + ensoRadius * sin(startRad)
        )
        let inkDropRadius = size * 0.07       // 绝对尺寸，35px 球 → ~1.7px 半径 = 3.4px 直径
        let inkDropPath = NSBezierPath(ovalIn: NSRect(
            x: inkDropCenter.x - inkDropRadius,
            y: inkDropCenter.y - inkDropRadius,
            width: inkDropRadius * 2,
            height: inkDropRadius * 2
        ))
        NSColor.white.withAlphaComponent(0.92).setFill()
        inkDropPath.fill()

        // 5c. 收笔渐隐散点（沿弧线延伸，用绝对尺寸确保可见）
        let tailAngles: [CGFloat] = [5.0, 13.0, 22.0]     // 角度偏移（间距拉大）
        let tailRadii: [CGFloat] = [0.042, 0.030, 0.020]  // 圆点半径（相对 size）
        let tailAlphas: [CGFloat] = [0.65, 0.42, 0.22]

        for j in 0..<tailAngles.count {
            let dotAngle = (startAngle + arcDegrees + tailAngles[j]) * .pi / 180
            let dotCenter = NSPoint(
                x: center.x + ensoRadius * cos(dotAngle),
                y: center.y + ensoRadius * sin(dotAngle)
            )
            let dotR = size * tailRadii[j]
            let dotPath = NSBezierPath(ovalIn: NSRect(
                x: dotCenter.x - dotR,
                y: dotCenter.y - dotR,
                width: dotR * 2,
                height: dotR * 2
            ))
            NSColor.white.withAlphaComponent(tailAlphas[j]).setFill()
            dotPath.fill()
        }

        NSGraphicsContext.restoreGraphicsState()

        image.unlockFocus()
        return image
    }

    // MARK: - 鼠标事件：右键菜单

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()

        let kanbanItem = NSMenuItem(title: "打开主看板", action: #selector(contextMenuOpenKanban), keyEquivalent: "")
        kanbanItem.target = self
        menu.addItem(kanbanItem)

        let toggleItem = NSMenuItem(title: "显示/隐藏悬浮球", action: #selector(contextMenuToggleBall), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出 Focus Copilot", action: #selector(contextMenuQuit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func contextMenuOpenKanban() {
        NotificationCenter.default.post(
            name: Constants.Notifications.ballOpenMainKanban,
            object: nil
        )
    }

    @objc private func contextMenuToggleBall() {
        NotificationCenter.default.post(
            name: Constants.Notifications.ballToggle,
            object: nil
        )
    }

    @objc private func contextMenuQuit() {
        let alert = NSAlert()
        alert.messageText = "退出 Focus Copilot"
        alert.informativeText = "确定要退出应用吗？"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "退出")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - 鼠标事件：hover

    override func mouseEntered(with event: NSEvent) {
        // 面板钉住时不响应 hover（不触发动画、计时器、面板弹出）
        guard !isPanelPinned else { return }
        // 如果正在拖拽中，不触发 hover
        guard !isDragging else { return }

        // 如果贴边半隐藏，先滑出
        if isHalfHidden {
            slideOut()
        }

        // hover 缩放反馈 + 光晕增强
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.layer?.setAffineTransform(CGAffineTransform(scaleX: 1.06, y: 1.06))
            self.layer?.shadowOpacity = 0.50
            self.layer?.shadowRadius = 14
        }

        // 鼠标进入时立即预热窗口数据（后续 show 不再等数据刷新）
        AppMonitor.shared.startWindowRefresh()

        // 启动 hover 计时器
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: Constants.Ball.hoverDelay, repeats: false) { [weak self] _ in
            self?.triggerQuickPanel()
        }
    }

    override func mouseExited(with event: NSEvent) {
        // 取消 hover 计时器
        hoverTimer?.invalidate()
        hoverTimer = nil

        // 恢复 hover 缩放 + 光晕
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.layer?.setAffineTransform(.identity)
            self.layer?.shadowOpacity = 0.4
            self.layer?.shadowRadius = 10
        }

        // 通知快捷面板鼠标已离开悬浮球
        NotificationCenter.default.post(
            name: Constants.Notifications.ballMouseExited,
            object: nil
        )
    }

    /// 触发快捷面板显示
    private func triggerQuickPanel() {
        guard let window = window else { return }
        NotificationCenter.default.post(
            name: Constants.Notifications.ballShowQuickPanel,
            object: nil,
            userInfo: ["ballFrame": NSValue(rect: window.frame)]
        )
    }

    // MARK: - 鼠标事件：拖拽 + 点击

    override func mouseDown(with event: NSEvent) {
        isDragging = false
        dragStartPoint = NSEvent.mouseLocation
        windowStartOrigin = window?.frame.origin ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window else { return }

        // 拖拽开始后取消 hover 计时器
        if !isDragging {
            isDragging = true
            hoverTimer?.invalidate()
            hoverTimer = nil
            // 面板钉住时不关闭面板（联动拖动）
            if !isPanelPinned {
                NotificationCenter.default.post(
                    name: Constants.Notifications.ballDragStarted,
                    object: nil
                )
            }
        }

        let currentPoint = NSEvent.mouseLocation
        // 偏移量方式：始终基于 mouseDown 时的起始位置计算，避免边缘夹紧导致漂移
        var newOrigin = CGPoint(
            x: windowStartOrigin.x + (currentPoint.x - dragStartPoint.x),
            y: windowStartOrigin.y + (currentPoint.y - dragStartPoint.y)
        )

        // 限制在当前屏幕可见区域
        if let screen = window.screen ?? NSScreen.main {
            let visibleFrame = screen.visibleFrame
            let ballSize = window.frame.size
            newOrigin.x = max(visibleFrame.minX, min(newOrigin.x, visibleFrame.maxX - ballSize.width))
            newOrigin.y = max(visibleFrame.minY, min(newOrigin.y, visibleFrame.maxY - ballSize.height))
        }

        // 计算增量用于面板联动
        let oldOrigin = window.frame.origin
        window.setFrameOrigin(newOrigin)
        let deltaX = newOrigin.x - oldOrigin.x
        let deltaY = newOrigin.y - oldOrigin.y

        // 面板钉住时，同步拖动面板（绝对定位，避免 delta 累积漂移）
        if isPanelPinned {
            let now = CACurrentMediaTime()
            if now - lastDragNotifyTime >= 0.016 {
                NotificationCenter.default.post(
                    name: Constants.Notifications.ballDragMoved,
                    object: nil,
                    userInfo: ["ballFrame": NSValue(rect: window.frame)]
                )
                lastDragNotifyTime = now
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            // 拖拽结束前发送最后一次联动通知，确保面板位置完全同步
            if isPanelPinned, let window = window {
                let oldOrigin = window.frame.origin
                // 计算 snapToEdge 前的最后增量（补偿节流丢失的末帧）
                let currentPoint = NSEvent.mouseLocation
                let newOrigin = CGPoint(
                    x: windowStartOrigin.x + (currentPoint.x - dragStartPoint.x),
                    y: windowStartOrigin.y + (currentPoint.y - dragStartPoint.y)
                )
                let deltaX = newOrigin.x - oldOrigin.x
                let deltaY = newOrigin.y - oldOrigin.y
                if abs(deltaX) > 0.01 || abs(deltaY) > 0.01 {
                    NotificationCenter.default.post(
                        name: Constants.Notifications.ballDragMoved,
                        object: nil,
                        userInfo: ["deltaX": deltaX, "deltaY": deltaY]
                    )
                }
            }
            // 拖拽结束：吸附到最近边缘 + 检测贴边半隐藏
            isDragging = false
            snapToEdge()
            return
        }

        // 直接触发单击（不再支持双击隐藏，悬浮球始终可见）
        handleSingleClick()
    }

    // MARK: - 点击处理

    /// 单击：切换快捷面板钉住状态
    private func handleSingleClick() {
        // 取消 hoverTimer，防止 hover 300ms 后重复触发面板
        hoverTimer?.invalidate()
        hoverTimer = nil
        // 发送 toggleQuickPanel 通知，由 AppDelegate 处理钉住/取消钉住逻辑
        guard let window = window else { return }
        NotificationCenter.default.post(
            name: Constants.Notifications.ballToggleQuickPanel,
            object: nil,
            userInfo: ["ballFrame": NSValue(rect: window.frame)]
        )
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

    /// 检查是否需要贴边半隐藏（面板钉住时不触发半隐藏）
    private func checkHalfHide(edge: ScreenEdge) {
        guard !isPanelPinned else { return }
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
        ConfigStore.shared.saveBallPosition()
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
