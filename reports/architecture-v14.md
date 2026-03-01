# PinTop V1.4 增量架构设计

## 0. 版本信息

| 项目 | 值 |
|---|---|
| 基线版本 | V1.3 |
| 目标版本 | V1.4 |
| 需求数量 | 7 项（1a/1b/1c/2/3/4/5） |
| 新增文件 | 0 |
| 修改文件 | 7 |

---

## 1. 影响分析

### 需求 1a: 快捷面板紧凑布局

| 修改文件 | 修改内容 | 回归风险 |
|---|---|---|
| `Constants.swift` | `appRowHeight` 32→28, `windowRowHeight` 28→24, topBar 28→24 | 低：纯尺寸调整 |
| `QuickPanelView.swift` | App 行 edgeInsets 缩小 (top/bottom 4→2), 窗口行 edgeInsets 缩小 (3→2), 图标 20→16, 字体 13→12/12→11 | 中：需验证多窗口 App 场景下列表不截断 |

### 需求 1b: 面板拖拽调整尺寸（Bug 修复）

| 修改文件 | 修改内容 | 回归风险 |
|---|---|---|
| `QuickPanelWindow.swift` | 重写 `sendEvent(_:)` 拦截 resize 热区的鼠标事件，防止事件被 contentView 子视图吞没 | 中：需验证面板内按钮/行点击不受影响 |

**根因分析：** QuickPanelWindow 设置了 `canBecomeKey = false`（非激活面板），且 `styleMask` 含 `.nonactivatingPanel`。虽然 `mouseDown/mouseDragged/mouseUp` 在 NSPanel 层重写了，但 AppKit 的事件分发流程是 `sendEvent → hitTest → view.mouseDown`。由于面板内容视图（QuickPanelView + scrollView）覆盖了整个面板区域，鼠标事件在 resize 热区被子视图的 tracking area 和 scroll view 拦截，导致 NSPanel 层的 mouseDown 从未被调用。

**修复方案：** 在 `QuickPanelWindow` 中重写 `sendEvent(_:)`，对 `.leftMouseDown` 事件先检查是否在 resize 热区，若是则直接调用自身的 mouseDown 处理 resize 逻辑，不再向下分发。

### 需求 1c: 点击悬浮球 → 弹出快捷面板

| 修改文件 | 修改内容 | 回归风险 |
|---|---|---|
| `FloatingBallView.swift` | `handleSingleClick()` 改为发送 `showQuickPanel` 通知（携带 ballFrame），不再发 `openMainKanban`；单击触发时取消 hoverTimer 防止重复触发 | 中：需验证 hover→click→drag 三种交互不冲突 |

### 需求 2: 置顶按钮不生效（Bug 修复）

| 修改文件 | 修改内容 | 回归风险 |
|---|---|---|
| `WindowService.swift` | `setWindowLevel` 增加返回值检查和诊断日志；API 不可用时打印警告；额外调用 AX API `AXUIElementSetAttributeValue` 设置 `AXRaise` 作为补充置顶手段 | 高：涉及 CGS Private API，需在多 macOS 版本测试 |
| `PinManager.swift` | `pin()` 方法在 `setWindowLevel` 后补充调用 `AXRaise` 确保窗口前置；增加 pin 结果验证（读回窗口 layer 确认生效） | 中：需验证 pin/unpin 循环稳定性 |

**根因分析：** `WindowService.setWindowLevel` 使用 CGS Private API（`CGSSetWindowLevel`），存在以下潜在失败点：
1. `dlsym` 加载 SkyLight/CoreGraphics 中的符号失败 → 函数指针为 nil → 方法静默返回
2. `CGSMainConnectionID()` 返回无效连接 → `CGSSetWindowLevel` 调用失败但未检查返回值
3. 某些 macOS 版本或 SIP 策略下 CGS API 行为变化

