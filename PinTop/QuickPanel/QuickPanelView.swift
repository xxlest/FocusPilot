import AppKit
import ApplicationServices

// MARK: - 快捷面板 Tab 枚举

enum QuickPanelTab: String {
    case running    = "running"   // 已打开
    case favorites  = "favorites" // 收藏
}

// MARK: - 快捷面板内容视图
// 全部/已打开/收藏三个 Tab，App 列表 + 内嵌窗口列表
// 支持实时更新、钉住模式、窗口重命名、窗口行高亮+前置

final class QuickPanelView: NSView {

    // MARK: - 状态

    /// 当前 Tab 页（setupView 中从 ConfigStore 恢复）
    private var currentTab: QuickPanelTab = .running

    /// 当前高亮的窗口行 ID（同一时间只有一个）
    private var highlightedWindowID: CGWindowID?

    /// 多窗口 App 折叠状态（按 bundleID 跟踪）
    private var collapsedApps: Set<String> = []

    /// 上次刷新时的窗口数据快照
    private var lastWindowSnapshot: String = ""

    /// 鼠标追踪区域
    private var trackingArea: NSTrackingArea?

    // MARK: - 子视图

    /// 顶部栏
    private let topBar: NSView = {
        let view = NSView()
        view.wantsLayer = true
        return view
    }()

    /// 顶部分割线
    private let topSeparator: NSBox = {
        let box = NSBox()
        box.boxType = .separator
        return box
    }()

