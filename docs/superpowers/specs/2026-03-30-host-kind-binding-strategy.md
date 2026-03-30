# 窗口绑定策略分化：IDE 多 Session 共享 vs Terminal 独占

> 日期：2026-03-30
> 版本：V4.1（coder-bridge hostKind 扩展）

## 1. 需求背景

当前所有 hostApp 统一使用"一窗口一 session"独占绑定策略（`manualWindowID` 驱逐、`autoWindowID` 冲突标红 ✕）。

**矛盾**：
- **Cursor/VSCode（IDE 类）**：一个窗口内嵌多个终端 tab，天然运行多个 AI session → 独占策略导致绑定冲突标红，用户被迫反复手动绑定
- **Terminal/iTerm2/Warp（终端类）**：每个窗口独立运行一个 session → 独占策略合理

## 2. 本期范围界定

**本期做**：新增 `hostKind` 字段，**仅影响"共享/独占"绑定策略**（冲突检测、占用规则、UI 标记）。

**本期不做**：不解决新宿主接入问题。当前方案只对 `HostAppMapping` 已支持的 6 个 hostApp 生效（terminal/iterm2/wezterm/warp/vscode/cursor）。未知 IDE（如 Windsurf）即使上报 `hostKind=ide`，因 `HostAppMapping` 无对应 bundleID，以下三处仍然失败：
- `resolveFrontmostWindow()` — 无法匹配前台窗口
- `findWindowsForHostApp()` — 无法找候选窗口
- `promptBindToCurrentWindow()` / `handleBindToCurrentWindow()` — 无法校验宿主匹配

新宿主接入需下期由 coder-bridge 额外上报 `bundleID`，替代硬编码映射表。

## 3. 模块划分

| 模块 | 文件 | 职责 | 独立变化理由 |
|------|------|------|------------|
| coder-bridge | `registry.sh` | 上报 hostKind 策略标签 | shell 脚本，独立于 Swift 编译 |
| Model | `CoderSession.swift` | HostKind 枚举 + CoderSession 字段 | 数据定义，被 Service 和 UI 共同依赖 |
| Service | `CoderBridgeService.swift` | BindingState helper + 绑定策略逻辑 | 核心业务逻辑 |
| UI | `QuickPanelRowBuilder.swift` + `QuickPanelMenuHandler.swift` | UI 标记 + 两条绑定入口 | 视图层，消费 BindingState |

依赖关系：coder-bridge → (独立) ← Model → Service → UI

## 4. 接口契约

### 4.1 契约：coder-bridge → FocusPilot（DistributedNotification）

**交互方式**：DistributedNotification（`com.focuscopilot.coder-bridge`）

**payload 新增字段**：

| 字段 | 类型 | 值域 | 默认值 | 说明 |
|------|------|------|--------|------|
| `hostKind` | String | `"ide"` / `"terminal"` | `"terminal"` | 桥接层基于环境变量给出的启发式策略标签 |

其他现有字段（event/sid/seq/tool/cwd/cwdNormalized/status/hostApp/ts）不变。

### 4.2 契约：BindingState helper（Service 内部）

```swift
enum BindingState {
    case manual           // manualWindowID != nil
    case autoValid        // manualWindowID == nil, autoWindowID != nil, 无冲突
    case autoConflicted   // manualWindowID == nil, autoWindowID != nil, 有冲突（仅 terminal）
    case missing          // 两个 ID 都是 nil
}
```

**计算规则**：
1. `manualWindowID != nil` → `.manual`
2. `autoWindowID != nil` 且 `isAutoWindowConflicted()` 返回 false → `.autoValid`
3. `autoWindowID != nil` 且 `isAutoWindowConflicted()` 返回 true → `.autoConflicted`
4. 其他 → `.missing`

**注意**：本期不在渲染阶段调用 `windowExists()`。`manual-invalid` 和 `auto-invalid` 为短暂运行态——渲染时不主动识别（看起来像 manual/autoValid），点击时才触发检测清空，UI 上直接退化为 missing。如需渲染阶段精确识别，可下期配合定时刷新做。

**调用方**：`createSessionRow()`、`performWindowSwitch()`、`resolveWindowForSession()` 统一调用此 helper，不再各自重复判断。

