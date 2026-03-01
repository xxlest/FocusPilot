# Focus Copilot 架构设计文档

> **版本**：V3.0
> **日期**：2026-03-02
> **基于**：PRD V3.0

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
│   │   └── QuickPanelView.swift       # 面板内容视图（已选/收藏 Tab、窗口行高亮+前置、底部按钮）
│   ├── MainKanban/
│   │   ├── MainKanbanWindow.swift     # 主看板窗口管理
│   │   ├── MainKanbanView.swift       # 主看板根视图（SwiftUI），侧边栏+底部双按钮
│   │   ├── AppConfigView.swift        # 快捷面板配置页（SwiftUI），含收藏★切换
│   │   └── PreferencesView.swift      # 偏好设置页（SwiftUI）
│   ├── Services/
│   │   ├── WindowService.swift        # 窗口枚举、AX 操作、层级控制、诊断日志
│   │   ├── AppMonitor.swift           # 监听 App 启动/退出，维护运行列表
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

### V3.0 变更说明

相比 V2.1，删除以下文件：
- `PinManager.swift` — V3.0 彻底移除 Pin（标记/置顶）概念
- `PinManageView.swift` — V3.0 移除标记管理页面

### 模块职责与拆分理由

| 模块 | 职责 | 独立变化理由 |
|---|---|---|
| **App/** | 应用入口、生命周期、权限管理 | 应用级初始化逻辑独立于具体 UI |
| **FloatingBall/** | 悬浮球 UI、拖拽、贴边、hover 检测、品牌 Logo | 悬浮球交互逻辑独立变化频率高 |
| **QuickPanel/** | 快捷面板 UI、已选/收藏 Tab、窗口行高亮+前置、底部按钮 | 面板展示和交互独立于悬浮球 |
| **MainKanban/** | 主看板 SwiftUI 界面（2 个配置页面 + 底部双按钮） | SwiftUI 技术栈独立，页面布局频繁调整 |
| **Services/** | 底层服务（窗口操作、App 监控、快捷键、配置存储） | 业务逻辑层与 UI 层分离 |
| **Models/** | 数据模型 | 数据结构被多个模块共享 |
| **Helpers/** | 桥接头、常量、通知名 | 基础设施，极少变化 |

### 防过度设计自查

- [x] 文件数（~17）<= 功能点数（28）
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
    var isFavorite: Bool          // 是否收藏（显示在收藏 Tab）

    // 自定义 decoder：兼容旧数据（无 isFavorite 时默认 false）
    init(from decoder: Decoder) throws { ... }
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
    func saveBallPosition(_ position: BallPosition)
    func save()    // 持久化到 UserDefaults
    func load()    // 从 UserDefaults 加载

    // V3.0 新增：收藏
    func toggleFavorite(_ bundleID: String)     // 切换收藏状态
    var favoriteAppConfigs: [AppConfig]         // 收藏的 App 子集（计算属性）

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

### 2.5 HotkeyManager 契约

```swift
class HotkeyManager {
    static let shared = HotkeyManager()

    func registerAll()       // 注册所有全局快捷键
    func unregisterAll()     // 注销所有

    enum HotkeyAction: Int {
        case ballToggle = 6  // ⌘⇧B
    }
}
```

### 2.6 PermissionManager 契约

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

### 2.7 Constants.Notifications（集中管理的通知名）

```swift
enum Constants {
    enum Notifications {
        // 系统级通知
        static let appStatusChanged = Notification.Name("FocusCopilot.appStatusChanged")
        static let windowsChanged = Notification.Name("FocusCopilot.windowsChanged")
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
QuickPanelView（V3.0 交互模式）
     │
     │── Tab 切换（已选/收藏） ──▶ 切换 currentTab，刷新 buildContent()
     │── 点击单窗口 App 行 ──▶ WindowService.activateWindow(window)
     │── 点击多窗口 App 行 ──▶ 切换折叠/展开（collapsedApps）
     │── 点击窗口行 ──────────▶ highlightedWindowID = window.id
     │                        + WindowService.activateWindow(window)
     │── 点击未运行 App ──────▶ NSWorkspace.openApplication(at:configuration:)
     │── 右键窗口行 ──────────▶ 窗口重命名（NSAlert+NSTextField）
     │                         └── ConfigStore.windowRenames["{bundleID}::{title}"]
     │── 点击底部显隐按钮 ────▶ ballToggle 通知
     │── 点击底部退出按钮 ────▶ NSAlert 确认 + NSApplication.terminate()
     │
     │── 读取数据 ─────────────▶ AppMonitor.runningApps
     │                       ▶ ConfigStore.appConfigs（已选 Tab）
     │                       ▶ ConfigStore.favoriteAppConfigs（收藏 Tab）
     │                       ▶ ConfigStore.windowRenames

QuickPanelWindow
     │
     │── 顶部钉住按钮 ─────────▶ togglePanelPin()
     │── 顶部拖拽区域（24px）──▶ handlePanelDrag()（钉住时联动悬浮球）
     │── 边缘拖拽 resize ──────▶ ConfigStore.panelSize + save()
     │── hide() ────────────────▶ resetToNormalMode()（highlightedWindowID = nil）
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
| 正常显示 | ⌘⇧B / 底部按钮 | 隐藏 | 保存状态，发送 ballVisibilityChanged 通知 |

#### 快捷面板状态

| 当前状态 | 触发条件 | 目标状态 | 副作用 |
|---|---|---|---|
| 隐藏 | 悬浮球 hover 300ms | 显示（未钉住） | startWindowRefresh() |
| 隐藏 | 悬浮球单击 | 显示（钉住） | startWindowRefresh() |
| 显示（未钉住） | 鼠标离开 500ms | 隐藏 | stopWindowRefresh()，highlightedWindowID = nil |
| 显示（未钉住） | 悬浮球拖拽 | 隐藏 | stopWindowRefresh() |
| 显示（未钉住） | 点击钉住按钮 | 显示（钉住） | 取消 dismissTimer |
| 显示（钉住） | 悬浮球单击 | 隐藏 | 取消钉住，stopWindowRefresh() |
| 显示（钉住） | 点击钉住按钮 | 显示（未钉住） | 恢复自动收起 |
| 显示（钉住） | 鼠标离开 | 显示（钉住） | 不触发收起 |
| 显示（钉住） | 面板拖拽 | 显示（钉住） | 联动悬浮球同步移动 |

#### 窗口行高亮状态（V3.0）

| 当前状态 | 触发条件 | 目标状态 | 副作用 |
|---|---|---|---|
| 无高亮 | 点击窗口行 A | A 高亮 | WindowService.activateWindow(A) |
| A 高亮 | 点击窗口行 B | B 高亮 | A 取消高亮，WindowService.activateWindow(B) |
| A 高亮 | 面板关闭 | 无高亮 | resetToNormalMode() |
| A 高亮 | 点击已高亮行 A | A 高亮 | 保持不变，不做额外操作 |

### 4.2 通用边界行为

| 场景 | 处理 |
|---|---|
| App 配置已满 8 个 | 禁用添加按钮，提示先移除 |
| 未配置任何 App | 快捷面板显示空状态引导 |
| 辅助功能未授权 | 窗口标题获取和前置不可用，App 切换正常 |
| 窗口标题为空 | 四级兜底：AX 标题 → CG 标题 → 缓存 → "(无标题)" |
| App 图标获取失败 | 使用系统默认图标 |
| 多显示器 | 悬浮球限制在一个屏幕，拖拽不跨屏 |
| 未运行 App | 灰度显示，点击调用 NSWorkspace.openApplication 启动 |
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

---

## 5. 验收用例

### TC-01: Tab 切换

- **前置条件**：已配置 3+ 个 App，其中至少 1 个收藏
- **操作步骤**：打开快捷面板 → 切换到收藏 Tab → 确认仅显示收藏 App → 切换回已选 Tab
- **预期结果**：已选 Tab 显示全部配置 App，收藏 Tab 仅显示 isFavorite=true 的 App
- **覆盖**：正常路径

### TC-02: 窗口行高亮+前置

- **前置条件**：配置多窗口 App，面板打开
- **操作步骤**：点击窗口行 A → 确认高亮 → 点击窗口行 B → 确认 A 取消高亮 B 高亮
- **预期结果**：同一时间只有一个窗口行高亮，窗口被激活并前置
- **覆盖**：正常路径

### TC-03: 启动未运行 App

- **前置条件**：已配置一个未运行的 App
- **操作步骤**：点击灰度显示的 App 行
- **预期结果**：App 启动，列表更新为运行状态并显示窗口
- **覆盖**：正常路径

### TC-04: 底部悬浮球显隐

- **前置条件**：悬浮球可见
- **操作步骤**：点击底部"悬浮球 隐藏"按钮 → 确认悬浮球隐藏 → 按钮文案变为"悬浮球 显示"
- **预期结果**：悬浮球显隐切换正常，按钮文案实时更新
- **覆盖**：正常路径

### TC-05: 底部退出

- **前置条件**：App 运行中
- **操作步骤**：点击底部退出按钮
- **预期结果**：弹出 NSAlert 确认框，确认后 App 退出
- **覆盖**：正常路径

### TC-06: 收藏持久化

- **前置条件**：主看板 AppConfigView 中可见已选 App
- **操作步骤**：点击 App 旁的 ★ 切换收藏 → 重启 App → 检查收藏状态
- **预期结果**：isFavorite 通过 Codable 编码到 UserDefaults，重启后状态恢复
- **覆盖**：边界（持久化）

### TC-07: 高亮重置

- **前置条件**：面板打开，某窗口行高亮
- **操作步骤**：关闭面板 → 重新打开面板
- **预期结果**：所有窗口行高亮状态重置为无高亮
- **覆盖**：边界（状态清理）

### TC-08: 旧数据迁移

- **前置条件**：存在 V2.x 格式的 AppConfig 数据（无 isFavorite 字段）
- **操作步骤**：启动 App，加载配置
- **预期结果**：自定义 decoder 使用 decodeIfPresent，旧数据 isFavorite 默认 false
- **覆盖**：异常恢复（数据兼容）

---

## 6. 非目标声明

当前版本**不做**以下功能：

- 不实现收藏 Tab 独立排序（沿用 order）
- 不添加快捷面板搜索框
- 不添加窗口缩略图预览
- 不实现窗口分组
- 不实现插件系统
- 不实现网络请求（无遥测、无更新检查）

---

## 7. 文件清单与职责

| 文件 | 行数 | 职责 |
|---|---|---|
| PinTopApp.swift | ~16 | @main 入口，初始化 AppDelegate |
| AppDelegate.swift | ~330 | 应用生命周期、窗口管理、菜单栏图标、Dock 图标 |
| PermissionManager.swift | ~90 | 辅助功能权限检测、引导、后台轮询 |
| FloatingBallWindow.swift | ~98 | NSPanel 子类，窗口层级、贴边 |
| FloatingBallView.swift | ~770 | 悬浮球视图、品牌 Logo、hover/click/drag 检测 |
| QuickPanelWindow.swift | ~480 | NSPanel 子类，面板位置、钉住、resize、drag、联动 |
| QuickPanelView.swift | ~1100 | 面板内容：已选/收藏 Tab、窗口行高亮+前置、底部按钮、启动 App |
| MainKanbanWindow.swift | ~51 | NSWindow 子类，主看板窗口管理 |
| MainKanbanView.swift | ~90 | SwiftUI 根视图，侧边栏导航 + 底部双按钮 |
| AppConfigView.swift | ~440 | SwiftUI 快捷面板配置：App 选择、排序、收藏★切换 |
| PreferencesView.swift | ~130 | SwiftUI 偏好设置页面 |
| WindowService.swift | ~599 | 窗口枚举、AX 操作、CGS 层级、标题四级兜底、跨 App 激活 |
| AppMonitor.swift | ~210 | App 运行状态监控、窗口刷新定时器 |
| HotkeyManager.swift | ~60 | 全局快捷键（Carbon API），1 个动作（⌘⇧B） |
| ConfigStore.swift | ~175 | UserDefaults 持久化（含迁移逻辑、收藏管理） |
| Models.swift | ~110 | 数据模型定义（AppConfig 含 isFavorite） |
| Constants.swift | ~80 | 全局常量、13 个集中管理的通知名 |
| **合计** | **~4899** | |
