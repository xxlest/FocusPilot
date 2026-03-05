# V3.6 QuickPanel 模块化拆分 — QA 缺陷检测报告

日期：2026-03-05

## 阶段 A：验收用例验证

| ID | 场景 | 结果 | 备注 |
|----|------|------|------|
| TC-01 | 文件拆分后编译 | PASS | 三个文件均使用 `extension QuickPanelView`，可见性正确，无编译障碍（详见 B-1~B-3 分析） |
| TC-02 | 活跃 Tab 功能 | PASS | `buildRunningTabContent` → `buildRunningAppList` → `createRunningAppRow` 调用链完整；折叠/展开通过 `collapsedApps` + `forceReload()` 实现；窗口行点击设置 `highlightedWindowID` + `activateWindow` + `forceReload()` |
| TC-03 | 收藏 Tab 功能 | PASS | `buildFavoritesTabContent` 正确遍历 `ConfigStore.shared.appConfigs`；`handlePinToTop` 调用 `reorderApps` + `forceReload()`；`handleRemoveFavorite` 调用 `removeApp` 依赖通知刷新 |
| TC-04 | 窗口右键菜单 | PASS | `createWindowContextMenu` 创建关闭/重命名/清除菜单项；`handleRenameWindow` 拆分为 `showRenameDialog` + `applyRename` 两步；`handleClearRename` 正确清除并 `forceReload()` |
| TC-05 | forceReload 差分更新 | PASS | `reloadData()` 通过 `buildStructuralKey()` 比较结构变化，标题变化走 `updateWindowTitles()` 轻量路径；`forceReload()` 清空 `lastStructuralKey` 后调用 `reloadData()` 强制全量重建 |
| TC-06 | 星号收藏无双重刷新 | PASS | `handleToggleFavorite` 不再显式调用 `forceReload()`，依赖 `addApp/removeApp` 内部通知。`buildStructuralKey()` 中包含 `fav` 标记，确保收藏变化被差分检测到，自动走全量重建 |
| TC-07 | runtimeOrder 删除 | PASS | 全局搜索 `runtimeOrder`，仅在 reports 目录的历史文档中存在，源代码中无残留引用 |
| TC-08 | HoverableRowView 交互 | PASS | `HoverableRowView` 实现了 `mouseEntered/mouseExited` hover 高亮、`mouseUp` 点击分发（区分按钮 vs 行点击）、`menu(for:)` 右键菜单代理 |

**验收用例全部 PASS。**

## 阶段 B：探索性测试发现

### B-1 跨文件可见性 — 无问题

extension 中的方法可以正确访问主文件中的 internal 属性。已确认以下属性从 `private` 调整为 `internal`（无修饰符）：
- `currentTab`、`collapsedApps`、`highlightedWindowID`、`windowTitleLabels`、`windowRowViewMap`、`contentStack`

`lastStructuralKey` 和 `trackingArea` 保持 `private`，仅主文件内部使用，正确。

### B-2 @objc selector 跨文件 — 无问题

关键跨文件 selector：
- `#selector(handleToggleFavorite(_:))` — RowBuilder(L130) 引用，MenuHandler(L155) 定义
- `#selector(openAccessibilitySettings)` — RowBuilder(L378) 引用，MenuHandler(L192) 定义
- `#selector(openMainKanban)` — 主文件(L64) 引用，MenuHandler(L188) 定义

Swift 编译器在同一 module 内统一处理所有 extension 的 `@objc` 方法，selector 可正确解析。所有 `@objc` handler 均为 `@objc func`（internal），未使用 `@objc private`（在 extension 中会编译错误）。

### B-3 关联对象 key 跨文件 — 无问题（但有改进建议）

`bundleIDKey` 和 `displayNameKey` 声明在 `QuickPanelMenuHandler.swift` 顶部（L5-L6），为文件级变量，默认 `internal` 可见性。RowBuilder 中通过 `&bundleIDKey` 写入（L131-132），MenuHandler 中通过 `&bundleIDKey` 读取（L156-157）。

由于两个文件引用的是**同一个** internal 变量，内存地址相同，关联对象可正确工作。

> **P2 改进建议**：架构文档 1.6 节建议将其提升为 `QuickPanelView` 的 `static` 属性，当前实现使用文件级变量也可工作，但 `static` 属性更符合封装原则。

### B-4 forceReload() 调用链 — 已完全替换

源代码中 `lastStructuralKey = ""` 仅出现两处：
1. `QuickPanelView.swift:323` — `forceReload()` 方法体内（定义处）
2. `QuickPanelView.swift:407` — `resetToNormalMode()` 内（按设计不调用 reloadData，保持原样）

所有原来的 `lastStructuralKey = "" + reloadData()` 散布点均已替换为 `forceReload()` 调用。

### B-5 双重刷新修复 — 已正确修复

