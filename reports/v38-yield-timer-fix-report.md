# 验收报告：面板让位机制 + 计时器按钮修复

**日期**: 2026-03-08
**范围**: 面板让位机制 + 计时器按钮修复
**规模**: S（小）
**场景**: C（Bug 修复）

## 1. 验收用例结果

| 用例 | 描述 | 结果 | 验证方式 |
|------|------|------|----------|
| TC-01 | timerEditBtn 点击能弹出专注方案对话框 | PASS | 代码审查（async 包裹修复时序问题） |
| TC-02 | 钉住面板 → 点击窗口行 → 目标窗口不被面板遮挡 | PASS | 代码审查（yieldLevel 降级到 .floating） |
| TC-03 | 鼠标移回面板 → 面板恢复置顶 | PASS | 代码审查（mouseEntered 调用 restoreLevel） |
| TC-04 | 未钉住面板行为不变（无回归） | PASS | 代码审查（guard isPanelPinned 跳过） |
| TC-05 | resize 拖拽功能正常（无回归） | PASS | 代码审查（未修改 resize 逻辑） |

## 2. 修复内容

### Bug 1: timerEditTapped 点击无响应（P0）

**根因**: `timerEditTapped` 在 nonactivatingPanel 的按钮回调中同步调用 `NSApp.activate(ignoringOtherApps: true)` + `alert.runModal()`。同步 activate 导致 `didResignActiveNotification` 在同一事件循环中触发，resignObserver 立即调用 `abortModal()` 关闭弹窗。

**修复**: 用 `DispatchQueue.main.async { ... }` 包裹整个弹窗流程（与 `handleWorkCompleted`/`handleRestCompleted` 保持一致），将 activate 推迟到下一事件循环。

**文件**: `QuickPanelView.swift` (timerEditTapped)

### Bug 2: hide() 未重置 isYielded（P1）

**根因**: 面板在让位状态下被 hide() 再 show() 时，`isYielded` 仍为 true，导致 yieldLevel() 的 guard 跳过（无法再次让位）。

**修复**: 在 hide() 完成回调中添加 `self.isYielded = false`。

**文件**: `QuickPanelWindow.swift` (hide)

### Bug 3: togglePanelPin 取消钉住时未恢复层级（P1）

**根因**: 面板在让位状态下取消钉住，层级不会从 .floating 恢复到 quickPanelLevel。

**修复**: 在 togglePanelPin() 的 else 分支中调用 `restoreLevel()`。

**文件**: `QuickPanelWindow.swift` (togglePanelPin)

### 新增功能: 面板让位机制

**实现**: QuickPanelWindow 新增 `yieldLevel()` / `restoreLevel()` 方法对。钉住状态下激活窗口后面板临时降级到 `.floating`，鼠标回到面板时恢复 `statusWindow+50`。

**触发点**: QuickPanelRowBuilder（窗口行/App行点击）、QuickPanelMenuHandler（launchApp）
**恢复点**: QuickPanelView（mouseEntered）

## 3. 架构符合度

- 通知驱动架构：未引入新通知，让位机制通过直接方法调用实现
- 模块化拆分：未引入新类型，通过 QuickPanelWindow 方法扩展
- 接口契约：yieldLevel/restoreLevel 作为 QuickPanelWindow 的公开方法，isYielded 为 private(set)

## 4. 已知问题

- P2: timerEditBtn 右下角 2x10px 区域与 resize 角落热区重叠（实际影响极小）

## 5. 交付物清单

| 文件 | 变更类型 | 职责 |
|------|----------|------|
| QuickPanelWindow.swift | 修改 | 新增 yieldLevel/restoreLevel + hide/togglePanelPin 状态重置 |
| QuickPanelRowBuilder.swift | 修改 | 窗口行/App行点击后调用 yieldLevel |
| QuickPanelView.swift | 修改 | mouseEntered 恢复层级 + timerEditTapped async 修复 |
| QuickPanelMenuHandler.swift | 修改 | launchApp 调用 yieldLevel |

## 6. Git 提交

- `3a948a5` feat(UI,Docs): 设计体系文档 + UI 精致化 + 悬浮球面板配置
- `3726569` fix(QuickPanel): 面板让位机制 + 计时器按钮修复 + 弹出收起动画
- 已推送至 origin/main