### 4.3 契约：HostKind 与绑定规则

| 维度 | `ide`（共享） | `terminal`（独占） |
|------|-------------|-------------------|
| 手动绑定 | 多 session 可共享同一窗口 | 独占，绑定时驱逐旧 session |
| `isAutoWindowConflicted()` | 始终返回 false | 保持现有逻辑 |
| `occupiedWindowIDs` | 不计入 | 计入 |
| 回退匹配排除 | 不排除已绑定的 IDE 窗口 | 排除已被占用的窗口 |
| 未知 hostKind | — | 默认 `.terminal` |

## 5. 行为约束

### 5.1 UI 状态矩阵

| BindingState | terminal 显示 | ide 显示 |
|-------------|--------------|---------|
| `.manual` | 无标记（正常） | 无标记（正常） |
| `.autoValid` | `?`（弱绑定，建议确认） | 无标记（IDE 共享正常） |
| `.autoConflicted` | 红 `✕`（冲突，需手动绑定） | **不会出现**（IDE 不算冲突） |
| `.missing` | 红 `✕`（未绑定） | 红 `✕`（未绑定） |

### 5.2 点击行为矩阵

| BindingState | terminal | ide |
|-------------|----------|-----|
| `.manual` | 激活窗口（点击时检测 windowExists，失效则清空退化为 missing → 走 fallback） | 同左 |
| `.autoValid` | 激活窗口（点击时检测 windowExists + 冲突，失效/冲突则走 fallback） | 激活窗口（点击时检测 windowExists，失效则清空退化为 missing → 走 fallback） |
| `.autoConflicted` | 弹绑定引导（`promptBindToCurrentWindow`） | 不会出现 |
| `.missing` | 弹绑定引导 | 弹绑定引导 |

### 5.3 两条手动绑定入口

| 维度 | `promptBindToCurrentWindow` | `handleBindToCurrentWindow` |
|------|---------------------------|---------------------------|
| 入口 | 点击行 → 无有效绑定时自动触发 | 右键菜单"绑定到当前窗口" |
| terminal 冲突 | **拦截**（显示"该窗口已被绑定"，不允许操作） | **替换确认**（显示"确定替换绑定？旧绑定将被清除"） |
| ide 冲突 | 跳过冲突检测，直接绑定确认 | 跳过冲突警告，直接绑定确认 |
| hostApp 校验 | 保持不变 | 保持不变 |

**产品理由**：自动引导入口（点击行触发）属于隐式操作，不应执行破坏性替换；右键菜单属于显式管理操作，允许用户在确认后替换已有绑定。

## 6. 变更清单

### 6.1 coder-bridge 端（registry.sh）

| 编号 | 改动 |
|------|------|
| A | `normalize_host_app()` 输出增加 hostKind：`echo "cursor ide"` / `echo "terminal terminal"` |
| B | `session_start/update/end` 拆分读取：`host_app="${host_info%% *}"` + `host_kind="${host_info##* }"` |
| C | `send_to_focuspilot()` 新增第 9 参数 `host_kind`，payload 新增 `hostKind` 字段 |

### 6.2 FocusPilot 端

| 编号 | 文件 | 改动 |
|------|------|------|
| D | CoderSession.swift | 新增 `HostKind` 枚举（`.ide` / `.terminal`） |
| E | CoderSession.swift | `CoderSession` 新增 `hostKind: HostKind` 字段 |
| F | CoderBridgeService.swift | 新增 `BindingState` 枚举和 `bindingState(for:)` helper |
| G | CoderBridgeService.swift | `handleDistributedNotification` 解析 `hostKind`，默认 `.terminal` |
| H | CoderBridgeService.swift | `isAutoWindowConflicted()` — IDE 返回 false |
| I | CoderBridgeService.swift | `bindSessionToWindow()` — IDE 不驱逐 |
| I2 | CoderBridgeService.swift | `sessionOccupyingWindow()` — 仅检查 terminal session 的占用（IDE session 不计入占用） |
| J | CoderBridgeService.swift | `occupiedWindowIDs` — 仅统计 terminal |
| K | CoderBridgeService.swift | `resolveWindowForSession()` 使用 bindingState + 回退排除调整 |
| L | QuickPanelRowBuilder.swift | `createSessionRow()` UI 标记使用 bindingState + 状态矩阵 |
| M | QuickPanelRowBuilder.swift | `performWindowSwitch()` 改为调用 `resolveWindowForSession()` + `bindingState`，消除与 K 的重复逻辑 |
| N | QuickPanelRowBuilder.swift | `promptBindToCurrentWindow()` — IDE 跳过冲突拦截 |
| O | QuickPanelMenuHandler.swift | `handleBindToCurrentWindow()` — IDE 跳过冲突警告 |

