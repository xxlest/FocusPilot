import AppKit

// MARK: - 快捷面板内容视图
// 包含正常模式（App 列表 + 内嵌窗口列表）和置顶模式
// 底部固定操作栏，支持实时更新、钉住模式、窗口重命名

final class QuickPanelView: NSView {

    // MARK: - 模式

    enum PanelMode {
        case normal   // 正常模式：App 列表 + 窗口列表
        case pinned   // 置顶模式：已 Pin 窗口列表
    }

    private var currentMode: PanelMode = .normal

    // MARK: - 子视图

    /// 顶部栏（钉住按钮）
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

    /// 📌 面板钉住按钮（放在顶部右侧）
    private lazy var panelPinButton: NSButton = {
        let btn = NSButton(title: "📌", target: self, action: #selector(togglePanelPin))
        btn.bezelStyle = .recessed
        btn.isBordered = false
        btn.font = .systemFont(ofSize: 12)
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

    /// 底部操作栏
    private let bottomBar: NSView = {
        let view = NSView()
        view.wantsLayer = true
        return view
    }()

    /// 底部分割线
    private let bottomSeparator: NSBox = {
        let box = NSBox()
        box.boxType = .separator
        return box
    }()

    /// 📌 置顶模式按钮
    private lazy var pinModeButton: NSButton = {
        let btn = NSButton(title: "📌 置顶模式", target: self, action: #selector(togglePinMode))
        btn.bezelStyle = .recessed
        btn.isBordered = false
        btn.font = .systemFont(ofSize: 12)
        return btn
    }()

    /// ← 返回按钮（置顶模式）
    private lazy var backButton: NSButton = {
        let btn = NSButton(title: "← 返回", target: self, action: #selector(backToNormal))
        btn.bezelStyle = .recessed
        btn.isBordered = false
        btn.font = .systemFont(ofSize: 12)
        return btn
    }()

    /// 鼠标追踪区域
    private var trackingArea: NSTrackingArea?

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

        // 滚动视图
        let clipView = NSClipView()
        clipView.drawsBackground = false
        clipView.documentView = contentStack
        scrollView.contentView = clipView

        // 顶部栏
        addSubview(topBar)
        addSubview(topSeparator)
        topBar.addSubview(panelPinButton)

        addSubview(scrollView)
        addSubview(bottomSeparator)
        addSubview(bottomBar)

        // 底部操作栏布局
        bottomBar.addSubview(pinModeButton)
        bottomBar.addSubview(backButton)
        backButton.isHidden = true

        // 使用 Auto Layout
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topSeparator.translatesAutoresizingMaskIntoConstraints = false
        panelPinButton.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        bottomSeparator.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        pinModeButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.translatesAutoresizingMaskIntoConstraints = false

        let barHeight: CGFloat = Constants.Panel.bottomBarHeight
        let topBarHeight: CGFloat = 28

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

            // 钉住按钮（顶部右侧）
            panelPinButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -8),
            panelPinButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            // 底部操作栏
            bottomBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: barHeight),

            // 底部分割线
            bottomSeparator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            bottomSeparator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            bottomSeparator.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            // 滚动区域（在顶部栏和底部栏之间）
            scrollView.topAnchor.constraint(equalTo: topSeparator.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomSeparator.topAnchor),

            // contentStack 宽度跟随 scrollView
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),

            // 底部按钮布局
            pinModeButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 12),
            pinModeButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),

            backButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 12),
            backButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
        ])

        // 鼠标追踪
        updateTrackingArea()
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
        // Pin 窗口变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pinnedWindowsDidChange),
            name: PinManager.pinnedWindowsChanged,
            object: nil
        )
        // 面板钉住状态变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelPinStateChanged(_:)),
            name: NSNotification.Name("QuickPanel.pinStateChanged"),
            object: nil
        )
    }

    @objc private func windowsDidChange() {
        reloadData()
    }

    @objc private func appStatusDidChange() {
        reloadData()
    }

    @objc private func pinnedWindowsDidChange() {
        if currentMode == .pinned {
            reloadData()
        }
    }

    @objc private func panelPinStateChanged(_ notification: Notification) {
        let isPinned = notification.userInfo?["isPinned"] as? Bool ?? false
        updatePanelPinButton(isPinned: isPinned)
    }

    private func updatePanelPinButton(isPinned: Bool) {
        if isPinned {
            panelPinButton.contentTintColor = .systemBlue
            panelPinButton.wantsLayer = true
            panelPinButton.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.15).cgColor
            panelPinButton.layer?.cornerRadius = 4
            panelPinButton.toolTip = "取消钉住"
        } else {
            panelPinButton.contentTintColor = nil
            panelPinButton.layer?.backgroundColor = nil
            panelPinButton.toolTip = "钉住面板"
        }
    }

    // MARK: - 数据加载

    /// 重新加载面板数据
    func reloadData() {
        // 清空内容
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        switch currentMode {
        case .normal:
            buildNormalMode()
        case .pinned:
            buildPinnedMode()
        }

        // 更新面板高度
        updatePanelSize()
    }

    /// 重置为正常模式
    func resetToNormalMode() {
        currentMode = .normal
        updatePanelPinButton(isPinned: false)
        updateBottomBarForMode()
    }

    // MARK: - 正常模式

    private func buildNormalMode() {
        let configs = ConfigStore.shared.appConfigs
        let runningApps = AppMonitor.shared.runningApps

        // 空状态
        if configs.isEmpty {
            let emptyLabel = createLabel("点击悬浮球配置应用", size: 13, color: .secondaryLabelColor)
            emptyLabel.alignment = .center
            contentStack.addArrangedSubview(emptyLabel)
            return
        }

        // 按配置顺序遍历 App（最多 8 个）
        for config in configs.prefix(Constants.Panel.maxApps) {
            // 查找运行状态
            let running = runningApps.first(where: { $0.bundleID == config.bundleID })
            let isRunning = running?.isRunning ?? false

            // App 行
            let appRow = createAppRow(config: config, runningApp: running, isRunning: isRunning)
            contentStack.addArrangedSubview(appRow)

            // 多窗口 App：内嵌展开窗口列表
            if let app = running, app.windows.count > 1 {
                let windowList = createWindowList(windows: app.windows, bundleID: config.bundleID, keywords: config.pinnedKeywords)
                contentStack.addArrangedSubview(windowList)
            }
        }
    }

    // MARK: - 创建 App 行

    private func createAppRow(config: AppConfig, runningApp: RunningApp?, isRunning: Bool) -> NSView {
        let row = HoverableRowView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let rowStack = NSStackView()
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.spacing = 8
        rowStack.edgeInsets = NSEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
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

        // App 图标 20x20
        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let app = runningApp {
            iconView.image = app.icon
        } else {
            iconView.image = NSWorkspace.shared.icon(forFile: "/Applications")
        }
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
        ])
        rowStack.addArrangedSubview(iconView)

        // App 名称
        let nameLabel = createLabel(config.displayName, size: 13, color: isRunning ? .labelColor : .tertiaryLabelColor)
        rowStack.addArrangedSubview(nameLabel)

        // 弹性空间
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        rowStack.addArrangedSubview(spacer)

        // 窗口数量（多窗口时显示）
        if let app = runningApp, app.windows.count > 1 {
            let countLabel = createLabel("\(app.windows.count) 个窗口", size: 11, color: .secondaryLabelColor)
            rowStack.addArrangedSubview(countLabel)
        }

        // 未运行 App 灰度显示
        if !isRunning {
            row.alphaValue = 0.5
            row.toolTip = "未运行"
        } else if let app = runningApp, app.windows.count <= 1 {
            // 单窗口 App：点击直接切换
            let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleAppClick(_:)))
            row.addGestureRecognizer(clickGesture)
            row.bundleID = config.bundleID
        }

        return row
    }

    // MARK: - 创建窗口列表

    private func createWindowList(windows: [WindowInfo], bundleID: String, keywords: [String]) -> NSView {
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

        // 按关键词分区排序
        let (pinnedWindows, normalWindows) = categorizeWindows(windows, keywords: keywords)

        // 置顶区
        for windowInfo in pinnedWindows {
            let windowRow = createWindowRow(windowInfo: windowInfo, bundleID: bundleID, isPinnedSection: true)
            stack.addArrangedSubview(windowRow)
        }

        // 分割线（仅在有置顶区时显示）
        if !pinnedWindows.isEmpty && !normalWindows.isEmpty {
            let separator = NSBox()
            separator.boxType = .separator
            separator.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(separator)
            NSLayoutConstraint.activate([
                separator.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
                separator.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -12),
            ])
        }

        // 普通区
        for windowInfo in normalWindows {
            let windowRow = createWindowRow(windowInfo: windowInfo, bundleID: bundleID, isPinnedSection: false)
            stack.addArrangedSubview(windowRow)
        }

        return container
    }

    // MARK: - 创建窗口行

    private func createWindowRow(windowInfo: WindowInfo, bundleID: String, isPinnedSection: Bool) -> NSView {
        let row = HoverableRowView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.windowID = windowInfo.id
        row.windowInfo = windowInfo

        let rowStack = NSStackView()
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.spacing = 6
        rowStack.edgeInsets = NSEdgeInsets(top: 3, left: 8, bottom: 3, right: 12)
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(rowStack)

        NSLayoutConstraint.activate([
            rowStack.topAnchor.constraint(equalTo: row.topAnchor),
            rowStack.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            rowStack.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: Constants.Panel.windowRowHeight),
        ])

        // ★ 标识（置顶区窗口）
        if isPinnedSection {
            let starLabel = createLabel("★", size: 11, color: .systemYellow)
            rowStack.addArrangedSubview(starLabel)
        }

        // 窗口标题：优先使用自定义名称
        let renameKey = Self.renameKey(bundleID: bundleID, title: windowInfo.title)
        let customName = ConfigStore.shared.windowRenames[renameKey]
        let displayTitle: String
        if let custom = customName, !custom.isEmpty {
            displayTitle = custom
        } else {
            displayTitle = windowInfo.title.isEmpty ? "（无标题）" : windowInfo.title
        }

        let titleLabel = createLabel(displayTitle, size: 12, color: .labelColor)
        titleLabel.lineBreakMode = .byTruncatingTail
        // tooltip 始终显示原始标题
        titleLabel.toolTip = windowInfo.title
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        rowStack.addArrangedSubview(titleLabel)

        // 弹性空间
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        rowStack.addArrangedSubview(spacer)

        // 设置右键菜单
        row.contextMenuProvider = { [weak self] in
            self?.createWindowContextMenu(bundleID: bundleID, windowInfo: windowInfo)
        }

        // 点击窗口条目：激活该窗口
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleWindowClick(_:)))
        row.addGestureRecognizer(clickGesture)

        return row
    }

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

        // 弹出重命名对话框
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

        // 让 textField 获取焦点
        alert.window.initialFirstResponder = textField

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newName.isEmpty && newName != windowInfo.title {
                ConfigStore.shared.windowRenames[key] = newName
                ConfigStore.shared.save()
                reloadData()
            } else if newName == windowInfo.title {
                // 如果名称等于原始标题，清除自定义名称
                ConfigStore.shared.windowRenames.removeValue(forKey: key)
                ConfigStore.shared.save()
                reloadData()
            }
        }
    }

    @objc private func handleClearRename(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        ConfigStore.shared.windowRenames.removeValue(forKey: key)
        ConfigStore.shared.save()
        reloadData()
    }

    // MARK: - 重命名 Key 工具方法

    static func renameKey(bundleID: String, title: String) -> String {
        return "\(bundleID)::\(title)"
    }

    // MARK: - 关键词匹配与分区

    /// 按关键词将窗口分为置顶区和普通区
    private func categorizeWindows(_ windows: [WindowInfo], keywords: [String]) -> (pinned: [WindowInfo], normal: [WindowInfo]) {
        guard !keywords.isEmpty else {
            return ([], windows)
        }

        var pinnedWithIndex: [(window: WindowInfo, keywordIndex: Int)] = []
        var normal: [WindowInfo] = []

        for window in windows {
            var matched = false
            for (index, keyword) in keywords.enumerated() {
                if window.title.localizedCaseInsensitiveContains(keyword) {
                    pinnedWithIndex.append((window, index))
                    matched = true
                    break // 只取第一个命中的关键词
                }
            }
            if !matched {
                normal.append(window)
            }
        }

        // 置顶区按关键词配置顺序排列
        let pinned = pinnedWithIndex.sorted(by: { $0.keywordIndex < $1.keywordIndex }).map(\.window)

        return (pinned, normal)
    }

    // MARK: - 置顶模式

    private func buildPinnedMode() {
        let pinnedWindows = PinManager.shared.pinnedWindows

        // 空状态
        if pinnedWindows.isEmpty {
            let emptyLabel = createLabel("暂无置顶窗口", size: 13, color: .secondaryLabelColor)
            emptyLabel.alignment = .center
            contentStack.addArrangedSubview(emptyLabel)
        } else {
            // 已 Pin 窗口列表
            for pinned in pinnedWindows {
                let row = createPinnedWindowRow(pinned)
                contentStack.addArrangedSubview(row)
            }
        }
    }

    /// 创建已 Pin 窗口行
    private func createPinnedWindowRow(_ pinned: PinnedWindow) -> NSView {
        let row = HoverableRowView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let rowStack = NSStackView()
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.spacing = 8
        rowStack.edgeInsets = NSEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(rowStack)

        NSLayoutConstraint.activate([
            rowStack.topAnchor.constraint(equalTo: row.topAnchor),
            rowStack.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            rowStack.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: Constants.Panel.appRowHeight),
        ])

        let pinIcon = createLabel("📌", size: 12, color: .labelColor)
        rowStack.addArrangedSubview(pinIcon)

        let titleLabel = createLabel(pinned.title, size: 13, color: .labelColor)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.toolTip = pinned.title
        rowStack.addArrangedSubview(titleLabel)

        // 点击切换到该窗口
        let windowInfo = WindowInfo(
            id: pinned.id,
            ownerBundleID: pinned.ownerBundleID,
            ownerPID: pinned.ownerPID,
            title: pinned.title,
            bounds: .zero,
            isMinimized: false,
            isFullScreen: false
        )
        row.windowInfo = windowInfo
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleWindowClick(_:)))
        row.addGestureRecognizer(clickGesture)

        return row
    }

    // MARK: - 底部操作栏模式切换

    private func updateBottomBarForMode() {
        switch currentMode {
        case .normal:
            pinModeButton.isHidden = false
            backButton.isHidden = true
        case .pinned:
            pinModeButton.isHidden = true
            backButton.isHidden = false
        }
    }

    // MARK: - 面板高度计算

    private func updatePanelSize() {
        guard let panelWindow = window else { return }
        guard let screen = panelWindow.screen ?? NSScreen.main else { return }

        // 计算内容高度（顶部栏 28 + 分割线 1 + 内容 + 分割线 1 + 底部栏）
        contentStack.layoutSubtreeIfNeeded()
        let contentHeight = contentStack.fittingSize.height
        let totalHeight = contentHeight + Constants.Panel.bottomBarHeight + 28 + 4 // 顶部栏+分割线

        // 限制最大高度：取屏幕 60% 和记忆高度的较大值
        let maxHeight = screen.visibleFrame.height * Constants.Panel.maxHeightRatio
        let savedHeight = ConfigStore.shared.panelSize.height
        let heightLimit = min(max(savedHeight, Constants.Panel.minHeight), maxHeight)
        let finalHeight = min(totalHeight, heightLimit)
        let clampedHeight = max(finalHeight, Constants.Panel.minHeight)

        // 更新窗口大小（保持原点不变）
        var frame = panelWindow.frame
        let heightDiff = clampedHeight - frame.height
        frame.size.height = clampedHeight
        frame.origin.y -= heightDiff
        panelWindow.setFrame(frame, display: true)
    }

    // MARK: - 事件处理

    @objc private func togglePinMode() {
        currentMode = .pinned
        updateBottomBarForMode()
        reloadData()
    }

    @objc private func backToNormal() {
        currentMode = .normal
        updateBottomBarForMode()
        reloadData()
    }

    @objc private func togglePanelPin() {
        if let panelWindow = window as? QuickPanelWindow {
            panelWindow.togglePanelPin()
        }
    }

    @objc private func handleAppClick(_ gesture: NSClickGestureRecognizer) {
        guard let row = gesture.view as? HoverableRowView,
              let bundleID = row.bundleID else { return }
        WindowService.shared.activateApp(bundleID)
        // 钉住模式下不收起面板
        if let panelWindow = window as? QuickPanelWindow, panelWindow.isPanelPinned {
            return
        }
        // 收起面板
        if let panelWindow = window as? QuickPanelWindow {
            panelWindow.hide()
        }
    }

    @objc private func handleWindowClick(_ gesture: NSClickGestureRecognizer) {
        guard let row = gesture.view as? HoverableRowView,
              let windowInfo = row.windowInfo else { return }
        WindowService.shared.activateWindow(windowInfo)
        // 钉住模式下不收起面板
        if let panelWindow = window as? QuickPanelWindow, panelWindow.isPanelPinned {
            return
        }
        // 收起面板
        if let panelWindow = window as? QuickPanelWindow {
            panelWindow.hide()
        }
    }

    // MARK: - 工具方法

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

    private var trackingArea: NSTrackingArea?
    private var isHovered = false

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
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        layer?.cornerRadius = 4
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        layer?.backgroundColor = nil
    }

    // MARK: - 右键菜单

    override func menu(for event: NSEvent) -> NSMenu? {
        return contextMenuProvider?() ?? super.menu(for: event)
    }
}
