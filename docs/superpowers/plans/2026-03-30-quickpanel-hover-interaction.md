# 快捷面板 Hover 交互模式 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 非固定模式下快捷面板通过 hover 驱动 Tab 切换和 App 展开/折叠，浮球显示 AI 消息数角标

**Architecture:** 以 `isPanelPinned` 分模式。Tab 拆分为 `selectedTab`（持久）+ `displayTab`（渲染态）。App 展开/折叠由 `hoverExpandedBundleID` 驱动，通过容器 `isHidden` 切换实现轻量更新。浮球复用 `badgeLabel` 显示 `actionableCount`。

**Tech Stack:** Swift 5, AppKit (NSTrackingArea, NSView)

**Spec:** `docs/superpowers/specs/2026-03-30-quickpanel-hover-interaction-design.md`

---

## 文件结构

| 文件 | 改动类型 | 职责 |
|---|---|---|
| `FocusPilot/QuickPanel/QuickPanelView.swift` | 修改 | Tab 双状态模型、hover 展开状态、Tab tracking area、通知监听、buildStructuralKey/buildContent 适配 |
| `FocusPilot/QuickPanel/QuickPanelRowBuilder.swift` | 修改 | App 行+窗口列表容器包装、hover tracking area、clickHandler 模式分流 |
| `FocusPilot/FloatingBall/FloatingBallView.swift` | 修改 | AI 角标显示逻辑、新增 coderBridgeSessionChanged 监听 |

---

### Task 1: Tab 双状态模型 — 状态拆分与初始化

**Files:**
- Modify: `FocusPilot/QuickPanel/QuickPanelView.swift:20-21` (状态声明)
- Modify: `FocusPilot/QuickPanel/QuickPanelView.swift:568` (初始化)

- [ ] **Step 1: 将 `currentTab` 拆分为 `selectedTab` + `displayTab`**

在 `QuickPanelView.swift` 第 20 行，将：

```swift
    var currentTab: QuickPanelTab = .running
```

替换为：

```swift
    /// 用户点击选择的持久 Tab（写入 UserDefaults）
    var selectedTab: QuickPanelTab = .running
    /// 当前实际显示的 Tab（驱动 UI 渲染，hover 预览时可与 selectedTab 不同）
    var displayTab: QuickPanelTab = .running
```

- [ ] **Step 2: 更新初始化代码**

在 `QuickPanelView.swift` 第 568 行，将：

```swift
        currentTab = QuickPanelTab(rawValue: ConfigStore.shared.lastPanelTab) ?? .running
```

替换为：

```swift
        selectedTab = QuickPanelTab(rawValue: ConfigStore.shared.lastPanelTab) ?? .running
        displayTab = selectedTab
```

- [ ] **Step 3: 全局替换 `currentTab` 引用为 `displayTab`**

在以下位置将 `currentTab` 替换为 `displayTab`（这些都是读取当前显示 Tab 的地方）：

`QuickPanelView.swift`:
- 第 1652 行 `switch currentTab` → `switch displayTab`（updateTabButtonStyles）
- 第 1715 行 `currentTab.rawValue` → `displayTab.rawValue`（buildStructuralKey）
- 第 1717 行 `switch currentTab` → `switch displayTab`（buildStructuralKey）
- 第 1789 行 `switch currentTab` → `switch displayTab`（buildContent）
- 第 2070 行 `self.currentTab == .ai` → `self.displayTab == .ai`（coderBridgeSessionsDidChange）

`QuickPanelRowBuilder.swift`:
- 第 193 行 `if currentTab == .running` → `if displayTab == .running`（星号按钮显示判断）

- [ ] **Step 4: 更新 `switchTab()` 同时设置两个状态**

在 `QuickPanelView.swift` 第 1623-1630 行，将：

```swift
    private func switchTab(_ tab: QuickPanelTab) {
        guard currentTab != tab else { return }
        currentTab = tab
        ConfigStore.shared.saveLastPanelTab(tab)
        highlightedWindowID = nil
        updateTabButtonStyles()
        forceReload()
    }
```

