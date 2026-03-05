# V3.4 拖拽排序架构设计

> 日期：2026-03-05
> 前置文档：[性能评估报告](v34-drag-perf-eval.md)（方案 C 手动拖拽）

## 0. 功能范围

### 功能 1：星号位置修复
将活跃 Tab 的星号收藏按钮从 App 图标之后移到 App 图标之前。

### 功能 2：App 行拖拽排序
两个 Tab 均支持拖拽 App 行重新排序：
- 活跃 Tab：运行时排序（`runtimeOrder`），不持久化
- 收藏 Tab：持久化排序（`ConfigStore.reorderApps`）

### 非目标
- 窗口行拖拽（仅 App 行支持）
- 跨 Tab 拖拽（不支持从活跃 Tab 拖到收藏 Tab）
- 拖拽过程中的实时行位移动画（mouseUp 时一次性 reloadData 完成排序）
- 新建文件或引入新的抽象层

## 1. 模块划分

所有修改集中在 **3 个现有文件**，预计新增代码 **150~200 行**。

| 文件 | 修改内容 | 新增行数 |
|------|---------|---------|
| `QuickPanelView.swift` — QuickPanelView | 功能 1 星号位置移动；功能 2 拖拽状态管理、runtimeOrder、排序逻辑 | ~80 行 |
| `QuickPanelView.swift` — HoverableRowView | 功能 2 mouseDown/mouseDragged/mouseUp 拖拽交互 | ~90 行 |
| `Constants.swift` | 拖拽阈值常量 | ~3 行 |

**不修改的文件**：ConfigStore.swift（已有 `reorderApps` 方法）、AppMonitor.swift、Models.swift。

## 2. 接口契约

### 2.1 Constants.swift 新增常量

```swift
enum Panel {
    // ... 现有常量 ...
    static let dragThreshold: CGFloat = 5       // 拖拽识别阈值（px）
    static let dragSnapshotAlpha: CGFloat = 0.8  // 浮动快照透明度
    static let dragSnapshotScale: CGFloat = 1.02 // 浮动快照缩放比例
}
```

### 2.2 QuickPanelView 新增属性

```swift
// MARK: - 拖拽排序状态

/// 拖拽进行中标志（抑制 reloadData 全量重建）
private var isDragging = false

/// 活跃 Tab 运行时排序（bundleID 数组，不持久化）
/// 为空时使用 AppMonitor 原始顺序；有值时按此顺序渲染
private var runtimeOrder: [String] = []
```

### 2.3 QuickPanelView 新增/修改方法

| 方法 | 类型 | 说明 |
|------|------|------|
| `reloadData()` | **修改** | 开头加 `if isDragging { return }` 守卫 |
| `buildRunningTabContent()` | **修改** | 用 `runtimeOrder` 对 apps 排序后再渲染 |
| `sortedRunningApps(_:)` → `[RunningApp]` | **新增** | 按 runtimeOrder 排序，新 App 追加末尾 |
| `resetToNormalMode()` | **修改** | 清除 `isDragging`（防止异常残留） |
| `handleDragReorder(from:to:)` | **新增** | 拖拽结束回调：更新 runtimeOrder/ConfigStore，补偿刷新 |
| `appRowIndex(for:)` → `Int?` | **新增** | 根据 bundleID 查找当前列表中的 App 行索引 |

### 2.4 HoverableRowView 新增属性和方法

```swift
// MARK: - 拖拽支持

/// 标记该行是否为 App 行（仅 App 行支持拖拽，窗口行不支持）
var isAppRow: Bool = false

/// 拖拽排序回调：(sourceBundleID, targetBundleID) → Void
/// 由 QuickPanelView 在创建 App 行时设置
var dragReorderHandler: ((_ sourceBundleID: String, _ targetBundleID: String) -> Void)?

// 内部状态
private var dragStartPoint: NSPoint = .zero
private var isDragActive = false
private var dragSnapshotView: NSView?
```

### 2.5 HoverableRowView mouseDown/mouseDragged/mouseUp 协议

```
mouseDown:
  → 记录 dragStartPoint = event.locationInWindow
  → 不调用 super（避免 NSView 默认行为干扰）

mouseDragged:
  → 计算位移 = |current - dragStartPoint|
  → 若 < dragThreshold 且 !isDragActive → 忽略
  → 若 >= dragThreshold 且 !isDragActive → 进入拖拽模式：
      isDragActive = true
      通知 QuickPanelView 设置 isDragging = true
      创建浮动快照视图（dataWithPDF 截图当前行）
      添加到 window?.contentView 最顶层
  → 若 isDragActive → 更新快照位置跟随鼠标 Y 坐标

mouseUp:
  → 若 isDragActive:
      移除快照视图
      计算鼠标释放位置命中的目标 App 行 bundleID
      调用 dragReorderHandler(sourceBundleID, targetBundleID)
      isDragActive = false
  → 若 !isDragActive:
      走原有点击逻辑（hitTest 检查按钮 → clickHandler）
```

