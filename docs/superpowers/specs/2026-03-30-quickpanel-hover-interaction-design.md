# 快捷面板 Hover 交互模式 + 浮球 AI 角标

## 概述

以 `isPanelPinned` 为分界，快捷面板在固定/非固定两种模式下提供不同的交互范式。非固定模式下通过 hover 驱动 Tab 切换和 App 展开/折叠，降低交互成本；同时在浮球上显示 AI 消息数角标，弥补面板收起后信息不可见的问题。

## 模式对照

| 维度 | 固定模式 (pinned) | 非固定模式 (unpinned) |
|---|---|---|
| Tab 切换 | 点击 | hover 临时预览，点击持久选择 |
| App 展开/折叠 | 点击切换 collapsedApps | 默认折叠，hover 展开，离开立即折叠 |
| App 行点击 | 切换折叠/展开（现状） | 激活第一个窗口 |
| 窗口行点击 | 激活窗口（不变） | 激活窗口（不变） |
| 浮球 pinBadge | 显示图钉 | 隐藏 |
| 浮球 badgeLabel | 隐藏 | 显示 AI actionableCount（>0 时） |

## 1. Tab 双状态模型

### 问题

现有 `switchTab()` 同时执行 `currentTab = tab` + `saveLastPanelTab(tab)` + `forceReload()`。hover 触发会导致：
- 持久化污染：划过即写入 UserDefaults
- 状态泄漏：QuickPanelView 是长生命周期对象，`resetToNormalMode()` 不重置 `currentTab`，hover 预览的 Tab 会残留到下次打开

### 设计

拆分为两个状态：

- `selectedTab: QuickPanelTab` — 用户点击选择的持久 Tab，由 `saveLastPanelTab()` 写入 UserDefaults
- `displayTab: QuickPanelTab` — 当前实际显示的 Tab，驱动 UI 渲染

规则：
- 固定模式：`displayTab` 始终等于 `selectedTab`
- 非固定模式：hover 只改 `displayTab`，不动 `selectedTab`
- 面板关闭时（`resetToNormalMode`）：`displayTab` 回退到 `selectedTab`
- 切换到固定模式时：`displayTab` 回退到 `selectedTab`

现有所有读 `currentTab` 的地方改读 `displayTab`。`switchTab()` 同时设置两者 + `saveLastPanelTab()`。

### 新增方法

```swift
/// 非固定模式 hover 临时预览 Tab（不持久化，不改 selectedTab）
private func hoverPreviewTab(_ tab: QuickPanelTab) {
    guard displayTab != tab else { return }
    displayTab = tab
    updateTabButtonStyles()
    forceReload()
}
```

### Tab 按钮 hover 触发

给 `runningTabButton` / `favoritesTabButton` / `aiTabButton` 各添加 `NSTrackingArea`。`mouseEntered` 时检查 `!isPanelPinned`，满足则调用 `hoverPreviewTab()`。

click action 保留，固定和非固定模式下都可点击持久切换。

## 2. App 行 Hover 展开/折叠

### 问题

现有 `collapsedApps` 机制通过 click 触发 `forceReload()` 全量重建。如果 hover 也走这条路：
- 频繁 `forceReload` 导致闪烁
- `collapsedApps` 状态在 pinned/unpinned 模式间交叉污染
- 后台 `windowsDidChange` / `appStatusDidChange` 触发 `reloadData()` 全量重建会冲掉 hover 展开态

### 设计

新增属性 `hoverExpandedBundleID: String?`，仅在非固定模式下使用。

#### 构建时

`buildContent()` 中将 App 行 + 窗口列表包在一个容器 `NSView` 中：

- 容器添加 `NSTrackingArea`（`mouseEnteredAndExited + activeAlways + inVisibleRect`）
- 非固定模式下窗口列表默认 `isHidden = true`
- 如果 `hoverExpandedBundleID == bundleID`，则初始 `isHidden = false`（应对 reloadData 重建后恢复状态）

#### Hover 逻辑

由 QuickPanelView 统一维护 `hoverExpandedBundleID`：

```swift
// 容器 mouseEntered:
hoverExpandedBundleID = bundleID   // 立即设新值，展开窗口列表

// 容器 mouseExited:
if hoverExpandedBundleID == bundleID {  // 只有还是自己才清除
    hoverExpandedBundleID = nil         // 折叠窗口列表
}
```

这样即使 exited 和 entered 顺序有微差（鼠标从 App A 容器滑向 App B 容器），新容器的 entered 先覆盖旧值，旧容器的 exited 发现值已变就不操作，不会闪烁。

窗口列表的显示/隐藏通过 `isHidden` 切换，不触发 `forceReload`。

#### 与 reloadData 对齐

- `buildStructuralKey()`：非固定模式下折叠态不纳入 key（`collapsedApps` 部分统一用 `"H"` 占位），避免 hover 展开/折叠触发全量重建
- `buildContent()`：重建时检查 `hoverExpandedBundleID`，匹配的容器窗口列表设 `isHidden = false`
- 后台 `windowsDidChange` 触发重建后，hover 展开态通过上述机制自动恢复

#### 与 collapsedApps 隔离

- 非固定模式下 App 行的 `clickHandler` 改为激活该 App 的第一个窗口（和无窗口 App 行为一致），不操作 `collapsedApps`
- `collapsedApps` 只在固定模式下使用
- 模式切换时不需要互相同步

#### 作用范围

仅在「活跃」「关注」Tab 且 `!isPanelPinned` 时生效。AI Tab 保持现有的 `collapsedGroups` 点击折叠逻辑不变。

## 3. 浮球 AI 消息数角标

### 设计

复用现有 `badgeLabel`（右上角药丸形红底白字），与 `pinBadgeView` 互斥（非固定模式下 pinBadge 隐藏）。

#### 数据源

`CoderBridgeService.shared.actionableCount`，与 QuickPanel 的 `aiBadgeLabel` 使用同一数据源。

#### 触发机制

FloatingBallView 直接监听两个现有通知，不引入新通知：

- `coderBridgeSessionChanged` — actionableCount 变化时重新计算
- `panelPinStateChanged` — 模式切换时决定是否显示

#### 显示逻辑

```swift
func updateAIBadge() {
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

#### 修改点

- 移除现有 `updateBadge(_ count: Int)` 中的强制隐藏逻辑
- 在 `setupNotifications()` 中添加 `coderBridgeSessionChanged` 监听
- `panelPinStateChanged` 回调中同步调用 `updateAIBadge()`

## 4. 涉及的文件和改动范围

| 文件 | 改动 |
|---|---|
| `QuickPanelView.swift` | `currentTab` 拆分为 `selectedTab` + `displayTab`；新增 `hoverPreviewTab()`；新增 `hoverExpandedBundleID`；Tab 按钮添加 tracking area；非固定模式下容器构建 + hover 展开逻辑；`buildStructuralKey()` 非固定模式折叠态占位；`resetToNormalMode()` 回退 `displayTab` |
| `QuickPanelRowBuilder.swift` | `createAppRow()` 返回的行 + 窗口列表包在容器中；`configureClickHandler()` 非固定模式下改为激活窗口 |
| `FloatingBallView.swift` | 新增 `updateAIBadge()`；监听 `coderBridgeSessionChanged`；`panelPinStateChanged` 回调同步刷新 badge |

## 5. 不变的部分

- 固定模式下所有现有行为完全保留
- 窗口行点击激活逻辑不变
- AI Tab 的 `collapsedGroups` 折叠逻辑不变
- 右键菜单不变
- 面板 500ms dismiss timer 不变
- 计时器栏不变
