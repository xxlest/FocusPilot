# V3.5 拖拽排序方案调研报告

## 1. 背景

FocusPilot 快捷面板使用 NSStackView 垂直排列收藏的应用块（每个块 = HoverableRowView App 行 + 可选的窗口列表 NSStackView）。V3.4 已实现基础拖拽排序，但存在以下问题：

1. **拖拽体验不流畅** - 快照跟随光标有延迟感，占位符移动生硬
2. **占位符视觉效果差** - 仅 4px 蓝色指示线，不够直观
3. **其他块不自动调整位置** - 只有占位符在移动，其余块没有平滑动画过渡
4. **健壮性不足** - 边界情况（快速拖拽出界、Tab 切换中拖拽等）处理不完善

### 当前实现分析（QuickPanelView.swift）

当前方案为 **纯手动鼠标事件处理**：

- **HoverableRowView** 重写 `mouseDown/mouseDragged/mouseUp`，超过阈值后触发回调
- **handleFavDragStart** - 创建位图快照、从 contentStack 移除源块、插入占位符
- **handleFavDragMove** - 快照跟随光标、基于 midY 计算插入位置、移动占位符
- **handleFavDragEnd** - 计算最终排序、持久化、清理状态、全量重建 UI

关键问题：
- 快照通过 `bitmapImageRepForCachingDisplay` 截图，添加到 `contentStack.superview`
- 移动时只操作占位符位置，其他行通过 `layoutSubtreeIfNeeded()` + `NSAnimationContext` 隐式动画
- 源块被完全移除再插回，状态管理复杂（8 个拖拽状态变量）

---

## 2. 方案调研

### 方案 A: Apple NSDragging 协议

**原理**：使用 AppKit 内置的拖拽系统（NSDraggingSource + NSDraggingDestination + NSPasteboard）。

**实现要点**：
- NSStackView 或其容器实现 `NSDraggingDestination`
- HoverableRowView 实现 `NSDraggingSource`
- 通过 `registerForDraggedTypes` 注册自定义 pasteboard 类型
- 实现 `draggingEntered/Updated/Ended` + `performDragOperation` 处理落点

**关键方法**：
```swift
// Source
func draggingSession(_:sourceOperationMaskFor:) -> NSDragOperation
// Destination
func draggingEntered(_:) -> NSDragOperation
func draggingUpdated(_:) -> NSDragOperation
func performDragOperation(_:) -> Bool
```

**优势**：
- Apple 官方 API，与系统深度集成
- 自动生成拖拽图像（也可自定义）
- 支持跨应用拖拽（本场景不需要）
- NSTableView/NSOutlineView/NSCollectionView 原生支持

**劣势**：
- **NSStackView 没有内置的 NSDragging 支持**，需手动实现所有回调
- 拖拽图像默认是半透明缩略图，自定义视觉效果（浮动快照、阴影）需额外工作
- NSDragOperation 语义更适合 "移动/复制数据"，用于同容器内重排序有些重
- 必须通过 NSPasteboard 传递数据（哪怕只是内部排序也需要序列化/反序列化）
- 占位符/插入指示线需要完全自行绘制
- 动画过渡（其他行自动让位）需要手动管理

**适配成本**：高。需要重构 HoverableRowView 为 NSDraggingSource，QuickPanelView 为 NSDraggingDestination，新增 pasteboard 数据模型，手动管理插入动画。

---

### 方案 B: 纯手动鼠标事件处理（改进版）- DraggingStackView 模式

