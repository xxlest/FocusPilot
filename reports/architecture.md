# 增量架构设计：星号收藏 + 主看板快捷键

## 功能 1：快捷面板活跃列表星号收藏

### 模块划分

**需修改的现有模块：**

| 文件 | 修改内容 |
|------|----------|
| `QuickPanelView.swift` | 在 `createAppRow()` 中，应用名称前插入星号按钮；收藏状态变更后触发全量重建 |

**无需新增文件**，完全在 `QuickPanelView.swift` 内部完成。

### 接口契约

星号收藏功能完全复用现有 ConfigStore API，不新增接口：

- **读取收藏状态**：`ConfigStore.shared.isFavorite(bundleID)` -> Bool
- **添加收藏**：`ConfigStore.shared.addApp(bundleID, displayName: name)`
- **移除收藏**：`ConfigStore.shared.removeApp(bundleID)`

上述方法内部已调用 `save()` 和发送 `appStatusChanged` 通知，无需额外处理。

### 实现方案

在 `createAppRow()` 方法中（约 L514），在 statusDot 和 iconView 之间插入星号按钮：

```
rowStack 布局顺序：
  statusDot → [星号按钮(新增)] → iconView → nameLabel → spacer → countLabel → chevron
```

星号按钮实现要点：
1. 使用 NSButton（bezelStyle: .recessed, isBordered: false）
2. 图标：已收藏 `star.fill`（`controlAccentColor`），未收藏 `star`（`secondaryLabelColor`）
3. 使用 `cachedSymbol` 缓存 SF Symbol
4. **仅在活跃 Tab 显示星号**（收藏 Tab 不需要，因为收藏 Tab 里的 App 已经全是收藏的）
5. 按钮 target/action 处理收藏切换，action 内部调用 `ConfigStore.addApp/removeApp`
6. 收藏变更后 ConfigStore 内部已发送 `appStatusChanged` 通知 → `reloadData()` 自动触发

### 星号点击不触发行折叠的机制

当前 `HoverableRowView.mouseUp()` 中已有逻辑（L1029-1033）：如果点击命中 NSButton 子视图，走 `super.mouseUp(event)` 而非 `clickHandler`。星号按钮作为 NSButton 会自然被这段逻辑拦截，无需额外处理。

### 结构 key 影响

`buildStructuralKey()` 需要将收藏状态纳入 key，否则星号切换后不会触发全量重建。但 ConfigStore.addApp/removeApp 内部发送 `appStatusChanged` 通知，会走 `reloadData()` → `buildStructuralKey()` 重新构建。由于 addApp/removeApp 会改变 `appConfigs` 数组，而收藏 Tab 的 structuralKey 包含 `configs` 遍历结果，所以切换到收藏 Tab 时 key 自然变化。

对于活跃 Tab，structuralKey 不包含收藏状态，但因为 `appStatusChanged` 通知会触发 `reloadData()`，且 `lastStructuralKey` 在通知处理中不需要清除——因为活跃 Tab 的结构并未变化，只是星号图标状态变了。解决方案：在活跃 Tab 的 structuralKey 中追加每个 app 的收藏状态标记（`F` / `N`），确保收藏切换后触发全量重建。

修改 `buildStructuralKey()` 中活跃 Tab 分支：
```swift
// 在 parts.append 行中追加收藏标记
let fav = ConfigStore.shared.isFavorite(app.bundleID) ? "F" : "N"
parts.append("\(app.bundleID):\(app.isRunning):\(windowIDs):\(collapsed):\(fav)")
```

---

## 功能 2：主看板可自定义快捷键（默认 Command+Escape）

### 模块划分

**需修改的现有模块：**

| 文件 | 修改内容 |
|------|----------|
| `Models.swift` | Preferences 新增 `hotkeyKanban` 字段 |
| `HotkeyManager.swift` | 支持注册第二个快捷键（独立 ID + 独立回调） |
| `AppDelegate.swift` | 注册主看板快捷键回调 + 跟踪变化重注册 |
| `PreferencesView.swift` | 快捷键区域新增主看板快捷键行 |

**无需新增文件。**

### 接口契约

#### Models.swift - Preferences 新增字段

```swift
struct Preferences: Codable {
    // ... 现有字段 ...
    var hotkeyKanban: HotkeyConfig = .kanbanDefault  // 新增
}
```

```swift
struct HotkeyConfig {
    // 新增默认值常量
    static let kanbanDefault = HotkeyConfig(
        keyCode: kVK_Escape,        // 0x35
        carbonModifiers: cmdKeyFlag  // Command
    )
}
```

Preferences 解码器新增：
```swift
hotkeyKanban = (try? container.decode(HotkeyConfig.self, forKey: .hotkeyKanban)) ?? .kanbanDefault
```