替换为：

```swift
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
```

- [ ] **Step 5: 更新 `resetToNormalMode()` 回退 `displayTab`**

在 `QuickPanelView.swift` 第 1776-1784 行，将：

```swift
    func resetToNormalMode() {
        highlightedWindowID = nil
        // 不重置 currentTab（Tab 记忆功能）
        collapsedApps.removeAll()
        windowTitleLabels.removeAll()
        windowRowViewMap.removeAll()
        lastStructuralKey = ""  // 清除快照，确保下次打开时强制刷新
    }
```

替换为：

```swift
    func resetToNormalMode() {
        highlightedWindowID = nil
        // displayTab 回退到 selectedTab（hover 预览不残留）
        displayTab = selectedTab
        hoverExpandedBundleID = nil
        hoverWindowListMap.removeAll()
        collapsedApps.removeAll()
        windowTitleLabels.removeAll()
        windowRowViewMap.removeAll()
        lastStructuralKey = ""  // 清除快照，确保下次打开时强制刷新
    }
```

- [ ] **Step 6: 编译验证**

```bash
make build
```

Expected: 编译通过，除 `hoverExpandedBundleID` 未声明外无错误（将在 Task 2 声明）。如果报错 `hoverExpandedBundleID` 未定义，先在状态区域加一行 `var hoverExpandedBundleID: String?` 占位。

- [ ] **Step 7: 提交**

```bash
git add FocusPilot/QuickPanel/QuickPanelView.swift FocusPilot/QuickPanel/QuickPanelRowBuilder.swift
git commit -m "refactor: Tab 双状态模型 — currentTab 拆分为 selectedTab + displayTab"
```

---

### Task 2: Hover 展开状态声明 + hoverPreviewTab + panelPinStateChanged 监听

**Files:**
- Modify: `FocusPilot/QuickPanel/QuickPanelView.swift:26` (状态声明)
- Modify: `FocusPilot/QuickPanel/QuickPanelView.swift:634-691` (setupNotifications)
- Modify: `FocusPilot/QuickPanel/QuickPanelView.swift:1623-1634` (Tab 切换区)

- [ ] **Step 1: 声明 `hoverExpandedBundleID` + `hoverWindowListMap`**

在 `QuickPanelView.swift` 的状态区域（`collapsedApps` 声明之后，约第 27 行），添加：

```swift
    /// 非固定模式下当前 hover 展开的 App（按 bundleID 跟踪）
    var hoverExpandedBundleID: String?
    /// 非固定模式下 bundleID → windowList 视图映射（用于中心化收起旧列表）
    var hoverWindowListMap: [String: NSView] = [:]
```

注意：如果 Task 1 Step 6 中已经添加了占位声明，将其替换为带注释的版本。`hoverWindowListMap` 在每次 `reloadData` 全量重建时随 `createHoverExpandContainer` 重新填充。

- [ ] **Step 2: 添加 `hoverPreviewTab()` 方法**

在 `switchTab()` 方法之后（约第 1634 行 `switchToAITab` 之后），添加：

```swift
    /// 非固定模式 hover 临时预览 Tab（不持久化，不改 selectedTab）
    private func hoverPreviewTab(_ tab: QuickPanelTab) {
        guard displayTab != tab else { return }
        hoverExpandedBundleID = nil
        displayTab = tab
        updateTabButtonStyles()
        forceReload()
    }
```

- [ ] **Step 3: 添加 `panelPinStateChanged` 监听**

在 `setupNotifications()` 方法末尾（CoderBridge session 监听之后，`}` 闭合之前），添加：

```swift
        // 面板钉住状态变化（hover 模式切换）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelPinStateDidChange(_:)),
            name: Constants.Notifications.panelPinStateChanged,
            object: nil
        )
```

- [ ] **Step 4: 添加 `panelPinStateDidChange` 回调**

在 `coderBridgeSessionsDidChange()` 方法之后，添加：

