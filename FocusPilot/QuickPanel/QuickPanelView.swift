import AppKit

// MARK: - 快捷面板 Tab 枚举

enum QuickPanelTab: String {
    case running    = "running"   // 活跃
    case favorites  = "favorites" // 关注
    case ai         = "ai"        // AI
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

    /// AI Tab 目录组折叠状态（按 cwdNormalized 跟踪）
    var collapsedGroups: Set<String> = []
    var expandedTodoGroups: Set<String> = []    // 任务区展开状态（默认折叠）
    var expandedDoneGroups: Set<String> = []    // Done 区展开状态（默认折叠）

    /// 上次渲染时的结构快照（用于判断是否需要全量重建）
    private var lastStructuralKey: String = ""

    /// 窗口行标题 label 引用（用于内容级更新）
    var windowTitleLabels: [CGWindowID: NSTextField] = [:]
    /// 窗口行视图引用（用于高亮更新）
    var windowRowViewMap: [CGWindowID: HoverableRowView] = [:]

    /// 鼠标追踪区域
    private var trackingArea: NSTrackingArea?

    // MARK: - 子视图

    /// 顶部栏（带明显背景底色，与列表区形成层次）
    private let topBar: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = ConfigStore.shared.currentThemeColors.nsTextPrimary.withAlphaComponent(0.10).cgColor
        return view
    }()

    /// 顶部分割线（手动颜色，确保主题下可见）
    private let topSeparator: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = ConfigStore.shared.currentThemeColors.nsSeparator.withAlphaComponent(0.8).cgColor
        return view
    }()

    /// Tab 按钮之间的竖线分隔符
    private let tabSeparator: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = ConfigStore.shared.currentThemeColors.nsSeparator.withAlphaComponent(0.8).cgColor
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

    /// Tab 按钮之间的竖线分隔符（关注 | AI）
    private let tabSeparator2: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = ConfigStore.shared.currentThemeColors.nsSeparator.withAlphaComponent(0.8).cgColor
        return view
    }()

    /// AI Tab 按钮
    private lazy var aiTabButton: NSButton = {
        let btn = NSButton(title: "AI", target: self, action: #selector(switchToAITab))
        btn.bezelStyle = .recessed
        btn.isBordered = false
        btn.font = .systemFont(ofSize: 11)
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 4
        btn.contentTintColor = ConfigStore.shared.currentThemeColors.nsTextSecondary
        return btn
    }()

    /// Tab 选中下划线指示条（AI）
    private let aiTabIndicator: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 1
        return view
    }()

    /// AI Tab 角标（actionable 计数）
    private let aiBadgeLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 9, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.cornerRadius = 6
        label.layer?.backgroundColor = NSColor.systemRed.cgColor
        label.isHidden = true
        return label
    }()

    // MARK: - FocusByTime 底部计时器栏

    /// 底部分割线
    private let bottomSeparator: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = ConfigStore.shared.currentThemeColors.nsSeparator.withAlphaComponent(0.9).cgColor
        return view
    }()

    /// 底部计时器栏容器
    private let timerBar: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = ConfigStore.shared.currentThemeColors.nsTextPrimary.withAlphaComponent(0.08).cgColor
        return view
    }()

    /// 阶段图标（laptopcomputer / cup.and.saucer.fill / pause.circle）
    private let timerPhaseIcon: NSImageView = {
        let iv = NSImageView()
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.setContentHuggingPriority(.required, for: .horizontal)
        iv.setContentHuggingPriority(.required, for: .vertical)
        iv.isHidden = true
        return iv
    }()

    /// 行动提示标签（idle / pending 共用，14pt medium 居中）
    private let timerActionLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        return label
    }()

    /// 时间显示 "MM:SS"（22pt 大号等宽，视觉重心）
    private let timerTimeLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
        label.textColor = ConfigStore.shared.currentThemeColors.nsTextPrimary
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        return label
    }()

    /// 计时器内容组（icon + time 水平排列，垂直居中对齐）
    private let timerContentStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        return stack
    }()

    /// 进度条背景
    private let timerProgressBg: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 1.5
        view.layer?.backgroundColor = ConfigStore.shared.currentThemeColors.nsTextPrimary.withAlphaComponent(0.08).cgColor
        return view
    }()

    /// 进度条填充
    private let timerProgressFill: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 1.5
        return view
    }()

    /// 引导休息步骤标签（步骤名 · n/N）
    private let timerStepLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.alignment = .center
        label.isHidden = true
        return label
    }()

    /// idle 状态：开始专注标签（左半边）
    private let timerIdleFocusLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.alignment = .center
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.isHidden = true
        return label
    }()

    /// idle 状态：休息标签（右半边）
    private let timerIdleRestLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.alignment = .center
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.isHidden = true
        return label
    }()

    /// idle 状态：专注与休息之间的竖线分隔符
    private let timerIdleSeparator: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.isHidden = true
        return view
    }()

    /// 进度条填充宽度约束
    private var timerProgressFillWidth: NSLayoutConstraint?
    /// 进度条可见时内容组微上移约束
    private var timerContentStackCenterY: NSLayoutConstraint?

    /// 计时器栏鼠标追踪区域（hover 效果）
    private var timerBarTrackingArea: NSTrackingArea?
    /// 计时器栏 hover 状态
    private var isTimerBarHovered = false

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
        if let area = timerBarTrackingArea {
            timerBar.removeTrackingArea(area)
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
        topBar.addSubview(tabSeparator2)
        topBar.addSubview(aiTabButton)
        topBar.addSubview(aiTabIndicator)
        topBar.addSubview(aiBadgeLabel)

        // 滚动区域
        addSubview(scrollView)

        // 底部计时器栏
        addSubview(bottomSeparator)
        addSubview(timerBar)
        timerContentStack.addArrangedSubview(timerPhaseIcon)
        timerContentStack.addArrangedSubview(timerTimeLabel)
        timerBar.addSubview(timerContentStack)
        timerBar.addSubview(timerActionLabel)
        timerBar.addSubview(timerStepLabel)
        timerBar.addSubview(timerProgressBg)
        timerProgressBg.addSubview(timerProgressFill)
        timerBar.addSubview(timerIdleFocusLabel)
        timerBar.addSubview(timerIdleSeparator)
        timerBar.addSubview(timerIdleRestLabel)

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
        tabSeparator2.translatesAutoresizingMaskIntoConstraints = false
        aiTabButton.translatesAutoresizingMaskIntoConstraints = false
        aiTabIndicator.translatesAutoresizingMaskIntoConstraints = false
        aiBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        bottomSeparator.translatesAutoresizingMaskIntoConstraints = false
        timerBar.translatesAutoresizingMaskIntoConstraints = false
        timerContentStack.translatesAutoresizingMaskIntoConstraints = false
        timerPhaseIcon.translatesAutoresizingMaskIntoConstraints = false
        timerActionLabel.translatesAutoresizingMaskIntoConstraints = false
        timerStepLabel.translatesAutoresizingMaskIntoConstraints = false
        timerProgressBg.translatesAutoresizingMaskIntoConstraints = false
        timerProgressFill.translatesAutoresizingMaskIntoConstraints = false
        timerIdleFocusLabel.translatesAutoresizingMaskIntoConstraints = false
        timerIdleSeparator.translatesAutoresizingMaskIntoConstraints = false
        timerIdleRestLabel.translatesAutoresizingMaskIntoConstraints = false

        let topBarHeight: CGFloat = 32

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

            // Tab 竖线分隔符 2（关注 | AI）
            tabSeparator2.leadingAnchor.constraint(equalTo: favoritesTabButton.trailingAnchor, constant: 5),
            tabSeparator2.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            tabSeparator2.widthAnchor.constraint(equalToConstant: 1),
            tabSeparator2.heightAnchor.constraint(equalToConstant: 12),

            aiTabButton.leadingAnchor.constraint(equalTo: tabSeparator2.trailingAnchor, constant: 5),
            aiTabButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            // AI Tab 下划线指示条
            aiTabIndicator.leadingAnchor.constraint(equalTo: aiTabButton.leadingAnchor, constant: 2),
            aiTabIndicator.trailingAnchor.constraint(equalTo: aiTabButton.trailingAnchor, constant: -2),
            aiTabIndicator.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -1),
            aiTabIndicator.heightAnchor.constraint(equalToConstant: 2),

            // AI Tab 角标（按钮右上角偏移）
            aiBadgeLabel.leadingAnchor.constraint(equalTo: aiTabButton.trailingAnchor, constant: -4),
            aiBadgeLabel.bottomAnchor.constraint(equalTo: aiTabButton.topAnchor, constant: 6),
            aiBadgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 14),
            aiBadgeLabel.heightAnchor.constraint(equalToConstant: 14),

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

            // 底部计时器栏（固定 48px 高度）
            timerBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            timerBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            timerBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            timerBar.heightAnchor.constraint(equalToConstant: 48),

            // 内容组（icon + time 水平排列，整组居中）
            timerContentStack.centerXAnchor.constraint(equalTo: timerBar.centerXAnchor),

            // 图标尺寸（比时间字体稍大，更醒目）
            timerPhaseIcon.widthAnchor.constraint(equalToConstant: 28),
            timerPhaseIcon.heightAnchor.constraint(equalToConstant: 28),

            // 行动提示标签居中（idle / pending 共用）
            timerActionLabel.centerXAnchor.constraint(equalTo: timerBar.centerXAnchor),
            timerActionLabel.centerYAnchor.constraint(equalTo: timerBar.centerYAnchor),

            // 引导步骤标签（居中，顶部偏上）
            timerStepLabel.centerXAnchor.constraint(equalTo: timerBar.centerXAnchor),
            timerStepLabel.topAnchor.constraint(equalTo: timerBar.topAnchor, constant: 3),

            // 进度条（底部，左右留边距居中）
            timerProgressBg.leadingAnchor.constraint(equalTo: timerBar.leadingAnchor, constant: 16),
            timerProgressBg.trailingAnchor.constraint(equalTo: timerBar.trailingAnchor, constant: -16),
            timerProgressBg.bottomAnchor.constraint(equalTo: timerBar.bottomAnchor, constant: -4),
            timerProgressBg.heightAnchor.constraint(equalToConstant: 3),

            // 进度条填充
            timerProgressFill.leadingAnchor.constraint(equalTo: timerProgressBg.leadingAnchor),
            timerProgressFill.topAnchor.constraint(equalTo: timerProgressBg.topAnchor),
            timerProgressFill.bottomAnchor.constraint(equalTo: timerProgressBg.bottomAnchor),

            // idle 双入口：竖线分隔符居中
            timerIdleSeparator.centerXAnchor.constraint(equalTo: timerBar.centerXAnchor),
            timerIdleSeparator.centerYAnchor.constraint(equalTo: timerBar.centerYAnchor),
            timerIdleSeparator.widthAnchor.constraint(equalToConstant: 1),
            timerIdleSeparator.heightAnchor.constraint(equalToConstant: 18),

            // idle 双入口：开始专注（左半边居中）
            timerIdleFocusLabel.leadingAnchor.constraint(equalTo: timerBar.leadingAnchor),
            timerIdleFocusLabel.trailingAnchor.constraint(equalTo: timerIdleSeparator.leadingAnchor),
            timerIdleFocusLabel.centerYAnchor.constraint(equalTo: timerBar.centerYAnchor),

            // idle 双入口：休息（右半边居中）
            timerIdleRestLabel.leadingAnchor.constraint(equalTo: timerIdleSeparator.trailingAnchor),
            timerIdleRestLabel.trailingAnchor.constraint(equalTo: timerBar.trailingAnchor),
            timerIdleRestLabel.centerYAnchor.constraint(equalTo: timerBar.centerYAnchor),
        ])

        // 进度条填充宽度约束（初始为 0）
        let fillWidth = timerProgressFill.widthAnchor.constraint(equalToConstant: 0)
        fillWidth.isActive = true
        timerProgressFillWidth = fillWidth

        // 内容组垂直居中（微上移 2px 给进度条留视觉空间）
        let centerY = timerContentStack.centerYAnchor.constraint(equalTo: timerBar.centerYAnchor, constant: -2)
        centerY.isActive = true
        timerContentStackCenterY = centerY

        // 计时器栏点击手势（整栏可点击）
        let timerBarClick = NSClickGestureRecognizer(target: self, action: #selector(handleTimerBarTapped(_:)))
        timerBar.addGestureRecognizer(timerBarClick)

        // 计时器栏 hover 追踪
        let timerTracking = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        timerBar.addTrackingArea(timerTracking)
        timerBarTrackingArea = timerTracking

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
        // 计时器栏 hover
        if event.trackingArea === timerBarTrackingArea {
            isTimerBarHovered = true
            updateTimerBarHover()
            return
        }
        if let panelWindow = window as? QuickPanelWindow {
            // 鼠标进入面板：取消收起计时器
            panelWindow.cancelDismissTimer()
            // 恢复让位状态（激活窗口后临时降级的层级）
            panelWindow.restoreLevel()
        }
    }

    override func mouseExited(with event: NSEvent) {
        // 计时器栏 hover 结束
        if event.trackingArea === timerBarTrackingArea {
            isTimerBarHovered = false
            updateTimerBarHover()
            return
        }
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
        // 引导休息步骤切换
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(focusGuidedStepDidChange),
            name: Constants.Notifications.focusGuidedStepChanged,
            object: nil
        )
        // CoderBridge session 变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(coderBridgeSessionsDidChange),
            name: Constants.Notifications.coderBridgeSessionChanged,
            object: nil
        )
    }

    @objc private func focusGuidedStepDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.updateTimerUI()
        }
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
        let isGuided = timer.restMode == .guided && timer.phase == .rest

        // 先隐藏所有元素，按状态按需显示
        timerPhaseIcon.isHidden = true
        timerActionLabel.isHidden = true
        timerTimeLabel.isHidden = true
        timerContentStack.isHidden = true
        timerProgressBg.isHidden = true
        timerProgressFill.isHidden = true
        timerStepLabel.isHidden = true
        timerIdleFocusLabel.isHidden = true
        timerIdleRestLabel.isHidden = true
        timerIdleSeparator.isHidden = true

        // pending 状态：弹窗被失焦自动关闭，等待用户点击栏确认
        if hasPending {
            timerActionLabel.isHidden = false

            switch timer.pendingAction {
            case .startRest:
                timerActionLabel.stringValue = "工作完成 · 开始休息"
                timerActionLabel.textColor = NSColor.systemGreen
                timerBar.layer?.backgroundColor = colors.nsTextPrimary.withAlphaComponent(0.08).cgColor
                bottomSeparator.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.3).cgColor
            case .startWork:
                timerActionLabel.stringValue = "休息结束 · 继续工作"
                timerActionLabel.textColor = colors.nsAccent
                timerBar.layer?.backgroundColor = colors.nsTextPrimary.withAlphaComponent(0.08).cgColor
                bottomSeparator.layer?.backgroundColor = colors.nsAccent.withAlphaComponent(0.3).cgColor
            case .none:
                break
            }
            return
        }

        if isIdle {
            // idle：左右双入口（开始专注 | 休息）
            timerIdleFocusLabel.isHidden = false
            timerIdleRestLabel.isHidden = false
            timerIdleSeparator.isHidden = false
            timerIdleFocusLabel.stringValue = "▶  开始专注"
            timerIdleFocusLabel.textColor = colors.nsAccent
            timerIdleRestLabel.stringValue = "☕  休息"
            timerIdleRestLabel.textColor = NSColor.systemGreen
            timerIdleSeparator.layer?.backgroundColor = colors.nsSeparator.withAlphaComponent(0.6).cgColor
            timerBar.layer?.backgroundColor = colors.nsTextPrimary.withAlphaComponent(0.08).cgColor
            bottomSeparator.layer?.backgroundColor = colors.nsSeparator.withAlphaComponent(0.9).cgColor
        } else {
            // running / paused：SF Symbol 图标 + 大号时间 + 进度条
            let isPaused = timer.status == .paused
            timerContentStack.isHidden = false
            timerPhaseIcon.isHidden = false
            timerTimeLabel.isHidden = false
            timerProgressBg.isHidden = false
            timerProgressFill.isHidden = false

            // 引导模式：显示步骤标签，内容组下移
            if isGuided, let step = timer.currentStep {
                timerStepLabel.isHidden = false
                timerStepLabel.stringValue = "\(step.label) · \(timer.currentStepIndex + 1)/\(timer.guidedSteps.count)"
                timerStepLabel.textColor = isPaused ? colors.nsTextTertiary : NSColor.systemGreen
                timerContentStackCenterY?.constant = 2
            } else {
                timerContentStackCenterY?.constant = -2
            }

            if isPaused {
                let iconConfig = NSImage.SymbolConfiguration(pointSize: 22, weight: .medium)
                let icon = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: "已暂停")
                timerPhaseIcon.image = icon?.withSymbolConfiguration(iconConfig)
                timerPhaseIcon.contentTintColor = colors.nsTextTertiary
                timerTimeLabel.textColor = colors.nsTextTertiary
                timerProgressFill.layer?.backgroundColor = colors.nsTextTertiary.cgColor
                timerBar.layer?.backgroundColor = colors.nsTextPrimary.withAlphaComponent(0.08).cgColor
                bottomSeparator.layer?.backgroundColor = colors.nsSeparator.withAlphaComponent(0.9).cgColor
            } else {
                let phaseColor = timer.phase == .work ? colors.nsAccent : NSColor.systemGreen
                let iconConfig = NSImage.SymbolConfiguration(pointSize: 22, weight: .medium)

                if isGuided, let step = timer.currentStep {
                    // 引导模式：使用当前步骤的 SF Symbol
                    let icon = NSImage(systemSymbolName: step.sfSymbol, accessibilityDescription: step.label)
                    timerPhaseIcon.image = icon?.withSymbolConfiguration(iconConfig)
                } else {
                    let iconName = timer.phase == .work ? "laptopcomputer" : "cup.and.saucer.fill"
                    let iconDesc = timer.phase == .work ? "工作中" : "休息中"
                    let icon = NSImage(systemSymbolName: iconName, accessibilityDescription: iconDesc)
                    timerPhaseIcon.image = icon?.withSymbolConfiguration(iconConfig)
                }

                timerPhaseIcon.contentTintColor = phaseColor
                timerTimeLabel.textColor = colors.nsTextPrimary
                timerProgressFill.layer?.backgroundColor = phaseColor.cgColor
                if timer.phase == .work {
                    timerBar.layer?.backgroundColor = colors.nsAccent.withAlphaComponent(0.12).cgColor
                    bottomSeparator.layer?.backgroundColor = colors.nsAccent.withAlphaComponent(0.3).cgColor
                } else {
                    timerBar.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.12).cgColor
                    bottomSeparator.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.3).cgColor
                }
            }

            // 引导模式显示步骤剩余时间，自由模式显示总剩余时间
            timerTimeLabel.stringValue = isGuided ? timer.stepDisplayTime : timer.displayTime
            let progressWidth = timerProgressBg.bounds.width * timer.progress
            timerProgressFillWidth?.constant = max(0, progressWidth)
            timerProgressBg.layoutSubtreeIfNeeded()
        }
    }

    // MARK: - 计时器栏 hover 效果

    private func updateTimerBarHover() {
        let colors = ConfigStore.shared.currentThemeColors
        let timer = FocusTimerService.shared

        if isTimerBarHovered {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Constants.Design.Anim.micro
                let isNeutral = timer.status == .idle || timer.pendingAction != .none || timer.status == .paused
                if isNeutral {
                    timerBar.animator().layer?.backgroundColor = colors.nsTextPrimary.withAlphaComponent(0.14).cgColor
                } else if timer.phase == .work {
                    timerBar.animator().layer?.backgroundColor = colors.nsAccent.withAlphaComponent(0.18).cgColor
                } else {
                    timerBar.animator().layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.18).cgColor
                }
            }
            NSCursor.pointingHand.push()
        } else {
            NSCursor.pop()
            updateTimerUI()
        }
    }

    // MARK: - FocusByTime 对话框

    /// 弹窗预处理：降低面板层级 + 提升弹窗层级，位置走系统默认居中
    func prepareAlert(_ alert: NSAlert) {
        if let panelWindow = self.window as? QuickPanelWindow {
            panelWindow.level = .normal
        }
        // didBecomeKey 中提升弹窗层级（runModal 会重置 layout 阶段设置的 level）
        let alertWindow = alert.window
        var observer: NSObjectProtocol?
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: alertWindow,
            queue: .main
        ) { _ in
            if let obs = observer { NotificationCenter.default.removeObserver(obs) }
            alertWindow.level = NSWindow.Level(rawValue: Int(Constants.alertLevel))
        }
    }

    /// 弹窗后：恢复面板层级
    func restoreAfterAlert() {
        if let panelWindow = self.window as? QuickPanelWindow {
            panelWindow.level = NSWindow.Level(rawValue: Int(Constants.quickPanelLevel))
        }
    }

    /// 构建休息选择 accessory view（引导休息 radio + 自由休息 radio）
    private func buildRestSelectionAccessoryView() -> (container: NSView, helper: WorkCompleteHelper, hoverInfo: HoverInfoView) {
        let timer = FocusTimerService.shared
        let containerWidth: CGFloat = 320
        let intensities = RestIntensity.allCases
        let radioRowH: CGFloat = 22
        let descRowH: CGFloat = 16
        let groupH = radioRowH + descRowH
        let groupGap: CGFloat = 4
        let sepH: CGFloat = 12
        let freeRowH: CGFloat = 22
        let freeDescH: CGFloat = 16
        let infoRowH: CGFloat = 20
        let totalH = CGFloat(intensities.count) * groupH + CGFloat(intensities.count - 1) * groupGap + sepH + freeRowH + freeDescH + 4 + infoRowH
        let container = NSView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: totalH))

        // --- 底部 ⓘ 了解更多 ---
        let colors = ConfigStore.shared.currentThemeColors
        let accentColor = colors.nsAccent
        let tipTitleColor = accentColor.blended(withFraction: 0.35, of: .secondaryLabelColor) ?? accentColor
        let tipTitleFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let tipBodyFont = NSFont.systemFont(ofSize: 11)
        let tipBodyColor = NSColor.secondaryLabelColor
        let tA: [NSAttributedString.Key: Any] = [.font: tipTitleFont, .foregroundColor: tipTitleColor]
        let bA: [NSAttributedString.Key: Any] = [.font: tipBodyFont, .foregroundColor: tipBodyColor]

        let popContent = NSMutableAttributedString()
        popContent.append(NSAttributedString(string: "三维恢复的科学依据\n\n", attributes: tA))
        popContent.append(NSAttributedString(string: "\u{1f441} 眼睛恢复\n", attributes: tA))
        popContent.append(NSAttributedString(string: "持续近距离用眼使睫状肌紧张痉挛，闭眼休息 + 远眺（6 米以上）能快速放松睫状肌、缓解干眼和视觉疲劳。每 20-30 分钟远眺 20 秒是眼科推荐的 20-20-20 法则。\n\n", attributes: bA))
        popContent.append(NSAttributedString(string: "\u{1f9e0} 大脑恢复\n", attributes: tA))
        popContent.append(NSAttributedString(string: "前额叶皮层主导专注与决策，持续 20-50 分钟后活力自然衰退。深呼吸能激活副交感神经，降低皮质醇水平，让前额叶「重启」。硬撑只会陷入伪工作状态。\n\n", attributes: bA))
        popContent.append(NSAttributedString(string: "\u{1f4aa} 肌肉恢复\n", attributes: tA))
        popContent.append(NSAttributedString(string: "久坐导致髋屈肌缩短、核心失活、腰椎压力增大。骨盆后倾激活深层核心，猫牛拉伸脊柱，夹臀锁定骨盆中立位。三级强度对应不同姿态需求：坐着 → 站立 → 全链路。\n\n", attributes: bA))
        popContent.append(NSAttributedString(string: "\u{26d4} 禁忌\n", attributes: tA))
        popContent.append(NSAttributedString(string: "别刷短视频、别看社交消息。它们会消耗注意力残留，让大脑无法真正恢复，反而加重疲劳感。", attributes: bA))

        let hoverInfo = HoverInfoView(
            frame: NSRect(x: 0, y: 0, width: containerWidth, height: infoRowH),
            text: "\u{24d8} 了解三维恢复（眼睛 · 大脑 · 肌肉）的科学依据",
            popoverAttributedContent: popContent
        )
        container.addSubview(hoverInfo)

        // --- 分隔线下方：自由休息 radio ---
        let freeY = infoRowH + 4
        let freeRadio = NSButton(radioButtonWithTitle: "自由休息    \(timer.restMinutes) 分钟",
                                 target: nil, action: nil)
        freeRadio.font = .systemFont(ofSize: 12)
        freeRadio.frame = NSRect(x: 2, y: freeY + freeDescH, width: containerWidth - 4, height: freeRowH)
        freeRadio.tag = intensities.count  // tag = 3（区别于引导 0/1/2）
        container.addSubview(freeRadio)

        let freeDesc = NSTextField(labelWithString: "不跟步骤，按自己节奏恢复")
        freeDesc.font = .systemFont(ofSize: 11)
        freeDesc.textColor = .secondaryLabelColor
        freeDesc.frame = NSRect(x: 22, y: freeY, width: containerWidth - 24, height: freeDescH)
        container.addSubview(freeDesc)

        // --- 分隔线 ---
        let sepY = freeY + freeRowH + freeDescH + sepH / 2 - 0.5
        let sepLine = NSView(frame: NSRect(x: 0, y: sepY, width: containerWidth, height: 1))
        sepLine.wantsLayer = true
        sepLine.layer?.backgroundColor = NSColor.separatorColor.cgColor
        container.addSubview(sepLine)

        // --- 引导休息 radio（轻度/标准/深度）---
        var radioButtons: [NSButton] = []
        let guidedBaseY = sepY + sepH / 2
        for (i, intensity) in intensities.enumerated() {
            let y = guidedBaseY + CGFloat(intensities.count - 1 - i) * (groupH + groupGap)
            let btn = NSButton(radioButtonWithTitle: "\(intensity.displayName)    ~\(intensity.totalMinutes) 分钟",
                               target: nil, action: nil)
            btn.font = .systemFont(ofSize: 12, weight: .medium)
            btn.frame = NSRect(x: 2, y: y + descRowH, width: containerWidth - 4, height: radioRowH)
            btn.tag = i
            container.addSubview(btn)
            radioButtons.append(btn)

            let desc = NSTextField(labelWithString: intensity.description)
            desc.font = .systemFont(ofSize: 11)
            desc.textColor = .secondaryLabelColor
            desc.frame = NSRect(x: 22, y: y, width: containerWidth - 24, height: descRowH)
            container.addSubview(desc)
        }
        radioButtons.append(freeRadio)

        // Helper 处理 radio 互斥
        let helper = WorkCompleteHelper(
            guidedCount: intensities.count,
            radioButtons: radioButtons
        )
        for btn in radioButtons {
            btn.target = helper
            btn.action = #selector(WorkCompleteHelper.radioSelected(_:))
        }

        // 根据休息时长自动匹配引导强度（1:1 对应：5min→轻度，7min→标准，10min→深度）
        let matchedIntensity: RestIntensity
        switch timer.restMinutes {
        case ...5:  matchedIntensity = .light
        case 6...8: matchedIntensity = .standard
        default:    matchedIntensity = .deep
        }
        let defaultIndex = intensities.firstIndex(of: matchedIntensity) ?? 1
        radioButtons[defaultIndex].state = .on
        helper.selectedTag = defaultIndex

        return (container, helper, hoverInfo)
    }

    @objc private func handleWorkCompleted() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let timer = FocusTimerService.shared
            let alert = NSAlert()

            alert.messageText = "工作完成！"
            alert.informativeText = "已专注 \(timer.workMinutes) 分钟，选择恢复方式"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "直接结束")
            alert.addButton(withTitle: "开始休息")

            // 主操作按钮（开始休息）靠右 → 第二个按钮着绿色
            if alert.buttons.count > 1 {
                alert.buttons[1].bezelColor = NSColor.systemGreen
                alert.buttons[1].keyEquivalent = "\r"  // 回车键绑定到"开始休息"
                alert.buttons[0].keyEquivalent = ""     // 取消"直接结束"的默认回车
            }

            let (container, helper, hoverInfo) = self.buildRestSelectionAccessoryView()
            alert.accessoryView = container
            alert.window.initialFirstResponder = nil
            self.prepareAlert(alert)

            // 失焦自动关闭
            var resignObserver: NSObjectProtocol?
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil, queue: .main
            ) { _ in
                NSApp.abortModal()
                alert.window.close()
            }

            let result = alert.runModal()

            hoverInfo.cleanup()
            if let observer = resignObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            self.restoreAfterAlert()

            let intensities = RestIntensity.allCases
            if result == .alertSecondButtonReturn {
                // "开始休息"按钮
                let tag = helper.selectedTag
                if tag < intensities.count {
                    timer.startGuidedRest(intensity: intensities[tag])
                } else {
                    timer.startRestPhase()
                }
            } else if result == .alertFirstButtonReturn {
                // "直接结束"
                timer.reset()
            } else {
                // 失焦自动关闭：保留 pending
                timer.pendingAction = .startRest
                self.updateTimerUI()
            }
            _ = helper
        }
    }

    @objc private func handleRestCompleted() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let timer = FocusTimerService.shared
            let alert = NSAlert()

            alert.messageText = "充电完毕"
            alert.informativeText = "准备好下一轮 \(timer.workMinutes) 分钟专注了吗？"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "开始专注")
            alert.addButton(withTitle: "稍后再说")

            // 主按钮着色（accent 蓝）
            let accentColor = ConfigStore.shared.currentThemeColors.nsAccent
            if let primaryBtn = alert.buttons.first {
                primaryBtn.bezelColor = accentColor
            }

            self.prepareAlert(alert)

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
            self.restoreAfterAlert()

            if result == .alertFirstButtonReturn {
                // 回到 idle 状态，弹出时长选择弹窗（与初始"开始专注"一致）
                timer.reset()
                self.updateTimerUI()
                self.timerEditTapped()
            } else {
                // 失焦自动关闭 / 稍后再说：重新设置 pendingAction，计时器栏显示快捷操作
                timer.pendingAction = .startWork
                self.updateTimerUI()
            }
        }
    }

    // MARK: - FocusByTime 计时器栏点击

    @objc private func handleTimerBarTapped(_ gesture: NSClickGestureRecognizer) {
        let timer = FocusTimerService.shared

        // 优先处理 pending 动作
        switch timer.pendingAction {
        case .startRest:
            handleWorkCompleted()
            return
        case .startWork:
            handleRestCompleted()
            return
        case .none:
            break
        }

        switch timer.status {
        case .idle:
            // 左半边 = 开始专注，右半边 = 休息
            let location = gesture.location(in: timerBar)
            if location.x > timerBar.bounds.midX {
                restDirectTapped()
            } else {
                timerEditTapped()
            }
        case .running, .paused:
            showRunningActionSheet()
        }
    }

    /// 运行/暂停中点击栏 → 弹出操作面板（暂停/继续 + 停止，休息时附加休息指南）
    private func showRunningActionSheet() {
        let timer = FocusTimerService.shared
        let isPaused = timer.status == .paused
        let isRest = timer.phase == .rest
        let isGuided = timer.restMode == .guided && isRest

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)

            let alert = NSAlert()

            if isGuided {
                // 引导模式：显示当前步骤信息
                let stepInfo = timer.currentStep.map { "\($0.label) · 步骤 \(timer.currentStepIndex + 1)/\(timer.guidedSteps.count)" } ?? "引导休息"
                if isPaused {
                    alert.messageText = "已暂停 · \(stepInfo)"
                    alert.informativeText = timer.currentStep?.detail ?? "准备好了就继续"
                } else {
                    alert.messageText = "引导休息 · \(stepInfo)"
                    alert.informativeText = timer.currentStep?.detail ?? "跟随引导恢复状态"
                }
                // 附加步骤列表
                alert.accessoryView = self.buildGuidedStepListView()
            } else {
                let totalDisplay = String(format: "%02d:%02d", timer.totalSeconds / 60, timer.totalSeconds % 60)
                if isPaused {
                    alert.messageText = "已暂停 · \(timer.displayTime) / \(totalDisplay)"
                    alert.informativeText = "准备好了就继续"
                } else if isRest {
                    alert.messageText = "休息中 · \(timer.displayTime) / \(totalDisplay)"
                    alert.informativeText = "让身体和大脑充分恢复"
                } else {
                    alert.messageText = "工作中 · \(timer.displayTime) / \(totalDisplay)"
                    alert.informativeText = "保持专注，你做得很好"
                }
                // 自由休息中附加休息指南
                if isRest {
                    alert.accessoryView = self.buildRestGuideView()
                }
            }
            alert.alertStyle = .informational

            if isPaused {
                alert.addButton(withTitle: "继续")
                if let primaryBtn = alert.buttons.first {
                    primaryBtn.bezelColor = ConfigStore.shared.currentThemeColors.nsAccent
                }
            } else {
                alert.addButton(withTitle: "暂停")
            }
            alert.addButton(withTitle: "停止")

            self.prepareAlert(alert)

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
            self.restoreAfterAlert()

            if result == .alertFirstButtonReturn {
                if isPaused {
                    timer.resume()
                } else {
                    timer.pause()
                }
            } else if result == .alertSecondButtonReturn {
                timer.reset()
            }
        }
    }

    /// 构建科学休息指南视图（三维单行摘要，用于自由休息操作面板）
    private func buildRestGuideView() -> NSView {
        let items: [(String, String, String)] = [
            ("\u{1f441}", "眼睛恢复", "闭眼休息 + 远眺，放松睫状肌"),
            ("\u{1f9e0}", "大脑恢复", "深呼吸放空，让前额叶皮层恢复活力"),
            ("\u{1f4aa}", "肌肉恢复", "拉伸激活核心肌群，缓解久坐损伤"),
            ("\u{26d4}",  "禁忌",     "别刷短视频、别看社交消息"),
        ]
        let lineHeight: CGFloat = 20
        let padding: CGFloat = 10
        let containerH = CGFloat(items.count) * lineHeight + padding * 2
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: containerH))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.textColor.withAlphaComponent(0.04).cgColor
        container.layer?.cornerRadius = 8

        for (i, item) in items.enumerated() {
            let y = containerH - padding - CGFloat(i + 1) * lineHeight
            let label = NSTextField(labelWithString: "\(item.0)  \(item.1)  \(item.2)")
            label.font = .systemFont(ofSize: 11)
            label.textColor = .labelColor
            label.frame = NSRect(x: padding, y: y, width: 280, height: lineHeight)
            container.addSubview(label)
        }

        return container
    }

    /// 构建引导休息步骤列表视图（用于运行中查看进度）
    private func buildGuidedStepListView() -> NSView {
        let timer = FocusTimerService.shared
        let steps = timer.guidedSteps
        let currentIndex = timer.currentStepIndex
        let isPaused = timer.status == .paused

        let lineHeight: CGFloat = 22
        let detailHeight: CGFloat = 16
        let padding: CGFloat = 10
        let titleH: CGFloat = 20
        // 当前步骤多一行 detail
        let contentH = CGFloat(steps.count) * lineHeight + detailHeight
        let containerH = titleH + contentH + padding * 2 + 4
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: containerH))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.textColor.withAlphaComponent(0.04).cgColor
        container.layer?.cornerRadius = 8

        // 标题：强度 + 动态剩余总时间
        let remaining = max(0, timer.guidedTotalSeconds - timer.guidedElapsedSeconds)
        let titleStr: String
        if isPaused {
            titleStr = "\(timer.restIntensity.displayName) · 已暂停"
        } else {
            let rm = remaining / 60
            let rs = remaining % 60
            let remainStr = rs > 0 ? "\(rm)m\(String(format: "%02d", rs))s" : "\(rm)m"
            titleStr = "\(timer.restIntensity.displayName) · \(remainStr)"
        }
        let title = NSTextField(labelWithString: titleStr)
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        title.textColor = .secondaryLabelColor
        title.frame = NSRect(x: padding, y: containerH - padding - titleH, width: 280, height: titleH)
        container.addSubview(title)

        var currentY = containerH - padding - titleH - 4
        for (i, step) in steps.enumerated() {
            currentY -= lineHeight
            let mins = step.durationSeconds / 60
            let secs = step.durationSeconds % 60
            let timeStr: String
            if i == currentIndex {
                // 当前步骤显示剩余时间
                let sr = timer.remainingSeconds
                let srm = sr / 60
                let srs = sr % 60
                timeStr = srm > 0 ? "\(srm)m\(srs > 0 ? String(format: "%02d", srs) + "s" : "")" : "\(srs)s"
            } else {
                timeStr = mins > 0 ? "\(mins)m\(secs > 0 ? String(format: "%02d", secs) + "s" : "")" : "\(secs)s"
            }
            let prefix: String
            let font: NSFont
            let color: NSColor
            if i < currentIndex {
                prefix = "\u{2713}"  // ✓
                font = .systemFont(ofSize: 11)
                color = .tertiaryLabelColor
            } else if i == currentIndex {
                prefix = isPaused ? "\u{23f8}" : "\u{25b6}\u{fe0f}"  // ⏸ or ▶️
                font = .systemFont(ofSize: 11, weight: .semibold)
                color = isPaused ? .secondaryLabelColor : NSColor.systemGreen
            } else {
                prefix = "\u{25cb}"  // ○
                font = .systemFont(ofSize: 11)
                color = .secondaryLabelColor
            }
            let label = NSTextField(labelWithString: "\(prefix)  \(step.label) · \(timeStr)")
            label.font = font
            label.textColor = color
            label.frame = NSRect(x: padding + 2, y: currentY, width: 278, height: lineHeight)
            container.addSubview(label)

            // 当前步骤下方显示 detail 副文案
            if i == currentIndex {
                currentY -= detailHeight
                let detail = NSTextField(labelWithString: step.detail)
                detail.font = .systemFont(ofSize: 10.5)
                detail.textColor = .secondaryLabelColor
                detail.frame = NSRect(x: padding + 20, y: currentY, width: 260, height: detailHeight)
                container.addSubview(detail)
            }
        }

        return container
    }

    /// idle 状态点击"休息" → 直接选择休息方式并开始
    private func restDirectTapped() {
        let timer = FocusTimerService.shared
        guard timer.status == .idle else { return }

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)

            let alert = NSAlert()
            alert.messageText = "选择休息方式"
            alert.informativeText = "放下工作，让身体和大脑充分恢复"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "取消")
            alert.addButton(withTitle: "开始休息")

            // 主操作按钮（开始休息）着绿色
            if alert.buttons.count > 1 {
                alert.buttons[1].bezelColor = NSColor.systemGreen
                alert.buttons[1].keyEquivalent = "\r"
                alert.buttons[0].keyEquivalent = "\u{1b}"
            }

            let (container, helper, hoverInfo) = self.buildRestSelectionAccessoryView()
            alert.accessoryView = container
            alert.window.initialFirstResponder = nil
            self.prepareAlert(alert)

            // 失焦自动关闭
            var resignObserver: NSObjectProtocol?
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil, queue: .main
            ) { _ in
                NSApp.abortModal()
                alert.window.close()
            }

            let result = alert.runModal()

            hoverInfo.cleanup()
            if let observer = resignObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            self.restoreAfterAlert()

            let intensities = RestIntensity.allCases
            if result == .alertSecondButtonReturn {
                // "开始休息"按钮 → 独立休息模式
                let tag = helper.selectedTag
                if tag < intensities.count {
                    timer.startStandaloneGuidedRest(intensity: intensities[tag])
                } else {
                    timer.startStandaloneRestFree()
                }
            }
            // 取消或失焦关闭：回到 idle，无需处理
            _ = helper
        }
    }

    @objc private func timerEditTapped() {
        let timer = FocusTimerService.shared
        guard timer.status == .idle else { return }

        // 异步弹窗，避免 nonactivatingPanel 按钮回调中同步 activate 导致
        // didResignActiveNotification 在同一事件循环触发，使弹窗被立即关闭
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
    
            let alert = NSAlert()

            alert.messageText = "开始专注"
            alert.informativeText = "选择匹配当前任务的节奏，让每段时间都有效"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "开始")
            let cancelBtn = alert.addButton(withTitle: "取消")
            cancelBtn.keyEquivalent = "\u{1b}"

            // 主按钮着色（accent 蓝）
            let colors = ConfigStore.shared.currentThemeColors
            if let primaryBtn = alert.buttons.first {
                primaryBtn.bezelColor = colors.nsAccent
            }

            // 构建 accessory view（预设方案 radio → 分隔线 → 自定义 radio + 输入 → ⓘ 提示）
            let presets: [(String, Int, Int)] = [
                ("深度专注", 25, 5),
                ("常规节奏", 35, 7),
                ("轻度脑力", 50, 10),
            ]
            let containerWidth: CGFloat = 300
            let presetRowH: CGFloat = 24
            let presetsH = CGFloat(presets.count) * presetRowH
            let sepH: CGFloat = 12
            let customRadioH: CGFloat = 22
            let customInputH: CGFloat = 26
            let infoRowH: CGFloat = 18
            let totalH = presetsH + sepH + customRadioH + customInputH + 6 + infoRowH
            let container = NSView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: totalH))

            // --- 底部 ⓘ 了解更多（hover 弹出 Popover）---
            let accentColor = colors.nsAccent
            let tipTitleColor = accentColor.blended(withFraction: 0.35, of: .secondaryLabelColor) ?? accentColor
            let tipTitleFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
            let tipBodyFont = NSFont.systemFont(ofSize: 11)
            let tipBodyColor = NSColor.secondaryLabelColor
            let tA: [NSAttributedString.Key: Any] = [.font: tipTitleFont, .foregroundColor: tipTitleColor]
            let bA: [NSAttributedString.Key: Any] = [.font: tipBodyFont, .foregroundColor: tipBodyColor]

            let popContent = NSMutableAttributedString()
            popContent.append(NSAttributedString(string: "\u{1f4cb} 方案说明\n\n", attributes: tA))
            popContent.append(NSAttributedString(string: "深度专注（25+5）\n", attributes: tA))
            popContent.append(NSAttributedString(string: "经典番茄钟节奏。适合需要高度集中的任务，如编码调试、论文写作、方案设计、深度阅读。\n\n", attributes: bA))
            popContent.append(NSAttributedString(string: "常规节奏（35+7）\n", attributes: tA))
            popContent.append(NSAttributedString(string: "平衡专注与疲劳恢复。适合日常工作节奏，如邮件处理、文档整理、会议纪要、代码审查。\n\n", attributes: bA))
            popContent.append(NSAttributedString(string: "轻度脑力（50+10）\n", attributes: tA))
            popContent.append(NSAttributedString(string: "适合低认知负荷的长周期任务，如资料浏览、数据录入、素材收集、笔记归档。\n\n", attributes: bA))
            popContent.append(NSAttributedString(string: "\u{1f9e0} 为什么要定时休息？\n", attributes: tA))
            popContent.append(NSAttributedString(string: "前额叶皮层主导专注与决策，持续 20-50 分钟后活力自然衰退。定时休息让它恢复，硬撑只会陷入「伪工作」。\n\n", attributes: bA))
            popContent.append(NSAttributedString(string: "\u{26a1} 为什么不能过度消耗？\n", attributes: tA))
            popContent.append(NSAttributedString(string: "透支会拖慢前额叶的恢复节奏，一次硬撑的代价往往是半天的低效。", attributes: bA))

            let hoverInfo = HoverInfoView(
                frame: NSRect(x: 0, y: 0, width: containerWidth, height: infoRowH),
                text: "\u{24d8} 了解各方案的适用场景与科学依据",
                popoverAttributedContent: popContent
            )
            container.addSubview(hoverInfo)

            // --- 自定义 radio + 输入区域 ---
            let customInputY: CGFloat = infoRowH + 4
            let customRadioY = customInputY + customInputH + 2
            let stepperSize: CGFloat = 22
            let stepperFont = NSFont.systemFont(ofSize: 12, weight: .medium)

            // 自定义 radio 按钮
            let customRadio = NSButton(radioButtonWithTitle: "自定义",
                                       target: nil, action: nil)
            customRadio.font = .systemFont(ofSize: 12)
            customRadio.frame = NSRect(x: 2, y: customRadioY, width: containerWidth - 4, height: customRadioH)
            customRadio.tag = presets.count  // tag = 3
            container.addSubview(customRadio)

            // 自定义输入（缩进 22px，与 radio 文字对齐）
            let inputIndent: CGFloat = 22

            let workLabel = NSTextField(labelWithString: "工作")
            workLabel.font = .systemFont(ofSize: 11)
            workLabel.frame = NSRect(x: inputIndent, y: customInputY, width: 28, height: customInputH)
            container.addSubview(workLabel)

            let workMinusBtn = NSButton(frame: NSRect(x: inputIndent + 30, y: customInputY + 2, width: stepperSize, height: stepperSize))
            workMinusBtn.title = "\u{2212}"
            workMinusBtn.bezelStyle = .circular
            workMinusBtn.font = stepperFont
            container.addSubview(workMinusBtn)

            let workVisibleField = NSTextField(string: "\(timer.workMinutes)")
            workVisibleField.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            workVisibleField.alignment = .center
            workVisibleField.frame = NSRect(x: inputIndent + 54, y: customInputY + 2, width: 34, height: 20)
            container.addSubview(workVisibleField)

            let workPlusBtn = NSButton(frame: NSRect(x: inputIndent + 90, y: customInputY + 2, width: stepperSize, height: stepperSize))
            workPlusBtn.title = "+"
            workPlusBtn.bezelStyle = .circular
            workPlusBtn.font = stepperFont
            container.addSubview(workPlusBtn)

            let restLabel = NSTextField(labelWithString: "休息")
            restLabel.font = .systemFont(ofSize: 11)
            restLabel.frame = NSRect(x: inputIndent + 124, y: customInputY, width: 28, height: customInputH)
            container.addSubview(restLabel)

            let restMinusBtn = NSButton(frame: NSRect(x: inputIndent + 154, y: customInputY + 2, width: stepperSize, height: stepperSize))
            restMinusBtn.title = "\u{2212}"
            restMinusBtn.bezelStyle = .circular
            restMinusBtn.font = stepperFont
            container.addSubview(restMinusBtn)

            let restVisibleField = NSTextField(string: "\(timer.restMinutes)")
            restVisibleField.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            restVisibleField.alignment = .center
            restVisibleField.frame = NSRect(x: inputIndent + 178, y: customInputY + 2, width: 34, height: 20)
            container.addSubview(restVisibleField)

            let restPlusBtn = NSButton(frame: NSRect(x: inputIndent + 214, y: customInputY + 2, width: stepperSize, height: stepperSize))
            restPlusBtn.title = "+"
            restPlusBtn.bezelStyle = .circular
            restPlusBtn.font = stepperFont
            container.addSubview(restPlusBtn)

            // --- helper 初始化（绑定可见输入框 + 自定义 radio）---
            let helper = TimerEditHelper(workField: workVisibleField, restField: restVisibleField, workStep: 1, restStep: 1)

            // --- 分隔线（预设 ↔ 自定义）---
            let sepY = customRadioY + customRadioH + sepH / 2 - 0.5
            let sepLine = NSView(frame: NSRect(x: 0, y: sepY, width: containerWidth, height: 1))
            sepLine.wantsLayer = true
            sepLine.layer?.backgroundColor = NSColor.separatorColor.cgColor
            container.addSubview(sepLine)

            // --- 推荐方案区域（顶部，单行 radio）---
            var radioButtons: [NSButton] = []
            let presetBaseY = totalH
            for (i, preset) in presets.enumerated() {
                let y = presetBaseY - CGFloat(i + 1) * presetRowH
                let btn = NSButton(radioButtonWithTitle: "\(preset.0)    \(preset.1) min 工作 \u{00b7} \(preset.2) min 休息",
                                   target: helper, action: #selector(TimerEditHelper.presetSelected(_:)))
                btn.font = NSFont.systemFont(ofSize: 12)
                btn.frame = NSRect(x: 2, y: y + 2, width: containerWidth - 4, height: 20)
                btn.tag = i
                container.addSubview(btn)
                radioButtons.append(btn)
            }
            // 自定义 radio 加入 radioButtons 数组（互斥管理）
            radioButtons.append(customRadio)
            customRadio.target = helper
            customRadio.action = #selector(TimerEditHelper.customSelected(_:))

            helper.presets = presets
            helper.radioButtons = radioButtons

            // 默认选中匹配当前时长的方案，无匹配则选中自定义
            if let matchIndex = presets.firstIndex(where: { $0.1 == timer.workMinutes && $0.2 == timer.restMinutes }) {
                radioButtons[matchIndex].state = .on
            } else {
                customRadio.state = .on
            }

            // +/- 按钮事件（切换到自定义 radio）
            workMinusBtn.target = helper
            workMinusBtn.action = #selector(TimerEditHelper.decreaseWork)
            workPlusBtn.target = helper
            workPlusBtn.action = #selector(TimerEditHelper.increaseWork)
            restMinusBtn.target = helper
            restMinusBtn.action = #selector(TimerEditHelper.decreaseRest)
            restPlusBtn.target = helper
            restPlusBtn.action = #selector(TimerEditHelper.increaseRest)

            // 输入框编辑时切换到自定义 radio
            workVisibleField.delegate = helper
            restVisibleField.delegate = helper
    
            alert.accessoryView = container
            alert.window.initialFirstResponder = nil
            self.prepareAlert(alert)
    
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

            // 清理
            hoverInfo.cleanup()
            if let observer = resignObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            self.restoreAfterAlert()

            if result == .alertFirstButtonReturn {
                // 保存时长并启动计时
                let workVal = Int(workVisibleField.stringValue) ?? timer.workMinutes
                let restVal = Int(restVisibleField.stringValue) ?? timer.restMinutes
                timer.setWorkMinutes(workVal)
                timer.setRestMinutes(restVal)
                self.updateTimerUI()
                timer.start()
            }
            _ = helper
        }
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
    @objc private func switchToAITab() { switchTab(.ai) }

    private func updateTabButtonStyles() {
        let colors = ConfigStore.shared.currentThemeColors
        // 先全部重置为未选中样式
        for btn in [runningTabButton, favoritesTabButton, aiTabButton] {
            btn.font = .systemFont(ofSize: 11)
            btn.contentTintColor = colors.nsTextTertiary
            btn.layer?.backgroundColor = NSColor.clear.cgColor
        }
        // 隐藏所有指示条
        runningTabIndicator.layer?.backgroundColor = NSColor.clear.cgColor
        favoritesTabIndicator.layer?.backgroundColor = NSColor.clear.cgColor
        aiTabIndicator.layer?.backgroundColor = NSColor.clear.cgColor

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
        case .ai:
            selectedButton = aiTabButton
            selectedIndicator = aiTabIndicator
        }
        selectedButton.font = .systemFont(ofSize: 11, weight: .semibold)
        selectedButton.contentTintColor = colors.nsAccent
        selectedIndicator.layer?.backgroundColor = colors.nsAccent.cgColor
    }

    /// 应用主题（外部调用）
    func applyTheme() {
        let colors = ConfigStore.shared.currentThemeColors
        topBar.layer?.backgroundColor = colors.nsTextPrimary.withAlphaComponent(0.10).cgColor
        openKanbanButton.contentTintColor = colors.nsTextSecondary
        topSeparator.layer?.backgroundColor = colors.nsSeparator.withAlphaComponent(0.8).cgColor
        tabSeparator.layer?.backgroundColor = colors.nsSeparator.withAlphaComponent(0.8).cgColor
        tabSeparator2.layer?.backgroundColor = colors.nsSeparator.withAlphaComponent(0.8).cgColor
        aiBadgeLabel.layer?.backgroundColor = NSColor.systemRed.cgColor
        bottomSeparator.layer?.backgroundColor = colors.nsSeparator.withAlphaComponent(0.9).cgColor
        timerBar.layer?.backgroundColor = colors.nsTextPrimary.withAlphaComponent(0.08).cgColor
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
        case .ai:
            let sessionKeys = CoderBridgeService.shared.sessions
                .map { "\($0.cwdNormalized):\($0.sessionID):\($0.status.rawValue):\($0.lifecycle.rawValue)" }
                .sorted()
                .joined(separator: "|")
            let collapsed = collapsedGroups.sorted().joined(separator: ",")
            // todo.md mtime 纳入 key，外部修改时触发全量重建
            let cwds = Set(CoderBridgeService.shared.sessions.map { $0.cwdNormalized })
            let todoMtimes = cwds.sorted().map { "\($0):\(TodoService.shared.mtime(cwd: $0))" }.joined(separator: ",")
            parts.append("AI:\(sessionKeys):C:\(collapsed):T:\(todoMtimes)")
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
        case .ai:
            buildAITabContent()
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

    /// "AI"Tab：显示 CoderBridge session 列表或空状态
    private func buildAITabContent() {
        let groups = CoderBridgeService.shared.groupedSessions

        if groups.isEmpty {
            let label = createLabel(
                "还没有 AI 编码会话\n启动一个 AI 编码工具后\n会自动显示在这里",
                size: 11,
                color: ConfigStore.shared.currentThemeColors.nsTextTertiary
            )
            label.alignment = .center
            label.maximumNumberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            label.translatesAutoresizingMaskIntoConstraints = false
            contentStack.addArrangedSubview(label)
            label.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
            return
        }

        let theme = ConfigStore.shared.currentThemeColors

        for group in groups {
            let isCollapsed = collapsedGroups.contains(group.cwdNormalized)

            // 目录组行
            let groupRow = HoverableRowView()
            groupRow.translatesAutoresizingMaskIntoConstraints = false
            groupRow.heightAnchor.constraint(equalToConstant: Constants.Panel.appRowHeight).isActive = true
            groupRow.setContentHuggingPriority(.defaultLow, for: .horizontal)

            let groupStack = NSStackView()
            groupStack.orientation = .horizontal
            groupStack.alignment = .centerY
            groupStack.spacing = Constants.Design.Spacing.sm
            groupStack.translatesAutoresizingMaskIntoConstraints = false
            groupRow.addSubview(groupStack)
            NSLayoutConstraint.activate([
                groupStack.leadingAnchor.constraint(equalTo: groupRow.leadingAnchor, constant: Constants.Design.Spacing.sm),
                groupStack.trailingAnchor.constraint(equalTo: groupRow.trailingAnchor, constant: -Constants.Design.Spacing.sm),
                groupStack.centerYAnchor.constraint(equalTo: groupRow.centerYAnchor),
            ])

            // 折叠箭头
            let chevronName = isCollapsed ? "chevron.right" : "chevron.down"
            if let chevronImage = Self.cachedSymbol(name: chevronName, size: 10, weight: .medium) {
                let chevron = NSImageView(image: chevronImage)
                chevron.contentTintColor = theme.nsTextSecondary
                chevron.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    chevron.widthAnchor.constraint(equalToConstant: 14),
                    chevron.heightAnchor.constraint(equalToConstant: 14),
                ])
                groupStack.addArrangedSubview(chevron)
            }

            // 文件夹图标（folder.fill，accent 色）
            if let folderImage = Self.cachedSymbol(name: "folder.fill", size: 13, weight: .regular) {
                let folderIcon = NSImageView(image: folderImage)
                folderIcon.contentTintColor = theme.nsAccent
                folderIcon.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    folderIcon.widthAnchor.constraint(equalToConstant: 16),
                    folderIcon.heightAnchor.constraint(equalToConstant: 14),
                ])
                groupStack.addArrangedSubview(folderIcon)
            }

            // 目录名（可截断）
            let dirLabel = createLabel(group.displayName, size: 12, color: theme.nsTextPrimary)
            dirLabel.font = .systemFont(ofSize: 12, weight: .medium)
            dirLabel.lineBreakMode = .byTruncatingTail
            dirLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            groupStack.addArrangedSubview(dirLabel)

            groupStack.addArrangedSubview(createSpacer())

            // session 数量（不被挤掉）
            let countLabel = createLabel("(\(group.sessions.count))", size: 11, color: theme.nsTextTertiary)
            countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            groupStack.addArrangedSubview(countLabel)

            let cwdKey = group.cwdNormalized
            groupRow.clickHandler = { [weak self] in
                if self?.collapsedGroups.contains(cwdKey) == true {
                    self?.collapsedGroups.remove(cwdKey)
                } else {
                    self?.collapsedGroups.insert(cwdKey)
                }
                self?.forceReload()
            }

            // 目录组右键菜单（置顶）
            let isFirstGroup = (groups.first?.cwdNormalized == cwdKey)
            if !isFirstGroup {
                groupRow.contextMenuProvider = { [weak self] in
                    let menu = NSMenu()
                    let pinItem = NSMenuItem(title: "置顶", action: nil, keyEquivalent: "")
                    pinItem.target = nil
                    menu.addItem(pinItem)
                    pinItem.target = self
                    pinItem.action = #selector(self?.handlePinGroup(_:))
                    pinItem.representedObject = cwdKey
                    return menu
                }
            }

            contentStack.addArrangedSubview(groupRow)
            groupRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

            if !isCollapsed {
                for session in group.sessions {
                    let row = createSessionRow(session: session)
                    contentStack.addArrangedSubview(row)
                    // 行宽撑满 contentStack
                    row.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
                }
            }
        }
    }

    /// 更新 AI Tab 角标（actionable 计数）
    private func updateAIBadge() {
        let count = CoderBridgeService.shared.actionableCount
        if count > 0 {
            aiBadgeLabel.stringValue = "\(count)"
            aiBadgeLabel.isHidden = false
        } else {
            aiBadgeLabel.isHidden = true
        }
    }

    @objc private func coderBridgeSessionsDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updateAIBadge()
            if self.currentTab == .ai {
                self.forceReload()
            }
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

