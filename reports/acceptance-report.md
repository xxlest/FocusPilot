# Focus Copilot V2.1 验收报告

## 1. 验收用例结果

| 用例 | 需求 | 结果 | 验证方式 | 备注 |
|------|------|------|----------|------|
| TC-01 | ⌘⇧U 快捷键已移除 | PASS | 代码审查 | HotkeyManager/AppDelegate 中无 unpinAll 引用 |
| TC-02 | 偏好设置无 Unpin All 行 | PASS | 代码审查 | PreferencesView 仅显示 2 行快捷键（⌘⇧P、⌘⇧B） |
| TC-03 | 底部按钮 - 悬浮球显隐 | PASS | 代码审查 | 左半按钮 eye/eye.slash 图标切换，通知 FloatingBall.toggleBall |
| TC-04 | 底部按钮 - 退出 | PASS | 代码审查 | 右半按钮保持原有确认对话框逻辑 |
| TC-05 | 窗口行整行可点击 | PASS | 运行时日志 | 点击文字区域成功触发 activateWindow，AXRaise 返回 0 |
| TC-06 | 单窗口 App 行整行可点击 | PASS | 运行时日志 | iTerm2/元宝/白描/闪电说 均通过 clickHandler 激活 |
| TC-07 | 跨 App 窗口激活 | PASS | 运行时日志 | 300ms 兜底重试正确触发，AXRaise 全部成功 |
| TC-08 | 多窗口 App 折叠/展开 | PASS | 运行时日志 | Cursor/Antigravity/微信 折叠/展开交替正常 |

## 2. 架构符合度

### 与 V2.1 架构文档一致性
- HotkeyManager 删除 unpinAll，仅保留 pinToggle 和 ballToggle ✅
- AppDelegate 删除 .unpinAll 处理分支 ✅
- Models.Preferences 删除 hotkeyUnpinAll 字段 ✅
- MainKanbanView 底部改为 HStack 双按钮（显隐+退出） ✅
- ConfigStore 新增 isBallVisible 运行时属性 ✅
- QuickPanelView App 行改用 clickHandler（移除 NSClickGestureRecognizer） ✅
- WindowService.activateWindow 增加 300ms 兜底重试 ✅

### 关键设计决策
- App 行和窗口行统一使用 `HoverableRowView.clickHandler` 模式，避免手势识别器与按钮冲突
- 折叠切换时强制清除 `lastWindowSnapshot` 确保即时刷新
- 悬浮球可见性通过 `ConfigStore.isBallVisible`（`@Published`）在 SwiftUI 和 AppKit 间同步

## 3. 非目标确认

- 未恢复 CGS 窗口层级控制（always-on-top）✅
- 未支持自定义快捷键 ✅
- 未修改悬浮球外观/动画 ✅
- 未引入新文件 ✅

## 4. 已知问题清单

### P2 缺陷（不阻塞）
- `app.activate()` 对部分已激活应用返回 `false`，但 AXRaise 始终成功，不影响功能
- 旧 `/Applications/PinTop.app` 仍需 `sudo rm -rf` 手动清理

### 技术债务
- AppMonitor.swift 有一个未使用返回值警告（`checkAccessibility()`）
- 辅助功能权限每次 codesign 后需重新授权（已自动化处理）

## 5. 交付物清单

### 修改的文件

| 文件 | 变更摘要 |
|------|----------|
| `PinTop/Services/HotkeyManager.swift` | 删除 unpinAll 枚举值和 ⌘⇧U 注册 |
| `PinTop/App/AppDelegate.swift` | 删除 .unpinAll 处理，toggleFloatingBall 同步 isBallVisible |
| `PinTop/Models/Models.swift` | 删除 hotkeyUnpinAll 属性 |
| `PinTop/MainKanban/PreferencesView.swift` | 删除 Unpin All 快捷键行 |
| `PinTop/MainKanban/MainKanbanView.swift` | 底部拆分为双按钮（显隐悬浮球 + 退出） |
| `PinTop/Services/ConfigStore.swift` | 新增 isBallVisible 运行时属性 |
| `PinTop/QuickPanel/QuickPanelView.swift` | App 行改用 clickHandler，删除手势识别器方法，折叠添加日志 |
| `PinTop/Services/WindowService.swift` | activateWindow 增加 300ms 兜底重试 |

### 新增文件

| 文件 | 职责 |
|------|------|
| `reports/v21-architecture.md` | V2.1 架构文档 |