```swift
    @objc private func panelPinStateDidChange(_ notification: Notification) {
        let pinned = notification.userInfo?["isPinned"] as? Bool ?? false
        if pinned {
            // 切回固定模式：displayTab 回退到 selectedTab，清空 hover 展开态
            displayTab = selectedTab
            hoverExpandedBundleID = nil
            hoverWindowListMap.removeAll()
            updateTabButtonStyles()
            forceReload()
        }
    }
```

- [ ] **Step 5: 编译验证**

```bash
make build
```

Expected: 编译通过，无错误。

- [ ] **Step 6: 提交**

```bash
git add FocusPilot/QuickPanel/QuickPanelView.swift
git commit -m "feat: hoverExpandedBundleID 状态 + hoverPreviewTab + panelPinStateChanged 监听"
```

---

### Task 3: Tab 按钮 Hover 触发

**Files:**
- Modify: `FocusPilot/QuickPanel/QuickPanelView.swift:84-141` (Tab 按钮声明区)
- Modify: `FocusPilot/QuickPanel/QuickPanelView.swift:575-630` (tracking area / mouseEntered / mouseExited)

- [ ] **Step 1: 为 Tab 按钮添加 tracking area**

在 `setupView()` 方法末尾（`updateTimerUI()` 调用之前），添加：

```swift
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
```

- [ ] **Step 2: 在 `mouseEntered` 中处理 Tab hover**

在 `QuickPanelView.swift` 的 `mouseEntered(with:)` 方法中，在计时器栏 hover 检查之后、panelWindow 处理之前，添加 Tab 按钮 hover 处理：

将现有的：

```swift
    override func mouseEntered(with event: NSEvent) {
        // 计时器栏 hover
        if event.trackingArea === timerBarTrackingArea {
            isTimerBarHovered = true
            updateTimerBarHover()
            return
        }
        if let panelWindow = window as? QuickPanelWindow {
```

替换为：

```swift
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
            if btn === runningTabButton {
                hoverPreviewTab(.running)
            } else if btn === favoritesTabButton {
                hoverPreviewTab(.favorites)
            } else if btn === aiTabButton {
                hoverPreviewTab(.ai)
            }
            return
        }
        if let panelWindow = window as? QuickPanelWindow {
```

- [ ] **Step 3: 编译验证**

```bash
make build
```

Expected: 编译通过。

- [ ] **Step 4: `make install` 并手动测试**

```bash
make install
```

测试步骤：
1. 启动应用，面板处于非固定模式
2. hover 悬浮球弹出面板
3. 鼠标划过 Tab 按钮区域 → Tab 应自动切换
4. 关闭面板，重新打开 → 应回到上次点击选择的 Tab（不是 hover 最后经过的）
5. 钉住面板 → hover Tab 按钮不应触发切换，需要点击

- [ ] **Step 5: 提交**

```bash
git add FocusPilot/QuickPanel/QuickPanelView.swift
git commit -m "feat: Tab 按钮 hover 触发（非固定模式自动切换，不持久化）"
```

---

### Task 4: App 行容器包装 + Hover 展开/折叠

**Files:**
- Modify: `FocusPilot/QuickPanel/QuickPanelView.swift:1812-1835` (buildRunningAppList)
- Modify: `FocusPilot/QuickPanel/QuickPanelView.swift:1838-1865` (buildFavoritesTabContent)
- Modify: `FocusPilot/QuickPanel/QuickPanelRowBuilder.swift:277-312` (configureClickHandler)

- [ ] **Step 1: 判断是否处于非固定模式的辅助属性**

在 `QuickPanelView.swift` 的状态区域（`hoverExpandedBundleID` 之后），添加：

```swift
    /// 当前是否处于非固定模式（便于各处判断）
    var isUnpinnedMode: Bool {
        (window as? QuickPanelWindow)?.isPanelPinned == false
    }
```

- [ ] **Step 2: 在 `reloadData` 全量重建时清空 `hoverWindowListMap`**

在 `QuickPanelView.swift` 的 `reloadData()` 方法中，全量重建分支的 `windowTitleLabels.removeAll()` 之后，添加一行：

