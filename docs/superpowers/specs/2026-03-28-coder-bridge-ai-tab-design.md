# Coder-Bridge AI Tab 设计文档

## 概述

在 FocusPilot 快捷面板新增第三个 Tab「AI」，展示通过 coder-bridge 注册的 AI 编码工具会话（Claude Code / Codex / Gemini CLI），支持状态感知、窗口快速切换和会话管理。

### 核心原则

- **session 和 window 关联的目的**：不是为了通知，而是为了 AI Tab 展示宿主窗口、用户点击时快速切回相关窗口
- **前台窗口初始关联为主路径**：`session.start` 时优先记录当前前台宿主窗口，而非依赖复杂的窗口指纹推断
- **不追求首次 100% 精确匹配**：多个同标题窗口时，允许先切到任意合理候选；切错一次可接受，用户通过改名或手动绑定修正
- **持久化用户意图，不持久化运行时标识**：CGWindowID 等瞬时 ID 不落盘；session 列表纯运行时，FocusPilot 重启后清空
- **不做复杂的窗口指纹推断作为主路径**：AX/CG 用于操作和枚举窗口，不依赖"从 session 精确反推唯一窗口"的复杂链路

---

## 1. 数据模型

### 1.1 CoderSession（运行时，不持久化）

AI 编码工具的一次会话实例，生命周期从 `session.start` 到清理移除。

```swift
struct CoderSession: Identifiable {
    let sessionID: String               // UUID，全局唯一，不复用
    var tool: CoderTool                  // claude / codex / gemini
    var cwd: String                      // 工作目录（原始路径）
    var hostApp: String                  // "cursor" / "terminal" / "iterm2" / ""
    var status: SessionStatus            // 业务态
    var lifecycle: SessionLifecycle      // 生命周期态
    var lastSeq: Int                     // 最后处理的 seq，防乱序
    var lastUpdate: Date
    var isHidden: Bool                   // session 级临时 UI 状态

    // 运行时窗口关联（不持久化）
    var initialCandidateWindowID: CGWindowID?  // session.start 时记录的前台宿主窗口
    var candidateWindowID: CGWindowID?         // 当前最佳候选窗口（初始关联或回退匹配）
    var matchConfidence: MatchConfidence       // high / low / none

    // 关联的用户偏好（通过 preferenceKey 查找 CoderSessionPreference）
    var preferenceKey: String {
        "\(tool.rawValue):\(cwdFingerprint):\(hostApp)"
    }

    /// 规范化路径指纹：优先 git repo root，其次 realpath(cwd)
    /// 避免同一项目因子目录、软链等产生多份偏好
    var cwdFingerprint: String {
        // 实现时：先尝试 git rev-parse --show-toplevel
        // 失败则 realpath(cwd)
        // coder-bridge 侧在 hook 脚本中计算并传入
        cwdNormalized
    }
    var cwdNormalized: String = ""       // 由 coder-bridge 上报的规范化路径
}

enum CoderTool: String, Codable { case claude, codex, gemini }
enum SessionStatus: String, Codable { case registered, working, idle, done, error }
enum SessionLifecycle: String, Codable { case active, ended }
enum MatchConfidence: String, Codable { case high, low, none }
```

### 1.2 CoderSessionPreference（持久化）

用户对某个 tool + cwdFingerprint + hostApp 组合的偏好设置，独立于 session 生命周期。新 session 自动继承。

```swift
struct CoderSessionPreference: Codable {
    let key: String                      // "claude:<repo-root-path>:cursor"
    var displayName: String              // 用户改的名字（默认 cwd basename）
    var windowHint: WindowHint?          // 手动绑定线索（P1 增强能力，非主路径）
    var isPinned: Bool                   // 置顶
}

struct WindowHint: Codable {
    let hostBundleID: String             // "com.todesktop.cursor"
    let matchTokens: Set<String>         // 从标题提取的归一化 token
    let cwdFingerprint: String
}
```

### 1.3 关键设计决策

- `isHidden` 在 CoderSession 上（session 级临时态），不在 Preference 上（避免永久隐藏未来会话）
- `displayName` 和 `windowHint` 在 Preference 上（按 tool+cwdFingerprint+hostApp 索引），session 结束后偏好保留
- `initialCandidateWindowID` 和 `candidateWindowID` 纯运行时，不持久化
- `cwdFingerprint` 使用规范化路径（git repo root 优先，realpath 兜底），确保同一项目不会因子目录或软链产生多份偏好
- `WindowHint` 是 P1 增强能力，不是主匹配路径；主路径是 `initialCandidateWindowID` + 回退匹配

