# PinTop 架构设计文档

> **版本**：V1.1
> **日期**：2026-03-01
> **基于**：PRD V1.0（第四轮）+ V1.1 实际实现

---

## 1. 模块划分

### 总览

```
PinTop/
├── PinTop/
│   ├── App/
│   │   ├── AppDelegate.swift          # 应用生命周期、权限检查、菜单栏
│   │   ├── PinTopApp.swift            # @main 入口
│   │   └── PermissionManager.swift    # 辅助功能权限检测与引导
│   ├── FloatingBall/
│   │   ├── FloatingBallWindow.swift   # 悬浮球窗口（NSPanel）
│   │   └── FloatingBallView.swift     # 悬浮球视图、拖拽、贴边、角标
│   ├── QuickPanel/
│   │   ├── QuickPanelWindow.swift     # 快捷面板窗口（NSPanel）
│   │   └── QuickPanelView.swift       # 快捷面板内容视图（App列表、窗口列表、置顶模式）
│   ├── MainKanban/
│   │   ├── MainKanbanWindow.swift     # 主看板窗口管理
│   │   ├── MainKanbanView.swift       # 主看板根视图（SwiftUI）
│   │   ├── AppConfigView.swift        # 快捷面板配置页（SwiftUI）
│   │   ├── PinManageView.swift        # 置顶管理页（SwiftUI）
│   │   └── PreferencesView.swift      # 偏好设置页（SwiftUI）
│   ├── Services/
│   │   ├── WindowService.swift        # 窗口枚举、AXUIElement 操作、层级控制
│   │   ├── AppMonitor.swift           # 监听 App 启动/退出，维护运行列表
│   │   ├── PinManager.swift           # 窗口置顶状态管理、生命周期
│   │   ├── HotkeyManager.swift        # 全局快捷键注册和分发
│   │   └── ConfigStore.swift          # 用户配置持久化（UserDefaults）
│   ├── Models/
│   │   └── Models.swift               # 数据模型定义
│   ├── Helpers/
│   │   ├── CGSPrivate.h               # Private API 桥接头
│   │   └── Constants.swift            # 全局常量
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
| **App/** | 应用入口、生命周期、权限管理 | 应用级别的初始化逻辑独立于具体 UI |
| **FloatingBall/** | 悬浮球 UI、拖拽、贴边、hover 检测、角标 | 悬浮球的交互逻辑（拖拽/贴边/动画）独立变化频率高 |
| **QuickPanel/** | 快捷面板 UI、App 列表、窗口列表、置顶模式视图 | 面板的展示逻辑和交互方式独立于悬浮球 |
| **MainKanban/** | 主看板 SwiftUI 界面（3 个配置页面） | SwiftUI 技术栈独立，页面布局频繁调整 |
| **Services/** | 底层服务（窗口操作、App 监控、Pin 管理、快捷键、配置存储） | 业务逻辑层与 UI 层分离，可独立测试 |
| **Models/** | 数据模型 | 数据结构被多个模块共享 |
| **Helpers/** | 桥接头、常量 | 基础设施，极少变化 |

### 防过度设计自查

- [x] 文件数（~17）<= 功能点数（25）
- [x] 无多余抽象层：Services 直接暴露方法，无 Protocol 包装（单实现不需要）
- [x] 没有为"未来可能"创建接口
- [x] 没有只有一个实现的抽象层
- [x] 没有无消费者的接口

---

## 2. 接口契约

### 2.1 数据模型（Models.swift）

```swift
// App 配置（持久化）
struct AppConfig: Codable, Identifiable {
    var id: String { bundleID }
    let bundleID: String          // App 唯一标识
    var displayName: String       // 显示名称
    var order: Int                // 快捷面板中的排序
    var pinnedKeywords: [String]  // 窗口排序关键词
}

// 运行中的 App 信息（运行时）
// 使用 class 而非 struct，因为需要 ObservableObject 支持 @Published 属性
class RunningApp: Identifiable, ObservableObject {
    var id: String { bundleID }
    let bundleID: String
    let localizedName: String
    let icon: NSImage
    /// 实际运行中的进程引用（未运行时为 nil）
    let nsApp: NSRunningApplication?
    @Published var windows: [WindowInfo]
    /// 标记该 App 是否真正在运行（未运行的已配置 App 此值为 false）
    @Published var isRunning: Bool

