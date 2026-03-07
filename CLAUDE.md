# Focus Copilot 项目指南

## 项目概述

Focus Copilot（原 PinTop）是 macOS 悬浮球应用，支持窗口快捷切换。
纯 Swift 5 + AppKit/SwiftUI，无第三方依赖。Bundle ID: `com.focuscopilot.FocusCopilot`

三层交互：悬浮球（常驻入口）→ 快捷面板（hover/单击弹出）→ 主看板（双击/Dock 图标）

## 设计基调与风格

### 核心基调：干净 · 高级 · 克制 · 专业

Focus Copilot 追求 **macOS 原生级精致 UI**，像系统自带应用一样自然融入桌面。
设计上宁可少做，不可过度——每一个像素、每一帧动画都应有明确理由，拒绝装饰性元素。

### 产品哲学：专注 × 禅意

品牌灵魂来自禅圆（Enso）——一笔未闭合的弧线，画在悬浮的渐变球体上。
传递「一期一会的专注」「循环而非封闭」「柔和过渡」三层含义。
所有 UI 决策围绕「专注、轻量、不打断」展开。详见 `docs/IconDesign.md`。

### 视觉准则

- **克制用色**：Notion 风格 8 色主题（浅 4 + 深 4），每主题 9 色槽覆盖全 UI。accent 仅用于关键操作和状态指示，大面积留白/留灰，不滥用彩色
- **原生质感**：毛玻璃（NSVisualEffectView）、系统动画曲线（ease-out/ease-in）、SF Symbols，不引入自定义图标库
- **层次分明**：textPrimary / textSecondary / textTertiary 三级文字层次严格区分，信息权重一目了然
- **精致细节**：悬浮球径向渐变 + 高光 + 暗区 + 内边缘光 + accent 呼吸光晕；hover 缩放 1.06x；贴边吸附动画——细节服务于高级感，而非炫技

### 交互原则

1. **非侵入**：悬浮球常驻但不抢焦点（nonactivating NSPanel），面板 hover 弹出 / 离开收起，钉住才持久
2. **三层递进**：悬浮球（零信息，纯入口）→ 快捷面板（紧凑列表，操作为主）→ 主看板（完整配置），信息密度逐层递增
3. **不打断工作流**：弹窗失焦自动关闭，PendingAction 保留上下文，回来后一键继续
4. **一致性**：同一主题下 AppKit + SwiftUI 颜色统一，通过 ThemeColors ns*/sw* 双套桥接

### 修改时必须遵守

- **配色**：新增 UI 元素必须使用 ThemeColors 取色，禁止硬编码颜色值，确保 8 主题视觉一致
- **动画**：参照 `Constants.Design.Anim`（micro 0.1s / fast 0.15s / normal 0.25s），节奏统一，禁止花哨过渡
- **间距**：参照 `Constants.Design.Spacing`（xs 4 / sm 8 / md 12 / lg 16 / xl 24），避免随意数值
- **图标一致**：悬浮球视觉修改必须同步 `FloatingBallView.createBrandLogoImage` 和 `scripts/gen-icon.swift`
- **弹窗规范**：新增弹窗默认添加失焦自动关闭（`didResignActiveNotification` → `abortModal`）
- **克制原则**：不加装饰性阴影、不加多余分割线、不加无意义动画，每个元素都应能回答"为什么需要它"

## 架构（V3.8）

技术栈：Swift 5, macOS 14+, arm64, AppKit + SwiftUI, CGS Private API, AX API, Carbon API

### 文件结构（20 个 .swift，~7400 行）

```
FocusPilot/
├── App/
│   ├── FocusPilotApp.swift         # @main 入口
│   ├── AppDelegate.swift           # 生命周期、窗口管理、菜单栏、快捷键
│   └── PermissionManager.swift     # 辅助功能权限检测（权限授予后自动停止轮询）
├── FloatingBall/
│   ├── FloatingBallWindow.swift    # NSPanel, 层级 statusWindow+100
│   └── FloatingBallView.swift      # 毛玻璃圆球、拖拽吸附、hover 弹出、贴边半隐藏、呼吸动画
├── QuickPanel/
│   ├── QuickPanelWindow.swift      # NSPanel, 层级 statusWindow+50, 动画弹出/收起, 钉住, resize
│   ├── QuickPanelView.swift        # UI 骨架、状态管理、Tab 切换、reloadData 调度、HoverableRowView、FocusByTime 计时器栏
│   ├── QuickPanelRowBuilder.swift  # App 行/窗口行构建、工具方法、SF Symbol 缓存（extension QuickPanelView）
│   └── QuickPanelMenuHandler.swift # 右键菜单、@objc 事件处理、星号关注、App 关闭/启动（extension QuickPanelView）
├── MainKanban/
│   ├── MainKanbanWindow.swift      # NSWindow 包裹 SwiftUI
│   ├── MainKanbanView.swift        # 侧边栏+内容区（关注管理 + 偏好设置）
│   ├── AppConfigView.swift         # 关注管理（全部/活跃/关注 三 Tab + 星标切换）
│   └── PreferencesView.swift       # 偏好设置（快捷键、主题选择、悬浮球外观）
├── Models/
│   └── Models.swift                # AppConfig, RunningApp, WindowInfo, Preferences, AppTheme, ThemeColors 等
├── Services/
│   ├── ConfigStore.swift           # UserDefaults 持久化 + 单字段保存（saveBallPosition/savePanelSize/saveWindowRenames）
│   ├── WindowService.swift         # 窗口枚举(CGWindowList+AX)、两阶段刷新、AX 后台队列、titleCache
│   ├── AppMonitor.swift            # App 运行监控、自适应刷新（1s→3s）、scanInstalledApps 后台线程
│   ├── HotkeyManager.swift         # Carbon 全局快捷键（⌘⇧B 显示/隐藏）
│   └── FocusTimerService.swift     # FocusByTime 番茄钟服务（状态机、计时、阶段切换通知、时长持久化、FocusPendingAction）
└── Helpers/
    └── Constants.swift             # Ball, Panel, Keys, Notifications 常量
```

