# V3.4 QA 验收报告

## 阶段 A：编译验证

| 项目 | 结果 |
|------|------|
| `make build` | PASS（编译成功） |
| 编译警告 | 3 个已知非严重警告（deltaX/deltaY 未使用、checkAccessibility 返回值未使用），均为既有代码 |
| 编译错误 | 无 |

## 阶段 B：集成检查

### 星号收藏功能

| 检查项 | 结果 | 说明 |
|--------|------|------|
| QuickPanelView 星号使用 ConfigStore.addApp/removeApp | PASS | `handleToggleFavorite` 方法（行 871-882）正确调用 `ConfigStore.shared.addApp/removeApp` |
| 点击星号不触发行折叠 | PASS | `HoverableRowView.mouseUp`（行 1069-1080）通过 `hitTest` 检测，命中 NSButton 时走 `super.mouseUp` 而非 clickHandler |
| 收藏状态变化后 structural key 包含收藏状态 | PASS | `buildStructuralKey`（行 357）在 running Tab 中拼入 `fav = ConfigStore.shared.isFavorite(bundleID) ? "F" : ""`，收藏变化触发全量重建 |
| 仅活跃 Tab 显示星号 | PASS | `createAppRow`（行 554-573）有 `if currentTab == .running` 条件守卫 |

### 主看板快捷键功能

| 检查项 | 结果 | 说明 |
|--------|------|------|
| Preferences.hotkeyKanban 默认值 ⌘Esc | PASS | `HotkeyConfig.kanbanDefault`（Models.swift:130）= keyCode 0x35 + cmdKeyFlag |
| 解码器兼容旧数据 | PASS | `Preferences.init(from:)`（行 228）使用 `try?` 解码 hotkeyKanban，失败时用 `.kanbanDefault` |
| HotkeyManager 事件处理器按 hotKeyID 分发 | PASS | handler 闭包（行 34-42）检查 `hotKeyID.id == hotkeyID` 和 `kanbanHotkeyID`，分别调用 `onToggle` / `onKanbanToggle` |
| AppDelegate setupHotkeys 注册两个快捷键 | PASS | `setupHotkeys`（行 176-185）调用 `register()` + `registerKanban()` |
| applyPreferences 检测主看板快捷键变化 | PASS | 行 314-317 检测 `hotkeyKanban != lastKanbanHotkey` 后调用 `reregisterKanban` |
| PreferencesView 有主看板快捷键录入 UI | PASS | hotkeySection（行 33）包含 `hotkeyRow(label: "主看板", config: $configStore.preferences.hotkeyKanban)` |

### 通用检查

| 检查项 | 结果 | 说明 |
|--------|------|------|
| 无新编译警告 | PASS | 仅有 3 个既有警告 |
| 无未使用变量/导入 | PASS | 关联对象 key（bundleIDKey, displayNameKey）均有使用 |
| 共享常量无重复定义 | PASS | Constants.maxApps 引用 Panel.maxApps |
| 事件名/通知名收发一致 | PASS | `appStatusChanged` 在 ConfigStore.addApp/removeApp 中 post，在 QuickPanelView 中 observe |

## 阶段 C：验收用例验证

| 用例 | 验证结果 | 说明 |
|------|---------|------|
| TC-01: 未收藏 App 显示空心星号，点击变填充 | PASS | `createAppRow` 根据 `isFavorite` 选择 "star"/"star.fill"，点击后 `handleToggleFavorite` 调用 addApp + 重建 |
| TC-02: 已收藏 App 显示填充星号，点击变空心 | PASS | 同上逻辑反向，调用 removeApp |
| TC-03: 点击星号不触发折叠/展开 | PASS | `mouseUp` 中 hitTest 检测到 NSButton 后直接 return，不执行 clickHandler |
| TC-04: ⌘Esc 打开/关闭主看板 | PASS | `onKanbanToggle` 回调调用 `toggleMainKanban`，该方法检查 isVisible 进行 toggle |
| TC-05: 偏好设置可录入新快捷键 | PASS | `HotkeyRecorderButton` 通过 NSEvent.addLocalMonitorForEvents 录制，结果写入 $config Binding |
| TC-06: 旧版本配置不丢失 | PASS | `hotkeyKanban` 使用 `try?` 解码，缺失时回退 `.kanbanDefault` |
| TC-07: 收藏 Tab 不显示星号 | PASS | `createAppRow` 中 `if currentTab == .running` 仅在活跃 Tab 添加星号按钮 |

## 阶段 D：探索性测试

### 快速连续点击星号
**结论：安全**。`ConfigStore.addApp` 有 `guard !appConfigs.contains(where:)` 防重复添加保护（行 166）。`removeApp` 使用 `removeAll` 幂等操作。每次点击后调用 `reloadData()` 全量重建，UI 状态与数据保持一致。

### 收藏已满（8 个）时点击星号
**结论：安全**。`ConfigStore.addApp` 有 `guard appConfigs.count < Constants.maxApps` 守卫（行 165），超限时静默忽略。但**没有用户提示**（P2 建议项，非阻塞）。

### 两个快捷键设置为相同组合
**结论：可能冲突**（P2）。Carbon `RegisterEventHotKey` 允许注册相同的键组合，但运行时只有后注册的会生效。由于 `setupHotkeys` 中先 `register()`（悬浮球）再 `registerKanban()`（主看板），相同组合时主看板快捷键会覆盖悬浮球快捷键。PreferencesView 中没有冲突检测/提示。这是 P2 级建议项，不阻塞发布。

## 缺陷清单

### P0（阻塞发布）
无

### P1（严重）
无（开发阶段已修复所有 P1）

### P2（建议改进，不阻塞）

| # | 描述 | 影响 | 建议 |
|---|------|------|------|
| B-01 | 收藏已满时点击星号无用户反馈 | 用户不知道操作被忽略 | 添加 Toast 或抖动动画提示"收藏已满" |
| B-02 | 两个快捷键可设置为相同组合 | 后注册的覆盖前者，悬浮球快捷键失效 | 录入时检测冲突并提示 |
| B-03 | 3 个编译警告未清理 | 代码整洁度 | 后续版本清理 |

## 验收结论

**PASS - 可发布**

两个核心功能（星号收藏 + 主看板快捷键）的所有关键路径验证通过，无 P0/P1 缺陷。3 个 P2 建议项可在后续版本处理。
