# V3.4 验收报告

## 1. 验收用例结果

| 用例 | 结果 | 验证方式 | 备注 |
|------|------|---------|------|
| TC-01: 未收藏 App 显示空心星号，点击后变为填充 | PASS | 代码审查 | star/star.fill SF Symbol + ConfigStore.addApp |
| TC-02: 已收藏 App 显示填充星号，点击后变为空心 | PASS | 代码审查 | ConfigStore.removeApp + reloadData |
| TC-03: 星号点击不触发折叠/展开 | PASS | 代码审查 | HoverableRowView.mouseUp 已有 NSButton 命中检查 |
| TC-04: ⌘Esc 打开/关闭主看板 | PASS | 代码审查 | HotkeyManager.onKanbanToggle → toggleMainKanban |
| TC-05: 偏好设置可录入新看板快捷键 | PASS | 代码审查 | hotkeyRow(label: "主看板") 复用现有组件 |
| TC-06: 旧版本配置升级不丢失数据 | PASS | 代码审查 | decodeIfPresent + 默认值兜底 |
| TC-07: 收藏 Tab 不显示星号 | PASS | 代码审查 | `if currentTab == .running` 条件守卫 |

## 2. 架构符合度

- 星号收藏：按设计实现，使用 ObjC 关联对象传递 bundleID/displayName
- 主看板快捷键：HotkeyManager 改为支持多快捷键，使用 hotkeyID 区分
- PreferencesView 复用了现有 hotkeyRow 组件，一行代码完成
- 所有变更在现有文件内完成，未创建新文件

## 3. 非目标确认

- 未做窗口级别的右键收藏（仅 App 级别星号）
- 未做快捷键冲突检测
- 未修改收藏 Tab 的交互

## 4. 已知问题

- P2: 两个快捷键设为相同组合时行为未定义（Carbon 注册不会报错，触发时两个回调都执行）
- P2: 收藏已满（8个）时点击星号，addApp 内部 guard 静默返回，无用户提示

## 5. 交付物清单

| 文件 | 变更内容 |
|------|---------|
| PinTop/Models/Models.swift | +HotkeyConfig.kanbanDefault, +Preferences.hotkeyKanban, 默认值调整(ballSize=35, blue) |
| PinTop/QuickPanel/QuickPanelView.swift | +星号收藏按钮(createAppRow), +handleToggleFavorite, +structural key 含收藏状态 |
| PinTop/Services/HotkeyManager.swift | 多快捷键支持：+kanbanHotKeyRef, +registerKanban, +reregisterKanban |
| PinTop/App/AppDelegate.swift | +onKanbanToggle 回调, +registerKanban, +lastKanbanHotkey 变更检测 |
| PinTop/MainKanban/PreferencesView.swift | +主看板快捷键录入行 |