    init(bundleID: String, localizedName: String, icon: NSImage,
         nsApp: NSRunningApplication?, windows: [WindowInfo] = [],
         isRunning: Bool = false)
}

// 窗口信息（运行时）
struct WindowInfo: Identifiable, Equatable {
    let id: CGWindowID
    let ownerBundleID: String
    let ownerPID: pid_t           // 所属进程 PID
    var title: String
    var bounds: CGRect
    var isMinimized: Bool
    var isFullScreen: Bool

    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool { lhs.id == rhs.id }
}

// Pin 窗口信息
struct PinnedWindow: Identifiable, Equatable {
    let id: CGWindowID
    let ownerBundleID: String
    var title: String
    var order: Int                // 层级顺序，1 = 最顶层
    let ownerPID: pid_t           // 所属进程 PID（用于 AX 操作）

    static func == (lhs: PinnedWindow, rhs: PinnedWindow) -> Bool { lhs.id == rhs.id }
}

// 已安装 App 信息（扫描 /Applications 获得）
struct InstalledApp: Identifiable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let icon: NSImage
    let url: URL
}

// 面板大小（持久化，拖拽 resize 后保存）
struct PanelSize: Codable {
    var width: CGFloat
    var height: CGFloat
    static let `default` = PanelSize(width: 280, height: 400)
}

// 悬浮球位置（持久化）
struct BallPosition: Codable {
    var x: CGFloat
    var y: CGFloat
    var edge: ScreenEdge         // 吸附的边缘
    static let `default` = BallPosition(x: 50, y: 300, edge: .left)
}

enum ScreenEdge: String, Codable {
    case top, bottom, left, right
}

// 偏好设置（持久化）
struct Preferences: Codable {
    var ballSize: CGFloat = 40
    var ballOpacity: CGFloat = 0.8
    var colorTheme: ColorTheme = .system
    var launchAtLogin: Bool = false
    var pinBorderColor: String = "blue"
    var pinSoundEnabled: Bool = true
    // 快捷键
    var hotkeyPinToggle: String = "⌘⇧P"
    var hotkeyUnpinAll: String = "⌘⇧U"
    var hotkeyBallToggle: String = "⌘⇧B"
}

enum ColorTheme: String, Codable {
    case system, light, dark
}
```

### 2.2 ConfigStore 契约

```swift
// ConfigStore — 配置持久化服务
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

    // CRUD 操作
    func addApp(_ bundleID: String, displayName: String)    // 添加 App 到已选列表
    func removeApp(_ bundleID: String)                      // 移除
    func reorderApps(_ ids: [String])                       // 重新排序
    func updateKeywords(for bundleID: String, keywords: [String])  // 更新关键词
    func save()                                              // 持久化到 UserDefaults
    func load()                                              // 从 UserDefaults 加载
}
```

### 2.3 AppMonitor 契约

```swift
// AppMonitor — App 运行状态监控
class AppMonitor: ObservableObject {
    static let shared = AppMonitor()

    // 当前运行中的 App 列表（已配置的 + 状态）
    @Published var runningApps: [RunningApp]

    // 已安装 App 列表
    @Published var installedApps: [InstalledApp]

    func startMonitoring()   // 开始监听 NSWorkspace 通知
    func stopMonitoring()    // 停止监听
    func refreshRunningApps()  // 刷新运行中 App 列表
    func refreshWindows(for bundleID: String)  // 刷新指定 App 的窗口列表
    func scanInstalledApps()   // 扫描已安装 App

    // 面板显示时启动窗口刷新定时器（1s 间隔），同步调用 PermissionManager.shared.checkAccessibility()
    func startWindowRefresh()
    // 面板隐藏时停止窗口刷新定时器
    func stopWindowRefresh()
    // 刷新所有已配置 App 的窗口列表（同步 isRunning 状态）
    func refreshAllWindows()

    // 通知：App 状态变化
    static let appStatusChanged = Notification.Name("AppMonitor.appStatusChanged")
    // 通知：窗口列表变化
    static let windowsChanged = Notification.Name("AppMonitor.windowsChanged")
}
```

### 2.4 WindowService 契约

```swift
// WindowService — 窗口操作底层服务
class WindowService {
    static let shared = WindowService()

    // 私有 API 函数指针（动态加载）
    // - CGSMainConnectionID / CGSSetWindowLevel：窗口层级控制
    // - _AXUIElementGetWindow：从 AXUIElement 获取 CGWindowID