// MARK: - 工作完成弹窗 radio 辅助

private class WorkCompleteHelper: NSObject {
    let guidedCount: Int
    let radioButtons: [NSButton]
    var selectedTag: Int = 0

    init(guidedCount: Int, radioButtons: [NSButton]) {
        self.guidedCount = guidedCount
        self.radioButtons = radioButtons
    }

    @objc func radioSelected(_ sender: NSButton) {
        selectedTag = sender.tag
        // 互斥：关闭其他 radio
        for btn in radioButtons where btn !== sender {
            btn.state = .off
        }
        sender.state = .on
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

    /// 取消所有预设 radio，选中"自定义"（数组最后一个）
    private func selectCustomRadio() {
        for btn in radioButtons { btn.state = .off }
        radioButtons.last?.state = .on
    }

    @objc func decreaseWork() {
        let cur = Int(workField.stringValue) ?? 0
        workField.stringValue = "\(max(1, cur - workStep))"
        selectCustomRadio()
    }

    @objc func increaseWork() {
        let cur = Int(workField.stringValue) ?? 0
        workField.stringValue = "\(cur + workStep)"
        selectCustomRadio()
    }

    @objc func decreaseRest() {
        let cur = Int(restField.stringValue) ?? 0
        restField.stringValue = "\(max(1, cur - restStep))"
        selectCustomRadio()
    }

    @objc func increaseRest() {
        let cur = Int(restField.stringValue) ?? 0
        restField.stringValue = "\(cur + restStep)"
        selectCustomRadio()
    }

    @objc func presetSelected(_ sender: NSButton) {
        let idx = sender.tag
        guard idx >= 0, idx < presets.count else { return }
        let preset = presets[idx]
        workField.stringValue = "\(preset.1)"
        restField.stringValue = "\(preset.2)"
        // 手动互斥：取消其他 radio
        for btn in radioButtons where btn !== sender { btn.state = .off }
        sender.state = .on
    }

    @objc func customSelected(_ sender: NSButton) {
        // 手动互斥：取消预设 radio
        for btn in radioButtons where btn !== sender { btn.state = .off }
        sender.state = .on
    }

    // MARK: - NSTextFieldDelegate（手动输入时切换到自定义 radio）

    func controlTextDidChange(_ obj: Notification) {
        selectCustomRadio()
    }
}

// MARK: - 悬停弹出信息提示视图

private final class HoverInfoView: NSView {
    private let label: NSTextField
    private var popover: NSPopover?
    private var hoverTimer: Timer?
    private let popoverContent: NSAttributedString