    /// 打开主界面按钮（顶部左侧）
    private lazy var openKanbanButton: NSButton = {
        let btn = NSButton()
        btn.bezelStyle = .recessed
        btn.isBordered = false
        if let img = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "打开主界面") {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            btn.image = img.withSymbolConfiguration(config) ?? img
        }
        btn.contentTintColor = .secondaryLabelColor
        btn.toolTip = "打开主界面"
        btn.target = self
        btn.action = #selector(openMainKanban)
        return btn
    }()

    /// 已打开 Tab 按钮
    private lazy var runningTabButton: NSButton = {
        let btn = NSButton(title: "已打开", target: self, action: #selector(switchToRunningTab))
        btn.bezelStyle = .recessed
        btn.isBordered = false
        btn.font = .systemFont(ofSize: 11)
        btn.contentTintColor = .secondaryLabelColor
        return btn
    }()

    /// 收藏 Tab 按钮
    private lazy var favoritesTabButton: NSButton = {
        let btn = NSButton(title: "收藏", target: self, action: #selector(switchToFavoritesTab))
        btn.bezelStyle = .recessed
        btn.isBordered = false
        btn.font = .systemFont(ofSize: 11)
        btn.contentTintColor = .secondaryLabelColor
        return btn
    }()

    /// 面板钉住按钮（顶部右侧）
    private lazy var panelPinButton: NSButton = {
        let btn = NSButton()
        btn.bezelStyle = .recessed
        btn.isBordered = false
        if let img = NSImage(systemSymbolName: "pin", accessibilityDescription: "钉住面板") {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            btn.image = img.withSymbolConfiguration(config) ?? img
        }
        btn.contentTintColor = .secondaryLabelColor
        btn.target = self
        btn.action = #selector(togglePanelPin)
        btn.toolTip = "钉住面板"
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
    private let contentStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
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
        topBar.addSubview(favoritesTabButton)
        topBar.addSubview(panelPinButton)

        // 滚动区域
        addSubview(scrollView)

        // Auto Layout
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topSeparator.translatesAutoresizingMaskIntoConstraints = false
        openKanbanButton.translatesAutoresizingMaskIntoConstraints = false
        runningTabButton.translatesAutoresizingMaskIntoConstraints = false
        favoritesTabButton.translatesAutoresizingMaskIntoConstraints = false
        panelPinButton.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let topBarHeight: CGFloat = 24

        NSLayoutConstraint.activate([
            // 顶部栏
            topBar.topAnchor.constraint(equalTo: topAnchor),
            topBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: topBarHeight),

            // 顶部分割线
            topSeparator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            topSeparator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            topSeparator.topAnchor.constraint(equalTo: topBar.bottomAnchor),

            // 打开主界面按钮（左侧）
            openKanbanButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 8),
            openKanbanButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            // Tab 按钮
            runningTabButton.leadingAnchor.constraint(equalTo: openKanbanButton.trailingAnchor, constant: 8),
            runningTabButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            favoritesTabButton.leadingAnchor.constraint(equalTo: runningTabButton.trailingAnchor, constant: 4),
            favoritesTabButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            // 钉住按钮（右侧）
            panelPinButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -8),
            panelPinButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            // 滚动区域（顶部栏到底部）
            scrollView.topAnchor.constraint(equalTo: topSeparator.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // contentStack 宽度跟随 scrollView
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
        ])

        // 鼠标追踪
        updateTrackingArea()

        // 从 ConfigStore 恢复上次选择的 Tab
        currentTab = QuickPanelTab(rawValue: ConfigStore.shared.lastPanelTab) ?? .running
        updateTabButtonStyles()
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
        // 面板钉住状态变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelPinStateChanged(_:)),
            name: Constants.Notifications.panelPinStateChanged,
            object: nil
        )
    }

    @objc private func windowsDidChange() {
        reloadData()
    }

    @objc private func appStatusDidChange() {
        reloadData()
    }

    @objc private func panelPinStateChanged(_ notification: Notification) {
        let isPinned = notification.userInfo?["isPinned"] as? Bool ?? false
        updatePanelPinButton(isPinned: isPinned)
    }

    private func updatePanelPinButton(isPinned: Bool) {
        let symbolName = isPinned ? "pin.fill" : "pin"
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: isPinned ? "取消钉住" : "钉住面板") {
            let configuredImage = img.withSymbolConfiguration(config) ?? img
            if isPinned {
                panelPinButton.image = Self.rotatedPinImage(from: configuredImage)
            } else {
                panelPinButton.image = configuredImage
            }
        }

        if isPinned {
            panelPinButton.contentTintColor = .systemRed
            panelPinButton.wantsLayer = true
            panelPinButton.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.15).cgColor
            panelPinButton.layer?.cornerRadius = 4
            panelPinButton.toolTip = "取消钉住"
        } else {
            panelPinButton.contentTintColor = .secondaryLabelColor
            panelPinButton.layer?.backgroundColor = nil
            panelPinButton.toolTip = "钉住面板"
        }
    }

    // MARK: - Tab 切换

    private func switchTab(_ tab: QuickPanelTab) {
        guard currentTab != tab else { return }
        currentTab = tab
        ConfigStore.shared.saveLastPanelTab(tab)
        highlightedWindowID = nil
        updateTabButtonStyles()
        lastWindowSnapshot = ""
        reloadData()
    }

    @objc private func switchToRunningTab() { switchTab(.running) }
    @objc private func switchToFavoritesTab() { switchTab(.favorites) }

    private func updateTabButtonStyles() {
        // 先全部重置为未选中样式
        for btn in [runningTabButton, favoritesTabButton] {
            btn.font = .systemFont(ofSize: 11)
            btn.contentTintColor = .secondaryLabelColor
        }
        // 设置选中 Tab 样式
        let selectedButton: NSButton
        switch currentTab {
        case .running:   selectedButton = runningTabButton
        case .favorites: selectedButton = favoritesTabButton
        }
        selectedButton.font = .systemFont(ofSize: 11, weight: .medium)
        selectedButton.contentTintColor = .controlAccentColor
    }

    // MARK: - 数据加载

    /// 重新加载面板数据（带去重，避免无意义刷新导致闪烁）
    func reloadData() {
        // 计算当前数据快照（含运行状态，确保 App 启动/退出时触发刷新）
        let windowKeys = AppMonitor.shared.runningApps.flatMap { app in
            ["\(app.bundleID):\(app.isRunning)"] + app.windows.map { "\(app.bundleID):\($0.id):\($0.title)" }
        }.joined(separator: "|")

        let favoriteKeys = ConfigStore.shared.appConfigs.map { $0.bundleID }.joined(separator: ",")
        let snapshot = "\(currentTab):\(windowKeys):\(favoriteKeys):\(highlightedWindowID ?? 0)"
        if snapshot == lastWindowSnapshot {
            return // 数据未变化，跳过刷新
        }
        lastWindowSnapshot = snapshot

        // 清空内容
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        buildContent()
        // 更新面板高度
        updatePanelSize()
    }

    /// 重置面板状态（面板关闭时调用，保留 Tab 记忆）
    func resetToNormalMode() {
        updatePanelPinButton(isPinned: false)
        highlightedWindowID = nil
        // 不重置 currentTab（Tab 记忆功能）
        collapsedApps.removeAll()
        lastWindowSnapshot = ""  // 清除快照，确保下次打开时强制刷新
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

    /// "已打开"Tab：显示有可见窗口的运行中 App
    private func buildRunningTabContent() {
        buildRunningAppList(apps: AppMonitor.shared.runningApps.filter { !$0.windows.isEmpty }, emptyText: "没有已打开窗口的应用")
    }

    /// 通用：构建运行中 App 列表（全部/已打开 Tab 共用）
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

    /// "收藏"Tab：显示收藏 App 列表（数据源来自 ConfigStore）
    private func buildFavoritesTabContent() {
        let configs = ConfigStore.shared.appConfigs
        let runningApps = AppMonitor.shared.runningApps

        if configs.isEmpty {
            addEmptyStateLabel("尚未收藏任何应用")
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

    // MARK: - 创建 App 行（全部/已打开 Tab 用）

    private func createRunningAppRow(app: RunningApp) -> NSView {
        return createAppRow(
            bundleID: app.bundleID,
            name: app.localizedName,
            icon: app.icon,
            isRunning: true,
            windows: app.windows
        )
    }

    // MARK: - 创建 App 行（收藏 Tab 用）

    private func createFavoriteAppRow(config: AppConfig, runningApp: RunningApp?, isRunning: Bool) -> NSView {
        // 未运行 App 图标：通过 urlForApplication 获取
        let icon: NSImage
        if let app = runningApp {
            icon = app.icon
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: config.bundleID) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            icon = NSImage(named: NSImage.applicationIconName)!
        }
        return createAppRow(
            bundleID: config.bundleID,
            name: config.displayName,
            icon: icon,
            isRunning: isRunning,
            windows: runningApp?.windows ?? []
        )
    }

    // MARK: - 创建 App 行（统一实现）

    private func createAppRow(bundleID: String, name: String, icon: NSImage, isRunning: Bool, windows: [WindowInfo]) -> NSView {
        let row = HoverableRowView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let rowStack = NSStackView()
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.spacing = 8
        rowStack.edgeInsets = NSEdgeInsets(top: 3, left: 12, bottom: 3, right: 12)
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(rowStack)

        NSLayoutConstraint.activate([
            rowStack.topAnchor.constraint(equalTo: row.topAnchor),
            rowStack.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            rowStack.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: Constants.Panel.appRowHeight),
        ])

        // 运行状态指示器
        let statusDot = createLabel(isRunning ? "🟢" : "⚪", size: 8, color: .labelColor)
        rowStack.addArrangedSubview(statusDot)

        // App 图标 16x16
        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = icon
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
        ])
        rowStack.addArrangedSubview(iconView)

        // App 名称
        let nameLabel = createLabel(name, size: 12, color: isRunning ? .labelColor : .tertiaryLabelColor)
        rowStack.addArrangedSubview(nameLabel)

        // 弹性空间
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        rowStack.addArrangedSubview(spacer)

        // 窗口数量 + 折叠/展开指示器（有窗口时显示）
        if !windows.isEmpty {
            let countLabel = createLabel("\(windows.count) 个窗口", size: 11, color: .secondaryLabelColor)
            rowStack.addArrangedSubview(countLabel)

            let isCollapsed = collapsedApps.contains(bundleID)
            let chevronName = isCollapsed ? "chevron.right" : "chevron.down"
            let chevronView = NSImageView()
            chevronView.translatesAutoresizingMaskIntoConstraints = false
            if let chevronImage = NSImage(systemSymbolName: chevronName, accessibilityDescription: isCollapsed ? "展开" : "折叠") {
                let symConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
                chevronView.image = chevronImage.withSymbolConfiguration(symConfig) ?? chevronImage
            }
            chevronView.contentTintColor = .secondaryLabelColor
            NSLayoutConstraint.activate([
                chevronView.widthAnchor.constraint(equalToConstant: 14),
                chevronView.heightAnchor.constraint(equalToConstant: 14),
            ])
            rowStack.addArrangedSubview(chevronView)
        }

        // 点击行为：所有运行中 App 统一为折叠/展开（窗口激活通过点击窗口行）
        row.bundleID = bundleID
        if !isRunning {
            // 未运行 App：灰度显示，点击启动
            row.alphaValue = 0.5
            row.toolTip = "点击启动"
            row.clickHandler = { [weak self] in
                self?.launchApp(bundleID: bundleID)
            }
        } else if !windows.isEmpty {
            // 运行中 App（有窗口）：点击切换折叠/展开
            row.clickHandler = { [weak self] in
                guard let self = self else { return }
                if self.collapsedApps.contains(bundleID) {
                    self.collapsedApps.remove(bundleID)
                } else {
                    self.collapsedApps.insert(bundleID)
                }
                self.lastWindowSnapshot = ""
                self.reloadData()
            }
        } else {
            // 运行中但无窗口 App：点击激活 App
            row.clickHandler = { [weak self] in
                guard let self = self else { return }
                if let runApp = AppMonitor.shared.runningApps.first(where: { $0.bundleID == bundleID }),
                   let firstWindow = runApp.windows.first {
                    self.highlightedWindowID = firstWindow.id
                    WindowService.shared.activateWindow(firstWindow)
                    self.lastWindowSnapshot = ""
                    self.reloadData()
                } else {
                    WindowService.shared.activateApp(bundleID)
                }
            }
        }

        return row
    }

    // MARK: - 创建窗口列表

    private func createWindowList(windows: [WindowInfo], bundleID: String) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Constants.Panel.windowIndent),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        // 所有窗口平铺显示（限制最多显示 maxWindowsPerApp 个）
        for windowInfo in windows.prefix(Constants.Panel.maxWindowsPerApp) {
            let windowRow = createWindowRow(windowInfo: windowInfo, bundleID: bundleID)
            stack.addArrangedSubview(windowRow)
        }

        return container
    }

    // MARK: - 创建窗口行

    private func createWindowRow(windowInfo: WindowInfo, bundleID: String) -> NSView {
        let row = HoverableRowView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.windowID = windowInfo.id
        row.windowInfo = windowInfo

        let rowStack = NSStackView()
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.spacing = 6
        rowStack.edgeInsets = NSEdgeInsets(top: 2, left: 8, bottom: 2, right: 12)
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(rowStack)

        NSLayoutConstraint.activate([
            rowStack.topAnchor.constraint(equalTo: row.topAnchor),
            rowStack.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            rowStack.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: Constants.Panel.windowRowHeight),
        ])

        // 窗口标题：优先使用自定义名称
        let renameKey = Self.renameKey(bundleID: bundleID, title: windowInfo.title)
        let customName = ConfigStore.shared.windowRenames[renameKey]
        let displayTitle: String
        if let custom = customName, !custom.isEmpty {
            displayTitle = custom
        } else {
            displayTitle = windowInfo.title.isEmpty ? "（无标题）" : windowInfo.title
        }

        let titleLabel = createLabel(displayTitle, size: 11, color: .labelColor)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.toolTip = windowInfo.title
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        rowStack.addArrangedSubview(titleLabel)

        // 弹性空间
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        rowStack.addArrangedSubview(spacer)

        // 选中高亮状态
        if highlightedWindowID == windowInfo.id {
            row.isHighlighted = true
            row.wantsLayer = true
            row.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
            row.layer?.cornerRadius = 4
        }

        // 设置右键菜单
        row.contextMenuProvider = { [weak self] in
            self?.createWindowContextMenu(bundleID: bundleID, windowInfo: windowInfo)
        }

        // 点击窗口行：高亮 + 前置窗口
        row.clickHandler = { [weak self] in
            guard let self = self else { return }
            WindowService.shared.debugLog("QuickPanel: 点击窗口行 wid=\(windowInfo.id) title=\(windowInfo.title)")
            self.highlightedWindowID = windowInfo.id
            WindowService.shared.activateWindow(windowInfo)
            // 刷新以更新高亮状态
            self.lastWindowSnapshot = ""
            self.reloadData()
        }

        return row
    }

    // MARK: - 关闭窗口

    // MARK: - 窗口右键菜单（重命名）

    private func createWindowContextMenu(bundleID: String, windowInfo: WindowInfo) -> NSMenu {
        let menu = NSMenu()

        let renameItem = NSMenuItem(title: "重命名窗口", action: #selector(handleRenameWindow(_:)), keyEquivalent: "")
        renameItem.target = self
        renameItem.representedObject = (bundleID, windowInfo)
        menu.addItem(renameItem)

        let key = Self.renameKey(bundleID: bundleID, title: windowInfo.title)
        if ConfigStore.shared.windowRenames[key] != nil {
            let clearItem = NSMenuItem(title: "清除自定义名称", action: #selector(handleClearRename(_:)), keyEquivalent: "")
            clearItem.target = self
            clearItem.representedObject = key
            menu.addItem(clearItem)
        }

        return menu
    }

    @objc private func handleRenameWindow(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? (String, WindowInfo) else { return }
        let bundleID = info.0
        let windowInfo = info.1
        let key = Self.renameKey(bundleID: bundleID, title: windowInfo.title)
        let currentName = ConfigStore.shared.windowRenames[key] ?? windowInfo.title

        let alert = NSAlert()
        alert.messageText = "重命名窗口"
        alert.informativeText = "原始标题：\(windowInfo.title)"
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        textField.stringValue = currentName
        textField.isEditable = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newName.isEmpty && newName != windowInfo.title {
                ConfigStore.shared.windowRenames[key] = newName
                ConfigStore.shared.save()
                lastWindowSnapshot = ""
                reloadData()
            } else if newName == windowInfo.title {
                ConfigStore.shared.windowRenames.removeValue(forKey: key)
                ConfigStore.shared.save()
                lastWindowSnapshot = ""
                reloadData()
            }
        }
    }

    @objc private func handleClearRename(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        ConfigStore.shared.windowRenames.removeValue(forKey: key)
        ConfigStore.shared.save()
        lastWindowSnapshot = ""
        reloadData()
    }

    // MARK: - 重命名 Key 工具方法

    static func renameKey(bundleID: String, title: String) -> String {
        return "\(bundleID)::\(title)"
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

    // MARK: - 事件处理

    @objc private func togglePanelPin() {
        if let panelWindow = window as? QuickPanelWindow {
            panelWindow.togglePanelPin()
        }
    }

    @objc private func openMainKanban() {
        NotificationCenter.default.post(name: Constants.Notifications.ballOpenMainKanban, object: nil)
    }


    /// 启动未运行的 App
    private func launchApp(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            WindowService.shared.debugLog("QuickPanel: 找不到 App URL bundleID=\(bundleID)")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
            if let error = error {
                WindowService.shared.debugLog("QuickPanel: 启动 App 失败 bundleID=\(bundleID) error=\(error)")
            } else {
                WindowService.shared.debugLog("QuickPanel: App 已启动 bundleID=\(bundleID) pid=\(app?.processIdentifier ?? -1)")
            }
        }
    }

    // MARK: - 权限引导视图

    private func createPermissionHintView() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(separator)
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])

        let lockLabel = createLabel("🔒", size: 16, color: .labelColor)
        lockLabel.alignment = .center
        stack.addArrangedSubview(lockLabel)

        let hintLabel = createLabel("需要辅助功能权限", size: 12, color: .secondaryLabelColor)
        hintLabel.alignment = .center
        stack.addArrangedSubview(hintLabel)

        let detailLabel = createLabel("窗口管理功能需要此权限才能正常工作", size: 10, color: .tertiaryLabelColor)
        detailLabel.alignment = .center
        stack.addArrangedSubview(detailLabel)

        let settingsButton = NSButton(title: "前往系统设置", target: self, action: #selector(openAccessibilitySettings))
        settingsButton.bezelStyle = .recessed
        settingsButton.controlSize = .small
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(settingsButton)

        return container
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    // MARK: - 工具方法

    /// 添加居中空状态提示文案到 contentStack
    private func addEmptyStateLabel(_ text: String) {
        let label = createLabel(text, size: 13, color: .secondaryLabelColor)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    /// 将 SF Symbol pin 图标旋转 45° 变竖直
    private static func rotatedPinImage(from image: NSImage) -> NSImage {
        let rotated = NSImage(size: image.size)
        rotated.lockFocus()
        let transform = NSAffineTransform()
        transform.translateX(by: image.size.width / 2, yBy: image.size.height / 2)
        transform.rotate(byDegrees: 45)
        transform.translateX(by: -image.size.width / 2, yBy: -image.size.height / 2)
        transform.concat()
        image.draw(in: NSRect(origin: .zero, size: image.size))
        rotated.unlockFocus()
        rotated.isTemplate = true
        return rotated
    }

    private func createLabel(_ text: String, size: CGFloat, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size)
        label.textColor = color
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
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
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
            layer?.cornerRadius = 4
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
