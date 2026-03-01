import AppKit

// MARK: - 快捷面板内容视图
// App 列表 + 内嵌窗口列表，每个窗口行前面有置顶切换按钮
// 支持实时更新、钉住模式、窗口重命名

final class QuickPanelView: NSView {

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

    /// 打开主界面按钮（放在顶部左侧）
    private lazy var openKanbanButton: NSButton = {
        let btn = NSButton()
        btn.bezelStyle = .recessed
        btn.isBordered = false
        if let img = NSImage(systemSymbolName: "macwindow", accessibilityDescription: "打开主界面") {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            btn.image = img.withSymbolConfiguration(config) ?? img
        }
        btn.contentTintColor = .secondaryLabelColor
        btn.toolTip = "打开主界面"
        btn.target = self
        btn.action = #selector(openMainKanban)
        return btn
    }()

    /// 置顶过滤按钮（放在顶部中间偏右）
    private lazy var pinFilterButton: NSButton = {
        let btn = NSButton()
        btn.bezelStyle = .recessed
        btn.isBordered = false
        if let img = NSImage(systemSymbolName: "line.3.horizontal.decrease.circle", accessibilityDescription: "过滤置顶窗口") {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            btn.image = img.withSymbolConfiguration(config) ?? img
        }
        btn.contentTintColor = .secondaryLabelColor
        btn.toolTip = "仅显示置顶窗口"
        btn.target = self
        btn.action = #selector(togglePinFilter)
        return btn
    }()

    /// 标题标签（显示当前模式：全部窗口 / 置顶窗口）
    private let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// 面板钉住按钮（放在顶部右侧，SF Symbol pin 图标）
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

    /// 多窗口 App 折叠状态（按 bundleID 跟踪）
    private var collapsedApps: Set<String> = []

    /// 置顶过滤模式：仅显示已 Pin 的窗口和对应 App
    private var isFilteringPinned = false

    /// 上次刷新时的 Pin 窗口 ID 快照（防止无意义刷新）
    private var lastPinnedSnapshot: [CGWindowID] = []
    /// 上次刷新时的窗口数据快照
    private var lastWindowSnapshot: String = ""

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

        // 滚动视图（使用翻转的 ClipView 确保内容从顶部开始显示）
        let clipView = FlippedClipView()
        clipView.drawsBackground = false
        clipView.documentView = contentStack
        scrollView.contentView = clipView

        // 顶部栏
        addSubview(topBar)
        addSubview(topSeparator)
        topBar.addSubview(openKanbanButton)
        topBar.addSubview(titleLabel)
        topBar.addSubview(pinFilterButton)
        topBar.addSubview(panelPinButton)

        addSubview(scrollView)

        // 使用 Auto Layout
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topSeparator.translatesAutoresizingMaskIntoConstraints = false
        openKanbanButton.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        pinFilterButton.translatesAutoresizingMaskIntoConstraints = false
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

