# 主题同步刷新修复 — 验收报告

> 日期：2026-03-05
> 版本：V3.7 补丁

---

## 1. 问题描述

偏好设置中切换主题后，快捷面板、主看板、悬浮球未同步更新。

## 2. 架构审查结果

### 审查发现的问题

| # | 问题 | 严重级别 | 说明 |
|---|------|---------|------|
| 1 | MainKanbanView 使用 `ConfigStore.shared` 而非 `@ObservedObject configStore` | P1 | 静态单例访问绕过了 SwiftUI 的响应式更新机制，导致 sidebar 背景色不跟随主题变化 |
| 2 | 主看板窗口 NSWindow.appearance 未随主题同步 | P1 | NSApp.appearance 变化不自动传播到已创建的 NSWindow，需显式设置 |
| 3 | AppConfigView 的 LazyVStack 缓存问题 | P2 | LazyVStack 中的行视图可能被缓存，主题变化后不重建 |

### 架构设计评价

- **模块化合理**：AppTheme/ThemeColors 集中定义于 Models.swift，各模块统一通过 `ConfigStore.shared.currentThemeColors` 获取
- **通知机制完整**：`themeChanged` 通知已定义，AppDelegate 中有发送逻辑
- **刷新链路设计正确**：Combine sink 监听 → applyPreferences → 各组件刷新。问题出在细节实现而非架构

## 3. 修复内容

| 文件 | 修改 | 解决问题 |
|------|------|---------|
| `AppDelegate.swift` | 主题变化时设置 `mainKanbanWindow?.appearance = NSApp.appearance` | #2 主看板窗口 appearance 同步 |
| `MainKanbanView.swift` | `ConfigStore.shared.currentThemeColors` → `configStore.currentThemeColors` | #1 SwiftUI 响应式更新 |
| `AppConfigView.swift` | 添加 `let themeKey = configStore.preferences.appTheme.rawValue` + `.id(themeKey)` | #3 强制 LazyVStack 重建 |

## 4. 验收用例

| 用例 | 描述 | 预期结果 | 结果 |
|------|------|---------|------|
| TC-01 | 切换浅色→深色主题 | NSApp.appearance 变为 darkAqua，所有 UI 变深色 | 待验证 |
| TC-02 | 悬浮球颜色同步 | 悬浮球渐变色跟随主题 accent 变化 | 待验证 |
| TC-03 | 快捷面板同步 | 面板背景色、文字色、高亮色跟随主题 | 待验证 |
| TC-04 | 主看板侧边栏同步 | 侧边栏背景色跟随主题 | 待验证 |
| TC-05 | AppConfigView 同步 | 状态点、星标色跟随主题 | 待验证 |
| TC-06 | 重启后主题持久化 | 重启 App 后主题选择保持 | 待验证 |
| TC-07 | 8 个主题全部切换 | 所有 8 个主题都能正确应用 | 待验证 |

## 5. 编译验证

- `make build` ✅ 编译通过
- `make install` ✅ 安装成功

## 6. 已知问题

- 无

## 7. 交付文件

| 文件 | 变更 |
|------|------|
| FocusPilot/App/AppDelegate.swift | +3 行（mainKanbanWindow.appearance 同步） |
| FocusPilot/MainKanban/MainKanbanView.swift | 1 行修改（使用 @ObservedObject 实例） |
| FocusPilot/MainKanban/AppConfigView.swift | +2 行（themeKey + .id 强制刷新） |
