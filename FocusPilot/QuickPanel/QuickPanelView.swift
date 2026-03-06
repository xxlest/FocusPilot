import AppKit

// MARK: - 快捷面板 Tab 枚举

enum QuickPanelTab: String {
    case running    = "running"   // 活跃
    case favorites  = "favorites" // 关注
}

// MARK: - 快捷面板内容视图
// 活跃/关注两个 Tab，App 列表 + 内嵌窗口列表
// 支持实时更新、钉住模式、窗口重命名、窗口行高亮+前置

final class QuickPanelView: NSView {

    // MARK: - 状态（跨文件 extension 需访问，使用 internal）

    /// 当前 Tab 页（setupView 中从 ConfigStore 恢复）
    var currentTab: QuickPanelTab = .running

    /// 当前高亮的窗口行 ID（同一时间只有一个）
    var highlightedWindowID: CGWindowID?

    /// 多窗口 App 折叠状态（按 bundleID 跟踪）
    var collapsedApps: Set<String> = []

    /// 上次渲染时的结构快照（用于判断是否需要全量重建）
    private var lastStructuralKey: String = ""

    /// 窗口行标题 label 引用（用于内容级更新）
    var windowTitleLabels: [CGWindowID: NSTextField] = [:]
    /// 窗口行视图引用（用于高亮更新）
    var windowRowViewMap: [CGWindowID: HoverableRowView] = [:]

    /// 鼠标追踪区域
    private var trackingArea: NSTrackingArea?

    // MARK: - 子视图