#### HotkeyManager.swift - 多快捷键支持

当前 HotkeyManager 只支持单个快捷键（`hotkeyID = 1`，单个 `hotKeyRef`、单个 `onToggle` 回调）。

扩展方案：引入 slot 概念，每个 slot 有独立的 ID、EventHotKeyRef、回调。

```swift
class HotkeyManager {
    static let shared = HotkeyManager()

    // 快捷键槽位
    private struct HotkeySlot {
        var hotKeyRef: EventHotKeyRef?
        var callback: (() -> Void)?
    }

    // 槽位 ID 常量
    static let slotToggle: UInt32 = 1   // 悬浮球+面板
    static let slotKanban: UInt32 = 2   // 主看板

    private var slots: [UInt32: HotkeySlot] = [:]
    private var eventHandler: EventHandlerRef?

    // 公开接口
    /// 旧接口保留兼容（内部转发到 slot 1）
    var onToggle: (() -> Void)? {
        get { slots[Self.slotToggle]?.callback }
        set { slots[Self.slotToggle, default: HotkeySlot()].callback = newValue }
    }

    /// 主看板快捷键回调
    var onKanban: (() -> Void)? {
        get { slots[Self.slotKanban]?.callback }
        set { slots[Self.slotKanban, default: HotkeySlot()].callback = newValue }
    }

    /// 注册指定槽位的快捷键
    func register(slot: UInt32, config: HotkeyConfig)

    /// 注销指定槽位
    func unregister(slot: UInt32)

    /// 注销全部
    func unregisterAll()

    /// 重注册指定槽位
    func reregister(slot: UInt32, config: HotkeyConfig)

    /// 兼容旧接口：register() 注册 toggle 槽位
    func register(config: HotkeyConfig? = nil)
}
```

Carbon 事件处理器中通过 `hotKeyID.id` 分发到对应 slot 的 callback。事件处理器只安装一次（首次注册时），后续注册只操作 `RegisterEventHotKey`。

#### AppDelegate.swift - 注册第二个快捷键

```swift
private func setupHotkeys() {
    // 悬浮球+面板快捷键
    HotkeyManager.shared.register(slot: HotkeyManager.slotToggle,
                                   config: ConfigStore.shared.preferences.hotkeyToggle)
    HotkeyManager.shared.onToggle = { [weak self] in
        self?.toggleAllViaHotkey()
    }

    // 主看板快捷键
    HotkeyManager.shared.register(slot: HotkeyManager.slotKanban,
                                   config: ConfigStore.shared.preferences.hotkeyKanban)
    HotkeyManager.shared.onKanban = { [weak self] in
        self?.toggleMainKanban()
    }
}
```

`applyPreferences()` 中新增主看板快捷键变化检测：

```swift
private var lastHotkeyKanban: HotkeyConfig?

// 在 applyPreferences 中：
if prefs.hotkeyKanban != lastHotkeyKanban {
    lastHotkeyKanban = prefs.hotkeyKanban
    HotkeyManager.shared.reregister(slot: HotkeyManager.slotKanban, config: prefs.hotkeyKanban)
}
```

#### PreferencesView.swift - 新增快捷键行

```swift
private var hotkeySection: some View {
    VStack(alignment: .leading, spacing: 12) {
        Text("快捷键")
            .font(.headline)
        VStack(spacing: 8) {
            hotkeyRow(label: "显示/隐藏", config: $configStore.preferences.hotkeyToggle)
            hotkeyRow(label: "主看板", config: $configStore.preferences.hotkeyKanban)  // 新增
        }
    }
}
```

`HotkeyRecorderButton` 无需修改，它已经是通用的录制组件，通过 Binding 自动写入对应字段。

---

## 行为约束

### 功能 1 边界情况

1. **收藏上限**：ConfigStore.addApp 内部已有 `maxApps` 限制（8个），星号点击时如果已达上限，addApp 静默返回，星号保持空心状态——因为 `isFavorite` 仍返回 false
2. **重复点击防抖**：addApp 内部有 `guard !appConfigs.contains` 防重复，removeApp 用 `removeAll` 无副作用
3. **收藏 Tab 不显示星号**：收藏 Tab 中的 App 全部是已收藏的，星号按钮无意义（取消收藏应在收藏管理中操作），仅活跃 Tab 显示星号
4. **未运行 App 不显示星号（活跃 Tab 无此场景）**：活跃 Tab 只显示有窗口的运行中 App，不存在未运行场景

### 功能 2 边界情况

