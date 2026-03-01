# Focus Copilot V2.1 增量架构文档

## 概述

V2.1 是 M 规模的增量修改，包含 4 项需求：快捷键精简、主界面退出按钮拆分、快捷面板激活优化、折叠功能验证。不引入新文件或新抽象层，所有修改在现有模块内完成。

---

## 1. 模块划分与职责

### 1.1 受影响模块

| 模块 | 文件 | 修改内容 | 涉及需求 |
|------|------|----------|----------|
| HotkeyManager | `Services/HotkeyManager.swift` | 删除 `unpinAll` 枚举值和对应快捷键注册 | 需求1 |
| AppDelegate | `App/AppDelegate.swift` | 删除 `setupHotkeys()` 中 `.unpinAll` 分支 | 需求1 |
| PreferencesView | `MainKanban/PreferencesView.swift` | 删除 "Unpin 全部" 快捷键行 | 需求1 |
| Models | `Models/Models.swift` | 删除 `Preferences.hotkeyUnpinAll` 属性 | 需求1 |
| MainKanbanView | `MainKanban/MainKanbanView.swift` | 底部退出按钮拆分为左右双按钮 | 需求2 |
| QuickPanelView | `QuickPanel/QuickPanelView.swift` | App 行单窗口点击增强 | 需求3a |
| WindowService | `Services/WindowService.swift` | `activateWindow()` 增强跨 App 激活可靠性 | 需求3b/3c |
| QuickPanelView | `QuickPanel/QuickPanelView.swift` | 折叠逻辑验证与修复（如有问题） | 需求4 |

### 1.2 不受影响模块

- FloatingBallView/FloatingBallWindow（无变更）
- QuickPanelWindow（无变更）
- ConfigStore（仅 Preferences 结构体变更，序列化自动兼容）
- PinManager / AppMonitor / TileEngine / PermissionManager（无变更）

---

## 2. 接口契约

### 2.1 需求1：快捷键精简

**HotkeyManager.swift 变更**

```swift
// 删除前
enum HotkeyAction: Int, CaseIterable {
    case pinToggle = 1    // ⌘⇧P
    case unpinAll = 3     // ⌘⇧U  ← 删除
    case ballToggle = 6   // ⌘⇧B
}

// 删除后
enum HotkeyAction: Int, CaseIterable {
    case pinToggle = 1    // ⌘⇧P
    case ballToggle = 6   // ⌘⇧B
}
```

- `registerAll()` 中删除 `⌘⇧U` 的 `registerHotKey` 调用（第49-50行）
- rawValue 保持不变（1 和 6），确保已注册的事件 ID 不冲突

**AppDelegate.swift 变更**

```swift
// setupHotkeys() 的 onAction 回调中删除 .unpinAll 分支
case .unpinAll:
    PinManager.shared.unpinAll()  // ← 整个 case 删除
```

**Models.swift 变更**

```swift
// Preferences 中删除
var hotkeyUnpinAll: String = "⌘⇧U"  // ← 删除
```

- `Preferences` 是 `Codable`，删除字段后旧数据反序列化时会自动忽略多余字段，无需迁移

**PreferencesView.swift 变更**

```swift
// hotkeySection 中删除
hotkeyRow(label: "Unpin 全部", value: $configStore.preferences.hotkeyUnpinAll)  // ← 删除
```

### 2.2 需求2：主界面底部按钮拆分

**MainKanbanView.swift 变更**

当前底部结构：
```
┌──────────────────────────┐
│  ⏻ 退出 Focus Copilot    │
└──────────────────────────┘
```

改为双按钮结构（视觉上一个整体，功能区分）：
```
┌────────────┬─────────────┐
│ 👁 显示/隐藏 │  ⏻ 退出     │
└────────────┴─────────────┘
```

**接口设计**

```swift
// 底部 safeAreaInset 内容替换
HStack(spacing: 0) {
    // 左半：悬浮球显隐切换
    Button(action: { toggleBallVisibility() }) {
        HStack(spacing: 4) {
            Image(systemName: isBallVisible ? "eye" : "eye.slash")
            Text(isBallVisible ? "隐藏" : "显示")
        }
    }

    Divider().frame(height: 16)

    // 右半：退出
    Button(action: { showQuitConfirmation = true }) {
        HStack(spacing: 4) {
            Image(systemName: "power")
            Text("退出")
        }
        .foregroundStyle(.red)
    }
}
```

