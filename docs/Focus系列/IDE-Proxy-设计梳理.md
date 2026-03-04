# IDE Proxy 设计梳理

> **状态**：Draft
> **日期**：2026-02-24
> **关联文档**：`FocusPilot-PRD-V1.md`、`FocusPilot-总架构设计.md`

---

## 1. 定位与职责

### 1.1 是什么

IDE Proxy 是 FocusPilot 与 IDE 执行环境之间的**桥接服务**。它对接 FocusPilot 的 Dispatch 模块，将 Task 派发指令转化为具体的 IDE 操作链：打开 Cursor → 在 Cursor 内嵌终端启动 Claude Code → 注入任务 Prompt → 监听执行状态 → 回传结果。

### 1.2 核心架构约束

> **Cursor 和 Claude Code 运行在同一个 Cursor IDE 窗口内。**

Claude Code 运行在 Cursor 的集成终端中，而不是独立进程。这意味着：
- 一个 Cursor 窗口 = 一个项目代码 + 一个 Claude Code 终端会话
- 用户可以在 Cursor 中直接观察 Claude Code 的执行输出
- Claude Code 的文件操作 → Cursor file watcher 实时刷新 → 用户即时可见

### 1.3 在 FocusPilot 架构中的位置

```
FocusPilot (Dispatch 模块)
    │
    │  HTTP API
    ▼
┌───────────────────────────────────┐
│            IDE Proxy              │
│  ┌─────────────────────────────┐  │
│  │ Session Manager             │  │
│  │ (Task ↔ Cursor 窗口绑定)    │  │
│  └─────────────────────────────┘  │
│  ┌─────────────────────────────┐  │
│  │ Cursor Automator            │  │
│  │ (CLI + AppleScript 控制)    │  │
│  └─────────────────────────────┘  │
│  ┌─────────────────────────────┐  │
│  │ Callback Server             │  │
│  │ (接收 Claude Code Hook)     │  │
│  └─────────────────────────────┘  │
└───────────────────────────────────┘
    │                          ▲
    │ cursor CLI               │ Claude Code Hook
    │ + AppleScript            │ (curl → Callback Server)
    ▼                          │
┌──────────────────────────────────┐
│          Cursor IDE 窗口          │
│  ┌────────────────────────────┐  │
│  │  编辑器区域（代码浏览/编辑） │  │
│  ├────────────────────────────┤  │
│  │  集成终端                   │  │
│  │  $ claude "task prompt"    │  │
│  │  > Claude Code 执行中...   │  │
│  └────────────────────────────┘  │
└──────────────────────────────────┘
```

对应 PRD 的模块映射：

| PRD 功能需求 | IDE Proxy 对应 |
|-------------|---------------|
| FR-D01 IDE 派发 | `POST /dispatch` API |
| FR-D02 IDE Adapter | Cursor Automator（统一控制 Cursor + Claude Code） |
| FR-D03 绑定管理 | Session Manager（task_id ↔ Cursor 窗口绑定） |
| FR-M01 窗口状态 | `GET /sessions/:id/status` API |

### 1.4 核心职责

1. **接收派发指令**：从 FocusPilot 接收 Task ID、代码库路径、任务描述
2. **启动 Cursor**：通过 `cursor` CLI 打开对应代码仓库
3. **终端自动化**：在 Cursor 集成终端中启动 Claude Code 并注入任务 Prompt
4. **状态追踪**：通过 Claude Code Hook 机制捕获执行状态
5. **状态回传**：通过 Webhook 将状态变更推送回 FocusPilot

---

## 2. 核心流程

### 2.1 完整派发流程（序列图）