**修复方案：**
- 在 `setWindowLevel` 中增加 nil 检查日志和返回值检查
- 调用后立即通过 `CGWindowListCopyWindowInfo` 读回目标窗口的 layer 值，验证是否真正生效
- 如果 CGS API 失败，回退到 AX API：通过 `AXUIElementPerformAction(kAXRaiseAction)` 将窗口提升到最前

### 需求 3: 关闭主面板 = 仅隐藏

| 修改文件 | 修改内容 | 回归风险 |
|---|---|---|
| `MainKanbanWindow.swift` | `windowShouldClose` 从 `terminate(nil)` 改为 `orderOut(nil)`，return false | 低：行为简化 |

### 需求 4: 退出机制

| 修改文件 | 修改内容 | 回归风险 |
|---|---|---|
| `MainKanbanView.swift` | 侧边栏底部增加"退出 PinTop"按钮，点击弹出 `.alert` 确认对话框，确认后调用 `NSApplication.shared.terminate(nil)` | 低：纯 UI 增加 |

### 需求 5: 状态栏图标 + Logo 重设计

| 修改文件 | 修改内容 | 回归风险 |
|---|---|---|
| `FloatingBallView.swift` | `createBrandLogo` 方法重构：蓝色渐变底 + 上方图钉 + 下方 "PT" 文字；新增 `highlighted` 参数控制红色/蓝色底色切换 | 中：需验证深色/浅色模式下可见性 |
| `AppDelegate.swift` | `setupStatusBar` 改用自绘 `NSImage`（程序化绘制 PT+图钉 模板图）替代系统 `pin.fill` 符号；监听 `pinnedWindowsChanged` 通知动态切换状态栏图标颜色 | 中：需验证 Retina/非 Retina 屏幕渲染 |

---

## 2. 模块划分与修改内容

### FloatingBallView（悬浮球视图）

| 修改项 | 说明 |
|---|---|
| `handleSingleClick()` | 发送 `showQuickPanel` 通知替代 `openMainKanban` |
| `handleSingleClick()` | 触发时取消 `hoverTimer`，防止与 hover 重复触发面板 |
| `createBrandLogo(size:highlighted:)` | 重绘：蓝色渐变圆底 + 上方白色图钉 + 下方白色 "PT" 文字 |
| `updateBadge(_:)` | 有 Pin 时底色改为红色渐变（原蓝色高亮），光晕改为红色 |

### QuickPanelWindow（快捷面板窗口）

| 修改项 | 说明 |
|---|---|
| `sendEvent(_:)` | 新增重写：拦截 resize 热区鼠标事件，修复拖拽调整尺寸失效 |

### QuickPanelView（快捷面板视图）

| 修改项 | 说明 |
|---|---|
| `createAppRow` | App 行高度 28px，图标 16x16，字号 12pt，内边距缩小 |
| `createWindowRow` | 窗口行高度 24px，字号 11pt，内边距缩小 |
| `topBar` | 高度 28→24px |

### MainKanbanWindow（主看板窗口）

| 修改项 | 说明 |
|---|---|
| `windowShouldClose` | `terminate(nil)` → `orderOut(nil)` + `return false` |

### MainKanbanView（主看板视图）

| 修改项 | 说明 |
|---|---|
| 侧边栏底部 | 新增"退出 PinTop"按钮 + 确认对话框 |

### AppDelegate（应用代理）

| 修改项 | 说明 |
|---|---|
| `setupStatusBar` | 自绘 PT+图钉 模板图标替代系统符号 |
| 新增方法 | `updateStatusBarIcon()` — 监听 Pin 变化动态切换图标 |

### WindowService（窗口服务）

| 修改项 | 说明 |
|---|---|
| `setWindowLevel` | 增加诊断日志、返回值检查、失败回退 |

### PinManager（置顶管理）

| 修改项 | 说明 |
|---|---|
| `pin()` | setWindowLevel 后补充 AXRaise + 结果验证 |