    /// 顶部栏（带微妙背景底色，与列表区形成层次）
    private let topBar: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = ConfigStore.shared.currentThemeColors.nsTextPrimary.withAlphaComponent(0.04).cgColor
        return view
    }()

    /// 顶部分割线（手动颜色，确保主题下可见）
    private let topSeparator: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = ConfigStore.shared.currentThemeColors.nsSeparator.cgColor
        return view
    }()

    /// Tab 按钮之间的竖线分隔符
    private let tabSeparator: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = ConfigStore.shared.currentThemeColors.nsSeparator.cgColor
        return view
    }()

    /// 打开主界面按钮（顶部左侧）
    private lazy var openKanbanButton: NSButton = {
        let btn = NSButton()
        btn.bezelStyle = .recessed
        btn.isBordered = false
        btn.image = Self.cachedSymbol(name: "slider.horizontal.3", size: 11, weight: .medium)
        btn.contentTintColor = ConfigStore.shared.currentThemeColors.nsTextSecondary
        btn.toolTip = "打开主界面"
        btn.target = self
        btn.action = #selector(openMainKanban)
        return btn
    }()

    /// 活跃 Tab 按钮
    private lazy var runningTabButton: NSButton = {
        let btn = NSButton(title: "活跃", target: self, action: #selector(switchToRunningTab))
        btn.bezelStyle = .recessed
        btn.isBordered = false
        btn.font = .systemFont(ofSize: 11)
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 4
        btn.contentTintColor = ConfigStore.shared.currentThemeColors.nsTextSecondary
        return btn
    }()

    /// 关注 Tab 按钮
    private lazy var favoritesTabButton: NSButton = {
        let btn = NSButton(title: "关注", target: self, action: #selector(switchToFavoritesTab))
        btn.bezelStyle = .recessed
        btn.isBordered = false
        btn.font = .systemFont(ofSize: 11)
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 4
        btn.contentTintColor = ConfigStore.shared.currentThemeColors.nsTextSecondary
        return btn
    }()

    /// Tab 选中下划线指示条（活跃）
    private let runningTabIndicator: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 1
        return view
    }()

    /// Tab 选中下划线指示条（关注）
    private let favoritesTabIndicator: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 1
        return view
    }()

    // MARK: - FocusByTime 底部计时器栏

    /// 底部分割线
    private let bottomSeparator: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = ConfigStore.shared.currentThemeColors.nsSeparator.cgColor
        return view
    }()

    /// 底部计时器栏容器
    private let timerBar: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = ConfigStore.shared.currentThemeColors.nsTextPrimary.withAlphaComponent(0.03).cgColor
        return view
    }()

    /// 阶段标签（"工作中" / "休息中" / 时钟图标）
    private let timerPhaseLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = ConfigStore.shared.currentThemeColors.nsTextSecondary
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        return label
    }()

    /// 时间显示 "MM:SS"
    private let timerTimeLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        label.textColor = ConfigStore.shared.currentThemeColors.nsTextPrimary
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        return label
    }()

    /// 进度条背景
    private let timerProgressBg: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 2
        view.layer?.backgroundColor = ConfigStore.shared.currentThemeColors.nsTextPrimary.withAlphaComponent(0.08).cgColor
        return view
    }()

    /// 进度条填充
    private let timerProgressFill: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 2
        return view
    }()

    /// 进度条填充宽度约束
    private var timerProgressFillWidth: NSLayoutConstraint?

    /// idle 模式时长摘要标签（"工作 25min / 休息 5min"）
    private let timerIdleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = ConfigStore.shared.currentThemeColors.nsTextSecondary
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        return label
    }()

    /// 编辑+开始按钮（弹出编辑对话框，可直接开始）
    private lazy var timerEditBtn: NSButton = {
        let btn = NSButton()
        btn.bezelStyle = .recessed
        btn.isBordered = false
        btn.image = Self.cachedSymbol(name: "play.circle", size: 14, weight: .medium)
        btn.contentTintColor = ConfigStore.shared.currentThemeColors.nsAccent
        btn.target = self
        btn.action = #selector(timerEditTapped)
        btn.toolTip = "设置并开始"
        return btn
    }()

    /// 开始/暂停按钮
    private lazy var timerActionBtn: NSButton = {
        let btn = NSButton()
        btn.bezelStyle = .recessed
        btn.isBordered = false
        btn.image = Self.cachedSymbol(name: "play.fill", size: 12, weight: .medium)
        btn.contentTintColor = ConfigStore.shared.currentThemeColors.nsAccent
        btn.target = self
        btn.action = #selector(timerActionTapped)
        btn.toolTip = "开始"
        return btn
    }()

    /// 重置按钮
    private lazy var timerResetBtn: NSButton = {
        let btn = NSButton()
        btn.bezelStyle = .recessed
        btn.isBordered = false
        btn.image = Self.cachedSymbol(name: "stop.fill", size: 10, weight: .medium)
        btn.contentTintColor = ConfigStore.shared.currentThemeColors.nsTextTertiary
        btn.target = self
        btn.action = #selector(timerResetTapped)
        btn.toolTip = "重置"
        btn.isHidden = true
        return btn
    }()

    /// 滚动视图（包含内容区域）
    private let scrollView: NSScrollView = {
        let sv = NSScrollView()
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = false
        sv.autohidesScrollers = true
        sv.borderType = .noBorder
        sv.drawsBackground = false
        sv.scrollerStyle = .overlay
        return sv
    }()

    /// 内容列表容器
    let contentStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.wantsLayer = true
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)
        return stack
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
        if let area = trackingArea {
            removeTrackingArea(area)
        }
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 视图设置

    private func setupView() {
        wantsLayer = true

        // 滚动视图（使用翻转的 ClipView 确保内容从顶部开始显示）
        let clipView = FlippedClipView()
        clipView.drawsBackground = false
        clipView.documentView = contentStack
        scrollView.contentView = clipView

        // 顶部栏
        addSubview(topBar)
        addSubview(topSeparator)
        topBar.addSubview(openKanbanButton)
        topBar.addSubview(runningTabButton)
        topBar.addSubview(tabSeparator)
        topBar.addSubview(favoritesTabButton)
        topBar.addSubview(runningTabIndicator)
        topBar.addSubview(favoritesTabIndicator)

        // 滚动区域
        addSubview(scrollView)

        // 底部计时器栏
        addSubview(bottomSeparator)
        addSubview(timerBar)
        timerBar.addSubview(timerPhaseLabel)
        timerBar.addSubview(timerTimeLabel)
        timerBar.addSubview(timerProgressBg)
        timerProgressBg.addSubview(timerProgressFill)
        timerBar.addSubview(timerIdleLabel)
        timerBar.addSubview(timerEditBtn)
        timerBar.addSubview(timerActionBtn)
        timerBar.addSubview(timerResetBtn)

        // Auto Layout
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topSeparator.translatesAutoresizingMaskIntoConstraints = false
        openKanbanButton.translatesAutoresizingMaskIntoConstraints = false
        runningTabButton.translatesAutoresizingMaskIntoConstraints = false
        tabSeparator.translatesAutoresizingMaskIntoConstraints = false
        favoritesTabButton.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        runningTabIndicator.translatesAutoresizingMaskIntoConstraints = false
        favoritesTabIndicator.translatesAutoresizingMaskIntoConstraints = false
        bottomSeparator.translatesAutoresizingMaskIntoConstraints = false
        timerBar.translatesAutoresizingMaskIntoConstraints = false
        timerPhaseLabel.translatesAutoresizingMaskIntoConstraints = false
        timerTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        timerProgressBg.translatesAutoresizingMaskIntoConstraints = false
        timerProgressFill.translatesAutoresizingMaskIntoConstraints = false
        timerIdleLabel.translatesAutoresizingMaskIntoConstraints = false
        timerEditBtn.translatesAutoresizingMaskIntoConstraints = false
        timerActionBtn.translatesAutoresizingMaskIntoConstraints = false
        timerResetBtn.translatesAutoresizingMaskIntoConstraints = false

        let topBarHeight: CGFloat = 28

        NSLayoutConstraint.activate([
            // 顶部栏
            topBar.topAnchor.constraint(equalTo: topAnchor),
            topBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: topBarHeight),

            // 顶部分割线（全宽，固定 1px 高度）
            topSeparator.leadingAnchor.constraint(equalTo: leadingAnchor),
            topSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
            topSeparator.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            topSeparator.heightAnchor.constraint(equalToConstant: 1),

            // 打开主界面按钮（右侧）
            openKanbanButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -8),
            openKanbanButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            // Tab 按钮（左侧，留出 32px 给悬浮球让位）
            runningTabButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 32),
            runningTabButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            // Tab 竖线分隔符
            tabSeparator.leadingAnchor.constraint(equalTo: runningTabButton.trailingAnchor, constant: 5),
            tabSeparator.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            tabSeparator.widthAnchor.constraint(equalToConstant: 1),
            tabSeparator.heightAnchor.constraint(equalToConstant: 12),

            favoritesTabButton.leadingAnchor.constraint(equalTo: tabSeparator.trailingAnchor, constant: 5),
            favoritesTabButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            // Tab 下划线指示条
            runningTabIndicator.leadingAnchor.constraint(equalTo: runningTabButton.leadingAnchor, constant: 2),
            runningTabIndicator.trailingAnchor.constraint(equalTo: runningTabButton.trailingAnchor, constant: -2),
            runningTabIndicator.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -1),
            runningTabIndicator.heightAnchor.constraint(equalToConstant: 2),

            favoritesTabIndicator.leadingAnchor.constraint(equalTo: favoritesTabButton.leadingAnchor, constant: 2),
            favoritesTabIndicator.trailingAnchor.constraint(equalTo: favoritesTabButton.trailingAnchor, constant: -2),
            favoritesTabIndicator.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -1),
            favoritesTabIndicator.heightAnchor.constraint(equalToConstant: 2),

            // 滚动区域（顶部栏到底部计时器栏之上）
            scrollView.topAnchor.constraint(equalTo: topSeparator.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomSeparator.topAnchor),

            // contentStack 宽度跟随 scrollView
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),

            // 底部分割线
            bottomSeparator.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomSeparator.bottomAnchor.constraint(equalTo: timerBar.topAnchor),
            bottomSeparator.heightAnchor.constraint(equalToConstant: 1),

            // 底部计时器栏（固定 44px 高度）
            timerBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            timerBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            timerBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            timerBar.heightAnchor.constraint(equalToConstant: 44),

            // 开始/暂停按钮（右侧）
            timerActionBtn.trailingAnchor.constraint(equalTo: timerBar.trailingAnchor, constant: -8),
            timerActionBtn.centerYAnchor.constraint(equalTo: timerBar.centerYAnchor),
            timerActionBtn.widthAnchor.constraint(equalToConstant: 24),
            timerActionBtn.heightAnchor.constraint(equalToConstant: 24),

            // 重置按钮（开始按钮左侧）
            timerResetBtn.trailingAnchor.constraint(equalTo: timerActionBtn.leadingAnchor, constant: -2),
            timerResetBtn.centerYAnchor.constraint(equalTo: timerBar.centerYAnchor),
            timerResetBtn.widthAnchor.constraint(equalToConstant: 20),
            timerResetBtn.heightAnchor.constraint(equalToConstant: 20),

            // 阶段标签（左侧）
            timerPhaseLabel.leadingAnchor.constraint(equalTo: timerBar.leadingAnchor, constant: 12),
            timerPhaseLabel.topAnchor.constraint(equalTo: timerBar.topAnchor, constant: 5),

            // 时间显示（阶段标签右侧）
            timerTimeLabel.leadingAnchor.constraint(equalTo: timerPhaseLabel.trailingAnchor, constant: 6),
            timerTimeLabel.centerYAnchor.constraint(equalTo: timerPhaseLabel.centerYAnchor),

            // 进度条（第二行）
            timerProgressBg.leadingAnchor.constraint(equalTo: timerBar.leadingAnchor, constant: 12),
            timerProgressBg.trailingAnchor.constraint(equalTo: timerResetBtn.leadingAnchor, constant: -8),
            timerProgressBg.bottomAnchor.constraint(equalTo: timerBar.bottomAnchor, constant: -8),
            timerProgressBg.heightAnchor.constraint(equalToConstant: 4),

            // 进度条填充
            timerProgressFill.leadingAnchor.constraint(equalTo: timerProgressBg.leadingAnchor),
            timerProgressFill.topAnchor.constraint(equalTo: timerProgressBg.topAnchor),
            timerProgressFill.bottomAnchor.constraint(equalTo: timerProgressBg.bottomAnchor),

            // idle 模式时长摘要标签（居中）
            timerIdleLabel.leadingAnchor.constraint(equalTo: timerBar.leadingAnchor, constant: 12),
            timerIdleLabel.centerYAnchor.constraint(equalTo: timerBar.centerYAnchor),

            // 编辑+开始按钮（右侧，idle 时替代 timerActionBtn 位置）
            timerEditBtn.trailingAnchor.constraint(equalTo: timerBar.trailingAnchor, constant: -8),
            timerEditBtn.centerYAnchor.constraint(equalTo: timerBar.centerYAnchor),
            timerEditBtn.widthAnchor.constraint(equalToConstant: 26),
            timerEditBtn.heightAnchor.constraint(equalToConstant: 26),
        ])

        // 进度条填充宽度约束（初始为 0）
        let fillWidth = timerProgressFill.widthAnchor.constraint(equalToConstant: 0)
        fillWidth.isActive = true
        timerProgressFillWidth = fillWidth

        // 鼠标追踪
        updateTrackingArea()

        // 从 ConfigStore 恢复上次选择的 Tab
        currentTab = QuickPanelTab(rawValue: ConfigStore.shared.lastPanelTab) ?? .running
        updateTabButtonStyles()

        // 初始化计时器 UI
        updateTimerUI()
    }

    // MARK: - 追踪区域（收起逻辑）

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

    override func mouseEntered(with event: NSEvent) {
        // 鼠标进入面板：取消收起计时器
        if let panelWindow = window as? QuickPanelWindow {
            panelWindow.cancelDismissTimer()
        }
    }

    override func mouseExited(with event: NSEvent) {
        // 钉住模式下不触发收起
        if let panelWindow = window as? QuickPanelWindow, panelWindow.isPanelPinned {
            return
        }
        // 自动回缩关闭时不触发收起
        if !ConfigStore.shared.preferences.autoRetractOnHover {
            return
        }
        // 鼠标离开面板：启动 500ms 收起延迟
        if let panelWindow = window as? QuickPanelWindow {
            panelWindow.startDismissTimer()
        }
    }

    // MARK: - 通知监听

    private func setupNotifications() {
        // 窗口列表变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowsDidChange),
            name: AppMonitor.windowsChanged,
            object: nil
        )
        // App 运行状态变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appStatusDidChange),
            name: AppMonitor.appStatusChanged,
            object: nil
        )
        // 辅助功能权限恢复（codesign 后用户重新授权）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilityDidGrant),
            name: Constants.Notifications.accessibilityGranted,
            object: nil
        )
        // FocusByTime 计时器状态变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(focusTimerDidChange),
            name: Constants.Notifications.focusTimerChanged,
            object: nil
        )
        // 工作阶段结束 → 弹对话框提示休息
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWorkCompleted),
            name: Constants.Notifications.focusWorkCompleted,
            object: nil
        )
        // 休息阶段结束 → 弹对话框提示开始工作
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRestCompleted),
            name: Constants.Notifications.focusRestCompleted,
            object: nil
        )
    }

    @objc private func windowsDidChange() {
        reloadData()
    }

    @objc private func appStatusDidChange() {
        reloadData()
    }

    @objc private func accessibilityDidGrant() {
        // 权限恢复：清除 AX 缓存 + 强制全量重建
        WindowService.shared.invalidateAXCache()
        forceReload()
    }

    @objc private func focusTimerDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.updateTimerUI()
        }
    }

    // MARK: - FocusByTime UI 更新

    private func updateTimerUI() {
        let timer = FocusTimerService.shared
        let colors = ConfigStore.shared.currentThemeColors
        let isIdle = timer.status == .idle
        let hasPending = timer.pendingAction != .none

        // pending 状态：idle 但有待处理动作（弹窗被失焦自动关闭）
        if hasPending {
            // 隐藏编辑按钮和常规 idle 控件
            timerIdleLabel.isHidden = true
            timerEditBtn.isHidden = true
            timerProgressBg.isHidden = true
            timerProgressFill.isHidden = true
            timerTimeLabel.isHidden = true
            timerResetBtn.isHidden = false

            // 显示 pending 状态文案和快捷操作按钮
            timerPhaseLabel.isHidden = false
            timerActionBtn.isHidden = false

            switch timer.pendingAction {
            case .startRest:
                timerPhaseLabel.stringValue = "工作完成 · 开始休息"
                timerPhaseLabel.textColor = NSColor.systemGreen
                timerActionBtn.image = Self.cachedSymbol(name: "cup.and.saucer.fill", size: 12, weight: .medium)
                timerActionBtn.contentTintColor = NSColor.systemGreen
                timerActionBtn.toolTip = "开始休息"
                timerBar.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.12).cgColor
                bottomSeparator.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.3).cgColor
            case .startWork:
                timerPhaseLabel.stringValue = "休息结束 · 继续工作"
                timerPhaseLabel.textColor = colors.nsAccent
                timerActionBtn.image = Self.cachedSymbol(name: "play.fill", size: 12, weight: .medium)
                timerActionBtn.contentTintColor = colors.nsAccent
                timerActionBtn.toolTip = "继续工作"
                timerBar.layer?.backgroundColor = colors.nsAccent.withAlphaComponent(0.12).cgColor
                bottomSeparator.layer?.backgroundColor = colors.nsAccent.withAlphaComponent(0.3).cgColor
            case .none:
                break
            }
            return
        }

        // idle 模式：显示时长摘要和编辑+开始按钮
        timerIdleLabel.isHidden = !isIdle
        timerEditBtn.isHidden = !isIdle

        // 运行模式：显示阶段、时间、进度条、暂停/继续按钮
        timerPhaseLabel.isHidden = isIdle
        timerTimeLabel.isHidden = isIdle
        timerProgressBg.isHidden = isIdle
        timerProgressFill.isHidden = isIdle
        timerResetBtn.isHidden = isIdle
        timerActionBtn.isHidden = isIdle

        // 计时器栏大面积颜色变化（工作=accent 底色，休息=绿色底色，idle=透明）
        if isIdle {
            timerBar.layer?.backgroundColor = colors.nsTextPrimary.withAlphaComponent(0.03).cgColor
            bottomSeparator.layer?.backgroundColor = colors.nsSeparator.cgColor
        } else if timer.phase == .work {
            timerBar.layer?.backgroundColor = colors.nsAccent.withAlphaComponent(0.12).cgColor
            bottomSeparator.layer?.backgroundColor = colors.nsAccent.withAlphaComponent(0.3).cgColor
        } else {
            timerBar.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.12).cgColor
            bottomSeparator.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.3).cgColor
        }

        if isIdle {
            // 更新时长摘要
            timerIdleLabel.stringValue = "工作 \(timer.workMinutes)min / 休息 \(timer.restMinutes)min"
        } else {
            // 阶段标签
            timerPhaseLabel.stringValue = timer.phaseLabel
            let phaseColor = timer.phase == .work ? colors.nsAccent : NSColor.systemGreen
            timerPhaseLabel.textColor = phaseColor

            // 时间（大号醒目）
            timerTimeLabel.stringValue = timer.displayTime
            timerTimeLabel.textColor = colors.nsTextPrimary

            // 进度条
            timerProgressFill.layer?.backgroundColor = phaseColor.cgColor
            let progressWidth = timerProgressBg.bounds.width * timer.progress
            timerProgressFillWidth?.constant = max(0, progressWidth)
            timerProgressBg.layoutSubtreeIfNeeded()

            // 暂停/继续按钮
            if timer.status == .running {
                timerActionBtn.image = Self.cachedSymbol(name: "pause.fill", size: 12, weight: .medium)
                timerActionBtn.contentTintColor = colors.nsTextSecondary
                timerActionBtn.toolTip = "暂停"
            } else {
                timerActionBtn.image = Self.cachedSymbol(name: "play.fill", size: 12, weight: .medium)
                timerActionBtn.contentTintColor = colors.nsAccent
                timerActionBtn.toolTip = "继续"
            }
        }
    }

    // MARK: - FocusByTime 对话框

    @objc private func handleWorkCompleted() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let timer = FocusTimerService.shared
            let alert = NSAlert()
            alert.messageText = "🎯 工作完成！"
            alert.informativeText = "已专注 \(timer.workMinutes) 分钟，休息 \(timer.restMinutes) 分钟吧\n休息是为了更高效地专注 💪"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "开始休息")
            alert.addButton(withTitle: "直接结束")

            // 科学休息指南 accessoryView
            let guideItems: [(String, String)] = [
                ("👀", "闭眼 1 分钟，看远处 20 秒"),
                ("🧘", "深呼吸 5 次（吸 4s → 屏 2s → 呼 6s）"),
                ("🚶", "站起来走动，转头耸肩拉伸"),
                ("💧", "喝杯水，离开屏幕看看窗外"),
                ("⛔", "别刷短视频、别看社交消息"),
            ]
            let lineHeight: CGFloat = 20
            let padding: CGFloat = 10
            let titleH: CGFloat = 18
            let containerH = titleH + CGFloat(guideItems.count) * lineHeight + padding * 2 + 4
            let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: containerH))
            container.wantsLayer = true
            container.layer?.backgroundColor = NSColor.textColor.withAlphaComponent(0.04).cgColor
            container.layer?.cornerRadius = 8

            let title = NSTextField(labelWithString: "科学休息指南")
            title.font = .systemFont(ofSize: 11, weight: .semibold)
            title.textColor = .secondaryLabelColor
            title.frame = NSRect(x: padding, y: containerH - padding - titleH, width: 260, height: titleH)
            container.addSubview(title)

            for (i, item) in guideItems.enumerated() {
                let y = containerH - padding - titleH - 4 - CGFloat(i + 1) * lineHeight
                let label = NSTextField(labelWithString: "\(item.0)  \(item.1)")
                label.font = .systemFont(ofSize: 12)
                label.textColor = .labelColor
                label.frame = NSRect(x: padding + 2, y: y, width: 260, height: lineHeight)
                container.addSubview(label)
            }

            alert.accessoryView = container

            // 失焦自动关闭（pendingAction 保留，计时器栏提供快捷操作）
            var resignObserver: NSObjectProtocol?
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil, queue: .main
            ) { _ in
                NSApp.abortModal()
                alert.window.close()
            }

            let result = alert.runModal()

            if let observer = resignObserver {
                NotificationCenter.default.removeObserver(observer)
            }

            if result == .alertFirstButtonReturn {
                timer.startRestPhase()
            } else if result == .alertSecondButtonReturn {
                timer.reset()
            }
            // 其他情况（失焦自动关闭）：pendingAction 保留为 .startRest，计时器栏显示快捷操作
        }
    }

    @objc private func handleRestCompleted() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let timer = FocusTimerService.shared
            let alert = NSAlert()
            alert.messageText = "⚡ 充电完毕"
            alert.informativeText = "准备好下一轮 \(timer.workMinutes) 分钟专注了吗？"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "开始工作")
            alert.addButton(withTitle: "稍后再说")

            // 失焦自动关闭（pendingAction 保留，计时器栏提供快捷操作）
            var resignObserver: NSObjectProtocol?
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil, queue: .main
            ) { _ in
                NSApp.abortModal()
                alert.window.close()
            }

            let result = alert.runModal()

            if let observer = resignObserver {
                NotificationCenter.default.removeObserver(observer)
            }

            if result == .alertFirstButtonReturn {
                timer.start()
            }
            // 其他情况（失焦自动关闭 / 稍后再说）：pendingAction 保留为 .startWork，计时器栏显示快捷操作
        }
    }

    // MARK: - FocusByTime 按钮事件

    @objc private func timerActionTapped() {
        let timer = FocusTimerService.shared

        // 优先处理 pending 动作（弹窗被失焦自动关闭后的快捷操作）
        switch timer.pendingAction {
        case .startRest:
            timer.startRestPhase()
            return
        case .startWork:
            timer.start()
            return
        case .none:
            break
        }

        switch timer.status {
        case .idle:
            break  // idle 时此按钮隐藏，不可达
        case .running:
            timer.pause()
        case .paused:
            timer.resume()
        }
    }

    @objc private func timerResetTapped() {
        let timer = FocusTimerService.shared
        let alert = NSAlert()
        alert.messageText = "停止计时"
        alert.informativeText = "确定要停止当前计时吗？进度将被重置。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "停止")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            timer.reset()
        }
    }

    @objc private func timerEditTapped() {
        let timer = FocusTimerService.shared
        guard timer.status == .idle else { return }

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "设置计时时长"
        alert.informativeText = "建议工作 1~120 分钟，休息 1~60 分钟"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "直接开始")
        alert.addButton(withTitle: "仅保存")
        alert.addButton(withTitle: "取消")

        // 构建 accessory view（输入框 + 推荐方案）
        let presets: [(String, Int, Int)] = [
            ("深度专注", 25, 5),
            ("常规节奏", 35, 7),
            ("轻度脑力", 50, 10),
        ]
        let inputAreaH: CGFloat = 64
        let separatorH: CGFloat = 20
        let presetRowH: CGFloat = 22
        let presetsH = CGFloat(presets.count) * presetRowH
        let totalH = inputAreaH + separatorH + presetsH + 4
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: totalH))

        // --- 输入区域（顶部）---
        let inputBaseY = totalH - inputAreaH

        let workTitleLabel = NSTextField(labelWithString: "工作（分钟）:")
        workTitleLabel.font = .systemFont(ofSize: 12)
        workTitleLabel.frame = NSRect(x: 0, y: inputBaseY + 36, width: 100, height: 20)
        container.addSubview(workTitleLabel)

        let workMinusBtn = NSButton(frame: NSRect(x: 104, y: inputBaseY + 35, width: 24, height: 22))
        workMinusBtn.title = "−"
        workMinusBtn.bezelStyle = .rounded
        workMinusBtn.font = .systemFont(ofSize: 13, weight: .medium)
        container.addSubview(workMinusBtn)

        let workField = NSTextField(string: "\(timer.workMinutes)")
        workField.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        workField.alignment = .center
        workField.frame = NSRect(x: 130, y: inputBaseY + 36, width: 50, height: 22)
        container.addSubview(workField)

        let workPlusBtn = NSButton(frame: NSRect(x: 182, y: inputBaseY + 35, width: 24, height: 22))
        workPlusBtn.title = "+"
        workPlusBtn.bezelStyle = .rounded
        workPlusBtn.font = .systemFont(ofSize: 13, weight: .medium)
        container.addSubview(workPlusBtn)

        let restTitleLabel = NSTextField(labelWithString: "休息（分钟）:")
        restTitleLabel.font = .systemFont(ofSize: 12)
        restTitleLabel.frame = NSRect(x: 0, y: inputBaseY + 6, width: 100, height: 20)
        container.addSubview(restTitleLabel)

        let restMinusBtn = NSButton(frame: NSRect(x: 104, y: inputBaseY + 5, width: 24, height: 22))
        restMinusBtn.title = "−"
        restMinusBtn.bezelStyle = .rounded
        restMinusBtn.font = .systemFont(ofSize: 13, weight: .medium)
        container.addSubview(restMinusBtn)

        let restField = NSTextField(string: "\(timer.restMinutes)")
        restField.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        restField.alignment = .center
        restField.frame = NSRect(x: 130, y: inputBaseY + 6, width: 50, height: 22)
        container.addSubview(restField)

        let restPlusBtn = NSButton(frame: NSRect(x: 182, y: inputBaseY + 5, width: 24, height: 22))
        restPlusBtn.title = "+"
        restPlusBtn.bezelStyle = .rounded
        restPlusBtn.font = .systemFont(ofSize: 13, weight: .medium)
        container.addSubview(restPlusBtn)

        // --- 分隔线 + "推荐方案" 标题 ---
        let sepY = inputBaseY - 2
        let sepLine = NSView(frame: NSRect(x: 0, y: sepY, width: 280, height: 1))
        sepLine.wantsLayer = true
        sepLine.layer?.backgroundColor = NSColor.separatorColor.cgColor
        container.addSubview(sepLine)

        let presetTitle = NSTextField(labelWithString: "推荐方案")
        presetTitle.font = .systemFont(ofSize: 10, weight: .medium)
        presetTitle.textColor = .secondaryLabelColor
        presetTitle.frame = NSRect(x: 0, y: sepY - separatorH + 2, width: 80, height: 16)
        container.addSubview(presetTitle)

        // --- 推荐方案 radio 行 ---
        let helper = TimerEditHelper(workField: workField, restField: restField, workStep: 1, restStep: 1)
        var radioButtons: [NSButton] = []

        let presetBaseY = sepY - separatorH
        for (i, preset) in presets.enumerated() {
            let y = presetBaseY - CGFloat(i + 1) * presetRowH + 2
            let btn = NSButton(radioButtonWithTitle: "\(preset.0)    \(preset.1) min / \(preset.2) min 休息",
                               target: helper, action: #selector(TimerEditHelper.presetSelected(_:)))
            btn.font = NSFont.systemFont(ofSize: 11)
            btn.frame = NSRect(x: 2, y: y, width: 270, height: presetRowH)
            btn.tag = i
            container.addSubview(btn)
            radioButtons.append(btn)
        }
        helper.presets = presets
        helper.radioButtons = radioButtons

        // +/- 按钮事件（同时取消 radio 选中）
        workMinusBtn.target = helper
        workMinusBtn.action = #selector(TimerEditHelper.decreaseWork)
        workPlusBtn.target = helper
        workPlusBtn.action = #selector(TimerEditHelper.increaseWork)
        restMinusBtn.target = helper
        restMinusBtn.action = #selector(TimerEditHelper.decreaseRest)
        restPlusBtn.target = helper
        restPlusBtn.action = #selector(TimerEditHelper.increaseRest)

        // 输入框编辑时取消 radio 选中
        workField.delegate = helper
        restField.delegate = helper

        alert.accessoryView = container
        alert.window.initialFirstResponder = workField

        // 失焦自动取消编辑弹窗（仅编辑弹窗，阶段提示弹窗不受影响）
        var resignObserver: NSObjectProtocol?
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main
        ) { _ in
            NSApp.abortModal()
            alert.window.close()
        }

        let result = alert.runModal()

        // 移除失焦观察者
        if let observer = resignObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        if result == .alertFirstButtonReturn || result == .alertSecondButtonReturn {
            // 直接开始 / 仅保存：都先保存时长
            let workVal = Int(workField.stringValue) ?? timer.workMinutes
            let restVal = Int(restField.stringValue) ?? timer.restMinutes
            timer.setWorkMinutes(workVal)
            timer.setRestMinutes(restVal)
            updateTimerUI()
            // 直接开始：保存后立即启动计时
            if result == .alertFirstButtonReturn {
                timer.start()
            }
        }
        _ = helper
    }

    // MARK: - Tab 切换

    private func switchTab(_ tab: QuickPanelTab) {
        guard currentTab != tab else { return }
        currentTab = tab
        ConfigStore.shared.saveLastPanelTab(tab)
        highlightedWindowID = nil
        updateTabButtonStyles()
        forceReload()
    }

    @objc private func switchToRunningTab() { switchTab(.running) }
    @objc private func switchToFavoritesTab() { switchTab(.favorites) }

    private func updateTabButtonStyles() {
        let colors = ConfigStore.shared.currentThemeColors
        // 先全部重置为未选中样式
        for btn in [runningTabButton, favoritesTabButton] {
            btn.font = .systemFont(ofSize: 11)
            btn.contentTintColor = colors.nsTextTertiary
            btn.layer?.backgroundColor = NSColor.clear.cgColor
        }
        // 隐藏所有指示条
        runningTabIndicator.layer?.backgroundColor = NSColor.clear.cgColor
        favoritesTabIndicator.layer?.backgroundColor = NSColor.clear.cgColor

        // 设置选中 Tab 样式（加粗 + 强调色 + 底部指示条）
        let selectedButton: NSButton
        let selectedIndicator: NSView
        switch currentTab {
        case .running:
            selectedButton = runningTabButton
            selectedIndicator = runningTabIndicator
        case .favorites:
            selectedButton = favoritesTabButton
            selectedIndicator = favoritesTabIndicator
        }
        selectedButton.font = .systemFont(ofSize: 11, weight: .semibold)
        selectedButton.contentTintColor = colors.nsAccent
        selectedIndicator.layer?.backgroundColor = colors.nsAccent.cgColor
    }

    /// 应用主题（外部调用）
    func applyTheme() {
        let colors = ConfigStore.shared.currentThemeColors
        topBar.layer?.backgroundColor = colors.nsTextPrimary.withAlphaComponent(0.04).cgColor
        openKanbanButton.contentTintColor = colors.nsTextSecondary
        topSeparator.layer?.backgroundColor = colors.nsSeparator.cgColor
        tabSeparator.layer?.backgroundColor = colors.nsSeparator.cgColor
        bottomSeparator.layer?.backgroundColor = colors.nsSeparator.cgColor
        timerBar.layer?.backgroundColor = colors.nsTextPrimary.withAlphaComponent(0.03).cgColor
        timerProgressBg.layer?.backgroundColor = colors.nsTextPrimary.withAlphaComponent(0.08).cgColor
        updateTabButtonStyles()
        updateTimerUI()
        forceReload()
    }

    // MARK: - 数据加载

    /// 强制全量重建 UI（清除差分缓存）
    func forceReload() {
        lastStructuralKey = ""
        reloadData()
    }

    /// 重新加载面板数据（差分更新：结构变化全量重建，仅标题变化只更新文本）
    func reloadData() {
        let structuralKey = buildStructuralKey()

        if structuralKey != lastStructuralKey {
            // 结构变了 → 全量重建（清空映射 + 重建所有视图）
            windowTitleLabels.removeAll()
            windowRowViewMap.removeAll()
            contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
            buildContent()
            lastStructuralKey = structuralKey
        } else {
            // 结构没变 → 只更新窗口标题文本
            updateWindowTitles()
        }

        updatePanelSize()
    }

    /// 构建结构 key（不含窗口标题，标题变化属于内容级更新）
    private func buildStructuralKey() -> String {
        let ax = WindowService.shared.isAXApiAvailable() ? "AX1" : "AX0"
        var parts: [String] = [currentTab.rawValue, ax]

        switch currentTab {
        case .running:
            let apps = AppMonitor.shared.runningApps.filter { !$0.windows.isEmpty }
            for app in apps {
                let windowIDs = app.windows.map { String($0.id) }.joined(separator: ",")
                let collapsed = collapsedApps.contains(app.bundleID) ? "C" : "E"
                let fav = ConfigStore.shared.isFavorite(app.bundleID) ? "F" : ""
                parts.append("\(app.bundleID):\(app.isRunning):\(windowIDs):\(collapsed):\(fav)")
            }
        case .favorites:
            let configs = ConfigStore.shared.appConfigs
            let runningApps = AppMonitor.shared.runningApps
            for config in configs {
                let running = runningApps.first(where: { $0.bundleID == config.bundleID })
                let isRunning = running?.isRunning ?? false
                let windowIDs = running?.windows.map { String($0.id) }.joined(separator: ",") ?? ""
                let collapsed = collapsedApps.contains(config.bundleID) ? "C" : "E"
                parts.append("\(config.bundleID):\(isRunning):\(windowIDs):\(collapsed)")
            }
        }

        parts.append("H:\(highlightedWindowID ?? 0)")
        return parts.joined(separator: "|")
    }

    /// 内容级更新：只刷新窗口标题文本（不重建视图）
    private func updateWindowTitles() {
        for app in AppMonitor.shared.runningApps {
            for window in app.windows {
                if let label = windowTitleLabels[window.id] {
                    let displayTitle = resolveDisplayTitle(bundleID: app.bundleID, windowInfo: window)
                    if label.stringValue != displayTitle {
                        label.stringValue = displayTitle
                    }
                }
            }
        }
    }

    /// 解析窗口显示标题（优先使用自定义名称）
    private func resolveDisplayTitle(bundleID: String, windowInfo: WindowInfo) -> String {
        let renameKey = Self.renameKey(bundleID: bundleID, windowID: windowInfo.id)
        let customName = ConfigStore.shared.windowRenames[renameKey]
        if let custom = customName, !custom.isEmpty {
            return custom
        }
        return windowInfo.title.isEmpty ? "（无标题）" : windowInfo.title
    }

    /// 重置面板状态（面板关闭时调用，保留 Tab 记忆）
    func resetToNormalMode() {
        highlightedWindowID = nil
        // 不重置 currentTab（Tab 记忆功能）
        collapsedApps.removeAll()
        windowTitleLabels.removeAll()
        windowRowViewMap.removeAll()
        lastStructuralKey = ""  // 清除快照，确保下次打开时强制刷新
    }

    // MARK: - 内容构建

    private func buildContent() {
        switch currentTab {
        case .running:
            buildRunningTabContent()
        case .favorites:
            buildFavoritesTabContent()
        }
    }

    /// "活跃"Tab：显示有可见窗口的运行中 App（关注的排在前面）
    private func buildRunningTabContent() {
        let activeApps = AppMonitor.shared.runningApps.filter { !$0.windows.isEmpty }
        let sorted = activeApps.sorted { a, b in
            let aFav = ConfigStore.shared.isFavorite(a.bundleID)
            let bFav = ConfigStore.shared.isFavorite(b.bundleID)
            if aFav != bFav { return aFav }
            return false // 同组内保持原有顺序
        }
        buildRunningAppList(apps: sorted, emptyText: "没有活跃窗口的应用")
    }

    /// 通用：构建运行中 App 列表（活跃/关注 Tab 共用）
    private func buildRunningAppList(apps: [RunningApp], emptyText: String) {
        if apps.isEmpty {
            addEmptyStateLabel(emptyText)
            return
        }

        let hasAccessibility = WindowService.shared.isAXApiAvailable()

        for app in apps {
            let appRow = createRunningAppRow(app: app)
            contentStack.addArrangedSubview(appRow)

            if hasAccessibility, !app.windows.isEmpty,
               !(collapsedApps.contains(app.bundleID)) {
                let windowList = createWindowList(windows: app.windows, bundleID: app.bundleID)
                contentStack.addArrangedSubview(windowList)
            }
        }

        if !hasAccessibility {
            let permissionHint = createPermissionHintView()
            contentStack.addArrangedSubview(permissionHint)
        }
    }

    /// "关注"Tab：显示关注 App 列表（数据源来自 ConfigStore）
    private func buildFavoritesTabContent() {
        let configs = ConfigStore.shared.appConfigs
        let runningApps = AppMonitor.shared.runningApps

        if configs.isEmpty {
            addEmptyStateLabel("尚未关注任何应用")
            return
        }

        let hasAccessibility = WindowService.shared.isAXApiAvailable()

        for config in configs {
            let running = runningApps.first(where: { $0.bundleID == config.bundleID })
            let isRunning = running?.isRunning ?? false

            let appRow = createFavoriteAppRow(config: config, runningApp: running, isRunning: isRunning)
            contentStack.addArrangedSubview(appRow)

            // 窗口列表（运行中且有权限时显示）
            if hasAccessibility, let app = running, !app.windows.isEmpty,
               !collapsedApps.contains(config.bundleID) {
                let windowList = createWindowList(windows: app.windows, bundleID: config.bundleID)
                contentStack.addArrangedSubview(windowList)
            }
        }

        if !hasAccessibility {
            let permissionHint = createPermissionHintView()
            contentStack.addArrangedSubview(permissionHint)
        }
    }

    // MARK: - 面板高度计算

    private func updatePanelSize() {
        guard let panelWindow = window else { return }
        guard let screen = panelWindow.screen ?? NSScreen.main else { return }

        // 使用用户保存的高度（尊重手动 resize 设定），内容不足时 scrollView 留白
        let maxHeight = screen.visibleFrame.height * Constants.Panel.maxHeightRatio
        let savedHeight = ConfigStore.shared.panelSize.height
        let clampedHeight = min(max(savedHeight, Constants.Panel.minHeight), maxHeight)

        var frame = panelWindow.frame
        let heightDiff = clampedHeight - frame.height
        frame.size.height = clampedHeight
        frame.origin.y -= heightDiff
        panelWindow.setFrame(frame, display: true)
    }
}

