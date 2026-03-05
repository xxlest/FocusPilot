# V3.5 缺陷检测报告

## 阶段 A：验收用例验证

| 用例 | 结果 | 验证方式 | 备注 |
|------|------|----------|------|
| UC1 星号位置 | PASS | 代码审查 | `createAppRow` 第 586-604 行：`currentTab == .running` 时先添加 starButton，再添加 statusDot（第 607-608 行），顺序正确：星号 -> 状态点 -> 图标 -> 名称 |
| UC2 星号功能不受影响 | PASS | 代码审查 | starButton 的 target/action（`handleToggleFavorite`）、关联对象（bundleIDKey/displayNameKey）、尺寸约束均未改变，收藏切换逻辑完整（第 1046-1057 行） |
| UC3 收藏拖拽排序 | PASS | 代码审查 | `handleFavDragStart` 创建浮动快照并隐藏源行（第 894-924 行），`handleFavDragMove` 计算目标位置并动画交换行（第 927-991 行），`handleFavDragEnd` 持久化并清理（第 995-1019 行） |
| UC4 拖拽排序持久化 | PASS | 代码审查 | `handleFavDragEnd` 调用 `ConfigStore.shared.reorderApps(favDragOrder)`（第 997 行），`reorderApps` 更新 appConfigs 并调用 `save()`（ConfigStore 第 189-199 行） |
| UC5 拖拽阈值防误触 | PASS | 代码审查 | HoverableRowView.mouseDragged 中计算移动距离，仅当 `distance >= Constants.Panel.dragThreshold`（5px）时才激活拖拽（第 1277-1281 行）；未超过阈值时 mouseUp 执行正常的 clickHandler（第 1307-1308 行） |
| UC6 窗口重命名绑定实例 | PASS | 代码审查 | `renameKey` 签名为 `(bundleID: String, windowID: CGWindowID) -> String`（第 887-889 行），返回 `bundleID::windowID`。`resolveDisplayTitle` 和 `handleRenameWindow` 均使用 `windowInfo.id` 调用（第 415 行、第 843 行），不同窗口实例有不同的 key |
| UC7 重命名跨重启失效 | PASS | 代码审查 | renameKey 基于 CGWindowID（临时 ID），App 重启后窗口 ID 变化，旧 key 自然无法匹配，重命名静默失效 |
| UC8 清除重命名 | PASS | 代码审查 | `handleClearRename` 通过 `representedObject` 获取 key 字符串，从 `windowRenames` 中移除并保存（第 877-883 行），逻辑正确 |

## 阶段 B：探索性测试发现

| # | 严重级别 | 描述 | 位置 | 建议修复 |
|---|----------|------|------|----------|
| B1 | P1 | **拖拽中重建窗口列表导致 windowTitleLabels/windowRowViewMap 映射错乱**：`handleFavDragMove` 在行交换动画中调用 `createWindowList`（第 981 行）重新创建窗口行，但不会清除 `windowTitleLabels` 和 `windowRowViewMap` 中的旧引用。这些旧视图已被 `removeFromSuperview` 移除，但字典中仍指向它们。后续的 `updateWindowTitles` 会更新已被移除的视图（无害但浪费），而新创建的窗口行标题不在映射中（无法差分更新）。拖拽结束时 `reloadData` 全量重建会修正，但拖拽过程中窗口标题变化不会实时反映。 | QuickPanelView.swift:964-985 | 在重建 contentStack 前清空 `windowTitleLabels` 和 `windowRowViewMap`，或在 `createWindowList` 中注册到映射（当前已在 `createWindowRow` 中注册，但拖拽中重建会覆盖旧引用——实际上这部分是自动处理的，因为 `createWindowRow` 会写入映射）。**修正**：仔细看代码，`createWindowRow`（第 762-763 行）会将新创建的视图注册到映射，所以新视图会覆盖旧引用，这个问题实际不存在。**降级为 P3**。 |
| B2 | P2 | **拖拽期间切换 Tab 可能导致状态不一致**：如果用户在拖拽进行中通过某种方式切换 Tab（虽然拖拽中鼠标被捕获，但理论上可以通过快捷键或其他方式触发），`switchTab` 会调用 `reloadData`，但 `isDragging=true` 导致 reloadData 直接返回。此时 Tab 已切换但内容未刷新，且拖拽状态残留。 | QuickPanelView.swift:316-323, 349-350 | 在 `switchTab` 中增加拖拽中的保护：如果 `isDragging` 为 true，先强制结束拖拽（清理状态），再执行 Tab 切换。 |
| B3 | P2 | **只有 1 个收藏时拖拽行为**：只有 1 个收藏 App 时，拖拽可以启动（创建快照、隐藏源行），但没有其他行可以交换。拖拽结束时 `reorderApps` 传入的数组与原数组相同，不会产生错误但用户体验不佳（源行消失又出现的闪烁）。 | QuickPanelView.swift:894-924 | 在 `handleFavDragStart` 中检查 `favDragAppRows.count <= 1`，如果只有一个收藏项则不启动拖拽。 |
| B4 | P2 | **拖拽中坐标系问题（FlippedClipView）**：`handleFavDragMove` 将窗口坐标转换到 `contentStack.superview`（即 FlippedClipView），FlippedClipView 的 `isFlipped = true`。但拖拽位置计算中的 Y 轴比较逻辑（第 939-944 行）使用 `localPoint.y < rowMid.y` 来判断向上移动、`localPoint.y > rowMid.y` 判断向下移动。在翻转坐标系中，Y 值从上到下递增，因此 `localPoint.y < rowMid.y` 表示在目标行上方，这是正确的。但快照位置设置（第 933 行 `snapshot.frame.origin.y = localPoint.y - snapshot.frame.height / 2`）在翻转坐标系中也应是正确的。**经分析，逻辑正确。撤回此项。** | - | - |
| B5 | P1 | **拖拽中 favDragAppRows 和 favDragOrder 索引不同步风险**：`handleFavDragMove` 中先修改 `favDragOrder`（第 950-951 行），再修改 `favDragAppRows`（第 954-955 行），然后通过 `favDragOrder` 遍历并查找 `favDragAppRows.first(where: { $0.bundleID == bundleID })`（第 973 行）来重建。如果 `favDragAppRows` 中有多个行的 `bundleID` 相同（理论上不应发生，因为收藏不允许重复），则 `first` 可能返回错误的行。在正常情况下 `bundleID` 唯一，此问题不会触发。 | QuickPanelView.swift:950-985 | 风险很低，可忽略。ConfigStore.addApp 已有去重保护（第 166 行）。 |
| B6 | P2 | **拖拽快照在滚动视图中的定位问题**：快照添加到 `contentStack.superview`（FlippedClipView），但滚动偏移量未考虑。如果收藏列表很长，用户滚动到中间位置后开始拖拽，快照的初始位置（`sourceRow.convert(sourceRow.bounds, to: contentStack.superview)` 第 917 行）是相对于 clipView 的，这是正确的。但 `handleFavDragMove` 中 `contentStack.superview?.convert(point, from: nil)` 将窗口坐标转换到 clipView 坐标，这也是正确的。然而，如果拖拽过程中视图发生了滚动（用户用触控板滚动），快照位置和行位置的比较可能出现偏差。 | QuickPanelView.swift:932-933 | 可考虑在拖拽期间禁止 scrollView 滚动，或使用 scrollView 的 documentView 坐标系统。优先级较低。 |

