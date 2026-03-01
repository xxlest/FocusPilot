# PinTop 验收报告

## 历史版本

### V1.1 全代码库缺陷扫描（2026-03-01 早期）

3 个 QA Agent 并行扫描 5 个模块，去重后发现 17 个 Bug（P0×1, P1×10, P2×6），全部 P0/P1 已修复。

### V1.2 用户报告 Bug 修复（2026-03-01 上午）

修复 5 个用户报告 Bug：拖动漂移、方框阴影、权限灰色、窗口无标题、安装问题。

### V1.2.1 功能增强 + Bug 深度修复（2026-03-01）

4 项需求：浮球右键菜单、窗口标题深度修复、浮球视觉优化、权限灰色深度修复。

### V1.3 功能增强 + UX 优化（2026-03-01）

4 项需求：关闭=退出App、Dock栏图标、悬浮球品牌Logo、置顶集成快捷面板。3 agent 并行开发，全部通过。

### V1.4 软件优化 + Bug 修复（2026-03-01）

9 项需求：快捷面板紧凑布局、面板拖拽resize修复、单击悬浮球→面板、置顶Bug修复(CGS诊断+AXRaise回退)、关闭=隐藏、退出机制、PT+图钉Logo、状态栏图标、maxPinnedWindows=3。3 agent 并行开发，25 条用例全部通过。

### V1.5 交互优化 + Bug 深度修复（2026-03-01）

7 项需求：浮球单击切换面板钉住、Pin超限Toast、Pin Bug深度修复(CGSOrderWindow+app.activate)、"打开主界面"按钮、图钉旋转反馈、侧边栏退出固定、Dock图标品牌化。2 agent 并行开发，20 条用例全部通过。

---

## V1.6 交互优化 + 快捷面板增强（2026-03-01）

**日期**: 2026-03-01
**范围**: 10 项需求（4 UX + 3 Feature + 2 UI + 1 Bug）
**规模**: M（5 个文件修改）
**流程**: Teams 开发流程（M 规模），2 个 agent 并行开发 + team lead 补充修改

---

## 1. 需求完成情况

| # | 需求 | 类型 | 状态 |
|---|------|------|------|
| 1 | 面板钉住时 hover 浮球无反应 | UX | ✅ 已完成 |
| 2 | 面板钉住按钮 SF Symbol（倾斜/竖直+背景加深） | UI | ✅ 已完成 |
| 3a | 窗口 Pin 图标已 Pin 排列表顶部 | UX | ✅ 已完成 |
| 3b | 激活非 Pin 窗口排在 Pin 窗口下面 | UX | ✅ 已完成 |
| 4a/b | 多窗口 App 折叠/展开 | Feature | ✅ 已完成 |
| 4c | 面板标题栏可拖动 | Feature | ✅ 已完成 |
| 4d/e | 面板与浮球联动拖动 | Feature | ✅ 已完成 |
| 5 | 浮球图标立体化（3D 质感） | UI | ✅ 已完成 |
| 6 | 多窗口 App 行点击也激活应用 | Bug | ✅ 已修复 |

## 2. 验收用例结果

