# 性能微优化 Round 2 — QA 报告

## 概览

| # | 优化项 | 文件 | 结果 |
|---|--------|------|------|
| 1 | titleCache pruneCache | WindowService.swift + AppMonitor.swift | PASS |
| 2 | PermissionManager 权限授予后停止轮询 | PermissionManager.swift | PASS (附 P2 备注) |
| 3 | 悬浮球拖拽联动节流 (16ms) | FloatingBallView.swift | **P1 已修复** |
| 4 | 呼吸动画后台暂停 | FloatingBallView.swift | **P1 已修复** |
| 5 | ConfigStore 单字段保存 | ConfigStore.swift + 调用者 | PASS |
| 6 | AppConfigView NSWorkspace 缓存 | AppConfigView.swift | PASS |
| 7 | PreferencesView Slider 防抖 | PreferencesView.swift | PASS (无需改动) |

---

## 详细检查

### 1. titleCache pruneCache — PASS

**文件**: `WindowService.swift:97-100`, `AppMonitor.swift:209-211`

- **功能正确性**: pruneCache 通过 `filter { activeIDs.contains($0.key) }` 保留当前活跃窗口的缓存，正确清理已关闭窗口条目
- **调用链**: AppMonitor.refreshAllWindows() → Phase 1 完成后 → pruneCache → 发通知
- **时序**: 在 Phase 1 结构更新后、通知发出前调用，顺序正确
- **线程安全**: refreshAllWindows 在 main queue 的 DispatchSourceTimer 中触发，titleCache 仅在主线程读写（pruneCache/buildWindowInfo/applyAXTitles 均在主线程），安全
- **Phase 2 兼容**: AX 回调通过 `DispatchQueue.main.async` 回主线程执行 applyAXTitles，不存在竞态

### 2. PermissionManager 权限授予后停止轮询 — PASS (P2 备注)

**文件**: `PermissionManager.swift:67-91`

- **功能正确性**: 权限授予后调用 stopBackgroundCheck() 停止 3 秒轮询，逻辑正确
- **资源清理**: deinit 中同时调用 stopPolling() 和 stopBackgroundCheck()，Timer 正确 invalidate + 置 nil
- **P2 备注**: 停止轮询后，如果权限又被撤销（用户在系统设置中手动移除，或 codesign --force），后台检测不会自动发现。但以下兜底路径仍可检测：
  - `AppMonitor.startWindowRefresh()` 每次面板显示时调用 `checkAccessibility()`
  - `WindowService.buildAXTitleMap()` 每次直接调用 `AXIsProcessTrusted()` 实时检测
  - 实际场景中 codesign --force 会导致 CDHash 变化，一般需要重启应用
- **结论**: 降级后的检测路径足够，暂不需要修复

### 3. 悬浮球拖拽联动节流 — P1 已修复

**文件**: `FloatingBallView.swift:600-611`

**缺陷**: 16ms 节流导致 mouseUp 时最后一帧 delta 可能被丢弃，面板位置与悬浮球存在几像素偏移。

**修复**: 在 mouseUp 中（snapToEdge 之前），检查是否有未发送的 delta，补发最后一次 `ballDragMoved` 通知。

**修复位置**: `FloatingBallView.swift:614-632`

### 4. 呼吸动画后台暂停 — P1 已修复

**文件**: `FloatingBallView.swift:249-270`

**缺陷**: 原实现使用 `NSApplication.didResignActiveNotification / didBecomeActiveNotification` 控制动画暂停/恢复。但本 App 的悬浮球窗口是 `nonactivatingPanel`，用户点击其他 App 后本 App 会 resign active，而 hover/点击悬浮球不会触发 becomeActive（因为窗口是 nonactivating 的），导致呼吸动画永久停止。

**修复**: 改用 `NSWindow.didChangeOcclusionStateNotification` 监听悬浮球窗口的遮挡状态：
- 窗口可见（`occlusionState.contains(.visible)`）→ 恢复动画
- 窗口完全被遮挡 → 暂停动画

这样无论 App 是否处于 active 状态，只要悬浮球窗口可见就保持动画，被完全遮挡时才暂停。

### 5. ConfigStore 单字段保存 — PASS

**文件**: `ConfigStore.swift:215-236`

- **新增方法**: saveBallPosition(), savePanelSize(), saveWindowRenames() — 仅序列化对应字段写入 UserDefaults
- **调用点验证**:
  - `FloatingBallView.savePosition()` → `saveBallPosition()` ✓
  - `QuickPanelWindow.mouseUp()` → `savePanelSize()` ✓
  - `QuickPanelView.handleRenameWindow()` → `saveWindowRenames()` ✓
  - `QuickPanelView.handleClearRename()` → `saveWindowRenames()` ✓
  - `saveLastPanelTab()` 已独立实现单字段保存 ✓
- **全量 save() 保留场景**: addApp/removeApp/reorderApps（涉及多字段）、PreferencesView.onDisappear（多偏好项变更），合理

### 6. AppConfigView NSWorkspace 缓存 — PASS

**文件**: `AppConfigView.swift:139-146`

- **缓存范围**: `filteredApps` 计算属性内，`workspaceRunningApps` 和 `installedByID` 字典在单次调用中缓存
- **三个 Tab 覆盖**:
  - `.all` Tab: 使用 `workspaceRunningApps` + `installedByID` ✓
  - `.running` Tab: 使用 `workspaceRunningApps` + `installedByID` ✓
  - `.favorites` Tab: 使用 `runningIDs` + `installedByID` ✓
- **Tab 数量计算**: `allCount` 和 `runningCount` 仍各自调用 `NSWorkspace.shared.runningApplications`（与 `filteredApps` 不同作用域），属于 P2 级别优化空间，当前不影响正确性

### 7. PreferencesView Slider 防抖 — PASS (无需改动)

**文件**: `PreferencesView.swift`

- **现状**: Slider 直接绑定 `$configStore.preferences.*`，值变更仅影响内存中的 @Published 属性
- **持久化时机**: `onDisappear` 统一调用 `configStore.save()`，只写一次磁盘
- **结论**: 滑动过程中不触发 UserDefaults 写入，无需额外防抖。SwiftUI 的绑定更新是内存操作，开销可忽略

---

## 修复汇总

| 级别 | 缺陷 | 修复 |
|------|------|------|
| P1 | 拖拽节流丢失末帧 delta | mouseUp 中补发最后一次 ballDragMoved 通知 |
| P1 | 呼吸动画 resign/becomeActive 对 nonactivating 窗口无效 | 改用 NSWindow.didChangeOcclusionStateNotification |
| P2 | PermissionManager 停止轮询后无法检测权限撤销 | 现有兜底路径可覆盖，暂不修复 |
| P2 | AppConfigView Tab 数量计算未用缓存 | 非性能瓶颈，暂不修复 |
