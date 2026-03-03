# 静态性能分析报告

> 分析时间：2026-03-03
> 分析范围：PinTop/PinTop 下全部 17 个 Swift 源文件（5546 行）

## 代码规模

| 文件 | 行数 | 备注 |
|------|------|------|
| QuickPanelView.swift | 1125 | 最大文件，快捷面板内容视图 |
| FloatingBallView.swift | 842 | 悬浮球视图（含品牌 Logo 绘制） |
| WindowService.swift | 741 | 窗口操作底层服务（AX/CGS API） |
| QuickPanelWindow.swift | 497 | 快捷面板窗口（含 resize/drag） |
| AppDelegate.swift | 418 | 应用生命周期管理 |
| Models.swift | 326 | 数据模型定义 |
| AppMonitor.swift | 314 | App 运行状态监控 |
| AppConfigView.swift | 300 | 收藏管理页面 |
| ConfigStore.swift | 237 | 配置持久化 |
| PreferencesView.swift | 192 | 偏好设置页面 |
| MainKanbanView.swift | 123 | 主看板根视图 |
| FloatingBallWindow.swift | 98 | 悬浮球窗口 |
| PermissionManager.swift | 92 | 辅助功能权限管理 |
| HotkeyManager.swift | 88 | 全局快捷键 |
| Constants.swift | 84 | 常量定义 |
| MainKanbanWindow.swift | 53 | 主看板窗口 |
| PinTopApp.swift | 16 | 应用入口 |
| **合计** | **5546** | |

## 性能问题清单