### Constants（常量）

| 修改项 | 说明 |
|---|---|
| `appRowHeight` | 32 → 28 |
| `windowRowHeight` | 28 → 24 |

---

## 3. 接口契约

### 3.1 通知变化

| 变化类型 | 通知名 | 说明 |
|---|---|---|
| **行为变更** | `FloatingBall.openMainKanban` | 不再由悬浮球单击触发；仅由右键菜单 `contextMenuOpenKanban()` 和 AppDelegate 的 Dock/菜单入口触发 |
| **复用** | `FloatingBall.showQuickPanel` | 新增触发源：悬浮球单击（原仅 hover 触发）。携带 `userInfo["ballFrame"]` 不变 |
| **不变** | `FloatingBall.mouseExited` | 不变 |
| **不变** | `FloatingBall.dragStarted` | 不变 |
| **不变** | `FloatingBall.toggleBall` | 不变 |
| **不变** | `PinTop.pinnedWindowsChanged` | 不变，新增消费者：AppDelegate（状态栏图标更新） |

### 3.2 新增方法

| 模块 | 方法 | 签名 | 说明 |
|---|---|---|---|
| `AppDelegate` | `updateStatusBarIcon()` | `private func updateStatusBarIcon()` | 根据 PinManager.pinnedCount 切换状态栏图标（正常/有Pin） |

### 3.3 方法签名变更

无方法签名变更。所有修改在现有方法体内完成。

---

## 4. 行为约束

### 4.1 悬浮球交互状态转换矩阵

```
状态\事件    │ 单击(mouseUp)     │ 双击(mouseUp×2)  │ hover 300ms      │ 拖拽(mouseDragged) │ 右键
─────────────┼───────────────────┼──────────────────┼──────────────────┼────────────────────┼──────────
空闲         │ → 弹出快捷面板     │ → 隐藏悬浮球      │ → 弹出快捷面板    │ → 拖拽中            │ 上下文菜单
面板已弹出   │ → 刷新面板(幂等)   │ → 隐藏悬浮球+面板  │ → 无操作(已显示)  │ → 关闭面板+拖拽     │ 上下文菜单
拖拽中       │ → 吸附边缘         │ N/A              │ N/A              │ → 继续拖拽          │ N/A
半隐藏       │ → 滑出+弹出面板    │ → 隐藏悬浮球      │ → 滑出+弹出面板   │ → 拖拽中            │ 上下文菜单
```

### 4.2 单击 vs Hover 时序处理

```
时间轴：mouseEntered(t=0) → hoverTimer启动(300ms) → mouseDown(t=T₁) → mouseUp(t=T₁+δ)

场景 A: 快速单击 (T₁ < 300ms)
  t=0       mouseEntered, hoverTimer 启动
  t=T₁      mouseDown, clickCount=1
  t=T₁+δ    mouseUp, 启动 250ms clickTimer
  t=T₁+250  clickTimer 触发, handleSingleClick:
             ① 取消 hoverTimer（防止 300ms 时重复触发）
             ② 发送 showQuickPanel 通知

场景 B: 慢 hover 后点击 (T₁ > 300ms)
  t=0       mouseEntered, hoverTimer 启动
  t=300     hoverTimer 触发, 面板已弹出
  t=T₁      mouseDown, clickCount=1
  t=T₁+δ    mouseUp, 启动 250ms clickTimer
  t=T₁+250  clickTimer 触发, handleSingleClick:
             ① hoverTimer 已无效（已触发过）
             ② 发送 showQuickPanel 通知 → show() 幂等刷新面板
```

### 4.3 主看板窗口生命周期

```
V1.3: 点击关闭按钮 → windowShouldClose → terminate(nil) → App 退出
V1.4: 点击关闭按钮 → windowShouldClose → orderOut(nil) → 窗口隐藏, App 后台运行
      退出方式: 侧边栏退出按钮 / 状态栏菜单"退出" / 右键菜单"退出" → 确认对话框 → terminate(nil)
```

