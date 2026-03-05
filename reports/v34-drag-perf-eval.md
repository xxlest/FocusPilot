# V3.4 拖拽排序性能评估报告

> 评估日期：2026-03-05
> 评估范围：QuickPanelView 添加 App 行拖拽排序功能的性能影响

## 1. 现有架构关键数据

| 指标 | 当前值 | 来源 |
|------|--------|------|
| 列表实现 | NSStackView（contentStack） | QuickPanelView.swift |
| 行视图 | HoverableRowView（自定义 NSView） | QuickPanelView.swift |
| 数据刷新 | 1s~3s 自适应定时器（面板显示时） | AppMonitor.swift |
| 差分更新 | buildStructuralKey 对比，标题变化走轻量路径 | QuickPanelView.swift |
| 全量重建触发 | structuralKey 变化时清空所有子视图重建 | QuickPanelView.swift |
| 收藏数据源 | ConfigStore.appConfigs（[AppConfig]），UserDefaults 持久化 | ConfigStore.swift |
| 收藏上限 | 8 个 App | Constants.swift |
| 每 App 窗口上限 | 10 个 | Constants.swift |
| App 行高 | 26pt，窗口行高 22pt | Constants.swift |

## 2. 方案对比

### 方案 A：NSStackView + NSDraggingSource/Destination

在现有 HoverableRowView 上实现 NSDraggingSource，在 QuickPanelView/contentStack 上实现 NSDraggingDestination。

| 维度 | 评估 |
|------|------|
| **性能开销** | 低。拖拽图像通过 `dataWithPDF(inside:)` 生成一次快照即可（单行 26pt 高，开销可忽略）。重排时仅调用 `NSStackView.insertArrangedSubview(_:at:)` 移动已有视图，不创建新视图 |
| **实现复杂度** | 中。需实现 NSDraggingSource（3 个方法）+ NSDraggingDestination（4 个方法）。需要处理拖拽占位符和插入指示线。NSStackView 没有原生的行移动动画，需手动用 NSAnimationContext 实现 |
| **兼容性** | 好。NSStackView 支持 `insertArrangedSubview` / `removeArrangedSubview`，可直接移动子视图。但需注意：移动 App 行时需连带其窗口列表子视图一起移动 |
| **与现有架构的冲突** | **中等风险**。contentStack 中 App 行和窗口列表是平铺的（非嵌套），拖拽 App 行时需识别并一起移动其关联的窗口列表视图 |

### 方案 B：改用 NSTableView

将 contentStack 替换为 NSTableView，利用其原生 `tableView(_:acceptDrop:)` 支持。

| 维度 | 评估 |
|------|------|
| **性能开销** | 低到中。NSTableView 有视图复用机制（`makeView(withIdentifier:)`），大量列表时性能更好。但当前列表最多 8 个 App + 80 个窗口行，规模小到 NSStackView 完全胜任 |
| **实现复杂度** | **高**。需要重写整个列表构建逻辑（~400 行代码），将现有 `buildContent()` / `createAppRow()` / `createWindowList()` 全部改为 NSTableView 的 delegate/dataSource 模式。差分更新逻辑也要重新设计 |
| **兼容性** | 好。NSTableView 原生支持行拖拽排序，动画流畅。但 App 行+窗口行的树形展开结构需用 NSOutlineView 才更自然 |
| **与现有架构的冲突** | **高风险**。大规模重构，引入回归风险。现有的 windowTitleLabels/windowRowViewMap 差分更新机制需要完全重新设计 |

### 方案 C：手动拖拽（mouseDown/mouseDragged/mouseUp）

在 HoverableRowView 中直接处理鼠标事件，手动实现拖拽视觉效果和行交换。