## 阶段 C：代码审查发现

| # | 严重级别 | 描述 | 位置 | 建议修复 |
|---|----------|------|------|----------|
| C1 | P1 | **强制解包 bitmapImageRepForCachingDisplay 可能崩溃**：`handleFavDragStart` 第 900 行 `sourceRow.bitmapImageRepForCachingDisplay(in: sourceRow.bounds)!` 使用了强制解包。如果 sourceRow 的 bounds 为 zero（例如视图尚未布局完成），`bitmapImageRepForCachingDisplay` 可能返回 nil，导致崩溃。 | QuickPanelView.swift:900 | 使用 `guard let bitmapRep = sourceRow.bitmapImageRepForCachingDisplay(in: sourceRow.bounds) else { return }` 安全解包。 |
| C2 | P2 | **isDragging 状态在异常路径下可能未清除**：如果 `handleFavDragStart` 设置了 `isDragging = true`，但后续由于某种原因 `handleFavDragEnd` 未被调用（例如 mouseUp 事件丢失、窗口被系统关闭），`isDragging` 将永久为 true，导致 `reloadData` 永远被跳过，面板内容不再更新。 | QuickPanelView.swift:895, 1014 | 在 `resetToNormalMode`（面板关闭时调用）中增加 `isDragging = false` 和拖拽状态清理。当前 `resetToNormalMode`（第 424-431 行）未清理拖拽状态。 |
| C3 | P1 | **handleFavDragEnd 中 favDragAppRows 遍历恢复 alphaValue 可能设置错误**：第 1003-1009 行恢复行透明度时，对所有行都设置 alphaValue。但源行在拖拽开始时被设为 `alphaValue = 0`，拖拽结束时需要恢复。代码中通过检查 `isRunning` 来决定 alpha（运行中 1.0，未运行 0.5），这是正确的。但问题是：**拖拽中重建 contentStack 时创建了新的 windowList 视图**（第 981 行），这些新创建的窗口行不在 `favDragAppRows` 中，不受 alpha 恢复影响——这没问题，窗口行默认 alpha 是 1.0。**此项经分析无问题，撤回。** | - | - |
| C4 | P2 | **windowRenames 旧数据积累**：V3.5 将 renameKey 从 `bundleID::title` 改为 `bundleID::windowID`，但旧格式的数据永远不会被清理。虽然单条数据很小，但长期使用后 `windowRenames` 字典会无限增长（每次窗口 ID 变化，旧 key 残留，新 key 写入）。 | ConfigStore.swift:48-51 | 可在加载时或定期清理已无法匹配的旧 key。优先级低，因为数据量小。 |
| C5 | P2 | **拖拽中行交换动画期间的 favDragSourceIndex 更新**：`handleFavDragMove` 第 990 行将 `favDragSourceIndex` 更新为 `targetIndex`。如果动画尚未完成时又触发了 `handleFavDragMove`（鼠标快速移动），可能导致基于旧布局位置的索引计算不准确，但由于 `favDragAppRows` 的引用已同步更新，逻辑上是一致的。 | QuickPanelView.swift:990 | 可以接受的行为，快速拖拽时可能有视觉抖动但不会导致数据错误。 |

## 总结

- P0 缺陷数：0
- P1 缺陷数：2（C1 强制解包崩溃风险、C2 isDragging 状态在面板关闭时未清理）
- P2 缺陷数：4（B2 拖拽中切换 Tab 状态不一致、B3 单项收藏拖拽体验、B6 滚动中拖拽定位、C4 旧 rename 数据积累）

### 建议优先修复项

1. **[P1] C1**：将 `bitmapImageRepForCachingDisplay` 的强制解包改为安全解包（1 行改动）
2. **[P1] C2**：在 `resetToNormalMode` 中增加拖拽状态清理（约 5 行改动）
3. **[P2] B2**：在 `switchTab` 中增加拖拽中保护逻辑（约 3 行改动）