| # | 严重度 | 类别 | 文件:行号 | 描述 | 影响 | 优化建议 |
|---|--------|------|-----------|------|------|----------|
| 1 | **High** | 主线程阻塞 | AppMonitor.swift:160 | `refreshRunningApps()` 对每个运行中 App 同步调用 `WindowService.listWindows(for: pid)`，该方法内部会同步调用 AX API（`buildAXTitleMap`），阻塞主线程 | App 启动/退出时主线程阻塞 50-200ms（取决于运行 App 数量），期间 UI 无响应 | 仅在 `refreshRunningApps` 中获取 CG 数据，AX 标题走 `buildAXTitleMapAsync` 异步路径，与 `refreshAllWindows` 统一 |
| 2 | **High** | 算法复杂度 | AppMonitor.swift:196-198 | `refreshAllWindows()` 热循环中对每个 App 调用 `NSRunningApplication.runningApplications(withBundleIdentifier:)` 系统 API 检查运行状态 | 每 1-3 秒触发一次，N 个 App 就有 N 次系统调用。已有 `app.nsApp` 引用，此调用完全冗余 | 直接使用 `app.nsApp?.isTerminated == false` 判断运行状态，避免 N 次系统 API 调用 |
| 3 | **High** | 主线程阻塞 | AppMonitor.swift:268-296 | `scanInstalledApps()` 同步遍历 `/Applications` 目录，逐个读取 Bundle 信息和图标 | 启动时阻塞主线程 100-500ms（取决于 App 数量）。`/Applications` 下通常有 50-200 个 App | 移至后台线程执行，完成后 `DispatchQueue.main.async` 回写 `installedApps` |
| 4 | **High** | 通知风暴 | AppMonitor.swift:213+254 | `refreshAllWindows()` 每个周期发送两次 `windowsChanged` 通知（Phase 1 CG 阶段 + Phase 2 AX 回调），每次触发 `QuickPanelView.reloadData()` 全量重建检查 | 1-3 秒周期内连续两次 UI 重建检查，Phase 2 AX 回调时间不确定可能导致短时间内多次重建 | Phase 2 仅在 `applyAXTitles` 返回 `true`（标题有变化）时发送通知（当前已有此判断但通知仍会连续到达），考虑合并去抖 |
| 5 | **Medium** | 算法复杂度 | QuickPanelView.swift:408+510 | 收藏 Tab 中 `buildStructuralKey()` 和 `buildFavoritesTabContent()` 均对每个 config 执行 `runningApps.first(where:)` 线性查找 | O(N*M) 复杂度，N=收藏数（最多 8），M=运行 App 数（通常 10-30）。每 1-3 秒执行 | 预构建 `[bundleID: RunningApp]` 字典，将查找降为 O(1) |
| 6 | **Medium** | 内存/视图 | QuickPanelView.swift:380+457 | 面板全量重建时销毁并重建所有 `NSView`（无视图回收），每个 App 行含 8 个子视图，每个窗口行含 6 个子视图 | 8 个 App * 10 个窗口 = 约 128 个 NSView 创建/销毁，产生内存分配压力和 Auto Layout 重算 | 考虑视图复用池或增量更新（仅插入/删除变化的行） |
| 7 | **Medium** | 内存泄漏 | PreferencesView.swift:229-248 | `HotkeyRecorderButton` 的 NSEvent 本地监听器在录制模式下如果视图被销毁（如用户切换 Tab），监听器永远不会被移除 | 每次泄漏一个 NSEvent 监听器 + 闭包捕获的引用。低频但累积 | 在 `.onDisappear` 中检查并移除监听器，或使用 `@State` 持有监听器引用并在视图销毁时清理 |
| 8 | **Medium** | 字符串分配 | QuickPanelView.swift:393-418 | `buildStructuralKey()` 在循环中大量字符串拼接：`map`+`joined`+`append`，每 1-3 秒调用 | 每次生成数十个中间 String 对象，对 ARC 和堆分配造成频繁压力 | 改用固定大小哈希（如累加窗口 ID 的 hashValue）替代字符串拼接 |
| 9 | **Medium** | 冗余系统调用 | AppConfigView.swift:103-117 | `allCount` 和 `runningCount` 两个计算属性分别独立调用 `NSWorkspace.shared.runningApplications`，视图渲染时被多次求值 | SwiftUI body 每次渲染调用两次系统 API 获取相同数据 | 提取为单一缓存变量，在 body 开始时计算一次 |
| 10 | **Medium** | 主线程 I/O | ConfigStore.swift:61-79 | `save()` 方法同步执行 7 次 JSON 编码 + 7 次 UserDefaults 写入 | 每次 save 约 7 次序列化操作，从 `addApp`/`removeApp` 等路径调用时阻塞主线程 | 使用节流（throttle）合并连续保存，或移至后台队列 |
| 11 | **Low** | 动画效率 | FloatingBallView.swift:500-511 | hover 时创建两个独立的 `NSAnimationContext.runAnimationGroup`（视图缩放 + 图标缩放），可合并为一个 | 微小开销，两个动画上下文对象 | 合并为单个 `runAnimationGroup` |
| 12 | **Low** | 缓存增长 | QuickPanelView.swift:986 | 静态 `symbolCache: [String: NSImage]` 只增不减 | SF Symbol 种类有限（约 10 个 key），实际增长极小 | 无需优化，当前设计合理 |
| 13 | **Low** | 冗余对象 | FloatingBallView.swift:317-437 | `createBrandLogo` 每次调用创建 5 个 NSImage 对象（主图、着色图钉、投影图钉、投影文字等），均使用 `lockFocus`/`unlockFocus` | 仅在颜色切换时调用，频率极低 | 可缓存 Logo 图片，颜色未变化时复用 |
| 14 | **Low** | Timer 开销 | PermissionManager.swift:69 | `backgroundCheckTimer` 每 3 秒调用 `AXIsProcessTrusted()`，权限未授予时持续运行 | `AXIsProcessTrusted()` 是轻量系统调用，开销可忽略 | 可改为指数退避（3s → 5s → 10s） |
| 15 | **Low** | 重复通知 | AppMonitor.swift:64 + PermissionManager.swift:79 | `accessibilityGranted` 通知在 PermissionManager 中触发后，AppMonitor 收到通知调用 `refreshRunningApps()`，同时 PermissionManager.startBackgroundCheck 也调用 `AppMonitor.shared.refreshRunningApps()` | 权限恢复时 `refreshRunningApps` 可能被调用两次 | 统一入口：PermissionManager 只发通知，不直接调用 AppMonitor |

## 资源管理审计

