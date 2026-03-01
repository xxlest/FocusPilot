# Focus Copilot 架构设计文档

> **版本**：V2.1
> **日期**：2026-03-02
> **基于**：PRD V2.1

---

## 1. 模块划分

### 总览

```
PinTop/
├── PinTop/
│   ├── App/
│   │   ├── AppDelegate.swift          # 应用生命周期、窗口管理、菜单栏图标
│   │   ├── PinTopApp.swift            # @main 入口
│   │   └── PermissionManager.swift    # 辅助功能权限检测与引导
│   ├── FloatingBall/
│   │   ├── FloatingBallWindow.swift   # 悬浮球窗口（NSPanel）
│   │   └── FloatingBallView.swift     # 悬浮球视图、拖拽、贴边、hover、品牌 Logo
│   ├── QuickPanel/
│   │   ├── QuickPanelWindow.swift     # 快捷面板窗口（NSPanel），钉住模式、resize、drag
│   │   └── QuickPanelView.swift       # 面板内容视图（App列表、窗口列表、折叠/展开、底部按钮）
│   ├── MainKanban/
│   │   ├── MainKanbanWindow.swift     # 主看板窗口管理
│   │   ├── MainKanbanView.swift       # 主看板根视图（SwiftUI），侧边栏+底部双按钮
│   │   ├── AppConfigView.swift        # 快捷面板配置页（SwiftUI）
│   │   ├── PinManageView.swift        # 标记管理页（SwiftUI）
│   │   └── PreferencesView.swift      # 偏好设置页（SwiftUI）
│   ├── Services/
│   │   ├── WindowService.swift        # 窗口枚举、AX 操作、层级控制、诊断日志
│   │   ├── AppMonitor.swift           # 监听 App 启动/退出，维护运行列表
│   │   ├── PinManager.swift           # 窗口标记状态管理（纯视觉标记）
│   │   ├── HotkeyManager.swift        # 全局快捷键注册（Carbon API）
│   │   └── ConfigStore.swift          # 用户配置持久化（UserDefaults）
│   ├── Models/
│   │   └── Models.swift               # 数据模型定义
│   ├── Helpers/
│   │   ├── CGSPrivate.h               # Private API 桥接头
│   │   └── Constants.swift            # 全局常量、通知名、窗口层级
│   ├── Resources/
│   │   ├── Assets.xcassets/           # 图标资源
│   │   └── PinTop.entitlements        # 权限配置
│   └── Info.plist
├── PinTop.xcodeproj/
└── docs/
    ├── PRD.md
    └── Architecture.md
```

### 模块职责与拆分理由