```swift
            hoverWindowListMap.removeAll()
```

（映射会在随后的 `buildContent()` → `createHoverExpandContainer()` 中重新填充。）

- [ ] **Step 3: 重构 `buildRunningAppList` — 容器包装 + hover 展开**

将 `QuickPanelView.swift` 中 `buildRunningAppList` 方法内的 for 循环部分：

```swift
        for app in apps {
            let appRow = createRunningAppRow(app: app)
            contentStack.addArrangedSubview(appRow)

            if hasAccessibility, !app.windows.isEmpty,
               !(collapsedApps.contains(app.bundleID)) {
                let windowList = createWindowList(windows: app.windows, bundleID: app.bundleID)
                contentStack.addArrangedSubview(windowList)
            }
        }
```

替换为：

```swift
        for app in apps {
            let appRow = createRunningAppRow(app: app)

            if hasAccessibility, !app.windows.isEmpty {
                let windowList = createWindowList(windows: app.windows, bundleID: app.bundleID)

                if isUnpinnedMode {
                    // 非固定模式：App 行+窗口列表包在容器中，hover 展开
                    let container = createHoverExpandContainer(
                        appRow: appRow, windowList: windowList, bundleID: app.bundleID
                    )
                    contentStack.addArrangedSubview(container)
                } else {
                    // 固定模式：保持现有逻辑
                    contentStack.addArrangedSubview(appRow)
                    if !collapsedApps.contains(app.bundleID) {
                        contentStack.addArrangedSubview(windowList)
                    }
                }
            } else {
                contentStack.addArrangedSubview(appRow)
            }
        }
```

- [ ] **Step 4: 重构 `buildFavoritesTabContent` — 同样的容器包装**

将 `QuickPanelView.swift` 中 `buildFavoritesTabContent` 方法内的 for 循环部分：

```swift
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
```

替换为：

```swift
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
```

- [ ] **Step 5: 添加 `createHoverExpandContainer` 方法**

在 `QuickPanelView.swift` 的 `buildContent()` 方法之前（MARK: - 内容构建 区域），添加：

```swift
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
```

- [ ] **Step 6: 在 `mouseEntered` / `mouseExited` 中处理 hover 展开/折叠**

在 `mouseEntered(with:)` 中，Tab 按钮 hover 处理之后，添加 App 容器 hover 处理：

在 Tab hover 的 `return` 之后、`if let panelWindow = window as? QuickPanelWindow {` 之前，添加：

```swift
        // App 容器 hover（非固定模式下展开窗口列表）
        if let bundleID = event.trackingArea?.userInfo?["hoverExpandBundleID"] as? String,
           isUnpinnedMode {
            // 中心化：先收起上一个展开的列表（解决 entered(B) 先于 exited(A) 时 A 残留的问题）
            if let oldID = hoverExpandedBundleID, oldID != bundleID,
               let oldList = hoverWindowListMap[oldID] {
                oldList.isHidden = true
            }
            hoverExpandedBundleID = bundleID
            hoverWindowListMap[bundleID]?.isHidden = false
            return
        }
```

在 `mouseExited(with:)` 中，计时器栏 hover 结束处理之后，钉住模式检查之前，添加：

```swift
        // App 容器 hover 结束（非固定模式下折叠窗口列表）
        if let bundleID = event.trackingArea?.userInfo?["hoverExpandBundleID"] as? String,
           isUnpinnedMode {
            // 只有当前 hover owner 未变时才折叠（如果已被新容器的 entered 覆盖则跳过）
            if hoverExpandedBundleID == bundleID {
                hoverExpandedBundleID = nil
                hoverWindowListMap[bundleID]?.isHidden = true
            }
            return
        }
```

- [ ] **Step 7: 编译验证**

```bash
make build
```

Expected: 编译通过。

- [ ] **Step 8: 提交**

```bash
git add FocusPilot/QuickPanel/QuickPanelView.swift
git commit -m "feat: App 行 hover 展开/折叠容器（中心化收起 + hoverWindowListMap）"
```

---