            // 打开主界面按钮（顶部左侧）
            openKanbanButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 8),
            openKanbanButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            // 标题标签（居中）
            titleLabel.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            // 置顶过滤按钮（钉住按钮左边）
            pinFilterButton.trailingAnchor.constraint(equalTo: panelPinButton.leadingAnchor, constant: -4),
            pinFilterButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            // 钉住按钮（顶部右侧）
            panelPinButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -8),
            panelPinButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            // 滚动区域（在顶部栏和视图底部之间）
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
        reloadData()  // 始终刷新，因为置顶按钮状态需要更新
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
                // 已钉住时旋转图标为竖直（与窗口 Pin 图标旋转逻辑一致）
                let rotatedImage = NSImage(size: configuredImage.size)
                rotatedImage.lockFocus()
                let transform = NSAffineTransform()
                transform.translateX(by: configuredImage.size.width / 2, yBy: configuredImage.size.height / 2)
                transform.rotate(byDegrees: 45)
                transform.translateX(by: -configuredImage.size.width / 2, yBy: -configuredImage.size.height / 2)
                transform.concat()
                configuredImage.draw(in: NSRect(origin: .zero, size: configuredImage.size))
                rotatedImage.unlockFocus()
                rotatedImage.isTemplate = true
                panelPinButton.image = rotatedImage
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

    // MARK: - 数据加载

    /// 重新加载面板数据（带去重，避免无意义刷新导致闪烁）
    func reloadData() {
        // 计算当前数据快照
        let pinnedIDs = PinManager.shared.pinnedWindows.map { $0.id }
        let windowKeys = AppMonitor.shared.runningApps.flatMap { app in
            app.windows.map { "\(app.bundleID):\($0.id):\($0.title)" }
        }.joined(separator: "|")

        let snapshot = "\(isFilteringPinned):\(pinnedIDs):\(windowKeys)"
        if snapshot == lastWindowSnapshot {
            return // 数据未变化，跳过刷新
        }
        lastWindowSnapshot = snapshot

        // 清空内容
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        buildNormalMode()
        // 更新面板高度
        updatePanelSize()
    }

    /// 重置面板状态
    func resetToNormalMode() {
        updatePanelPinButton(isPinned: false)
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

        // 置顶过滤模式：仅显示有 Pin 窗口的 App 和对应的 Pin 窗口
        if isFilteringPinned {
            let pinnedWindows = PinManager.shared.pinnedWindows
            if pinnedWindows.isEmpty {
                let emptyLabel = createLabel("暂无置顶窗口", size: 13, color: .secondaryLabelColor)
                emptyLabel.alignment = .center
                contentStack.addArrangedSubview(emptyLabel)
                return
            }

            // 按 App 分组 Pin 窗口
            var pinnedByApp: [String: [PinnedWindow]] = [:]
            for pinned in pinnedWindows {
                pinnedByApp[pinned.ownerBundleID, default: []].append(pinned)
            }

            for (bundleID, appPinnedWindows) in pinnedByApp {
                // 显示 App 行
                let config = configs.first(where: { $0.bundleID == bundleID })
                let running = runningApps.first(where: { $0.bundleID == bundleID })
                let displayName = config?.displayName ?? running?.localizedName ?? bundleID
                let tempConfig = AppConfig(bundleID: bundleID, displayName: displayName, order: 0, pinnedKeywords: [])
                let appRow = createAppRow(config: tempConfig, runningApp: running, isRunning: running?.isRunning ?? false)
                contentStack.addArrangedSubview(appRow)

                // 显示该 App 下的 Pin 窗口
                if let app = running {
                    let pinnedIDs = Set(appPinnedWindows.map { $0.id })
                    let pinnedWindowInfos = app.windows.filter { pinnedIDs.contains($0.id) }
                    if !pinnedWindowInfos.isEmpty {
                        let windowList = createWindowList(windows: pinnedWindowInfos, bundleID: bundleID, keywords: [])
                        contentStack.addArrangedSubview(windowList)
                    }
                }
            }
            return
        }

        // 正常模式：按配置顺序遍历 App（最多 8 个）
        for config in configs.prefix(Constants.Panel.maxApps) {
            // 查找运行状态
            let running = runningApps.first(where: { $0.bundleID == config.bundleID })
            let isRunning = running?.isRunning ?? false

            // App 行
            let appRow = createAppRow(config: config, runningApp: running, isRunning: isRunning)
            contentStack.addArrangedSubview(appRow)

            // 窗口列表：有窗口时显示（多窗口折叠状态下不显示）
            if let app = running, !app.windows.isEmpty,
               !(app.windows.count > 1 && collapsedApps.contains(config.bundleID)) {
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
        if let app = runningApp {
            iconView.image = app.icon
        } else {
            iconView.image = NSWorkspace.shared.icon(forFile: "/Applications")
        }
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
        ])
        rowStack.addArrangedSubview(iconView)

        // App 名称
        let nameLabel = createLabel(config.displayName, size: 12, color: isRunning ? .labelColor : .tertiaryLabelColor)
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

            // 折叠/展开 chevron 指示器
            let isCollapsed = collapsedApps.contains(config.bundleID)
            let chevronName = isCollapsed ? "chevron.right" : "chevron.down"
            let chevronView = NSImageView()
            chevronView.translatesAutoresizingMaskIntoConstraints = false
            if let chevronImage = NSImage(systemSymbolName: chevronName, accessibilityDescription: isCollapsed ? "展开" : "折叠") {
                let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
                chevronView.image = chevronImage.withSymbolConfiguration(config) ?? chevronImage
            }
            chevronView.contentTintColor = .secondaryLabelColor
            NSLayoutConstraint.activate([
                chevronView.widthAnchor.constraint(equalToConstant: 14),
                chevronView.heightAnchor.constraint(equalToConstant: 14),
            ])
            rowStack.addArrangedSubview(chevronView)
        }

        // 未运行 App 灰度显示
        if !isRunning {
            row.alphaValue = 0.5
            row.toolTip = "未运行"
        } else if let app = runningApp, app.windows.count > 1 {
            // 多窗口 App：点击切换折叠/展开
            let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleAppToggleCollapse(_:)))
            row.addGestureRecognizer(clickGesture)
            row.bundleID = config.bundleID
        } else {
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

        // 第一优先级：按 Pin 状态分组（已 Pin 窗口排最前）
        let pinnedByPin = windows.filter { PinManager.shared.isPinned($0.id) }
        let unpinnedByPin = windows.filter { !PinManager.shared.isPinned($0.id) }

        // 已 Pin 窗口直接渲染（不再按关键词分区）
        for windowInfo in pinnedByPin {
            let windowRow = createWindowRow(windowInfo: windowInfo, bundleID: bundleID, isPinnedSection: false)
            stack.addArrangedSubview(windowRow)
        }

        // Pin 区与非 Pin 区之间的分割线
        if !pinnedByPin.isEmpty && !unpinnedByPin.isEmpty {
            let pinSeparator = NSBox()
            pinSeparator.boxType = .separator
            pinSeparator.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(pinSeparator)
            NSLayoutConstraint.activate([
                pinSeparator.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
                pinSeparator.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -12),
            ])
        }

        // 未 Pin 窗口按关键词分区排序
        let (keywordPinned, normalWindows) = categorizeWindows(unpinnedByPin, keywords: keywords)

        // 关键词置顶区
        for windowInfo in keywordPinned {
            let windowRow = createWindowRow(windowInfo: windowInfo, bundleID: bundleID, isPinnedSection: true)
            stack.addArrangedSubview(windowRow)
        }

        // 关键词置顶区和普通区之间的分割线
        if !keywordPinned.isEmpty && !normalWindows.isEmpty {
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

        // 置顶切换按钮（最前面）
        let pinButton = NSButton()
        pinButton.bezelStyle = .inline
        pinButton.isBordered = false
        let isPinned = PinManager.shared.isPinned(windowInfo.id)
        let pinSymbolName = isPinned ? "pin.fill" : "pin"
        let pinColor: NSColor = isPinned ? .systemRed : .tertiaryLabelColor
        if let pinImage = NSImage(systemSymbolName: pinSymbolName, accessibilityDescription: "置顶") {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
            let configuredImage = pinImage.withSymbolConfiguration(config) ?? pinImage
            if isPinned {
                // 已钉住时旋转图标为竖直（SF Symbol pin 默认倾斜 45°，逆时针旋转 45° 变竖直）
                let rotatedImage = NSImage(size: configuredImage.size)
                rotatedImage.lockFocus()
                let transform = NSAffineTransform()
                transform.translateX(by: configuredImage.size.width / 2, yBy: configuredImage.size.height / 2)
                transform.rotate(byDegrees: 45)
                transform.translateX(by: -configuredImage.size.width / 2, yBy: -configuredImage.size.height / 2)
                transform.concat()
                configuredImage.draw(in: NSRect(origin: .zero, size: configuredImage.size))
                rotatedImage.unlockFocus()
                rotatedImage.isTemplate = true
                pinButton.image = rotatedImage
            } else {
                pinButton.image = configuredImage
            }
        }
        pinButton.contentTintColor = pinColor
        pinButton.target = self
        pinButton.action = #selector(handlePinToggle(_:))
        pinButton.tag = Int(windowInfo.id)
        pinButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pinButton.widthAnchor.constraint(equalToConstant: 20),
            pinButton.heightAnchor.constraint(equalToConstant: 20),
        ])
        rowStack.addArrangedSubview(pinButton)

        // ★ 标识（关键词匹配置顶区窗口）
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

        let titleLabel = createLabel(displayTitle, size: 11, color: .labelColor)
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

        // 点击窗口条目：激活该窗口（通过 clickHandler，避免手势识别器拦截按钮点击）
        row.clickHandler = { [weak self] in
            guard let self = self else { return }
            WindowService.shared.activateWindow(windowInfo)
            // 钉住模式下不收起面板
            if let panelWindow = self.window as? QuickPanelWindow, panelWindow.isPanelPinned {
                return
            }
            if let panelWindow = self.window as? QuickPanelWindow {
                panelWindow.hide()
            }
        }

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

    /// 按关键词将窗口分为置顶区和普通区（保持原始 z-order 不重排）
    private func categorizeWindows(_ windows: [WindowInfo], keywords: [String]) -> (pinned: [WindowInfo], normal: [WindowInfo]) {
        guard !keywords.isEmpty else {
            return ([], windows)
        }

        var pinned: [WindowInfo] = []
        var normal: [WindowInfo] = []

        for window in windows {
            var matched = false
            for keyword in keywords {
                if window.title.localizedCaseInsensitiveContains(keyword) {
                    pinned.append(window)
                    matched = true
                    break // 只取第一个命中的关键词
                }
            }
            if !matched {
                normal.append(window)
            }
        }

        // 保持原始 z-order（CGWindowList 返回的顺序即为屏幕显示顺序）
        return (pinned, normal)
    }

    // MARK: - 面板高度计算

    private func updatePanelSize() {
        guard let panelWindow = window else { return }
        guard let screen = panelWindow.screen ?? NSScreen.main else { return }

        // 计算内容高度（顶部栏 24 + 分割线 1 + 内容）
        contentStack.layoutSubtreeIfNeeded()
        let contentHeight = contentStack.fittingSize.height
        let totalHeight = contentHeight + 24 + 4 // 顶部栏+分割线

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

    @objc private func handlePinToggle(_ sender: NSButton) {
        let windowID = CGWindowID(sender.tag)
        // 从 sender 的父视图链中找到 HoverableRowView
        guard let rowStack = sender.superview as? NSStackView,
              let row = rowStack.superview as? HoverableRowView,
              let windowInfo = row.windowInfo else { return }

        if PinManager.shared.isPinned(windowID) {
            PinManager.shared.unpin(windowID: windowID)
        } else {
            let success = PinManager.shared.pin(window: windowInfo)
            if success {
                // Pin 成功后激活该窗口，确保窗口实际排到最前
                WindowService.shared.activateWindow(windowInfo)
            } else if PinManager.shared.pinnedCount >= Constants.maxPinnedWindows {
                showToast("最多置顶 \(Constants.maxPinnedWindows) 个窗口")
            }
        }
        // Pin 状态变化会通过通知触发 reloadData
    }

    // MARK: - Toast 提示

    /// 在快捷面板顶部居中显示临时 Toast 提示
    private func showToast(_ message: String) {
        guard let panelWindow = window else { return }

        let toast = NSTextField(labelWithString: message)
        toast.font = .systemFont(ofSize: 12, weight: .medium)
        toast.textColor = .white
        toast.alignment = .center
        toast.isBezeled = false
        toast.isEditable = false
        toast.drawsBackground = false
        toast.wantsLayer = true
        toast.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        toast.layer?.cornerRadius = 6

        // 计算尺寸
        let textSize = toast.fittingSize
        let padding: CGFloat = 16
        let toastWidth = textSize.width + padding * 2
        let toastHeight = textSize.height + 8
        let panelWidth = panelWindow.frame.width
        toast.frame = NSRect(
            x: (panelWidth - toastWidth) / 2,
            y: bounds.height - toastHeight - 28, // 顶部栏下方
            width: toastWidth,
            height: toastHeight
        )

        addSubview(toast)

        // 2 秒后淡出移除
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                toast.animator().alphaValue = 0
            }, completionHandler: {
                toast.removeFromSuperview()
            })
        }
    }

    @objc private func togglePinFilter() {
        isFilteringPinned.toggle()
        updatePinFilterButton()
        reloadData()
    }

    private func updatePinFilterButton() {
        let symbolName = isFilteringPinned ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: isFilteringPinned ? "显示全部" : "过滤置顶窗口") {
            pinFilterButton.image = img.withSymbolConfiguration(config) ?? img
        }
        if isFilteringPinned {
            pinFilterButton.contentTintColor = .systemRed
            pinFilterButton.wantsLayer = true
            pinFilterButton.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.15).cgColor
            pinFilterButton.layer?.cornerRadius = 4
            pinFilterButton.toolTip = "显示全部窗口"
            // 更新标题标签
            titleLabel.stringValue = "置顶窗口"
            titleLabel.textColor = .systemRed
        } else {
            pinFilterButton.contentTintColor = .secondaryLabelColor
            pinFilterButton.layer?.backgroundColor = nil
            pinFilterButton.toolTip = "仅显示置顶窗口"
            // 更新标题标签
            titleLabel.stringValue = ""
            titleLabel.textColor = .secondaryLabelColor
        }
    }

    @objc private func togglePanelPin() {
        if let panelWindow = window as? QuickPanelWindow {
            panelWindow.togglePanelPin()
        }
    }

    @objc private func openMainKanban() {
        NotificationCenter.default.post(name: NSNotification.Name("FloatingBall.openMainKanban"), object: nil)
    }

    @objc private func handleAppToggleCollapse(_ gesture: NSClickGestureRecognizer) {
        guard let row = gesture.view as? HoverableRowView,
              let bundleID = row.bundleID else { return }
        if collapsedApps.contains(bundleID) {
            collapsedApps.remove(bundleID)
        } else {
            collapsedApps.insert(bundleID)
        }
        // 同时激活该应用
        WindowService.shared.activateApp(bundleID)
        reloadData()
    }

    @objc private func handleAppClick(_ gesture: NSClickGestureRecognizer) {
        guard let row = gesture.view as? HoverableRowView,
              let bundleID = row.bundleID else { return }
        // 单窗口 App：直接激活具体窗口（而不仅仅激活 App），确保 Electron 等应用窗口能正确前置
        if let app = AppMonitor.shared.runningApps.first(where: { $0.bundleID == bundleID }),
           let firstWindow = app.windows.first {
            WindowService.shared.activateWindow(firstWindow)
        } else {
            WindowService.shared.activateApp(bundleID)
        }
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
    /// 点击处理闭包（用于窗口行点击，避免手势识别器拦截内部按钮）
    var clickHandler: (() -> Void)?

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

    // MARK: - 点击处理（优先让内部 NSButton 处理，其余区域触发 clickHandler）

    override func mouseUp(with event: NSEvent) {
        // 检查点击位置是否在 NSButton 上（让按钮自己处理点击）
        let location = convert(event.locationInWindow, from: nil)
        if let hitView = hitTest(location), hitView is NSButton || hitView.superview is NSButton {
            super.mouseUp(with: event)
            return
        }
        // 非按钮区域：触发行点击处理
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
