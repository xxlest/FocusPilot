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

    /// 用户点击选择的持久 Tab（写入 UserDefaults）
    var selectedTab: QuickPanelTab = .running
    /// 当前实际显示的 Tab（驱动 UI 渲染，hover 预览时可与 selectedTab 不同）
    var displayTab: QuickPanelTab = .running

    /// 当前高亮的窗口行 ID（同一时间只有一个）
    var highlightedWindowID: CGWindowID?

    /// 多窗口 App 折叠状态（按 bundleID 跟踪）
    var collapsedApps: Set<String> = []

    /// 非固定模式下当前 hover 展开的 App（按 bundleID 跟踪）
    var hoverExpandedBundleID: String?
    /// 非固定模式下 bundleID → windowList 视图映射（用于中心化收起旧列表）
    var hoverWindowListMap: [String: NSView] = [:]

    /// 当前是否处于非固定模式（便于各处判断）
    var isUnpinnedMode: Bool {
        (window as? QuickPanelWindow)?.isPanelPinned == false
    }

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

    // MARK: - FocusByTime 底部计时器栏（跨文件 extension 需访问，使用 internal）

    /// 底部分割线
    let bottomSeparator: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = ConfigStore.shared.currentThemeColors.nsSeparator.withAlphaComponent(0.9).cgColor
        return view
    }()

    /// 底部计时器栏容器
    let timerBar: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = ConfigStore.shared.currentThemeColors.nsTextPrimary.withAlphaComponent(0.08).cgColor
        return view
    }()

    /// 阶段图标（laptopcomputer / cup.and.saucer.fill / pause.circle）
    let timerPhaseIcon: NSImageView = {
        let iv = NSImageView()
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.setContentHuggingPriority(.required, for: .horizontal)
        iv.setContentHuggingPriority(.required, for: .vertical)
        iv.isHidden = true
        return iv
    }()

    /// 行动提示标签（idle / pending 共用，14pt medium 居中）
    let timerActionLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        return label
    }()

    /// 时间显示 "MM:SS"（22pt 大号等宽，视觉重心）
    let timerTimeLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
        label.textColor = ConfigStore.shared.currentThemeColors.nsTextPrimary
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        return label
    }()

    /// 计时器内容组（icon + time 水平排列，垂直居中对齐）
    let timerContentStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        return stack
    }()

    /// 进度条背景
    let timerProgressBg: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 1.5
        view.layer?.backgroundColor = ConfigStore.shared.currentThemeColors.nsTextPrimary.withAlphaComponent(0.08).cgColor
        return view
    }()

    /// 进度条填充
    let timerProgressFill: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 1.5
        return view
    }()

    /// 引导休息步骤标签（步骤名 · n/N）
    let timerStepLabel: NSTextField = {
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
    let timerIdleFocusLabel: NSTextField = {
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
    let timerIdleRestLabel: NSTextField = {
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
    let timerIdleSeparator: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.isHidden = true
        return view
    }()

    /// 进度条填充宽度约束
    var timerProgressFillWidth: NSLayoutConstraint?
    /// 进度条可见时内容组微上移约束
    var timerContentStackCenterY: NSLayoutConstraint?

    /// 计时器栏鼠标追踪区域（hover 效果）
    var timerBarTrackingArea: NSTrackingArea?
    /// 计时器栏 hover 状态
    var isTimerBarHovered = false

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
        selectedTab = QuickPanelTab(rawValue: ConfigStore.shared.lastPanelTab) ?? .running
        displayTab = selectedTab
        updateTabButtonStyles()

        // Tab 按钮 hover tracking（非固定模式下 hover 切换 Tab）
        for btn in [runningTabButton, favoritesTabButton, aiTabButton] {
            let area = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: ["tabButton": btn]
            )
            btn.addTrackingArea(area)
        }

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
        // Tab 按钮 hover（非固定模式下自动切换 Tab）
        if let btn = event.trackingArea?.userInfo?["tabButton"] as? NSButton,
           let panelWindow = window as? QuickPanelWindow,
           !panelWindow.isPanelPinned {
            // 子视图 hover 也要取消面板收起计时器
            panelWindow.cancelDismissTimer()
            panelWindow.restoreLevel()
            if btn === runningTabButton {
                hoverPreviewTab(.running)
            } else if btn === favoritesTabButton {
                hoverPreviewTab(.favorites)
            } else if btn === aiTabButton {
                hoverPreviewTab(.ai)
            }
            return
        }

        // App 容器 hover（非固定模式下展开窗口列表）
        if let bundleID = event.trackingArea?.userInfo?["hoverExpandBundleID"] as? String,
           isUnpinnedMode {
            // 子视图 hover 也要取消面板收起计时器
            if let panelWindow = window as? QuickPanelWindow {
                panelWindow.cancelDismissTimer()
                panelWindow.restoreLevel()
            }
            // 中心化：先收起上一个展开的列表
            if let oldID = hoverExpandedBundleID, oldID != bundleID,
               let oldList = hoverWindowListMap[oldID] {
                oldList.isHidden = true
            }
            hoverExpandedBundleID = bundleID
            hoverWindowListMap[bundleID]?.isHidden = false
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
        // Tab 按钮 hover 结束（不触发收起，由主 tracking area 负责）
        if event.trackingArea?.userInfo?["tabButton"] != nil {
            return
        }
        // App 容器 hover 结束（非固定模式下折叠窗口列表）
        if let bundleID = event.trackingArea?.userInfo?["hoverExpandBundleID"] as? String,
           isUnpinnedMode {
            if hoverExpandedBundleID == bundleID {
                hoverExpandedBundleID = nil
                hoverWindowListMap[bundleID]?.isHidden = true
            }
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
        // 面板钉住状态变化（hover 模式切换）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelPinStateDidChange(_:)),
            name: Constants.Notifications.panelPinStateChanged,
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

    // MARK: - FocusByTime 弹窗辅助

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

    // MARK: - Tab 切换

    private func switchTab(_ tab: QuickPanelTab) {
        guard displayTab != tab else { return }
        hoverExpandedBundleID = nil
        selectedTab = tab
        displayTab = tab
        ConfigStore.shared.saveLastPanelTab(tab)
        highlightedWindowID = nil
        updateTabButtonStyles()
        forceReload()
    }

    @objc private func switchToRunningTab() { switchTab(.running) }
    @objc private func switchToFavoritesTab() { switchTab(.favorites) }
    @objc private func switchToAITab() { switchTab(.ai) }

    /// 非固定模式 hover 临时预览 Tab（不持久化，不改 selectedTab）
    private func hoverPreviewTab(_ tab: QuickPanelTab) {
        guard displayTab != tab else { return }
        hoverExpandedBundleID = nil
        displayTab = tab
        updateTabButtonStyles()
        forceReload()
    }

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
        switch displayTab {
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

    /// 面板即将显示时调用：清理所有临时态（兜住 hide 动画竞态导致 resetToNormalMode 被跳过的情况）
    func prepareForShow() {
        resetToNormalMode()
        updateTabButtonStyles()
    }

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
            hoverWindowListMap.removeAll()
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
        var parts: [String] = [displayTab.rawValue, ax]

        switch displayTab {
        case .running:
            let apps = AppMonitor.shared.runningApps.filter { !$0.windows.isEmpty }
            for app in apps {
                let windowIDs = app.windows.map { String($0.id) }.joined(separator: ",")
                let collapsed = isUnpinnedMode ? "H" : (collapsedApps.contains(app.bundleID) ? "C" : "E")
                let fav = ConfigStore.shared.isFavorite(app.bundleID) ? "F" : ""
                parts.append("\(app.bundleID):\(app.isRunning):\(windowIDs):\(collapsed):\(fav)")
            }
        case .favorites:
            let configs = ConfigStore.shared.appConfigs
            let runningApps = AppMonitor.shared.runningApps
            for config in configs {
                let running = runningApps.first(where: { $0.bundleID == config.bundleID })
                let isRunning = running?.isRunning ?? false
                let windows = running?.windows ?? []
                let windowIDs = windows.map { String($0.id) }.joined(separator: ",")
                let collapsed = isUnpinnedMode ? "H" : (collapsedApps.contains(config.bundleID) ? "C" : "E")
                let unreadCounts = windows.map { String(CoderBridgeService.shared.actionableCount(for: $0.id)) }.joined(separator: ",")
                parts.append("\(config.bundleID):\(isRunning):\(windowIDs):\(collapsed):U\(unreadCounts)")
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
        displayTab = selectedTab
        hoverExpandedBundleID = nil
        hoverWindowListMap.removeAll()
        collapsedApps.removeAll()
        windowTitleLabels.removeAll()
        windowRowViewMap.removeAll()
        lastStructuralKey = ""  // 清除快照，确保下次打开时强制刷新
    }

    /// 创建 hover 展开容器（App 行 + 窗口列表，非固定模式专用）
    private func createHoverExpandContainer(appRow: NSView, windowList: NSView, bundleID: String) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        stack.addArrangedSubview(appRow)
        stack.addArrangedSubview(windowList)

        // 默认折叠，hover 展开时恢复
        windowList.isHidden = (hoverExpandedBundleID != bundleID)

        // 注册到映射表（用于中心化收起）
        hoverWindowListMap[bundleID] = windowList

        // Tracking area for hover expand/collapse
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: ["hoverExpandBundleID": bundleID]
        )
        container.addTrackingArea(area)

        return container
    }

    // MARK: - 内容构建

    private func buildContent() {
        switch displayTab {
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

            if hasAccessibility, !app.windows.isEmpty {
                let windowList = createWindowList(windows: app.windows, bundleID: app.bundleID)

                if isUnpinnedMode {
                    let container = createHoverExpandContainer(
                        appRow: appRow, windowList: windowList, bundleID: app.bundleID
                    )
                    contentStack.addArrangedSubview(container)
                } else {
                    contentStack.addArrangedSubview(appRow)
                    if !collapsedApps.contains(app.bundleID) {
                        contentStack.addArrangedSubview(windowList)
                    }
                }
            } else {
                contentStack.addArrangedSubview(appRow)
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

            if hasAccessibility, let app = running, !app.windows.isEmpty {
                let windowList = createWindowList(windows: app.windows, bundleID: config.bundleID)

                if isUnpinnedMode {
                    let container = createHoverExpandContainer(
                        appRow: appRow, windowList: windowList, bundleID: config.bundleID
                    )
                    contentStack.addArrangedSubview(container)
                } else {
                    contentStack.addArrangedSubview(appRow)
                    if !collapsedApps.contains(config.bundleID) {
                        contentStack.addArrangedSubview(windowList)
                    }
                }
            } else {
                contentStack.addArrangedSubview(appRow)
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

            // 目录组右键菜单
            let isFirstGroup = (groups.first?.cwdNormalized == cwdKey)
            let hasTodoFile = FileManager.default.fileExists(atPath: (cwdKey as NSString).appendingPathComponent("todo.md"))
            if !isFirstGroup || !hasTodoFile {
                groupRow.contextMenuProvider = { [weak self] in
                    let menu = NSMenu()
                    if !isFirstGroup {
                        let pinItem = NSMenuItem(title: "置顶", action: nil, keyEquivalent: "")
                        pinItem.target = self
                        pinItem.action = #selector(self?.handlePinGroup(_:))
                        pinItem.representedObject = cwdKey
                        menu.addItem(pinItem)
                    }
                    if !hasTodoFile {
                        if menu.items.count > 0 { menu.addItem(NSMenuItem.separator()) }
                        let todoItem = NSMenuItem(title: "创建任务看板", action: nil, keyEquivalent: "")
                        todoItem.target = self
                        todoItem.action = #selector(self?.handleCreateTodoFile(_:))
                        todoItem.representedObject = cwdKey
                        menu.addItem(todoItem)
                    }
                    return menu
                }
            }

            contentStack.addArrangedSubview(groupRow)
            groupRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

            if !isCollapsed {
                // === 任务区（todo.md 存在时渲染）===
                if let board = TodoService.shared.parse(cwd: cwdKey) {
                    let isTodoExpanded = expandedTodoGroups.contains(cwdKey)

                    // 任务折叠行
                    let foldRow = createTodoFoldRow(todoBoard: board, cwdNormalized: cwdKey, isExpanded: isTodoExpanded)
                    contentStack.addArrangedSubview(foldRow)
                    foldRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

                    if isTodoExpanded {
                        // Todo 区
                        for (i, item) in board.todo.enumerated() {
                            let itemRow = createTodoItemRow(item: item, section: .todo, index: i, cwdNormalized: cwdKey)
                            contentStack.addArrangedSubview(itemRow)
                            itemRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
                        }
                        // In Progress 区
                        for (i, item) in board.inProgress.enumerated() {
                            let itemRow = createTodoItemRow(item: item, section: .inProgress, index: i, cwdNormalized: cwdKey)
                            contentStack.addArrangedSubview(itemRow)
                            itemRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
                        }

                        // Done 摘要行
                        if board.doneCount > 0 {
                            let isDoneExpanded = expandedDoneGroups.contains(cwdKey)
                            let doneRow = createDoneSummaryRow(doneCount: board.doneCount, cwdNormalized: cwdKey, isExpanded: isDoneExpanded)
                            contentStack.addArrangedSubview(doneRow)
                            doneRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

                            if isDoneExpanded {
                                for (i, item) in board.done.enumerated() {
                                    let itemRow = createTodoItemRow(item: item, section: .done, index: i, cwdNormalized: cwdKey)
                                    contentStack.addArrangedSubview(itemRow)
                                    itemRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
                                }
                            }
                        }
                    }

                    // 分隔线（任务区和 session 区之间）
                    if !group.sessions.isEmpty {
                        let separator = NSView()
                        separator.wantsLayer = true
                        separator.layer?.backgroundColor = theme.nsSeparator.cgColor
                        separator.translatesAutoresizingMaskIntoConstraints = false
                        contentStack.addArrangedSubview(separator)
                        NSLayoutConstraint.activate([
                            separator.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -Constants.Panel.windowIndent * 2),
                            separator.heightAnchor.constraint(equalToConstant: 1),
                            separator.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor, constant: Constants.Panel.windowIndent),
                        ])
                    }
                }

                // === Session 行（已有逻辑）===
                for session in group.sessions {
                    let row = createSessionRow(session: session)
                    contentStack.addArrangedSubview(row)
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
            if self.displayTab == .ai || self.displayTab == .favorites {
                self.forceReload()
            }
        }
    }

    @objc private func panelPinStateDidChange(_ notification: Notification) {
        let pinned = notification.userInfo?["isPinned"] as? Bool ?? false
        if pinned {
            displayTab = selectedTab
            hoverExpandedBundleID = nil
            hoverWindowListMap.removeAll()
            updateTabButtonStyles()
            forceReload()
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

    var doubleClickHandler: (() -> Void)?

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if let hitView = hitTest(location), hitView is NSButton || hitView.superview is NSButton {
            super.mouseUp(with: event)
            return
        }
        if event.clickCount == 2, let dblHandler = doubleClickHandler {
            dblHandler()
        } else if event.clickCount == 1, let handler = clickHandler {
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
