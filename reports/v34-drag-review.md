# V3.4 拖拽排序架构评审报告

> 评审日期：2026-03-05
> 评审文档：v34-drag-arch.md（架构设计）、v34-drag-perf-eval.md（性能评估）
> 参考源码：QuickPanelView.swift、ConfigStore.swift、QuickPanelWindow.swift

## 评审结论：通过

未发现 P0 问题。架构设计完整覆盖了状态转换路径，接口契约两端对齐，边界行为定义充分。

---

## 1. 完整性评审

### 1.1 状态转换路径覆盖 — 通过

状态机定义了三个状态（正常、等待拖拽、拖拽中）和所有转换路径：

| 转换 | 是否覆盖 | 评估 |
|------|---------|------|
| 正常 → 等待拖拽（mouseDown） | 已覆盖 | 记录 dragStartPoint，不调用 super |
| 等待拖拽 → 拖拽中（位移 >= 5px） | 已覆盖 | isDragActive=true，通知 isDragging=true，创建快照 |
| 等待拖拽 → 正常（mouseUp，位移 < 5px） | 已覆盖 | 走原有点击逻辑 |
| 拖拽中 → 正常（mouseUp） | 已覆盖 | 移除快照，调用 dragReorderHandler，重置 isDragActive |
| 拖拽中 → 正常（面板快捷键隐藏） | 已覆盖 | resetToNormalMode 兜底清除 isDragging |
| 拖拽中 → reloadData 被抑制 | 已覆盖 | isDragging 守卫 |

### 1.2 中断场景覆盖 — 通过

| 中断场景 | 处理方式 | 评估 |
|----------|---------|------|
| 拖拽中定时器触发 reloadData | isDragging 守卫完整跳过 | 充分 |
| 拖拽中面板被 mouseExited 收起 | mouseExited 增加 isDragging 检查 | 充分 |
| 拖拽中面板被快捷键隐藏 | resetToNormalMode 清除状态 | 充分 |
| 拖拽中 App 退出 | isDragging 抑制刷新，拖拽结束后补偿 | 充分 |
| 拖拽中 Tab 切换 | 未显式提及 | 见建议 1 |

### 1.3 边界行为定义 — 通过

文档 3.4 节列出了 8 种边界场景，覆盖了释放到空白区域、原位释放、窗口行释放、1 个 App、空列表等情况。定义充分。

### 1.4 isDragging 守卫覆盖 — 通过

reloadData 的所有入口（源码核查）：

| 入口 | 是否被守卫覆盖 |
|------|--------------|
| windowsDidChange 通知 → reloadData() | 是（守卫在 reloadData 开头） |
| appStatusDidChange 通知 → reloadData() | 是 |
| accessibilityDidGrant 通知 → reloadData() | 是 |
| switchTab → reloadData() | 见建议 1 |
| handleToggleFavorite → reloadData() | 是（拖拽中星号按钮不可点击） |
| App 行 clickHandler → reloadData() | 是（拖拽中 mouseUp 不走 clickHandler） |
| 窗口行 clickHandler → reloadData() | 是（窗口行无拖拽功能） |
| QuickPanelWindow.show → reloadData() | 是（面板显示时不可能已在拖拽中） |
| handleCloseWindow → reloadData() | 是（右键菜单在拖拽中不会出现） |
| handleRenameWindow/handleClearRename → reloadData() | 是（同上） |

所有入口均被覆盖或在拖拽状态下不可触发。

---

## 2. 一致性评审

### 2.1 接口契约对齐 — 通过

**HoverableRowView 端**：
- 新增 `isAppRow`、`dragReorderHandler`、`dragStartPoint`、`isDragActive`、`dragSnapshotView`
- mouseUp 中 `isDragActive` 分支精确区分拖拽和点击

**QuickPanelView 端**：
- `handleDragReorder(from:to:)` 接收两个 bundleID
- `findTargetAppRow(at:)` 提供坐标反查能力
- 在 `createAppRow` 中设置 `isAppRow=true` 和 `dragReorderHandler`

两端接口一致，参数类型匹配（bundleID: String）。

