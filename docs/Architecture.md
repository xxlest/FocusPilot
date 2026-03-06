# Focus Copilot 架构设计文档

> **版本**：V3.8
> **日期**：2026-03-06
> **基于**：PRD V3.8

---

## 1. 模块划分

### 总览

```
FocusPilot/
├── FocusPilot/
│   ├── App/
│   │   ├── AppDelegate.swift          # 应用生命周期、窗口管理、菜单栏图标
│   │   ├── FocusPilotApp.swift        # @main 入口
│   │   └── PermissionManager.swift    # 辅助功能权限检测与引导
│   ├── FloatingBall/
│   │   ├── FloatingBallWindow.swift   # 悬浮球窗口（NSPanel）
│   │   └── FloatingBallView.swift     # 悬浮球视图、拖拽、贴边、hover、品牌 Logo
│   ├── QuickPanel/
│   │   ├── QuickPanelWindow.swift     # 快捷面板窗口（NSPanel），钉住模式、resize、drag
│   │   └── QuickPanelView.swift       # 面板内容视图（活跃/关注 Tab、窗口行高亮+前置+关闭、Tab 记忆、FocusByTime 计时器栏）
│   ├── MainKanban/
│   │   ├── MainKanbanWindow.swift     # 主看板窗口管理
│   │   ├── MainKanbanView.swift       # 主看板根视图（SwiftUI），侧边栏+底部双按钮
│   │   ├── AppConfigView.swift        # 关注管理页面（SwiftUI），三 Tab 过滤 + 星标关注切换
│   │   └── PreferencesView.swift      # 偏好设置页（SwiftUI）
│   ├── Services/
│   │   ├── WindowService.swift        # 窗口枚举、AX 操作、层级控制、关闭窗口、诊断日志
│   │   ├── AppMonitor.swift           # 监听 App 启动/退出，维护运行列表（不依赖 ConfigStore）
│   │   ├── HotkeyManager.swift        # 全局快捷键注册（Carbon API，支持多快捷键）
│   │   ├── ConfigStore.swift          # 用户配置持久化（UserDefaults）、关注管理、Tab 记忆
│   │   └── FocusTimerService.swift   # FocusByTime 番茄钟（状态机、计时、阶段切换通知、时长持久化、FocusPendingAction）
│   ├── Models/
│   │   └── Models.swift               # 数据模型定义
│   ├── Helpers/
│   │   ├── CGSPrivate.h               # Private API 桥接头
│   │   └── Constants.swift            # 全局常量、通知名、窗口层级、UserDefaults Keys
│   ├── Resources/
│   │   ├── Assets.xcassets/           # 图标资源
│   │   └── FocusPilot.entitlements     # 权限配置
│   └── Info.plist
├── FocusPilot.xcodeproj/
└── docs/
    ├── PRD.md
    └── Architecture.md
```

### 版本变更说明

**V3.8 相比 V3.7 的关键变更**：