### 4.4 Logo 视觉状态

```
                  │ 悬浮球                           │ 状态栏图标
──────────────────┼──────────────────────────────────┼──────────────────
无 Pin            │ 蓝色渐变底 + 白色图钉 + 白色PT    │ 模板图标(跟随系统深浅)
                  │ 黑色阴影呼吸动画                  │
──────────────────┼──────────────────────────────────┼──────────────────
有 Pin            │ 红色渐变底 + 白色图钉 + 白色PT    │ 红色着色图标
                  │ 红色光晕呼吸动画 + 角标数字        │
```

### 4.5 Resize 事件分发

```
sendEvent(event) 入口:
  ├─ event.type == .leftMouseDown ?
  │   ├─ YES: 鼠标位置在 resize 热区?
  │   │   ├─ YES → 自身 mouseDown(event), 启动 resize 流程
  │   │   └─ NO  → super.sendEvent(event), 正常分发给子视图
  │   └─
  ├─ event.type == .leftMouseDragged && isResizing ?
  │   ├─ YES → 自身 mouseDragged(event)
  │   └─ NO  → super.sendEvent(event)
  ├─ event.type == .leftMouseUp && isResizing ?
  │   ├─ YES → 自身 mouseUp(event)
  │   └─ NO  → super.sendEvent(event)
  └─ 其他 → super.sendEvent(event)
```

---

## 5. 验收用例

### 需求 1a: 快捷面板紧凑布局

| ID | 场景 | 预期结果 |
|---|---|---|
| TC-01 | 打开快捷面板，观察 App 行高度 | App 行高度 28px，图标 16x16，文字 12pt |
| TC-02 | 打开快捷面板，观察窗口行高度 | 窗口行高度 24px，文字 11pt |
| TC-03 | 配置 8 个 App，其中 3 个多窗口 | 面板内容紧凑，不超过屏幕 60% 高度，可滚动 |
| TC-04 | 面板钉住后持续显示 | 面板占用空间明显小于 V1.3 |

### 需求 1b: 面板拖拽调整尺寸

| ID | 场景 | 预期结果 |
|---|---|---|
| TC-05 | 鼠标移到面板右边缘（5px 内） | 光标变为左右箭头 |
| TC-06 | 鼠标移到面板底边缘（5px 内） | 光标变为上下箭头 |
| TC-07 | 鼠标移到面板右下角（10px 内） | 光标变为左右箭头（对角 resize） |
| TC-08 | 从右边缘拖拽调整宽度 | 宽度跟随鼠标变化，范围 220-500px |
| TC-09 | 从底边缘拖拽调整高度 | 高度跟随鼠标变化，不超过屏幕 60% |
| TC-10 | 从右下角拖拽同时调整宽高 | 宽高同时变化，范围约束生效 |
| TC-11 | 拖拽后松开鼠标 | 尺寸保存到 ConfigStore，下次打开面板保持 |
| TC-12 | 面板内按钮/行点击 | 不受 resize 拦截影响，正常响应 |

### 需求 1c: 点击悬浮球 → 弹出快捷面板

| ID | 场景 | 预期结果 |
|---|---|---|
| TC-13 | 单击悬浮球 | 快捷面板弹出（而非打开主看板） |
| TC-14 | hover 悬浮球 300ms | 快捷面板弹出（行为不变） |
| TC-15 | hover 后再单击 | 面板刷新，不闪烁 |
| TC-16 | 快速单击（< 300ms hover） | 面板在 ~250ms 后弹出，不出现重复触发 |
| TC-17 | 双击悬浮球 | 悬浮球隐藏（行为不变） |
| TC-18 | 拖拽悬浮球 | 面板关闭，开始拖拽（行为不变） |
| TC-19 | 点击 Dock 图标 | 打开主看板 |
| TC-20 | 右键菜单 → 打开主看板 | 打开主看板 |
| TC-21 | 状态栏菜单 → 打开主看板 | 打开主看板 |