| 资源类型 | 创建位置 | 清理位置 | 状态 |
|----------|----------|----------|------|
| Timer (hoverTimer) | FloatingBallView.swift:515 | deinit:104, mouseExited:522, mouseDown:568 等多处 | **正常** |
| NSTrackingArea (FloatingBallView) | FloatingBallView.swift:222-229 | deinit:105-108, updateTrackingArea:219 | **正常** |
| NSTrackingArea (QuickPanelView) | QuickPanelView.swift:235-242 | deinit:138-139 | **正常** |
| NSTrackingArea (HoverableRowView) | QuickPanelView.swift:1072-1079 | deinit:1057-1061 | **正常** |
| Timer (dismissTimer) | QuickPanelWindow.swift:241 | deinit:63, hide:199, show:163 等 | **正常** |
| DispatchSourceTimer (windowRefreshTimer) | AppMonitor.swift:128-134 | stopWindowRefresh:103-108 | **正常** |
| Timer (pollTimer) | PermissionManager.swift:42 | deinit:19, stopPolling:59-61 | **正常** |
| Timer (backgroundCheckTimer) | PermissionManager.swift:69 | deinit:20, stopBackgroundCheck:88-90 | **正常** |
| NotificationCenter observers (AppDelegate) | AppDelegate.swift:88-117 | applicationWillTerminate:71 | **正常** |
| NotificationCenter observers (FloatingBallView) | FloatingBallView.swift:234-257 | deinit:108 | **正常** |
| NotificationCenter observers (QuickPanelView) | QuickPanelView.swift:265-293 | deinit:141 | **正常** |
| NotificationCenter observers (QuickPanelWindow) | QuickPanelWindow.swift:116-131 | deinit:64 | **正常** |
| NotificationCenter observers (AppMonitor) | AppMonitor.swift:43-65 | stopMonitoring:73-87 | **正常** |
| EventHotKeyRef (HotkeyManager) | HotkeyManager.swift:83 | unregisterAll:58-70 | **正常** |
| EventHandlerRef (HotkeyManager) | HotkeyManager.swift:42 | unregisterAll:66-69 | **正常** |
| FileHandle (logFileHandle) | WindowService.swift:41 | 无显式关闭 | **注意**：单例生命周期与进程一致，OS 在进程退出时回收，不会泄漏但不够严谨 |
| Combine AnyCancellable (preferencesObserver) | AppDelegate.swift:230-234 | ARC 自动管理 | **正常** |
| NSEvent local monitor (HotkeyRecorderButton) | PreferencesView.swift:230 | 闭包内 removeMonitor:237,246 | **风险**：视图销毁时若仍在录制模式，监听器不会被移除（详见问题 #7） |
| dlopen handles (WindowService) | WindowService.swift:50-51 | 从未 dlclose | **正常**：框架句柄应保持打开 |

## 总结

- **Critical 问题数：0**
- **High 问题数：4**（主线程阻塞 x2、冗余系统调用 x1、通知风暴 x1）
- **Medium 问题数：6**（算法复杂度 x1、内存/视图 x1、内存泄漏 x1、字符串分配 x1、冗余系统调用 x1、主线程 I/O x1）
- **Low 问题数：5**（动画效率 x1、缓存增长 x1、冗余对象 x1、Timer 开销 x1、重复通知 x1）

### 整体评价

项目代码质量良好：
1. **资源管理规范**：所有 Timer、Observer、TrackingArea 均有对应的清理逻辑，未发现资源泄漏（除 HotkeyRecorderButton 的边缘情况）
2. **已有优化意识**：AppConfigView 中预构建了 `installedByID` 字典优化查找；QuickPanelView 实现了差分更新（structuralKey 比较）；AppMonitor 实现了自适应刷新间隔和 AX 异步两阶段刷新
3. **主要瓶颈集中在 AppMonitor**：`refreshRunningApps` 的同步 AX 调用和 `scanInstalledApps` 的同步文件遍历是最需要优先优化的两个点
4. **QuickPanelView 的视图重建开销**是中等优先级问题，当前差分更新策略已缓解了大部分不必要的重建
