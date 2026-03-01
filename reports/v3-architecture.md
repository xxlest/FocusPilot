# Focus Copilot V3.0 增量架构设计

> **版本**：V3.0
> **日期**：2026-03-02
> **基线**：V2.1（当前 main 分支）

---

## 1. 变更概述

| 文件 | 变更类型 | 说明 |
|---|---|---|
| `PinTop/Models/Models.swift` | **修改** | AppConfig 添加 `isFavorite`，移除 `pinnedKeywords`；删除 `PinnedWindow` 结构体 |
| `PinTop/Services/ConfigStore.swift` | **修改** | 添加 `toggleFavorite` 方法，移除 `updateKeywords` 方法 |
| `PinTop/Services/PinManager.swift` | **删除** | V3.0 移除 Pin 标记功能 |
| `PinTop/Helpers/Constants.swift` | **修改** | 移除 `pinnedWindowsChanged` 通知和 `pinnedWindowBaseLevel` 常量 |
| `PinTop/QuickPanel/QuickPanelView.swift` | **修改** | 添加 Tab 切换、选中高亮、底部按钮栏、App 启动逻辑；移除图钉按钮、关键词分区 |
| `PinTop/QuickPanel/QuickPanelWindow.swift` | **修改** | 面板高度计算适配底部栏 |
| `PinTop/MainKanban/MainKanbanView.swift` | **修改** | KanbanTab 移除 `.pinManage`，底部按钮文案变更 |
| `PinTop/MainKanban/AppConfigView.swift` | **修改** | 添加收藏 ★ 按钮，移除关键词配置 UI |
| `PinTop/MainKanban/PinManageView.swift` | **删除** | 置顶管理页面删除 |

---

## 2. 数据模型变更

### 2.1 AppConfig（修改）

**变更前**（Models.swift:5-11）：

```swift
struct AppConfig: Codable, Identifiable, Equatable {
    var id: String { bundleID }
    let bundleID: String
    var displayName: String
    var order: Int
    var pinnedKeywords: [String]   // ← 移除
}
```

**变更后**：

```swift
struct AppConfig: Codable, Identifiable, Equatable {
    var id: String { bundleID }
    let bundleID: String
    var displayName: String
    var order: Int
    var isFavorite: Bool           // ← 新增，默认 false
}
```

**迁移策略**：自定义 `init(from decoder:)` 解码器，旧数据无 `isFavorite` 字段时默认 `false`，忽略 `pinnedKeywords`，存量用户升级不丢数据。

### 2.2 PinnedWindow（删除）

Models.swift:66-76 的 `PinnedWindow` 结构体整体删除。V3.0 无"标记"概念，窗口行点击 = 高亮 + 前置，高亮为纯运行时状态，无需持久化模型。

---

## 3. 接口契约变更

### 3.1 ConfigStore

| 方法 | 变更 | 说明 |
|---|---|---|
| `addApp(_:displayName:)` | **修改** | 初始化 `isFavorite: false` 替代 `pinnedKeywords: []` |
| `toggleFavorite(for:)` | **新增** | 切换指定 bundleID 的 isFavorite 状态并保存 |
| `updateKeywords(for:keywords:)` | **移除** | 关键词功能已删除 |

**新增方法**：

```swift
func toggleFavorite(for bundleID: String) {
    if let index = appConfigs.firstIndex(where: { $0.bundleID == bundleID }) {
        appConfigs[index].isFavorite.toggle()
        save()
    }
}
```

### 3.2 QuickPanelView 内部状态

| 状态 | 类型 | 说明 |
|---|---|---|
| `currentTab` | `QuickPanelTab` | 当前 Tab，`.selected`（默认）或 `.favorite` |
| `highlightedWindowID` | `CGWindowID?` | 当前高亮窗口行 ID，面板关闭时重置为 nil |

**新增枚举**（QuickPanelView.swift 内部私有）：

```swift
private enum QuickPanelTab {
    case selected   // 已选
    case favorite   // 收藏
}
```

### 3.3 通知名变更

| 通知名 | 变更 |
|---|---|
| `pinnedWindowsChanged` | **移除**（随 PinManager 删除） |

无需新增通知。Tab 切换和高亮均为 QuickPanelView 内部状态。

---

## 4. 模块变更详情

### 4.1 QuickPanelView（最大变更）