---

## 2. 状态机

### 2.1 状态定义（两个正交维度）

**业务态（status）**：AI 工具当前在做什么

| 状态 | 含义 |
|------|------|
| `registered` | 刚注册，尚未收到后续事件 |
| `working` | AI 正在输出 / 执行工具 |
| `idle` | AI 停下等待用户输入 |
| `done` | AI 完成本轮任务 |
| `error` | 本轮因 API 错误终止 |

**生命周期态（lifecycle）**：session 本身的存活状态

| 状态 | 含义 |
|------|------|
| `active` | 正常运行中 |
| `ended` | 收到 session.end，保留显示等用户确认或超时 |

### 2.2 事件与状态迁移

**3 个核心事件**：

| 事件 | hook 来源 | 迁移 |
|------|----------|------|
| `session.start` | SessionStart hook | → status=registered, lifecycle=active；同时记录前台宿主窗口为 initialCandidateWindowID |
| `session.update` | Stop / Notification hook | → status 由字段指定（working/idle/done/error），lifecycle 不变 |
| `session.end` | SessionEnd hook | → lifecycle=ended，status 保持不变 |

**乱序防护**：每个事件携带 `seq`（session 内单调递增）。`if seq <= lastSeq then drop`。

### 2.3 清理策略

| 条件 | 动作 |
|------|------|
| done/error + ended → 用户右键菜单"移除已结束的会话" | 移除 |
| done/error + ended → 30 分钟超时 | 移除 |
| working/idle/registered + ended → 5 分钟超时 | 移除 |
| ended + session.start（同 sid） | 拒绝，sid 不复用 |
| FocusPilot 重启 | 清空所有 session（等重新注册） |

---

## 3. IPC 协议

### 3.1 传输方式

coder-bridge（shell 脚本）→ macOS DistributedNotificationCenter → FocusPilot（Swift）

通知名：`com.focuscopilot.coder-bridge`

### 3.2 消息格式

```json
{
    "event": "session.start | session.update | session.end",
    "sid": "uuid-v4",
    "seq": 1,
    "tool": "claude | codex | gemini",
    "cwd": "/absolute/path",
    "cwdNormalized": "/repo/root/path",
    "status": "working | idle | done | error",
    "hostApp": "cursor | terminal | iterm2 | vscode | ...",
    "ts": 1711584000
}
```

**字段说明**：
- `event` + `status` 分离：event 决定操作类型，status 决定业务态
- `seq`：session 内单调递增，防乱序覆盖
- `cwd`：原始工作目录
- `cwdNormalized`：规范化路径（git repo root 优先，realpath 兜底），用于偏好索引
- `hostApp`：从 `$TERM_PROGRAM` 推断并归一化，辅助字段（见 3.4 归一化规则）
- `sid`：必须 UUID，禁止复用

### 3.3 FocusPilot 接收端

```swift
// AppDelegate 中注册
DistributedNotificationCenter.default().addObserver(
    self,
    selector: #selector(handleCoderBridgeEvent(_:)),
    name: NSNotification.Name("com.focuscopilot.coder-bridge"),
    object: nil
)
```

### 3.4 hostApp 归一化规则

coder-bridge 侧根据 `$TERM_PROGRAM` 环境变量归一化为标准值：

| `$TERM_PROGRAM` 原始值 | 归一化 hostApp | 对应 bundleID |
|------------------------|---------------|---------------|
| `Apple_Terminal` | `terminal` | `com.apple.Terminal` |
| `iTerm.app` / `iTerm2` | `iterm2` | `com.googlecode.iterm2` |
| `WezTerm` | `wezterm` | `com.github.wez.wezterm` |
| `WarpTerminal` | `warp` | `dev.warp.Warp-Stable` |
| `vscode` | `vscode` | `com.microsoft.VSCode` |
| `cursor` | `cursor` | `com.todesktop.230313mzl4w4u92` |
| 其他 / 未设置 | `""` (空) | — |

```bash
# coder-bridge 侧归一化逻辑
normalize_host_app() {
    case "${TERM_PROGRAM:-}" in
        Apple_Terminal)     echo "terminal" ;;
        iTerm.app|iTerm2)   echo "iterm2" ;;
        WezTerm)            echo "wezterm" ;;
        WarpTerminal)       echo "warp" ;;
        vscode)             echo "vscode" ;;
        cursor)             echo "cursor" ;;
        *)                  echo "" ;;
    esac
}
```

FocusPilot 侧维护一张 `hostApp → bundleID` 映射表，用于 `session.start` 时判断"前台窗口所属 app 与 hostApp 是否一致"。