    // 窗口枚举
    func listWindows(for bundleID: String) -> [WindowInfo]  // 获取指定 App 的窗口列表
    func listWindows(for pid: pid_t) -> [WindowInfo]        // 获取指定 PID 的窗口列表
    func listAllWindows() -> [WindowInfo]                    // 获取所有窗口

    // 窗口操作（需要辅助功能权限）
    func activateWindow(_ window: WindowInfo)                // 激活并前置窗口（通过 CGWindowID 精确匹配 AX 窗口）
    func setWindowLevel(_ windowID: CGWindowID, level: Int32)  // 设置窗口层级（CGS Private API）
    func moveWindow(_ axWindow: AXUIElement, to: CGPoint)    // 移动窗口
    func resizeWindow(_ axWindow: AXUIElement, to: CGSize)   // 调整窗口大小
    func setWindowFrame(_ axWindow: AXUIElement, frame: CGRect)  // 设置窗口位置和大小

    // AX 窗口查找
    func getAXElement(for pid: pid_t) -> AXUIElement         // 获取 App 的 AX 元素
    func getAXWindows(for pid: pid_t) -> [AXUIElement]       // 获取 App 的所有 AX 窗口
    func findAXWindow(pid: pid_t, windowID: CGWindowID) -> AXUIElement?  // 通过 CGWindowID 精确匹配
    func findAXWindow(pid: pid_t, title: String) -> AXUIElement?         // 通过标题匹配

    // App 操作（不需要辅助功能权限）
    func activateApp(_ bundleID: String)             // 激活 App（NSRunningApplication.activate）

    // --- 关键实现细节 ---
    // getCGWindowID(from: AXUIElement) -> CGWindowID?
    //   使用 _AXUIElementGetWindow 私有 API 从 AXUIElement 获取 CGWindowID
    //
    // buildAXTitleMap(for pid: pid_t, cgWindows: [[String: Any]]) -> [CGWindowID: String]
    //   构建 CGWindowID → AX 标题映射表
    //   - 调用 AXIsProcessTrusted() 实时检查辅助功能权限
    //   - 优先通过 _AXUIElementGetWindow 精确映射
    //   - 无法获取 CGWindowID 时，回退到位置匹配（tolerance=10px）
    //
    // 窗口标题来源优先级：AX API 标题 → CG 标题 → "(无标题)"
}
```

### 2.5 PinManager 契约

```swift
// PinManager — 窗口置顶管理
class PinManager: ObservableObject {
    static let shared = PinManager()

    // 已 Pin 的窗口列表（有序，index 0 = 最顶层）
    @Published var pinnedWindows: [PinnedWindow]

    var pinnedCount: Int { pinnedWindows.count }
    static let maxPinnedCount = 6

    func pin(window: WindowInfo) -> Bool     // Pin 窗口，返回是否成功
    func unpin(windowID: CGWindowID)          // Unpin 窗口
    func unpinAll()                           // Unpin 所有
    func togglePin(windowID: CGWindowID)      // 切换 Pin 状态
    func reorder(_ ids: [CGWindowID])         // 重新排列层级
    func isPinned(_ windowID: CGWindowID) -> Bool

    // 监听窗口关闭/最小化/全屏，自动清理 Pin
    func startObserving()
    func stopObserving()

    // 通知
    static let pinnedWindowsChanged = Notification.Name("PinManager.pinnedWindowsChanged")
}
```

### 2.6 HotkeyManager 契约

```swift
// HotkeyManager — 全局快捷键
class HotkeyManager {
    static let shared = HotkeyManager()

    func registerAll()      // 注册所有全局快捷键
    func unregisterAll()    // 注销所有
    func updateHotkey(for action: HotkeyAction, keyCombo: String)  // 更新单个快捷键

    enum HotkeyAction {
        case pinToggle      // ⌘⇧P
        case unpinAll       // ⌘⇧U
        case ballToggle     // ⌘⇧B
    }
}
```

### 2.7 FloatingBall → QuickPanel 交互

```
FloatingBallWindow                QuickPanelWindow
     │                                │
     │── mouseEntered(300ms) ────────▶│ show(relativeTo: ballFrame)
     │                                │    └── AppMonitor.startWindowRefresh()
     │                                │
     │◀── mouseExited(500ms) ────────│ hide()（钉住时跳过）
     │                                │    └── AppMonitor.stopWindowRefresh()
     │                                │
     │── mouseDown(click) ──────────▶ MainKanbanWindow.show()
     │                                │
     │── mouseDown(double-click) ──▶ self.hide()  // 隐藏悬浮球
     │                                │
     │── mouseDown(drag-start) ────▶│ hide()  // 拖动浮球时关闭面板