- `handleToggleFavorite`（MenuHandler L155-166）：不调用 `forceReload()`，注释说明依赖通知机制
- `handleRemoveFavorite`（MenuHandler L145-149）：不调用 `forceReload()`，依赖 `removeApp` 内部通知

两者均通过 `ConfigStore.addApp/removeApp` → `appStatusChanged` 通知 → `appStatusDidChange` → `reloadData()` 路径刷新。`buildStructuralKey()` 中的 `fav` 标记确保收藏变化被检测为结构变化。

### B-6 死代码

| 项目 | 文件 | 严重级别 | 说明 |
|------|------|----------|------|
| `import ApplicationServices` | QuickPanelView.swift:2 | P2 | 未直接使用 ApplicationServices 中的符号，AX 相关调用通过 WindowService 间接访问。可移除 |

### B-7 runtimeOrder 删除 — 已确认完全删除

源代码中无任何 `runtimeOrder` 引用，仅在 reports 目录的历史设计文档中存在。

## 阶段 C：代码审查发现

### C-1 复杂度分析

| 位置 | 复杂度 | 说明 |
|------|--------|------|
| `buildStructuralKey()` 收藏 Tab 分支 | O(n*m) | 对每个 config 调用 `runningApps.first(where:)` 线性查找。n=收藏数，m=运行 App 数。实际场景 n,m < 50，无性能问题 |
| `updateWindowTitles()` | O(n*w) | 遍历所有 App 的所有窗口，检查 titleLabel 映射。n=App 数，w=窗口数。字典查找 O(1)，整体 O(总窗口数)，无问题 |
| `buildRunningAppList()` / `buildFavoritesTabContent()` | O(n*w) | 遍历构建视图，每个 App 构建一行 + 窗口列表。正常复杂度 |

**结论：无 O(n^2) 或更差的复杂度问题。**

### C-2 资源泄漏检查

| 资源 | 清理位置 | 结论 |
|------|----------|------|
| QuickPanelView trackingArea | `deinit`(L126) + `updateTrackingArea()`(L214) | 正确 |
| HoverableRowView trackingArea | `deinit`(L537) + `updateTrackingArea()`(L548) | 正确 |
| NotificationCenter observers | `deinit`(L129) `removeObserver(self)` | 正确 |
| windowTitleLabels / windowRowViewMap | `reloadData()` 全量重建时清空(L333-334)；`resetToNormalMode()` 清空(L405-406) | 正确 |

**结论：无资源泄漏。**

### C-3 强制解包崩溃风险

| 位置 | 代码 | 风险级别 | 说明 |
|------|------|----------|------|
| RowBuilder L77 | `NSImage(named: NSImage.applicationIconName)!` | P2（极低风险） | `NSImage.applicationIconName` 是系统内置图标常量，理论上永远不会返回 nil。但强制解包不符合防御性编程风格。建议改为 `?? NSImage()` |
| MenuHandler L193 | `URL(string: "x-apple.systempreferences:...")!` | P2（极低风险） | 硬编码合法 URL，不会返回 nil |

### C-4 symbolCache 内存增长分析

`symbolCache` 是 `static var`（类级别），存储 SF Symbol 图片缓存。

缓存 key 格式：`"\(name)-\(Int(size))-\(Int(weight.rawValue * 100))"`

当前代码中使用的 symbol 组合：
- `gearshape-12-medium`、`star.fill-11-regular`、`star-11-regular`、`macwindow-10-regular`、`chevron.right-10-medium`、`chevron.down-10-medium`

最多约 6-8 个不同的缓存条目，每个 NSImage 约几 KB。**无内存增长风险**。缓存是有界的，因为 symbol 名称/大小/粗细组合是代码中硬编码的有限集合。

### C-5 其他发现

| 项目 | 严重级别 | 说明 |
|------|----------|------|
| `applyRename` else if 冗余条件 | P2 | MenuHandler L98 `else if newName == originalTitle \|\| newName.isEmpty` 中，由于第一个 if 分支排除了 `newName.isEmpty`，else 分支中 `newName.isEmpty` 永远为 false。可简化为 `else`，但不影响正确性 |
| 架构文档建议 `bundleIDKey` 改为 static 属性 | P2 | 1.6 节建议提升为 `QuickPanelView.static` 属性，当前使用文件级 internal 变量功能正确，但封装性稍弱 |

## 总结

| 级别 | 数量 | 说明 |
|------|------|------|
| P0（编译/运行时错误） | 0 | 无 |
| P1（功能缺陷） | 0 | 无 |
| P2（代码质量/改进建议） | 4 | 1. 多余 import ApplicationServices；2. 强制解包 NSImage；3. applyRename 冗余条件；4. bundleIDKey 封装建议 |

**模块化拆分质量良好**，8 个验收用例全部通过，无 P0/P1 缺陷。B-2（selector 跨文件）和 B-3（关联对象 key 跨文件）两个高风险项均验证通过。