---

## 4. 窗口关联与匹配

### 4.1 设计说明

`session.start` 时，FocusPilot 优先将 session 关联到当前前台且宿主应用一致的窗口，作为运行时初始候选。独立终端场景关联到当前终端窗口；Cursor/VSCode 集成终端场景关联到当前 IDE 主窗口。该关联不持久化，仅用于提升首次点击命中率；若候选失效，再退回到基于宿主 app、cwd 和标题的常规匹配。

### 4.2 两层匹配模型

**第一层：初始关联（主路径）**

`session.start` 事件到达时：
1. FocusPilot 立即读取当前前台窗口（`NSWorkspace.shared.frontmostApplication` + CGWindowList 获取该 app 的最前窗口）
2. 如果前台窗口所属 app 与 `hostApp` 一致，记为 `initialCandidateWindowID`
3. 如果不一致或无法获取，`initialCandidateWindowID` 为 nil，退回第二层

**场景说明**：

| 场景 | 行为 |
|------|------|
| 独立终端（iTerm2 / Terminal.app） | 用户在前台终端窗口启动 AI 工具 → 关联到该终端窗口 |
| IDE 集成终端（Cursor / VSCode） | 用户在 IDE 内置 terminal 启动 AI 工具 → 关联到当前 IDE 主窗口（不尝试识别底部 terminal tab） |
| 前台窗口与 hostApp 不一致 | 用户可能通过脚本等方式启动 → 不做初始关联，退回第二层 |

**第二层：回退匹配**

当 `initialCandidateWindowID` 失效（窗口已关闭/重建）或不存在时，按以下优先级匹配：

```
resolveWindow(session) -> (CGWindowID?, MatchConfidence)

P0 规则（按优先级）：
1. 同宿主 app 的窗口中，cwd basename 命中窗口标题 → .high
2. 同宿主 app 只有一个窗口 → .low
3. 同宿主 app 有多个窗口，无法区分 → 取窗口列表第一个可见候选（CGWindowList z-order 最前）→ .low
4. 全部未命中 → .none

P1 新增规则（插入到 P0 规则之前）：
0. WindowHint 匹配 → .high（用户手动绑定过，最高优先级）

P1 增强规则（插入到规则 1 和 2 之间）：
1.5. 同宿主 app 的窗口中，cwd 高信息 token 命中窗口标题 → .low
```

**Token stopwords 过滤**（P1 启用，不参与匹配的低信息词）：
```
users, home, workspace, documents, desktop, code, projects,
src, app, web, server, client, lib, packages, repos, dev,
var, tmp, opt, usr, volumes + 当前用户名
```

### 4.3 点击行为

```
点击 CoderSession 行：

1. initialCandidateWindowID 仍存在于窗口列表中？
   → 直接 activateWindow + yieldLevel（.high）

2. 退回回退匹配，得到候选窗口：
   - .high → 直接 activateWindow + yieldLevel
   - .low  → 也直接切到该候选窗口 + 行背景短暂闪烁提示（0.6s accent 色 flash）
   - .none → 只激活宿主 App

3. 多个候选同分 → 取最近活跃的，直接切（不弹选择器）
```

用户切错了 → 右键改名 → 标题自然区分 → 下次匹配准确。

### 4.4 手动绑定（P1 增强能力）

```
右键 → "绑定到窗口..." → 子菜单列出同宿主 App 的窗口
→ 用户选择
→ 存 WindowHint { hostBundleID, matchTokens(从标题提取), cwdFingerprint }
→ 后续匹配时 WindowHint 作为最高优先级（回退规则第 0 步）
```

WindowHint 是用户可选增强，不承担"解决所有同标题窗口"的核心责任。

**限制说明**：如果窗口标题仍是低信息标题（如 `Default`、`Claude`），手动绑定后 matchTokens 区分度不足，提升有限。建议用户先改窗口名再绑定，改名后标题自然不同，匹配自然准确。

---

## 5. AI Tab UI 设计

### 5.1 Tab 栏

```
┌─ 运行中 ─┬─ 关注 ─┬─ AI ─┐
│          │        │  (3) │   ← 角标 = actionable 会话数
└──────────┴────────┴──────┘
```

角标计算（actionable 组合态白名单）：

```swift
let actionable: [(SessionStatus, SessionLifecycle)] = [
    (.idle, .active),
    (.done, .active),
    (.done, .ended),
    (.error, .active),
    (.error, .ended),
]
```

注意：`working + ended` 不算 actionable，不进角标。

### 5.2 排序规则