### Task 5: buildStructuralKey 适配 + configureClickHandler 模式分流

**Files:**
- Modify: `FocusPilot/QuickPanel/QuickPanelView.swift:1712-1750` (buildStructuralKey)
- Modify: `FocusPilot/QuickPanel/QuickPanelRowBuilder.swift:277-312` (configureClickHandler)

- [ ] **Step 1: `buildStructuralKey()` 非固定模式折叠态占位**

在 `buildStructuralKey()` 中，running 和 favorites 分支里的折叠态编码需要区分模式。

将第 1722 行：

```swift
                let collapsed = collapsedApps.contains(app.bundleID) ? "C" : "E"
```

替换为：

```swift
                let collapsed = isUnpinnedMode ? "H" : (collapsedApps.contains(app.bundleID) ? "C" : "E")
```

将第 1733 行：

```swift
                let collapsed = collapsedApps.contains(config.bundleID) ? "C" : "E"
```

替换为：

```swift
                let collapsed = isUnpinnedMode ? "H" : (collapsedApps.contains(config.bundleID) ? "C" : "E")
```

- [ ] **Step 2: `configureClickHandler()` 非固定模式下改为激活窗口**

在 `QuickPanelRowBuilder.swift` 中，将 `configureClickHandler` 方法：

```swift
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
```

替换为：

```swift
    private func configureClickHandler(row: HoverableRowView, bundleID: String, isRunning: Bool, hasWindows: Bool) {
        if !isRunning {
            // 未运行 App：灰度显示，点击启动
            row.alphaValue = 0.5
            row.toolTip = "点击启动"
            row.clickHandler = { [weak self] in
                self?.launchApp(bundleID: bundleID)
            }
        } else if hasWindows {
            if isUnpinnedMode {
                // 非固定模式：点击激活第一个窗口（展开/折叠由 hover 驱动）
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
            } else {
                // 固定模式：点击切换折叠/展开
                row.clickHandler = { [weak self] in
                    guard let self = self else { return }
                    if self.collapsedApps.contains(bundleID) {
                        self.collapsedApps.remove(bundleID)
                    } else {
                        self.collapsedApps.insert(bundleID)
                    }
                    self.forceReload()
                }
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
```

- [ ] **Step 3: App 行 chevron 图标适配非固定模式**

在 `QuickPanelRowBuilder.swift` 的 `createAppRow` 方法中，第 256 行的 chevron 逻辑：

```swift
            let isCollapsed = collapsedApps.contains(bundleID)
            let chevronName = isCollapsed ? "chevron.right" : "chevron.down"
```

替换为：

```swift
            let isCollapsed: Bool
            if isUnpinnedMode {
                isCollapsed = (hoverExpandedBundleID != bundleID)
            } else {
                isCollapsed = collapsedApps.contains(bundleID)
            }
            let chevronName = isCollapsed ? "chevron.right" : "chevron.down"
```

- [ ] **Step 4: 编译验证**

```bash
make build
```

Expected: 编译通过。

- [ ] **Step 5: `make install` 并手动测试**

```bash
make install
```

测试步骤：
1. 非固定模式下 hover 弹出面板 → App 行默认折叠
2. hover 到 App 行 → 窗口列表展开，chevron 变为向下
3. hover 离开 App 区域 → 窗口列表折叠
4. 从 App A hover 到 App B → A 折叠 B 展开，无闪烁
5. 点击 App 行 → 激活第一个窗口
6. 钉住面板 → 切回固定模式行为（点击折叠/展开）
7. 后台有窗口变化（打开新窗口）→ hover 展开态应保留

- [ ] **Step 6: 提交**

```bash
git add FocusPilot/QuickPanel/QuickPanelView.swift FocusPilot/QuickPanel/QuickPanelRowBuilder.swift
git commit -m "feat: buildStructuralKey 非固定模式适配 + configureClickHandler 模式分流 + chevron 适配"
```

---

### Task 6: 浮球 AI 消息数角标

