# V3.6 QuickPanelView 模块化拆分架构设计

## 1.0 需求澄清

QuickPanelView.swift 当前 1149 行，是一个典型的 God Object，承担了 UI 骨架搭建、Tab 切换、数据加载/差分更新、App 行构建、窗口行构建、右键菜单创建与 action 处理、面板尺寸管理等 7 项独立职责。

本次重构的三个目标：

1. **模块化**：按"独立变化的理由"拆分为 3 个文件，降低单文件认知负荷
2. **消除重复**：统一 `lastStructuralKey = "" + reloadData()` 模式为 `forceReload()`；提取 App 列表构建模板
3. **修复缺陷**：消除 `handleToggleFavorite` 双重 reloadData；删除无用的 `runtimeOrder` 变量

## 1.1 模块划分

按"独立变化的理由"拆分为 3 个文件，使用 `extension QuickPanelView` 方式，不引入新类型或协议。

### 文件 1：`QuickPanelView.swift`（主文件，约 580 行）

**职责**：UI 骨架 + 状态管理 + Tab 切换 + reloadData 调度 + 通知监听 + 工具方法

保留内容：
- `QuickPanelTab` 枚举
- `QuickPanelView` 类定义（所有属性声明）
- `setupView()` / `setupNotifications()` / 追踪区域
- `switchTab()` / `updateTabButtonStyles()`
- `reloadData()` / `buildStructuralKey()` / `updateWindowTitles()` / `resolveDisplayTitle()`
- `forceReload()` **（新增）**
- `resetToNormalMode()`
- `buildContent()` / `buildRunningTabContent()` / `buildFavoritesTabContent()` / `buildRunningAppList()`
- `updatePanelSize()`
- `openMainKanban()` / `launchApp()` / `openAccessibilitySettings()`
- `createPermissionHintView()` / `addEmptyStateLabel()`
- `cachedSymbol()` / `createLabel()`
- `HoverableRowView` 类
- `FlippedClipView` 类

**变化理由**：面板整体结构/布局/数据流发生变化时修改此文件。

### 文件 2：`QuickPanelRowBuilder.swift`（约 250 行）

**职责**：App 行和窗口行的视图构建

```swift
extension QuickPanelView {
    // App 行构建
    func createRunningAppRow(app: RunningApp) -> NSView
    func createFavoriteAppRow(config: AppConfig, runningApp: RunningApp?, isRunning: Bool) -> NSView
    func createAppRow(bundleID: String, name: String, icon: NSImage, isRunning: Bool, windows: [WindowInfo]) -> NSView

    // 窗口行构建
    func createWindowList(windows: [WindowInfo], bundleID: String) -> NSView
    func createWindowRow(windowInfo: WindowInfo, bundleID: String) -> NSView

    // 辅助方法（从 createAppRow 提取）
    func createSpacer() -> NSView
    func configureAppRowClickHandler(row: HoverableRowView, bundleID: String, isRunning: Bool, hasWindows: Bool)
}
```

**变化理由**：行的视觉样式/交互行为发生变化时修改此文件，不影响整体骨架和菜单逻辑。

### 文件 3：`QuickPanelMenuHandler.swift`（约 200 行）

**职责**：所有右键菜单创建 + `@objc` action handler + 星号收藏切换

```swift
extension QuickPanelView {
    // 窗口右键菜单
    func createWindowContextMenu(bundleID: String, windowInfo: WindowInfo) -> NSMenu
    @objc func handleCloseWindow(_ sender: NSMenuItem)
    @objc func handleRenameWindow(_ sender: NSMenuItem)
    @objc func handleClearRename(_ sender: NSMenuItem)

    // 收藏右键菜单
    func createFavoriteContextMenu(bundleID: String) -> NSMenu
    @objc func handlePinToTop(_ sender: NSMenuItem)
    @objc func handleRemoveFavorite(_ sender: NSMenuItem)

    // 星号收藏按钮
    @objc func handleToggleFavorite(_ sender: NSButton)

    // 重命名工具方法
    static func renameKey(bundleID: String, windowID: CGWindowID) -> String
}
```