#### 4.1.1 顶部栏变更

**当前**：左侧 openKanbanButton + 右侧 panelPinButton

**变更后**：左侧 openKanbanButton + 中间 Tab 按钮组 + 右侧 panelPinButton

Tab 按钮实现为两个 `NSButton`，选中态用 `controlAccentColor` 背景 + 白色文字，未选中用透明背景 + `secondaryLabelColor` 文字。点击切换 `currentTab` 并调用 `reloadData()`。

#### 4.1.2 窗口行变更

**移除**：
- 图钉按钮（pinButton 及全部 pin toggle 逻辑）
- ★ 标识（关键词匹配标记）
- `handlePinToggle(_:)` 方法
- `categorizeWindows(_:keywords:)` 方法

**新增**：
- 选中高亮：当 `highlightedWindowID == windowInfo.id` 时，行背景色为 `controlAccentColor.withAlphaComponent(0.2)`
- 点击逻辑：设置 `highlightedWindowID` + `WindowService.shared.activateWindow()`
- 高亮渲染在 `createWindowRow` 中根据 highlightedWindowID 判断

#### 4.1.3 底部按钮栏（新增）

scrollView 下方固定 36px 高度底部栏：

```
┌──────────────────┬──────────────────┐
│ 🔵 悬浮球 显示    │    ⏻ 退出        │  ← 36px
└──────────────────┴──────────────────┘
```

- **左半**：eye/eye.slash 图标 + "悬浮球 显示"/"悬浮球 隐藏"
  - 点击发 `Constants.Notifications.ballToggle`
  - 监听 `ConfigStore.shared.isBallVisible` 更新
- **右半**：power 图标 + "退出" 红色文字
  - 点击弹 NSAlert 确认，确认后 terminate
- 中间 1px 分割线
- 按钮各占一半宽度，整个面积可点击

**布局调整**：
- 新增 `bottomBar` 和 `bottomSeparator` 子视图
- scrollView.bottomAnchor 约束改到 bottomSeparator.topAnchor
- bottomBar.bottomAnchor 约束到视图底部

#### 4.1.4 数据源变更

根据 `currentTab` 过滤 appConfigs：

```swift
let configs: [AppConfig]
switch currentTab {
case .selected:
    configs = Array(ConfigStore.shared.appConfigs.prefix(Constants.Panel.maxApps))
case .favorite:
    configs = ConfigStore.shared.appConfigs.filter { $0.isFavorite }
}
```

#### 4.1.5 移除关键词相关

- 移除 `categorizeWindows(_:keywords:)` 方法
- `createWindowList` 移除 `keywords` 参数，窗口列表不再分区
- 所有窗口按系统层级顺序平铺

#### 4.1.6 未运行 App 启动

当前未运行 App 行无 clickHandler。变更后添加：

```swift
if !isRunning {
    row.alphaValue = 0.5
    row.toolTip = "点击启动"
    row.clickHandler = {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: config.bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error = error {
                    NSLog("[FocusCopilot] 启动 App 失败: %@ - %@", config.bundleID, error.localizedDescription)
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "无法启动该应用"
                        alert.informativeText = error.localizedDescription
                        alert.runModal()
                    }
                }
            }
        }
    }
}
```

App 启动后通过 AppMonitor `didLaunchApplication` 通知自动 reloadData。

#### 4.1.7 reloadData 快照变更

移除 `pinnedIDs`（PinManager 数据），增加 `currentTab` 和 `highlightedWindowID`：

```swift
let snapshot = "\(currentTab):\(highlightedWindowID ?? 0):\(windowKeys)"
```

#### 4.1.8 通知监听变更

- 移除 `pinnedWindowsDidChange` 监听
- 添加 `ballVisibilityChanged` 监听（底部按钮更新）

#### 4.1.9 resetToNormalMode 变更

面板关闭/重置时清除高亮：

```swift
func resetToNormalMode() {
    updatePanelPinButton(isPinned: false)
    highlightedWindowID = nil
    currentTab = .selected
}
```

### 4.2 QuickPanelWindow

面板高度计算需考虑底部栏 36px：

```swift
// updatePanelSize 中的总高度计算
let totalHeight = contentHeight + 24 + 4 + Constants.Panel.bottomBarHeight
```

### 4.3 MainKanbanView

#### 4.3.1 KanbanTab 变更