// MARK: - 计时器编辑对话框辅助（+/- 按钮事件）

private class TimerEditHelper: NSObject, NSTextFieldDelegate {
    let workField: NSTextField
    let restField: NSTextField
    let workStep: Int
    let restStep: Int
    var presets: [(String, Int, Int)] = []
    var radioButtons: [NSButton] = []

    init(workField: NSTextField, restField: NSTextField, workStep: Int, restStep: Int) {
        self.workField = workField
        self.restField = restField
        self.workStep = workStep
        self.restStep = restStep
    }

    private func deselectRadios() {
        for btn in radioButtons {
            btn.state = .off
        }
    }

    @objc func decreaseWork() {
        let cur = Int(workField.stringValue) ?? 0
        workField.stringValue = "\(max(1, cur - workStep))"
        deselectRadios()
    }

    @objc func increaseWork() {
        let cur = Int(workField.stringValue) ?? 0
        workField.stringValue = "\(cur + workStep)"
        deselectRadios()
    }

    @objc func decreaseRest() {
        let cur = Int(restField.stringValue) ?? 0
        restField.stringValue = "\(max(1, cur - restStep))"
        deselectRadios()
    }

    @objc func increaseRest() {
        let cur = Int(restField.stringValue) ?? 0
        restField.stringValue = "\(cur + restStep)"
        deselectRadios()
    }

