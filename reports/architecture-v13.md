# PinTop V1.3 增量架构文档

**日期**: 2026-03-01
**范围**: 4 项需求（2 Feature + 1 UI + 1 UX 优化）+ PRD 文档更新
**规模**: M（6-8 个文件修改）

---

## 1. 需求清单

| # | 类型 | 描述 |
|---|------|------|
| 1 | UX | 关闭主看板窗口 = 退出整个 App |
| 2 | Feature | Dock 栏显示 PinTop 图标 |
| 3 | UI | 悬浮球添加自定义品牌 Logo |
| 4 | Feature | 置顶功能集成到快捷面板正常模式（移除独立置顶模式页） |

---

## 2. 影响分析

### 需求 1: 关闭 = 退出

**现状**: `MainKanbanWindow` 关闭时仅隐藏（`hide()`），App 继续在后台运行
**目标**: 关闭主看板窗口时终止整个 App

**修改文件**:
- `MainKanbanWindow.swift`: `windowShouldClose` 改为调用 `NSApplication.shared.terminate(nil)`

**回归风险**: 低。仅影响主看板关闭行为。

### 需求 2: Dock 栏图标

**现状**: Makefile 在 Info.plist 中设置 `LSUIElement bool true`，App 不显示在 Dock 和 Cmd+Tab
**目标**: App 显示在 Dock 栏，点击 Dock 图标时显示主看板

**修改文件**:
- `Makefile`: 移除 `LSUIElement bool true` 那行
- `AppDelegate.swift`: 实现 `applicationShouldHandleReopen(_:hasVisibleWindows:)` 处理 Dock 图标点击

**行为约束**:
- 点击 Dock 图标（无可见窗口时）→ 打开主看板
- 点击 Dock 图标（主看板已打开）→ 聚焦主看板
- App 在 Cmd+Tab 中可见
- 菜单栏图标保留（statusItem 不受影响）

**回归风险**: 中。LSUIElement 变化影响 App 生命周期行为。

### 需求 3: 悬浮球 Logo

**现状**: 使用 SF Symbol `pin`/`pin.fill` 图标
**目标**: 使用自定义品牌 Logo，保留 Pin 状态视觉反馈

**设计方案**: 程序化绘制品牌 Logo（蓝色渐变背景 + 白色图钉轮廓）
- 正常状态: 蓝灰色调的品牌 Logo
- Pin 状态: 蓝色光晕 + Logo 高亮

**修改文件**:
- `FloatingBallView.swift`: 替换 `iconView`（NSImageView + SF Symbol）为自定义绘制的 Logo 视图

**回归风险**: 低。仅影响悬浮球视觉。

### 需求 4: 置顶功能集成到快捷面板

**现状**:
- 快捷面板有两个模式：正常模式（App 列表）和置顶模式（已 Pin 窗口列表）
- 底部操作栏有"📌 置顶模式"和"← 返回"按钮切换模式
- 窗口行只显示标题，无法直接置顶/取消置顶

**目标**:
- 移除独立的置顶模式页面
- 在每个窗口行**最前面**添加置顶切换图标
- 图标颜色：已置顶 = 红色，未置顶 = 灰色
- 点击图标切换窗口的 Pin 状态
- 移除底部操作栏的"置顶模式"和"返回"按钮

**修改文件**:
- `QuickPanelView.swift`: 重构窗口行布局、移除置顶模式

**接口契约**:
- 窗口行 → PinManager: `PinManager.shared.togglePin(window:)` / `PinManager.shared.isPinned(windowID:)`
- PinManager → 通知: `PinManager.pinnedWindowsChanged` 触发面板刷新

**行为约束**:
| 状态 | 图标 | 颜色 | 点击行为 |
|------|------|------|----------|
| 未置顶 | pin | 灰色 (.tertiaryLabelColor) | togglePin → 变红 |
| 已置顶 | pin.fill | 红色 (.systemRed) | togglePin → 变灰 |

**回归风险**: 中。快捷面板核心交互变更，需验证 Pin/Unpin 功能完整性。

---

## 3. 模块划分

不新增模块，在现有模块内修改：

| 模块 | 修改内容 |
|------|----------|
| FloatingBall | Logo 替换 |
| QuickPanel | 置顶功能集成、底部栏简化 |
| MainKanban | 关闭行为变更 |
| App (AppDelegate) | Dock 图标点击处理 |
| Build (Makefile) | LSUIElement 移除 |
| Docs (PRD.md) | 需求文档更新 |

---

## 4. 验收用例

### TC-01: 关闭主看板 = 退出 App
- 前置：PinTop 运行中
- 操作：点击主看板窗口关闭按钮
- 预期：整个 App 终止（进程结束）

### TC-02: Dock 栏图标可见
- 前置：make install 后启动
- 操作：查看 Dock 栏
- 预期：PinTop 图标显示在 Dock 中

### TC-03: Dock 图标点击
- 前置：PinTop 运行，主看板未打开
- 操作：点击 Dock 图标
- 预期：打开主看板窗口

### TC-04: 悬浮球 Logo
- 前置：PinTop 运行
- 操作：观察悬浮球
- 预期：显示品牌 Logo 而非通用 SF Symbol

### TC-05: 快捷面板置顶按钮
- 前置：hover 悬浮球，展开快捷面板，有多窗口 App
- 操作：查看窗口行
- 预期：每个窗口行最前面有灰色图钉图标

### TC-06: 置顶切换
- 前置：快捷面板展开
- 操作：点击窗口行前面的灰色图钉
- 预期：图标变红色，窗口被置顶

### TC-07: 取消置顶
- 前置：有已置顶窗口
- 操作：点击红色图钉图标
- 预期：图标变灰色，窗口取消置顶

### TC-08: 无独立置顶模式页
- 前置：快捷面板展开
- 操作：查看底部
- 预期：无"📌 置顶模式"按钮，无独立置顶页面

### TC-09: 窗口标题正确（无标题 Bug 回归检查）
- 前置：make install + 授权辅助功能
- 操作：hover 悬浮球查看快捷面板
- 预期：多窗口 App 的窗口标题正确显示，不是"(无标题)"

---

## 5. 非目标

- 不修改窗口标题获取逻辑（V1.2 已稳定）
- 不优化内存占用
- 不修改面板 CPU 性能
- 不实现 DMG 打包
- 不添加新的全局快捷键