| 用例 | 描述 | 结果 | 验证方式 |
|------|------|------|----------|
| TC-01 | 面板钉住时 hover 浮球无反应 | PASS | 代码审查（mouseEntered: guard !isPanelPinned） |
| TC-02 | 面板钉住时贴边半隐藏不触发 | PASS | 代码审查（checkHalfHide: guard !isPanelPinned） |
| TC-03 | 面板 Pin 按钮未钉住：倾斜 pin + 灰色 | PASS | 代码审查（updatePanelPinButton: pin + secondaryLabelColor） |
| TC-04 | 面板 Pin 按钮已钉住：竖直 pin.fill + 蓝色 + 背景 | PASS | 代码审查（rotate 45° + systemBlue + bgColor 0.15） |
| TC-05 | 已 Pin 窗口排列表最前面 | PASS | 代码审查（createWindowList: pinnedByPin 先渲染） |
| TC-06 | Pin 区和非 Pin 区之间有分割线 | PASS | 代码审查（NSBox.separator 插入） |
| TC-07 | 激活非 Pin 窗口后 Pin 窗口仍在上层 | PASS | 代码审查（activateWindow 末尾 orderWindowAbove 循环） |
| TC-08 | 多窗口 App 显示 chevron 指示器 | PASS | 代码审查（chevron.right/down SF Symbol） |
| TC-09 | 点击多窗口 App 行切换折叠/展开 | PASS | 代码审查（handleAppToggleCollapse toggle collapsedApps） |
| TC-10 | 折叠时隐藏窗口列表 | PASS | 代码审查（buildNormalMode: !collapsedApps.contains） |
| TC-11 | 点击多窗口 App 行同时激活应用 | PASS | 代码审查（handleAppToggleCollapse: activateApp） |
| TC-12 | 面板 topBar 区域（24px）可拖动 | PASS | 代码审查（sendEvent: isDraggingPanel + handlePanelDrag） |
| TC-13 | topBar 上按钮点击不被拖动拦截 | PASS | 代码审查（hitTest 检查 NSButton 后 break） |
| TC-14 | 拖动浮球时面板钉住状态下同步移动 | PASS | 代码审查（FloatingBall.dragMoved 通知 + delta） |
| TC-15 | 拖动面板标题栏时浮球同步移动 | PASS | 代码审查（QuickPanel.dragMoved 通知 + delta） |
| TC-16 | 联动拖动无递归（isSyncMoving 防护） | PASS | 代码审查（双方 isSyncMoving guard） |
| TC-17 | 面板钉住时拖动浮球不关闭面板 | PASS | 代码审查（!isPanelPinned 才发 dragStarted） |
| TC-18 | 浮球图标立体球形高光 | PASS | 代码审查（椭圆高光 + 底部暗区 + 内边缘光） |
| TC-19 | 图标图钉和文字有投影 | PASS | 代码审查（shadowTinted + shadowPtString 偏移 0.5px） |
| TC-20 | 编译通过 | PASS | `make build` 成功 |
| TC-21 | 安装运行正常 | PASS | `make install` 成功 + 进程启动 |

## 3. 实现详情

### 需求 1: 面板钉住时 hover 浮球无反应

**修改**: `FloatingBallView.swift`
- 新增 `isPanelPinned` 标志，监听 `QuickPanel.pinStateChanged` 通知
- `mouseEntered`: `guard !isPanelPinned else { return }` 跳过所有 hover 逻辑
- `checkHalfHide`: `guard !isPanelPinned else { return }` 不触发贴边半隐藏

### 需求 2: 面板钉住按钮视觉优化

**修改**: `QuickPanelView.swift`
- `panelPinButton` 从 emoji 📌 替换为 SF Symbol `pin`（pointSize 12, weight .medium）
- `updatePanelPinButton(isPinned:)`:
  - 已钉住：`pin.fill` + NSAffineTransform 旋转 45° + `.systemBlue` + 蓝色背景 0.15 + cornerRadius 4
  - 未钉住：`pin` 默认倾斜 + `.secondaryLabelColor` + 无背景

### 需求 3a: 已 Pin 窗口排列表最上方

**修改**: `QuickPanelView.swift`
- `createWindowList`: 先按 Pin 状态分组（pinnedByPin/unpinnedByPin），已 Pin 窗口先渲染
- Pin 区与非 Pin 区之间插入分割线，非 Pin 区保持关键词分区排序

### 需求 3b: 激活非 Pin 窗口排在 Pin 窗口下面

**修改**: `WindowService.swift`
- `activateWindow` 末尾遍历 `PinManager.shared.pinnedWindows` 调用 `orderWindowAbove`

### 需求 4a/b: 多窗口 App 折叠/展开