**变化理由**：菜单项增删/action 逻辑变更时修改此文件，不影响行构建和整体骨架。

### 防过度设计自查

| 检查项 | 结论 |
|--------|------|
| 是否引入了新 protocol？ | 否，纯 extension 拆分 |
| 是否引入了新 class/struct？ | 否，不新增任何类型 |
| 是否引入了 delegate/回调抽象？ | 否，直接调用 `forceReload()` |
| 是否改变了数据流方向？ | 否，通知驱动架构不变 |
| 是否增加了文件间的依赖复杂度？ | 否，extension 天然可访问 internal 成员 |
| 拆分后每个文件是否有独立的变更理由？ | 是（骨架/行样式/菜单逻辑） |

## 1.2 接口契约

### 可见性调整

拆分为 extension 后，`private` 成员无法跨文件访问。需要将以下成员从 `private` 调整为 `internal`（无修饰符）：

#### 主文件中需要 internal 的属性（供 RowBuilder 和 MenuHandler 访问）

| 属性 | 访问者 | 理由 |
|------|--------|------|
| `currentTab` | RowBuilder | `createAppRow` 中判断是否显示星号按钮 |
| `contentStack` | RowBuilder | `buildRunningAppList` 中添加子视图 |
| `collapsedApps` | RowBuilder | `createAppRow` 中判断折叠状态 |
| `highlightedWindowID` | RowBuilder | `createWindowRow` 中设置高亮 |
| `windowTitleLabels` | RowBuilder | `createWindowRow` 中注册标题 label |
| `windowRowViewMap` | RowBuilder | `createWindowRow` 中注册行视图 |

#### 主文件中需要 internal 的方法（供 RowBuilder 和 MenuHandler 调用）

| 方法 | 访问者 | 理由 |
|------|--------|------|
| `forceReload()` | RowBuilder, MenuHandler | 替代散布的 `lastStructuralKey = "" + reloadData()` |
| `createLabel(_:size:color:)` | RowBuilder | 创建文本标签 |
| `cachedSymbol(name:size:weight:)` | RowBuilder | 创建 SF Symbol 图片 |
| `resolveDisplayTitle(bundleID:windowInfo:)` | RowBuilder | 解析窗口显示标题 |
| `launchApp(bundleID:)` | RowBuilder | App 行点击启动 |
| `createWindowContextMenu(bundleID:windowInfo:)` | RowBuilder | `createWindowRow` 中设置右键菜单 |
| `createFavoriteContextMenu(bundleID:)` | RowBuilder | `createFavoriteAppRow` 中设置右键菜单 |
| `renameKey(bundleID:windowID:)` | MenuHandler, 主文件 | 重命名 key 生成 |

#### 保持 private 的成员（仅单文件内部使用）

- 主文件：`lastStructuralKey`、`trackingArea`、所有子视图属性（topBar、scrollView 等）、`setupView()`、`setupNotifications()`、`buildStructuralKey()`、`updateWindowTitles()`、`updatePanelSize()`
- RowBuilder：`configureAppRowClickHandler()` 如果仅 `createAppRow` 内部调用则保持 `private`——但 extension 中的 `private` 等同于 `fileprivate`，所以实际上在同文件内可见，足够使用
- MenuHandler：各 `@objc` handler 方法在同文件内 `private` 即可（Objective-C runtime 通过 selector 调用，不受 Swift 可见性限制——但 `@objc private` 在 extension 中无法编译，需改为 `@objc func`）

#### 关键约束

1. `forceReload()` 定义在主文件，签名为 `func forceReload()`（internal），RowBuilder 和 MenuHandler 直接调用
2. `@objc` 方法不能标记为 `private`（extension 中 `@objc private` 会编译错误），统一使用 `@objc func`（internal）
3. `HoverableRowView` 保持在主文件中，因为 RowBuilder 和 MenuHandler 都依赖它

