# QuickPanelView FocusByTime 拆分方案

## 目标

将 `QuickPanelView.swift`（2600 行）中 ~1600 行 FocusByTime 代码拆到独立 extension 文件 `QuickPanelTimerHandler.swift`，主文件降到 ~1000 行。

## 现状分析

| 文件 | FocusByTime 相关行数 | 占比 |
|---|---|---|
| `QuickPanelView.swift`（2600 行） | ~1600 行（行 176-1775） | 62% |
| `FocusTimerService.swift`（411 行） | 411 行（整个文件） | 100% |
| `FloatingBallView.swift`（1098 行） | ~30 行（进度环） | 3% |
| Constants / ConfigStore | 各几行 | 微量 |

## 拆分方案

### 新文件

```
QuickPanel/QuickPanelTimerHandler.swift  (~1600 行)
```

### 搬迁的 MARK Section

| MARK Section | 行号范围 | 行数 | 内容 |
|---|---|---|---|
| `FocusByTime 底部计时器栏` | 176~797 | ~620 | 计时器栏构建（idle/running/paused/pending 四种状态） |
| `FocusByTime UI 更新` | 798~939 | ~140 | 通知处理、UI 刷新方法 |
| `FocusByTime 对话框` | 940~1190 | ~250 | 编辑弹窗、工作完成弹窗、休息结束弹窗、操作面板 |
| `FocusByTime 计时器栏点击` | 1191~1775 | ~585 | 点击分发、引导休息 UI、科学休息指南、辅助类 |

### 新文件结构

```swift
import AppKit

// MARK: - FocusByTime 计时器栏与弹窗（extension QuickPanelView）

extension QuickPanelView {

    // MARK: - 底部计时器栏
    // buildTimerBar(), updateTimerBar(), buildIdleTimerContent(), ...

    // MARK: - UI 更新
    // handleFocusTimerChanged(), handleFocusWorkCompleted(), ...

    // MARK: - 对话框
    // timerEditTapped(), showWorkCompletedDialog(), showRestCompletedDialog(), ...

    // MARK: - 计时器栏点击
    // handleTimerBarClick(), showRunningActionSheet(), ...
}

// MARK: - 辅助类

class TimerEditHelper: NSObject, NSTextFieldDelegate { ... }
class WorkCompleteHelper: NSObject { ... }
class HoverInfoView: NSView { ... }
```

### 留在 QuickPanelView.swift 中的

| 内容 | 说明 |
|---|---|
| 属性声明 | `timerBar`, `timerService` 等属性保留在主文件（extension 可访问） |
| `setupUI()` 中 `addSubview(timerBar)` | 一行调用 |
| `reloadData()` 中 `updateTimerBar()` 调用 | 一行调用 |
| 通知注册（`addObserver`） | 保留在 `setupNotifications()` 中 |

### 依赖处理

| 依赖项 | 处理方式 |
|---|---|
| `timerBar: NSView` 属性 | 留在主文件，extension 直接访问（同一个类） |
| `timerService` | 留在主文件或直接用 `FocusTimerService.shared` |
| `colors` (ThemeColors) | 留在主文件，extension 直接访问 |
| `prepareAlert()` / `restoreAfterAlert()` | 留在主文件（弹窗通用方法，非 FocusByTime 专属） |
| `TimerEditHelper` / `WorkCompleteHelper` / `HoverInfoView` | 搬到新文件（FocusByTime 专属辅助类） |

### 不改的

- `FocusTimerService.swift` — 已独立
- `FloatingBallView.swift` 进度环 — 30 行，不值得拆
- `Constants.swift` — 不动
- 任何业务逻辑和 UI 行为 — 纯文件搬迁，不改逻辑

### 不建议独立目录的理由

1. FocusByTime UI 是 QuickPanel 底部栏，不是独立窗口
2. 业务逻辑已在 `FocusTimerService.swift` 中独立
3. FloatingBallView 进度环仅 30 行，不值得拆
4. 沿用现有 extension 拆分模式（RowBuilder/MenuHandler），保持一致性

### 风险

低风险：纯 extension 拆分，Swift extension 天然支持跨文件访问同类属性和方法，编译行为完全等价。现有 RowBuilder 和 MenuHandler 已验证此模式可行。

### 验证

1. `make build` 编译通过
2. `make install` 安装后功能验证：idle 双入口 → 开始专注 → 暂停/继续 → 工作完成弹窗 → 引导休息 → 步骤轮播 → 休息结束
