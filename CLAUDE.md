# Focus Copilot 项目指南

## 项目概述

Focus Copilot（原 PinTop）是 macOS 悬浮球应用，支持窗口快捷切换。
纯 Swift 5 + AppKit/SwiftUI，无第三方依赖。Bundle ID: `com.focuscopilot.FocusCopilot`

三层交互：悬浮球（常驻入口）→ 快捷面板（hover/单击弹出）→ 主看板（双击/Dock 图标）

## 架构（V3.4）

技术栈：Swift 5, macOS 14+, arm64, AppKit + SwiftUI, CGS Private API, AX API, Carbon API

### 文件结构（17 个 .swift）

```
PinTop/
├── App/
│   ├── PinTopApp.swift             # @main 入口
│   ├── AppDelegate.swift           # 生命周期、窗口管理、菜单栏、快捷键
│   └── PermissionManager.swift     # 辅助功能权限检测（权限授予后自动停止轮询）
├── FloatingBall/
│   ├── FloatingBallWindow.swift    # NSPanel, 层级 statusWindow+100
│   └── FloatingBallView.swift      # 毛玻璃圆球、拖拽吸附、hover 弹出、贴边半隐藏、呼吸动画
├── QuickPanel/
│   ├── QuickPanelWindow.swift      # NSPanel, 层级 statusWindow+50, 动画弹出/收起, 钉住, resize
│   └── QuickPanelView.swift        # 活跃/收藏双 Tab、差分 UI 更新、窗口行高亮+前置+关闭
├── MainKanban/
│   ├── MainKanbanWindow.swift      # NSWindow 包裹 SwiftUI
│   ├── MainKanbanView.swift        # 侧边栏+内容区（收藏管理 + 偏好设置）
│   ├── AppConfigView.swift         # 收藏管理（全部/活跃/收藏 三 Tab + 星标切换）
│   └── PreferencesView.swift       # 偏好设置（快捷键、悬浮球外观/颜色）
├── Models/
│   └── Models.swift                # AppConfig, RunningApp, InstalledApp, WindowInfo, Preferences, BallColorStyle 等
├── Services/
│   ├── ConfigStore.swift           # UserDefaults 持久化 + 单字段保存（saveBallPosition/savePanelSize/saveWindowRenames）
│   ├── WindowService.swift         # 窗口枚举(CGWindowList+AX)、两阶段刷新、AX 后台队列、titleCache
│   ├── AppMonitor.swift            # App 运行监控、自适应刷新（1s→3s）、scanInstalledApps 后台线程
│   └── HotkeyManager.swift         # Carbon 全局快捷键（⌘⇧B 悬浮球显隐、⌘Esc 主看板显隐）
└── Helpers/
    └── Constants.swift             # Ball, Panel, Keys, Notifications 常量
```

### 关键设计决策

- **通知驱动架构**：FloatingBall → AppDelegate → QuickPanel，通过 NotificationCenter
- **两阶段窗口刷新**：Phase 1 CG 标题主线程快速渲染 → Phase 2 AX 标题后台补全（不阻塞 UI）
- **差分 UI 更新**：QuickPanelView.reloadData 通过 buildStructuralKey 对比，标题变化走 updateWindowTitles 轻量路径
- **窗口标题四级解析**：AX 标题 → 缓存 AX → CG 标题 → "(无标题)"
- **自适应刷新**：面板显示时 1s，无变化时逐步降至 3s；面板隐藏时完全停止
- **收藏机制**：ConfigStore.appConfigs 中存在即为收藏（V3.1 移除了 isFavorite 字段）
- **窗口前置**：NSWorkspace.openApplication + AXRaise + AXMain + AXFocused 三重设置

### 配置迁移

- V2.0: com.pintop.PinTop → com.focuscopilot.FocusCopilot
- V3.1: appConfigs 含 isFavorite → 仅保留收藏（migrateToV31）
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

## ⚠️ 高频 Bug 防范：窗口标题"无标题"

**根因**：codesign --force 改变 CDHash → TCC 失效 → AXIsProcessTrusted() 返回 false → 所有窗口标题变成"(无标题)"

**必检项**：每次修改 WindowService / PermissionManager / 安装流程后：
1. 测试首次安装（无 TCC 记录）→ 弹授权 → 授权后标题正常
2. 测试重新安装（有旧 TCC 记录）→ 权限失效 → 重新授权后恢复
3. 测试正常运行 → 所有窗口标题正确

**绝对禁止**：在 buildAXTitleMap 中用 `PermissionManager.shared.accessibilityGranted` 缓存值代替 `AXIsProcessTrusted()` 实时调用