## 1.3 行为约束

### 1.3.1 forceReload() 语义

```swift
/// 强制全量重建：清除结构快照 + 触发 reloadData
func forceReload() {
    lastStructuralKey = ""
    reloadData()
}
```

所有现有的 `lastStructuralKey = "" + reloadData()` 散布点（共 12 处）统一替换为 `forceReload()` 调用：

| 位置 | 原代码 | 替换 |
|------|--------|------|
| `accessibilityDidGrant` | `lastStructuralKey = ""; reloadData()` | `forceReload()` |
| `switchTab` | `lastStructuralKey = ""; reloadData()` | `forceReload()` |
| `resetToNormalMode` | `lastStructuralKey = ""` | 保持原样（此处不调用 reloadData） |
| App 折叠/展开点击 | `lastStructuralKey = ""; reloadData()` | `forceReload()` |
| 无窗口 App 点击 | `lastStructuralKey = ""; reloadData()` | `forceReload()` |
| 窗口行点击 | `lastStructuralKey = ""; reloadData()` | `forceReload()` |
| `handleCloseWindow` | `lastStructuralKey = ""; reloadData()` | `forceReload()` |
| `handleRenameWindow`（两处） | `lastStructuralKey = ""; reloadData()` | `forceReload()` |
| `handleClearRename` | `lastStructuralKey = ""; reloadData()` | `forceReload()` |
| `handlePinToTop` | `lastStructuralKey = ""; reloadData()` | `forceReload()` |
| `handleToggleFavorite` | `lastStructuralKey = ""; reloadData()` | 见 1.3.2 |

注意：`resetToNormalMode` 中的 `lastStructuralKey = ""` 不伴随 `reloadData()` 调用，保持原样即可。

### 1.3.2 handleToggleFavorite 双重刷新修复

**问题**：`handleToggleFavorite` 调用 `ConfigStore.addApp/removeApp` 后，ConfigStore 内部会发送 `appStatusChanged` 通知触发一次 `reloadData()`，然后 `handleToggleFavorite` 又显式调用 `lastStructuralKey = "" + reloadData()`，导致双重刷新。

**修复方案**：去掉 `handleToggleFavorite` 中的显式 `forceReload()` 调用，完全依赖 ConfigStore 发出的通知。但通知触发的 `reloadData()` 走差分路径，可能不会全量重建。因此需要确保通知处理中也走强制重建路径。

具体修改：

```swift
// handleToggleFavorite 修复后
@objc func handleToggleFavorite(_ sender: NSButton) {
    guard let bundleID = objc_getAssociatedObject(sender, &bundleIDKey) as? String else { return }
    let name = objc_getAssociatedObject(sender, &displayNameKey) as? String ?? ""

    if ConfigStore.shared.isFavorite(bundleID) {
        ConfigStore.shared.removeApp(bundleID)
    } else {
        ConfigStore.shared.addApp(bundleID, displayName: name)
    }
    // 不再显式调用 forceReload()
    // ConfigStore.addApp/removeApp 内部发送 appStatusChanged 通知
    // 通知会触发 appStatusDidChange → reloadData()
    // 由于收藏状态变化会改变 structuralKey，reloadData 会自动全量重建
}
```

**验证**：`buildStructuralKey()` 中活跃 Tab 包含 `fav` 标记（`ConfigStore.shared.isFavorite(app.bundleID) ? "F" : ""`），收藏状态变化会导致 structuralKey 不同，`reloadData()` 会自动走全量重建路径。所以不需要显式清空 `lastStructuralKey`，通知触发的普通 `reloadData()` 即可正确处理。

### 1.3.3 runtimeOrder 变量删除

`runtimeOrder`（第 46 行）声明后从未被读取或写入（除初始化为空数组外），直接删除。