| 维度 | 评估 |
|------|------|
| **性能开销** | **最低**。无系统拖拽会话开销，无剪贴板写入。直接操作视图 frame/transform |
| **实现复杂度** | **中偏低**。需处理：(1) mouseDown 记录起始位置和行索引 (2) mouseDragged 创建浮动快照视图并跟随鼠标 (3) mouseUp 计算目标位置并交换。约 100~150 行代码 |
| **兼容性** | 需注意。HoverableRowView 已有 mouseUp 处理点击事件，需区分"点击"和"拖拽"（通过拖拽阈值，如 5px 位移） |
| **与现有架构的冲突** | **低风险**。不涉及系统拖拽 API，不改变现有视图层次结构。行交换后调用一次 reloadData 即可 |

### 方案对比总表

| 方案 | 性能开销 | 实现复杂度 | 与现有架构冲突 | 推荐度 |
|------|---------|-----------|--------------|--------|
| A: NSStackView + NSDragging | 低 | 中 | 中 | ★★★★ |
| B: 改用 NSTableView | 低~中 | 高（大重构） | 高 | ★★ |
| C: 手动拖拽 | 最低 | 中偏低 | 低 | ★★★★★ |

## 3. 运行时开销分析

### 3.1 拖拽过程中的 CPU/内存

| 操作 | 开销 | 说明 |
|------|------|------|
| 拖拽图像生成 | ~0.1ms | 单行视图快照（26pt x 280pt），一次性生成 |
| 行重排动画 | ~1-2ms/帧 | NSStackView `insertArrangedSubview` 或手动 frame 动画，60fps 下无压力 |
| 内存增量 | ~数 KB | 一张浮动快照图 + 临时索引数据 |

**结论**：拖拽过程中的 CPU/内存开销可忽略不计。

### 3.2 拖拽完成后的数据同步

| Tab | 操作 | 开销 |
|-----|------|------|
| 活跃 Tab | 更新运行时数组顺序 | ~0，纯内存操作 |
| 收藏 Tab | `ConfigStore.reorderApps()` → JSON 编码 → UserDefaults 写入 | < 0.5ms（8 个 AppConfig 序列化体积极小） |

`reorderApps()` 已存在于 ConfigStore 中，内部调用 `save()` 做全量序列化。对于 8 个 AppConfig 的数组，JSON 编码 + UserDefaults 写入耗时远低于 1ms。

### 3.3 与自适应刷新的冲突（核心风险）

**场景**：用户正在拖拽 App 行时，AppMonitor 的 1s 定时器触发 `refreshAllWindows()` → 发送 `windowsChanged` 通知 → `QuickPanelView.reloadData()` 被调用。

**影响分析**：
1. `buildStructuralKey()` 会重新计算 — 如果此时 App 列表无变化，structuralKey 不变，仅走 `updateWindowTitles()` 轻量路径 → **不影响拖拽**
2. 如果恰好有 App 启动/退出导致 structuralKey 变化 → 全量重建（`contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }`）→ **拖拽被打断，用户拖着的视图被移除**

**概率**：低（拖拽操作通常 0.5~2s，期间恰好有 App 状态变化的概率很低），但一旦触发体验极差。

## 4. 关键风险点

### 风险 1：reloadData 打断拖拽（严重度：高，概率：低）

**根因**：`reloadData()` 在 structuralKey 变化时执行全量重建，清空所有子视图。

**保护措施**：添加 `isDragging` 标志位，拖拽期间抑制 `reloadData()` 的全量重建：
```
// 伪代码
private var isDragging = false

func reloadData() {
    if isDragging { return }  // 拖拽中不刷新
    // ... 原有逻辑
}
```
拖拽结束后，执行一次 `lastStructuralKey = ""; reloadData()` 补偿刷新。

### 风险 2：收藏 Tab 排序被 reloadData 覆盖（严重度：中，概率：中）

**根因**：收藏 Tab 数据源是 `ConfigStore.shared.appConfigs`。`reorderApps()` 会更新 `appConfigs` 并持久化。但如果拖拽过程中 `reloadData()` 被调用且走全量重建，会从 `ConfigStore.appConfigs` 重新读取数据 — 只要 `reorderApps()` 已执行，排序不会丢失。