    init(frame: NSRect, text: String, popoverAttributedContent: NSAttributedString) {
        self.label = NSTextField(labelWithString: text)
        self.popoverContent = popoverAttributedContent
        super.init(frame: frame)

        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.frame = bounds
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    // 在视图进入窗口后动态管理 tracking area
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        label.textColor = .labelColor
        hoverTimer?.invalidate()
        // Timer 必须加入 .common mode 才能在 NSAlert modal 中触发
        let timer = Timer(timeInterval: 0.15, repeats: false) { [weak self] _ in
            self?.showPopover()
        }
        RunLoop.current.add(timer, forMode: .common)
        hoverTimer = timer
    }

    override func mouseExited(with event: NSEvent) {
        label.textColor = .secondaryLabelColor
        hoverTimer?.invalidate()
        hoverTimer = nil
        popover?.close()
        popover = nil
    }

    private func showPopover() {
        guard popover == nil, window != nil else { return }

        let textField = NSTextField(wrappingLabelWithString: "")
        textField.attributedStringValue = popoverContent
        textField.isSelectable = false
        textField.preferredMaxLayoutWidth = 300
        let size = textField.intrinsicContentSize
        textField.frame = NSRect(x: 12, y: 12, width: size.width, height: size.height)

        let vc = NSViewController()
        vc.view = NSView(frame: NSRect(x: 0, y: 0, width: size.width + 24, height: size.height + 24))
        vc.view.addSubview(textField)

        let pop = NSPopover()
        pop.contentViewController = vc
        pop.behavior = .semitransient
        pop.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
        popover = pop
    }