### 1.3.4 统一 App 列表构建模板

当前 `buildRunningTabContent` 和 `buildFavoritesTabContent` 存在结构重复（空状态判断 → 遍历构建 App 行 → 可选展开窗口列表 → 权限提示）。

**设计方案**：不提取为独立方法（因为收藏 Tab 的数据源和行创建逻辑与活跃 Tab 差异较大），而是保持现有的 `buildRunningAppList` 供活跃 Tab 使用，收藏 Tab 的 `buildFavoritesTabContent` 保持独立。

理由：
- 活跃 Tab 数据源是 `[RunningApp]`，收藏 Tab 数据源是 `[AppConfig]` + 可选的 `RunningApp`
- 收藏 Tab 需要处理未运行 App 的图标获取和右键菜单设置
- 强行统一会引入复杂的泛型或协议抽象，违反"不过度设计"原则

### 1.3.5 createSpacer() 提取

当前 `createAppRow` 和 `createWindowRow` 中重复创建弹性空间视图（Spacer），提取为统一方法：

```swift
func createSpacer() -> NSView {
    let spacer = NSView()
    spacer.translatesAutoresizingMaskIntoConstraints = false
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    return spacer
}
```

### 1.3.6 handleRenameWindow UI 与业务分离

将 `handleRenameWindow` 拆为两步：

```swift
// 步骤 1：展示弹窗，返回用户输入（可选）
private func showRenameAlert(currentName: String, originalTitle: String) -> String? {
    let alert = NSAlert()
    alert.messageText = "重命名窗口"
    alert.informativeText = "原始标题：\(originalTitle)"
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
    guard response == .alertFirstButtonReturn else { return nil }
    return textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
}

// 步骤 2：保存重命名结果
private func applyWindowRename(key: String, newName: String, originalTitle: String) {
    if !newName.isEmpty && newName != originalTitle {
        ConfigStore.shared.windowRenames[key] = newName
    } else if newName == originalTitle || newName.isEmpty {
        ConfigStore.shared.windowRenames.removeValue(forKey: key)
    }
    ConfigStore.shared.saveWindowRenames()
    forceReload()
}
```

### 1.3.7 HoverableRowView 属性分类

当前 `HoverableRowView` 有 6 个公开属性，区分为两类但不改变可见性（避免 breaking change）：

**构建配置（创建时设置，之后不变）**：
- `bundleID: String?`
- `windowID: CGWindowID?`
- `windowInfo: WindowInfo?`
- `contextMenuProvider: (() -> NSMenu?)?`
- `clickHandler: (() -> Void)?`

**运行时状态（生命周期中可变）**：
- `isHighlighted: Bool`

通过 MARK 注释分组即可，不引入新类型：

```swift
// MARK: - 构建配置（创建时设置）
var bundleID: String?
var windowID: CGWindowID?
// ...

// MARK: - 运行时状态
var isHighlighted = false
```

## 1.4 验收用例

| ID | 场景 | 验证方法 | 预期结果 |
|----|------|----------|----------|
| TC-01 | 文件拆分后编译 | `make build` | 编译通过，无 warning |
| TC-02 | 活跃 Tab 功能 | 打开面板 → 查看活跃 App 列表 → 点击折叠/展开 → 点击窗口行前置 | 列表正确显示，折叠/展开动画正常，窗口成功前置并高亮 |
| TC-03 | 收藏 Tab 功能 | 切换到收藏 Tab → 查看收藏列表 → 右键置顶 → 右键取消收藏 | 收藏列表正确显示，置顶生效，取消收藏后列表更新 |
| TC-04 | 窗口右键菜单 | 右键窗口行 → 重命名 → 确认 → 右键 → 清除自定义名称 → 右键 → 关闭窗口 | 重命名生效，清除后恢复原标题，关闭后窗口从列表消失 |
| TC-05 | forceReload 差分更新 | 面板打开 → 等待窗口标题通过 AX 补全 → 观察是否只更新标题而非全量重建 | 标题变化走 `updateWindowTitles` 轻量路径，无闪烁 |
| TC-06 | 星号收藏无双重刷新 | 活跃 Tab → 点击星号收藏/取消收藏 | 收藏状态正确切换，面板只刷新一次（可通过 debugLog 或断点验证 `reloadData` 调用次数） |
| TC-07 | runtimeOrder 删除 | `make build` + 全局搜索 `runtimeOrder` | 编译通过，无残留引用 |
| TC-08 | HoverableRowView 交互 | 鼠标 hover App 行/窗口行 → 点击 → 右键菜单 | hover 高亮正常，点击触发对应操作，右键菜单正常弹出 |