### 需求 2: 置顶按钮不生效

| ID | 场景 | 预期结果 |
|---|---|---|
| TC-22 | 点击窗口行的图钉按钮（pin） | 按钮变红 + 窗口实际置顶（遮住其他窗口） |
| TC-23 | 再次点击图钉按钮（unpin） | 按钮恢复灰色 + 窗口恢复普通层级 |
| TC-24 | Pin 窗口 A，切到其他 App | 窗口 A 保持在最上方 |
| TC-25 | Pin 多个窗口（2-3 个） | 后 Pin 的窗口在上，层级递增 |
| TC-26 | CGS API 不可用时 | 控制台输出警告日志，回退到 AX Raise |
| TC-27 | Pin 后最小化窗口 | 自动 Unpin |

### 需求 3: 关闭主面板 = 仅隐藏

| ID | 场景 | 预期结果 |
|---|---|---|
| TC-28 | 点击主看板关闭按钮（红色 ×） | 窗口隐藏，App 继续后台运行，悬浮球仍可见 |
| TC-29 | 关闭主看板后点击 Dock 图标 | 主看板重新显示 |
| TC-30 | 关闭主看板后 hover 悬浮球 | 快捷面板正常弹出 |

### 需求 4: 退出机制

| ID | 场景 | 预期结果 |
|---|---|---|
| TC-31 | 点击侧边栏"退出 PinTop"按钮 | 弹出确认对话框："是否确认退出 PinTop？" |
| TC-32 | 确认对话框点击"确认" | App 退出（所有 Pin 清除，窗口关闭） |
| TC-33 | 确认对话框点击"取消" | 对话框关闭，App 继续运行 |
| TC-34 | 状态栏菜单 → 退出 PinTop | App 直接退出（现有行为保留） |
| TC-35 | 右键菜单 → 退出 PinTop | App 直接退出（现有行为保留） |

### 需求 5: 状态栏图标 + Logo 重设计

| ID | 场景 | 预期结果 |
|---|---|---|
| TC-36 | 启动 App，无 Pin | 悬浮球：蓝色渐变底 + 白色图钉 + 白色 "PT" |
| TC-37 | Pin 一个窗口 | 悬浮球：红色渐变底 + 白色图钉 + 白色 "PT" + 红色光晕 + 角标"1" |
| TC-38 | Unpin 所有窗口 | 悬浮球恢复蓝色底 + 黑色阴影呼吸动画 |
| TC-39 | 状态栏图标（无 Pin） | 显示 PT+图钉 模板图标，跟随系统深浅色 |
| TC-40 | 状态栏图标（有 Pin） | 图标切换为红色着色 |
| TC-41 | 深色模式下悬浮球 | Logo 文字和图钉清晰可见 |
| TC-42 | 浅色模式下状态栏 | 图标清晰可见，不与背景混淆 |

---

## 6. 非目标声明

1. **不新增文件**：所有修改在现有 7 个文件内完成
2. **不新增抽象层**：不引入新 Protocol、基类或中间层
3. **不修改数据模型**：ConfigStore、AppConfig、PinnedWindow 等模型不变
4. **不修改快捷键系统**：HotkeyManager 不变
5. **不修改 App 监控逻辑**：AppMonitor 不变
6. **不做国际化**：所有 UI 文字保持中文硬编码
7. **不支持 App Icon 资源替换**：Logo 仍为程序化绘制，不新增 Asset Catalog 资源
8. **不修改权限管理**：PermissionManager 不变
9. **不修改窗口枚举 `layer == 0` 过滤**：已 Pin 窗口的 layer 变化不影响 QuickPanel 列表（列表数据来自 AppMonitor 的定时刷新，Pin 状态通过 PinManager.isPinned 独立查询）
