# Phase 1 增量架构设计

## 变更概述

四项需求：(1) 删除面板图钉按钮，齿轮移至最右 (2) 悬浮球钉住状态红色发光边框 (3) 新增 hover 回缩开关 (4) 钉住状态不受回缩设置影响

---

## 1.1 模块变更清单

### QuickPanelView.swift

**删除：**
- `panelPinButton` 属性声明（第 88-99 行）
- `setupView()` 中 `topBar.addSubview(panelPinButton)`（第 161 行）
- `panelPinButton.translatesAutoresizingMaskIntoConstraints = false`（第 172 行）
- `panelPinButton` 的 trailing 约束（第 201-202 行）
- `updatePanelPinButton(isPinned:)` 方法（第 316-337 行）
- `panelPinStateChanged(_:)` 通知处理方法（第 311-314 行）
- `setupNotifications()` 中监听 `panelPinStateChanged` 的代码（第 281-286 行）
- `togglePanelPin()` 方法（第 890-894 行）
- `resetToNormalMode()` 中 `updatePanelPinButton(isPinned: false)` 调用（第 446 行）
- `rotatedPinImage(from:)` 静态方法（第 999-1011 行）——仅被 panelPinButton 使用

**修改布局约束：**
- `openKanbanButton` 从左侧（`leadingAnchor + 32`）改为右侧（`trailingAnchor - 8`）
- `runningTabButton` 改为 `leadingAnchor + 32`（原来跟在 openKanbanButton 后面，现在成为最左侧按钮，保留 32px 给悬浮球让位）
- `favoritesTabButton` 保持跟在 `runningTabButton` 后面

### FloatingBallView.swift

**新增：**
- `pinGlowLayer: CALayer` 属性——红色发光边框环 layer
- `setupPinGlowLayer()` 方法——创建并配置发光 layer（初始隐藏）
- 在 `setupView()` 末尾调用 `setupPinGlowLayer()`

**修改：**
- `panelPinStateChanged(_:)` 方法（第 293-295 行）：在设置 `isPanelPinned` 之后，调用 `updatePinGlow(isPinned:)`
- 新增 `updatePinGlow(isPinned: Bool)` 方法：
  - `isPinned == true`：显示 pinGlowLayer，添加脉冲动画
  - `isPinned == false`：隐藏 pinGlowLayer，移除动画
- `updateLayout(size:)` 方法：同步更新 pinGlowLayer 的 frame 和 cornerRadius

### Models.swift — Preferences 结构体

**新增字段：**
- `var autoRetractOnHover: Bool = true`（第 209 行后新增）

**修改解码器：**
- `init(from decoder:)` 中新增：`autoRetractOnHover = try container.decodeIfPresent(Bool.self, forKey: .autoRetractOnHover) ?? true`

### PreferencesView.swift

**修改：**
- `generalSection` 中新增 Toggle：`Toggle("hover 离开后自动收起面板", isOn: $configStore.preferences.autoRetractOnHover)`
- 位于"开机自启动"Toggle 之前

### QuickPanelView.swift — mouseExited

**修改（第 252-260 行）：**
- 在现有 `isPanelPinned` 检查之后，新增 `autoRetractOnHover` 检查：
  ```swift
  // 钉住模式下不触发收起
  if let panelWindow = window as? QuickPanelWindow, panelWindow.isPanelPinned {
      return
  }
  // autoRetractOnHover 关闭时不触发收起
  if !ConfigStore.shared.preferences.autoRetractOnHover {
      return
  }
  ```

### QuickPanelWindow.swift — ballMouseExited / startDismissTimer

**修改 `ballMouseExited()`（第 147-153 行）：**
- 在 `isPanelPinned` 检查之后，新增 `autoRetractOnHover` 检查：
  ```swift
  @objc private func ballMouseExited() {
      guard !isPanelPinned else { return }
      guard ConfigStore.shared.preferences.autoRetractOnHover else { return }
      if isVisible {
          startDismissTimer()
      }
  }
  ```

**无需修改 `startDismissTimer()`**——它已有 `isPanelPinned` guard，且由 `ballMouseExited` 和 `QuickPanelView.mouseExited` 调用，两处调用方已做 autoRetractOnHover 检查。

---

## 1.2 接口契约（变更部分）

### 新增属性

| 文件 | 属性 | 类型 | 默认值 | 说明 |
|------|------|------|--------|------|
| Models.swift | `Preferences.autoRetractOnHover` | `Bool` | `true` | hover 离开后是否自动收起面板 |
| FloatingBallView.swift | `pinGlowLayer` | `CALayer` | hidden | 红色发光边框环 |

### 新增方法

| 文件 | 方法 | 说明 |
|------|------|------|
| FloatingBallView.swift | `setupPinGlowLayer()` | 创建红色发光 CALayer，cornerRadius = ballSize/2，初始隐藏 |
| FloatingBallView.swift | `updatePinGlow(isPinned: Bool)` | 切换发光 layer 可见性和脉冲动画 |