**Files:**
- Modify: `FocusPilot/FloatingBall/FloatingBallView.swift:411-441` (setupNotifications)
- Modify: `FocusPilot/FloatingBall/FloatingBallView.swift:475-485` (panelPinStateChanged + updateBadge)

- [ ] **Step 1: 添加 `coderBridgeSessionChanged` 监听**

在 `FloatingBallView.swift` 的 `setupNotifications()` 方法中，`panelPinStateChanged` 监听之后，添加：

```swift
        // AI 会话状态变化 → 更新角标
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(coderBridgeSessionsDidChange),
            name: Constants.Notifications.coderBridgeSessionChanged,
            object: nil
        )
```

- [ ] **Step 2: 替换 `updateBadge` 为 `updateAIBadge` + 添加通知回调**

将现有的 `updateBadge` 方法和 `panelPinStateChanged` 回调：

```swift
    @objc private func panelPinStateChanged(_ notification: Notification) {
        isPanelPinned = notification.userInfo?["isPinned"] as? Bool ?? false
        updatePinBadge(isPinned: isPanelPinned)
    }

    // MARK: - 角标

    /// 更新角标（V3.0: 角标始终隐藏）
    func updateBadge(_ count: Int) {
        badgeLabel.isHidden = true
    }
```

替换为：

```swift
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
```

- [ ] **Step 3: 移除外部对 `updateBadge` 的调用（如有）**

搜索项目中是否有其他地方调用 `updateBadge`：

```bash
grep -rn "updateBadge" FocusPilot/
```

如有调用方，删除调用行（`updateAIBadge` 现在由通知自驱动，不需要外部调用）。

- [ ] **Step 4: 编译验证**

```bash
make build
```

Expected: 编译通过。

- [ ] **Step 5: `make install` 并手动测试**

```bash
make install
```

测试步骤：
1. 非固定模式下有活跃 AI 会话 → 浮球右上角显示红色角标数字
2. AI 会话无 actionable → 角标隐藏
3. 钉住面板 → 角标隐藏（面板上已有 aiBadgeLabel）
4. 取消钉住 → 角标恢复显示（如有 actionable 会话）

- [ ] **Step 6: 提交**

```bash
git add FocusPilot/FloatingBall/FloatingBallView.swift
git commit -m "feat: 浮球 AI 消息数角标（非固定模式下显示 actionableCount）"
```

---

### Task 7: 更新 CLAUDE.md + PRD + Architecture

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/PRD.md`
- Modify: `docs/Architecture.md`

- [ ] **Step 1: 更新 CLAUDE.md 配置迁移和关键设计决策**

在 CLAUDE.md 的「关键设计决策」末尾追加：

```
- **Tab 双状态模型**：`selectedTab`（持久，写 UserDefaults）+ `displayTab`（渲染态，hover 预览临时切换）；面板关闭/进入固定模式时 displayTab 回退到 selectedTab
- **Hover 展开/折叠**：非固定模式下 `hoverExpandedBundleID` 驱动，App 行+窗口列表容器包装，`isHidden` 轻量切换不触发 forceReload；displayTab 切换/进入固定模式/面板关闭时清空
- **浮球 AI 角标**：非固定模式下复用 `badgeLabel` 显示 `CoderBridgeService.actionableCount`，监听 coderBridgeSessionChanged + panelPinStateChanged 自驱动
```

在「配置迁移」末尾追加：

```
- V4.2: QuickPanelView `currentTab` 拆分为 `selectedTab` + `displayTab`；新增 `hoverExpandedBundleID`；FloatingBallView 新增 AI 角标
```

- [ ] **Step 2: 更新 PRD 和 Architecture 文档**

根据实际改动内容更新 `docs/PRD.md` 和 `docs/Architecture.md` 中相关章节，补充：
- 非固定模式下 hover 交互行为描述
- 浮球角标说明
- Tab 双状态模型架构说明

- [ ] **Step 3: 提交**

```bash
git add CLAUDE.md docs/PRD.md docs/Architecture.md
git commit -m "docs: 更新 CLAUDE.md/PRD/Architecture — hover 交互模式 + 浮球 AI 角标"
```
