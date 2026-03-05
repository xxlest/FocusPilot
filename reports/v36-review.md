# V3.6 架构设计评审报告

**评审对象**：`reports/v36-architecture.md`
**对照源码**：`FocusPilot/QuickPanel/QuickPanelView.swift`（1149 行）
**评审日期**：2026-03-05

---

## P0 问题（阻塞，必须修正）

### P0-1：`@objc private` 在 extension 中的编译行为描述有误

**文档原文**（1.2 节，第 134 行）：
> `@objc private` 在 extension 中无法编译，需改为 `@objc func`（internal）

**实际情况**：Swift 5 中，`@objc private` 在同一 module 的 extension 中**可以编译通过**。`private` 在独立文件中等效于 `fileprivate`，Objective-C runtime 通过 selector 调用不受 Swift 可见性限制。因此这些 `@objc` handler 方法**可以保持 `private`**（即 `fileprivate` 到 MenuHandler 文件），无需暴露为 `internal`。

**风险**：如果按文档执行，会不必要地将 `handleCloseWindow`、`handleRenameWindow` 等 8 个 `@objc` 方法暴露为 `internal`，增加模块耦合面。

**修正建议**：删除"无法编译"的结论。`@objc` handler 方法统一使用 `@objc private func`（编译后等效 `fileprivate`），既能被 ObjC selector 正确调用，又不会在其他文件中暴露。

---

### P0-2：`contentStack` 不应标记为需要 RowBuilder 访问

**文档原文**（1.2 节可见性表格）：
> `contentStack` | RowBuilder | `buildRunningAppList` 中添加子视图

**实际情况**：根据文档 1.1 节的文件划分，`buildRunningAppList` 保留在主文件（第 29 行明确列出），不属于 RowBuilder。RowBuilder 只负责创建单行视图（`createRunningAppRow`、`createAppRow`、`createWindowRow` 等），返回 `NSView`，不直接操作 `contentStack`。

**风险**：将 `contentStack` 暴露为 `internal` 后，RowBuilder 可能误用，破坏主文件对内容容器的独占控制。

**修正建议**：从"需要 internal"表格中移除 `contentStack`，保持 `private`。

---

## P1 问题（重要，应修正）

### P1-1：`forceReload()` 散布点计数有误

**文档原文**（1.3.1 节）：
> 所有现有的 `lastStructuralKey = "" + reloadData()` 散布点（共 12 处）

**实际计数**：源码中 `lastStructuralKey = ""` 出现 13 次，其中：
- 伴随 `reloadData()` 的有 **11 处**（accessibilityDidGrant / switchTab / 折叠展开 / 无窗口App / 窗口行点击 / handleCloseWindow / handleRenameWindow x2 / handleClearRename / handlePinToTop / handleToggleFavorite）
- `resetToNormalMode` 中 1 处（不伴随 `reloadData()`，文档已正确标注）
- 总共 11 处需替换为 `forceReload()`（含 handleToggleFavorite 的特殊处理）

文档表格实际也列了 11 行（含 handleToggleFavorite），但正文说"共 12 处"，数字不一致。

**修正建议**：将"共 12 处"修正为"共 11 处"。

### P1-2：关联对象 key 迁移方案存在矛盾

**文档原文**（1.5 非目标 第 8 项）：
> 不修改 `private` 关联对象 key（`bundleIDKey`、`displayNameKey`）的位置

**但文档 1.6 节明确提出迁移方案**：
> 最简单的方案是将它们提升为 `QuickPanelView` 的 static 属性

两处自相矛盾：非目标声明说"不修改位置"，影响分析又说"提升为 static 属性"。

**实际需求**：拆分后 `bundleIDKey` 在 RowBuilder 中写入（`createAppRow` 的 `objc_setAssociatedObject`），在 MenuHandler 中读取（`handleToggleFavorite` 的 `objc_getAssociatedObject`）。跨文件的 `private var` 无法共享，**必须迁移**。