**悬浮球可见性状态获取**

- 通过 `NotificationCenter` 监听 `FloatingBall.toggleBall` 通知后的状态变化
- 新增 `@State private var isBallVisible: Bool = true`
- 切换操作：发送 `FloatingBall.toggleBall` 通知，由 `AppDelegate.toggleFloatingBall()` 处理
- 状态同步：监听悬浮球窗口的 `orderOut`/`orderFront`，或直接检查 `FloatingBallWindow.isVisible`
- 注意：需要一个方式在 SwiftUI View 中获取悬浮球可见性。方案：在 AppDelegate 中通过通知广播可见性状态，或在 ConfigStore 添加一个 `@Published var isBallVisible: Bool` 运行时属性（不持久化）

**推荐方案**：在 `ConfigStore` 中添加 `@Published var isBallVisible: Bool = true`（不参与 Codable 持久化）。`AppDelegate.toggleFloatingBall()` 中同步更新此属性。MainKanbanView 通过 `@ObservedObject configStore` 读取。

### 2.3 需求3：快捷面板激活优化

#### 3a 整行点击

**现状分析**

当前代码中窗口行的点击已通过 `HoverableRowView.clickHandler` + `mouseUp()` 实现整行可点击（`QuickPanelView.swift:619-631`）。`mouseUp()` 检查点击位置是否在 NSButton 上，非按钮区域触发 `clickHandler`（`QuickPanelView.swift:967-979`）。

但 App 行（单窗口 App）使用的是 `NSClickGestureRecognizer`（`QuickPanelView.swift:463`），这可能被 Pin 按钮区域拦截。

**修改方案**

对单窗口 App 行，改用与窗口行相同的 `clickHandler` 模式替代 `NSClickGestureRecognizer`，确保点击行任意位置都能激活窗口。同样对多窗口 App 行也改用 `clickHandler` 处理折叠/展开。

```swift
// 单窗口 App 行：从 NSClickGestureRecognizer 改为 clickHandler
row.clickHandler = { [weak self] in
    // 激活窗口逻辑（同现有 handleAppClick）
}

// 多窗口 App 行：从 NSClickGestureRecognizer 改为 clickHandler
row.clickHandler = { [weak self] in
    // 折叠/展开逻辑（同现有 handleAppToggleCollapse）
}
```

#### 3b 激活可靠性增强

**现状**

`WindowService.activateWindow()` 当前流程：
1. `app.unhide()`（如果隐藏）
2. `app.activate()`
3. `raiseWindowViaAX(window)`
4. 150ms 后再次 `raiseWindowViaAX()` + `app.activate()`

**问题**：面板窗口（`QuickPanelWindow`）是 `level = statusWindow+50` 的浮动面板，且 `canBecomeKey = false`。虽然面板不抢焦点，但在某些跨 App 场景（如从 Cursor 切换到 Claude Code）中，系统可能因为面板是 `nonactivatingPanel` 而延迟处理 App 切换。

**增强方案**

```swift
func activateWindow(_ window: WindowInfo) {
    guard let app = NSRunningApplication(processIdentifier: window.ownerPID) else { return }

    // 1. 取消隐藏
    if app.isHidden { app.unhide() }

    // 2. 首次激活 + AXRaise
    app.activate()
    raiseWindowViaAX(window)

    // 3. 延迟 150ms 重试（等待系统完成 App 切换）
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
        self?.raiseWindowViaAX(window)
        app.activate()
    }

    // 4. 新增：延迟 300ms 二次重试（跨 App 场景兜底）
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
        // 检查目标 App 是否已成为活跃 App，未成功则再试一次
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != window.ownerPID {
            self?.debugLog("activateWindow: 300ms 兜底重试 wid=\(window.id)")
            app.activate()
            self?.raiseWindowViaAX(window)
        }
    }
}
```

#### 3c 跨 App 切换

跨 App 切换的核心问题在于 `app.activate()` 在某些场景下不立即生效。增强方案（3b）的 300ms 兜底重试 + `frontmostApplication` 检测可覆盖此场景。

无需额外修改面板窗口（`canBecomeKey = false` + `nonactivatingPanel` 已确保面板不抢焦点）。

### 2.4 需求4：折叠功能验证

**现状分析**

折叠逻辑位于 `QuickPanelView.swift`：