```
FocusPilot       IDE Proxy                    Cursor IDE 窗口                  FocusPilot
                                     ┌──────────┬──────────────┐          (Webhook)
  │               │                  │ 编辑器    │ 集成终端      │              │
  │               │                  │          │              │              │
  │ POST /dispatch│                  │          │              │              │
  │──────────────>│                  │          │              │              │
  │               │                  │          │              │              │
  │ 202 {sess_id} │                  │          │              │              │
  │<──────────────│                  │          │              │              │
  │               │                  │          │              │              │
  │               │ ① cursor CLI     │          │              │              │
  │               │ 打开项目          │          │              │              │
  │               │─────────────────>│ 加载代码  │              │              │
  │               │                  │          │              │              │
  │               │ ② 写入 Hook 配置  │          │              │              │
  │               │ (.claude/settings.local.json)│              │              │
  │               │                  │          │              │              │
  │               │ ③ AppleScript    │          │              │              │
  │               │ 打开集成终端      │          │  终端就绪     │              │
  │               │─────────────────>│          │──────────────│              │
  │               │                  │          │              │              │
  │               │ ④ AppleScript    │          │              │              │
  │               │ 输入 claude 命令  │          │ $ claude ... │              │
  │               │─────────────────>│          │──────────────│              │
  │               │                  │          │ CC 启动执行   │              │
  │               │                  │          │              │              │
  │               │                  │          │              │  executing   │
  │               │──────────────────────────────────────────────────────────>│
  │               │                  │          │              │              │
  │               │ ⑤ Hook callback  │          │              │              │
  │               │ (等待用户确认)    │          │ 等待输入...   │              │
  │               │<─────────────────────────────────────────│              │
  │               │                  │          │              │  waiting     │
  │               │──────────────────────────────────────────────────────────>│
  │               │                  │          │              │              │
  │               │ ⑥ Hook callback  │          │              │              │
  │               │ (Stop)           │          │ 执行完毕      │              │
  │               │<─────────────────────────────────────────│              │
  │               │                  │          │              │  completed   │
  │               │──────────────────────────────────────────────────────────>│
```

### 2.2 流程拆解

**Step 1：接收派发**
- FocusPilot 调用 `POST /dispatch`，传入 task_id、repo_path、prompt
- IDE Proxy 创建 Session 记录，返回 session_id
- 标记状态为 `launching`

**Step 2：配置 Claude Code Hook**
- 在 `<repo_path>/.claude/settings.local.json` 写入 Hook 配置（必须在启动 Claude Code 前完成）
- Hook 脚本在触发时调用 IDE Proxy 的回调 endpoint

**Step 3：启动 Cursor 并打开项目**
- 执行 `cursor --new-window <repo_path>`
- 等待 Cursor 窗口就绪（通过 AppleScript 检测窗口出现）
- 获取 Cursor 窗口 ID 用于后续自动化操作

**Step 4：在 Cursor 集成终端中启动 Claude Code**
- AppleScript 聚焦目标 Cursor 窗口
- AppleScript 打开集成终端（模拟快捷键 Ctrl+`）
- AppleScript 在终端中输入命令并执行：
  ```bash
  claude "$(cat /tmp/focuspilot-{session_id}.prompt)"
  ```
- Prompt 预先写入临时文件，避免长文本 AppleScript 传输问题
- 标记状态为 `executing`，推送回 FocusPilot

**Step 5：状态监听与回传**
- Claude Code 的 Hook 在关键事件触发时调用 IDE Proxy 回调
- IDE Proxy 收到回调后更新 Session 状态，并 Webhook 通知 FocusPilot

---

## 3. 状态机设计

### 3.1 Session 状态流转

```
                 dispatch 请求
                      │
                      ▼
              ┌──────────────┐
              │   launching  │
              └──────┬───────┘
                     │ Cursor + Claude Code 启动成功
                     ▼
              ┌──────────────┐
         ┌───>│  executing   │<───┐
         │    └──────┬───────┘    │
         │           │            │
         │     Hook: 等待输入     │ 用户输入后继续
         │           ▼            │
         │    ┌──────────────┐    │
         │    │waiting_input │────┘
         │    └──────────────┘
         │
         │    Hook: Stop / 进程退出
         │           │
         │           ▼
         │    ┌──────────────┐
         │    │  completed   │
         │    └──────────────┘
         │
         │    启动失败 / 进程异常
         │           │
         └───────────┘ (可从任意状态转入)
                     ▼
              ┌──────────────┐
              │    error     │
              └──────────────┘
