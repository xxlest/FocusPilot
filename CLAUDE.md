# FocusPilot 项目指南

## 项目概述

FocusPilot是 macOS 悬浮球应用，支持窗口快捷切换。
纯 Swift 5 + AppKit/SwiftUI，无第三方依赖。Bundle ID: `com.focuspilot.FocusPilot`

三层交互：悬浮球（常驻入口）→ 快捷面板（hover/单击弹出）→ 主看板（双击/Dock 图标）

## 文档体系

- **产品需求（主）**：`docs/PRD.md` — FocusPilot 0.0.1 主 PRD（两阶段模型、四模式、Crew、知识管道、Dashboard）
- **产品需求（归档）**：`docs/archive/PRD-v4-legacy.md` — FocusPilot V4.x 既有功能清单、交互规则、验收标准
- **技术架构**：`docs/Architecture.md` — 模块划分、接口契约、状态机
- **设计规范**：`docs/DesignGuide.md` — 视觉准则、主题色值、动画参数、修改规则
- **版本规划**：`docs/Editions.md` — 个人版/企业版功能边界、付费方案

修改 UI 前必读 DesignGuide.md，修改业务逻辑前必读 Architecture.md，修改功能边界时必读 Editions.md。PilotOne 新功能开发前必读 PRD.md。

## 产品设计基调

**新增功能时必须对照以下四条准则评估，不符合的不做。**

**干净** — 每个功能只解决一个问题，三层架构各司其职，功能之间不互相污染

**高级** — 宁做一个极致的功能，不做三个粗糙的。追求完成度，不追求数量

**克制** — 新功能必须能回答"没有它用户会怎样"。不做平台化、社交化。设置项能用默认值解决的不暴露选项

**专业** — 不打断（弹窗失焦自动关闭）、不抢焦点（nonactivating）、不制造决策负担（默认覆盖 90% 场景）

## 架构（V4.2）

技术栈：Swift 5, macOS 14+, arm64, AppKit + SwiftUI, CGS Private API, AX API, Carbon API, DistributedNotificationCenter

### 文件结构（25 个 .swift，~11000 行）

```
FocusPilot/
├── App/
│   ├── FocusPilotApp.swift         # @main 入口
│   ├── AppDelegate.swift           # 生命周期、窗口管理、菜单栏、快捷键、CoderBridgeService 初始化
│   └── PermissionManager.swift     # 辅助功能权限检测（权限授予后自动停止轮询）
├── FloatingBall/
│   ├── FloatingBallWindow.swift    # NSPanel, 层级 statusWindow+100
│   └── FloatingBallView.swift      # 毛玻璃圆球、拖拽吸附、hover 弹出、贴边半隐藏、呼吸动画
├── QuickPanel/
│   ├── QuickPanelWindow.swift        # NSPanel, 层级 statusWindow+50, 动画弹出/收起, 钉住, resize
│   ├── QuickPanelView.swift          # UI 骨架、状态管理、三 Tab 切换（活跃/关注/AI）、reloadData 调度、HoverableRowView
│   ├── QuickPanelRowBuilder.swift    # App 行/窗口行/AI Session 行构建、工具方法、SF Symbol 缓存（extension QuickPanelView）
│   ├── QuickPanelMenuHandler.swift   # 右键菜单、@objc 事件处理、星号关注、App 关闭/启动、AI 会话移除（extension QuickPanelView）
│   └── QuickPanelTimerHandler.swift  # FocusByTime 计时器栏 UI、编辑/阶段转换弹窗、引导休息、辅助类（extension QuickPanelView）
├── MainKanban/
│   ├── MainKanbanWindow.swift      # NSWindow 包裹 SwiftUI
│   ├── MainKanbanView.swift        # 侧边栏+内容区（关注管理 + 偏好设置）
│   ├── AppConfigView.swift         # 关注管理（全部/活跃/关注 三 Tab + 星标切换）
│   └── PreferencesView.swift       # 偏好设置（快捷键、主题选择、悬浮球外观）
├── Models/
│   ├── Models.swift                # AppConfig, RunningApp, WindowInfo, Preferences, AppTheme, ThemeColors 等
│   └── CoderSession.swift          # CoderSession, CoderTool, SessionStatus, SessionLifecycle, HostKind, HostAppMapping, CoderSessionPreference
├── Services/
│   ├── ConfigStore.swift           # UserDefaults 持久化 + 单字段保存（saveBallPosition/savePanelSize/saveWindowRenames）
│   ├── WindowService.swift         # 窗口枚举(CGWindowList+AX)、两阶段刷新、AX 后台队列、titleCache
│   ├── AppMonitor.swift            # App 运行监控、自适应刷新（1s→3s）、scanInstalledApps 后台线程
│   ├── HotkeyManager.swift         # Carbon 全局快捷键（⌘⇧B 显示/隐藏）
│   ├── FocusTimerService.swift     # FocusByTime 番茄钟服务（状态机、计时、阶段切换通知、时长持久化、FocusPendingAction、引导休息分步倒计时）
│   └── CoderBridgeService.swift    # AI 编码工具会话管理（DistributedNotification 监听、session 列表、BindingState 统一 helper、hostKind 策略分流、前台窗口关联、回退匹配、清理定时器、窗口级未读查询/已读标记）
└── Helpers/
    └── Constants.swift             # Ball, Panel, Keys, Notifications 常量
```