- `collapsedApps: Set<String>`（第81行）— 按 bundleID 跟踪折叠状态
- `handleAppToggleCollapse()`（第792-803行）— 点击多窗口 App 行切换折叠
- `buildNormalMode()`（第372-373行）— 根据折叠状态决定是否显示窗口列表

**关键逻辑**（第372-373行）：
```swift
if let app = running, !app.windows.isEmpty,
   !(app.windows.count > 1 && collapsedApps.contains(config.bundleID)) {
```

此逻辑含义：如果 App 有窗口，且**不是**（多窗口 + 已折叠），则显示窗口列表。

**潜在问题**

1. 折叠状态在 `reloadData()` 时不会被清空（`collapsedApps` 是实例变量），这是正确行为
2. 当多窗口 App 关闭窗口变为单窗口时，折叠状态仍在 `collapsedApps` 中但不影响显示（因为 `count > 1` 条件不满足），这是正确行为
3. `handleAppToggleCollapse` 在切换折叠后调用了 `WindowService.shared.activateApp(bundleID)`（第801行），并调用 `reloadData()`（第802行），这会正确刷新界面

**验证用例**需确认：
- 多窗口 App 点击折叠后窗口列表消失，chevron 从 `chevron.down` 变为 `chevron.right`
- 再次点击展开后窗口列表恢复显示
- 折叠状态在面板数据刷新（如窗口变化通知）后保持

---

## 3. 行为约束

### 3.1 状态转换

| 场景 | 输入 | 预期行为 |
|------|------|----------|
| 按下 ⌘⇧U | 键盘事件 | 无响应（快捷键已移除） |
| 按下 ⌘⇧P | 键盘事件 | Pin/Unpin 当前窗口（不变） |
| 按下 ⌘⇧B | 键盘事件 | 悬浮球显隐切换（不变） |
| 点击底部"隐藏"按钮 | 悬浮球可见时 | 悬浮球隐藏，按钮图标变为 `eye.slash`，文字变为"显示" |
| 点击底部"显示"按钮 | 悬浮球隐藏时 | 悬浮球显示，按钮图标变为 `eye`，文字变为"隐藏" |
| 点击底部"退出"按钮 | 任意状态 | 弹出确认对话框（保持现有逻辑） |
| 点击窗口行任意位置 | 非 Pin 按钮区域 | 激活目标窗口 |
| 点击单窗口 App 行任意位置 | App 正在运行 | 激活该 App 的窗口 |
| 跨 App 激活窗口 | 从 App A 切到 App B | 300ms 内目标 App 应成为 frontmost |
| 多窗口 App 折叠 | App 有 2+ 窗口 | 窗口列表隐藏，chevron 变为 right |

### 3.2 边界行为

- **Preferences 向后兼容**：`hotkeyUnpinAll` 字段删除后，旧 UserDefaults 数据反序列化时自动忽略多余 key，不会崩溃
- **悬浮球可见性初始状态**：`isBallVisible` 默认为 `true`（与 App 启动时悬浮球默认显示一致）
- **激活超时**：300ms 兜底重试后不再继续重试，避免无限循环（某些系统级权限窗口可能阻止激活）

---

## 4. 验收用例

### TC-01：快捷键 ⌘⇧U 已移除
- **前置条件**：App 运行中，有已 Pin 的窗口
- **操作**：按下 ⌘⇧U
- **预期**：无任何响应，已 Pin 的窗口保持 Pin 状态

### TC-02：偏好设置不显示 Unpin All 快捷键
- **前置条件**：打开主看板 → 偏好设置页
- **操作**：查看快捷键配置区域
- **预期**：仅显示 2 行快捷键（Pin/Unpin 当前窗口 ⌘⇧P、悬浮球显隐 ⌘⇧B），无 "Unpin 全部" 行

### TC-03：底部按钮拆分 - 悬浮球显隐
- **前置条件**：打开主看板，悬浮球当前可见
- **操作**：点击底部左侧按钮
- **预期**：悬浮球隐藏，按钮图标变为 `eye.slash`，文字显示"显示"
- **操作**：再次点击
- **预期**：悬浮球显示，按钮图标变为 `eye`，文字显示"隐藏"

### TC-04：底部按钮拆分 - 退出功能
- **前置条件**：打开主看板
- **操作**：点击底部右侧"退出"按钮
- **预期**：弹出确认对话框 "是否确认退出 Focus Copilot？"，点击取消不退出，点击退出则退出