### 删除的接口

| 文件 | 接口 | 说明 |
|------|------|------|
| QuickPanelView.swift | `panelPinButton` | 面板图钉按钮 |
| QuickPanelView.swift | `updatePanelPinButton(isPinned:)` | 图钉按钮状态更新 |
| QuickPanelView.swift | `togglePanelPin()` | 图钉按钮点击事件 |
| QuickPanelView.swift | `rotatedPinImage(from:)` | 图钉旋转图片 |
| QuickPanelView.swift | `panelPinStateChanged(_:)` | 面板钉住通知监听 |

### 复用的通知（无新增）

| 通知名 | 发送者 | 接收者 | 用途 |
|--------|--------|--------|------|
| `panelPinStateChanged` | QuickPanelWindow | FloatingBallView | 钉住状态变化 → 悬浮球更新发光边框 |

---

## 1.3 行为约束

### 状态转换矩阵

| 钉住状态 | autoRetractOnHover | hover 离开面板 | hover 离开悬浮球 | 预期行为 |
|---------|-------------------|---------------|-----------------|---------|
| 已钉住 | true | 不收起 | 不收起 | 钉住优先级最高，忽略所有回缩 |
| 已钉住 | false | 不收起 | 不收起 | 同上 |
| 未钉住 | true | 500ms 后收起 | 500ms 后收起 | 现有默认行为 |
| 未钉住 | false | 不收起 | 不收起 | 面板保持显示，直到用户主动关闭 |

### 判断顺序（mouseExited / ballMouseExited）

```
1. isPanelPinned == true → return（不收起）
2. autoRetractOnHover == false → return（不收起）
3. 启动 500ms dismissTimer
```

### 悬浮球发光边框状态

| 钉住状态 | 悬浮球外观 |
|---------|-----------|
| 已钉住 | 红色发光边框环（带脉冲动画） |
| 未钉住 | 无边框（当前默认样式） |

### pinGlowLayer 规格

- 类型：CALayer（圆环，非填充）
- 颜色：`NSColor.systemRed`
- 边框宽度：2.5px
- 阴影：`shadowColor = systemRed, shadowRadius = 6, shadowOpacity = 0.8`
- 动画：shadowOpacity 在 0.4 ↔ 0.9 间循环，duration = 1.2s
- 尺寸：与悬浮球同大，跟随 `updateLayout(size:)` 同步

---

## 1.4 验收用例

### UC-1: 面板顶部栏布局正确
- 打开面板 → 顶部栏左侧为 Tab 按钮（活跃/收藏），右侧为齿轮图标
- Tab 按钮左侧有 32px 空白（给悬浮球让位）
- 无图钉按钮

### UC-2: 齿轮按钮功能正常
- 点击齿轮 → 打开主看板
- 与之前行为一致

### UC-3: 悬浮球钉住状态显示红色发光边框
- 单击悬浮球（钉住面板）→ 悬浮球出现红色发光边框环，有脉冲动画
- 再次单击悬浮球（取消钉住）→ 红色边框消失
- 通过快捷键触发钉住 → 同样出现红色边框

### UC-4: hover 回缩设置 = ON（默认）
- 偏好设置中"hover 离开后自动收起面板"开启
- hover 进入悬浮球 → 面板弹出 → 鼠标移出面板 → 500ms 后面板收起
- 与现有行为一致

### UC-5: hover 回缩设置 = OFF
- 偏好设置中关闭"hover 离开后自动收起面板"
- hover 进入悬浮球 → 面板弹出 → 鼠标移出面板 → 面板不收起
- 面板保持显示直到：单击悬浮球钉住/取消钉住、快捷键隐藏、拖拽悬浮球

### UC-6: 钉住状态不受回缩设置影响
- 无论 autoRetractOnHover 开/关，钉住状态下面板都不会收起
- 钉住状态通过单击悬浮球切换（现有逻辑）

### UC-7: 悬浮球大小变化后发光边框同步
- 在偏好设置中拖动悬浮球大小滑块
- 如果当前处于钉住状态，红色发光边框随悬浮球大小同步缩放

### UC-8: 设置持久化
- 关闭"hover 离开后自动收起面板" → 退出应用 → 重新启动
- 设置保持为关闭状态

---

## 1.5 非目标声明

- **不创建新文件**：所有变更在现有 7 个文件中完成
- **不引入新通知名称**：复用现有 `panelPinStateChanged` 通知
- **不修改核心窗口管理逻辑**：不改变 show/hide/togglePanelPin 的核心流程
- **不修改 ConfigStore 的保存/加载机制**：`autoRetractOnHover` 作为 Preferences 的一部分，自动参与现有的 encode/decode 流程
- **不修改 Constants.swift**：无需新增常量（发光 layer 参数内联在 FloatingBallView 中）
- **不修改 AppDelegate.swift**：通知路由和面板管理逻辑不变