### 2.6 拖拽目标定位机制

QuickPanelView 需提供从鼠标坐标反查目标 App 行的能力：

```swift
/// 从 contentStack 的 arrangedSubviews 中找到鼠标命中的 App 行
/// 只匹配 isAppRow == true 的 HoverableRowView
func findTargetAppRow(at windowPoint: NSPoint) -> HoverableRowView?
```

实现方式：遍历 `contentStack.arrangedSubviews`，对每个 `HoverableRowView`（`isAppRow == true`）检查 `convert(windowPoint, from: nil)` 是否在其 bounds 内。列表最多 8 行，O(n) 遍历无性能问题。

## 3. 行为约束（状态机）

### 3.1 状态转换

```
正常状态 ──mouseDown──→ 等待拖拽
    ↑                      │
    │                      ├──mouseDragged(< 5px)──→ 等待拖拽（保持）
    │                      │
    │                      ├──mouseDragged(>= 5px)──→ 拖拽中
    │                      │                              │
    │                      │                              ├──mouseDragged──→ 拖拽中（更新快照位置）
    │                      │                              │
    │                      │                              └──mouseUp──→ 完成排序 → 正常状态
    │                      │
    │                      └──mouseUp(< 5px)──→ 触发点击 → 正常状态
    │
    └─────── reloadData 被 isDragging 守卫阻止 ────────────┘
```

### 3.2 isDragging 守卫的精确行为

```swift
func reloadData() {
    if isDragging { return }  // 完整跳过，包括 updatePanelSize
    // ... 原有逻辑 ...
}
```

拖拽结束时的补偿刷新：
```swift
func handleDragReorder(from sourceBundleID: String, to targetBundleID: String) {
    // 1. 更新数据源排序
    if currentTab == .running {
        // 在 runtimeOrder 中交换位置
        updateRuntimeOrder(moving: sourceBundleID, before: targetBundleID)
    } else {
        // 收藏 Tab：构建新顺序并持久化
        var ids = ConfigStore.shared.appConfigs.map { $0.bundleID }
        // 移动 sourceBundleID 到 targetBundleID 的位置
        moveElement(&ids, from: sourceBundleID, to: targetBundleID)
        ConfigStore.shared.reorderApps(ids)
    }
    // 2. 关闭守卫 + 补偿刷新
    isDragging = false
    lastStructuralKey = ""
    reloadData()
}
```

### 3.3 runtimeOrder 与 AppMonitor 数据同步

```swift
/// 按 runtimeOrder 排序运行中 App 列表
/// 规则：runtimeOrder 中存在的 bundleID 按顺序排列，新出现的 App 追加末尾
private func sortedRunningApps(_ apps: [RunningApp]) -> [RunningApp] {
    guard !runtimeOrder.isEmpty else { return apps }
    let orderMap = Dictionary(uniqueKeysWithValues: runtimeOrder.enumerated().map { ($1, $0) })
    let maxOrder = runtimeOrder.count
    return apps.sorted { a, b in
        let orderA = orderMap[a.bundleID] ?? (maxOrder + apps.firstIndex(where: { $0.bundleID == a.bundleID })!)
        let orderB = orderMap[b.bundleID] ?? (maxOrder + apps.firstIndex(where: { $0.bundleID == b.bundleID })!)
        return orderA < orderB
    }
}
```

在 `buildRunningTabContent()` 中使用：
```swift
private func buildRunningTabContent() {
    let apps = sortedRunningApps(
        AppMonitor.shared.runningApps.filter { !$0.windows.isEmpty }
    )
    buildRunningAppList(apps: apps, emptyText: "没有活跃窗口的应用")
}
```

### 3.4 边界处理

| 场景 | 处理 |
|------|------|
| 拖拽释放在列表外部（空白区域） | 不执行排序，恢复原状 |
| 拖拽释放在原位（sourceBundleID == targetBundleID） | 不执行排序，直接恢复 |
| 拖拽释放在窗口行上 | 不匹配（窗口行 isAppRow=false），不执行排序 |
| 拖拽过程中面板被关闭（mouseExited 触发收起） | isDragging 为 true 时，mouseExited 不触发面板收起 |
| 拖拽过程中面板被快捷键隐藏 | resetToNormalMode 清除 isDragging |
| 活跃 Tab 下 App 退出导致列表变短 | isDragging 守卫阻止 reloadData，拖拽结束后补偿刷新时自然去掉已退出 App |
| 收藏 Tab 列表为空 | 无 App 行可拖拽，不触发 |
| 活跃 Tab 只有 1 个 App | 无目标可交换，拖拽释放后不执行排序 |

### 3.5 面板收起防护

QuickPanelView 的 `mouseExited` 需增加拖拽检查：