**修正建议**：从非目标列表中移除第 8 项，在 1.2 接口契约中明确记录：将 `bundleIDKey` 和 `displayNameKey` 从文件级 `private var` 提升为 `QuickPanelView` 的 `static var`。

### P1-3：`handleToggleFavorite` 双重刷新修复方案需补充时序说明

**文档方案**：去掉显式 `forceReload()`，依赖 ConfigStore 通知触发 `reloadData()`，因为 `buildStructuralKey()` 包含 `fav` 标记会自动检测结构变化。

**验证结果**：方案逻辑正确——`buildStructuralKey()` 在活跃 Tab 中确实包含 `ConfigStore.shared.isFavorite(app.bundleID) ? "F" : ""` 标记（源码第 362 行），收藏状态变更会改变 structuralKey，普通 `reloadData()` 即可全量重建。

**但存在隐患**：`handleToggleFavorite` 当前只在活跃 Tab 显示（源码第 556 行 `if currentTab == .running`），但如果未来收藏 Tab 也添加星号按钮，收藏 Tab 的 `buildStructuralKey()` **不包含 `fav` 标记**（源码第 366-374 行），通知触发的 `reloadData()` 将走差分路径而非全量重建，导致 UI 不更新。

**修正建议**：在文档中补充约束："如果未来收藏 Tab 也使用 `handleToggleFavorite`，需要在收藏 Tab 的 structuralKey 中加入收藏标记，或改为显式 `forceReload()`"。

### P1-4：缺少 `launchApp` 的可见性声明

**源码**：`launchApp(bundleID:)` 当前是 `private`（第 940 行），在 `createAppRow` 的 click handler 闭包中通过 `self?.launchApp(bundleID:)` 调用（第 625 行）。

**拆分后**：`createAppRow` 移至 RowBuilder 文件，闭包捕获的 `self` 调用 `launchApp` 需要该方法至少为 `internal`。

**文档状态**：1.2 节方法表中已列出 `launchApp(bundleID:)` 需要 `internal`，但 1.1 节文件划分中 `launchApp()` 被列在主文件的"保留内容"（第 31 行），这暗示它留在主文件但被 RowBuilder 的 extension 跨文件调用。关系是正确的，但建议在可见性表中明确标注"定义在主文件，被 RowBuilder 闭包跨文件调用"。

---

## P2 问题（建议，可接受）

### P2-1：`createSpacer()` 提取价值有限

**文档提议**：提取 `createSpacer()` 方法消除重复（1.3.5 节）。

**实际影响**：当前只有 `createAppRow`（第 595-598 行）和 `createWindowRow`（第 736-739 行）两处创建 spacer，各 3 行代码。提取为方法后调用点仍然是 2 处，节省的代码量极少（总共 4 行），但增加了一个需要维护的方法签名。

**建议**：可做可不做，不阻塞。如果执行，放在 RowBuilder 文件中（`private` 即可，因为两个调用点都在 RowBuilder）。

### P2-2：`handleRenameWindow` UI 拆分可推迟

**文档提议**（1.3.6 节）：将 `handleRenameWindow` 拆为 `showRenameAlert` + `applyWindowRename` 两个方法。

**评估**：当前 `handleRenameWindow` 约 35 行，逻辑清晰（弹窗 → 判断 → 保存 → 刷新），拆分后反而增加方法数量和跳转成本。这属于代码整洁度优化，对模块化拆分不是必要条件。

**建议**：可推迟到后续迭代，本次重构聚焦文件拆分和 `forceReload()` 统一即可。

### P2-3：`HoverableRowView` 属性分类（MARK 注释）优先级低

**文档提议**（1.3.7 节）：用 MARK 注释区分"构建配置"和"运行时状态"属性。

**评估**：`HoverableRowView` 仅 90 行左右，6 个属性一目了然，MARK 注释增加的可读性收益有限。

**建议**：可做可不做，不阻塞。

### P2-4：需要改为 internal 的 private 属性完整清单