### coder-bridge 模块（shell 脚本，安装到 ~/.coder-bridge/）

```
coder-bridge/
├── lib/coder-bridge/
│   ├── adapters/
│   │   ├── claude.sh              # Claude Code hook 适配（解析 stdin JSON → 分发到 registry）
│   │   ├── codex.sh               # Codex 适配（预留）
│   │   └── gemini.sh              # Gemini CLI 适配（预留）
│   ├── core/
│   │   ├── registry.sh            # 会话注册/状态更新/hostKind 上报/osascript DistributedNotification 发送
│   │   ├── notifier.sh            # 桌面通知（原 code-notify）
│   │   └── config.sh              # 配置管理
│   └── utils/                     # colors.sh, detect.sh, help.sh, sound.sh, voice.sh
└── scripts/                       # install.sh, run_tests.sh
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
- **QuickPanel 模块化**：extension 拆分（RowBuilder 负责视图构建、MenuHandler 负责菜单和事件、TimerHandler 负责 FocusByTime 计时器栏+弹窗），不引入新类型
- **Coder-Bridge AI Tab**：第三个 Tab「AI」展示 AI 编码工具会话，通过 DistributedNotificationCenter 接收 coder-bridge 事件
- **AI 会话生命周期**：session.start（注册+前台窗口关联）→ session.update（状态变更）→ session.end（标记 ended 保留显示）
- **两层窗口匹配**：第一层 session.start 时记录前台宿主窗口 → 第二层回退匹配（cwd basename + z-order 最前窗口兜底）
- **HostKind 绑定策略分化**：coder-bridge 上报 hostKind（ide/terminal）作为启发式策略标签；IDE（Cursor/VSCode）允许多 session 共享同一窗口，Terminal 保持独占策略
- **BindingState 统一 helper**：`bindingState(for:)` 枚举（manual/autoValid/autoConflicted/missing）统一供 UI 标记、窗口切换、绑定引导三处调用，消除重复判断
- **两条绑定入口差异化**：promptBindToCurrentWindow（点击触发，隐式）对 terminal 冲突拦截不允许替换；handleBindToCurrentWindow（右键菜单，显式）对 terminal 冲突允许确认替换。IDE 两处均跳过冲突检测
- **Cursor/VSCode 区分**：coder-bridge 通过 CURSOR_TRACE_ID 环境变量区分 Cursor 和 VS Code（两者 $TERM_PROGRAM 均为 vscode）
- **会话不持久化**：CoderSession 列表纯运行时，FocusPilot 重启后清空（AI 工具中断后需重新启动注册）
- **AI 会话偏好持久化**：CoderSessionPreference 按 tool+cwdNormalized+hostApp 索引，存储 displayName；新 session 自动继承同 key 的偏好
- **Transcript 读取**：从 ~/.claude/projects/<sanitized-cwd>/<session-id>.jsonl 提取用户消息（type=="user" + message.role=="user"），用于 query 摘要
- **双行 Session 行**：第一行主信息（工具图标+displayName+宿主图标+状态），第二行最近 query 摘要（10pt nsTextTertiary）
- **Tab 双状态模型**：`selectedTab`（持久，写 UserDefaults）+ `displayTab`（渲染态，hover 预览临时切换）；面板关闭/进入固定模式时 displayTab 回退到 selectedTab
- **Hover 展开/折叠**：非固定模式下 `hoverExpandedBundleID` 驱动，App 行+窗口列表容器包装，`isHidden` 轻量切换不触发 forceReload；displayTab 切换/进入固定模式/面板关闭时清空
- **浮球 AI 角标**：非固定模式下复用 `badgeLabel` 显示 `CoderBridgeService.actionableCount`，监听 coderBridgeSessionChanged + panelPinStateChanged 自驱动
- **关注 Tab 未读角标**：窗口行图标区域根据 `CoderBridgeService.actionableCount(for:)` 动态切换为红色 pill 角标；点击窗口行 `markAsRead(windowID:)` 标记已读（内置 count==1 保护，多 session 共享窗口时静默跳过），通过 `coderBridgeSessionChanged` 通知驱动三处同步刷新
- **Notion 风格主题系统**：AppTheme 枚举 8 种预设 → ThemeColors 9 色槽（ns* + sw* 双套，含 sidebarBackground），覆盖全 UI
- **主题刷新链路**：PreferencesView → @Published → AppDelegate.applyPreferences → NSApp.appearance + quickPanelWindow.applyTheme + themeChanged 通知
- **FocusByTime 番茄钟**：FocusTimerService 单例管理状态机（idle/running/paused × work/rest），通过 NotificationCenter 驱动 QuickPanel 底部计时器栏和 FloatingBall 进度环
- **引导休息模式**：RestIntensity 三级强度（轻度~3min/中度~5min/深度~8min），RestStep 分步定义覆盖脑/眼/肌肉三维恢复；tick() 自动推进步骤，计时器栏显示步骤名+步骤图标+步骤倒计时
- **计时器栏整栏可点击**：栏内零按钮，NSClickGestureRecognizer 整栏点击，根据状态分发到编辑弹窗/操作面板/阶段转换弹窗；hover 时底色加深 + 手形光标；`buildRestGuideView()` 三维分组休息指南
- **idle 双入口**：计时器栏 idle 状态显示「▶ 开始专注 | ☕ 休息」左右并排，点击位置检测分发到 `timerEditTapped()` 或 `restDirectTapped()`
- **独立休息模式**：`isStandaloneRest` 标记直接休息（非工作→休息流程），休息结束后直接 reset 回 idle，不弹"充电完毕"对话框
- **休息选择 UI 共享**：`buildRestSelectionAccessoryView()` 提取引导/自由休息 radio 选择 UI，`handleWorkCompleted()` 和 `restDirectTapped()` 共用
- **FocusByTime 弹窗全失焦关闭**：所有弹窗均失焦自动关闭（NSApp.didResignActive → abortModal）。阶段完成弹窗关闭后，FocusPendingAction 保留待处理动作，计时器栏显示 pending pill 徽章供用户点击重新弹出
- **弹窗层级处理**：NSAlert.runModal() 会重置 layout() 阶段设置的 window level，因此必须通过 `didBecomeKey` 回调延迟设置层级。当前方案：prepareAlert() 先降低面板到 .normal（兜底防遮挡），再用 didBecomeKey 提升弹窗到 alertLevel（floatingBallLevel + 10）；restoreAfterAlert() 恢复面板层级。位置走系统默认居中，不做自定义定位

### 配置迁移

- V3.1: appConfigs 含 isFavorite → 仅保留关注（migrateToV31）
- V3.7: Preferences 移除 colorTheme/ballColorStyle/ballCustomColorHex，新增 appTheme（保留旧 CodingKey 兼容解码）
- V3.8: 新增 FocusTimerService + QuickPanel 计时器栏 + FloatingBall 进度环
- V3.9: FocusTimerService 新增引导休息（RestStep/RestMode/RestIntensity）+ QuickPanel 强度选择弹窗 + 步骤进度列表 + idle 双入口（专注/休息）+ 独立休息模式
- V4.0: 新增 coder-bridge 模块 + CoderBridgeService + AI Tab（三 Tab 快捷面板）+ CoderSession 模型 + DistributedNotification IPC
- V4.1: coder-bridge 新增 hostKind 上报 + CoderSession 新增 HostKind 字段 + BindingState 统一 helper + IDE/Terminal 绑定策略分化
- V4.2: QuickPanelView `currentTab` 拆分为 `selectedTab` + `displayTab`；新增 `hoverExpandedBundleID`；FloatingBallView 新增 AI 角标
- V4.3: 关注 Tab 窗口行新增 AI 未读角标，CoderBridgeService 新增 `actionableCount(for:)` / `markAsRead(windowID:)`
- AppConfig decoder 向后兼容（忽略旧字段）

## 构建

```bash
make build      # 编译到 /tmp/focuspilot-build/
make install    # 编译+签名+安装+启动
make clean      # 清理
```

- 仅 Command Line Tools（无 Xcode IDE），swiftc 直接编译
- VFS overlay 绕过 SwiftBridging module 重复定义 bug
- 自签名证书 `FocusPilot Dev`（`make setup-cert`），权限持久化

## 开发规范

- 使用 **Teams**（多 Agent 协作）进行开发和修复
- **每次修改功能，都要更新 PRD（docs/PRD.md）和架构设计（docs/Architecture.md）；修改 UI 时同步更新设计规范（docs/DesignGuide.md）**
- **每完成一个功能或大修改，自动使用 `/commit` skill 提交并推送到远程仓库**
- **每次修复或新开发完成后，必须执行 `make install` 安装到本地**

## ⚠️ 高频 Bug 防范：窗口标题"无标题"

**根因**：codesign --force 改变 CDHash → TCC 失效 → AXIsProcessTrusted() 返回 false → 所有窗口标题变成"(无标题)"

**必检项**：每次修改 WindowService / PermissionManager / 安装流程后：

1. 测试首次安装（无 TCC 记录）→ 弹授权 → 授权后标题正常
2. 测试重新安装（有旧 TCC 记录）→ 权限失效 → 重新授权后恢复
3. 测试正常运行 → 所有窗口标题正确

**绝对禁止**：在 buildAXTitleMap 中用 `PermissionManager.shared.accessibilityGranted` 缓存值代替 `AXIsProcessTrusted()` 实时调用
