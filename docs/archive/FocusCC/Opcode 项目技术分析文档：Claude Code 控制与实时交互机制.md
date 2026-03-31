# Opcode 项目技术分析文档：Claude Code 控制与实时交互机制

> 分析日期：2026-02-23
> 项目地址：<https://github.com/anthropics/opcode> (AGPL-3.0)
> 技术栈：Tauri 2.0 (Rust) + React 18 (TypeScript) + Vite 6 + SQLite

---

## 目录

- [一、技术细节与原理](#一技术细节与原理)
  - [1.1 核心运行机制总览](#11-核心运行机制总览)
  - [1.2 Claude Code 二进制检测与定位](#12-claude-code-二进制检测与定位)
  - [1.3 CLI 进程生成与参数构造](#13-cli-进程生成与参数构造)
  - [1.4 流式 JSON 输出协议](#14-流式-json-输出协议)
  - [1.5 双模式运行架构：Tauri IPC vs WebSocket](#15-双模式运行架构tauri-ipc-vs-websocket)
  - [1.6 进程注册与生命周期管理](#16-进程注册与生命周期管理)
  - [1.7 任务 ID 与会话 ID 的映射关联机制 (run_id vs session_id)](#17-任务-id-与会话-id-的映射关联机制-run_id-vs-session_id)
- [二、数据流转说明](#二数据流转说明)
  - [2.1 完整数据流全景图](#21-完整数据流全景图)
  - [2.2 Tauri 桌面模式数据流（逐步详解）](#22-tauri-桌面模式数据流逐步详解)
  - [2.3 Web 浏览器模式数据流（逐步详解）](#23-web-浏览器模式数据流逐步详解)
  - [2.4 反馈机制与交付逻辑](#24-反馈机制与交付逻辑)
  - [2.5 取消与异常处理流程](#25-取消与异常处理流程)
- [三、历史信息重载延迟分析与优化方案](#三历史信息重载延迟分析与优化方案)
  - [3.1 延迟原因分析](#31-延迟原因分析)
  - [3.2 优化方案 (由易到难)](#32-优化方案-由易到难)

---

## 一、技术细节与原理

### 1.1 核心运行机制总览

Opcode 的核心思路是：**将 Claude Code CLI 作为子进程生成，通过 `--output-format stream-json` 参数获取结构化的流式 JSONL 输出，再通过事件系统实时推送到前端渲染**。

整个系统分为三层：

```
┌─────────────────────────────────────────────────────┐
│                  前端展示层 (React)                    │
│  useClaudeMessages Hook ← Tauri Event / DOM Event   │
├─────────────────────────────────────────────────────┤
│                 中间通信层 (Tauri / Axum)              │
│  Tauri IPC invoke() / WebSocket ws://               │
├─────────────────────────────────────────────────────┤
│                  后端执行层 (Rust + Tokio)             │
│  tokio::process::Command → Claude CLI 子进程          │
│  stdout/stderr 逐行读取 → 事件发射                     │
└─────────────────────────────────────────────────────┘
```

关键设计决策：

- **不使用 Claude API/SDK**，而是直接调用 Claude Code CLI 二进制
- **不轮询**，使用事件驱动的流式推送
- **会话隔离**，每个事件名称包含 sessionId，支持多并发会话

---

### 1.2 Claude Code 二进制检测与定位

**源码位置**：`src-tauri/src/claude_binary.rs`

Opcode 启动时不假定 Claude Code 安装在固定路径，而是通过多策略搜索来定位二进制文件：

#### 搜索优先级与策略

```
优先级 1: 数据库存储路径 (app_settings 表中的 claude_binary_path)
         ↓ 路径不存在则继续
优先级 2: discover_system_installations() 自动发现
         ├── which claude              (source: "which")
         ├── /opt/homebrew/bin/claude   (source: "homebrew")
         ├── /usr/local/bin/claude      (source: "system")
         ├── ~/.nvm/versions/node/*/bin/claude (source: "nvm-*")
         ├── ~/.local/bin/claude        (source: "local-bin")
         ├── ~/.claude/local/claude     (source: "claude-local")
         ├── npm root -g 路径           (source: "npm-global")
         ├── yarn/bun global 路径       (source: "yarn"/"bun")
         └── PATH 环境变量搜索          (source: "PATH")
         ↓
优先级 3: 按版本号排序，选择最高版本
```

#### 逻辑数据示例

`find_claude_binary()` 返回的 `ClaudeInstallation` 结构：

```rust
ClaudeInstallation {
    path: "/opt/homebrew/bin/claude",
    version: Some("1.0.33"),
    source: "homebrew",
    installation_type: InstallationType::System,
}
```

当发现多个安装时，`select_best_installation()` 按版本号降序排列，并通过 `source_preference()` 对同版本的不同来源进行排序（which > homebrew > system > nvm > ...）。

---

### 1.3 CLI 进程生成与参数构造

**源码位置**：`src-tauri/src/commands/claude.rs:920-1015`

Opcode 提供三种 Claude Code 执行模式，每种对应不同的 CLI 参数：

#### 模式一：新建会话 (`execute_claude_code`)

```rust
// claude.rs:935-944
let args = vec![
    "-p",                          // 以 prompt 模式运行（非交互式）
    prompt.clone(),                // 用户输入的问题
    "--model",
    model.clone(),                 // 如 "claude-sonnet-4-20250514"
    "--output-format",
    "stream-json",                 // 关键：流式 JSON Lines 输出
    "--verbose",                   // 包含详细元数据
    "--dangerously-skip-permissions", // 跳过工具权限确认
];
```

#### 模式二：继续会话 (`continue_claude_code`)

```rust
// claude.rs:966-976
let args = vec![
    "-c",                          // 继续最近的会话
    "-p", prompt.clone(),
    "--model", model.clone(),
    "--output-format", "stream-json",
    "--verbose",
    "--dangerously-skip-permissions",
];
```

#### 模式三：恢复指定会话 (`resume_claude_code`)

```rust
// claude.rs:1000-1011
let args = vec![
    "--resume",
    session_id.clone(),            // 指定要恢复的会话 UUID
    "-p", prompt.clone(),
    "--model", model.clone(),
    "--output-format", "stream-json",
    "--verbose",
    "--dangerously-skip-permissions",
];
```

#### 进程创建过程

```rust
// claude.rs:293-306
fn create_system_command(claude_path: &str, args: Vec<String>, project_path: &str) -> Command {
    let mut cmd = create_command_with_env(claude_path);  // 注入 Homebrew PATH
    for arg in args { cmd.arg(arg); }
    cmd.current_dir(project_path)      // 在项目目录下执行
       .stdout(Stdio::piped())         // 捕获标准输出
       .stderr(Stdio::piped());        // 捕获标准错误
    cmd
}
```

`create_command_with_env` 还会检测 Homebrew 路径（`/opt/homebrew/bin`）并将其注入到 `PATH` 环境变量中，确保 Claude CLI 运行时能找到依赖的工具。

---

### 1.4 流式 JSON 输出协议

Claude Code CLI 使用 `--output-format stream-json` 后，输出为 **JSONL（JSON Lines）** 格式 —— 每行一个完整的 JSON 对象。

#### Claude CLI 输出的消息类型

以下是实际流经管道的 JSONL 数据示例：

**1. 初始化消息（system/init）**

```json
{
  "type": "system",
  "subtype": "init",
  "session_id": "abc123-def456",
  "tools": ["Read", "Write", "Bash"],
  "model": "claude-sonnet-4-20250514"
}
```

这是最关键的第一条消息，Opcode 从中提取 `session_id` 来建立会话追踪。

**2. 助手文本消息**

```json
{
  "type": "assistant",
  "message": {
    "role": "assistant",
    "content": [{ "type": "text", "text": "让我查看一下代码..." }],
    "usage": { "input_tokens": 1234, "output_tokens": 56 }
  }
}
```

**3. 工具调用消息**

```json
{
  "type": "assistant",
  "message": {
    "role": "assistant",
    "content": [
      {
        "type": "tool_use",
        "id": "tool_1",
        "name": "Read",
        "input": { "file_path": "/src/main.rs" }
      }
    ]
  }
}
```

**4. 工具结果消息**

```json
{
  "type": "tool",
  "content": [
    { "type": "tool_result", "tool_use_id": "tool_1", "content": "文件内容..." }
  ]
}
```

**5. 部分流式消息（partial）**

```json
{
  "type": "partial",
  "tool_calls": [{ "partial_tool_call_index": 0, "content": "部分输出内容..." }]
}
```

**6. 完成/错误消息**

```json
{"type":"response","message":{"usage":{"input_tokens":5000,"output_tokens":2000}}}
{"type":"error","error":"rate_limit_exceeded"}
```

---

### 1.5 双模式运行架构：Tauri IPC vs WebSocket

Opcode 支持两种前后端通信模式：

#### 模式 A：Tauri 桌面模式（IPC）

```
React 前端 ──invoke()──→ Rust Tauri 命令 ──emit()──→ React 前端
             (同步调用)                      (异步事件推送)
```

**触发入口**：前端通过 `apiAdapter.ts` 调用 `invoke<T>(command, params)`
**事件监听**：前端通过 `@tauri-apps/api/event` 的 `listen()` 监听事件

**源码位置**：`src/lib/apiAdapter.ts:134-145`

```typescript
// 环境检测
export async function apiCall<T>(command: string, params?: any): Promise<T> {
  const isWeb = !detectEnvironment()
  if (!isWeb) {
    // Tauri 模式 - 直接调用 Rust 函数
    return await invoke<T>(command, params)
  }
  // Web 模式 - 走 REST/WebSocket
  // ...
}
```

#### 模式 B：Web 浏览器模式（WebSocket + REST）

```
React 前端 ──WebSocket──→ Axum Web Server ──spawn──→ Claude CLI
             ws://host/ws/claude                      stdout→WebSocket
React 前端 ──HTTP GET──→ REST API endpoints
```

**WebSocket 端点**：`/ws/claude`
**源码位置**：`src-tauri/src/web_server.rs:252-442`

Web 模式下，流式命令（execute/continue/resume）走 WebSocket，非流式命令走 REST API。

**WebSocket 请求体结构**：

```json
{
  "command_type": "execute", // "execute" | "continue" | "resume"
  "project_path": "/path/to/project",
  "prompt": "用户的问题",
  "model": "claude-sonnet-4-20250514",
  "session_id": null // 仅 resume 时提供
}
```

**WebSocket 响应消息类型**：

```json
// 1. 启动消息
{"type": "start", "message": "Starting Claude execution..."}

// 2. 输出消息（包裹 Claude 的 JSONL 行）
{"type": "output", "content": "{\"type\":\"assistant\",\"message\":{...}}"}

// 3. 完成消息
{"type": "completion", "status": "success"}
{"type": "completion", "status": "error", "error": "错误信息"}

// 4. 错误消息
{"type": "error", "message": "Failed to parse request: ..."}
```

#### 环境自动检测

`apiAdapter.ts:27-51` 通过检测 `window.__TAURI__`、`window.__TAURI_METADATA__`、`window.__TAURI_INTERNALS__` 以及 UserAgent 中的 `Tauri` 标识来判断运行环境，所有调用统一走 `apiCall()` 函数，对上层组件完全透明。

---

### 1.6 进程注册与生命周期管理

**源码位置**：`src-tauri/src/process/registry.rs`

`ProcessRegistry` 是一个全局单例，负责跟踪所有正在运行的 Claude 进程：

```rust
pub struct ProcessRegistry {
    processes: Arc<Mutex<HashMap<i64, ProcessHandle>>>, // run_id → ProcessHandle
    next_id: Arc<Mutex<i64>>,                           // 自增 ID（从 1000000 开始）
}

pub struct ProcessHandle {
    pub info: ProcessInfo,                // 进程元数据
    pub child: Arc<Mutex<Option<Child>>>, // tokio 子进程句柄
    pub live_output: Arc<Mutex<String>>,  // 累积的实时输出
}
```

**生命周期**：

```
register_claude_session()   ← 从 init 消息中提取 session_id 后注册
       ↓
append_live_output()        ← 每行 stdout 输出追加到 live_output
       ↓
get_running_processes()     ← 前端查询活跃进程列表
       ↓
kill_process()              ← 用户取消或超时时终止
       ↓
unregister_process()        ← 进程退出后清理
```

---

### 1.7 任务 ID 与会话 ID 的映射关联机制 (run_id vs session_id)

在 Opcode 中，对于同一个智能体（Agent）或历史聊天对话，系统需要处理两种截然不同的 ID 体系，并且它们呈 **一对多（One-to-Many）** 的关系：

1. **`run_id`（本地调度器执行 ID，短生命周期）**：
   每当用户点击发送或开始一个任务时，SQLite 数据库通过自增主键生成的一个独立任务编号。它代表了操作系统层面**一次独立的子进程拉起**。
2. **`session_id`（Claude 上下文会话 ID，长生命周期）**：
   由 Claude Code CLI 自身生成的 UUID，代表了一个连续的历史对话档案节点（关联着 `.claude/projects/` 下的物理日志）。

由于 Claude CLI 是一个“即用即弃”的命令行工具（生成完回复即进程死亡），为了实现连续的 Web/UI 聊天式对话效果，Opcode 采用了如下机制组合历史会话：

#### 1) 动态探针嗅探与反向绑定

应用启动子进程时，并没有从外部直接把 `session_id` 硬塞给模型控制端，而是在 Rust 端像监听器一样，嗅探 Stdout 管道吐出的第一条类型为 `init` 的 JSONL 块。
一旦解析出官方 CLI 内部决定的 `session_id`，立刻执行 SQL `UPDATE`，将其绑定给当前维持生命周期的 `run_id` 等级数据；同时该值也会反馈，让前端 React 将其锁定到内存状态中（如 `currentSessionId` 变量）。

#### 2) `resume` 命令挂载实现串联

当用户针对上文并未清空，而是继续追问时：

- 之前的那个被拉起的回复子进程早已执行完 `exit 0` 销毁了。

- 前端发现当前环境存在有效记忆的 `session_id`，于是不会调用创建新对话接口，而是调用 `resumeClaudeCode`。
- Rust 会在数据库开辟一个全新的任务执行号（分配新的 `run_id`，如上一次生命周期是编号 15，这次是编号 16），并再次唤醒一个系统子进程。
- **串联核心**：Rust 拼接唤起参数时，为其注入了 `--resume {session_id}`，这就迫使新的 Claude CLI 在启动时，去本地硬盘重新提取那份长效历史存档作为基础上下文，然后再次以 JSON 流应答。

#### 3) 事件总线隔离订阅

纵然底层是通过无数次毁更重拔的短命进程（散落不同的 `run_id`）工作的，每一次进程输出都被打好包，加上当前进程所属被锁定的 `session_id`。
前端 React Hook `useClaudeMessages` 在挂载初期，利用该凭据精确过滤频道广播：

```typescript
listen("claude-output:sess_abc123")
```

通过上述「持久化识别」+「断点重连式运行」+「专属频道订阅」，原本割裂的一次次终端调用过程，在前端被完美整合进同一张顺滑而持久的聊天记录视窗中。

---

## 二、数据流转说明

### 2.1 完整数据流全景图

```
                           ┌──────────────────────────┐
                           │     用户在 UI 中输入       │
                           │  prompt + 选择 model      │
                           └───────────┬──────────────┘
                                       │
                          ┌────────────▼────────────┐
                          │   apiAdapter.ts          │
                          │   环境检测 + 路由分发      │
                          └────┬──────────────┬─────┘
                     Tauri桌面 │              │ Web浏览器
                               │              │
              ┌────────────────▼──┐    ┌──────▼──────────────┐
              │  invoke(command)  │    │ WebSocket 连接       │
              │  Tauri IPC       │    │ ws://host/ws/claude  │
              └────────┬─────────┘    └──────┬───────────────┘
                       │                     │
              ┌────────▼─────────┐    ┌──────▼───────────────┐
              │  Rust Tauri Cmd  │    │  Axum WebSocket      │
              │  execute_claude  │    │  Handler             │
              │  _code()         │    │  claude_websocket()  │
              └────────┬─────────┘    └──────┬───────────────┘
                       │                     │
                       └──────────┬──────────┘
                                  │
                    ┌─────────────▼─────────────┐
                    │  find_claude_binary()      │
                    │  数据库查询 → 系统发现       │
                    └─────────────┬─────────────┘
                                  │
                    ┌─────────────▼─────────────┐
                    │  create_system_command()   │
                    │  构造 CLI 参数 + 环境变量    │
                    └─────────────┬─────────────┘
                                  │
                    ┌─────────────▼─────────────┐
                    │  tokio::process::Command   │
                    │  .spawn()                  │
                    │  生成 Claude CLI 子进程      │
                    └─────────────┬─────────────┘
                                  │
                         stdout (piped) + stderr (piped)
                                  │
                    ┌─────────────▼─────────────┐
                    │  BufReader::lines()        │
                    │  逐行异步读取 JSONL         │
                    │  ┌───────────────────────┐ │
                    │  │ 第1行: system/init     │ │ ──→ 提取 session_id
                    │  │ 第2行: assistant msg   │ │ ──→ 存储 + 发射事件
                    │  │ 第3行: tool_use        │ │ ──→ 存储 + 发射事件
                    │  │ 第N行: response        │ │ ──→ 存储 + 发射事件
                    │  └───────────────────────┘ │
                    └─────────────┬─────────────┘
                                  │
                       ┌──────────┴──────────┐
                Tauri  │                     │  Web
                       │                     │
           ┌───────────▼────────┐  ┌─────────▼──────────┐
           │ app.emit(          │  │ send_to_session()   │
           │  "claude-output:   │  │ WebSocket.send()    │
           │   {sessionId}",    │  │ {"type":"output",   │
           │  line)             │  │  "content": line}   │
           └───────────┬────────┘  └─────────┬──────────┘
                       │                     │
           ┌───────────▼────────┐  ┌─────────▼──────────┐
           │ tauriListen(       │  │ ws.onmessage →     │
           │  "claude-stream")  │  │ window.dispatch-    │
           │                    │  │ Event("claude-      │
           │                    │  │ output", detail)    │
           └───────────┬────────┘  └─────────┬──────────┘
                       │                     │
                       └──────────┬──────────┘
                                  │
                    ┌─────────────▼─────────────┐
                    │  useClaudeMessages Hook    │
                    │  handleMessage()           │
                    │  ┌───────────────────────┐ │
                    │  │ type=start → 设置流式  │ │
                    │  │ type=partial → 累积    │ │
                    │  │ type=response → token  │ │
                    │  │ type=error → 停止流式  │ │
                    │  └───────────────────────┘ │
                    │  setMessages([...prev,msg]) │
                    └─────────────┬─────────────┘
                                  │
                    ┌─────────────▼─────────────┐
                    │  React 组件渲染             │
                    │  MessageList / 输出面板      │
                    └───────────────────────────┘
```

---

### 2.2 Tauri 桌面模式数据流（逐步详解）

#### 步骤 1：用户触发

用户在 React UI 中输入 prompt 并点击执行按钮。

**数据形态**：

```typescript
// 前端调用
apiCall("execute_claude_code", {
  projectPath: "/Users/bruce/my-project",
  prompt: "帮我修复登录页面的 bug",
  model: "claude-sonnet-4-20250514",
})
```

#### 步骤 2：API 适配层路由

`apiAdapter.ts:134` 检测 `window.__TAURI__` 存在，走 Tauri IPC 通道。

**数据形态**：

```typescript
// apiAdapter.ts:141
invoke<void>("execute_claude_code", {
  projectPath: "/Users/bruce/my-project",
  prompt: "帮我修复登录页面的 bug",
  model: "claude-sonnet-4-20250514",
})
```

#### 步骤 3：Rust 命令接收

Tauri 框架将 IPC 调用路由到 `#[tauri::command]` 标注的 Rust 函数。

**数据形态**（Rust 端接收）：

```rust
// claude.rs:921-926
pub async fn execute_claude_code(
    app: AppHandle,
    project_path: String,  // "/Users/bruce/my-project"
    prompt: String,        // "帮我修复登录页面的 bug"
    model: String,         // "claude-sonnet-4-20250514"
) -> Result<(), String>
```

#### 步骤 4：二进制定位

调用 `find_claude_binary(&app)` 搜索 Claude CLI。

**数据形态**（返回值）：

```
Ok("/opt/homebrew/bin/claude")
```

#### 步骤 5：构造 CLI 命令

**数据形态**（生成的完整命令）：

```bash
/opt/homebrew/bin/claude \
    -p "帮我修复登录页面的 bug" \
    --model claude-sonnet-4-20250514 \
    --output-format stream-json \
    --verbose \
    --dangerously-skip-permissions
# 工作目录: /Users/bruce/my-project
```

#### 步骤 6：生成子进程

`tokio::process::Command::spawn()` 创建子进程，stdout 和 stderr 通过管道捕获。

**数据形态**：

```rust
// claude.rs:1185-1195
let mut child = cmd.spawn()?;
let stdout = child.stdout.take();  // AsyncRead
let stderr = child.stderr.take();  // AsyncRead
let pid = child.id();              // e.g., 12345
```

同时将 `child` 存入 `ClaudeProcessState`（全局进程状态），用于后续取消操作。

#### 步骤 7：流式读取 stdout

在独立的 tokio 异步任务中逐行读取。

**数据形态**（stdout 管道中的原始数据）：

```
{"type":"system","subtype":"init","session_id":"sess_abc123","model":"claude-sonnet-4-20250514"}\n
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"我来看看登录页面的代码..."}]}}\n
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"src/Login.tsx"}}]}}\n
...
```

#### 步骤 8：解析 init 消息，提取 session_id

**数据形态**：

```rust
// claude.rs:1232-1258
// 解析第一行 JSON
let msg = serde_json::from_str::<Value>(&line);
// 检查 type == "system" && subtype == "init"
// 提取 session_id = "sess_abc123"
// 注册到 ProcessRegistry，获得 run_id = 1000001
```

#### 步骤 9：发射 Tauri 事件

每行输出发射两个事件 —— 一个带会话 ID 的隔离事件，一个通用事件。

**数据形态**：

```rust
// claude.rs:1268-1272
// 隔离事件（用于多会话场景）
app.emit("claude-output:sess_abc123", &line);
// 通用事件（向后兼容）
app.emit("claude-output", &line);
```

#### 步骤 10：前端事件接收与处理

`useClaudeMessages` Hook 监听事件并更新 React 状态。

**数据形态**：

```typescript
// useClaudeMessages.ts:141-146
tauriListen("claude-stream", (event) => {
  const message: ClaudeStreamMessage = JSON.parse(event.payload)
  handleMessage(message)
  // → setMessages(prev => [...prev, message])
  // → setRawJsonlOutput(prev => [...prev, JSON.stringify(message)])
})
```

#### 步骤 11：进程结束与清理

stdout 读完后，等待子进程退出，发射完成事件。

**数据形态**：

```rust
// claude.rs:1304-1314
let status = child.wait().await?;
// 延迟 100ms 确保消息处理完毕
tokio::time::sleep(Duration::from_millis(100)).await;
app.emit("claude-complete:sess_abc123", status.success()); // true
app.emit("claude-complete", true);
// 从 ProcessRegistry 注销
registry.unregister_process(run_id);
```

---

### 2.3 Web 浏览器模式数据流（逐步详解）

#### 步骤 1-2：与 Tauri 模式相同

用户输入 prompt，`apiAdapter.ts` 检测到 `window.__TAURI__` 不存在。

#### 步骤 3：建立 WebSocket 连接

**数据形态**：

```typescript
// apiAdapter.ts:285-314
const wsProtocol = window.location.protocol === "https:" ? "wss:" : "ws:"
const ws = new WebSocket(`${wsProtocol}//${window.location.host}/ws/claude`)

ws.onopen = () => {
  ws.send(
    JSON.stringify({
      command_type: "execute",
      project_path: "/Users/bruce/my-project",
      prompt: "帮我修复登录页面的 bug",
      model: "claude-sonnet-4-20250514",
      session_id: null,
    }),
  )
}
```

#### 步骤 4：Axum 服务器接收

WebSocket 升级完成后，`claude_websocket_handler()` 开始处理。

**数据形态**（服务端解析）：

```rust
// web_server.rs:310
let request: ClaudeExecutionRequest = serde_json::from_str(&text)?;
// request.command_type = "execute"
// request.project_path = "/Users/bruce/my-project"
// request.prompt = "帮我修复登录页面的 bug"
```

#### 步骤 5：通道转发架构

服务端创建 `mpsc::channel` 用于将 Claude 输出转发到 WebSocket。

```rust
// web_server.rs:267
let (tx, mut rx) = tokio::sync::mpsc::channel::<String>(100);
// tx 存入 active_sessions HashMap
// rx 在 forward_task 中消费，发送到 WebSocket sender
```

#### 步骤 6-7：Claude CLI 生成与流式读取

与 Tauri 模式相同，但输出通过 channel 发送而非 Tauri event。

**数据形态**（每行包装后）：

```rust
// web_server.rs:531-537
let message = json!({
    "type": "output",
    "content": line    // Claude 的原始 JSONL 行
}).to_string();
send_to_session(&state, &session_id, message).await;
```

#### 步骤 8：前端 WebSocket 接收

```typescript
// apiAdapter.ts:316-342
ws.onmessage = (event) => {
  const message = JSON.parse(event.data)
  if (message.type === "output") {
    // 解包：从 content 中提取 Claude 原始消息
    const claudeMessage = JSON.parse(message.content)
    // 通过 DOM CustomEvent 桥接到 useClaudeMessages
    window.dispatchEvent(
      new CustomEvent("claude-output", {
        detail: claudeMessage,
      }),
    )
  }
}
```

#### 步骤 9：useClaudeMessages 接收

Web 模式下，Hook 监听 DOM 事件而非 Tauri 事件：

```typescript
// useClaudeMessages.ts:155-165
window.addEventListener("claude-output", (event) => {
  const message = event.detail as ClaudeStreamMessage
  handleMessage(message) // 与 Tauri 模式共用同一处理函数
})
```

---

### 2.4 反馈机制与交付逻辑

#### 2.4.1 Token 统计反馈

当收到 `type: "response"` 且包含 `usage` 字段时，触发 token 统计回调：

```typescript
// useClaudeMessages.ts:54-59
if (message.type === "response" && message.message?.usage) {
  const totalTokens =
    message.message.usage.input_tokens + message.message.usage.output_tokens
  options.onTokenUpdate?.(totalTokens) // 回调到父组件更新 UI
}
```

#### 2.4.2 流式状态反馈

```typescript
// 开始流式
type === "start" → setIsStreaming(true)
                 → options.onStreamingChange?.(true, sessionId)

// 结束流式
type === "error" | "response" → setIsStreaming(false)
                               → options.onStreamingChange?.(false, sessionId)
```

前端组件根据 `isStreaming` 状态控制 UI 元素（加载动画、禁用输入框等）。

#### 2.4.3 会话信息反馈

```typescript
// useClaudeMessages.ts:79-86
if (message.type === "session_info") {
  options.onSessionInfo?.({
    sessionId: message.session_id,
    projectId: message.project_id,
  })
  setCurrentSessionId(message.session_id)
}
```

#### 2.4.4 部分输出累积（Partial Content）

对于工具调用的流式输出，Opcode 维护一个累积缓冲区：

```typescript
// useClaudeMessages.ts:40-53
if (message.type === "partial" && message.tool_calls) {
  message.tool_calls.forEach((toolCall) => {
    const key = `tool-${toolCall.partial_tool_call_index}`
    accumulatedContentRef.current[key] += toolCall.content
    toolCall.accumulated_content = accumulatedContentRef.current[key]
  })
}
```

这使得前端可以在工具执行过程中实时显示部分结果。

#### 2.4.5 进程完成交付

**Tauri 模式**：

```
claude-complete:{sessionId} 事件 → payload: true (成功) / false (失败)
```

**Web 模式**：

```json
{"type": "completion", "status": "success"}  → resolve Promise
{"type": "completion", "status": "error", "error": "..."} → reject Promise
```

两种模式都会触发 `claude-complete` DOM 事件，供 UI 层做最终状态更新。

#### 2.4.6 数据持久化

- **ProcessRegistry**：`append_live_output(run_id, &line)` 将每行输出追加到内存中的 `live_output` 字段
- **SQLite 数据库**：Agent 执行记录存储在 `agent_runs` 表中，包含 `session_id`、状态、指标等
- **JSONL 文件**：Claude Code 自身在 `~/.claude/projects/` 下维护会话的 JSONL 日志

---

### 2.5 取消与异常处理流程

**源码位置**：`src-tauri/src/commands/claude.rs:1017-1149`

取消执行采用多层回退策略：

```
步骤 1: 查询 ProcessRegistry，尝试通过 session_id 找到 run_id
        ↓ 找到
步骤 2: registry.kill_process(run_id) — 发送 SIGKILL
        ↓ 未找到
步骤 3: 查询 ClaudeProcessState（全局进程状态）
        ↓ 找到
步骤 4: child.kill().await — 通过 tokio 句柄终止
        ↓ 未找到
步骤 5: 通过 PID 使用系统命令终止

// 跨平台终止命令
if cfg!(target_os = "windows") {
    Command::new("taskkill").args(["/F", "/PID", &pid.to_string()])
} else {
    Command::new("kill").args(["-KILL", &pid.to_string()])
}
```

**异常事件传递**：

```
进程异常退出 → child.wait() 返回非零状态
            → emit("claude-complete:{sessionId}", false)
            → 前端 setIsStreaming(false)
            → UI 显示错误状态

WebSocket 异常断开 → ws.onclose (code !== 1000)
                   → dispatch("claude-complete", false)
                   → UI 显示连接断开

stderr 输出 → emit("claude-error:{sessionId}", line)
            → 前端可选展示错误日志
```

---

## 三、历史信息重载延迟分析与优化方案

在 `opcode` 的现存架构下，历史信息的重载延迟实质是由**密集型文件 I/O 扫描**与**大量数据的跨进程（IPC）传输**两头叠加造成的。

### 3.1 延迟原因分析

在代码实现层面（`src-tauri/src/commands/claude.rs`），卡顿和延迟的根源分为两个阶段：

1. **左侧会话列表渲染（宽表全量扫盘）**：
   当用户点开某个 Project 触发 `get_project_sessions` 时，Rust 端为了在列表展示提取好的“首句话/标题”，它必须通过 `fs::read_dir` 扫过该目录下所有 `.jsonl` 文件，甚至对于每一个日志都进行逐行解析 `extract_first_user_message`。一旦会话积累了上百个，这种高吞吐扫描会直接导致明显的延迟。

2. **右侧具体对话读取与 IPC 阻塞（暴力反序列化）**：
   当用户点击某一条对话，调用 `load_session_history` 时，Rust 的做法是将整个数十 MB 或含有上千条纪录的 JSONL，使用 `BufReader` 从头到尾一顿暴力读，外加密集的 `serde_json::from_str` 并组装成臃肿的 `Vec<Value>`。这坨庞然大物透过 Tauri IPC 序列化后扔回给 React 前端，会导致前端在重计算/重渲染甚至通信瞬间卡帧。

### 3.2 优化方案 (由易到难)

要解决这个问题，思路围绕着**缓存化**、**只读必要元信息**、**IPC体积瘦身**展开。建议由容易到复杂的实行进度如下：

#### 🚀 方案一：前端引入全局视图缓存拦截（立刻见效极具性价比）

- **原理说明**：每次切换历史会话都不必重新找后端拉取。用状态库 (例如 Zustand 或用类似 React Query) 将拉取的历史数组直接放置于内存变量。
- **工作流**：
  1. 初次点击会话时（如 `Session A`），发起 `invoke('load_session_history')`，结果拉取后放入内存 Map `key=A`。
  2. 随后 Claude 每次发出 `app.emit("claude-output")` 的增量日志流时，前端订阅并在内存的列表中直接 `push` 追加写入。
  3. 当用户来回切换对话时，前端**不再触发任何后端 IPC 系统调用**，100% 命中缓存，实现 0 毫秒渲染。

#### 📦 方案二：利用 SQLite 接管元数据清单（解决打开时的死锁级白屏）

- **原理说明**：根据现有的架构图，既然 `opcode` 已经有用于存储 `usage db` 计费相关的本地 SQLite 库，这里强烈建议新增一个 `session_metadata` 表。
- **工作流**：
  把类似 `first_message`、`session_id`、`project_id`、`created_at` 的固定元信息在其落盘时插入到 SQLite 里。
  以后左侧列表的刷新不再需要去翻所有文件，仅需一条 SQL `SELECT * FROM sessions WHERE project_id=? ORDER BY created_at DESC;`，瞬间无 I/O 输出结果，仅当真正点进去时才读那个 `.jsonl` 文件。

#### ✂️ 方案三：在 Rust 后台提前处理好增量“瘦身”压缩

- **原理说明**：这是针对极长时间的对话会引起巨量传输的必杀方案。由于 Claude 记录的是 Stream 日志格式，它里面混杂了 `message_start`、`message_delta`、`content_block_delta`，非常零碎且繁重无用。
- **工作流**：
  重构后端的 `load_session_history`：在 Rust 处理日志时便引入归整（Reducer）与聚合算法。例如把那十几条长字符串断更（`delta`），在 Rust 内先进行字符串拼接合并。那些不需要被前端渲染用的冗杂对象抛弃，这样最终交给 IPC 通道传给前端的，是一个精炼、纯净且尺寸缩小 **70% 以上**的数据阵列，可以保证 React 的毫秒级首屏加载。

#### 📖 方案四：反向倒读与瀑布流懒加载（应对极端海量记录）

- **原理说明**：用户看历史通常只看最后几轮问答，没必要将三千行的历史全拉出来。
- **工作流**：
  Rust 服务端利用类似 `rev_lines` 第三方库，逆向读取尾部的最近日志。将 `load_session_history` 增加 `limit` 与 `offset`。在首次开启历史页面时，只拉取位于后段的 N 条最后的内容去组装。待用户在视图内往上滚动历史界面到头时，继续分页发送加载上一页动作的 Invoke。

> **总结意见**：建议先实行**方案一**打底体验，并伴随使用**方案二**去把慢速的文件 `IO scan` 给彻底替换掉。前两条即可立刻解决肉眼可见的明显卡顿。未来随着工程的复杂度演化，再将方案三或方案四结合。

---

## 附录：关键文件索引

| 功能模块               | 文件路径                                                  | 关键行号  |
| :--------------------- | :-------------------------------------------------------- | :-------- |
| Tauri 主入口与命令注册 | `src-tauri/src/main.rs`                                   | 186-292   |
| Claude 执行核心逻辑    | `src-tauri/src/commands/claude.rs`                        | 920-1340  |
| CLI 命令构造           | `src-tauri/src/commands/claude.rs`                        | 293-306   |
| 进程生成与流式处理     | `src-tauri/src/commands/claude.rs`                        | 1174-1340 |
| 取消执行               | `src-tauri/src/commands/claude.rs`                        | 1017-1149 |
| 二进制检测             | `src-tauri/src/claude_binary.rs`                          | 35-95     |
| 进程注册表             | `src-tauri/src/process/registry.rs`                       | 1-120     |
| WebSocket 服务端       | `src-tauri/src/web_server.rs`                             | 252-550   |
| Agent 执行             | `src-tauri/src/commands/agents.rs`                        | 681-993   |
| 前端消息 Hook          | `src/components/claude-code-session/useClaudeMessages.ts` | 1-205     |
| API 适配层             | `src/lib/apiAdapter.ts`                                   | 1-444     |
| 流式命令处理（Web）    | `src/lib/apiAdapter.ts`                                   | 285-411   |
| 命令→端点映射          | `src/lib/apiAdapter.ts`                                   | 165-269   |