### TC-05：窗口行整行可点击
- **前置条件**：快捷面板显示，有 App 运行并显示窗口行
- **操作**：点击窗口行标题文字区域（非 Pin 按钮）
- **预期**：目标窗口被激活并前置

### TC-06：单窗口 App 行整行可点击
- **前置条件**：快捷面板显示，有单窗口 App 正在运行
- **操作**：点击 App 行名称文字区域
- **预期**：该 App 的窗口被激活并前置

### TC-07：跨 App 窗口激活
- **前置条件**：Cursor 和微信同时运行，Cursor 当前在前台
- **操作**：在快捷面板中点击微信的窗口行
- **预期**：微信窗口在 300ms 内激活并前置，微信成为 frontmost 应用

### TC-08：多窗口 App 折叠/展开
- **前置条件**：快捷面板显示，某 App 有 2 个以上窗口
- **操作**：
  1. 点击该 App 行 → 窗口列表折叠，chevron 变为 `chevron.right`
  2. 再次点击该 App 行 → 窗口列表展开，chevron 变为 `chevron.down`
  3. 等待窗口刷新通知触发 `reloadData()`
- **预期**：折叠/展开状态在刷新后保持不变

---

## 5. 非目标声明

以下内容**不在** V2.1 范围内：

- 不支持自定义快捷键（快捷键仍为只读显示）
- 不修改 Pin 的核心行为（纯视觉标记模式不变）
- 不引入新文件或新类
- 不修改悬浮球外观或动画
- 不修改面板窗口层级或 resize 行为
- 不修改 ConfigStore 持久化逻辑（除删除 `hotkeyUnpinAll` 字段外）
- 不增加 `PinManager.unpinAll()` 的其他调用入口（菜单栏、右键菜单中如有需要可保留，但不在本次范围）
- 不优化内存/CPU 性能

---

## 6. 影响分析

### 6.1 现有模块修改

| 文件 | 修改量 | 风险等级 | 说明 |
|------|--------|----------|------|
| `HotkeyManager.swift` | ~5行删除 | 低 | 删除枚举值和注册调用 |
| `AppDelegate.swift` | ~2行删除 | 低 | 删除 switch case |
| `Models.swift` | ~1行删除 | 低 | 删除属性，Codable 自动兼容 |
| `PreferencesView.swift` | ~1行删除 | 低 | 删除 UI 行 |
| `MainKanbanView.swift` | ~25行修改 | 中 | 底部区域重新布局 + 新增状态 |
| `ConfigStore.swift` | ~3行新增 | 低 | 新增 `isBallVisible` 运行时属性 |
| `WindowService.swift` | ~10行新增 | 中 | 激活逻辑增强，延迟重试 |
| `QuickPanelView.swift` | ~15行修改 | 中 | App 行点击改用 clickHandler |

### 6.2 回归风险

| 风险项 | 影响范围 | 缓解措施 |
|--------|----------|----------|
| 删除 `hotkeyUnpinAll` 导致旧配置反序列化失败 | 偏好设置加载 | `Codable` 的 `init(from:)` 默认忽略未知字段；删除的字段有默认值不影响 |
| `ConfigStore.isBallVisible` 与实际悬浮球状态不同步 | 底部按钮显示错误 | 在 `toggleFloatingBall()` 中同步更新 |
| 激活增强的 300ms 重试导致 UI 闪烁 | 快捷面板行为 | 重试前检查 `frontmostApplication`，已成功则跳过 |
| App 行改用 clickHandler 后手势冲突 | 快捷面板点击 | 删除旧的 `NSClickGestureRecognizer`，使用与窗口行相同的 `mouseUp` 模式 |
| 折叠状态在 App 进程重启后丢失 | 面板折叠 | `collapsedApps` 是运行时状态，不持久化，符合预期 |

### 6.3 编译检查

删除 `HotkeyAction.unpinAll` 后，以下位置会产生编译错误（需同步删除）：
1. `AppDelegate.swift:167` — `case .unpinAll: PinManager.shared.unpinAll()`
2. `HotkeyManager.swift:49-50` — `registerHotKey(id: HotkeyAction.unpinAll.rawValue, ...)`

删除 `Preferences.hotkeyUnpinAll` 后：
1. `PreferencesView.swift:33` — `hotkeyRow(label: "Unpin 全部", value: $configStore.preferences.hotkeyUnpinAll)`

这些都是编译期即可发现的错误，风险极低。