**真正的风险在活跃 Tab**：活跃 Tab 的排序是纯运行时状态，`reloadData()` 会从 `AppMonitor.runningApps` 重新读取（按字母排序），排序立即丢失。

**保护措施**：
- 活跃 Tab 需维护一个 `runtimeOrder: [String]`（bundleID 数组），`buildRunningTabContent()` 按此顺序渲染
- 每次 `reloadData()` 对新数据按 `runtimeOrder` 排序，新增 App 追加到末尾

### 风险 3：NSStackView 拖拽性能问题（严重度：低）

NSStackView 本身无已知拖拽性能问题。列表规模小（最多 8 + 80 = 88 个视图），远低于 NSStackView 的性能瓶颈（数百个视图时才会出现布局计算卡顿）。

### 风险 4：App 行与窗口列表的耦合（严重度：中，方案 A 特有）

contentStack 中 App 行和其窗口列表是相邻但独立的 arrangedSubview。拖拽 App 行时，需要：
1. 识别该 App 行关联的窗口列表视图
2. 一起移动（否则窗口列表会留在原位）

**方案 C 的优势**：手动拖拽可以在 mouseUp 时通过修改数据源顺序 + 一次 `reloadData()` 来完成，避免直接操作视图层次。

## 5. 对现有性能指标的影响

### 5.1 面板弹出速度（目标 < 100ms）

| 场景 | 影响 |
|------|------|
| 未拖拽状态 | **无影响**。拖拽功能仅在用户触发时生效，不改变视图构建逻辑 |
| 拖拽后立即关闭再打开面板 | **无影响**。面板关闭时调用 `resetToNormalMode()` 清除所有状态，下次打开走全量重建 |

### 5.2 正常使用（非拖拽状态）

| 指标 | 影响 |
|------|------|
| 内存 | +微量（isDragging 标志位 + runtimeOrder 数组，< 1KB） |
| CPU | **无影响**。差分更新逻辑不变 |
| 渲染 | **无影响**。行视图结构不变 |

### 5.3 拖拽过程帧率

| 方案 | 预估帧率 |
|------|---------|
| A: NSDragging | 60fps（系统拖拽会话硬件加速） |
| B: NSTableView | 60fps（系统原生动画） |
| C: 手动拖拽 | 60fps（仅更新一个浮动视图的 frame，开销极低） |

所有方案在当前列表规模下都能保持 60fps。

## 6. 结论

### 对现有性能的影响：无影响

拖拽排序功能仅在用户主动触发时消耗资源，对面板弹出速度、正常浏览、差分更新等现有性能路径零影响。

### 推荐方案：方案 C（手动拖拽）

**理由**：
1. **最低风险**：不引入系统拖拽 API，不改变现有视图层次结构
2. **最小改动**：约 100~150 行新代码，集中在 HoverableRowView 和 QuickPanelView 两个文件
3. **与现有架构最兼容**：通过修改数据源 + reloadData 完成排序，复用现有差分更新机制
4. **性能最优**：无剪贴板序列化、无拖拽会话开销

### 必须实现的保护措施

1. **isDragging 守卫**：拖拽期间抑制 `reloadData()` 全量重建，拖拽结束后补偿刷新
2. **拖拽/点击区分**：mouseDown 后位移超过 5px 阈值才进入拖拽模式，否则走原有点击逻辑
3. **活跃 Tab 排序持久化**：维护 `runtimeOrder` 数组，`reloadData()` 时按此顺序渲染，避免被字母排序覆盖
4. **收藏 Tab 即时持久化**：拖拽结束立即调用 `ConfigStore.reorderApps()`，确保排序不因 App 崩溃而丢失
5. **窗口列表折叠**：建议拖拽开始时自动折叠所有 App 的窗口列表，简化视觉和计算（可选优化）