```swift
// 变更后
enum KanbanTab: String, CaseIterable {
    case appConfig = "快捷面板配置"
    case preferences = "偏好设置"

    var icon: String {
        switch self {
        case .appConfig: return "square.grid.2x2"
        case .preferences: return "gearshape"
        }
    }
}
```

#### 4.3.2 detail 视图

移除 `case .pinManage: PinManageView()`。

#### 4.3.3 底部按钮文案

- 字号从 `.caption` 改为 `.callout`
- 文案从 "隐藏"/"显示" 改为 "悬浮球 隐藏"/"悬浮球 显示"

#### 4.3.4 移除引用

移除 `@ObservedObject private var pinManager = PinManager.shared`。

### 4.4 AppConfigView

#### 4.4.1 收藏按钮

齿轮按钮替换为 ★ 收藏切换按钮：

```swift
Button {
    configStore.toggleFavorite(for: config.bundleID)
} label: {
    Image(systemName: config.isFavorite ? "star.fill" : "star")
        .foregroundStyle(config.isFavorite ? .yellow : .secondary)
}
.buttonStyle(.borderless)
```

#### 4.4.2 移除关键词配置

- 移除 `expandedAppID` 状态
- 移除 `keywordConfigSection(for:)` 方法
- 移除 `windowPreview(for:)` 方法
- 移除 `categorizeWindows(_:keywords:)` 方法
- 移除 `AddKeywordField` 辅助视图

---

## 5. 删除清单

### 5.1 文件删除

| 文件 | 原因 |
|---|---|
| `PinTop/Services/PinManager.swift` | 标记功能移除 |
| `PinTop/MainKanban/PinManageView.swift` | 置顶管理页面移除 |

### 5.2 引用清理

| 位置 | 清理内容 |
|---|---|
| `QuickPanelView.swift` | 移除 PinManager 所有引用、pinnedWindowsDidChange 监听、handlePinToggle、rotatedPinImage（面板钉住按钮仍使用 rotatedPinImage，需保留） |
| `MainKanbanView.swift` | 移除 `@ObservedObject pinManager`、`.pinManage` case |
| `Constants.swift` | 移除 `pinnedWindowsChanged` 通知名、`pinnedWindowBaseLevel` 常量 |
| `Models.swift` | 移除 `PinnedWindow` 结构体、`AppConfig.pinnedKeywords` |
| `ConfigStore.swift` | 移除 `updateKeywords` 方法 |

### 5.3 Preferences 字段清理

| 字段 | 决策 |
|---|---|
| `pinBorderColor` | **移除**（无消费方） |
| `pinSoundEnabled` | **移除**（无消费方） |
| `hotkeyPinToggle` | **保留**（快捷键 ⌘⇧P 用于"前置当前窗口"，PRD 中仍保留此功能） |

---

## 6. 验收用例

| # | 用例 | 操作 | 预期结果 | 类型 |
|---|---|---|---|---|
| TC-01 | Tab 切换 | 配置 3 App 其中 2 个收藏 → 打开面板 → 切换到收藏 Tab | 收藏 Tab 显示 2 个 App | 正常 |
| TC-02 | 窗口行高亮+前置 | 点击窗口 A → 点击窗口 B | A 取消高亮，B 高亮+前置 | 正常 |
| TC-03 | 启动未运行 App | 点击灰色未运行 App | App 启动，面板刷新为运行态 | 正常 |
| TC-04 | 底部悬浮球显隐 | 点击"悬浮球 隐藏" | 球隐藏，文案变"悬浮球 显示" | 正常 |
| TC-05 | 底部退出 | 点击退出 → 确认 | 弹确认框，确认后 App 退出 | 正常 |
| TC-06 | 收藏持久化 | 收藏 App → 重启 | 收藏状态恢复 | 边界 |
| TC-07 | 高亮重置 | 高亮某行 → 关闭面板 → 重开 | 无高亮 | 边界 |
| TC-08 | 旧数据迁移 | 旧 AppConfig 含 pinnedKeywords | 正常加载，isFavorite=false | 异常恢复 |

---

## 7. 非目标声明

- 收藏 Tab 独立排序（沿用 order 排序）
- 快捷面板搜索框
- 窗口缩略图预览
- 拖拽排序窗口列表
- WindowService / AppMonitor 重构
- 悬浮球逻辑修改
- 网络相关功能