```

### 3.2 状态定义

| 状态 | 含义 | 触发条件 |
|------|------|---------|
| `launching` | 正在启动 Cursor 和 Claude Code | 收到 dispatch 请求 |
| `executing` | Claude Code 正在执行任务 | Claude Code 子进程启动成功 |
| `waiting_input` | 等待用户输入/确认 | Claude Code Hook 检测到需要用户决策 |
| `completed` | 任务执行完毕 | Claude Code Stop Hook 触发 / 进程正常退出 |
| `error` | 异常状态 | 启动失败 / 进程崩溃 / 超时 |

### 3.3 FocusPilot 关注的三种状态

对应用户描述的需求：

| 用户需求 | Session 状态 | 回传给 FocusPilot |
|---------|-------------|---------------|
| (a) 正在执行中 | `executing` | `{ "status": "executing" }` |
| (b) 已执行完毕 | `completed` | `{ "status": "completed" }` |
| (c) 等待输入 | `waiting_input` | `{ "status": "waiting_input" }` |

---

## 4. API 接口设计

### 4.1 IDE Proxy 对外 API（供 FocusPilot 调用）

#### POST /dispatch — 派发任务

```json
// Request
{
  "task_id": "task-001",
  "repo_path": "/Users/bruce/Workspace/2-Code/01-work/project-a",
  "prompt": "实现用户登录功能，参考 docs/login-spec.md",
  "ide_type": "cursor",
  "callback_url": "http://localhost:9800/webhook/task-status"
}

// Response 202
{
  "session_id": "sess-abc123",
  "status": "launching"
}
```

#### GET /sessions/:session_id — 查询会话状态

```json
// Response 200
{
  "session_id": "sess-abc123",
  "task_id": "task-001",
  "status": "executing",
  "ide_type": "cursor",
  "cursor_pid": 12345,
  "claude_pid": 12346,
  "started_at": "2026-02-23T10:30:00Z",
  "updated_at": "2026-02-23T10:31:15Z"
}
```

#### GET /sessions — 列出所有会话

```json
// Response 200
{
  "sessions": [
    {
      "session_id": "sess-abc123",
      "task_id": "task-001",
      "status": "executing",
      "ide_type": "cursor"
    }
  ]
}
```

#### DELETE /sessions/:session_id — 终止会话

终止 Claude Code 进程，清理绑定关系。

### 4.2 IDE Proxy 内部回调 API（供 Claude Code Hook 调用）

#### POST /internal/callback — Hook 回调

```json
// Claude Code Hook 脚本调用
{
  "session_id": "sess-abc123",
  "event": "stop",          // "stop" | "waiting_input" | "error"
  "detail": "Task completed successfully"
}
```

### 4.3 Webhook 回调（IDE Proxy → FocusPilot）

```json
// IDE Proxy 推送给 FocusPilot
{
  "session_id": "sess-abc123",
  "task_id": "task-001",
  "status": "completed",     // "executing" | "waiting_input" | "completed" | "error"
  "timestamp": "2026-02-23T10:45:00Z",
  "detail": "Task completed"
}
```

---

## 5. Claude Code Hook 配置

### 5.1 Hook 机制说明

Claude Code 支持在项目级别配置 hooks（`.claude/settings.local.json`），在特定事件发生时执行 shell 命令。

### 5.2 需要利用的 Hook 事件

| Hook 事件 | 用途 | 触发时机 |
|-----------|------|---------|
| `Stop` | 检测任务完成 | Claude Code 完成一轮对话/任务后 |
| `Notification` | 检测等待用户输入 | Claude Code 需要用户确认权限时 |
| `PreToolUse` | 可选：追踪执行进度 | Claude Code 调用工具前 |

### 5.3 Hook 配置模板

IDE Proxy 在启动 Claude Code 前，自动写入项目级 Hook 配置：

```json
// <repo_path>/.claude/settings.local.json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "curl -s -X POST http://localhost:{{PROXY_PORT}}/internal/callback -H 'Content-Type: application/json' -d '{\"session_id\": \"{{SESSION_ID}}\", \"event\": \"stop\"}'"
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "curl -s -X POST http://localhost:{{PROXY_PORT}}/internal/callback -H 'Content-Type: application/json' -d '{\"session_id\": \"{{SESSION_ID}}\", \"event\": \"waiting_input\"}'"
          }
        ]
      }
    ]
  }
}
```

> **注意**：`settings.local.json` 应加入 `.gitignore`，避免提交到代码仓库。

### 5.4 Hook 变量注入

IDE Proxy 在写入配置时，将 `{{PROXY_PORT}}` 和 `{{SESSION_ID}}` 替换为实际值。

---

## 6. 技术方案

### 6.1 IDE Proxy 服务形态

**独立轻量 HTTP 服务**，随 FocusPilot 启动/关闭。

| 选项 | 方案 |
|------|------|
| 语言 | Rust（与 FocusPilot 后端一致）或 TypeScript/Node.js（快速原型） |
| HTTP 框架 | Axum (Rust) / Express (Node.js) |
| 进程管理 | 作为子进程由 FocusPilot 启动和管理 |
| 端口 | 动态分配或配置（默认 `localhost:9801`） |

### 6.2 Cursor 启动方式

```bash
# 打开项目（新窗口）
cursor --new-window /path/to/repo
```

窗口就绪检测（AppleScript）：

```applescript
-- 等待 Cursor 窗口出现，匹配项目路径
tell application "System Events"
    tell process "Cursor"
        repeat 30 times -- 最多等待 30 秒
            try
                set winList to every window whose name contains "project-a"
                if (count of winList) > 0 then
                    return name of item 1 of winList
                end if
            end try
            delay 1
        end repeat
    end tell