1. **两个快捷键相同**：用户可能将两个快捷键设为相同组合。系统行为：Carbon 注册两个相同快捷键时，只有后注册的生效。应在 UI 层面做提示但不阻止
2. **Command+Escape 冲突**：macOS 系统使用 Cmd+Esc 打开 Force Quit 对话框。App 注册的 Carbon 全局快捷键优先级高于系统快捷键，会拦截此组合。如果用户不希望覆盖系统行为，可自行修改
3. **旧版本配置兼容**：Preferences 解码器使用 `(try? container.decode(...)) ?? .kanbanDefault`，旧版配置文件中不含 `hotkeyKanban` 字段时自动使用默认值
4. **主看板 toggle 行为**：`toggleMainKanban()` 已存在于 AppDelegate 中，窗口可见时关闭、不可见时创建并显示，无需新增逻辑

---

## 验收用例

### 功能 1：星号收藏

| # | 场景 | 操作 | 预期结果 |
|---|------|------|----------|
| 1 | 活跃 Tab 显示星号 | 打开快捷面板，切换到活跃 Tab | 每个 App 行的名称前有星号图标，已收藏为实心高亮，未收藏为空心 |
| 2 | 点击星号添加收藏 | 点击未收藏 App 的空心星号 | 星号变为实心高亮，切换到收藏 Tab 可见该 App |
| 3 | 点击星号取消收藏 | 点击已收藏 App 的实心星号 | 星号变为空心，收藏 Tab 中该 App 消失 |
| 4 | 星号点击不触发折叠 | 点击有多窗口 App 的星号 | 收藏状态切换，但窗口列表折叠/展开状态不变 |
| 5 | 收藏上限 | 已有 8 个收藏，点击第 9 个 App 的星号 | 星号保持空心（静默失败），收藏数量不变 |
| 6 | 收藏 Tab 无星号 | 切换到收藏 Tab | App 行没有星号按钮（与当前行为一致） |

### 功能 2：主看板快捷键

| # | 场景 | 操作 | 预期结果 |
|---|------|------|----------|
| 7 | 默认快捷键打开看板 | 按 Command+Escape | 主看板窗口打开并前置 |
| 8 | 快捷键关闭看板 | 看板已打开时按 Command+Escape | 主看板窗口关闭 |
| 9 | 修改快捷键 | 在偏好设置中将主看板快捷键改为 Cmd+Shift+K | 新快捷键立即生效，旧快捷键失效 |
| 10 | 旧版配置升级 | 使用不含 hotkeyKanban 字段的旧配置启动 | 自动使用 Command+Escape 默认值，无崩溃 |

---

## 非目标声明

1. **不修改收藏 Tab 的交互**：收藏管理（增删排序）仍通过主看板 AppConfigView 完成
2. **不新增收藏上限提示 UI**：达到上限时静默失败，不弹 toast
3. **不做快捷键冲突检测**：两个快捷键设为相同组合时不阻止、不弹警告
4. **不修改 toggleMainKanban() 行为**：快捷键回调直接复用现有方法
5. **不涉及其他快捷键**：本次仅新增主看板快捷键，不涉及面板内操作快捷键
6. **不修改 HotkeyRecorderButton**：现有录制组件已通用

---

## 影响分析

### 需修改的现有模块

| 文件 | 修改范围 | 风险等级 |
|------|----------|----------|
| `QuickPanelView.swift` | `createAppRow()` 插入星号按钮 + `buildStructuralKey()` 追加收藏标记 | 低 - 纯增量，不改变现有行为 |
| `Models.swift` | Preferences 新增字段 + HotkeyConfig 新增常量 | 低 - 向后兼容 |
| `HotkeyManager.swift` | 重构为多槽位架构 | 中 - 核心变更，需确保旧 onToggle 行为不变 |
| `AppDelegate.swift` | setupHotkeys + applyPreferences 扩展 | 低 - 追加逻辑 |
| `PreferencesView.swift` | hotkeySection 新增一行 | 低 - 纯 UI 追加 |

### 回归风险点

1. **HotkeyManager 重构**：最高风险点。旧的 `register()`/`unregister()`/`reregister()` 接口需保持向后兼容，确保悬浮球快捷键不受影响。建议实现完成后先验证悬浮球快捷键（验收用例中的现有功能回归）
2. **星号按钮事件冒泡**：依赖 `HoverableRowView.mouseUp()` 中 NSButton 命中检测逻辑（L1029-1033），如果该逻辑变更可能导致星号点击同时触发行折叠
3. **Preferences 解码兼容性**：新增 `hotkeyKanban` 使用 `try?` + 默认值模式，与现有 `hotkeyToggle` 一致，风险低
4. **structuralKey 变更**：活跃 Tab 的 key 追加收藏标记，可能导致首次加载时多一次全量重建，性能影响可忽略
