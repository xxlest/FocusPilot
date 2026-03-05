# FocusPilot V3.5 增量架构设计

## 概述

V3.5 包含三项增量功能：活跃列表星号位置调整、收藏 Tab 拖动排序、窗口重命名绑定窗口实例。三项需求互相独立，可并行实现。

---

## 1. 影响分析

### 需修改的文件

| 文件 | 需求 1 | 需求 2 | 需求 3 | 修改范围 |
|------|--------|--------|--------|----------|
| `QuickPanel/QuickPanelView.swift` | Y | Y | Y | 主要修改文件 |
| `Services/ConfigStore.swift` | - | - | - | 无需修改（reorderApps 已存在） |
| `Models/Models.swift` | - | - | - | 无需修改（WindowInfo.id 已是 CGWindowID） |
| `Helpers/Constants.swift` | - | - | - | 无需修改（拖拽常量已存在） |

### 回归风险点

1. **需求 1**：纯视图顺序调整，风险极低。需验证星号按钮的关联对象（bundleID/displayName）在位置变化后仍正常工作。
2. **需求 2**：拖拽过程中 `isDragging=true` 会抑制 `reloadData`，需确保拖拽结束后正确恢复并触发刷新。活跃 Tab 已有 `runtimeOrder` 拖拽逻辑（但当前代码中未实现拖拽手势），收藏 Tab 的拖拽实现应复用相同模式。
3. **需求 3**：renameKey 格式变更会导致旧的 `bundleID::title` 格式重命名数据失效。需要清理旧数据或静默忽略。

---

## 2. 模块划分

### 需求 1：活跃列表星号位置调整

**修改方法**：`QuickPanelView.createAppRow(bundleID:name:icon:isRunning:windows:)`

**当前代码**（第 554-577 行）：
```
statusDot → starButton → iconView → nameLabel
```

**目标代码**：
```
starButton → statusDot → iconView → nameLabel
```

**具体操作**：将第 559-577 行（星号按钮创建和添加）移动到第 554-556 行（状态点创建和添加）之前。仅调整 `addArrangedSubview` 的调用顺序。

### 需求 2：收藏 Tab 拖动排序

**涉及方法**：

| 方法 | 操作 | 说明 |
|------|------|------|
| `createFavoriteAppRow(config:runningApp:isRunning:)` | 修改 | 为返回的行添加拖拽手势识别 |
| `buildFavoritesTabContent()` | 修改 | 为拖拽提供行索引映射 |
| 新增：拖拽手势处理方法组 | 新增 | `handleFavDragStart`、`handleFavDragMove`、`handleFavDragEnd` |

**新增状态属性**：
```swift
/// 收藏 Tab 拖拽状态
private var favDragSourceIndex: Int?          // 拖拽源行索引
private var favDragSnapshot: NSView?          // 浮动快照视图
private var favDragMouseDown: NSPoint?        // 按下位置（用于阈值判断）
private var favDragAppRows: [NSView] = []     // 当前收藏行视图数组（用于位置计算）
```

### 需求 3：窗口重命名绑定窗口实例

**涉及方法**：

| 方法 | 操作 | 说明 |
|------|------|------|
| `renameKey(bundleID:title:)` | 修改签名+实现 | 改为 `renameKey(bundleID:windowID:)` |
| `resolveDisplayTitle(bundleID:windowInfo:)` | 修改 | 调用新签名 |
| `handleRenameWindow(_:)` | 修改 | 使用新 renameKey |
| `handleClearRename(_:)` | 无需修改 | 仍然通过 representedObject 传递 key 字符串 |
| `createWindowContextMenu(bundleID:windowInfo:)` | 修改 | 使用新 renameKey 检查是否已重命名 |

---

## 3. 接口契约

### 3.1 renameKey 签名变更

**旧签名**：
```swift
static func renameKey(bundleID: String, title: String) -> String
// 返回 "bundleID::title"
```

**新签名**：
```swift
static func renameKey(bundleID: String, windowID: CGWindowID) -> String
// 返回 "bundleID::windowID"  (例如 "com.apple.Safari::12345")
```

所有调用点统一传入 `windowInfo.id`（类型 `CGWindowID` 即 `UInt32`）。

### 3.2 ConfigStore 接口（无变更）

- `reorderApps(_ ids: [String])` — 收藏 Tab 拖拽排序完成时调用，传入重排后的 bundleID 数组
- `windowRenames: [String: String]` — key 格式从 `bundleID::title` 变为 `bundleID::windowID`
- `saveWindowRenames()` — 保存变更

### 3.3 拖拽与 reloadData 的互斥

拖拽期间 `isDragging = true`，`reloadData()` 入口处检测到后直接 `return`（已有此逻辑，第 341 行）。拖拽结束时设置 `isDragging = false` 并调用 `reloadData()`。

---

## 4. 行为约束

### 4.1 需求 1：星号位置调整

- 仅影响活跃 Tab（`currentTab == .running` 分支）
- 收藏 Tab 的 `createFavoriteAppRow` 不显示星号，不受影响
- 视图元素顺序变为：星号 -> 状态点 -> 图标 -> 名称
- 星号按钮的 target/action、关联对象、尺寸约束均不变

