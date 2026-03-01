# Focus Copilot V2.0 架构文档

## 概述

PinTop V1.x → Focus Copilot V2.0 重构，核心变更：
1. Pin 从"窗口置顶"简化为"窗口标记"（纯视觉标记，不控制层级）
2. 窗口激活 Bug 修复（确保切换时目标窗口显示在最上面）
3. Dock 图标调小
4. 品牌改名：PinTop → Focus Copilot

## 变更清单

### 需求 1: PinManager.swift — Pin 简化为标记

**移除项：**
- CGS 层级控制：`setWindowLevel`, `orderWindowAbove`, `enforcePinnedLevels`
- 层级维持机制：`enforcementTimer`, `activationObserver`, `startEnforcementIfNeeded`, `stopEnforcementIfNeeded`
- Pin/Unpin 音效：`NSSound`
- maxPinnedWindows 限制
- AX Observer 监听窗口关闭/全屏自动 Unpin

**保留项：**
- `pinnedWindows` 集合 + `pin/unpin/isPinned/togglePin` 接口
- `notifyChange()` 通知
- `reorder()` 方法（简化为只更新 order）

**pin() 新行为：**
- 仅将窗口添加到 `pinnedWindows` 集合
- 不调用 CGS API，不设置层级，不播放音效
- 无数量限制

### 需求 2: QuickPanelView.swift — 移除过滤功能

**移除项：**
- `pinFilterButton`（置顶过滤按钮）及 `isFilteringPinned` 状态
- `togglePinFilter()` / `updatePinFilterButton()` 方法
- 置顶过滤模式的 UI 代码块
- `titleLabel`（标题标签，仅过滤模式使用）
- pinnedByPin 排序（选中窗口不排到最前）
- Pin 区与非 Pin 区分割线
- handlePinToggle 中超限 Toast

**保留项：**
- 图钉按钮，点击切换选中状态：
  - 未选中：灰色倾斜图钉（pin, secondaryLabelColor）
  - 已选中：红色竖直图钉（pin.fill, systemRed）

### 需求 3: FloatingBallView.swift — 移除 Pin 视觉反馈

**移除项：**
- 角标（badge）显示（updateBadge 中不再显示数字，角标始终隐藏）
- Pin 状态光晕变化（红色光晕、红色呼吸动画）
- Pin 状态品牌 Logo 变化（highlighted 模式）

**保留项：**
- 浮球始终显示正常态橙色渐变
- 呼吸动画（使用固定橙色）

### 需求 4: WindowService.swift — 移除 Pin 层级干扰

**移除项：**
- `activateWindow` 末尾恢复 Pin 窗口层级的逻辑
- `listWindows/listAllWindows` 中 `|| PinManager.shared.isPinned(windowID)` 条件

### 需求 5-6: WindowService.swift — 窗口激活修复

**修复内容：**
- 确保 `app.activate()` 正确调用
- 确保 `raiseWindowViaAX` 正确执行 AXRaise
- 保留延迟 100ms 二次 AXRaise

### 需求 7: AppDelegate.swift — Dock 图标调小

- 图标绘制区域从 256x256 缩小，内容区域使用 padding 居中

### 需求 8: 改名 PinTop → Focus Copilot

**修改位置：**
- Makefile: APP_NAME/BUNDLE_ID/显示文字
- Constants.swift: UserDefaults Keys、通知名称
- AppDelegate.swift: 菜单文字、Dock 图标 PT→FC、状态栏 PT→FC
- FloatingBallView.swift: 品牌 Logo PT→FC
- Info.plist: 通过 Makefile sed 替换
- PermissionManager.swift: 无硬编码 PinTop 文字
- QuickPanelView.swift: 无硬编码 PinTop 文字

## 层级变化

V1.x:
```
normalWindow(0) < pinnedBase(35) < quickPanel(75) < floatingBall(125)
```

V2.0:
```
normalWindow(0) < quickPanel(75) < floatingBall(125)
```

Pin 窗口不再有独立层级，与普通窗口相同。