**修改**: `QuickPanelView.swift`
- 新增 `collapsedApps: Set<String>` 按 bundleID 跟踪折叠状态
- App 行添加 chevron 指示器（chevron.down/right）
- 多窗口 App 整行可点击切换折叠/展开
- `buildNormalMode` 中按折叠状态决定是否渲染窗口列表

### 需求 4c: 面板标题栏可拖动

**修改**: `QuickPanelWindow.swift`
- `sendEvent` 中 topBar 区域（窗口顶部 24px）检测拖动，hitTest 排除按钮
- 新增 `handlePanelDrag()` 使用增量 delta 移动面板

### 需求 4d/e: 面板与浮球联动拖动

**修改**: `QuickPanelWindow.swift` + `FloatingBallView.swift`
- 双向通知：`FloatingBall.dragMoved` / `QuickPanel.dragMoved` 携带 deltaX/deltaY
- 双方 `isSyncMoving` 标志防递归
- 面板钉住时拖浮球不发 `dragStarted`（不关闭面板）

### 需求 5: 浮球图标立体化

**修改**: `FloatingBallView.swift`
- `createBrandLogo`: 三色渐变（亮→中→暗，angle 135°）
- 左上椭圆高光（白色渐变，模拟 3D 球体反射）
- 底部暗区椭圆（黑色渐变，增强球形立体感）
- 内边缘白色描边 0.8px（增强质感）
- 图标和文字投影（黑色 0.3 透明度，偏移 0.5px）

### 需求 6: 多窗口 App 行点击也激活应用

**修改**: `QuickPanelView.swift`
- `handleAppToggleCollapse` 在切换折叠状态后同时调用 `activateApp(bundleID)`

## 4. 架构符合度

- ✅ 所有修改在现有 5 个文件内完成，未新增文件
- ✅ 通知驱动架构不变（新增 dragMoved/pinStateChanged 通知遵循现有模式）
- ✅ 双向联动拖动通过 isSyncMoving 防递归，架构清晰
- ✅ 折叠状态本地管理（不持久化），符合快捷面板临时 UI 的定位

## 5. 非目标确认

- ❌ 未修改数据模型（ConfigStore/AppConfig/PinnedWindow 不变）
- ❌ 未新增国际化
- ❌ 未修改权限管理（PermissionManager 不变）
- ❌ 未修改 AppDelegate.swift（V1.5 的逻辑不变）
- ❌ 未修改 PinManager.swift（V1.5 的逻辑不变）

## 6. 已知问题

| 级别 | 描述 | 影响 |
|------|------|------|
| P2 | AppMonitor L80 checkAccessibility() 返回值未使用（编译 warning） | 不影响功能 |
| P2 | 每次 make install 后需重新授权辅助功能 | macOS 安全机制限制 |
| 待办 | 内存占用优化（~105MB > 80MB 目标） | 历史遗留 |
| 待办 | 面板打开时 CPU 偏高（窗口刷新定时器） | 历史遗留 |

## 7. 交付物清单

| 文件 | 修改内容 |
|------|----------|
| `FloatingBallView.swift` | hover 抑制 + 联动拖动 + 立体图标 |
| `QuickPanelView.swift` | Pin 按钮视觉 + Pin 排序 + 折叠/展开 + App 行激活 |
| `QuickPanelWindow.swift` | 标题栏拖动 + 联动拖动 |
| `WindowService.swift` | activateWindow 后恢复 Pin 窗口层级 |

## 8. 安装后操作指南

```bash
# 编译安装
make install

# 安装后重新授权辅助功能：
# 系统设置 → 隐私与安全性 → 辅助功能 → 找到 PinTop → 关闭 → 重新开启

# 验证
# 1. 单击悬浮球 → 弹出面板 + 钉住；面板钉住时 hover 浮球无反应
# 2. 面板右上角 Pin 按钮：未钉住=倾斜灰色，钉住=竖直蓝色+背景
# 3. 窗口图钉：灰色倾斜=未置顶，红色竖直=已置顶，置顶窗口排列表最前
# 4. 多窗口 App 可折叠/展开（chevron 指示器），点击同时激活应用
# 5. 面板顶部 24px 区域可拖动移动面板
# 6. 面板钉住时：拖浮球带面板，拖面板带浮球（联动拖动）
# 7. 浮球图标有 3D 立体质感（球形高光+底部暗区+投影）
```