```

### 2.8 QuickPanel → Services 交互

```
QuickPanelView
     │
     │── 点击单窗口 App ───▶ WindowService.activateApp(bundleID)
     │── 点击窗口条目 ────▶ WindowService.activateWindow(window: WindowInfo)
     │── 点击📌按钮 ──────▶ 切换到置顶模式视图
     │── 右键窗口条目 ────▶ 窗口重命名（NSAlert+NSTextField 对话框）
     │                      └── 存储到 ConfigStore.windowRenames["{bundleID}::{title}"]
     │
     │── 读取数据 ────────▶ AppMonitor.runningApps（实时）
     │                  ▶ ConfigStore.appConfigs（已选 App 配置）
     │                  ▶ ConfigStore.windowRenames（窗口自定义名称）
     │                  ▶ PinManager.pinnedWindows（已 Pin 窗口）

QuickPanelWindow
     │
     │── 顶部钉住按钮 ────▶ togglePanelPin()（isPanelPinned 切换）
     │                      钉住时：dismiss/mouseExited 均 guard 跳过
     │
     │── 边缘拖拽 resize ─▶ mouseDown/mouseDragged/mouseUp（热区 5px）
     │                      └── 保存到 ConfigStore.panelSize + save()
```

### 2.9 PermissionManager 契约

```swift
// PermissionManager — 辅助功能权限管理
class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published var accessibilityGranted: Bool = false

    func checkAccessibility() -> Bool      // 检查辅助功能权限
    func requestAccessibility()            // 引导用户开启权限
    func startPolling()                    // 轮询检测权限状态
    func stopPolling()
}
```

---

## 3. 行为约束

### 3.1 状态转换矩阵

#### 悬浮球状态

| 当前状态 | 触发条件 | 目标状态 | 副作用 |
|---|---|---|---|
| 正常显示 | hover 300ms | 正常显示 + 快捷面板弹出 | QuickPanel.show() |
| 正常显示 | 单击 | 正常显示 | MainKanban.show() |
| 正常显示 | 双击 | 隐藏 | 保存位置 |
| 正常显示 | 拖拽开始 | 拖拽中 | 取消 hover 计时器 |
| 拖拽中 | 拖拽结束 | 正常显示 | 吸附到最近边缘 + 保存位置 |
| 正常显示 | 贴边检测 | 贴边半隐藏 | 收入一半 |
| 贴边半隐藏 | 鼠标靠近 | 正常显示 | 滑出动画 |
| 隐藏 | ⌘⇧B | 正常显示 | 恢复到上次位置 |

#### 快捷面板状态

| 当前状态 | 触发条件 | 目标状态 | 副作用 |
|---|---|---|---|
| 隐藏 | 悬浮球 hover 300ms | 正常模式（展开） | 加载 App 列表+窗口列表，startWindowRefresh() |
| 正常模式 | 鼠标离开 500ms | 隐藏 | 收起动画，stopWindowRefresh() |
| 正常模式 | 点击 App/窗口 | 隐藏 | 执行切换 |
| 正常模式 | 点击📌按钮 | 置顶模式 | 切换视图 |
| 正常模式 | 点击钉住按钮 | 正常模式（钉住） | isPanelPinned=true，取消 dismissTimer |
| 正常模式（钉住） | 鼠标离开 | 正常模式（钉住） | 不触发收起（guard 跳过） |
| 正常模式（钉住） | 点击钉住按钮 | 正常模式 | isPanelPinned=false，恢复自动收起 |
| 正常模式（钉住） | 面板 hide() | 隐藏 | isPanelPinned 重置为 false |
| 置顶模式 | 点击← 返回 | 正常模式 | 切换视图 |
| 置顶模式 | 鼠标离开 500ms | 隐藏 | 收起动画（钉住时跳过） |
| 任意模式 | 悬浮球拖拽开始 | 隐藏 | 面板收起 |

#### Pin 窗口状态

| 当前状态 | 触发条件 | 目标状态 | 副作用 |
|---|---|---|---|
| 未 Pin | Pin 操作（未达上限） | 已 Pin | 设置窗口层级 + 显示边框 + 更新角标 |
| 未 Pin | Pin 操作（已达 6 个） | 未 Pin | 提示已达上限 |
| 已 Pin | Unpin 操作 | 未 Pin | 恢复窗口层级 + 移除边框 + 更新角标 |
| 已 Pin | 窗口关闭 | 清除 | 自动 Unpin + 释放名额 |
| 已 Pin | 窗口最小化 | 清除 | 自动 Unpin |
| 已 Pin | 窗口全屏 | 清除 | 自动 Unpin |
| 已 Pin | App 崩溃 | 清除 | 自动清理 |

### 3.2 通用边界行为

| 场景 | 处理 |
|---|---|
| App 配置已满 8 个 | 禁用添加按钮，提示先移除 |
| Pin 已达 6 个 | 禁用 Pin 操作，提示先 Unpin |
| 未配置任何 App | 快捷面板显示空状态引导 |
| 辅助功能未授权 | 置顶相关功能灰度禁用，其他功能正常 |
| 窗口标题为空 | 显示"(无标题)"。标题来源优先级：AX API(_AXUIElementGetWindow 精确映射) → 位置匹配回退(tolerance=10px) → CG 标题 → "(无标题)" |
| App 图标获取失败 | 使用系统默认图标 |
| 多显示器 | 悬浮球限制在一个屏幕，拖拽不跨屏 |
| PinTop 退出 | 清除所有 Pin 状态（不持久化） |

### 3.3 [前端] 专项约束

| 约束 | 规则 |
|---|---|
| hover 检测定时器 | 进入时启动，离开时取消，避免泄漏 |
| 窗口列表刷新定时器 | 面板显示时启动（1s 间隔），隐藏时停止 |
| 窗口观察器（AXObserver） | Pin 时注册，Unpin/窗口关闭时注销 |
| NSWorkspace 通知 | App 启动时注册，App 退出时注销 |
| 动画 | 使用 NSAnimationContext，基于 duration 而非帧率 |
| 贴边检测 | 拖拽结束时计算，非实时轮询 |

### 3.4 关键词匹配规则

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
- 置顶区：按 matchedKeywordIndex 升序（关键词配置顺序）
- 普通区：按系统窗口层级排列
```