## 7. 验收用例

### TC-01: IDE 多 session 共享窗口（正常路径）

- 前置条件：Cursor 打开一个项目窗口，启动两个 Claude Code session
- 操作步骤：两个 session 自动绑定到同一 Cursor 窗口
- 预期结果：两个 session 均显示无标记（正常状态），点击任一 session 均能激活同一窗口
- 覆盖类型：正常路径

### TC-02: Terminal 独占绑定（正常路径）

- 前置条件：Terminal.app 打开两个窗口，各启动一个 Claude Code session
- 操作步骤：两个 session 分别自动绑定到各自窗口
- 预期结果：各自显示无标记，点击各自激活对应窗口
- 覆盖类型：正常路径

### TC-03: Terminal 冲突拦截（边界）

- 前置条件：Terminal.app 一个窗口，两个 session 的 autoWindowID 指向同一窗口
- 操作步骤：点击第一个 session（auto 冲突），弹绑定引导
- 预期结果：UI 显示红 ✕（autoConflicted），点击弹出绑定引导
- 覆盖类型：边界

### TC-04: 旧版 coder-bridge 兼容（异常恢复）

- 前置条件：使用旧版 coder-bridge（不上报 hostKind）
- 操作步骤：启动 session
- 预期结果：hostKind 默认 .terminal，行为与升级前完全一致
- 覆盖类型：异常恢复

### TC-05: IDE session 未绑定状态（边界）

- 前置条件：IDE session 的 autoWindowID 和 manualWindowID 均为 nil
- 操作步骤：渲染 session 行
- 预期结果：显示红 ✕（missing 状态，IDE 不豁免未绑定）
- 覆盖类型：边界

### TC-06: 右键菜单绑定（IDE + Terminal 对比）

- 前置条件：一个 IDE session 和一个 Terminal session 均已手动绑定
- 操作步骤：对另一个同类 session 右键"绑定到当前窗口"，目标窗口已被占用
- 预期结果：IDE session 直接确认绑定；Terminal session 显示替换确认对话框
- 覆盖类型：正常路径

### TC-07: IDE session 窗口消失退化（边界）

- 前置条件：IDE session 有 autoWindowID 且窗口有效（autoValid 状态）
- 操作步骤：关闭该 IDE 窗口后点击 session 行
- 预期结果：autoWindowID 被清空，退化为 missing，触发绑定引导弹窗
- 覆盖类型：边界

## 8. 非目标声明

- 不实现新宿主接入（Windsurf/Zed/JetBrains 等）的零改动支持
- 不实现渲染阶段的 `windowExists()` 主动检测（invalid 状态通过点击时检测清空）
- 不修改 `HostAppMapping` 映射表
- 不修改 Session 生命周期管理
- 不修改 DistributedNotification 名称和基础 payload 结构
- 不修改分组显示、置顶/排序/清理逻辑

## 9. 兼容性

| 场景 | 行为 |
|------|------|
| 旧 coder-bridge → 新 FocusPilot | 通知无 `hostKind` → 默认 `.terminal` → 与升级前一致 |
| 新 coder-bridge → 旧 FocusPilot | 多出的 `hostKind` 字段被忽略 → 无影响 |

## 10. 影响分析（增量场景）

- 需修改的现有模块：registry.sh、CoderSession、CoderBridgeService、QuickPanelRowBuilder、QuickPanelMenuHandler
- 需调整的现有接口：`isAutoWindowConflicted()`、`bindSessionToWindow()`、`occupiedWindowIDs`、`resolveWindowForSession()`
- 回归风险点：Terminal 独占绑定行为不应受影响（hostKind 默认 terminal 保障）
