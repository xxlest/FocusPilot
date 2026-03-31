# FocusPilot 架构设计文档

> **版本**：V4.2
> **日期**：2026-03-31
> **基于**：PRD V4.2
> **关联文档**：[PRD.md](PRD.md)（产品需求）、[DesignGuide.md](DesignGuide.md)（设计规范）

---

## 1. 技术栈与模块划分

**技术栈**：Swift 5, macOS 14+, arm64, AppKit + SwiftUI, CGS Private API, AX API, Carbon API, DistributedNotificationCenter

### 文件结构

```
FocusPilot/
├── App/
│   ├── FocusPilotApp.swift           # @main 入口（~16 行）
│   ├── AppDelegate.swift             # 生命周期、窗口管理、菜单栏、快捷键、CoderBridgeService 初始化（~507 行）
│   └── PermissionManager.swift       # 辅助功能权限检测（~92 行）
├── FloatingBall/
│   ├── FloatingBallWindow.swift      # NSPanel, 层级 statusWindow+100（~98 行）
│   └── FloatingBallView.swift        # 毛玻璃圆球、拖拽吸附、hover 弹出、品牌 Logo、进度环、AI 角标（~1098 行）
├── QuickPanel/
│   ├── QuickPanelWindow.swift        # NSPanel, 层级 statusWindow+50, 动画/钉住/resize（~671 行）
│   ├── QuickPanelView.swift          # UI 骨架、三 Tab 切换、reloadData、布局、hover 交互（~1553 行）
│   ├── QuickPanelRowBuilder.swift    # App 行/窗口行/AI Session 行构建（extension）（~1049 行）
│   ├── QuickPanelMenuHandler.swift   # 右键菜单、@objc 事件处理（extension）（~558 行）
│   └── QuickPanelTimerHandler.swift  # FocusByTime 计时器栏 UI + 弹窗 + 辅助类（extension）（~1055 行）
├── MainKanban/
│   ├── MainKanbanWindow.swift        # NSWindow 包裹 SwiftUI（~55 行）
│   ├── MainKanbanView.swift          # 侧边栏+内容区（~106 行）
│   ├── AppConfigView.swift           # 关注管理（三 Tab + 星标）（~310 行）
│   ├── PreferencesView.swift         # 偏好设置（快捷键、主题、外观）（~276 行）
│   └── BallPanelConfigView.swift     # 悬浮球/面板外观配置（~143 行）
├── Models/
│   ├── Models.swift                  # AppConfig, Preferences, AppTheme, ThemeColors 等（~539 行）
│   └── CoderSession.swift            # CoderSession, CoderTool, SessionStatus, HostKind 等（~209 行）
├── Services/
│   ├── ConfigStore.swift             # UserDefaults 持久化（~269 行）
│   ├── WindowService.swift           # 窗口枚举/操作（CGWindowList+AX）（~797 行）
│   ├── AppMonitor.swift              # App 运行监控、自适应刷新（~362 行）
│   ├── HotkeyManager.swift           # Carbon 全局快捷键（~68 行）
│   ├── FocusTimerService.swift       # 番茄钟状态机、引导休息（~411 行）
│   ├── CoderBridgeService.swift      # AI 编码工具会话管理（~494 行）
│   └── TodoService.swift             # Todo 看板数据服务（~269 行）
└── Helpers/
    └── Constants.swift               # Ball, Panel, Design Token, Notifications, Keys（~130 行）
```

**合计**：~11179 行，25 个 .swift 文件

### 模块职责