```
第一档：actionable（需要用户处理）
  idle+active, done+active, done+ended, error+active, error+ended
  → 内部按 lastUpdate 倒排

第二档：passive（不需要处理）
  working+active, registered+active, working+ended
  → 内部按 lastUpdate 倒排

第三档：faded（已结束但不紧急）
  idle+ended, registered+ended
  → 内部按 lastUpdate 倒排
```

### 5.3 Session 行视觉

```
┌─ HoverableRowView (高度 32px) ─────────────────────────────┐
│ [●] [⬡] FocusPilot                 [Cursor图标]  等待输入  │
│  ↑   ↑       ↑                         ↑            ↑      │
│ 状态 工具  displayName              宿主图标      状态文字   │
└────────────────────────────────────────────────────────────┘
```

#### 状态圆点 + 文字（组合态总表）

| status | lifecycle | 状态文字 | 圆点颜色 | 行透明度 | 排序档 | 角标 |
|--------|-----------|---------|---------|---------|--------|------|
| idle | active | "等待输入" | 蓝+光晕 | 1.0 | 1 | ✅ |
| done | active | "已完成" | 绿+光晕 | 1.0 | 1 | ✅ |
| done | ended | "已完成 · 已结束" | 绿+光晕 | 0.7 | 1 | ✅ |
| error | active | "出错" | 红+光晕 | 1.0 | 1 | ✅ |
| error | ended | "出错 · 已结束" | 红+光晕 | 0.7 | 1 | ✅ |
| working | active | "执行中" | 蓝 | 1.0 | 2 | ❌ |
| working | ended | "执行中 · 已结束" | 蓝 | 0.7 | 2 | ❌ |
| registered | active | "已连接" | 灰 | 1.0 | 2 | ❌ |
| idle | ended | "等待输入 · 已结束" | 蓝 | 0.5 | 3 | ❌ |
| registered | ended | "已连接 · 已结束" | 灰 | 0.5 | 3 | ❌ |

#### 工具图标（14px）

| 工具 | 图标 | SF Symbol |
|------|------|----------|
| Claude | ⬡ | `hexagon` |
| Codex | ◈ | `diamond` |
| Gemini | ✦ | `sparkle` |

颜色：`nsTextSecondary`，不用品牌色。

#### 宿主 App 图标（16px）

使用宿主 app 的 NSImage（和 Running tab 的 app icon 一样取法）。hostApp 为空时不显示。

匹配 confidence 反馈：
- `.high`：正常显示
- `.low`：宿主图标右下角加 `?` 小角标
- `.none`：宿主图标正常显示，右下角加 `✕` 标记

#### Hover 效果

复用 HoverableRowView 现有行为。actionable 行 hover 时背景用对应状态色 0.08α（蓝/绿/红）。

### 5.4 右键菜单

P0：
```
移除此会话           ← 仅删当前这条 ended session
────
移除所有已结束会话    ← 批量删除所有 ended session
```

P1：
```
改名...
绑定到窗口 →  （子菜单列出同宿主 App 的窗口）
解除绑定
────
隐藏此会话
移除已结束的会话
```

### 5.5 隐藏会话入口（P1）

有隐藏会话时，Tab 底部显示：

```
┌─────────────────────────────────┐
│  隐藏的会话 (2)            ▶    │   ← 点击展开/收起
└─────────────────────────────────┘
```

11pt，`nsTextTertiary`，只在有隐藏会话时出现。

### 5.6 空状态

```
┌─────────────────────────────────┐
│                                 │
│    还没有 AI 编码会话           │
│    启动一个 AI 编码工具后       │
│    会自动显示在这里             │
│                                 │
└─────────────────────────────────┘
```

11pt，`nsTextTertiary`，居中。

---

## 6. coder-bridge 侧实现

### 6.1 目录结构

```
FocusPilot/coder-bridge/
├── bin/coder-bridge
├── lib/coder-bridge/
│   ├── adapters/
│   │   ├── claude.sh          # Claude Code hook 适配
│   │   ├── codex.sh           # Codex 适配（预留）
│   │   └── gemini.sh          # Gemini CLI 适配（预留）
│   ├── core/
│   │   ├── registry.sh        # 会话注册/状态更新/DistributedNotification 发送
│   │   ├── notifier.sh        # 桌面通知（原 code-notify）
│   │   └── config.sh          # 配置管理
│   ├── commands/
│   └── utils/
└── scripts/
```

### 6.2 cwdNormalized 计算逻辑

coder-bridge 侧在发送事件前计算规范化路径：