### 关键设计决策

- **通知驱动架构**：FloatingBall → AppDelegate → QuickPanel，通过 NotificationCenter
- **两阶段窗口刷新**：Phase 1 CG 标题主线程快速渲染 → Phase 2 AX 标题后台补全（不阻塞 UI）
- **差分 UI 更新**：QuickPanelView.reloadData 通过 buildStructuralKey 对比，标题变化走 updateWindowTitles 轻量路径
- **forceReload() 封装**：统一强制全量刷新入口，封装 lastStructuralKey 清除细节
- **窗口标题四级解析**：AX 标题 → 缓存 AX → CG 标题 → "(无标题)"
- **自适应刷新**：面板显示时 1s，无变化时逐步降至 3s；面板隐藏时完全停止
- **关注机制**：ConfigStore.appConfigs 中存在即为关注（V3.1 移除了 isFavorite 字段）
- **关注排序**：右键菜单"置顶"操作，通过 ConfigStore.reorderApps 持久化
- **窗口前置**：NSWorkspace.openApplication + AXRaise + AXMain + AXFocused 三重设置
- **QuickPanel 模块化**：extension 拆分（RowBuilder 负责视图构建、MenuHandler 负责菜单和事件），不引入新类型
- **Notion 风格主题系统**：AppTheme 枚举 8 种预设 → ThemeColors 9 色槽（ns* + sw* 双套，含 sidebarBackground），覆盖全 UI
- **主题刷新链路**：PreferencesView → @Published → AppDelegate.applyPreferences → NSApp.appearance + quickPanelWindow.applyTheme + themeChanged 通知
- **FocusByTime 番茄钟**：FocusTimerService 单例管理状态机（idle/running/paused × work/rest），通过 NotificationCenter 驱动 QuickPanel 底部计时器栏和 FloatingBall 进度环
- **FocusByTime 弹窗全失焦关闭**：所有弹窗（编辑/工作完成/休息结束）均失焦自动关闭（NSApp.didResignActive → abortModal）。阶段完成弹窗关闭后，FocusPendingAction 保留待处理动作，计时器栏显示快捷操作按钮供用户回来后一键执行

### 配置迁移

- V2.0: com.pintop.PinTop → com.focuscopilot.FocusCopilot
- V3.1: appConfigs 含 isFavorite → 仅保留关注（migrateToV31）
- V3.7: Preferences 移除 colorTheme/ballColorStyle/ballCustomColorHex，新增 appTheme（保留旧 CodingKey 兼容解码）
- V3.8: 新增 FocusTimerService + QuickPanel 计时器栏 + FloatingBall 进度环
- AppConfig decoder 向后兼容（忽略旧字段）

## 构建

```bash
make build      # 编译到 /tmp/focuscopilot-build/
make install    # 编译+签名+安装+启动
make clean      # 清理
```

- 仅 Command Line Tools（无 Xcode IDE），swiftc 直接编译
- VFS overlay 绕过 SwiftBridging module 重复定义 bug
- 自签名证书 `FocusCopilot Dev`（`make setup-cert`），权限持久化

## 开发规范

- 使用 **Teams**（多 Agent 协作）进行开发和修复
- **每次修改功能，都要更新 PRD（docs/PRD.md）和架构设计（docs/Architecture.md）**
- **每完成一个功能或大修改，自动使用 `/commit` skill 提交并推送到远程仓库**
- **每次修复或新开发完成后，必须执行 `make install` 安装到本地**

## ⚠️ 高频 Bug 防范：窗口标题"无标题"

**根因**：codesign --force 改变 CDHash → TCC 失效 → AXIsProcessTrusted() 返回 false → 所有窗口标题变成"(无标题)"

**必检项**：每次修改 WindowService / PermissionManager / 安装流程后：
1. 测试首次安装（无 TCC 记录）→ 弹授权 → 授权后标题正常
2. 测试重新安装（有旧 TCC 记录）→ 权限失效 → 重新授权后恢复
3. 测试正常运行 → 所有窗口标题正确

**绝对禁止**：在 buildAXTitleMap 中用 `PermissionManager.shared.accessibilityGranted` 缓存值代替 `AXIsProcessTrusted()` 实时调用