---

## 4. 验收用例

### TC-01: 悬浮球基本显示与拖拽

- **前置条件**：应用启动完成
- **操作步骤**：
  1. 确认悬浮球显示在屏幕上
  2. 拖拽悬浮球到屏幕中间
  3. 松开鼠标
- **预期结果**：悬浮球吸附到最近屏幕边缘，拖拽 60fps 流畅
- **覆盖**：正常路径（F01, F02）

### TC-02: 快捷面板 hover 弹出与 App 切换

- **前置条件**：已在主看板配置 3+ 个 App，其中至少 2 个运行中
- **操作步骤**：
  1. hover 悬浮球 300ms
  2. 等待快捷面板弹出
  3. 点击一个运行中的单窗口 App
- **预期结果**：面板弹出 <100ms，点击后 <200ms 切换到目标 App，面板收起
- **覆盖**：正常路径（F05, F06, F07）

### TC-03: 多窗口 App 一次性展开与窗口切换

- **前置条件**：已配置一个多窗口 App（如 Cursor，打开 3 个窗口），配置关键词"PinTop"
- **操作步骤**：
  1. hover 悬浮球
  2. 观察快捷面板中该 App 的窗口列表
  3. 确认关键词命中窗口在分割线上方（带★）
  4. 点击一个窗口条目
- **预期结果**：窗口列表随面板一次性展开，置顶区/普通区正确分区，点击后 <200ms 激活窗口
- **覆盖**：正常路径（F08, F09, F10）

### TC-04: 主看板 App 配置完整流程

- **前置条件**：首次使用，未配置任何 App
- **操作步骤**：
  1. 单击悬浮球打开主看板
  2. 在快捷面板配置页添加 3 个 App
  3. 拖拽调整顺序
  4. 为其中一个 App 配置窗口关键词
  5. 关闭主看板
  6. hover 悬浮球
- **预期结果**：主看板正常打开，App 添加/排序/关键词配置生效，快捷面板按配置顺序展示
- **覆盖**：正常路径（F14, F15）