### 4.2 需求 2：收藏 Tab 拖动排序

**状态转换**：

```
空闲 → mouseDown 记录起始位置
     → mouseDragged 超过阈值(5px) → isDragging=true, 创建浮动快照, 隐藏原行
     → mouseDragged 持续 → 移动快照位置, 计算目标插入位置, 视觉反馈(行交换动画)
     → mouseUp → 确认排序, 调用 ConfigStore.reorderApps(), isDragging=false, 销毁快照, reloadData()
```

**关键约束**：
- 拖拽开始阈值：`Constants.Panel.dragThreshold`（5px），防止误触
- 浮动快照：透明度 `dragSnapshotAlpha`（0.8），缩放 `dragSnapshotScale`（1.02）
- 拖拽中抑制 `reloadData`：已有 `isDragging` 守卫（第 341 行）
- 持久化时机：mouseUp 时一次性调用 `ConfigStore.reorderApps()`
- 拖拽仅在收藏 Tab 生效（`currentTab == .favorites`）
- 窗口列表子行不参与拖拽，仅 App 行可拖拽

**实现方式**：在 `HoverableRowView` 上通过 `mouseDown`/`mouseDragged`/`mouseUp` 事件实现拖拽。收藏 Tab 构建时为每个 App 行设置 `dragHandler` 闭包。或直接在 `QuickPanelView` 层面覆盖鼠标事件，通过 hitTest 判断拖拽目标。

推荐方案：在 `HoverableRowView` 中新增可选的 `dragEnabled: Bool` 属性和 `dragHandler` 回调闭包组，收藏 Tab 构建时启用。这样拖拽逻辑封装在行视图中，与现有 `clickHandler` 模式一致。

### 4.3 需求 3：窗口重命名绑定窗口实例

**renameKey 变更影响**：
- 旧格式 `bundleID::originalTitle` → 同标题窗口共享重命名
- 新格式 `bundleID::CGWindowID` → 每个窗口实例独立重命名
- CGWindowID 是临时 ID，App 重启后窗口 ID 变化，重命名自动失效

**旧数据清理策略**：
- **方案：静默失效，懒清理**
  - 升级后旧 key（`bundleID::title` 格式）自然无法匹配新 key（`bundleID::windowID` 格式）
  - 旧数据残留在 `windowRenames` 字典中但不会被读取
  - 不主动清理，因为数据量极小（通常几十条），不影响性能
  - 用户重新为窗口设置重命名时写入新格式 key

**注意事项**：
- `handleRenameWindow` 中弹窗的 `informativeText` 仍显示原始窗口标题（`windowInfo.title`），不受 renameKey 格式变更影响
- `handleClearRename` 通过 `representedObject` 传入的已经是完整的 key 字符串，无需修改

---

## 5. 验收用例

### UC1：星号位置（需求 1）
**操作**：打开快捷面板活跃 Tab，观察 App 行布局
**预期**：每行从左到右依次为 星号 -> 绿色状态点 -> App 图标 -> 应用名

### UC2：星号功能不受影响（需求 1）
**操作**：在新布局下点击星号添加/取消收藏
**预期**：收藏状态正确切换，星号颜色（黄色/灰色）正确更新

### UC3：收藏拖拽排序（需求 2）
**操作**：收藏 Tab 中，长按并拖拽一个 App 行到另一位置
**预期**：出现浮动快照，其他行自动让位；松手后排序生效，面板刷新显示新顺序

### UC4：拖拽排序持久化（需求 2）
**操作**：拖拽排序后关闭面板，重新打开
**预期**：收藏 Tab 中 App 顺序与拖拽后一致（持久化到 UserDefaults）

### UC5：拖拽阈值防误触（需求 2）
**操作**：在收藏 Tab 中短按（移动 < 5px）App 行
**预期**：触发正常的点击行为（折叠/展开窗口列表），不启动拖拽

### UC6：窗口重命名绑定实例（需求 3）
**操作**：同一 App 打开两个同标题窗口，右键重命名其中一个
**预期**：仅被重命名的窗口显示新名称，另一个同标题窗口不受影响

### UC7：重命名跨重启失效（需求 3）
**操作**：重命名一个窗口后，退出并重新启动目标 App
**预期**：重启后窗口 ID 变化，旧重命名自动失效，窗口显示原始标题

### UC8：清除重命名（需求 3）
**操作**：右键已重命名的窗口，选择"清除自定义名称"
**预期**：窗口恢复显示原始标题

---

## 6. 非目标声明

- **不修改** 活跃 Tab 的拖拽排序（`runtimeOrder` 机制保持不变）
- **不实现** 跨 Tab 拖拽（如从活跃 Tab 拖拽到收藏 Tab）
- **不迁移** 旧格式的 windowRenames 数据（静默失效即可）
- **不添加** 窗口重命名的跨重启持久化机制（用户已确认接受 CGWindowID 临时性）
- **不修改** ConfigStore、Models、Constants 文件（现有接口已满足需求）
- **不修改** 收藏 Tab 中窗口子行的拖拽（仅 App 行可拖拽）
