import AppKit
import ObjectiveC

// MARK: - 行视图构建（extension QuickPanelView）
// 从 QuickPanelView 主文件提取的行构建逻辑，包括 App 行、窗口行、权限引导视图、工具方法

extension QuickPanelView {

    // MARK: - SF Symbol 缓存

    /// SF Symbol 图片缓存（避免重复创建相同配置的图片）
    static var symbolCache: [String: NSImage] = [:]

    static func cachedSymbol(name: String, size: CGFloat, weight: NSFont.Weight) -> NSImage? {
        let key = "\(name)-\(Int(size))-\(Int(weight.rawValue * 100))"
        if let cached = symbolCache[key] { return cached }
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        let configured = img.withSymbolConfiguration(config) ?? img
        symbolCache[key] = configured
        return configured
    }

    // MARK: - 工具方法

    /// 创建文本标签
    func createLabel(_ text: String, size: CGFloat, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size)
        label.textColor = color
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    /// 创建弹性空间视图（P3-#6：提取重复的 spacer 创建逻辑）
    func createSpacer() -> NSView {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return spacer
    }

    /// 添加居中空状态提示文案到 contentStack
    func addEmptyStateLabel(_ text: String) {
        let label = createLabel(text, size: 13, color: ConfigStore.shared.currentThemeColors.nsTextSecondary)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    // MARK: - 创建 App 行（活跃 Tab 用）

    func createRunningAppRow(app: RunningApp) -> NSView {
        let row = createAppRow(
            bundleID: app.bundleID,
            name: app.localizedName,
            icon: app.icon,
            isRunning: true,
            windows: app.windows
        )

        // 右键菜单：关闭应用
        if let hoverRow = row as? HoverableRowView {
            let bundleID = app.bundleID
            hoverRow.contextMenuProvider = { [weak self] in
                self?.createRunningAppContextMenu(bundleID: bundleID)
            }
        }

        return row
    }

    // MARK: - 创建 App 行（关注 Tab 用）

    func createFavoriteAppRow(config: AppConfig, runningApp: RunningApp?, isRunning: Bool) -> NSView {
        // 未运行 App 图标：通过 urlForApplication 获取
        let icon: NSImage
        if let app = runningApp {
            icon = app.icon
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: config.bundleID) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            icon = NSImage(named: NSImage.applicationIconName)!
        }
        let row = createAppRow(
            bundleID: config.bundleID,
            name: config.displayName,
            icon: icon,
            isRunning: isRunning,
            windows: runningApp?.windows ?? []
        )

        // 右键菜单：置顶、取消关注
        if let hoverRow = row as? HoverableRowView {
            let bundleID = config.bundleID
            hoverRow.contextMenuProvider = { [weak self] in
                self?.createFavoriteContextMenu(bundleID: bundleID, isRunning: isRunning)
            }
        }

        return row
    }

    // MARK: - 创建 App 行（统一实现）