---

## V1.6.1 Bug 修复（2026-03-01）

**日期**: 2026-03-01
**范围**: 3 个 Bug 修复
**规模**: S（3 个文件修改）
**流程**: 直接修复（S 规模）

---

## 1. Bug 修复情况

| # | Bug 描述 | 根因 | 修复方式 | 状态 |
|---|----------|------|----------|------|
| 1 | Pin 窗口视觉变化但实际不置顶 | CGSSetWindowLevel 对跨进程窗口可能不生效 + listWindows 过滤 layer==0 导致 Pin 后窗口从列表消失 | (a) listWindows/listAllWindows 放行已 Pin 窗口(layer!=0 也保留) (b) PinManager 添加层级持续维持机制(定时器+App切换监听) | ✅ 已修复 |
| 2 | 面板窗口顺序与屏幕显示不一致 | categorizeWindows 按关键词索引排序打乱了 CGWindowList 原始 z-order | 移除关键词索引排序，保持 CGWindowList 返回的 z-order | ✅ 已修复 |
| 3 | 无窗口/单窗口应用点击不激活 | V1.6 折叠功能 `windows.count > 1` 条件导致单窗口 App 的窗口列表不再显示 | 改为 `!app.windows.isEmpty && !(多窗口已折叠)` | ✅ 已修复 |

## 2. 验收用例结果

| 用例 | 描述 | 结果 | 验证方式 |
|------|------|------|----------|
| TC-01 | Pin 窗口后窗口实际置顶 | PASS | 代码审查（enforcePinnedLevels: orderWindowAbove 循环 + didActivateApplication 监听） |
| TC-02 | Pin 窗口在列表刷新后仍显示 | PASS | 代码审查（listWindows: layer==0 \|\| isPinned(windowID)） |
| TC-03 | 面板窗口顺序与屏幕 z-order 一致 | PASS | 代码审查（categorizeWindows 不再 sorted by keywordIndex） |
| TC-04 | 单窗口 App 显示窗口列表 | PASS | 代码审查（buildNormalMode: !app.windows.isEmpty && !(多窗口已折叠)） |
| TC-05 | 多窗口 App 折叠/展开正常 | PASS | 代码审查（条件逻辑兼容 count==1 和 count>1） |
| TC-06 | 无窗口运行中 App 点击激活 | PASS | 代码审查（else 分支 handleAppClick → activateApp） |
| TC-07 | 编译通过 | PASS | `make build` 成功（仅 1 个历史 warning） |
| TC-08 | 安装运行正常 | PASS | `make install` 成功 + 进程启动 |

## 3. 实现详情

### Bug 1: Pin 窗口层级持续维持

**修改**: `WindowService.swift` + `PinManager.swift`

**WindowService.swift**:
- `listWindows(for:)` 和 `listAllWindows()`：layer 过滤条件从 `layer == 0` 改为 `layer == 0 || PinManager.shared.isPinned(windowID)`
- `cgsMainConnectionIDFunc` 和 `cgsSetWindowLevelFunc` 改为非 private，供 PinManager 直接调用

**PinManager.swift**:
- 新增 `enforcementTimer`：有 Pin 窗口时每 1 秒调用 `enforcePinnedLevels()` 强制维持层级
- 新增 `activationObserver`：监听 `NSWorkspace.didActivateApplicationNotification`，App 切换时立即重新提升 Pin 窗口（延迟 0.1s 等系统排序完成）
- `enforcePinnedLevels()`：对每个 Pin 窗口调用 CGSSetWindowLevel + orderWindowAbove
- `startEnforcementIfNeeded()` / `stopEnforcementIfNeeded()`：pin/unpin/unpinAll 时自动启停