```swift
override func mouseExited(with event: NSEvent) {
    // 拖拽中不触发收起
    if isDragging { return }
    // ... 原有逻辑 ...
}
```

## 4. 功能 1：星号位置修复

### 修改位置

`QuickPanelView.swift` → `createAppRow()` 方法，第 540~573 行区域。

### 修改内容

将星号按钮的 `rowStack.addArrangedSubview(starButton)` 从 App 图标之后移到 App 图标之前。

当前顺序（第 540~573 行）：
```
statusDot → iconView → starButton → nameLabel
```

修改后顺序：
```
statusDot → starButton → iconView → nameLabel
```

具体操作：将第 554~573 行的星号按钮创建代码块移到第 544 行（`rowStack.addArrangedSubview(statusDot)` 之后、iconView 创建之前）。

## 5. 验收用例

### 用例 1：基本拖拽排序（活跃 Tab）
1. 打开面板，切换到活跃 Tab，确认有 >= 2 个 App
2. 按住第 2 个 App 行，拖拽到第 1 个位置
3. 释放鼠标
4. **预期**：App 顺序交换，窗口列表跟随其所属 App

### 用例 2：基本拖拽排序（收藏 Tab）+ 持久化
1. 打开面板，切换到收藏 Tab，确认有 >= 2 个收藏 App
2. 拖拽排序
3. 关闭面板，重新打开
4. **预期**：排序保持不变

### 用例 3：点击不受影响
1. 单击 App 行（无拖拽位移）
2. **预期**：触发折叠/展开（运行中有窗口）或启动（未运行）
3. 单击星号按钮
4. **预期**：切换收藏状态（不触发拖拽）

### 用例 4：拖拽期间定时器刷新不打断
1. 拖拽一个 App 行，保持不放
2. 等待 > 1 秒（定时器会触发 reloadData）
3. **预期**：拖拽不被打断，浮动快照正常跟随鼠标

### 用例 5：拖拽释放到无效区域
1. 拖拽 App 行到列表底部空白区域并释放
2. **预期**：不执行排序，列表恢复原状

### 用例 6：活跃 Tab 排序在 App 退出后保持
1. 活跃 Tab 下拖拽排序 A、B、C 为 C、A、B
2. 不触发任何 App 退出
3. 定时器刷新多次后
4. **预期**：顺序仍为 C、A、B（不被字母排序覆盖）

### 用例 7：星号位置验证
1. 打开面板，活跃 Tab
2. **预期**：每个 App 行的星号在图标左侧（顺序：状态点 → 星号 → 图标 → 名称）

### 用例 8：拖拽中面板不自动收起
1. 拖拽 App 行时鼠标移出面板范围
2. **预期**：面板不收起，拖拽继续
3. 释放鼠标后鼠标仍在面板外
4. **预期**：此时面板正常触发收起逻辑

## 6. 影响分析（回归风险）

| 风险点 | 严重度 | 说明 | 防护 |
|--------|--------|------|------|
| mouseUp 点击逻辑被破坏 | **高** | HoverableRowView 的 mouseUp 需同时处理点击和拖拽结束 | isDragActive 标志位精确区分；mouseUp 中 `if !isDragActive` 走原有点击路径 |
| reloadData 被永久阻塞 | **高** | 若 isDragging 未被正确重置 | resetToNormalMode 兜底清除；mouseUp 必定重置 isDragActive 并回调 handleDragReorder（内部重置 isDragging） |
| 收藏排序被 appStatusChanged 通知覆盖 | **中** | ConfigStore.addApp/removeApp 会 post appStatusChanged | reorderApps 内部先更新 appConfigs 再 save，通知触发的 reloadData 从 appConfigs 读取最新顺序 |
| 活跃 Tab 排序与 AppMonitor 字母排序冲突 | **中** | AppMonitor.runningApps 始终按字母排序返回 | sortedRunningApps 在渲染时重排，不修改 AppMonitor 数据 |
| 浮动快照视图泄漏 | **低** | mouseUp 未触发时快照残留 | mouseUp 必定移除快照；resetToNormalMode 兜底移除 |
| 星号位置修改破坏 Auto Layout | **低** | addArrangedSubview 顺序变化 | 星号按钮的约束（18x18 固定尺寸）不依赖相邻视图 |

## 7. 防过度设计自查

- [x] 不创建新文件 — 所有修改在 QuickPanelView.swift 和 Constants.swift 内完成
- [x] 不引入新的抽象层 — 无 DragManager/DragProtocol，拖拽逻辑直接写在 HoverableRowView
- [x] 代码量控制 — 预计 ~170 行新代码（HoverableRowView ~90 行 + QuickPanelView ~80 行）
- [x] 不修改 ConfigStore — 复用现有 `reorderApps()` 方法
- [x] 不修改 AppMonitor — 渲染时排序，不改变数据源顺序
- [x] 不引入新依赖 — 纯 AppKit 鼠标事件 API