    func createAppRow(bundleID: String, name: String, icon: NSImage, isRunning: Bool, windows: [WindowInfo]) -> NSView {
        let colors = ConfigStore.shared.currentThemeColors
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

        // 星号关注按钮（仅活跃 Tab 显示，位于最左侧）
        if currentTab == .running {
            let isFav = ConfigStore.shared.isFavorite(bundleID)
            let starButton = NSButton()
            starButton.bezelStyle = .recessed
            starButton.isBordered = false
            starButton.image = Self.cachedSymbol(name: isFav ? "star.fill" : "star", size: 11, weight: .regular)
            starButton.contentTintColor = isFav ? colors.nsFavoriteStar : colors.nsTextTertiary
            starButton.toolTip = isFav ? "取消关注" : "添加到关注"
            starButton.target = self
            starButton.action = #selector(handleToggleFavorite(_:))
            objc_setAssociatedObject(starButton, &bundleIDKey, bundleID, .OBJC_ASSOCIATION_RETAIN)
            objc_setAssociatedObject(starButton, &displayNameKey, name, .OBJC_ASSOCIATION_RETAIN)
            starButton.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                starButton.widthAnchor.constraint(equalToConstant: 18),
                starButton.heightAnchor.constraint(equalToConstant: 18),
            ])
            rowStack.addArrangedSubview(starButton)
        }

        // 运行状态指示器（6px 圆点 + 运行中带外发光效果）
        let statusDotView = NSView()
        statusDotView.wantsLayer = true
        statusDotView.layer?.cornerRadius = 3
        statusDotView.layer?.backgroundColor = (isRunning ? colors.nsAccent : colors.nsTextTertiary.withAlphaComponent(0.3)).cgColor
        if isRunning {
            statusDotView.layer?.shadowColor = colors.nsAccent.cgColor
            statusDotView.layer?.shadowRadius = 3
            statusDotView.layer?.shadowOpacity = 0.5
            statusDotView.layer?.shadowOffset = .zero
        }
        statusDotView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusDotView.widthAnchor.constraint(equalToConstant: 6),
            statusDotView.heightAnchor.constraint(equalToConstant: 6),
        ])
        rowStack.addArrangedSubview(statusDotView)

        // App 图标 20x20（圆角 4px）
        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = icon
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 5
        iconView.layer?.masksToBounds = true
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
        ])
        rowStack.addArrangedSubview(iconView)

        // App 名称
        let nameLabel = createLabel(name, size: 12, color: isRunning ? colors.nsTextPrimary : colors.nsTextTertiary)
        rowStack.addArrangedSubview(nameLabel)

        // 弹性空间
        rowStack.addArrangedSubview(createSpacer())

        // 窗口数量 + 折叠/展开指示器（有窗口时显示）
        if !windows.isEmpty {
            let countLabel = createLabel("\(windows.count) 个窗口", size: 11, color: colors.nsTextSecondary)
            rowStack.addArrangedSubview(countLabel)

            let isCollapsed = collapsedApps.contains(bundleID)
            let chevronName = isCollapsed ? "chevron.right" : "chevron.down"
            let chevronView = NSImageView()
            chevronView.translatesAutoresizingMaskIntoConstraints = false
            chevronView.image = Self.cachedSymbol(name: chevronName, size: 9, weight: .medium)
            chevronView.contentTintColor = colors.nsTextSecondary
            NSLayoutConstraint.activate([
                chevronView.widthAnchor.constraint(equalToConstant: 14),
                chevronView.heightAnchor.constraint(equalToConstant: 14),
            ])
            rowStack.addArrangedSubview(chevronView)
        }

        // 配置点击行为（P2-#5：提取点击处理逻辑）
        row.bundleID = bundleID
        configureClickHandler(row: row, bundleID: bundleID, isRunning: isRunning, hasWindows: !windows.isEmpty)

        return row
    }

    /// 配置 App 行点击行为（P2-#5：从 createAppRow 提取）
    private func configureClickHandler(row: HoverableRowView, bundleID: String, isRunning: Bool, hasWindows: Bool) {
        if !isRunning {
            // 未运行 App：灰度显示，点击启动
            row.alphaValue = 0.5
            row.toolTip = "点击启动"
            row.clickHandler = { [weak self] in
                self?.launchApp(bundleID: bundleID)
            }
        } else if hasWindows {
            // 运行中 App（有窗口）：点击切换折叠/展开
            row.clickHandler = { [weak self] in
                guard let self = self else { return }
                if self.collapsedApps.contains(bundleID) {
                    self.collapsedApps.remove(bundleID)
                } else {
                    self.collapsedApps.insert(bundleID)
                }
                self.forceReload()
            }
        } else {
            // 运行中但无窗口 App：点击激活 App
            row.clickHandler = { [weak self] in
                guard let self = self else { return }
                if let runApp = AppMonitor.shared.runningApps.first(where: { $0.bundleID == bundleID }),
                   let firstWindow = runApp.windows.first {
                    self.highlightedWindowID = firstWindow.id
                    WindowService.shared.activateWindow(firstWindow)
                    (self.window as? QuickPanelWindow)?.yieldLevel()
                    self.forceReload()
                } else {
                    WindowService.shared.activateApp(bundleID)
                    (self.window as? QuickPanelWindow)?.yieldLevel()
                }
            }
        }
    }

    // MARK: - 创建窗口列表

    func createWindowList(windows: [WindowInfo], bundleID: String) -> NSView {
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

    func createWindowRow(windowInfo: WindowInfo, bundleID: String) -> NSView {
        let colors = ConfigStore.shared.currentThemeColors
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

        // 窗口图标（层叠矩形 SF Symbol，使用缓存）
        let windowIconView = NSImageView()
        windowIconView.translatesAutoresizingMaskIntoConstraints = false
        windowIconView.image = Self.cachedSymbol(name: "rectangle.on.rectangle", size: 11, weight: .regular)
        windowIconView.contentTintColor = colors.nsTextTertiary
        NSLayoutConstraint.activate([
            windowIconView.widthAnchor.constraint(equalToConstant: 14),
            windowIconView.heightAnchor.constraint(equalToConstant: 14),
        ])
        rowStack.addArrangedSubview(windowIconView)

        // 窗口标题：优先使用自定义名称
        let renameKey = Self.renameKey(bundleID: bundleID, windowID: windowInfo.id)
        let customName = ConfigStore.shared.windowRenames[renameKey]
        let displayTitle: String
        if let custom = customName, !custom.isEmpty {
            displayTitle = custom
        } else {
            displayTitle = windowInfo.title.isEmpty ? "（无标题）" : windowInfo.title
        }

        let titleLabel = createLabel(displayTitle, size: 11, color: colors.nsTextPrimary)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.toolTip = windowInfo.title
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        rowStack.addArrangedSubview(titleLabel)

        // 注册到映射（用于差分更新时直接修改标题文本）
        windowTitleLabels[windowInfo.id] = titleLabel
        windowRowViewMap[windowInfo.id] = row

        // 弹性空间
        rowStack.addArrangedSubview(createSpacer())

        // 橙色 hover/selected（和 AI Tab 一致）
        row.hoverColor = NSColor.systemOrange.withAlphaComponent(0.15)
        row.selectedColor = NSColor.systemOrange.withAlphaComponent(0.15)
        row.indicatorColor = .systemOrange

        // 恢复上次的选中状态
        if highlightedWindowID == windowInfo.id {
            row.isSelected = true
        }

        // 设置右键菜单
        row.contextMenuProvider = { [weak self] in
            self?.createWindowContextMenu(bundleID: bundleID, windowInfo: windowInfo)
        }

        // 点击窗口行：即时橙色高亮 + 前置窗口（不 forceReload，列表不跳动）
        row.clickHandler = { [weak self] in
            guard let self = self else { return }

            // 即时选中高亮（didSet 自动清除上一个 selected 行）
            row.isSelected = true
            self.highlightedWindowID = windowInfo.id

            // 切换窗口
            WindowService.shared.activateWindow(windowInfo)
            (self.window as? QuickPanelWindow)?.yieldLevel()
        }

        return row
    }

    // MARK: - 权限引导视图

    func createPermissionHintView() -> NSView {
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

        let colors = ConfigStore.shared.currentThemeColors
        let lockLabel = createLabel("🔒", size: 16, color: colors.nsTextPrimary)
        lockLabel.alignment = .center
        stack.addArrangedSubview(lockLabel)

        let hintLabel = createLabel("需要辅助功能权限", size: 12, color: colors.nsTextSecondary)
        hintLabel.alignment = .center
        stack.addArrangedSubview(hintLabel)

        let detailLabel = createLabel("窗口管理功能需要此权限才能正常工作", size: 10, color: colors.nsTextTertiary)
        detailLabel.alignment = .center
        stack.addArrangedSubview(detailLabel)

        let settingsButton = NSButton(title: "前往系统设置", target: self, action: #selector(openAccessibilitySettings))
        settingsButton.bezelStyle = .recessed
        settingsButton.controlSize = .small
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(settingsButton)

        return container
    }

    // MARK: - AI Session Row (V2)

    func createSessionRow(session: CoderSession) -> NSView {
        let theme = ConfigStore.shared.currentThemeColors
        let row = HoverableRowView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let verticalStack = NSStackView()
        verticalStack.orientation = .vertical
        verticalStack.alignment = .leading
        verticalStack.spacing = 2
        verticalStack.translatesAutoresizingMaskIntoConstraints = false

        // === 第一行：● Claude · shortID    hostApp  状态 ===
        let firstLine = NSStackView()
        firstLine.orientation = .horizontal
        firstLine.alignment = .centerY
        firstLine.spacing = 4
        firstLine.distribution = .fill
        firstLine.translatesAutoresizingMaskIntoConstraints = false

        // 状态圆点（10px，支持闪烁）
        let dotSize: CGFloat = session.lifecycle == .ended ? 8 : 10
        let dot = NSView()
        dot.wantsLayer = true
        dot.translatesAutoresizingMaskIntoConstraints = false
        let dotColor = session.statusDotColor(theme: theme)
        dot.layer?.backgroundColor = dotColor.cgColor
        dot.layer?.cornerRadius = dotSize / 2
        if session.statusDotHasGlow {
            dot.layer?.shadowColor = dotColor.cgColor
            dot.layer?.shadowRadius = 4
            dot.layer?.shadowOpacity = 0.6
            dot.layer?.shadowOffset = .zero
        }
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: dotSize),
            dot.heightAnchor.constraint(equalToConstant: dotSize),
        ])
        firstLine.addArrangedSubview(dot)

        // working 状态：绿点闪烁动画
        if session.status == .working && session.lifecycle == .active {
            let pulseAnim = CABasicAnimation(keyPath: "opacity")
            pulseAnim.fromValue = 1.0
            pulseAnim.toValue = 0.3
            pulseAnim.duration = 0.8
            pulseAnim.autoreverses = true
            pulseAnim.repeatCount = .infinity
            pulseAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            dot.layer?.add(pulseAnim, forKey: "pulse")
        }

        // App 图标（16px）
        if !session.hostApp.isEmpty,
           let bundleID = HostAppMapping.bundleID(for: session.hostApp),
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let appIcon = NSWorkspace.shared.icon(forFile: appURL.path)
            appIcon.size = NSSize(width: 16, height: 16)
            let iconView = NSImageView(image: appIcon)
            iconView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                iconView.widthAnchor.constraint(equalToConstant: 16),
                iconView.heightAnchor.constraint(equalToConstant: 16),
            ])
            firstLine.addArrangedSubview(iconView)
        }

        // 绑定状态标记（紧跟图标后面）
        let state = CoderBridgeService.shared.bindingState(for: session)
        switch state {
        case .manual:
            break  // 无标记
        case .autoValid:
            if session.hostKind == .ide {
                break  // IDE auto 不显示标记
            }
            // terminal auto：显示 ? 标记
            if let qImage = Self.cachedSymbol(name: "questionmark.circle", size: 10, weight: .regular) {
                let qView = NSImageView(image: qImage)
                qView.contentTintColor = theme.nsTextTertiary
                qView.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    qView.widthAnchor.constraint(equalToConstant: 12),
                    qView.heightAnchor.constraint(equalToConstant: 12),
                ])
                firstLine.addArrangedSubview(qView)
            }
        case .autoConflicted, .missing:
            // 红色 ✕
            if let xImage = Self.cachedSymbol(name: "xmark.square", size: 12, weight: .medium) {
                let xView = NSImageView(image: xImage)
                xView.contentTintColor = .systemRed
                xView.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    xView.widthAnchor.constraint(equalToConstant: 12),
                    xView.heightAnchor.constraint(equalToConstant: 12),
                ])
                firstLine.addArrangedSubview(xView)
            }
        }

        // "Claude · a1b2c3d4"（可截断）
        let idText = "\(session.tool.displayName) · \(session.shortID)"
        let idLabel = createLabel(idText, size: 11, color: theme.nsTextPrimary)
        idLabel.lineBreakMode = .byTruncatingTail
        idLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        firstLine.addArrangedSubview(idLabel)

        firstLine.addArrangedSubview(createSpacer())

        // 状态文字（不被挤压）
        let statusLabel = createLabel(session.statusText, size: 10, color: session.statusTextColor(theme: theme))
        statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        firstLine.addArrangedSubview(statusLabel)

        // actionable 未读标签（统一红底白字，与 Tab 角标/悬浮球角标风格一致）
        if session.isActionable {
            let badge = NSTextField(labelWithString: " 未读 ")
            badge.font = .systemFont(ofSize: 9, weight: .semibold)
            badge.textColor = .white
            badge.wantsLayer = true
            badge.layer?.backgroundColor = NSColor.systemRed.cgColor
            badge.layer?.cornerRadius = 3
            badge.alignment = .center
            badge.translatesAutoresizingMaskIntoConstraints = false
            firstLine.addArrangedSubview(badge)
        }

        firstLine.translatesAutoresizingMaskIntoConstraints = false
        verticalStack.addArrangedSubview(firstLine)
        // firstLine 宽度跟随 verticalStack
        firstLine.widthAnchor.constraint(equalTo: verticalStack.widthAnchor).isActive = true

        // === 第二行：query 摘要 ===
        let queryText: String
        if let query = CoderBridgeService.shared.latestQuerySummary(for: session, maxLength: 60) {
            queryText = "\"\(query)\""
        } else {
            queryText = "等待输入..."
        }
        let queryLabel = createLabel(queryText, size: 10, color: theme.nsTextTertiary)
        queryLabel.lineBreakMode = .byTruncatingTail
        queryLabel.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
        queryLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        queryLabel.translatesAutoresizingMaskIntoConstraints = false
        verticalStack.addArrangedSubview(queryLabel)
        queryLabel.widthAnchor.constraint(lessThanOrEqualTo: verticalStack.widthAnchor).isActive = true

        // 布局（缩进 windowIndent）
        row.addSubview(verticalStack)
        NSLayoutConstraint.activate([
            verticalStack.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: Constants.Panel.windowIndent),
            verticalStack.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -Constants.Design.Spacing.sm),
            verticalStack.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])

        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        row.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.alphaValue = session.rowAlpha

        // AI session 行：橙色 hover + selected
        row.hoverColor = NSColor.systemOrange.withAlphaComponent(0.15)
        row.selectedColor = NSColor.systemOrange.withAlphaComponent(0.15)
        row.indicatorColor = .systemOrange

        // 恢复上次的选中状态
        if session.sessionID == CoderBridgeService.shared.activeSessionID {
            row.isSelected = true
        }

        row.clickHandler = { [weak self] in
            self?.handleSessionClick(session, row: row)
        }

        row.contextMenuProvider = { [weak self] in
            self?.createSessionContextMenu(session: session)
        }

        return row
    }

    private func handleSessionClick(_ session: CoderSession, row: HoverableRowView) {
        // 即时选中高亮（didSet 自动清除上一个 selected 行）
        row.isSelected = true
        CoderBridgeService.shared.activeSessionID = session.sessionID
        CoderBridgeService.shared.updateLastInteraction(sid: session.sessionID)

        // 2. 直接执行窗口切换
        performWindowSwitch(session, row: row)
    }

    private func performWindowSwitch(_ session: CoderSession, row: HoverableRowView? = nil) {
        let state = CoderBridgeService.shared.bindingState(for: session)

        switch state {
        case .manual, .autoValid:
            // 有绑定（强或弱）→ 通过 resolveWindowForSession 获取窗口并激活
            let (windowID, confidence) = CoderBridgeService.shared.resolveWindowForSession(session)
            if let wid = windowID, confidence == .high {
                let allWindows = AppMonitor.shared.runningApps.flatMap { $0.windows }
                if let windowInfo = allWindows.first(where: { $0.id == wid }) {
                    CoderBridgeService.shared.markAsRead(sid: session.sessionID)
                    WindowService.shared.activateWindow(windowInfo)
                    (self.window as? QuickPanelWindow)?.yieldLevel()
                    return
                }
            }
            // 绑定的窗口已失效 → 走引导
            promptBindToCurrentWindow(sid: session.sessionID)

        case .autoConflicted, .missing:
            // 未绑定或冲突 → 直接引导手动绑定，不走 fallback 匹配
            promptBindToCurrentWindow(sid: session.sessionID)
        }
    }

    /// 弹出绑定引导对话框
    private func promptBindToCurrentWindow(sid: String) {
        // 获取 session 信息用于 hostApp 校验
        guard let session = CoderBridgeService.shared.sessions.first(where: { $0.sessionID == sid }) else { return }

        let myPID = ProcessInfo.processInfo.processIdentifier
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return }

        // 从 CGWindowList（z-order）找第一个非 FocusPilot 的普通窗口
        var targetWindowID: CGWindowID?
        var targetTitle = ""
        var targetPID: pid_t = 0
        for windowInfo in windowList {
            guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID != myPID,
                  let layer = windowInfo[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let wid = windowInfo[kCGWindowNumber as String] as? CGWindowID else { continue }
            targetWindowID = wid
            targetTitle = windowInfo[kCGWindowName as String] as? String ?? ""
            targetPID = ownerPID
            break
        }

        guard let wid = targetWindowID else { return }

        // 通过 PID 找 app
        let frontApp = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == targetPID })
        let frontBundleID = frontApp?.bundleIdentifier ?? ""

        let appName = frontApp?.localizedName ?? "未知应用"
        let displayTitle = targetTitle.isEmpty ? appName : "\(appName) — \(targetTitle)"

        let alert = NSAlert()

        // hostApp 校验：目标窗口必须属于 session 的宿主 app
        if !session.hostApp.isEmpty,
           let expectedBundleID = HostAppMapping.bundleID(for: session.hostApp),
           frontBundleID != expectedBundleID {
            let expectedName = HostAppMapping.displayName(for: session.hostApp)
            alert.messageText = "窗口不匹配"
            alert.informativeText = "此会话的宿主应用是「\(expectedName)」，当前窗口属于「\(appName)」。\n请先切换到「\(expectedName)」的窗口再绑定。"
            alert.addButton(withTitle: "确定")
            prepareAlert(alert)
            alert.runModal()
            restoreAfterAlert()
            // 切换失败，清除高亮
            CoderBridgeService.shared.activeSessionID = nil
            forceReload()
            return
        }

        // 冲突检测：仅 terminal 类型才拦截
        if session.hostKind == .terminal,
           let occupierSid = CoderBridgeService.shared.sessionOccupyingWindow(wid, excludingSid: sid) {
            let occupierSession = CoderBridgeService.shared.sessions.first(where: { $0.sessionID == occupierSid })
            let occupierName = occupierSession?.shortID ?? "其他会话"
            alert.messageText = "该窗口已被绑定"
            alert.informativeText = "「\(displayTitle)」当前已被会话 \(occupierName) 绑定。\n请先切换到目标窗口再重新绑定。"
            alert.addButton(withTitle: "确定")
            prepareAlert(alert)
            alert.runModal()
            restoreAfterAlert()
            CoderBridgeService.shared.activeSessionID = nil
            forceReload()
            return
        }

        alert.messageText = "此会话尚未绑定窗口"
        alert.informativeText = "是否绑定到当前窗口「\(displayTitle)」？"
        alert.addButton(withTitle: "绑定")
        alert.addButton(withTitle: "取消")

        prepareAlert(alert)
        let result = alert.runModal()
        restoreAfterAlert()
        if result == .alertFirstButtonReturn {
            CoderBridgeService.shared.bindSessionToWindow(sid: sid, windowID: wid)
            forceReload()
        } else {
            // 取消绑定，清除高亮
            CoderBridgeService.shared.activeSessionID = nil
            forceReload()
        }
    }
}