**原理**：在当前 mouseDown/mouseDragged/mouseUp 基础上，借鉴 [DraggingStackView](https://gist.github.com/monyschuk/cbca3582b6b996ab54c32e2d7eceaf25) 的核心技巧：**所有视图创建位图快照层 + window.trackEvents 事件循环 + Core Animation 平滑过渡**。

**DraggingStackView 核心思路**：

1. **拖拽开始**：为 NSStackView 中所有 arrangedSubview 创建 `CachedViewLayer`（位图快照 CALayer），叠加到 NSStackView.layer 上
2. **原始视图隐藏**：设置 `alphaValue = 0`，视图仍在布局中占位，但用户看到的是快照层
3. **拖拽中**：
   - 被拖拽的快照层跟随光标（`CATransaction.setDisableActions(true)` 无动画）
   - 根据拖拽层中点位置，实时计算新顺序
   - 如果顺序变化，调用 `update(stack, reordered)` 更新实际视图顺序 + `layoutSubtreeIfNeeded()`
   - 其他快照层通过 `CATransaction` 0.15s ease-in-out 动画滑动到新位置
4. **拖拽结束**：移除所有快照层，恢复视图透明度，布局已经是最终顺序
5. **事件循环**：使用 `window.trackEvents(matching:timeout:mode:)` 在 `.eventTracking` 模式下独占事件，避免事件泄漏

**改进版实现要点**（适配 FocusPilot 的"块"概念）：

```
原始 DraggingStackView: 每个 arrangedSubview 独立拖拽
FocusPilot 需求: App行 + 窗口列表 = 一个逻辑块，需要整块拖拽
```

需要的改造：
- 将"块"（App 行 + 附属窗口列表）视为一个拖拽单元
- 为每个块创建合并的快照层
- 重排序时以块为单位移动

**优势**：
- **视觉效果最佳**：所有视图都用快照层渲染，拖拽层和其他层都在 Core Animation 层面动画，60fps
- **简洁优雅**：利用 NSStackView 自身布局能力 + CALayer 动画，不需要手动计算每个视图位置
- **状态管理简单**：`trackEvents` 独占事件循环，不需要在类级别维护拖拽状态
- **动画流畅**：其他块通过 Core Animation 自动滑动到新位置（0.15s ease-in-out）
- **与现有架构兼容**：仍然基于 NSStackView，不需要替换容器

**劣势**：
- `trackEvents` 会阻塞当前 RunLoop（在 `.eventTracking` 模式下），拖拽期间其他 UI 更新被暂停
- 需要为"块"概念做适配（合并多个 arrangedSubview 的快照）
- 每次拖拽开始都要为所有视图创建位图快照（内存开销，但面板通常 < 20 行，可忽略）
- `bitmapImageRepForCachingDisplay` 在高 DPI 显示器上需注意 scale factor

**适配成本**：中。核心逻辑 ~100 行，需要适配块概念 +50 行。可以复用现有 HoverableRowView 的 dragEnabled 机制触发，也可以直接在 QuickPanelView 层面处理。

---

### 方案 C: NSCollectionView 替代

**原理**：用 NSCollectionView 替换 contentStack（NSStackView），利用其内置的拖拽排序支持。

**实现要点**：
- 创建 `NSCollectionViewItem` 子类包装当前的 App 块
- 实现 `NSCollectionViewDataSource` + `NSCollectionViewDelegateFlowLayout`
- 实现拖拽相关 delegate 方法（约 5 个）
- 注册 pasteboard 类型

**关键 delegate 方法**：
```swift
collectionView(_:pasteboardWriterForItemAt:)
collectionView(_:draggingSession:willBeginAt:forItemsAt:)
collectionView(_:validateDrop:proposedIndexPath:dropOperation:)
collectionView(_:acceptDrop:indexPath:dropOperation:)
```

**优势**：
- 内置拖拽排序支持，delegate 方法清晰
- 自动处理插入动画和视觉反馈
- 支持多选拖拽（本场景不需要）
- 内置 diffable data source（macOS 10.15+）

**劣势**：
- **迁移成本极高**：需要完全重写快捷面板的渲染逻辑
  - 当前的 `reloadData()` 手动构建 NSStackView 子视图的方式需要改为 data source 模式
  - `HoverableRowView` 需要改造为 `NSCollectionViewItem`
  - 差分更新逻辑（`buildStructuralKey`、`updateWindowTitles`）需要重写
  - 窗口行高亮、hover 效果、右键菜单等交互需要重新实现
- **布局灵活性降低**：NSCollectionView 的布局模型不如 NSStackView 灵活
  - "块"概念（App 行 + 展开的窗口列表 = 可变高度项）在 NSCollectionView 中实现复杂
  - 折叠/展开动画需要额外处理
- **调试困难**：NSCollectionView 的内部行为不透明，出问题时排查困难
- **过度工程化**：仅为拖拽排序替换整个容器组件，投入产出比低

**适配成本**：极高。几乎需要重写整个 QuickPanelView（~600 行），预计工作量是方案 B 的 5-8 倍。

---

### 方案 D: 第三方库/开源方案

**调研结果**：

| 项目 | 平台 | 说明 | 适用性 |
|------|------|------|--------|
| [DraggingStackView](https://gist.github.com/monyschuk/cbca3582b6b996ab54c32e2d7eceaf25) | macOS/AppKit | NSStackView 拖拽排序，~120 行 | 直接可用，即方案 B 的基础 |
| [SQReorderableStackView](https://github.com/markedwardmurray/SQReorderableStackView) | iOS/UIKit | UIStackView 拖拽排序 | 仅 iOS，不可用 |
| [SwiftReorder](https://github.com/adamshin/SwiftReorder) | iOS/UIKit | UITableView 拖拽排序 | 仅 iOS，不可用 |
| [swiftui-reorderable-foreach](https://github.com/globulus/swiftui-reorderable-foreach) | SwiftUI | ForEach 拖拽排序 | SwiftUI，与 AppKit 面板不兼容 |
| [ReordableViews](https://github.com/gadirom/ReordableViews) | SwiftUI | SwiftUI 视图拖拽排序 | SwiftUI，与 AppKit 面板不兼容 |

**结论**：macOS AppKit 生态中没有广泛使用的第三方拖拽排序库。唯一直接可用的是 **DraggingStackView Gist**（即方案 B 的基础），它是一个约 120 行的 NSStackView 子类，已被社区广泛引用。

---

## 3. 方案对比

| 维度 | 方案 A: NSDragging | 方案 B: 改进版手动（推荐） | 方案 C: NSCollectionView | 方案 D: 第三方 |
|------|-------------------|--------------------------|------------------------|--------------|
| **实现复杂度** | 高（~300行，协议重） | 低（~150行，逻辑清晰） | 极高（~600行重写） | 低（直接用 Gist） |
| **60fps 流畅度** | 中（需自管动画） | 高（Core Animation 原生） | 高（系统内置） | 高（同方案 B） |
| **浮动快照** | 需自定义 | 原生支持（位图层） | 系统内置 | 原生支持 |
| **指引线/占位** | 需自己画 | 快照层自动让位 | 系统内置 | 快照层自动让位 |
| **动画过渡** | 需手动管理 | CATransaction 自动 | 系统内置 | CATransaction 自动 |
| **健壮性** | 中（协议回调多） | 高（trackEvents 独占） | 高（系统管理） | 高（同方案 B） |
| **与现有架构兼容** | 中（需重构接口） | 高（最小改动） | 低（需全部重写） | 高（同方案 B） |
| **灵活性（自定义）** | 中 | 高（完全可控） | 低（受限于布局） | 高 |
| **学习曲线** | 高（协议较多） | 低（纯视图+动画） | 高（新范式） | 低 |
| **维护成本** | 中 | 低 | 高 | 低 |

---

## 4. 触发方式对比

### 方案 a: 左键按住 App 行，超过阈值进入拖拽（推荐）

**原理**：mouseDown 记录起点，mouseDragged 检测距离超过阈值（当前 Constants.Panel.dragThreshold）后进入拖拽模式。这就是当前 V3.4 的触发方式。

**优势**：
- **零 UI 改动**：不需要增加任何视觉元素，行布局保持不变
- **符合直觉**：macOS Finder、Dock、Safari 标签页都是按住直接拖拽，用户无需学习
- **代码最简**：HoverableRowView 中已有 mouseDown/mouseDragged/mouseUp 处理，只需保留触发逻辑
- **不占用水平空间**：快捷面板宽度有限（约 280px），不需要为手柄按钮腾出空间

**劣势**：
- 按住后有一个短暂的"死区"（阈值距离内），用户可能觉得有微小延迟
- 点击（前置窗口）和拖拽共用鼠标左键，靠阈值区分，理论上可能误触（但实际 3-5px 阈值足够可靠）

**与方案 B 拖拽核心的配合**：
- HoverableRowView.mouseDragged 超阈值后调用 dragStartHandler
- dragStartHandler 内调用 `window.trackEvents` 接管后续事件
- mouseUp 在 trackEvents 内部处理，外部 mouseUp 不会触发

### 方案 b: 左侧增加拖拽手柄按钮

**原理**：在 App 行左侧增加一个拖拽图标（如 SF Symbol `line.3.horizontal`），只有在手柄区域按下才能触发拖拽。

**优势**：
- 拖拽与点击完全分离，零误触
- 视觉上明确提示"可拖拽排序"

**劣势**：
- **增加 UI 复杂度**：每个 App 行需要额外增加一个 NSImageView/NSButton
- **占用水平空间**：当前行布局已包含 [星标] [状态点] [图标] [名称] [窗口数] [折叠箭头]，再加手柄会很拥挤
- **仅收藏 Tab 需要**：活跃 Tab 不支持拖拽排序，手柄只在收藏 Tab 出现，两个 Tab 布局不一致
- **代码量增加**：需要在 createAppRow 中条件性创建手柄视图、设置约束、处理手柄的鼠标事件转发
- **不符合 macOS 惯例**：macOS 原生应用很少使用拖拽手柄（Finder、Dock、系统偏好都是直接拖拽）

### 触发方式结论

| 维度 | 方案 a: 按住拖拽 | 方案 b: 手柄拖拽 |
|------|-----------------|-----------------|
| UI 改动量 | 无 | 每行增加手柄 |
| 代码量 | ~0 行（复用现有） | ~30 行 |
| 水平空间占用 | 无 | ~20px |
| 误触风险 | 极低（阈值可靠） | 零 |
| macOS 一致性 | 高（系统惯例） | 低（非主流） |
| 两 Tab 一致性 | 高 | 低（仅收藏显示） |

**推荐方案 a**（按住拖拽）。理由：零 UI 改动、符合 macOS 惯例、代码最简。当前 V3.4 的触发方式已经是正确的，只需改进拖拽开始后的动画和排序逻辑。

---

## 5. 推荐方案：方案 B + 触发方式 a

### 最终推荐

- **拖拽核心**：方案 B（DraggingStackView 模式，Core Animation 快照层 + trackEvents）
- **触发方式**：方案 a（左键按住超阈值，复用现有 HoverableRowView 机制）

### 推荐理由

1. **最简洁**：不引入新框架、不增加 UI 元素、不改变触发方式，只改进拖拽后的动画核心
2. **视觉效果最佳**：所有行用 CALayer 快照渲染，拖拽行跟随光标无延迟，其他行 Core Animation 平滑过渡
3. **状态管理简化**：当前 8 个拖拽状态变量可简化为 `trackEvents` 事件循环内的局部变量
4. **高度兼容**：完全兼容现有的 HoverableRowView、差分更新、窗口行高亮等机制

### 实现计划

**核心改造点**：

1. **替换 handleFavDragStart/Move/End 为单个 `handleBlockDrag` 方法**
   - HoverableRowView.dragStartHandler 触发后进入
   - 使用 `window.trackEvents` 独占事件循环，所有拖拽逻辑在一个方法内完成
   - 为所有块创建 CachedViewLayer，Core Animation 驱动动画

2. **块快照**
   - 一个块 = HoverableRowView + 紧随的窗口列表视图
   - 为每个块创建位图快照 CALayer

3. **排序计算**
   - 基于拖拽层中点 vs 其他块中点判断位置
   - 变化时更新 arrangedSubviews 顺序 + CATransaction 动画

4. **清理 8 个类级别拖拽状态变量**
   - `favDragSourceIndex/TargetIndex/Snapshot/Placeholder/SourceViews/AppRows/RemainingRows/Order` 全部删除
   - 只保留 `isDragging` 标志（抑制 reloadData）

**预计改动文件**：
- `QuickPanelView.swift` - 替换拖拽核心逻辑（~150 行替换 ~160 行，净减少代码）

---

## 6. 参考资料

- [DraggingStackView Gist](https://gist.github.com/monyschuk/cbca3582b6b996ab54c32e2d7eceaf25) - NSStackView 拖拽排序参考实现
- [Apple NSDraggingSource](https://developer.apple.com/documentation/appkit/nsdraggingsource) - 拖拽源协议
- [Apple NSDraggingDestination](https://developer.apple.com/documentation/appkit/nsdraggingdestination) - 拖拽目标协议
- [Kodeco Drag and Drop Tutorial](https://www.kodeco.com/1016-drag-and-drop-tutorial-for-macos) - macOS 拖拽教程
- [NSCollectionView Drag Drop](https://github.com/harryworld/NSCollectionView-DragDrop) - NSCollectionView 拖拽示例
- [proxpero Custom NSView Drag](http://proxpero.com/2016/01/18/drag-and-drop-nsview/) - 自定义 NSView 拖拽实现
- [objc.io AppKit 动画](https://www.objc.io/issues/14-mac/appkit-for-uikit-developers/) - AppKit 层动画说明