### Bug 2: 窗口顺序保持 z-order

**修改**: `QuickPanelView.swift`
- `categorizeWindows` 移除 `sorted(by: keywordIndex)` 排序，直接用 `append` 保持 CGWindowList 原始 z-order
- 各分区（Pin 区 / 关键词区 / 普通区）内部均保持屏幕显示顺序

### Bug 3: 单窗口 App 窗口列表恢复

**修改**: `QuickPanelView.swift`
- `buildNormalMode` 窗口列表条件从 `app.windows.count > 1 && !collapsed` 改为 `!app.windows.isEmpty && !(count > 1 && collapsed)`
- 单窗口 App 始终展示窗口列表（与 V1.5 行为一致）
- 多窗口 App 保持折叠/展开功能

## 4. 交付物清单

| 文件 | 修改内容 |
|------|----------|
| `WindowService.swift` | layer 过滤放行已 Pin 窗口 + CGS 函数指针暴露 |
| `PinManager.swift` | 层级持续维持（定时器+App切换监听） |
| `QuickPanelView.swift` | 窗口 z-order 保持 + 单窗口列表恢复 |

## 5. 安装后操作指南

```bash
make install
# 系统设置 → 隐私与安全性 → 辅助功能 → PinTop 关闭 → 重新开启
# 验证：Pin 窗口实际置顶 + 切换 App 后 Pin 窗口仍在最上层
# 验证：面板窗口顺序与屏幕一致
# 验证：单窗口 App 可看到并点击窗口行
```

---

## V1.7 悬浮球颜色调整（2026-03-01）

**日期**: 2026-03-01
**范围**: 悬浮球正常态背景色从蓝色改为橙色
**规模**: S（1 个文件修改）
**流程**: Teams 开发流程（S 规模）

---

## 1. 需求

将悬浮球正常态（无置顶窗口时）的品牌 Logo 背景渐变色从蓝色系改为橙色系，使视觉更新颖。

## 2. 验收用例结果

| 用例 | 描述 | 结果 | 验证方式 |
|------|------|------|----------|
| TC-01 | 正常态渐变色已改为橙色系 | PASS | 代码审查（浅橙 1.0/0.65/0.3 → 中橙 0.9/0.45/0.1 → 深橙 0.6/0.25/0.05） |
| TC-02 | 高亮态（有置顶窗口）仍为红色渐变 | PASS | 代码审查（if highlighted 分支未修改，红色色值不变） |
| TC-03 | 注释已同步更新为"橙色" | PASS | 代码审查（第 300 行、第 319 行注释均已更新） |
| TC-04 | 编译通过 | PASS | `make build` 成功（仅 1 个历史 warning） |

## 3. 实现详情

**修改文件**: `FloatingBallView.swift`

| 修改点 | 修改前 | 修改后 |
|--------|--------|--------|
| 正常态渐变浅色（位置 0.0） | `(0.35, 0.65, 1.0)` 浅蓝 | `(1.0, 0.65, 0.3)` 浅橙 |
| 正常态渐变中色（位置 0.5） | `(0.15, 0.45, 0.85)` 中蓝 | `(0.9, 0.45, 0.1)` 中橙 |
| 正常态渐变深色（位置 1.0） | `(0.05, 0.2, 0.55)` 深蓝 | `(0.6, 0.25, 0.05)` 深橙 |
| 注释（第 300 行） | "正常蓝色版本的品牌 Logo" | "正常橙色版本的品牌 Logo" |
| 注释（第 319 行） | "正常=蓝色渐变" | "正常=橙色渐变" |

## 4. 已知问题

| 级别 | 描述 | 影响 |
|------|------|------|
| 备注 | Dock 图标（AppDelegate.swift）仍为蓝色渐变 | 不在本次需求范围，如需统一可后续调整 |

## 5. 交付物清单

| 文件 | 修改内容 |
|------|----------|
| `FloatingBallView.swift` | 正常态渐变色蓝→橙 + 注释更新 |