### 2.2 runtimeOrder 与 buildContent 协作 — 通过

- `sortedRunningApps` 在 `buildRunningTabContent` 中对 AppMonitor 原始数据排序
- 新 App（不在 runtimeOrder 中的）追加末尾
- runtimeOrder 为空时退化为原始顺序
- 补偿刷新时通过 `lastStructuralKey = ""` 强制全量重建

逻辑清晰，不修改 AppMonitor 数据源。

### 2.3 isDragging 通知机制 — 需明确（非 P0）

架构文档 2.5 节写到 mouseDragged 进入拖拽模式时"通知 QuickPanelView 设置 isDragging = true"，但未明确通知方式。可选方案：

- (a) HoverableRowView 持有对 QuickPanelView 的弱引用
- (b) 通过 responder chain 查找
- (c) 通过 NotificationCenter

建议在实现时选用 (a) 或 (b)，并在代码注释中说明。这不影响架构正确性。

---

## 3. 过度设计检查

### 3.1 无多余接口 — 通过

| 新增接口 | 消费者 |
|----------|--------|
| isAppRow | mouseDragged 判断是否支持拖拽 |
| dragReorderHandler | mouseUp 回调排序结果 |
| findTargetAppRow(at:) | mouseUp 中定位目标行 |
| sortedRunningApps(_:) | buildRunningTabContent 排序渲染 |
| appRowIndex(for:) | handleDragReorder 中索引计算 |

所有接口均有明确消费者，无冗余。

### 3.2 无不必要的新文件或抽象 — 通过

文档明确声明不创建新文件、不引入 DragManager/DragProtocol 等新抽象，所有逻辑内聚在 HoverableRowView 和 QuickPanelView 中。代码量预估 ~170 行，合理。

---

## 4. 可测试性评审

### 4.1 验收用例可执行性 — 通过

文档列出 8 个验收用例，全部可通过编译 + 手动测试验证：

| 用例 | 可执行性 | 评估 |
|------|---------|------|
| 用例 1：基本拖拽排序（活跃 Tab） | 手动操作即可验证 | 明确 |
| 用例 2：收藏 Tab 拖拽 + 持久化 | 关闭重开面板验证 | 明确 |
| 用例 3：点击不受影响 | 单击验证折叠/展开和收藏 | 明确 |
| 用例 4：定时器刷新不打断 | 拖拽保持 > 1s | 明确 |
| 用例 5：释放到无效区域 | 拖到空白区域释放 | 明确 |
| 用例 6：排序在刷新后保持 | 排序后等待多次刷新 | 明确 |
| 用例 7：星号位置 | 视觉检查 | 明确 |
| 用例 8：拖拽中面板不收起 | 鼠标移出面板范围 | 明确 |

### 4.2 缺少的测试场景（建议补充，非 P0）

- 快速连续拖拽（拖拽完成后立即再次拖拽）
- 拖拽中收藏 Tab 的星号点击（虽然拖拽中 mouseDown 已被拦截，建议显式验证）

---

## 5. 与现有代码兼容性

### 5.1 mouseUp 点击逻辑 — 兼容

现有 HoverableRowView.mouseUp（第 1069~1080 行）逻辑：
1. hitTest 检查是否点击了 NSButton（星号按钮等）→ 交给 super
2. 否则调用 clickHandler

架构设计在此基础上增加 `isDragActive` 前置判断：
- `isDragActive == true` → 走拖拽结束逻辑
- `isDragActive == false` → 走原有点击逻辑（完全不变）

兼容性好，点击路径零修改。

### 5.2 差分更新机制 — 兼容

`buildStructuralKey()` 不包含排序信息（只包含 bundleID、窗口 ID、折叠状态、收藏状态）。这意味着：

- 纯排序变化不会改变 structuralKey → 不会触发全量重建
- 补偿刷新时通过 `lastStructuralKey = ""` 强制全量重建 → 正确

**注意**：这也意味着如果 runtimeOrder 变化但窗口列表不变，普通 reloadData 不会重建视图。但这恰好是期望的行为——排序只在拖拽结束时通过补偿刷新生效。

### 5.3 resetToNormalMode 清理 — 需补充（非 P0）