文档 1.2 节列出了 6 个属性和 8 个方法需要从 `private` 改为 `internal`。经逐一核对源码，以下是最终确认的清单：

**属性（需 private → internal）**：
| 属性 | 当前行号 | 访问者 |
|------|----------|--------|
| `currentTab` | L25 | RowBuilder（`createAppRow` 判断星号按钮） |
| `collapsedApps` | L31 | RowBuilder（`createAppRow` 判断折叠/click handler） |
| `highlightedWindowID` | L28 | RowBuilder（`createWindowRow` 设置高亮 / click handler 赋值） |
| `windowTitleLabels` | L37 | RowBuilder（`createWindowRow` 注册 label） |
| `windowRowViewMap` | L39 | RowBuilder（`createWindowRow` 注册行视图） |
| `lastStructuralKey` | L34 | 仅主文件的 `forceReload()` 使用，**不需要 internal**（如果 RowBuilder/MenuHandler 统一调用 `forceReload()` 而非直接操作该属性） |

注意：文档表格中列了 6 个属性，但 `contentStack` 应移除（见 P0-2），`lastStructuralKey` 也不需要暴露（通过 `forceReload()` 间接访问）。实际需要改为 internal 的属性是 **5 个**。

**方法（需 private → internal）**：
| 方法 | 访问者 |
|------|--------|
| `forceReload()` | RowBuilder（闭包中调用）、MenuHandler |
| `createLabel(_:size:color:)` | RowBuilder |
| `cachedSymbol(name:size:weight:)` | RowBuilder（static 方法，本身已经是 internal 可见） |
| `resolveDisplayTitle(bundleID:windowInfo:)` | RowBuilder |
| `launchApp(bundleID:)` | RowBuilder（闭包中调用） |
| `createWindowContextMenu(bundleID:windowInfo:)` | RowBuilder（定义在 MenuHandler，RowBuilder 调用） |
| `createFavoriteContextMenu(bundleID:)` | RowBuilder（定义在 MenuHandler，RowBuilder 调用） |

注意：`cachedSymbol` 是 `private static` 方法（源码第 1026 行），拆分后需改为 `static func`（去掉 `private`）。`renameKey` 已经是 `static func`（源码第 857 行），无需修改。

---

## 遗漏的跨模块依赖检查

经核对源码，以下依赖在文档中**已正确覆盖**：
- RowBuilder → 主文件：`currentTab`、`collapsedApps`、`highlightedWindowID`、`windowTitleLabels`、`windowRowViewMap`、`forceReload()`、`createLabel`、`cachedSymbol`、`resolveDisplayTitle`、`launchApp`
- RowBuilder → MenuHandler：`createWindowContextMenu`、`createFavoriteContextMenu`
- MenuHandler → 主文件：`forceReload()`
- MenuHandler ↔ RowBuilder：`bundleIDKey`/`displayNameKey`（关联对象 key，需提升为 static 属性）

**未遗漏的依赖**：无发现额外遗漏。

---

## 总结

| 级别 | 数量 | 说明 |
|------|------|------|
| P0 | 2 | `@objc private` 编译行为误判；`contentStack` 可见性错误 |
| P1 | 4 | 散布点计数偏差；关联对象 key 方案矛盾；双重刷新时序隐患；`launchApp` 描述补充 |
| P2 | 4 | `createSpacer` 价值有限；`handleRenameWindow` 拆分可推迟；MARK 分类优先级低；属性清单确认 |

### 评审结论：有条件通过

架构方案整体思路正确——纯 extension 拆分、不引入新抽象、`forceReload()` 统一散布点、双重刷新修复方案合理。文件划分的"独立变化理由"充分，验收用例覆盖全面。

**通过条件**：修正 2 个 P0 问题（`@objc private` 描述纠正 + `contentStack` 移出 internal 清单），以及处理 P1-2（关联对象 key 方案矛盾）后即可进入实施阶段。其余 P1/P2 问题可在实施过程中同步处理。
