# Coder-Bridge AI Tab 设计文档

## 概述

在 FocusPilot 快捷面板新增第三个 Tab「AI」，展示通过 coder-bridge 注册的 AI 编码工具会话（Claude Code / Codex / Gemini CLI），支持状态感知、窗口快速切换和会话管理。

### 核心原则

- **会话身份和窗口定位解耦**：hook 只注册会话元数据，点击时再实时匹配窗口
- **能自动就自动，不能自动就靠用户改名区分**：不做复杂的窗口指纹推断
- **持久化用户意图，不持久化运行时标识**：CGWindowID 等瞬时 ID 不落盘
- **不持久化 session 列表**：FocusPilot 重启后清空所有 session，等 coder-bridge 重新注册（因为 AI 工具中断后必须重新启动）

---

## 1. 数据模型

### 1.1 CoderSession（运行时）

AI 编码工具的一次会话实例，生命周期从 `session.start` 到清理移除。

```swift
struct CoderSession: Identifiable {
    let sessionID: String               // UUID，全局唯一，不复用
    var tool: CoderTool                  // claude / codex / gemini
    var cwd: String                      // 工作目录
    var hostApp: String                  // "cursor" / "terminal" / "iterm2" / ""
    var status: SessionStatus            // 业务态
    var lifecycle: SessionLifecycle      // 生命周期态
    var lastSeq: Int                     // 最后处理的 seq，防乱序
    var lastUpdate: Date
    var isHidden: Bool                   // session 级临时 UI 状态

    // 运行时计算（不持久化）
    var candidateWindowID: CGWindowID?
    var matchConfidence: MatchConfidence // high / low / none

    // 关联的用户偏好
    var preferenceKey: String {
        "\(tool.rawValue):\(cwdFingerprint):\(hostApp)"
    }
    var cwdFingerprint: String {
        cwd  // 完整路径作为指纹
    }
}

enum CoderTool: String, Codable { case claude, codex, gemini }
enum SessionStatus: String, Codable { case registered, working, idle, done, error }
enum SessionLifecycle: String, Codable { case active, ended }
enum MatchConfidence: String, Codable { case high, low, none }
```

### 1.2 CoderSessionPreference（持久化）

用户对某个 tool + cwd + hostApp 组合的偏好设置，独立于 session 生命周期。新 session 自动继承。

```swift
struct CoderSessionPreference: Codable {
    let key: String                      // "claude:/Users/.../FocusPilot:cursor"
    var displayName: String              // 用户改的名字（默认 cwd basename）
    var windowHint: WindowHint?          // 绑定线索
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
- `displayName` 和 `windowHint` 在 Preference 上（按 tool+cwd+hostApp 索引），session 结束后偏好保留
- `candidateWindowID` 纯运行时，不持久化

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

**4 个事件**：

| 事件 | hook 来源 | 迁移 |
|------|----------|------|
| `session.start` | SessionStart hook | → status=registered, lifecycle=active |
| `session.update` | Stop / Notification hook | → status 由字段指定（working/idle/done/error），lifecycle 不变 |
| `session.end` | SessionEnd hook | → lifecycle=ended，status 保持不变 |
| `session.heartbeat` | 可选（P2），周期上报 | 刷新 lastUpdate，不变 status/lifecycle |

**乱序防护**：每个事件携带 `seq`（session 内单调递增）。`if seq <= lastSeq then drop`。

### 2.3 清理策略

| 条件 | 动作 |
|------|------|
| done/error + ended → 用户点击确认 | 移除 |
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
    "status": "working | idle | done | error",
    "hostApp": "cursor | terminal | iterm2 | vscode | ...",
    "ts": 1711584000
}
```

**字段说明**：
- `event` + `status` 分离：event 决定操作类型，status 决定业务态
- `seq`：session 内单调递增，防乱序覆盖
- `hostApp`：从 `$TERM_PROGRAM` 推断，辅助字段，不做核心依赖
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

---

## 4. 窗口匹配算法

### 4.1 设计哲学

- 匹配在面板刷新时和用户点击时执行，复用 AppMonitor 已有的窗口快照
- 不在 hook 侧做窗口推断，不持久化 CGWindowID
- 多候选同标题时取最近活跃的，用户觉得不对就改名重新绑定

### 4.2 评分规则

```
evaluateCandidate(window, session) -> score: Int

+50  WindowHint.matchTokens 与窗口标题 tokens 交集 ≥ 60%
+30  cwd basename 精确命中窗口标题 tokens
+15  cwd 路径高信息 tokens 与标题 tokens 交集 ≥ 2 个
+10  hostApp 与窗口 bundleID 一致
+5   displayName tokens 命中窗口标题
```

**Token stopwords 过滤**（不参与匹配的低信息词）：
```
users, home, workspace, documents, desktop, code, projects,
src, app, web, server, client, lib, packages, repos, dev,
var, tmp, opt, usr, volumes + 当前用户名
```

### 4.3 置信度判定

```
无 WindowHint 时：
  score ≥ 40 且命中特征数 ≥ 2 → .high
  score 20-39 → .low
  score < 20 → .none

有 WindowHint 时：
  matchTokens 交集 ≥ 60% → .high
  否则 → .low（hint 可能过期）
```

### 4.4 点击行为

```
点击 CoderSession 行：
  有候选窗口（任意 confidence）→ activateWindow + yieldLevel
  多个候选同分 → 取最近活跃的，直接切（不弹选择器）
  无候选 → 只激活宿主 App
```

用户切错了 → 右键改名 → 标题自然区分 → 下次匹配准确。

### 4.5 手动绑定

```
右键 → "绑定到窗口..." → 子菜单列出同宿主 App 的窗口
→ 用户选择
→ 存 WindowHint { hostBundleID, matchTokens(从标题提取), cwdFingerprint }
→ 后续匹配优先用 hint
```

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
    (.working, .ended),   // 异常退出
]
```

### 5.2 排序规则

```
第一档：actionable（需要用户处理）
  idle+active, done+active, done+ended, error+active, error+ended, working+ended
  → 内部按 lastUpdate 倒排

第二档：passive（不需要处理）
  working+active, registered+active
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
| working | ended | "执行中 · 已结束" | 蓝 | 0.7 | 1 | ✅ |
| working | active | "执行中" | 蓝 | 1.0 | 2 | ❌ |
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

```
改名...
绑定到窗口 →  （子菜单列出同宿主 App 的窗口）
解除绑定
────
隐藏此会话
移除已结束的会话
```

### 5.5 隐藏会话入口

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

### 6.2 hook 配置示例（Claude Code）

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
| `Services/CoderBridgeService.swift` | DistributedNotification 监听、CoderSession 列表管理（纯运行时）、清理定时器、偏好持久化 |
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
  → 更新 CoderSession 列表
  → 为每个 session 执行窗口匹配（复用 AppMonitor 窗口快照）
  → post NotificationCenter("coderBridgeSessionChanged")
  → QuickPanelView.reloadData()
  → AI Tab 重建 session 行
```

---

## 8. 分期计划

### P0：MVP

- CoderSession 模型 + 状态机
- DistributedNotification 收发
- AI Tab 基础 UI（session 列表 + 状态显示 + 排序）
- 点击切换（cwd basename 匹配 + 最近活跃兜底）
- Claude Code adapter

### P1：体验补齐

- 右键改名 + WindowHint 绑定
- displayName 持久化偏好
- 角标 + actionable 排序
- ended 清理策略
- 隐藏会话入口

### P2：扩展

- Codex / Gemini CLI adapter 实现
- heartbeat 心跳机制
- Token stopwords 优化