```bash
# 优先 git repo root
CWD_NORMALIZED=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)
if [[ -z "$CWD_NORMALIZED" ]]; then
    # 非 git 目录，用 realpath
    CWD_NORMALIZED=$(realpath "$CWD" 2>/dev/null || echo "$CWD")
fi
```

### 6.3 hook 配置示例（Claude Code）

```json
{
  "hooks": {
    "SessionStart": [{
      "hooks": [{
        "type": "command",
        "command": "/path/to/coder-bridge/lib/coder-bridge/adapters/claude.sh SessionStart"
      }]
    }],
    "Stop": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": "/path/to/coder-bridge/lib/coder-bridge/adapters/claude.sh Stop"
      }]
    }],
    "Notification": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": "/path/to/coder-bridge/lib/coder-bridge/adapters/claude.sh Notification"
      }]
    }],
    "SessionEnd": [{
      "hooks": [{
        "type": "command",
        "command": "/path/to/coder-bridge/lib/coder-bridge/adapters/claude.sh SessionEnd"
      }]
    }]
  }
}
```

---

## 7. FocusPilot 侧新增模块

### 7.1 新增文件

| 文件 | 职责 |
|------|------|
| `Services/CoderBridgeService.swift` | DistributedNotification 监听、CoderSession 列表管理（纯运行时）、前台窗口初始关联、清理定时器、偏好持久化 |
| `Models/CoderSession.swift` | CoderSession + CoderSessionPreference + WindowHint 数据结构 |

### 7.2 集成点

| 现有文件 | 改动 |
|---------|------|
| `AppDelegate.swift` | 初始化 CoderBridgeService，转发通知 |
| `QuickPanelView.swift` | 新增 AI Tab 按钮、buildAITabContent()、Tab 角标 |
| `QuickPanelRowBuilder.swift` | 新增 createSessionRow() 方法 |
| `QuickPanelMenuHandler.swift` | 新增 session 右键菜单处理 |
| `Constants.swift` | 新增 coderBridgeSessionChanged 通知名 |
| `ConfigStore.swift` | 新增 sessionPreferences 持久化 |

### 7.3 数据流

```
coder-bridge hook 脚本
  → DistributedNotification("com.focuscopilot.coder-bridge")
  → CoderBridgeService.handleEvent()
  → session.start: 创建 CoderSession + 记录前台宿主窗口为 initialCandidateWindowID
  → session.update: 更新 status
  → session.end: lifecycle → ended
  → 为每个 session 验证 initialCandidateWindowID 是否仍有效，失效则执行回退匹配
  → post NotificationCenter("coderBridgeSessionChanged")
  → QuickPanelView.reloadData()
  → AI Tab 重建 session 行
```

---

## 8. 分期计划

### P0：MVP ✅ 已完成

- CoderSession 模型 + 状态机（status + lifecycle 双维度）
- DistributedNotification 收发（osascript + ObjC bridge）
- **前台宿主窗口初始关联**（session.start 时记录）
- 简单回退匹配（cwd basename + z-order 最前窗口兜底）
- AI Tab 基础 UI（session 列表 + 状态显示 + 排序 + 角标）
- 点击切换（初始关联优先 → 回退匹配 → 激活宿主 App）
- Claude Code adapter + hook 配置
- cwdNormalized 规范化路径计算
- Cursor/VSCode 区分（CURSOR_TRACE_ID）
- session.update 自动创建不存在的 session（兼容已运行会话）
- coder-bridge 安装到 ~/.coder-bridge/（通用路径）

### P1：体验补齐

- **右键改名**：NSAlert + NSTextField，持久化到 CoderSessionPreference.displayName
- **显示名统一**：默认 cwdBasename，home 目录显示 ~，用户可通过改名覆盖
- **最近 query 摘要**：从 session transcript 文件（~/.claude/projects/<sanitized-cwd>/<session-id>.jsonl）提取最近一条用户消息（顶层 type=="user" 且 message.role=="user"），截断显示在 session 行第二行（10pt nsTextTertiary）
- **WindowHint 手动绑定**（增强能力，非主路径）
- **隐藏会话 + 恢复入口**
- ended 清理策略完善

### P2：扩展

- **query 历史**：基于 transcript 解析，右键菜单"查看 query 历史"，弹出轻量列表面板
- **Gemini CLI adapter**：需单独调研 Gemini CLI 的 hook / session 事件机制后接入
- **Codex adapter**
- heartbeat 心跳机制

### 不做

- ~~右键断开会话~~：FocusPilot 只被动读取真实 session 状态，不伪造或修改远端会话生命周期