    @objc func presetSelected(_ sender: NSButton) {
        let idx = sender.tag
        guard idx >= 0, idx < presets.count else { return }
        let preset = presets[idx]
        workField.stringValue = "\(preset.1)"
        restField.stringValue = "\(preset.2)"
    }

    // MARK: - NSTextFieldDelegate（手动输入时取消 radio 选中）

    func controlTextDidChange(_ obj: Notification) {
        deselectRadios()
    }
}

// MARK: - 可 hover 高亮的行视图（支持右键菜单）

final class HoverableRowView: NSView {

    /// 关联的 bundleID（用于 App 行点击）
    var bundleID: String?
    /// 关联的窗口 ID（用于窗口行点击）
    var windowID: CGWindowID?
    /// 关联的窗口信息
    var windowInfo: WindowInfo?
    /// 右键菜单提供者
    var contextMenuProvider: (() -> NSMenu?)?
    /// 点击处理闭包
    var clickHandler: (() -> Void)?

    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    /// 标记该行是否处于选中高亮状态（由外部设置）
    var isHighlighted = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        updateTrackingArea()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        updateTrackingArea()
    }

    deinit {
        if let area = trackingArea {
            removeTrackingArea(area)
        }
    }

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

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        // hover 高亮不覆盖选中高亮（选中高亮由 QuickPanelView 在构建行时设置）
        if !isHighlighted {
            layer?.backgroundColor = ConfigStore.shared.currentThemeColors.nsTextPrimary.withAlphaComponent(0.06).cgColor
            layer?.cornerRadius = 6
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        // 恢复时检查是否有选中高亮，避免清除选中状态
        if !isHighlighted {
            layer?.backgroundColor = nil
        }
    }

    // MARK: - 点击处理

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if let hitView = hitTest(location), hitView is NSButton || hitView.superview is NSButton {
            super.mouseUp(with: event)
            return
        }
        if let handler = clickHandler {
            handler()
        } else {
            super.mouseUp(with: event)
        }
    }

    // MARK: - 右键菜单

    override func menu(for event: NSEvent) -> NSMenu? {
        return contextMenuProvider?() ?? super.menu(for: event)
    }
}

// MARK: - 翻转坐标系的 ClipView（确保内容从顶部开始显示）

private final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}