### TC-05: Pin 窗口

- **前置条件**：辅助功能权限已授权，2+ 个窗口可见
- **操作步骤**：
  1. 在主看板置顶管理中 Pin 2 个窗口
  2. 关闭其中一个 Pin 窗口
- **预期结果**：Pin 成功（边框显示），关闭后自动 Unpin + 释放名额
- **覆盖**：正常路径 + 异常恢复（F16, F19, F20）

### TC-06: 全局快捷键

- **前置条件**：应用运行中，至少一个窗口可见
- **操作步骤**：
  1. 按 ⌘⇧P Pin 当前窗口
  2. 按 ⌘⇧U Unpin 全部
  3. 按 ⌘⇧B 隐藏/唤出悬浮球
- **预期结果**：各快捷键正确触发对应功能
- **覆盖**：正常路径（F04、全局快捷键）

### TC-07: 边界情况——Pin 上限与权限缺失

- **前置条件**：已 Pin 6 个窗口 / 或辅助功能未授权
- **操作步骤**：
  1. 尝试 Pin 第 7 个窗口
  2. 或：在未授权时点击置顶功能
- **预期结果**：
  - Pin 上限：提示已达上限，不执行
  - 未授权：置顶功能灰度禁用，显示权限引导
- **覆盖**：边界（F19, F21）

### TC-08: 配置持久化

- **前置条件**：已配置 App、关键词、悬浮球位置
- **操作步骤**：
  1. 退出 PinTop
  2. 重新启动 PinTop
- **预期结果**：已选 App、排序、关键词、悬浮球位置全部恢复
- **覆盖**：正常路径（F25）

---

## 5. 非目标声明

V1.0 **不做**以下功能：

- 不实现快捷面板启动未运行 App（快捷面板只做切换）
- 不实现窗口分组
- 不实现 Pin 状态持久化恢复（退出即清除）
- 不实现插件系统
- 不实现网络请求（无遥测、无更新检查）
- 不实现 Homebrew Cask / App Store 分发（仅 DMG）
- 不实现 Free/Pro 功能区分（V1.0 全功能）
- 不实现 Onboarding 引导（降低首版复杂度，后续迭代）

---

## 6. 文件清单与职责

| 文件 | 行数 | 职责 |
|---|---|---|
| PinTopApp.swift | ~16 | @main 入口，初始化 AppDelegate |
| AppDelegate.swift | ~187 | 应用生命周期、初始化各服务、菜单栏图标 |
| PermissionManager.swift | ~56 | 辅助功能权限检测、引导、轮询 |
| FloatingBallWindow.swift | ~98 | NSPanel 子类，窗口层级、拖拽、贴边 |
| FloatingBallView.swift | ~579 | 悬浮球视图、绘制、hover 检测、角标、视觉效果 |
| QuickPanelWindow.swift | ~379 | NSPanel 子类，面板窗口管理、钉住模式、拖拽 resize |
| QuickPanelView.swift | ~898 | 面板内容视图、App 列表、窗口列表、置顶模式、右键菜单 |
| MainKanbanWindow.swift | ~40 | NSWindow 子类，主看板窗口管理 |
| MainKanbanView.swift | ~46 | SwiftUI 根视图，侧边栏导航 |
| AppConfigView.swift | ~420 | SwiftUI 快捷面板配置页面 |
| PinManageView.swift | ~174 | SwiftUI 置顶管理页面 |
| PreferencesView.swift | ~165 | SwiftUI 偏好设置页面 |
| WindowService.swift | ~416 | 窗口枚举、AX 操作、CGS 层级、_AXUIElementGetWindow |
| AppMonitor.swift | ~197 | App 运行状态监控、窗口列表刷新、定时器管理 |
| PinManager.swift | ~179 | Pin 状态管理、窗口生命周期监听 |
| HotkeyManager.swift | ~80 | 全局快捷键注册（Carbon API） |
| ConfigStore.swift | ~117 | UserDefaults 持久化（含 windowRenames、panelSize） |
| Models.swift | ~119 | 数据模型定义（含 InstalledApp、PanelSize） |
| Constants.swift | ~74 | 全局常量 |
| CGSPrivate.h | ~20 | Private API 声明 |
| PinTop-Bridging-Header.h | ~8 | Bridging Header |
| **合计** | **~4268** | |