- 新增 `FocusTimerService.swift`：番茄钟单例服务，管理 idle/running/paused 状态机 × work/rest 阶段，Timer 计时，FocusPendingAction 保留弹窗失焦后的待处理动作，通过 NotificationCenter 通知 UI 层
- Constants：新增 `Keys.focusTimerSettings`、`Notifications.focusTimerChanged`/`focusWorkCompleted`/`focusRestCompleted`
- FloatingBallView：新增 `CAShapeLayer` 进度环（工作=accent，休息=green），`handleFocusTimerChanged` 通知处理
- FloatingBallView：品牌 Logo 重设计为十字准星图标（外环+内环+中心点+4 刻度线），accent 光晕阴影，hover 缩放反馈
- QuickPanelView：底部新增 44px 计时器栏（timerBar），idle 状态显示时长摘要 + play.circle 按钮，运行状态显示阶段/倒计时/进度条 + 暂停/停止按钮
- QuickPanelView：编辑弹窗含 +/- 按钮、推荐方案 radio 行（深度专注/常规节奏/轻度脑力），手动修改时自动取消 radio 选中
- QuickPanelView：所有弹窗（编辑/工作完成/休息结束）失焦自动关闭（`didResignActiveNotification` → `abortModal`）
- QuickPanelView：工作完成弹窗含科学休息指南 accessoryView（5 条建议），休息结束弹窗文案"⚡ 充电完毕"
- QuickPanelView：阶段完成弹窗失焦关闭后，计时器栏显示 pending 状态（"工作完成 · 开始休息" / "休息结束 · 继续工作"）+ 快捷操作按钮
- Models.swift：默认白主题 accent 从蓝色(#2383E2)改为红色(#E53935)
- AppDelegate：启动时自动展开快捷面板并钉住
- 新增 `TimerEditHelper` 辅助类（`NSTextFieldDelegate`，处理 +/- 和推荐方案事件）

**V3.7 相比 V3.6 的关键变更**：

- Models.swift：新增 `AppTheme`（8 个 Notion 风格主题枚举）和 `ThemeColors`（8 色槽结构体，ns* + sw* 双套属性）
- Preferences：新增 `appTheme: AppTheme = .defaultWhite`，移除 `colorTheme`/`ballColorStyle`/`ballCustomColorHex`（保留旧 CodingKey 兼容解码）
- Constants：新增 `themeChanged` 通知名
- ConfigStore：新增 `currentThemeColors` 便捷属性
- QuickPanelWindow：新增 `effectView`/`bgOverlayView` 实例属性 + `applyTheme()` 方法，背景色叠加半透明主题层
- QuickPanelView：所有 `.labelColor`/`.secondaryLabelColor`/`.controlAccentColor` 替换为 `colors.nsTextPrimary`/`nsTextSecondary`/`nsAccent`，新增 `applyTheme()` 方法
- QuickPanelRowBuilder：`.systemYellow` → `colors.nsFavoriteStar`，运行状态点改为 NSView 圆点（主题色）替代 emoji
- FloatingBallView：`currentGradientColors()` 改为读取 `appTheme.ballGradientColors`，不再依赖 BallColorStyle
- PreferencesView：移除"悬浮球颜色"6 色圆点 + 自定义取色器 + "颜色主题" Picker，新增浅色 4 卡片 + 深色 4 卡片的主题选择网格
- AppConfigView：运行状态点 → `swAccent`，关注星标 → `swFavoriteStar`
- MainKanbanView：侧边栏背景 → `swBackground`
- AppDelegate.applyPreferences：设置 `NSApp.appearance`（浅色/深色），调用 `quickPanelWindow.applyTheme()`，发送 `themeChanged` 通知

**主题切换刷新链路**：
```
PreferencesView → @Published → AppDelegate.applyPreferences()
  → NSApp.appearance 更新 → ballView.updateColorStyle()
  → quickPanelWindow.applyTheme() → panelView.forceReload()
  → post themeChanged 通知
```

**V3.3 相比 V3.2 的关键变更**：

- QuickPanelView：删除 `panelPinButton` 及所有关联代码（`togglePanelPin`、`updatePanelPinButton`、`rotatedPinImage`、`panelPinStateChanged` 监听）
- QuickPanelView 顶部栏布局：`openKanbanButton` 从左侧移到右侧（`trailingAnchor - 8`），Tab 按钮成为最左侧元素（`leadingAnchor + 32`）
- FloatingBallView：新增 `pinGlowLayer`（红色发光边框环 CALayer），通过 `panelPinStateChanged` 通知驱动显隐和脉冲动画
- Preferences：新增 `autoRetractOnHover: Bool = true`，控制 hover 离开后是否自动收起面板
- QuickPanelWindow.ballMouseExited()：新增 `autoRetractOnHover` 检查（钉住优先 → 回缩开关 → dismissTimer）
- QuickPanelView.mouseExited()：同步新增 `autoRetractOnHover` 检查
- PreferencesView：新增 Toggle "hover 离开后自动收起面板"

**V3.2 相比 V3.0 的关键变更**：

- QuickPanelTab 枚举：`.selected/.favorites` → `.running/.favorites`（移除 `.all`）
- AppConfig 移除 `isFavorite` 字段（在 `appConfigs` 中即为关注）
- ConfigStore 移除 `toggleFavorite` / `favoriteAppConfigs`，新增 `isFavorite()` / `saveLastPanelTab()` / `lastPanelTab`
- AppMonitor.refreshRunningApps() 不再依赖 ConfigStore，直接遍历所有 regular App
- WindowService: `activateWindow` 改用 `NSWorkspace.openApplication`；新增 `raiseAndFocusWindowViaAX`、`closeWindow`
- QuickPanelView：两个 Tab（活跃/关注）、Tab 记忆、窗口行关闭按钮、移除底部按钮栏、移除面板内关注操作
- AppConfigView 重写为关注管理页面（三 Tab：全部/活跃/关注 + 显示数量）
- MainKanban Tab 标题改为"关注管理"
- V3.1 数据迁移：`migrateToV31` 保留旧 `isFavorite==true` 的 App
- Constants 新增 `Keys.lastPanelTab`

**V3.0 相比 V2.1 的变更**：

- 彻底移除 Pin（标记/置顶）概念
- 删除 `PinManager.swift` 和 `PinManageView.swift`

### 模块职责与拆分理由

| 模块 | 职责 | 独立变化理由 |
|---|---|---|
| **App/** | 应用入口、生命周期、权限管理 | 应用级初始化逻辑独立于具体 UI |
| **FloatingBall/** | 悬浮球 UI、拖拽、贴边、hover 检测、品牌 Logo、钉住状态发光边框 | 悬浮球交互逻辑独立变化频率高 |
| **QuickPanel/** | 快捷面板 UI、活跃/关注 Tab、Tab 记忆、窗口行高亮+前置+关闭（V3.3：移除面板内钉住按钮） | 面板展示和交互独立于悬浮球 |
| **MainKanban/** | 主看板 SwiftUI 界面（关注管理 + 偏好设置 + 底部双按钮） | SwiftUI 技术栈独立，页面布局频繁调整 |
| **Services/** | 底层服务（窗口操作+关闭、App 监控、快捷键、配置存储+Tab 记忆、FocusByTime 计时） | 业务逻辑层与 UI 层分离 |
| **Models/** | 数据模型 | 数据结构被多个模块共享 |
| **Helpers/** | 桥接头、常量、通知名、UserDefaults Keys | 基础设施，极少变化 |

### 防过度设计自查

- [x] 文件数（~18）<= 功能点数（34）
- [x] 无多余抽象层：Services 直接暴露方法，无 Protocol 包装
- [x] 没有为"未来可能"创建接口
- [x] 没有只有一个实现的抽象层

---

## 2. 接口契约

### 2.1 数据模型（Models.swift）

```swift
// 快捷面板 Tab 枚举（V3.2：.running/.favorites）
enum QuickPanelTab: String {
    case running    = "running"   // 活跃
    case favorites  = "favorites" // 关注
}

// App 配置（持久化）
// V3.2：移除 isFavorite 字段，在 appConfigs 中即为关注
struct AppConfig: Codable, Identifiable, Equatable {
    var id: String { bundleID }
    let bundleID: String          // App 唯一标识
    var displayName: String       // 自定义显示名称
    var order: Int                // 快捷面板中的排序

    // 自定义 decoder：兼容旧数据（忽略旧 isFavorite / pinnedKeywords 字段）
    init(from decoder: Decoder) throws { ... }
    init(bundleID: String, displayName: String, order: Int)
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
    var ballSize: CGFloat = 35        // 30-60px
    var ballOpacity: CGFloat = 0.8    // 0.3-1.0
    var panelOpacity: CGFloat = 0.9   // 0.3-1.0（快捷面板透明度）
    var appTheme: AppTheme = .defaultWhite  // V3.7：Notion 风格主题
    var launchAtLogin: Bool = false
    var autoRetractOnHover: Bool = true  // V3.3：hover 离开后是否自动收起面板
    var hotkeyToggle: HotkeyConfig
    var hotkeyKanban: HotkeyConfig
    var panelAnimationSpeed: CGFloat = 0.25
    // 自定义 CodingKeys 保留旧字段（colorTheme/ballColorStyle/ballCustomColorHex）兼容解码
}

// V3.7：Notion 风格主题（8 种预设）
enum AppTheme: String, Codable, CaseIterable {
    case defaultWhite, warmIvory, mintGreen, lightBlue  // 浅色
    case classicDark, deepOcean, inkGreen, pureBlack    // 深色
    var colors: ThemeColors       // 8 色槽（background, accent, textPrimary, ...)
    var isDark: Bool
    var ballGradientColors        // 从 accent 自动派生
    var panelMaterial: Int        // .light=1 / .dark=2
}

struct ThemeColors {
    // NSColor 属性：nsBackground, nsAccent, nsTextPrimary, nsTextSecondary, nsTextTertiary, nsRowHighlight, nsSeparator, nsFavoriteStar
    // SwiftUI 扩展：swBackground, swAccent, swTextPrimary, ...
}

// 旧枚举保留定义不删（兼容），新代码不再引用
enum ColorTheme: String, Codable, CaseIterable { ... }
enum BallColorStyle: String, Codable, CaseIterable { ... }
```

### 2.2 ConfigStore 契约

```swift
class ConfigStore: ObservableObject {
    static let shared = ConfigStore()

    // 关注 App 列表（有序，在列表中即为关注）
    @Published var appConfigs: [AppConfig]

    // 偏好设置
    @Published var preferences: Preferences

    // 悬浮球位置
    @Published var ballPosition: BallPosition

    // Onboarding 是否已完成
    @Published var onboardingCompleted: Bool

    // 窗口重命名映射（key="{bundleID}::{CGWindowID}", value=自定义名称）
    @Published var windowRenames: [String: String]

    // 面板大小（拖拽 resize 后持久化）
    @Published var panelSize: PanelSize

    // 快捷面板上次选择的 Tab（持久化，面板关闭再打开时恢复）
    @Published var lastPanelTab: String    // QuickPanelTab.rawValue

    // 悬浮球显隐状态（运行时，不持久化）
    @Published var isBallVisible: Bool

    // CRUD 操作
    func addApp(_ bundleID: String, displayName: String)
    func removeApp(_ bundleID: String)
    func reorderApps(_ ids: [String])
    func saveBallPosition(_ position: BallPosition)
    func save()    // 持久化到 UserDefaults
    func load()    // 从 UserDefaults 加载

    // V3.2 关注查询
    func isFavorite(_ bundleID: String) -> Bool    // 在 appConfigs 中即为关注

    // V3.2 面板 Tab 记忆
    func saveLastPanelTab(_ tab: QuickPanelTab)    // 轻量单字段写入，不触发全量 save

    // 配置迁移
    private func migrateFromPinTop()               // PinTop → FocusCopilot
    private func migrateToV31()                    // V3.1 迁移：仅保留 isFavorite==true 的 App
}
```

**UserDefaults Keys**：`FocusCopilot.appConfigs`、`FocusCopilot.preferences`、`FocusCopilot.ballPosition`、`FocusCopilot.onboardingCompleted`、`FocusCopilot.windowRenames`、`FocusCopilot.panelSize`、`FocusCopilot.lastPanelTab`

### 2.3 AppMonitor 契约

```swift
class AppMonitor: ObservableObject {
    static let shared = AppMonitor()

    // 运行中的 App 列表（所有 regular App，不依赖 ConfigStore）
    @Published var runningApps: [RunningApp]

    // 已安装 App 列表
    @Published var installedApps: [InstalledApp]

    func startMonitoring()        // 注册 NSWorkspace 通知
    func stopMonitoring()         // 注销通知

    // V3.2：直接遍历所有 regular App，不依赖 ConfigStore
    func refreshRunningApps()     // 刷新运行中 App 列表（排除自身，按名称排序）
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
    // V3.2：使用 NSWorkspace.openApplication 激活 App（系统级 API）
    func activateWindow(_ window: WindowInfo)  // 激活并前置窗口
    func activateApp(_ bundleID: String)       // 激活 App（不需要权限）

    // V3.2 新增：关闭窗口（通过 AX API 获取关闭按钮并点击）
    func closeWindow(_ window: WindowInfo)

    // V3.2 新增：提升并聚焦窗口（AXRaise + AXMain + AXFocused）
    private func raiseAndFocusWindowViaAX(_ window: WindowInfo)
    private func raiseAndFocusAXWindow(_ axWindow: AXUIElement, wid: CGWindowID)

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
    // activateWindow 跨 App 激活机制（V3.2）：
    //   NSWorkspace.openApplication(activates: true) → raiseAndFocusWindowViaAX
    //   → 150ms 后再次 raiseAndFocusWindowViaAX
    //   → 300ms 后检查 frontmostApplication → yieldActivation + activate 兜底重试
    //
    // raiseAndFocusWindowViaAX 实现：
    //   AXRaise → kAXMainAttribute=true → kAXFocusedAttribute=true
    //   优先通过 CGWindowID 精确匹配，回退到位置匹配
    //
    // closeWindow 实现：
    //   findAXWindow → kAXCloseButtonAttribute → AXPressAction
}
```

### 2.5 HotkeyManager 契约

```swift
class HotkeyManager {
    static let shared = HotkeyManager()

    func registerAll()       // 注册所有全局快捷键
    func unregisterAll()     // 注销所有

    var onAction: ((HotkeyAction) -> Void)?

    enum HotkeyAction: Int, CaseIterable {
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

### 2.7 FocusTimerService 契约（V3.8）

```swift
final class FocusTimerService: ObservableObject {
    static let shared = FocusTimerService()

    // 状态
    @Published var status: FocusTimerStatus    // .idle / .running / .paused
    @Published var phase: FocusTimerPhase      // .work / .rest
    @Published var remainingSeconds: Int
    @Published var workMinutes: Int             // 默认 25，持久化
    @Published var restMinutes: Int             // 默认 5，持久化
    @Published var pendingAction: FocusPendingAction  // .none / .startRest / .startWork

    // 计算属性
    var progress: CGFloat                      // 0.0~1.0（剩余/总共）
    var displayTime: String                    // "MM:SS"
    var phaseLabel: String                     // "工作中" / "休息中"

    // 控制
    func start()                               // idle → running(work)，清除 pendingAction
    func pause()                               // running → paused
    func resume()                              // paused → running
    func reset()                               // → idle，清除 pendingAction
    func startRestPhase()                      // paused(work) → running(rest)，清除 pendingAction
    func setWorkMinutes(_ m: Int)              // 仅 idle 时可调，≥1
    func setRestMinutes(_ m: Int)              // 仅 idle 时可调，≥1

    // 阶段切换（内部）
    // switchPhase()：工作完成 → pendingAction=.startRest + 发 focusWorkCompleted
    //               休息完成 → pendingAction=.startWork + 发 focusRestCompleted

    // 通知
    // focusTimerChanged：每秒或状态变化时发送
    // focusWorkCompleted：工作阶段倒计时归零
    // focusRestCompleted：休息阶段倒计时归零

    // 持久化：workMinutes/restMinutes → UserDefaults(focusTimerSettings)
}
```

### 2.8 Constants（集中管理的常量、通知名、Keys）

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

        // V3.7：主题变更通知
        static let themeChanged = Notification.Name("FocusCopilot.themeChanged")

        // V3.8：FocusByTime 计时器通知
        static let focusTimerChanged = Notification.Name("FocusCopilot.focusTimerChanged")
        static let focusWorkCompleted = Notification.Name("FocusCopilot.focusWorkCompleted")
        static let focusRestCompleted = Notification.Name("FocusCopilot.focusRestCompleted")
    }

    // V3.2 新增：UserDefaults Keys
    enum Keys {
        static let appConfigs = "FocusCopilot.appConfigs"
        static let preferences = "FocusCopilot.preferences"
        static let ballPosition = "FocusCopilot.ballPosition"
        static let onboardingCompleted = "FocusCopilot.onboardingCompleted"
        static let windowRenames = "FocusCopilot.windowRenames"
        static let panelSize = "FocusCopilot.panelSize"
        static let lastPanelTab = "FocusCopilot.lastPanelTab"   // V3.2 新增
        static let focusTimerSettings = "FocusCopilot.focusTimerSettings"  // V3.8 新增
    }
}
```

---

## 3. 模块间交互

### 3.1 FloatingBall → QuickPanel 交互

```
FloatingBallView                   QuickPanelWindow
     │                                │
     │── mouseEntered ───────────────▶│ AppMonitor.startWindowRefresh()（数据预热）
     │                                │
     │── hover 150ms ────────────────▶│ show(relativeTo: ballFrame)
     │   (ballShowQuickPanel)         │
     │                                │
     │── click ──────────────────────▶│ toggleQuickPanel (ballToggleQuickPanel)
     │   未显示/未钉住→show+pin        │
     │   已显示且钉住→unpin+hide       │
     │                                │
     │── double-click ──────────────▶ MainKanbanWindow.toggleMainKanban()
     │   (ballOpenMainKanban)         │
     │                                │
     │── drag-start ────────────────▶│ hide() (ballDragStarted)
     │                                │
     │◀── mouseExited(500ms) ────────│ hide()（钉住时跳过；autoRetractOnHover=false 时跳过）
     │   (ballMouseExited)            │    └── AppMonitor.stopWindowRefresh()
```

> **性能优化**：QuickPanelWindow 在应用启动时预创建（非懒加载），mouseEntered 时立即预热窗口数据，面板弹出动画 100ms / 收起 120ms，hover 延迟 150ms。

### 3.2 QuickPanel → Services 交互

```
QuickPanelView（V3.2 交互模式）
     │
     │── Tab 切换（活跃/关注） ──▶ 切换 currentTab，ConfigStore.saveLastPanelTab()
     │── 点击单窗口 App 行 ──▶ WindowService.activateWindow(window)
     │── 点击多窗口 App 行 ──▶ 切换折叠/展开（collapsedApps）
     │── 点击窗口行 ──────────▶ highlightedWindowID = window.id
     │                        + WindowService.activateWindow(window)
     │── 点击窗口行✕按钮 ──────▶ NSAlert 确认 → WindowService.closeWindow(window)
     │── 点击未运行 App ──────▶ NSWorkspace.openApplication(at:configuration:)
     │── 右键窗口行 ──────────▶ 窗口重命名（NSAlert+NSTextField）
     │                         └── ConfigStore.windowRenames["{bundleID}::{CGWindowID}"]
     │── 右键 App 行 ──────────▶ createRunningAppContextMenu(bundleID:)
     │                         └── "关闭应用" → handleTerminateApp(_:)
     │── 点击顶部主界面按钮 ──▶ ballOpenMainKanban 通知（切换主看板显示/隐藏）
     │
     │── 读取数据 ─────────────▶ AppMonitor.runningApps（活跃 Tab：有窗口的 App，关注优先排序）
     │                       ▶ ConfigStore.appConfigs（关注 Tab）
     │                       ▶ ConfigStore.windowRenames
     │                       ▶ ConfigStore.lastPanelTab（Tab 记忆恢复）

QuickPanelWindow
     │
     │── 顶部拖拽区域（24px）──▶ handlePanelDrag()（钉住时联动悬浮球）
     │── 边缘拖拽 resize ──────▶ ConfigStore.panelSize + save()
     │── hide() ────────────────▶ resetToNormalMode()（highlightedWindowID = nil，保留 Tab 记忆）
```

### 3.3 MainKanban 交互

```
MainKanbanView
     │
     │── 侧边栏 Tab ──────────▶ "关注管理" / "偏好设置"
     │── 左半按钮（显隐球）──▶ ballToggle 通知
     │── 右半按钮（退出）───▶ 确认对话框 → NSApplication.terminate()

AppConfigView（关注管理页面）
     │
     │── 三 Tab 过滤 ─────────▶ 全部(N) / 活跃(N) / 关注(N)
     │── 搜索框 ──────────────▶ 过滤 App 名称
     │── 点击★按钮 ───────────▶ ConfigStore.addApp() / removeApp()
     │── 右键菜单 ────────────▶ "添加到关注" / "从关注中移除"
     │── 读取数据 ────────────▶ AppMonitor.installedApps（全部 Tab）
     │                       ▶ NSWorkspace.runningApplications（活跃 Tab）
     │                       ▶ ConfigStore.appConfigs（关注 Tab）
```

---

## 4. 行为约束

### 4.1 状态转换矩阵

#### 悬浮球状态

| 当前状态 | 触发条件 | 目标状态 | 副作用 |
|---|---|---|---|
| 正常显示 | mouseEntered | 正常显示 | AppMonitor.startWindowRefresh()（数据预热） |
| 正常显示 | hover 150ms | 正常显示 + 快捷面板弹出 | QuickPanel.show()（面板已钉住时跳过） |
| 正常显示 | 单击 | 正常显示 | 切换面板钉住状态 + 悬浮球红色发光边框（V3.3） |
| 正常显示 | 双击 | 正常显示 | 切换主看板显示/隐藏 |
| 正常显示 | 拖拽开始 | 拖拽中 | 关闭快捷面板 |
| 拖拽中 | 拖拽结束 | 正常显示 | 吸附到最近边缘 + 保存位置 |
| 正常显示 | 贴边检测 | 贴边半隐藏 | 收入一半 |
| 贴边半隐藏 | 鼠标靠近 | 正常显示 | 滑出动画 |
| 隐藏 | ⌘⇧B | 正常显示 | 恢复到上次位置 |
| 正常显示 | ⌘⇧B / 底部按钮 | 隐藏 | 保存状态，发送 ballVisibilityChanged 通知 |

#### 快捷面板状态

| 当前状态 | 触发条件 | 目标状态 | 副作用 |
|---|---|---|---|
| 隐藏 | 悬浮球 hover 150ms | 显示（未钉住） | startWindowRefresh()（已由 mouseEntered 预热），恢复 lastPanelTab，活跃 Tab 关注优先排序 |
| 隐藏 | 悬浮球单击 | 显示（钉住） | startWindowRefresh()，恢复 lastPanelTab |
| 显示（未钉住） | 鼠标离开 500ms（autoRetractOnHover=true） | 隐藏 | stopWindowRefresh()，highlightedWindowID = nil |
| 显示（未钉住） | 鼠标离开（autoRetractOnHover=false） | 显示（未钉住） | 面板保持显示，不触发 dismissTimer |
| 显示（未钉住） | 悬浮球拖拽 | 隐藏 | stopWindowRefresh() |
| 显示（未钉住） | 点击钉住按钮 | 显示（钉住） | 取消 dismissTimer |
| 显示（钉住） | 悬浮球单击 | 隐藏 | 取消钉住，stopWindowRefresh() |
| 显示（钉住） | 点击钉住按钮 | 显示（未钉住） | 恢复自动收起 |
| 显示（钉住） | 鼠标离开 | 显示（钉住） | 不触发收起 |
| 显示（钉住） | 面板拖拽 | 显示（钉住） | 联动悬浮球同步移动 |
| 显示 | Tab 切换 | 显示 | ConfigStore.saveLastPanelTab()，刷新内容 |
| 显示 | 点击窗口行✕ | 显示 | NSAlert 确认后 closeWindow()，刷新内容 |

#### 窗口行高亮状态

| 当前状态 | 触发条件 | 目标状态 | 副作用 |
|---|---|---|---|
| 无高亮 | 点击窗口行 A | A 高亮 | WindowService.activateWindow(A) |
| A 高亮 | 点击窗口行 B | B 高亮 | A 取消高亮，WindowService.activateWindow(B) |
| A 高亮 | 面板关闭 | 无高亮 | resetToNormalMode() |
| A 高亮 | 点击已高亮行 A | A 高亮 | 保持不变，不做额外操作 |

### 4.2 通用边界行为

| 场景 | 处理 |
|---|---|
| 关注 App 已满 8 个 | 禁用添加按钮，底部显示关注计数 |
| 未关注任何 App | 关注 Tab 显示空状态引导 |
| 辅助功能未授权 | 窗口标题获取和前置不可用，App 切换正常，面板底部显示权限引导 |
| 窗口标题为空 | 四级兜底：AX 标题 → CG 标题 → 缓存 → "(无标题)" |
| App 图标获取失败 | 使用系统默认图标 |
| 多显示器 | 悬浮球限制在一个屏幕，拖拽不跨屏 |
| 未运行 App（关注 Tab） | 灰度显示，点击调用 NSWorkspace.openApplication 启动 |
| codesign 导致权限失效 | PermissionManager 后台轮询检测，自动恢复 |
| 面板关闭后重新打开 | 恢复上次 Tab 选择（Tab 记忆） |
| autoRetractOnHover=false 且未钉住 | hover 离开不收起面板，面板保持显示直到主动关闭 |

### 4.3 跨 App 窗口激活（V3.2）

```
activateWindow(window)
  → app.isHidden → unhide()
  → NSWorkspace.openApplication(activates: true)   // 系统级 API，不受 nonactivatingPanel 限制
    │  回退: yieldActivation + activate
  → raiseAndFocusWindowViaAX(window)                // AXRaise + AXMain + AXFocused
  → 150ms 后 raiseAndFocusWindowViaAX(window)       // 等待 openApplication 完成
  → 300ms 后检查 frontmostApplication
    → 若目标 App 未成为前台
      → yieldActivation + activate 重试
      → raiseAndFocusWindowViaAX(window) 重试
```

### 4.4 窗口关闭流程（V3.2）

```
点击窗口行✕按钮
  → NSAlert 确认对话框（"关闭窗口" / "取消"）
  → 确认 → WindowService.closeWindow(window)
    → findAXWindow(pid, windowID)
    → AXUIElementCopyAttributeValue(kAXCloseButtonAttribute)
    → AXUIElementPerformAction(kAXPressAction)
```

### 4.5 FocusByTime 状态机（V3.8）

#### 计时器状态

| 当前状态 | 触发条件 | 目标状态 | 副作用 |
|---|---|---|---|
| idle | 编辑弹窗"直接开始" | running(work) | 保存时长，启动 Timer，清除 pendingAction |
| running(work) | 暂停按钮 | paused(work) | 停止 Timer |
| paused(work) | 继续按钮 | running(work) | 恢复 Timer |
| running/paused | 停止按钮确认 | idle | 清除 Timer，清除 pendingAction |
| running(work) | 倒计时归零 | paused(work) | pendingAction=.startRest，发送 focusWorkCompleted |
| paused(work) | 弹窗/快捷按钮"开始休息" | running(rest) | 启动休息 Timer，清除 pendingAction |
| paused(work) | 弹窗"直接结束"/重置 | idle | 清除状态，清除 pendingAction |
| running(rest) | 倒计时归零 | idle | pendingAction=.startWork，发送 focusRestCompleted |
| idle(pending=startWork) | 弹窗/快捷按钮"开始工作" | running(work) | 启动 Timer，清除 pendingAction |

#### 编辑弹窗行为

| 事件 | 处理 |
|---|---|
| 点击推荐方案 | 自动填充输入框，radio 选中 |
| 手动输入/点击±按钮 | 取消所有 radio 选中 |
| 切换到其他应用 | `abortModal` + `close`（等同取消） |
| 点击"直接开始" | 保存时长 + 启动计时 |
| 点击"仅保存" | 保存时长，不启动 |

#### 阶段转换弹窗行为

| 事件 | 处理 |
|---|---|
| 切换到其他应用 | `abortModal` + `close`，pendingAction 保留，计时器栏显示快捷操作 |
| 回到应用 | 计时器栏显示 pending 状态提示（"工作完成 · 开始休息" / "休息结束 · 继续工作"） + 快捷操作按钮 |
| 点击快捷操作按钮 | 执行对应动作（startRestPhase / start），清除 pendingAction |
| 点击重置按钮 | reset()，清除 pendingAction |

### 4.6 关闭应用流程

```
右键 App 行 → createRunningAppContextMenu(bundleID:)
  → 菜单项："关闭应用"
  → handleTerminateApp(_:) → NSRunningApplication.terminate()

关注 Tab：createFavoriteContextMenu(bundleID:, isRunning:)
  → isRunning=true 时显示"关闭应用"菜单项
  → isRunning=false 时不显示
```

---

## 5. 验收用例

### TC-01: Tab 切换与记忆

- **前置条件**：有运行中的 App，已关注至少 1 个 App
- **操作步骤**：打开快捷面板 → 切换到关注 Tab → 关闭面板 → 重新打开面板
- **预期结果**：活跃 Tab 显示有可见窗口的运行中 App，关注 Tab 显示 ConfigStore.appConfigs 中的 App。重新打开面板时恢复到关注 Tab
- **覆盖**：正常路径 + Tab 记忆

### TC-02: 窗口行高亮+前置

- **前置条件**：有多窗口 App，面板打开
- **操作步骤**：点击窗口行 A → 确认高亮 → 点击窗口行 B → 确认 A 取消高亮 B 高亮
- **预期结果**：同一时间只有一个窗口行高亮，窗口被激活并前置
- **覆盖**：正常路径

### TC-03: 启动未运行 App

- **前置条件**：关注了一个未运行的 App
- **操作步骤**：切换到关注 Tab → 点击灰度显示的 App 行
- **预期结果**：App 启动，列表更新为运行状态并显示窗口
- **覆盖**：正常路径

### TC-04: 窗口关闭

- **前置条件**：有运行中的多窗口 App，面板打开
- **操作步骤**：点击窗口行右侧✕按钮 → 确认对话框点击"关闭"
- **预期结果**：目标窗口被关闭，面板列表刷新
- **覆盖**：正常路径

### TC-05: 关注管理

- **前置条件**：主看板 AppConfigView 打开
- **操作步骤**：全部 Tab 中点击★添加关注 → 切换到关注 Tab → 确认已显示 → 点击★移除关注 → 重启 App
- **预期结果**：关注通过 appConfigs 持久化到 UserDefaults，重启后状态恢复
- **覆盖**：正常路径 + 持久化

### TC-06: 高亮重置

- **前置条件**：面板打开，某窗口行高亮
- **操作步骤**：关闭面板 → 重新打开面板
- **预期结果**：所有窗口行高亮状态重置为无高亮
- **覆盖**：边界（状态清理）

### TC-07: 旧数据迁移（V3.1）

- **前置条件**：存在 V3.0 格式的 AppConfig 数据（含 isFavorite 字段）
- **操作步骤**：启动 App，加载配置
- **预期结果**：migrateToV31 将 isFavorite==true 的 App 保留，其余移除。迁移标记 `FocusCopilot.v31Migrated` 写入 UserDefaults
- **覆盖**：异常恢复（数据兼容）

### TC-08: 关注管理三 Tab 过滤

- **前置条件**：主看板 AppConfigView，有已安装/运行中/关注 App
- **操作步骤**：在全部/活跃/关注 Tab 间切换 → 输入搜索关键词
- **预期结果**：各 Tab 显示对应数量标签（全部(N)/活跃(N)/关注(N)），搜索即时过滤
- **覆盖**：正常路径

### TC-09: "打开主界面"按钮切换

- **前置条件**：快捷面板打开
- **操作步骤**：点击顶部主界面按钮 → 确认主看板打开 → 再次点击
- **预期结果**：主看板在显示/隐藏之间切换
- **覆盖**：正常路径

### TC-10: FocusByTime 编辑+开始

- **前置条件**：快捷面板打开，计时器 idle 状态
- **操作步骤**：点击 play.circle → 选择"深度专注"推荐方案 → 手动修改工作时长为 30 → 确认 radio 取消选中 → 点击"直接开始"
- **预期结果**：推荐方案填充 25/5，手动修改后 radio 取消选中，开始后计时器栏显示 30:00 倒计时
- **覆盖**：正常路径 + 推荐方案交互

### TC-11: FocusByTime 阶段转换（正常路径）

- **前置条件**：计时器工作阶段运行中
- **操作步骤**：等待倒计时归零 → 弹窗确认"开始休息" → 等待休息结束 → 弹窗确认"开始工作"
- **预期结果**：工作完成弹窗含科学休息指南，休息结束弹窗提示开始工作，状态正确切换
- **覆盖**：正常路径

### TC-12: FocusByTime 弹窗失焦自动关闭

- **前置条件**：编辑弹窗 / 工作完成弹窗 / 休息结束弹窗已打开
- **操作步骤**：切换到其他应用 → 切回 FocusPilot
- **预期结果**：
  - 编辑弹窗：自动关闭（等同取消），计时器仍为 idle
  - 工作完成弹窗：自动关闭，计时器栏显示"工作完成 · 开始休息"+ 休息快捷按钮，点击可启动休息
  - 休息结束弹窗：自动关闭，计时器栏显示"休息结束 · 继续工作"+ 工作快捷按钮，点击可启动工作
  - 点击重置按钮可清除 pending 状态回到 idle
- **覆盖**：边界（失焦处理 + PendingAction）

---

## 6. 非目标声明

当前版本**不做**以下功能：

- 关注 Tab 支持拖拽排序（mouseDown/mouseDragged/mouseUp 手势，通过 HoverableRowView 的 dragEnabled + handler 闭包组实现，持久化到 ConfigStore.reorderApps）
- 不添加快捷面板搜索框
- 不添加窗口缩略图预览
- 不实现窗口分组
- 不实现插件系统
- 不实现网络请求（无遥测、无更新检查）
- 不在快捷面板内提供关注操作（关注仅通过主看板 AppConfigView 管理）

---

## 7. 文件清单与职责

| 文件 | 行数 | 职责 |
|---|---|---|
| FocusPilotApp.swift | ~16 | @main 入口，初始化 AppDelegate |
| AppDelegate.swift | ~342 | 应用生命周期、窗口管理、菜单栏图标、Dock 图标 |
| PermissionManager.swift | ~90 | 辅助功能权限检测、引导、后台轮询 |
| FloatingBallWindow.swift | ~98 | NSPanel 子类，窗口层级、贴边 |
| FloatingBallView.swift | ~800 | 悬浮球视图、品牌 Logo、hover/click/drag 检测、钉住状态红色发光边框 |
| QuickPanelWindow.swift | ~483 | NSPanel 子类，面板位置、钉住、resize、drag、联动 |
| QuickPanelView.swift | ~1130 | 面板内容：活跃/关注 Tab、Tab 记忆、窗口行高亮+前置+关闭、App 行右键菜单（关闭应用）、FocusByTime 计时器栏+编辑弹窗 |
| MainKanbanWindow.swift | ~51 | NSWindow 子类，主看板窗口管理 |
| MainKanbanView.swift | ~90 | SwiftUI 根视图，侧边栏导航（关注管理/偏好设置）+ 底部双按钮 |
| AppConfigView.swift | ~306 | SwiftUI 关注管理：三 Tab 过滤（全部/活跃/关注）+ 搜索 + 星标关注切换 |
| PreferencesView.swift | ~140 | SwiftUI 偏好设置页面（外观、颜色主题、hover 回缩开关） |
| WindowService.swift | ~652 | 窗口枚举、AX 操作、CGS 层级、标题四级兜底、跨 App 激活、窗口关闭 |
| AppMonitor.swift | ~195 | App 运行状态监控（不依赖 ConfigStore）、窗口刷新定时器 |
| HotkeyManager.swift | ~101 | 全局快捷键（Carbon API），2 个动作（⌘⇧B 悬浮球显隐、⌘Esc 主看板显隐） |
| ConfigStore.swift | ~221 | UserDefaults 持久化（含迁移逻辑、关注管理、Tab 记忆） |
| Models.swift | ~118 | 数据模型定义（AppConfig 无 isFavorite、QuickPanelTab 枚举在 QuickPanelView.swift 中） |
| FocusTimerService.swift | ~195 | FocusByTime 番茄钟服务：状态机（idle/running/paused × work/rest）、Timer 计时、阶段切换通知、FocusPendingAction、时长持久化 |
| Constants.swift | ~97 | 全局常量、16 个通知名、8 个 UserDefaults Keys |
| **合计** | **~5040** | |
