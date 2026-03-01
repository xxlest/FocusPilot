# PinTop Bug 修复验收报告

**日期**: 2026-03-01
**范围**: 全代码库缺陷扫描与修复
**规模**: M（19 文件，4226 行）

---

## 1. 缺陷检测结果

3 个 QA Agent 并行扫描 5 个模块，去重后发现 17 个 Bug：

| 级别 | 数量 | 处理 |
|------|------|------|
| P0 | 1 | 全部修复 |
| P1 | 10 | 全部修复 |
| P2 | 6 | 记录，不阻塞 |

## 2. 已修复的 Bug（P0 + P1）

### P0

| # | 标题 | 文件 | 修复方式 |
|---|------|------|----------|
| 1 | WindowService.init dlsym 强制解包可致崩溃 | WindowService.swift | cgsMainConnectionID/cgsSetWindowLevel 改为 Optional，统一 dlopen 管理，调用时 guard 降级 |

### P1

| # | 标题 | 文件 | 修复方式 |
|---|------|------|----------|
| 2 | PinManager 后 pin 窗口层级更低 | PinManager.swift | 层级公式改为 `base + pinnedCount`（后 pin 层级更高），同步修复 unpin/reorder |
| 3 | AppMonitor 未运行 App 用 NSRunningApplication.current 占位 | Models.swift, AppMonitor.swift | nsApp 改为 Optional，未运行时设 nil |
| 4 | refreshAllWindows() 中 isRunning 不触发 UI 更新 | Models.swift | isRunning 添加 @Published 属性包装器 |
| 5 | slideIn 动画状态提前设置导致竞态 | FloatingBallView.swift | isHalfHidden 移入 completionHandler |
| 6 | hide() completionHandler 强引用+竞态 | QuickPanelWindow.swift | 改用 [weak self]，添加 alphaValue==0 竞态保护 |
| 7 | mouseMoved 未生效（resize 光标不切换） | QuickPanelWindow.swift | configureWindow() 添加 acceptsMouseMovedEvents = true |
| 8 | resize 面板无最大高度限制 | QuickPanelWindow.swift | bottom/bottomRight 分支添加 maxHeight 上限（屏幕 60%） |
| 9 | @StateObject 误用于全局单例 | MainKanbanView/AppConfigView/PinManageView/PreferencesView | 全部改为 @ObservedObject |
| 10 | AppDelegate 通知观察者未移除 | AppDelegate.swift | applicationWillTerminate 添加 removeObserver(self) |
| 11 | dlopen 句柄重复打开 | WindowService.swift | 统一在 init 开头打开 cg 句柄，每个框架只 dlopen 一次 |

## 3. 未修复的 P2 缺陷（记录）

| # | 标题 | 文件 | 说明 |
|---|------|------|------|
| 12 | ConfigStore.save() 全量序列化 | ConfigStore.swift | 当前 UserDefaults 有缓存，性能影响小 |
| 13 | maxWindowsPerApp 限制未使用 | QuickPanelView.swift | 功能性影响低，建议后续版本处理 |
| 14 | SMAppService 错误静默忽略 | PreferencesView.swift | 建议后续添加用户反馈 |
| 15 | 通知名称硬编码未集中管理 | 多文件 | 建议后续统一到 Constants.Notifications |
| 16 | contentStack 缺少底部约束 | QuickPanelView.swift | NSStackView fittingSize 自行计算，影响有限 |
| 17 | HotkeyManager Carbon 回调设计 | HotkeyManager.swift | 当前 singleton 模式无实际泄漏 |

## 4. 编译验证

- 编译命令: swiftc + VFS overlay（兼容 Command Line Tools 6.2.3）
- 编译结果: **通过**
- 产物: `/tmp/pintop-build/PinTop.app/Contents/MacOS/PinTop` (1.09MB)

## 5. 架构符合度

- 所有修复均在现有架构内完成，未引入新文件或新模块
- 接口变更最小化：仅 `RunningApp.nsApp` 从非可选改为可选，`isRunning` 添加 @Published
- 窗口层级语义统一为"后 pin 在上"

## 6. 交付物清单

| 文件 | 修改内容 |
|------|----------|
| Services/WindowService.swift | P0 dlsym 安全降级 + dlopen 统一管理 |
| Services/PinManager.swift | P1 层级计算修正 |
| Services/AppMonitor.swift | P1 nsApp 占位移除 |
| Models/Models.swift | P1 nsApp Optional + isRunning @Published |
| FloatingBall/FloatingBallView.swift | P1 slideIn 动画竞态修复 |
| QuickPanel/QuickPanelWindow.swift | P1 hide 竞态 + mouseMoved + resize 限高 |
| MainKanban/MainKanbanView.swift | P1 @StateObject → @ObservedObject |
| MainKanban/AppConfigView.swift | P1 @StateObject → @ObservedObject |
| MainKanban/PinManageView.swift | P1 @StateObject → @ObservedObject |
| MainKanban/PreferencesView.swift | P1 @StateObject → @ObservedObject |
| App/AppDelegate.swift | P1 通知 removeObserver |