| 模块 | 职责 | 独立变化理由 |
|---|---|---|
| **App/** | 应用入口、生命周期、权限管理 | 应用级初始化逻辑独立于具体 UI |
| **FloatingBall/** | 悬浮球 UI、拖拽、贴边、hover、品牌 Logo、进度环、AI 角标 | 悬浮球交互逻辑独立变化频率高 |
| **QuickPanel/** | 快捷面板 UI、三 Tab（活跃/关注/AI）、Tab 记忆、窗口操作、AI 会话交互。extension 拆分为 RowBuilder（行构建）+ MenuHandler（右键菜单）+ TimerHandler（FocusByTime 计时器栏+弹窗） | 面板展示和交互独立于悬浮球 |
| **MainKanban/** | 主看板 SwiftUI 界面（关注管理 + 偏好设置） | SwiftUI 技术栈独立 |
| **Services/** | 底层服务（窗口操作、App 监控、快捷键、配置存储、番茄钟、AI 会话管理、Todo） | 业务逻辑层与 UI 层分离 |
| **Models/** | 数据模型 | 数据结构被多个模块共享 |
| **Helpers/** | 桥接头、常量、通知名、Keys | 基础设施 |

### 防过度设计自查

- [x] 文件数（25）<= 功能点数（38）
- [x] 无多余抽象层：Services 直接暴露方法，无 Protocol 包装
- [x] 没有为"未来可能"创建接口
- [x] 没有只有一个实现的抽象层

---

## 2. 数据模型

### 2.1 核心模型（Models.swift）

```swift
enum QuickPanelTab: String {
    case running    = "running"   // 活跃
    case favorites  = "favorites" // 关注
    case ai         = "ai"       // AI
}

struct AppConfig: Codable, Identifiable, Equatable {
    var id: String { bundleID }
    let bundleID: String
    var displayName: String
    var order: Int
    // 自定义 decoder 兼容旧数据（忽略旧 isFavorite / pinnedKeywords 字段）
}

class RunningApp: Identifiable, ObservableObject {
    var id: String { bundleID }
    let bundleID: String
    let localizedName: String
    let icon: NSImage
    let nsApp: NSRunningApplication?
    @Published var windows: [WindowInfo]
    @Published var isRunning: Bool
}

struct WindowInfo: Identifiable, Equatable {
    let id: CGWindowID
    let ownerBundleID: String
    let ownerPID: pid_t
    var title: String
    var bounds: CGRect
    var isMinimized: Bool
    var isFullScreen: Bool
}

struct InstalledApp: Identifiable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let icon: NSImage
    let url: URL
}

struct PanelSize: Codable { var width: CGFloat; var height: CGFloat }
struct BallPosition: Codable { var x: CGFloat; var y: CGFloat; var edge: ScreenEdge }
enum ScreenEdge: String, Codable { case top, bottom, left, right }

struct Preferences: Codable {
    var ballSize: CGFloat = 35
    var ballOpacity: CGFloat = 0.8
    var panelOpacity: CGFloat = 0.9
    var appTheme: AppTheme = .defaultWhite
    var launchAtLogin: Bool = false
    var hotkeyToggle: HotkeyConfig
    var autoRetractOnHover: Bool = true
    var panelAnimationSpeed: CGFloat = 0.25
    var multiBindApps: [String] = ["cursor", "vscode"]  // 允许多 session 共享窗口的 App
    // 自定义 CodingKeys 保留旧字段兼容解码
}

// 主题系统详见 DesignGuide.md §4
enum AppTheme: String, Codable, CaseIterable {
    case defaultWhite, warmIvory, mintGreen, lightBlue
    case classicDark, deepOcean, inkGreen, pureBlack
    var colors: ThemeColors
    var isDark: Bool
    var ballGradientColors: (light: NSColor, medium: NSColor, dark: NSColor)
    var panelMaterial: Int
}

struct ThemeColors {
    // 9 色槽，ns* (NSColor) + sw* (SwiftUI Color) 双套
    // nsBackground, nsSidebarBackground, nsAccent, nsTextPrimary,
    // nsTextSecondary, nsTextTertiary, nsRowHighlight, nsSeparator, nsFavoriteStar
}
```

### 2.2 AI 会话模型（CoderSession.swift）

```swift
enum CoderTool: String { case claude, codex, gemini }
enum SessionStatus: String { case registered, working, idle, done, error }
enum SessionLifecycle: String { case active, ended }
enum MatchConfidence: String { case high, none }
enum HostKind: String { case ide, terminal }

struct CoderSession: Identifiable {
    let sessionID: String
    var tool: CoderTool
    var cwd: String
    var cwdNormalized: String
    var hostApp: String
    var hostKind: HostKind
    var status: SessionStatus
    var lifecycle: SessionLifecycle
    var lastSeq: Int
    var lastUpdate: Date
    var lastInteraction: Date?
    var isRead: Bool = false
    var isDismissed: Bool = false

    var autoWindowID: CGWindowID?       // session.start 自动采样（弱绑定）
    var manualWindowID: CGWindowID?     // 用户手动确认（强绑定）

    // 计算属性
    var isActionable: Bool              // done: !isRead; idle/error: !isRead && !isDismissed
    var statusText: String              // "执行中"、"等待输入·已结束" 等
    func statusTextColor(theme:) -> NSColor
    func statusDotColor(theme:) -> NSColor
    var statusDotHasGlow: Bool
    var rowAlpha: CGFloat               // ended=0.4, done+isRead=0.6, dismissed=0.6
    var cwdBasename: String
    var sortDate: Date                  // lastInteraction ?? lastUpdate
    var preferenceKey: String           // tool::cwdNormalized::hostApp
}

struct SessionGroup {
    let cwdNormalized: String
    var displayName: String
    var sessions: [CoderSession]
}

struct CoderSessionPreference: Codable {
    let key: String                     // tool::cwdNormalized::hostApp
    var displayName: String
    var isPinned: Bool
}

enum HostAppMapping {
    static let hostToBundleID: [String: String]  // terminal→com.apple.Terminal, cursor→com.todesktop..., etc.
    static func bundleID(for:) -> String?
    static func hostApp(for:) -> String?
    static func displayName(for:) -> String
}
```

---

## 3. 接口契约

### 3.1 ConfigStore

```swift
class ConfigStore: ObservableObject {
    static let shared = ConfigStore()

    @Published var appConfigs: [AppConfig]        // 关注列表（有序）
    @Published var preferences: Preferences
    @Published var ballPosition: BallPosition
    @Published var windowRenames: [String: String] // "{bundleID}::{CGWindowID}" → 自定义名称
    @Published var panelSize: PanelSize
    @Published var lastPanelTab: String
    @Published var isBallVisible: Bool             // 运行时，不持久化

    func addApp(_ bundleID: String, displayName: String)
    func removeApp(_ bundleID: String)
    func reorderApps(_ ids: [String])
    func isFavorite(_ bundleID: String) -> Bool
    func saveLastPanelTab(_ tab: QuickPanelTab)    // 轻量单字段写入
    func saveBallPosition(_ position: BallPosition)
    func save()
    func load()

    // 迁移
    private func migrateFromPinTop()
    private func migrateToV31()
}
```

### 3.2 AppMonitor

```swift
class AppMonitor: ObservableObject {
    static let shared = AppMonitor()

    @Published var runningApps: [RunningApp]
    @Published var installedApps: [InstalledApp]

    func startMonitoring()
    func stopMonitoring()
    func refreshRunningApps()          // 不依赖 ConfigStore
    func refreshAllWindows()
    func refreshWindows(for bundleID: String)
    func scanInstalledApps()           // 后台线程扫描
    func isRunning(_ bundleID: String) -> Bool
    func startWindowRefresh()          // 面板显示时 1s 间隔
    func stopWindowRefresh()           // 面板隐藏时停止
}
```

### 3.3 WindowService

```swift
class WindowService {
    static let shared = WindowService()

    // 窗口枚举
    func listWindows(for bundleID: String) -> [WindowInfo]
    func listAllWindows() -> [WindowInfo]

    // 窗口操作
    func activateWindow(_ window: WindowInfo)      // NSWorkspace.openApplication + AXRaise/AXMain/AXFocused
    func activateApp(_ bundleID: String)            // 不需要辅助功能权限
    func closeWindow(_ window: WindowInfo)          // AX kAXCloseButtonAttribute → AXPressAction

    // AX 窗口查找
    func findAXWindow(pid: pid_t, windowID: CGWindowID) -> AXUIElement?

    // AX 可用性
    func isAXApiAvailable() -> Bool                // 3 秒缓存

    // 关键实现细节：
    // - buildAXTitleMap：四级标题兜底（AX → CG → 缓存 → "(无标题)"）
    // - activateWindow：NSWorkspace.openApplication → raiseAndFocusWindowViaAX → 150ms 重试 → 300ms 兜底
    // - 两阶段刷新：Phase 1 CG 标题主线程快速渲染 → Phase 2 AX 标题后台补全
}
```

### 3.4 HotkeyManager

```swift
class HotkeyManager {
    static let shared = HotkeyManager()
    var onToggle: (() -> Void)?

    func register(config: HotkeyConfig? = nil)
    func unregister()
    func reregister(config: HotkeyConfig)
}
```

### 3.5 PermissionManager

```swift
class PermissionManager: ObservableObject {
    static let shared = PermissionManager()
    @Published var accessibilityGranted: Bool = false

    func checkAccessibility() -> Bool   // 实时检查，不可缓存
    func requestAccessibility()
    func startPolling()
    func stopPolling()
}
```

### 3.6 FocusTimerService

```swift
final class FocusTimerService: ObservableObject {
    static let shared = FocusTimerService()

    @Published var status: FocusTimerStatus       // .idle / .running / .paused
    @Published var phase: FocusTimerPhase          // .work / .rest
    @Published var remainingSeconds: Int
    @Published var workMinutes: Int                // 持久化
    @Published var restMinutes: Int                // 持久化
    @Published var pendingAction: FocusPendingAction

    // 引导休息
    @Published var restMode: RestMode             // .free / .guided
    @Published var currentStepIndex: Int
    var guidedSteps: [RestStep]
    var restIntensity: RestIntensity              // 持久化

    // 计算属性
    var progress: CGFloat
    var displayTime: String
    var stepDisplayTime: String
    var phaseLabel: String

    // 控制
    func start()
    func pause()
    func resume()
    func reset()
    func startRestPhase()
    func startGuidedRest(intensity:)
    func startStandaloneRestFree()
    func startStandaloneGuidedRest(intensity:)

    // 通知：focusTimerChanged / focusWorkCompleted / focusRestCompleted / focusGuidedStepChanged
}
```

### 3.7 CoderBridgeService

```swift
class CoderBridgeService: NSObject {
    static let shared = CoderBridgeService()

    private(set) var sessions: [CoderSession]

    // BindingState 统一 helper
    enum BindingState { case manual, autoValid, autoConflicted, missing }
    func bindingState(for session: CoderSession) -> BindingState
    func allowsSharedBinding(for session: CoderSession) -> Bool  // 读取 multiBindApps 白名单

    // 生命周期
    func start()   // 注册 DistributedNotification + 30s 清理定时器

    // 会话查询
    var groupedSessions: [SessionGroup]          // 按 cwdNormalized 分组，支持置顶
    var actionableCount: Int                      // 未读可操作会话数
    func transcriptPath(for:) -> String?
    func latestQuerySummary(for:maxLength:) -> String?  // 5s 缓存

    // 窗口解析
    func resolveWindowForSession(_:) -> (CGWindowID?, MatchConfidence)
    func windowExists(_:) -> Bool
    func isAutoWindowConflicted(for:) -> Bool

    // 会话操作
    var activeSessionID: String?                  // 最近成功切换的 session
    func markAsRead(sid:)
    func dismissSession(sid:)                     // isDismissed = true
    func updateLastInteraction(sid:)
    func bindSessionToWindow(sid:windowID:)       // 独占类驱逐旧绑定
    func clearManualWindowID(sid:)
    func clearAutoWindowID(sid:)
    func removeSession(_:)
    func removeEndedSessions()

    // 置顶
    var pinnedGroups: [String]
    var pinnedSessions: [String]
    func pinGroup(_:)
    func pinSession(_:)
}
```

### 3.8 Constants

```swift
enum Constants {
    enum Ball { ... }      // defaultSize=40, hoverDelay=0.15 等
    enum Panel { ... }     // width=280, cornerRadius=14, timerBarHeight=46 等
    enum Design {
        enum Spacing { ... }  // xs=4, sm=8, md=12, lg=16, xl=24
        enum Corner { ... }   // sm=4, md=6, lg=10, xl=14
        enum Anim { ... }     // micro=0.1, fast=0.15, normal=0.25
    }

    enum Keys {
        static let appConfigs, preferences, ballPosition, onboardingCompleted,
                   windowRenames, panelSize, lastPanelTab,
                   focusTimerSettings, focusRestIntensity,
                   sessionPreferences: String
    }

    enum Notifications {
        // 系统：appStatusChanged, windowsChanged, ballVisibilityChanged, accessibilityGranted
        // 悬浮球：ballShowQuickPanel, ballToggle, ballOpenMainKanban, ballDragStarted,
        //        ballDragMoved, ballMouseExited, ballToggleQuickPanel
        // 面板：panelPinStateChanged, panelDragMoved
        // 主题：themeChanged
        // 番茄钟：focusTimerChanged, focusWorkCompleted, focusRestCompleted, focusGuidedStepChanged
        // AI：coderBridgeSessionChanged
        // 偏好：showPreferencesMultiBind
    }
}
```

---

## 4. 模块间交互

### 4.1 FloatingBall → QuickPanel

```
FloatingBallView                   QuickPanelWindow
     │── mouseEntered ───────────▶ AppMonitor.startWindowRefresh()（预热）
     │── hover 150ms ────────────▶ show(relativeTo: ballFrame)
     │── click ──────────────────▶ toggleQuickPanel
     │── double-click ──────────▶ MainKanbanWindow.toggleMainKanban()
     │── drag-start ────────────▶ hide()
     │◀── mouseExited(500ms) ───── hide()（钉住/autoRetractOnHover=false 时跳过）
```

### 4.2 QuickPanel → Services

```
QuickPanelView
     │── Tab hover（非固定）──────▶ displayTab 临时切换
     │── Tab 点击 ───────────────▶ selectedTab + ConfigStore.saveLastPanelTab()
     │── App 行 hover（非固定）──▶ hoverExpandedBundleID（展开）
     │── 点击窗口行 ──────────────▶ WindowService.activateWindow()
     │── 点击 Session 行 ─────────▶ CoderBridgeService.resolveWindowForSession() → activateWindow
     │── 右键窗口行 ──────────────▶ 窗口重命名 → ConfigStore.windowRenames
     │── 右键 App 行 ──────────────▶ handleTerminateApp()
     │── 右键 Session 行 ──────────▶ 绑定/解绑/忽略/移除 → CoderBridgeService
     │── 点击顶部主界面按钮 ──────▶ ballOpenMainKanban 通知
```

### 4.3 MainKanban 交互

```
MainKanbanView
     │── 侧边栏 Tab ──────▶ 关注管理 / 偏好设置
     │── 左半按钮 ─────────▶ ballToggle 通知
     │── 右半按钮 ─────────▶ 确认对话框 → NSApplication.terminate()

AppConfigView
     │── 点击★ ────────────▶ ConfigStore.addApp() / removeApp()
```

### 4.4 Coder-Bridge 事件流

```
coder-bridge shell hook（Claude Code / Codex / Gemini CLI）
  → osascript DistributedNotification("com.focuscopilot.coder-bridge")
  → CoderBridgeService.handleDistributedNotification(_:)
    ├─ session.start: 创建 CoderSession + resolveFrontmostWindow → autoWindowID
    ├─ session.update: 更新 status + 重置 isRead/isDismissed（状态变化时）
    └─ session.end: lifecycle → .ended
  → postSessionChanged()
  → NotificationCenter: coderBridgeSessionChanged
    ├─ QuickPanelView.reloadData()（AI Tab 刷新）
    └─ FloatingBallView（AI 角标刷新）
```

### 4.5 主题刷新链路

```
PreferencesView → @Published → AppDelegate.applyPreferences()
  → NSApp.appearance（浅色/深色）
  → ballView.updateColorStyle()
  → quickPanelWindow.applyTheme()
  → panelView.forceReload()
  → post themeChanged
```

---

## 5. 行为约束

### 5.1 悬浮球状态转换

| 当前状态 | 触发 | 目标状态 | 副作用 |
|---|---|---|---|
| 正常 | mouseEntered | 正常 | startWindowRefresh() |
| 正常 | hover 150ms | 正常+面板弹出 | show()（已钉住时跳过） |
| 正常 | 单击 | 正常 | 切换面板钉住状态 |
| 正常 | 双击 | 正常 | 切换主看板 |
| 正常 | 拖拽开始 | 拖拽中 | 关闭面板 |
| 拖拽中 | 拖拽结束 | 正常 | 吸附+保存位置 |
| 正常 | 贴边 | 贴边半隐藏 | 收入一半 |
| 贴边 | 鼠标靠近 | 正常 | 滑出 |
| 隐藏 | ⌘⇧B | 正常 | 恢复位置 |
| 正常 | ⌘⇧B / 按钮 | 隐藏 | ballVisibilityChanged |

### 5.2 快捷面板状态转换

| 当前状态 | 触发 | 目标状态 | 副作用 |
|---|---|---|---|
| 隐藏 | hover 150ms | 显示（未钉住） | startWindowRefresh，恢复 lastPanelTab |
| 隐藏 | 单击 | 显示（钉住） | startWindowRefresh |
| 显示（未钉住） | 离开 500ms | 隐藏 | stopWindowRefresh，reset |
| 显示（未钉住） | autoRetractOnHover=false | 保持 | 不触发 dismissTimer |
| 显示（钉住） | 单击 | 隐藏 | 取消钉住 |
| 显示（钉住） | 离开 | 保持 | — |

### 5.3 FocusByTime 状态转换

| 当前状态 | 触发 | 目标状态 | 副作用 |
|---|---|---|---|
| idle | 开始专注 | running(work) | 保存时长，启动 Timer |
| running(work) | 暂停 | paused(work) | 停止 Timer |
| paused(work) | 继续 | running(work) | 恢复 Timer |
| running/paused | 停止确认 | idle | 清除 Timer + pendingAction |
| running(work) | 归零 | paused(work) | pendingAction=.startRest, 发 focusWorkCompleted |
| paused(work) | 开始休息 | running(rest) | 清除 pendingAction |
| paused(work) | 直接结束 | idle | 清除 pendingAction |
| idle | 独立休息 | running(rest, standalone) | isStandaloneRest=true |
| running(rest) | 归零 | idle | 非独立→pendingAction=.startWork, 独立→直接 idle |

### 5.4 AI 会话生命周期

| 事件 | 状态迁移 | 副作用 |
|---|---|---|
| session.start | → registered + active | autoWindowID 采样 |
| session.update(working) | → working | — |
| session.update(idle) | → idle | isRead=false, isDismissed=false |
| session.update(done) | → done | isRead=false |
| session.update(error) | → error | isRead=false, isDismissed=false |
| session.end | → lifecycle=ended | 保留 status |
| markAsRead | — | isRead=true |
| dismissSession | — | isDismissed=true |
| 清理（ended>2min / 僵尸>30s） | 移除 | — |

### 5.5 跨 App 窗口激活（V3.2）

```
activateWindow(window)
  → app.isHidden → unhide()
  → NSWorkspace.openApplication(activates: true)
  → raiseAndFocusWindowViaAX (AXRaise + AXMain + AXFocused)
  → 150ms 后再次 raiseAndFocusWindowViaAX
  → 300ms 后检查 frontmostApplication → 兜底重试
```

### 5.6 通用边界行为

| 场景 | 处理 |
|---|---|
| 窗口标题为空 | 四级兜底：AX → CG → 缓存 → "(无标题)" |
| App 图标获取失败 | 系统默认图标 |
| codesign 导致权限失效 | PermissionManager 后台轮询，自动恢复 |
| 未运行 App（关注 Tab） | 灰度显示，点击 NSWorkspace.openApplication 启动 |

---

## 6. 关键设计决策

| 决策 | 理由 |
|---|---|
| **通知驱动架构** | FloatingBall → AppDelegate → QuickPanel 解耦，避免循环引用 |
| **两阶段窗口刷新** | Phase 1 CG 快速渲染不阻塞 UI，Phase 2 AX 后台补全精确标题 |
| **差分 UI 更新** | buildStructuralKey 对比，标题变化走轻量路径 updateWindowTitles |
| **forceReload() 封装** | 统一强制全量刷新入口，封装 lastStructuralKey 清除细节 |
| **prepareForShow() 兜底** | 面板显示前清理临时态，防止 hide 动画竞态导致 displayTab 残留 |
| **窗口标题四级解析** | AX → 缓存 AX → CG → "(无标题)"，权限丢失时回退到位置匹配 |
| **自适应刷新** | 面板显示 1s，无变化逐步降至 3s；隐藏时完全停止 |
| **QuickPanel 模块化** | extension 拆分（RowBuilder + MenuHandler），不引入新类型 |
| **Tab 双状态模型** | selectedTab（持久）+ displayTab（渲染态），hover 预览不污染持久状态 |
| **Hover 展开/折叠** | hoverExpandedBundleID 驱动，isHidden 切换不触发 forceReload |
| **CoderSession 不持久化** | 纯运行时，重启后清空（AI 工具中断后需重新启动注册） |
| **HostKind 策略分化** | IDE 允许多 session 共享窗口（多终端 tab），Terminal 独占 |
| **BindingState 统一 helper** | 枚举消除 UI/窗口切换/绑定引导三处重复判断 |
| **两条绑定入口差异化** | 点击（隐式）对 terminal 冲突拦截；右键（显式）允许确认替换 |
| **isDismissed 与 isRead 双标记** | done 仅受 isRead 控制，idle/error 受双重控制，粒度更细 |
| **僵尸 session 清理** | registered 超 30s 无后续→自动移除，防止 coder-bridge 异常退出残留 |
| **弹窗统一失焦关闭** | didResignActiveNotification → abortModal，PendingAction 保留上下文 |
| **弹窗层级处理** | NSAlert.runModal() 重置 level，通过 didBecomeKey 延迟设置 alertLevel |

---

## 7. 配置迁移

| 版本 | 迁移内容 |
|---|---|
| V2.0 | com.pintop.PinTop → com.focuspilot.FocusPilot |
| V3.1 | appConfigs 含 isFavorite → 仅保留关注 |
| V3.7 | Preferences 移除 colorTheme/ballColorStyle，新增 appTheme |
| V3.8 | 新增 FocusTimerService + 计时器栏 + 进度环 |
| V3.9 | 新增引导休息（RestStep/RestMode/RestIntensity） |
| V4.0 | 新增 coder-bridge + CoderBridgeService + AI Tab |
| V4.1 | 新增 hostKind + BindingState + IDE/Terminal 策略分化 |
| V4.2 | Tab 双状态 + hover 展开/折叠 + AI 角标 + isDismissed |

---

## 8. 验收用例

### TC-01: Tab 切换与记忆

- 打开面板 → 切换到关注 Tab → 关闭 → 重新打开
- 预期：恢复到关注 Tab

### TC-02: 窗口行高亮+前置

- 点击窗口行 A → 高亮 → 点击 B → A 取消高亮 B 高亮
- 预期：同时只有一个高亮，窗口前置

### TC-03: 启动未运行 App

- 关注 Tab → 点击灰度 App → 预期：启动并刷新窗口

### TC-04: 窗口关闭

- 窗口行 ✕ → 确认 → 预期：窗口关闭，列表刷新

### TC-05: 关注管理持久化

- 主看板添加关注 → 重启 → 预期：关注恢复

### TC-06: FocusByTime 弹窗失焦

- 编辑弹窗打开 → 切换应用 → 预期：弹窗关闭，pending 保留

### TC-07: AI 会话生命周期

- session.start → 列表出现 registered → session.update(working) → 状态更新 → session.end → ended 显示
- 预期：状态实时刷新，ended 2 分钟后自动清理

### TC-08: AI 窗口绑定策略

- Terminal session 自动采样 → 第二个 session 同窗口 → 预期：冲突标记
- IDE session 自动采样 → 第二个 session 同窗口 → 预期：无冲突，正常共享

### TC-09: isDismissed 忽略提醒

- idle session → 右键"忽略提醒" → 预期：降灰，不计角标
- session.update(working) → session.update(idle) → 预期：isDismissed 重置

---

## 9. 非目标声明

当前版本**不做**：

- 快捷面板搜索框
- 窗口缩略图预览
- 窗口分组
- 插件系统
- 网络请求（无遥测、无更新检查）
- AI 会话持久化（重启后清空）