| 模块 | 职责 | 独立变化理由 |
|---|---|---|
| **App/** | 应用入口、生命周期、权限管理 | 应用级初始化逻辑独立于具体 UI |
| **FloatingBall/** | 悬浮球 UI、拖拽、贴边、hover 检测、品牌 Logo | 悬浮球交互逻辑独立变化频率高 |
| **QuickPanel/** | 快捷面板 UI、App 列表、窗口列表、折叠/展开、底部按钮 | 面板展示和交互独立于悬浮球 |
| **MainKanban/** | 主看板 SwiftUI 界面（3 个配置页面 + 底部双按钮） | SwiftUI 技术栈独立，页面布局频繁调整 |
| **Services/** | 底层服务（窗口操作、App 监控、Pin 管理、快捷键、配置存储） | 业务逻辑层与 UI 层分离 |
| **Models/** | 数据模型 | 数据结构被多个模块共享 |
| **Helpers/** | 桥接头、常量、通知名 | 基础设施，极少变化 |

### 防过度设计自查

- [x] 文件数（~19）<= 功能点数（28）
- [x] 无多余抽象层：Services 直接暴露方法，无 Protocol 包装
- [x] 没有为"未来可能"创建接口
- [x] 没有只有一个实现的抽象层

---

## 2. 接口契约

### 2.1 数据模型（Models.swift）

```swift
// App 配置（持久化）
struct AppConfig: Codable, Identifiable, Equatable {
    var id: String { bundleID }
    let bundleID: String          // App 唯一标识
    var displayName: String       // 自定义显示名称
    var order: Int                // 快捷面板中的排序
    var pinnedKeywords: [String]  // 窗口排序关键词
}

// 运行中的 App 信息（运行时）
class RunningApp: Identifiable, ObservableObject {
    var id: String { bundleID }
    let bundleID: String
    let localizedName: String
    let icon: NSImage
    let nsApp: NSRunningApplication?  // 进程引用（未运行时为 nil）
    @Published var windows: [WindowInfo]
    @Published var isRunning: Bool
}

// 窗口信息（运行时）
struct WindowInfo: Identifiable, Equatable {
    let id: CGWindowID
    let ownerBundleID: String
    let ownerPID: pid_t
    var title: String
    var bounds: CGRect
    var isMinimized: Bool
    var isFullScreen: Bool
}

// 标记窗口信息
struct PinnedWindow: Identifiable, Equatable {
    let id: CGWindowID
    let ownerBundleID: String
    var title: String
    var order: Int                // 排序序号
    let ownerPID: pid_t
}

// 已安装 App 信息
struct InstalledApp: Identifiable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let icon: NSImage
    let url: URL
}

// 面板大小（持久化）
struct PanelSize: Codable {
    var width: CGFloat
    var height: CGFloat
    static let `default` = PanelSize(width: 280, height: 400)
}

// 悬浮球位置（持久化）
struct BallPosition: Codable {
    var x: CGFloat
    var y: CGFloat
    var edge: ScreenEdge
    static let `default` = BallPosition(x: 50, y: 300, edge: .left)
}

enum ScreenEdge: String, Codable {
    case top, bottom, left, right
}

// 偏好设置（持久化）
struct Preferences: Codable {
    var ballSize: CGFloat = 40        // 30-60px
    var ballOpacity: CGFloat = 0.8    // 0.3-1.0
    var colorTheme: ColorTheme = .system
    var launchAtLogin: Bool = false
    var pinBorderColor: String = "blue"
    var pinSoundEnabled: Bool = true
    var hotkeyPinToggle: String = "⌘⇧P"
    var hotkeyBallToggle: String = "⌘⇧B"
}

enum ColorTheme: String, Codable {
    case system, light, dark
}
```

### 2.2 ConfigStore 契约

```swift
class ConfigStore: ObservableObject {
    static let shared = ConfigStore()

    // 已选 App 列表（有序）
    @Published var appConfigs: [AppConfig]

    // 偏好设置
    @Published var preferences: Preferences

    // 悬浮球位置
    @Published var ballPosition: BallPosition

    // Onboarding 是否已完成
    @Published var onboardingCompleted: Bool

    // 窗口重命名映射（key="{bundleID}::{原标题}", value=自定义名称）
    @Published var windowRenames: [String: String]

    // 面板大小（拖拽 resize 后持久化）
    @Published var panelSize: PanelSize

    // 悬浮球显隐状态（运行时，不持久化）
    @Published var isBallVisible: Bool

    // CRUD 操作
    func addApp(_ bundleID: String, displayName: String)
    func removeApp(_ bundleID: String)
    func reorderApps(_ ids: [String])
    func updateKeywords(for bundleID: String, keywords: [String])
    func saveBallPosition(_ position: BallPosition)
    func save()    // 持久化到 UserDefaults
    func load()    // 从 UserDefaults 加载

    // 配置迁移（PinTop → FocusCopilot）
    private func migrateFromPinTop()
}
```

**UserDefaults Keys**：`FocusCopilot.appConfigs`、`FocusCopilot.preferences`、`FocusCopilot.ballPosition`、`FocusCopilot.onboardingCompleted`、`FocusCopilot.windowRenames`、`FocusCopilot.panelSize`

### 2.3 AppMonitor 契约

```swift
class AppMonitor: ObservableObject {
    static let shared = AppMonitor()

    // 当前运行中的 App 列表（已配置的 + 状态）
    @Published var runningApps: [RunningApp]

    // 已安装 App 列表
    @Published var installedApps: [InstalledApp]

    func startMonitoring()        // 注册 NSWorkspace 通知
    func stopMonitoring()         // 注销通知
    func refreshRunningApps()     // 刷新已配置 App 运行状态
    func refreshAllWindows()      // 刷新所有 App 窗口列表
    func refreshWindows(for bundleID: String)  // 刷新单个 App 窗口
    func scanInstalledApps()      // 扫描 /Applications + ~/Applications
    func isRunning(_ bundleID: String) -> Bool

    // 面板显示时启动窗口刷新定时器（1s 间隔）
    func startWindowRefresh()
    // 面板隐藏时停止窗口刷新定时器
    func stopWindowRefresh()

    // 通知
    static let appStatusChanged = Constants.Notifications.appStatusChanged
    static let windowsChanged = Constants.Notifications.windowsChanged
}
```

### 2.4 WindowService 契约

```swift
class WindowService {
    static let shared = WindowService()

    // CGS Private API 函数指针（动态加载）
    let cgsMainConnectionIDFunc: (@convention(c) () -> Int32)?
    let cgsSetWindowLevelFunc: (@convention(c) (Int32, CGWindowID, Int32) -> CGError)?

    // AX 可用性检测（带 3 秒缓存）
    func isAXApiAvailable() -> Bool
    func invalidateAXCache()

    // 窗口枚举
    func listWindows(for bundleID: String) -> [WindowInfo]
    func listWindows(for pid: pid_t) -> [WindowInfo]
    func listAllWindows() -> [WindowInfo]

    // 窗口操作（需要辅助功能权限）
    func activateWindow(_ window: WindowInfo)  // 激活并前置窗口
    func activateApp(_ bundleID: String)       // 激活 App（不需要权限）

    // 窗口层级（诊断用）
    func setWindowLevel(_ windowID: CGWindowID, level: Int32)
    func orderWindowAbove(_ windowID: CGWindowID)
    func axRaiseWindow(_ windowID: CGWindowID)

    // AX 窗口查找
    func getAXElement(for pid: pid_t) -> AXUIElement
    func getAXWindows(for pid: pid_t) -> [AXUIElement]
    func findAXWindow(pid: pid_t, windowID: CGWindowID) -> AXUIElement?
    func findAXWindow(pid: pid_t, title: String) -> AXUIElement?

    // AX 窗口操作
    func moveWindow(_ axWindow: AXUIElement, to: CGPoint)
    func resizeWindow(_ axWindow: AXUIElement, to: CGSize)
    func setWindowFrame(_ axWindow: AXUIElement, frame: CGRect)

    // 诊断日志（写入 /tmp/focuscopilot-debug.log）
    func debugLog(_ message: String)

    // --- 关键实现细节 ---
    // getCGWindowID(from: AXUIElement) -> CGWindowID?
    //   使用 _AXUIElementGetWindow 私有 API
    //
    // buildAXTitleMap(for pid: pid_t, cgWindows: [[String: Any]]) -> [CGWindowID: String]
    //   四级标题兜底：AX 标题 → CG 标题 → 缓存 → "(无标题)"
    //   权限丢失时回退到位置匹配（tolerance=10px）
    //
    // activateWindow 跨 App 激活重试机制：
    //   activate App → AXRaise → 300ms 后检查 frontmostApplication → 兜底重试
}
```

### 2.5 PinManager 契约

```swift
class PinManager: ObservableObject {
    static let shared = PinManager()

    // 已标记的窗口列表（有序）
    @Published var pinnedWindows: [PinnedWindow]

    var pinnedCount: Int { pinnedWindows.count }

    func pin(window: WindowInfo) -> Bool     // 标记窗口（纯视觉），返回是否成功
    func unpin(windowID: CGWindowID)          // 取消标记
    func unpinAll()                           // 取消所有标记
    func togglePin(window: WindowInfo)        // 切换标记状态
    func reorder(_ ids: [CGWindowID])         // 重新排列顺序
    func isPinned(_ windowID: CGWindowID) -> Bool

    // 通知
    static let pinnedWindowsChanged = Constants.Notifications.pinnedWindowsChanged
}
```

**注意**：Pin 为纯视觉标记，无数量上限，不控制窗口层级。

### 2.6 HotkeyManager 契约

```swift
class HotkeyManager {
    static let shared = HotkeyManager()

    func registerAll()       // 注册所有全局快捷键
    func unregisterAll()     // 注销所有

    enum HotkeyAction: Int {
        case pinToggle = 1   // ⌘⇧P
        case ballToggle = 6  // ⌘⇧B
    }
}
```

### 2.7 PermissionManager 契约

```swift
class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published var accessibilityGranted: Bool = false

    func checkAccessibility() -> Bool   // 实时检查（不可缓存）
    func requestAccessibility()         // 引导用户开启权限
    func startPolling()                 // 轮询检测权限状态
    func stopPolling()
}
```

### 2.8 Constants.Notifications（集中管理的通知名）

```swift
enum Constants {
    enum Notifications {
        // 系统级通知
        static let appStatusChanged = Notification.Name("FocusCopilot.appStatusChanged")
        static let windowsChanged = Notification.Name("FocusCopilot.windowsChanged")
        static let pinnedWindowsChanged = Notification.Name("FocusCopilot.pinnedWindowsChanged")
        static let ballVisibilityChanged = Notification.Name("FocusCopilot.ballVisibilityChanged")
        static let accessibilityGranted = Notification.Name("FocusCopilot.accessibilityGranted")

        // 悬浮球通知
        static let ballShowQuickPanel = Notification.Name("FloatingBall.showQuickPanel")
        static let ballToggle = Notification.Name("FloatingBall.toggleBall")
        static let ballOpenMainKanban = Notification.Name("FloatingBall.openMainKanban")
        static let ballDragStarted = Notification.Name("FloatingBall.dragStarted")
        static let ballDragMoved = Notification.Name("FloatingBall.dragMoved")
        static let ballMouseExited = Notification.Name("FloatingBall.mouseExited")
        static let ballToggleQuickPanel = Notification.Name("FloatingBall.toggleQuickPanel")

        // 快捷面板通知
        static let panelPinStateChanged = Notification.Name("QuickPanel.pinStateChanged")
        static let panelDragMoved = Notification.Name("QuickPanel.dragMoved")
    }
}
```

---

## 3. 模块间交互

### 3.1 FloatingBall → QuickPanel 交互

```
FloatingBallView                   QuickPanelWindow
     │                                │
     │── hover 300ms ────────────────▶│ show(relativeTo: ballFrame)
     │   (ballShowQuickPanel)         │    └── AppMonitor.startWindowRefresh()
     │                                │
     │── click ──────────────────────▶│ toggleQuickPanel (ballToggleQuickPanel)
     │   未显示/未钉住→show+pin        │
     │   已显示且钉住→unpin+hide       │
     │                                │
     │── double-click ──────────────▶ MainKanbanWindow.show()
     │   (ballOpenMainKanban)         │
     │                                │
     │── drag-start ────────────────▶│ hide() (ballDragStarted)
     │                                │
     │◀── mouseExited(500ms) ────────│ hide()（钉住时跳过）
     │   (ballMouseExited)            │    └── AppMonitor.stopWindowRefresh()
```

### 3.2 QuickPanel → Services 交互

```
QuickPanelView（clickHandler 模式）
     │
     │── 点击单窗口 App 行 ──▶ WindowService.activateWindow(window)
     │── 点击多窗口 App 行 ──▶ 切换折叠/展开（collapsedApps）
     │── 点击窗口行 ──────────▶ PinManager.togglePin(window) + WindowService.activateWindow(window)
     │── 点击窗口行 Pin 按钮 ─▶ PinManager.togglePin(window)
     │── 点击窗口行 Unpin 按钮▶ PinManager.unpin(windowID)
     │── 右键窗口行 ──────────▶ 窗口重命名（NSAlert+NSTextField）
     │                         └── ConfigStore.windowRenames["{bundleID}::{title}"]
     │── 点击底部显隐按钮 ────▶ ballToggle 通知
     │── 点击底部退出按钮 ────▶ NSApplication.terminate()
     │
     │── 读取数据 ─────────────▶ AppMonitor.runningApps
     │                       ▶ ConfigStore.appConfigs
     │                       ▶ ConfigStore.windowRenames
     │                       ▶ PinManager.pinnedWindows

QuickPanelWindow
     │
     │── 顶部钉住按钮 ─────────▶ togglePanelPin()
     │── 顶部拖拽区域（24px）──▶ handlePanelDrag()（钉住时联动悬浮球）
     │── 边缘拖拽 resize ──────▶ ConfigStore.panelSize + save()
```

### 3.3 MainKanban 侧边栏底部按钮

```
MainKanbanView
     │
     │── 左半按钮（显隐球）──▶ ballToggle 通知
     │── 右半按钮（退出）───▶ 确认对话框 → NSApplication.terminate()
```

---

## 4. 行为约束

### 4.1 状态转换矩阵

#### 悬浮球状态

| 当前状态 | 触发条件 | 目标状态 | 副作用 |
|---|---|---|---|
| 正常显示 | hover 300ms | 正常显示 + 快捷面板弹出 | QuickPanel.show()（面板已钉住时跳过） |
| 正常显示 | 单击 | 正常显示 | 切换面板钉住状态 |
| 正常显示 | 双击 | 正常显示 | 打开主看板 |
| 正常显示 | 拖拽开始 | 拖拽中 | 关闭快捷面板 |
| 拖拽中 | 拖拽结束 | 正常显示 | 吸附到最近边缘 + 保存位置 |
| 正常显示 | 贴边检测 | 贴边半隐藏 | 收入一半 |
| 贴边半隐藏 | 鼠标靠近 | 正常显示 | 滑出动画 |
| 隐藏 | ⌘⇧B | 正常显示 | 恢复到上次位置 |
| 正常显示 | ⌘⇧B / 底部按钮 | 隐藏 | 保存状态 |

#### 快捷面板状态

| 当前状态 | 触发条件 | 目标状态 | 副作用 |
|---|---|---|---|
| 隐藏 | 悬浮球 hover 300ms | 显示（未钉住） | startWindowRefresh() |
| 隐藏 | 悬浮球单击 | 显示（钉住） | startWindowRefresh() |
| 显示（未钉住） | 鼠标离开 500ms | 隐藏 | stopWindowRefresh() |
| 显示（未钉住） | 点击 App/窗口切换 | 隐藏 | 执行切换，stopWindowRefresh() |
| 显示（未钉住） | 悬浮球拖拽 | 隐藏 | stopWindowRefresh() |
| 显示（未钉住） | 点击钉住按钮 | 显示（钉住） | 取消 dismissTimer |
| 显示（钉住） | 悬浮球单击 | 隐藏 | 取消钉住，stopWindowRefresh() |
| 显示（钉住） | 点击钉住按钮 | 显示（未钉住） | 恢复自动收起 |
| 显示（钉住） | 鼠标离开 | 显示（钉住） | 不触发收起 |
| 显示（钉住） | 面板拖拽 | 显示（钉住） | 联动悬浮球同步移动 |

#### Pin 窗口状态

| 当前状态 | 触发条件 | 目标状态 | 副作用 |
|---|---|---|---|
| 未标记 | 点击窗口行/快捷键 | 已标记 | 更新菜单栏图标颜色 |
| 已标记 | 点击窗口行/Unpin按钮/快捷键 | 未标记 | 更新菜单栏图标颜色 |
| 已标记 | 窗口关闭 | 清除 | 自动取消标记 |
| 已标记 | App 退出 | 清除 | 自动清理 |

### 4.2 通用边界行为

| 场景 | 处理 |
|---|---|
| App 配置已满 8 个 | 禁用添加按钮，提示先移除 |
| 未配置任何 App | 快捷面板显示空状态引导 |
| 辅助功能未授权 | 标记功能和窗口标题获取不可用，App 切换正常 |
| 窗口标题为空 | 四级兜底：AX 标题 → CG 标题 → 缓存 → "(无标题)" |
| App 图标获取失败 | 使用系统默认图标 |
| 多显示器 | 悬浮球限制在一个屏幕，拖拽不跨屏 |
| App 退出 | 清除所有 Pin 状态（不持久化） |
| codesign 导致权限失效 | PermissionManager 后台轮询检测，自动恢复 |

### 4.3 跨 App 窗口激活

```
activateWindow(window)
  → app.activate()                // 激活目标 App
  → raiseWindowViaAX(window)      // AXRaise 前置窗口
  → 300ms 后检查 frontmostApplication
    → 若目标 App 未成为前台
      → app.activate() 重试
      → raiseWindowViaAX(window) 重试
```

### 4.4 关键词匹配规则

```
输入：窗口标题 title, 关键词列表 keywords
输出：(isPinned: Bool, matchedKeywordIndex: Int?)

for (index, keyword) in keywords.enumerated() {
    if title.localizedCaseInsensitiveContains(keyword) {
        return (true, index)
    }
}
return (false, nil)

排序规则：
- 置顶区：按 matchedKeywordIndex 升序
- 普通区：按系统窗口层级排列
```

---

## 5. 验收用例

### TC-01: 悬浮球基本显示与拖拽

- **前置条件**：应用启动完成
- **操作步骤**：确认悬浮球显示 → 拖拽到屏幕中间 → 松开
- **预期结果**：悬浮球吸附到最近屏幕边缘，拖拽 60fps 流畅
- **覆盖**：F01, F02

### TC-02: 快捷面板 hover 弹出与 App 切换

- **前置条件**：已配置 3+ 个 App，其中 2+ 个运行中
- **操作步骤**：hover 悬浮球 300ms → 面板弹出 → 点击运行中的单窗口 App
- **预期结果**：面板弹出 <100ms，点击后 <200ms 切换到目标 App，面板收起
- **覆盖**：F05, F07, F08

### TC-03: 单击弹出+钉住与取消钉住

- **前置条件**：快捷面板未显示
- **操作步骤**：单击悬浮球 → 面板弹出并钉住 → 鼠标离开 → 确认不收起 → 再次单击悬浮球
- **预期结果**：面板弹出且自动钉住，鼠标离开不收起，再次单击后取消钉住并关闭
- **覆盖**：F06, F14

### TC-04: 多窗口折叠/展开与窗口切换

- **前置条件**：已配置一个多窗口 App（如 Cursor，3 个窗口）
- **操作步骤**：hover 弹出面板 → 确认多窗口展开 → 点击 App 行折叠 → 再次点击展开 → 点击窗口行
- **预期结果**：默认展开，点击切换折叠/展开，点击窗口行激活该窗口
- **覆盖**：F09, F11, F12

### TC-05: 跨 App 窗口激活

- **前置条件**：配置了多个 App（如 Cursor 和微信）
- **操作步骤**：在 Cursor 中点击快捷面板的微信窗口 → 确认微信窗口前置
- **预期结果**：微信窗口被激活并前置，<200ms 响应
- **覆盖**：F12

### TC-06: 主看板 App 配置

- **前置条件**：首次使用
- **操作步骤**：双击悬浮球打开主看板 → 添加 3 个 App → 拖拽排序 → 配置关键词 → 关闭主看板 → hover 悬浮球
- **预期结果**：配置生效，快捷面板按配置顺序展示
- **覆盖**：F17, F18

### TC-07: Pin/Unpin 操作

- **前置条件**：辅助功能权限已授权，2+ 个窗口可见
- **操作步骤**：在快捷面板中点击窗口行标记 → 确认红色图钉 → 使用 ⌘⇧P 切换 → 关闭窗口
- **预期结果**：标记成功（红色图钉），快捷键切换正常，窗口关闭后自动清除标记
- **覆盖**：F11, F21

### TC-08: 底部按钮——显隐球与退出

- **前置条件**：悬浮球可见
- **操作步骤**：点击面板底部"隐藏"按钮 → 悬浮球隐藏 → ⌘⇧B 唤出 → 主看板底部点"退出"
- **预期结果**：底部按钮正确切换显隐，退出弹出确认对话框
- **覆盖**：F04, F26

---

## 6. 非目标声明

当前版本**不做**以下功能：

- 不实现快捷面板启动未运行 App（只做切换）
- 不实现窗口分组
- 不实现 Pin 状态持久化恢复（退出即清除）
- 不实现插件系统
- 不实现网络请求（无遥测、无更新检查）
- 不实现 Onboarding 引导
- 不实现 Pin 窗口层级控制（Pin 为纯视觉标记）

---

## 7. 文件清单与职责

| 文件 | 行数 | 职责 |
|---|---|---|
| PinTopApp.swift | ~16 | @main 入口，初始化 AppDelegate |
| AppDelegate.swift | ~366 | 应用生命周期、窗口管理、菜单栏图标、Dock 图标 |
| PermissionManager.swift | ~90 | 辅助功能权限检测、引导、后台轮询 |
| FloatingBallWindow.swift | ~98 | NSPanel 子类，窗口层级、贴边 |
| FloatingBallView.swift | ~783 | 悬浮球视图、品牌 Logo、hover/click/drag 检测 |
| QuickPanelWindow.swift | ~480 | NSPanel 子类，面板位置、钉住、resize、drag、联动 |
| QuickPanelView.swift | ~979 | 面板内容：App 列表、窗口列表、折叠/展开、底部按钮、重命名 |
| MainKanbanWindow.swift | ~51 | NSWindow 子类，主看板窗口管理 |
| MainKanbanView.swift | ~95 | SwiftUI 根视图，侧边栏导航 + 底部双按钮 |
| AppConfigView.swift | ~459 | SwiftUI 快捷面板配置：App 选择、排序、关键词 |
| PinManageView.swift | ~180 | SwiftUI 标记管理页面 |
| PreferencesView.swift | ~164 | SwiftUI 偏好设置页面 |
| WindowService.swift | ~599 | 窗口枚举、AX 操作、CGS 层级、标题四级兜底、跨 App 激活 |
| AppMonitor.swift | ~210 | App 运行状态监控、窗口刷新定时器 |
| PinManager.swift | ~91 | 纯视觉标记状态管理 |
| HotkeyManager.swift | ~76 | 全局快捷键（Carbon API），2 个动作 |
| ConfigStore.swift | ~162 | UserDefaults 持久化（含迁移逻辑） |
| Models.swift | ~118 | 数据模型定义 |
| Constants.swift | ~89 | 全局常量、14 个集中管理的通知名 |
| **合计** | **~5106** | |