    func cleanup() {
        hoverTimer?.invalidate()
        popover?.close()
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

    // MARK: - 状态

    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    /// 标记该行是否处于选中高亮状态（由外部设置）
    var isHighlighted = false

    // MARK: - 可配置颜色（AI session 行设置，其他行不设置走默认灰色）

    /// hover 时的背景色（nil = 默认灰色 0.08）
    var hoverColor: NSColor?
    /// 选中时的背景色（nil = 同 hoverColor 或默认灰色）
    var selectedColor: NSColor?
    /// 左侧竖线颜色（nil = 不显示竖线）
    var indicatorColor: NSColor?
    /// 是否处于选中状态（点击后固定，优先级高于 hover）
    var isSelected = false {
        didSet {
            if isSelected {
                // 清除上一个 selected 行
                if let prev = Self.currentlySelectedRow, prev !== self {
                    prev.isSelected = false
                }
                Self.currentlySelectedRow = self
            } else if Self.currentlySelectedRow === self {
                Self.currentlySelectedRow = nil
            }
            updateAppearance()
        }
    }

    /// 左侧竖线（创建一次，通过 isHidden 切换）
    private lazy var indicatorLine: NSView = {
        let line = NSView()
        line.wantsLayer = true
        line.isHidden = true
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.topAnchor.constraint(equalTo: topAnchor),
            line.bottomAnchor.constraint(equalTo: bottomAnchor),
            line.widthAnchor.constraint(equalToConstant: 5),
        ])
        return line
    }()

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

    // MARK: - 渲染

    /// 全局唯一选中行（点击哪个就高亮哪个，其他全部清除）
    static weak var currentlySelectedRow: HoverableRowView?

    func updateAppearance() {
        if isSelected {
            layer?.backgroundColor = (selectedColor ?? NSColor.systemOrange.withAlphaComponent(0.15)).cgColor
            if let color = indicatorColor {
                indicatorLine.layer?.backgroundColor = color.cgColor
                indicatorLine.isHidden = false
            }
        } else {
            layer?.backgroundColor = nil
            indicatorLine.isHidden = true
        }
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        if !isSelected {
            layer?.backgroundColor = ConfigStore.shared.currentThemeColors.nsTextPrimary.withAlphaComponent(0.08).cgColor
            layer?.cornerRadius = 6
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        if !isSelected {
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