当前 resetToNormalMode（第 401~408 行）清除：highlightedWindowID、collapsedApps、windowTitleLabels、windowRowViewMap、lastStructuralKey。

架构设计要求增加清除 isDragging。建议同时清除：
- `isDragging = false`
- HoverableRowView 的 `dragSnapshotView`（如果存在的话移除）

文档已在影响分析中提到 resetToNormalMode 兜底清除浮动快照，但未在 2.3 节 resetToNormalMode 修改说明中列出。建议补充。

---

## 6. 改进建议（均为非 P0）

### 建议 1：拖拽中 Tab 切换的处理

架构文档未显式说明拖拽中用户点击 Tab 切换按钮的行为。虽然拖拽中 mouseDown 被 HoverableRowView 拦截（不调用 super），但 Tab 按钮不在 HoverableRowView 内部（在 topBar 上），用户仍可点击。

**场景**：用户在活跃 Tab 拖拽 App 行时点击"收藏"Tab 按钮。

switchTab 内部调用 `reloadData()`，此时 isDragging 守卫会阻止刷新，但 Tab 状态已变更为 favorites。后续拖拽结束后，handleDragReorder 的补偿刷新将渲染收藏 Tab 内容，而拖拽的 source/target bundleID 来自活跃 Tab 的 App 行。

**建议**：在 switchTab 中增加拖拽中断处理——如果 isDragging 为 true，先取消拖拽（清除状态、移除快照），再执行 Tab 切换。

### 建议 2：resetToNormalMode 补充清除快照视图

文档 2.3 节的 resetToNormalMode 修改说明仅提到清除 isDragging。建议显式列出同时清除 dragSnapshotView（遍历 contentStack 或记录引用）。影响分析第 305 行已提到此风险，但修改清单中未包含。

### 建议 3：sortedRunningApps 中 force unwrap 的安全性

文档 3.3 节伪代码中：
```swift
let orderA = orderMap[a.bundleID] ?? (maxOrder + apps.firstIndex(where: { $0.bundleID == a.bundleID })!)
```

`firstIndex` 在传入的 `apps` 数组中查找元素本身，理论上不会返回 nil（因为 a 就来自 apps），但 force unwrap 在生产代码中不够安全。建议改为 `?? 0` 或使用 guard let。

### 建议 4：runtimeOrder 的生命周期

runtimeOrder 在面板关闭（resetToNormalMode）时不清除（文档未提及清除），这意味着用户排序后关闭面板再打开，排序仍保持。这是合理的。

但需确认：runtimeOrder 中包含已退出 App 的 bundleID 时，sortedRunningApps 的行为是否正确。根据伪代码，已退出 App 不在 `apps` 参数中，其 bundleID 在 orderMap 中占位但不参与排序，新 App 追加末尾。行为正确。

### 建议 5：补充"快速连续拖拽"验收用例

用户完成一次拖拽后立即开始第二次拖拽。需确认补偿刷新（reloadData）完成前不会被第二次 isDragging=true 阻塞。由于补偿刷新是同步的（主线程），handleDragReorder 内部的 `isDragging = false` + `reloadData()` 会在返回前完成，第二次 mouseDown 一定在其之后。无风险，但建议作为验收用例显式验证。

---

## 7. 评审总结

| 维度 | 结论 | 说明 |
|------|------|------|
| 完整性 | 通过 | 状态转换路径完整，边界行为定义充分，isDragging 守卫覆盖所有入口 |
| 一致性 | 通过 | 接口契约两端对齐，runtimeOrder 协作逻辑清晰 |
| 过度设计 | 通过 | 无冗余接口，无不必要的抽象，代码量合理 |
| 可测试性 | 通过 | 8 个验收用例均可通过编译+手动测试验证 |
| 兼容性 | 通过 | mouseUp 点击逻辑兼容，差分更新不受影响，resetToNormalMode 可兜底 |

**质量关卡：通过** — 无 P0 问题（无遗漏状态转换路径、无接口契约矛盾、无缺少关键边界行为定义）。

5 条改进建议均为非 P0，可在实现阶段酌情采纳。