## 1.5 非目标声明

本次重构 **不做** 以下事项：

1. **不引入 MVVM / Coordinator / 响应式框架**：保持现有的 NSView + 命令式构建模式
2. **不拆分 HoverableRowView 为独立文件**：它只有约 90 行，且被主文件和 RowBuilder 共同使用，留在主文件最合适
3. **不修改数据流方向**：通知驱动架构（NotificationCenter）不变
4. **不修改 ConfigStore / WindowService / AppMonitor 的接口**
5. **不修改面板窗口（QuickPanelWindow）的任何逻辑**
6. **不优化 buildStructuralKey 的性能**（当前没有性能问题）
7. **不调整 `buildFavoritesTabContent` 与 `buildRunningAppList` 的统一**（数据源差异大，强行统一会过度设计）
8. **不修改 `private` 关联对象 key（`bundleIDKey`、`displayNameKey`）的位置**——它们是文件级变量，拆分后需要移至 MenuHandler 文件顶部（因为 `handleToggleFavorite` 在 MenuHandler 中使用）

## 1.6 影响分析（增量场景）

### 拆分后的典型修改场景

| 场景 | 修改文件 | 不受影响的文件 |
|------|----------|----------------|
| 新增 App 行上的 UI 元素（如拖拽排序手柄） | `QuickPanelRowBuilder.swift` | 主文件、MenuHandler |
| 新增窗口右键菜单项（如"最小化窗口"） | `QuickPanelMenuHandler.swift` | 主文件、RowBuilder |
| 新增第三个 Tab（如"最近"） | `QuickPanelView.swift` | RowBuilder（复用已有行构建）、MenuHandler |
| 修改差分更新策略 | `QuickPanelView.swift` | RowBuilder、MenuHandler |
| 修改窗口行高亮样式 | `QuickPanelRowBuilder.swift` | 主文件、MenuHandler |
| 新增"批量关闭窗口"菜单功能 | `QuickPanelMenuHandler.swift` | 主文件、RowBuilder |

### 关联文件对象 key 迁移

拆分后，`private var bundleIDKey` 和 `private var displayNameKey` 需要注意放置位置：
- `bundleIDKey` / `displayNameKey` 在 `createAppRow`（RowBuilder）中写入，在 `handleToggleFavorite`（MenuHandler）中读取
- 解决方案：将这两个变量声明在 RowBuilder 文件顶部（文件级 `private`），MenuHandler 文件中通过将其改为 `internal` 或在两个文件中各自声明——但关联对象 key 只需要地址唯一，所以**最简单的方案是将它们提升为 QuickPanelView 的 static 属性**：

```swift
// 在主文件 QuickPanelView 类内
static var bundleIDKey: UInt8 = 0
static var displayNameKey: UInt8 = 0
```

这样 RowBuilder 和 MenuHandler 的 extension 都可以通过 `Self.bundleIDKey` / `QuickPanelView.bundleIDKey` 访问。

### 编译顺序

三个文件无编译顺序依赖（Swift 编译器统一处理同一 module 内的所有文件）。Makefile 中只需将两个新文件加入源文件列表即可。