end tell
```

### 6.3 Cursor 集成终端自动化

Claude Code 运行在 Cursor 的集成终端内，需要通过 AppleScript 完成终端操作链：

```applescript
-- Step 1: 聚焦目标 Cursor 窗口
tell application "Cursor" to activate
tell application "System Events"
    tell process "Cursor"
        -- 定位到指定项目窗口
        set frontmost to true
        perform action "AXRaise" of window "project-a"
    end tell
end tell

-- Step 2: 打开集成终端 (Ctrl+`)
tell application "System Events"
    key code 50 using control down  -- ` 键的 key code
end tell

delay 0.5  -- 等待终端面板打开

-- Step 3: 输入 Claude Code 启动命令
tell application "System Events"
    -- 使用剪贴板粘贴，避免长文本 keystroke 问题
    keystroke "claude \"$(cat /tmp/focuspilot-sess-abc123.prompt)\""
    delay 0.2
    keystroke return
end tell
```

### 6.4 Prompt 传递方案

长文本 Prompt 不适合通过 AppleScript keystroke 逐字符输入，采用**临时文件方案**：

```
IDE Proxy                                     Cursor 集成终端
    │                                              │
    │ ① 将 prompt 写入临时文件                       │
    │    /tmp/focuspilot-{session_id}.prompt           │
    │                                              │
    │ ② AppleScript 在终端输入命令                   │
    │    claude "$(cat /tmp/focuspilot-xxx.prompt)"    │
    │─────────────────────────────────────────────>│
    │                                              │
    │                                 Claude Code 读取 prompt 并执行
```

**为什么用临时文件**：
- AppleScript `keystroke` 对长文本不可靠（丢字符、特殊字符转义）
- 剪贴板方案会覆盖用户当前剪贴板内容
- `$(cat file)` 通过 shell 展开，支持任意长度和特殊字符
- 临时文件在 Session 结束后清理

**Claude Code 启动模式**：
- `claude "prompt"` — 带初始 Prompt 的交互模式（推荐，用户可后续追加输入）
- `claude -p "prompt"` — 非交互 print mode（执行完即退出，不适合需要 waiting_input 的场景）

### 6.5 Cursor 窗口内的协作关系

```
┌─────────────────────────────────────────┐
│             Cursor IDE 窗口              │
│                                         │
│  ┌───────────────────────────────────┐  │
│  │ 编辑器区域                         │  │
│  │                                   │  │
│  │  Claude Code 修改文件              │  │
│  │         ↓ file watcher            │  │
│  │  编辑器实时刷新显示变更             │  │
│  │                                   │  │
│  ├───────────────────────────────────┤  │
│  │ 集成终端                           │  │
│  │                                   │  │
│  │  $ claude "implement login..."    │  │
│  │  > 正在分析代码库...               │  │
│  │  > 正在修改 src/auth/login.ts     │  │
│  │  > ...                            │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

- **编辑器** + **终端** 同屏：用户同时看到代码变更和 Claude Code 执行输出
- Claude Code 修改文件 → Cursor file watcher 自动刷新编辑器
- 用户可随时在终端中与 Claude Code 交互（追加指令、确认权限等）

---

## 7. 方案评估

### 7.1 可行性判定：可行，但有条件

整条链路中，**AppleScript 对 Cursor 集成终端的控制能力**是核心前提。如果这一步验证通过，后续链路（Claude Code 启动 → Hook 回调 → 状态回传）均为成熟技术，风险可控。

### 7.2 优势

| 维度 | 说明 |
|------|------|
| **统一工作区** | 代码编辑器 + Claude Code 终端在同一窗口，用户无需切换上下文 |
| **即时可见** | Claude Code 修改文件 → Cursor file watcher 实时刷新，用户直接看到变更 |
| **可交互** | 用户可以随时在 Cursor 终端中与 Claude Code 交互（追加指令、确认权限） |
| **符合真实工作流** | 这就是开发者手动操作的方式，IDE Proxy 只是自动化了这个过程 |
| **Hook 回调成熟** | Claude Code Hook 是官方支持的机制，稳定性有保障 |

### 7.3 风险与缓解

| 风险 | 严重度 | 说明 | 缓解策略 |
|------|--------|------|---------|
| **R1: AppleScript 脆弱性** | 高 | 模拟快捷键打开终端、输入命令依赖 Cursor 的 UI 结构和快捷键绑定 | Phase 0 先验证；保留升级到 Cursor Extension 方案的余地 |
| **R2: 窗口定位** | 中 | 多个 Cursor 窗口时需精确定位目标窗口 | 通过窗口标题匹配 repo 名称；记录窗口 ID |
| **R3: 终端状态不确定** | 中 | Cursor 终端可能已有进程运行，或终端面板已打开 | 通过 AppleScript 新建终端 Tab（Cmd+Shift+`）而非切换现有终端 |
| **R4: 长 Prompt 传递** | 低 | 任务描述可能很长，含特殊字符 | 采用临时文件方案 `$(cat /tmp/xxx.prompt)`，不走 keystroke |
| **R5: Cursor 更新破坏** | 中 | Cursor 版本更新可能改变快捷键或 UI 行为 | AppleScript 脚本做版本适配；关键操作做超时检测和重试 |
| **R6: Hook 事件覆盖度** | 中 | Notification Hook 能否准确对应"等待用户输入" | Phase 0 验证；备选方案见 7.4 |

### 7.4 "等待输入"状态检测的备选方案

Claude Code 的 `Notification` Hook 是否能精确捕获"等待用户输入"场景需要实测。如果不够准确，有以下备选：

| 方案 | 原理 | 优缺点 |
|------|------|--------|
| **A: Notification Hook** | Claude Code 需要用户确认权限时触发 | 最简单；但可能不覆盖所有"等待"场景 |
| **B: PreToolUse Hook** | 工具调用前触发，如果需要用户确认则意味着等待 | 更细粒度；但需要区分"已自动批准"和"需要用户确认" |
| **C: 轮询进程输出** | 定期通过 AppleScript 读取终端内容，检测是否有等待提示 | 不依赖 Hook；但轮询有延迟且解析终端输出不可靠 |
| **D: Claude Code stdin 监听** | 通过 pty 监听 Claude Code 进程是否在等待 stdin | 技术上最准确；但 Claude Code 运行在 Cursor 终端内，IDE Proxy 不持有 pty |

**推荐**：Phase 0 先测方案 A（Notification Hook），不满足再考虑 B。

### 7.5 替代架构方案（如 AppleScript 不可行时）

如果 Phase 0 验证 AppleScript 方案不够稳定，可升级到：

**方案 B：Cursor Extension（VS Code 扩展）**

```
IDE Proxy ──HTTP──> Cursor Extension ──Extension API──> 集成终端
                        │
                        │  vscode.window.createTerminal()
                        │  terminal.sendText("claude ...")
                        ▼
                    Cursor 集成终端
```

- 开发一个轻量 Cursor/VS Code 扩展，暴露 HTTP API
- 扩展内部通过 `vscode.window.createTerminal()` 可靠地创建终端
- 通过 `terminal.sendText()` 可靠地发送命令
- 优点：完全不依赖 AppleScript，API 级别的控制
- 缺点：需要额外开发和安装 VS Code 扩展

> 建议在 Phase 0 验证后决定是否需要走 Extension 路线。

---

## 8. 数据模型

### 8.1 Session（IDE Proxy 内存/持久化）

```typescript
interface Session {
  session_id: string;        // UUID
  task_id: string;           // FocusPilot Task 标识
  repo_path: string;         // 代码仓库路径
  prompt: string;            // 任务描述
  ide_type: "cursor";        // IDE 类型

  // 进程信息
  cursor_pid?: number;       // Cursor 进程 PID
  claude_pid?: number;       // Claude Code 进程 PID

  // 状态
  status: SessionStatus;     // launching | executing | waiting_input | completed | error
  error_detail?: string;     // 错误详情

  // 回调
  callback_url: string;      // FocusPilot Webhook 地址

  // 时间
  created_at: string;        // ISO 8601
  updated_at: string;
}

type SessionStatus =
  | "launching"
  | "executing"
  | "waiting_input"
  | "completed"
  | "error";
```

---

## 9. 与 FocusPilot Dispatch 模块的集成点

### 9.1 FocusPilot 端改造

在 FocusPilot 的 `CursorAdapter`（`src-tauri/src/infra/ide/cursor.rs`）中，原本直接调用 `cursor` CLI，改为调用 IDE Proxy API：

```
原始设计：
  DispatchService → CursorAdapter → cursor CLI → 获取 PID

集成 IDE Proxy 后：
  DispatchService → CursorAdapter → HTTP POST /dispatch → IDE Proxy
  IDE Proxy → cursor CLI + claude CLI → Hook 回调 → Webhook → FocusPilot
```

### 9.2 ExecutionBinding 扩展

在原有 `execution_binding` 表基础上增加 `session_id` 字段：

```sql
ALTER TABLE execution_binding ADD COLUMN proxy_session_id TEXT;
```

绑定关系：`task_id ↔ proxy_session_id ↔ cursor_pid + claude_pid`

### 9.3 状态回传通道

```
Claude Code Hook
      │
      ▼ POST /internal/callback
IDE Proxy
      │
      ▼ POST callback_url (Webhook)
FocusPilot (SyncCmd 或专用 endpoint)
      │
      ▼ emit Tauri Event
前端 (monitor.store.ts)
```

---

## 10. 边界与约束

### 10.1 IDE Proxy 的边界

| 职责 | 说明 |
|------|------|
| **做** | 启动 Cursor、启动 Claude Code、注入 Prompt、监听状态、回传状态 |
| **不做** | 不存储 Task 数据、不做任务调度逻辑、不直接操作 Obsidian |
| **不做** | 不管理 Claude Code 的具体执行内容（只关心状态） |

### 10.2 约束条件

- **macOS Only**：依赖 `cursor` CLI 和 macOS 进程管理
- **Claude Code CLI 可用**：需要用户已安装 Claude Code 并配置好 API Key
- **Cursor CLI 可用**：需要用户已安装 Cursor 并启用 `cursor` shell command
- **本地通信**：IDE Proxy 仅监听 localhost，不暴露到网络

### 10.3 已知风险

| 风险 | 影响 | 缓解 |
|------|------|------|
| Claude Code Hook 格式变更 | 状态回调失效 | Hook 配置做版本检测，失败时通过进程退出兜底 |
| `settings.local.json` 被覆盖 | Hook 丢失 | 每次启动前检查并重写 |
| Claude Code 长时间运行 | Session 堆积 | 配置超时机制，超时自动标记 stale |
| Cursor 进程无法精确匹配 | PID 绑定不准确 | 通过窗口标题 + 进程参数组合匹配 |

---

## 11. 待确认问题

1. **AppleScript 能否可靠控制 Cursor 集成终端？**
   - 核心前提，Phase 0 第一优先验证项
   - 包括：打开终端面板、新建终端 Tab、输入命令、回车执行
   - 如果不可靠 → 切换到 Cursor Extension 方案（见 7.5）

2. **Claude Code Hook 的 Notification 事件是否能准确捕获"等待用户输入"场景？**
   - 需要实测 Claude Code 在 permission prompt 时是否触发 Notification Hook
   - 备选方案对比见 7.4

3. **多个 Task 派发到同一个 repo 时如何处理？**
   - 方案 A：每个 Task 启动独立的 Cursor 窗口（`cursor --new-window`）
   - 方案 B：复用已有窗口，在新终端 Tab 中启动另一个 Claude Code 实例
   - 推荐 Phase 1 先用方案 A（简单隔离），后续按需支持方案 B

4. **Hook 配置的 settings.local.json 写入是否会影响已有配置？**
   - 需要 merge 而非覆盖，保留用户已有的 Hook 配置
   - 任务完成后是否需要清理 IDE Proxy 注入的 Hook

5. **`cursor --new-window` 是否在所有 Cursor 版本上行为一致？**
   - 需要测试 Cursor 的 CLI 参数兼容性

---

## 12. 推荐实现路径

### Phase 0：验证核心链路（PoC）— 最高优先级

手动逐步验证，不写代码，目的是确认技术假设：

- [ ] **P0-1**: `cursor --new-window /path/to/repo` 能否正确打开项目
- [ ] **P0-2**: AppleScript 能否聚焦指定 Cursor 窗口（通过窗口标题匹配）
- [ ] **P0-3**: AppleScript 能否打开 Cursor 集成终端（Ctrl+`）
- [ ] **P0-4**: AppleScript 能否在终端中输入命令并执行
- [ ] **P0-5**: `claude "$(cat /tmp/test.prompt)"` 能否正确启动并读取 Prompt
- [ ] **P0-6**: Claude Code Stop Hook 触发时能否成功 curl 回调
- [ ] **P0-7**: Claude Code Notification Hook 能否捕获"等待用户输入"
- [ ] **P0-8**: 从 Cursor CLI 启动到 Claude Code 开始执行的端到端耗时

> **判定标准**：P0-1 ~ P0-6 全部通过 → 进入 Phase 1。P0-2 ~ P0-4 失败 → 评估 Cursor Extension 方案。

### Phase 1：最小可用 IDE Proxy

- [ ] HTTP 服务框架搭建（POST /dispatch, GET /sessions, DELETE /sessions）
- [ ] Session 状态机实现
- [ ] Hook 配置自动写入（merge 模式）
- [ ] Prompt 临时文件管理
- [ ] Cursor 启动 + AppleScript 终端自动化
- [ ] 内部 Hook 回调 endpoint（POST /internal/callback）
- [ ] Webhook 推送（IDE Proxy → FocusPilot）
- [ ] 基础日志

### Phase 2：与 FocusPilot 集成

- [ ] FocusPilot CursorAdapter 改为调用 IDE Proxy API
- [ ] ExecutionBinding 表增加 proxy_session_id
- [ ] FocusPilot 接收 Webhook 并更新 Monitor 状态
- [ ] 前端 Widget 展示细化的执行状态（executing / waiting / completed）

### Phase 3：稳定性完善

- [ ] 进程异常检测与自动清理（Cursor 窗口关闭 → Session 标记 stale）
- [ ] Session 超时机制
- [ ] Hook 配置清理（任务完成后移除注入的 Hook）
- [ ] AppleScript 操作重试与超时
- [ ] 日志与错误追踪

---

_最后更新：2026-02-24_
