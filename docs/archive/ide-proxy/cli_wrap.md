# 混合流式调用架构详解：opcode 实现剖析

本文档详细剖析了 `opcode` 项目（一个基于 Tauri + Rust 的 Claude Code GUI 客户端）是如何通过混合架构（非 PTY 的流式无头调用 + ID 溯源）优雅地接管和管理 Claude Code CLI 的。

## 1. 架构概述

传统的 GUI 管理 CLI 工具通常面临两种选择：

1.  **完整 PTY 模拟**：实现复杂，需处理各种 ANSI 转义码和复杂的被动终端输入（如等待用户输入 Y/n）。
2.  **一次性调用 (One-off)**：简单但丢失上下文，无法进行多轮连续对话。

`opcode` 采用了一种极其聪明的**第三条道路**：

- **弃用 PTY**：通过底层的 `spawn` 启动进程，并将 `stdin` 置空（`Stdio::null()`），将 `stdout` 和 `stderr` 接管通过管道读取（`Stdio::piped()`）。
- **机器友好格式**：强制注入 `--output-format stream-json` 参数，让 CLI 放弃人类易读的控制台界面（如动态进度条、颜色高亮），转而输出极其标准化的逐行 JSON (JSONL) 数据流。
- **强行静默执行**：注入 `--dangerously-skip-permissions` 参数，剥夺 CLI 中途停顿询问用户权限（如是否允许修改文件、执行命令）的能力，防止进程因等待一个永远不会到来的 `stdin` 输入而死锁僵死。
- **按需提取记忆**：首次创建会话时，从第一行 JSON 截获 Claude CLI 在底层创建的 `session_id`。
- **断点续传式的多轮对话**：下次用户继续提问时，抛弃维护常驻后台的长连接进程，而是直接起一个全新的极短生命周期进程，附带 `--resume <session_id>` 参数，让 Claude CLI 自己去磁盘加载历史上下文。

## 2. 数据流转与执行细节

### 阶段一：初次提问 (发起新会话)

当用户在客户端界面首次发起对话：“帮我写一个 Python HelloWorld”，后端 Rust 代码构建出如下执行命令：

#### 隐式执行的底层命令

```bash
claude -p "帮我写一个 Python HelloWorld" \
  --model claude-3-5-sonnet-20241022 \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions
```

#### 数据流特征 (JSONL 输出)

GUI 控制端监听 `stdout` 管道。数据会像水流一样，一行一行（每行都是一个完整的 JSON）吐出来：

````json
// 1. 系统初始化，客户端必须第一时间捕获这行，提取关键的 session_id
{"type":"system","subtype":"init","session_id":"550e8400-e29b-41d4-a716-446655440000","cwd":"/Users/bruce/projects/demo"}

// 2. 交互开始，大模型准备输出
{"type":"message_start","message":{"id":"msg_01","role":"assistant","content":[],"model":"claude-3-5-sonnet"}}

// 3. 内容块开始 (文本输出)
{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

// 4. 持续吐出的 Delta (流式增量文本)，客户端将 text 字段拼接到 UI 上
{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"好的，没问题。"}}
{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"\n```python\nprint('Hello World')\n```\n"}}

// 5. 内容块结束
{"type":"content_block_stop","index":0}

// 6. 消息生命周期结束，携带本次生成消耗停止原因和部分 Token 统计
{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":25}}
{"type":"message_stop"}

// 7. 系统级使用统计，此时该进程生命周期结束，自动退出
{"type":"usage","message_count":1,"cost":0.001,"input_tokens":100,"output_tokens":25}
````

客户端的唯一职责就是：**解析这份源源不断的 JSON 流**。
对于前端 UI，只需监听 `content_block_delta` 下的 `text`，就能实现打字机效果。把 `usage` 记录下来，存入本地数据库用于计费。最重要的，把第一行的 `session_id` 存入数据库与当前客户端的会话绑定。

### 阶段二：多轮对话中的追问 (恢复会话)

当用户在界面上继续发送追问：“把它改成输出中文”，此时之前的进程**早就死掉了**。但客户端手握第一步拿到的 `session_id`。

#### 隐式执行的底层命令

```bash
claude --resume "550e8400-e29b-41d4-a716-446655440000" \
  -p "把它改成输出中文" \
  --model claude-3-5-sonnet-20241022 \
  --output-format stream-json \
  --verbose \
  --dangerously-skip-permissions
```

#### 数据流特征 (JSONL 输出)

这一次，Claude CLI 启动后，第一件事就是去 `~/.claude/projects/[编码后的工程路径]/550e8400-e29b-41d4-a716-446655440000.jsonl` 中把上一次聊天记录全盘加载（这个动作是 CLI 自己做的，完全不需要 GUI 操心）。

输出的流格式与第一步类似：

````json
// 注意，这里不需要重新生成 session_id，沿用旧的
{"type":"system","subtype":"init","session_id":"550e8400-e29b-41d4-a716-446655440000","cwd":"/Users/bruce/projects/demo"}
{"type":"message_start","message":{"id":"msg_02","role":"assistant","content":[],"model":"claude-3-5-sonnet"}}
{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}
{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"修改如下：\n```python\nprint('你好，世界！')\n```\n"}}
{"type":"content_block_stop","index":0}
{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":30}}
{"type":"message_stop"}
{"type":"usage","message_count":2,"cost":0.003,"input_tokens":125,"output_tokens":30}
````

## 3. 工具调用的特殊处理 (Tool Use 数据流)

如果有复杂操作，如大模型自己决定去修改文件，JSON 流中会带有明确的标志让前端做 UI 渲染（但无需前端干预实际执行，因为加了危险放行指令）：

```json
{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_01","name":"Bash","input":{}}}
{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"command\": \"cat hello.py\"}"}}
{"type":"content_block_stop","index":1}
```

客户端在收到这个事件包后，可以展示 "Agent 正在阅读 hello.py"。当底层执行完毕后，后续的 JSON 流会继续吐出大模型对 `hello.py` 阅读的总结。整个过程客户端都是**纯“旁观者”**。

## 4. 方案总结与优劣势评估

### 为什么这是最适合现代 AI CLI 管理的架构？

1.  **极度轻量与高可用**：没有长连接、没有 PTY 资源泄露问题。每个 `claude` 进程都是用完即抛（Stateless Runner），即便某个进程意外 Crash，也不会导致整个会话坏死（因为记录已经保存在文件中）。
2.  **极简的进程同步**：不需要去写复杂的交互期望代码（比如“期待光标变绿则表示等待输入”这种薛定谔的 PTY 判断），只要没有收到 `message_stop` 事件，大模型就是在思考或执行，全解析 JSON 协议，准确率 100%。
3.  **极简的历史管理**：依靠官方自带的磁盘缓存及 `session_id` 机制，GUI 只需要做个“传话筒和界面画家”，免去了自行统计上万 Token History Message 然后每次带在请求体里的繁琐工作。

### 存在的问题与边界

唯一的问题是：必须启用 `--dangerously-skip-permissions`。这意味着在这一瞬时的生命周期里，这个 Agent 是无拘无束的，它能删代码、它能外连网络、它能通过 Bash 提权。
GUI 开发者为了兜底，必须提供一个一键急救杀进程机制（如给前端暴露强杀底层进程 PID 的按钮）。这对使用这一变种方案的前端提出了必须有“看门狗”架构的要求。

---

# 通用 AI CLI 统一挂载架构 (Claude / Gemini / Codex)

在分析了 `opcode` 对 Claude CLI 的混合挂载架构后，我们验证了这套**「无头直调 + 管道流接管 + 强行免打断 + JSONL解析」**的设计模式，是开发 Mac 客户端管理 AI 命令行工具的通用最优解。

为了彻底证明其普适性，我亲手在本地调研并验证了 **Gemini CLI** 和 **Codex CLI**，发现它们**完全提供了这套模式所需的底层等价参数**。

以下我为你彻底整理的**跨平台多 CLI 统一管理方案**。

## 1. 核心参数映射表 (三剑客等价替换)

要利用这套架构，我们必须在三种主流大厂 CLI 中找到**三把钥匙**：

1. **静默提问**：不进入交互式 TTY 界面，发完问题拿数据就走。
2. **免交互强执行**：跳过一切诸如“是否允许修改文件(Y/n)”的询问。
3. **机器序列化输出**：关闭滚动条、颜色转义符，全部吐纯净 JSONL。
4. **历史复活**：通过 Session ID 唤醒曾经的对话记忆。

| 功能诉求              | Claude Code (`claude`)           | Gemini CLI (`gemini`)                             | Codex CLI (`codex`)                          |
| :-------------------- | :------------------------------- | :------------------------------------------------ | :------------------------------------------- |
| **发起一次性提问**    | `-p "提问内容"`                  | `-p "提问内容"`                                   | `exec "提问内容"`                            |
| **输出转为 JSONL 流** | `--output-format stream-json`    | `-o stream-json` 或 `--output-format stream-json` | `--json`                                     |
| **断点续传历史对话**  | `--resume <session_id>`          | `--resume <session_id>`或`-r <id>`                | `exec resume <session_id>`                   |
| **免打断暴力执行**    | `--dangerously-skip-permissions` | `--yolo` (Automatically accept all actions)       | `--dangerously-bypass-approvals-and-sandbox` |

## 2. 三种 CLI 的详细发包案例

基于上述参数，你的 Mac App (控制端) 可以在完全不建立 PTY 的情况下，通过 Rust 的 `spawn()` + `Stdio::piped()` 来拉起这三种工具的任何一轮对话：

### A. Claude CLI 方案

**创建新对话：**

```bash
claude -p "分析当前目录" --output-format stream-json --dangerously-skip-permissions
```

**基于旧 ID 追问：**

```bash
claude --resume "550e8400-xxx" -p "继续修改" --output-format stream-json --dangerously-skip-permissions
```

### B. Gemini CLI 方案

**创建新对话：**

```bash
gemini -p "分析当前目录" -o stream-json --yolo
```

_(注：`--yolo` 意为 You Only Live Once，在此处是自动 Accept 所有动作的官方参数)_

**基于旧 ID 追问：**

```bash
gemini --resume "550e8400-xxx" -p "继续修改" -o stream-json --yolo
```

### C. Codex CLI 方案

**创建新对话：**

```bash
codex exec "分析当前目录" --json --dangerously-bypass-approvals-and-sandbox
```

**基于旧 ID 追问：**

```bash
codex exec resume "550e8400-xxx" "继续修改" --json --dangerously-bypass-approvals-and-sandbox
```

## 3. 多端通用的 Mac App 前端/后端架构设计

当你的底层收集齐这三套方案后，你的 Mac App 应该设计成如下的**适配器模式 (Adapter Pattern)**：

### 核心接口设计：统一调度层 (Rust / Node 后端)

```rust
// 1. 定义一个统一的前端流式输出事件格式 (App 中立的 JSON 协议)
struct UnifiedAgentEvent {
    status: "thinking" | "executing" | "writing",
    content_delta: String,
    tool_use: Option<String>
}

// 2. 设计通用的执行接口
async fn spawn_agent(cli_type: CLI_TYPE, prompt: String, session_id: Option<String>) {
    let mut cmd = match cli_type {
        CLI_TYPE::Claude => {
            let mut c = Command::new("claude");
            if let Some(id) = session_id { c.arg("--resume").arg(id); }
            c.arg("-p").arg(prompt)
             .arg("--output-format").arg("stream-json")
             .arg("--dangerously-skip-permissions")
        },
        CLI_TYPE::Gemini => {
            let mut c = Command::new("gemini");
            if let Some(id) = session_id { c.arg("--resume").arg(id); }
            c.arg("-p").arg(prompt)
             .arg("-o").arg("stream-json")
             .arg("--yolo")
        },
        CLI_TYPE::Codex => {
            let mut c = Command::new("codex");
            if let Some(id) = session_id {
                c.arg("exec").arg("resume").arg(id).arg(prompt);
            } else {
                c.arg("exec").arg(prompt);
            }
            c.arg("--json").arg("--dangerously-bypass-approvals-and-sandbox")
        }
    };

    // 彻底抛弃交互终端，截获流
    cmd.stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped());

    let mut child = cmd.spawn().unwrap();
    let stdout = child.stdout.take().unwrap();
    let reader = BufReader::new(stdout);

    // 3. 将各家独有的 JSONL 格式剥离，清洗为你规定的统一个 UnifiedAgentEvent 推给前端 UI
    for line in reader.lines() {
        let raw_json: Value = serde_json::from_str(&line.unwrap()).unwrap();
        let normalized_event = match cli_type {
             CLI_TYPE::Claude => parse_claude_jsonl(raw_json),
             CLI_TYPE::Gemini => parse_gemini_jsonl(raw_json),
             CLI_TYPE::Codex  => parse_codex_jsonl(raw_json),
        };
        emit_to_frontend("agent_event", normalized_event);
    }
}
```

### 前端职责 (Tauri / Electron UI 层)

1. **状态无关**：你的前端 UI 组件完全不需要关心当前在跑的是 Claude 还是 Gemini，它只负责监听 `agent_event`。
2. **拦截强杀**：由于底层塞入了“强行提权+免询问”的参数（如 YOLO），前端面板**必须提供一个红色的“Stop”或者“Kill”按钮**。当用户发现它在乱写代码或死循环时，按钮通过 IPC 触发后端的 `child.kill()` 将其物理超度。

## 总结

你完全可以通过同一套**无头进程 + Stdio 截取 + JSON 流 + 会话断点记忆** 的底层逻辑，统治三家目前最强的大语言模型 CLI 工具。

不仅能跨越 CLI 获取极其现代化的流畅 GUI 体验，还能避开以往所有“正则表达式提取控制台颜色”、“Y/n 卡死”的超级大坑。这份落地的可行性论证指南已保存在你的工程目录。

---

## 4. Mac 原生方案评估 (Swift + SwiftUI / AppKit)

使用 Apple 官方的 Swift 语言和 `Foundation` 框架来实现这套架构不仅**完全可行**，而且在 macOS 上的体验和性能甚至会超过基于 Web 技术的 Electron 或 Tauri 方案。

### A. 核心技术栈映射

在 Rust 或 Node.js 中的底层进程调用机制，在 Swift 中都有一一对应的原生实现：

| 架构核心组件       | Rust (Tauri / Tokio)      | Swift (Mac 原生)                                            |
| :----------------- | :------------------------ | :---------------------------------------------------------- |
| **创建无头子进程** | `Command::new(...)`       | `Process()`                                                 |
| **管道流接管**     | `Stdio::piped()`          | `Pipe()`                                                    |
| **环境变量透传**   | `cmd.env(...)`            | `process.environment = ProcessInfo.processInfo.environment` |
| **异步逐行读取**   | `TokioBufReader::lines()` | `FileHandle.readabilityHandler` 或 `Combine` 流监听         |
| **强行杀进程**     | `child.kill()`            | `process.terminate()`                                       |
| **JSON 解析**      | `serde_json`              | `Codable` 或 `JSONSerialization`                            |

### B. Swift 实现的核心代码链路演示

原生 Swift 中，处理子进程生命周期和标准输出的代码非常紧凑并且线程安全：

```swift
import Foundation

class AgentRunner: ObservableObject {
    private var process: Process?
    private var outputPipe: Pipe?

    // 监听实时事件输出
    @Published var latestEvent: String = ""

    func spawnAgent(prompt: String, sessionID: String?) {
        process = Process()
        // 需要处理好查找到完整路径，可以通过 "which claude" 获取
        process?.executableURL = URL(fileURLWithPath: "/usr/local/bin/claude")

        var args = ["-p", prompt, "--output-format", "stream-json", "--dangerously-skip-permissions"]
        if let sid = sessionID {
            // 如果存在旧会话，通过 resume 复活
            args.insert(contentsOf: ["--resume", sid], at: 0)
        }
        process?.arguments = args

        // 【关键组件】挂载管道
        outputPipe = Pipe()
        process?.standardOutput = outputPipe
        process?.standardError = Pipe()     // 忽略错误流，或者单独接管
        process?.standardInput = nil        // 彻底切断标准输入 (核心安全策略，防止卡死)

        // 【关键组件】逐行监听 StdOut
        outputPipe?.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }

            // 收到 JSONL 的一行！接下来反序列化即可
            // print("Received: \(line)")

            DispatchQueue.main.async {
                self?.latestEvent = line
            }
        }

        // 为了安全，记得传系统 PATH 环境变量给大模型 CLI，否则它在执行 Bash 时找不到 node 或 npm 等本地程序
        process?.environment = ProcessInfo.processInfo.environment

        do {
            try process?.run()
        } catch {
            print("Failed to run CLI: \(error)")
        }
    }

    // 强杀进程 (实现紧急停止按钮)
    func killAgent() {
        process?.terminate()
        outputPipe?.fileHandleForReading.readabilityHandler = nil
    }
}
```

### C. Mac 原生方案的优劣势分析

**优势（为什么推荐用 Swift）：**

1. **极致的内存占用**：完全省去了 Chromium 内核或 V8 引擎的庞大开销。对于常驻后台的智能助手（例如屏幕划词、悬浮图标）来说，原生资源消耗极低，对用户电池友好。
2. **深度集成 macOS 原生特性**：如果你希望你的 App 能做到“按下全局快捷键 -> 唤出 Spotlight 风格面板 -> 调用 CLI”的丝滑体验，Swift 原生调用辅助功能 API 的体验是跨平台框架无法比拟的。
3. **进程树环境控制更纯粹**：Electron 或 Tauri 往往涉及繁琐的多进程和 Node.js 环境隔离，Swift 中构建和接管后台 CLI 子进程更为直接纯粹。

**劣势（痛点在哪）：**

1. **纯代码画流式文字较折磨**：接收到的 JSONL 流是碎片化的 Markdown Delta。用 SwiftUI 去动态逐行拼接、渲染并带有打字机特效的流式 Markdown 文本，远没有在前端直接调用极其成熟的 `react-markdown` 来得简单，通常需要手写很多底层解析。
2. **跨平台锁定**：一旦选择了 Swift 原生开发，这个强大的统一管理控制桌面端就彻底与 Windows / Linux 绝缘了。

### D. SwiftUI 渲染 JSON 流的架构建议

面对零碎的 JSON 流：

````json
{"type":"text_delta","text":"\n```"}
{"type":"text_delta","text":"python\n"}
...
````

在前端架构中，你需要维护一个类似于 `@Published var currentMessage: String` 的状态。每次从流中监听到有效的 `text_delta` 后，持续累加 `currentMessage += newText`。UI 展示层则推荐引入类似 `MarkdownUI` 这样的第三方 Swift 视图库进行实时屏幕重新渲染。

## 最终定论

**用 Swift 实现这套逻辑不仅完全可行，而且是追求 Mac 系统级效率工具最佳体验的最终归宿！**

你可以将这一套方案称之为：**面向过程管理 (Swift Process) 的大一统无头会话架构**。核心的解题思想永远不变：

1. 取消人为打字交互口
2. 接通下水道接收纯文本 JSON 流
3. 在需要的时候随时物理拔电源杀进程
4. 靠历史 ID 重生上下文。

---

## 5. Task 粒度全自动调度评估 (Agentic Outer Loop)

你提出的**“Task 粒度下发 -> REPL 大循环自动分析/编码/测试 -> 完成全流程”**的诉求，正是从单纯的“CLI 包装器”向真正的“AI 智能体管家 (Agentic Orchestrator)”进化的核心标志！

基于我们上面确立的“单次调用 + ID 重生上下文”底层架构，实现全自动的“Task 大循环”不仅**完全可行**，而且这套底层架构天生就适合做这种外围包装。

### A. 为什么需要外层大循环 (Outer Loop)？

目前像 Claude Code 这样的工具内部本身就有一定的循环机制（它遇到需运行的 Bash 脚本会自己评估并执行），但如果你把一个极其宏大的 Task（如：“重构整个登录系统从架构到测试”）一次性塞给它，往往会面临以下物理限制：

1. **Token 截断/并发限制**：模型生成达到最大长度被迫停止。
2. **逻辑迷失 (Lost in the middle)**：任务太长，做到后面忘了前面的架构设计。
3. **报错死循环**：测试失败后如果在自己内部死磕容易一直报错。

这就是为什么我们需要在 **Mac 客户端 (控制层)** 用 Swift 或 Rust 写一个外层的**大循环或状态机 (State Machine)**，把大模型 CLI 当成一个“**具备记忆的无状态打工人 (Worker)**”。

### B. "Ralph-Loop / State Machine" 执行模型设计

我们可以在 GUI 客户端定义一个基于状态机的全自动调度器：

1. **破拆规划层 (Planning)**：
   客户端拿到大 Task 后，第一次拉起 CLI：
   `claude -p "请把【重构登录系统】拆分成具体的执行步骤。返回纯 JSON 步骤数组。"`，拿到步骤数组 `[Step 1: 分析原有代码, Step 2: 编写新架构, Step 3: 运行单元测试]`。
2. **循环调度层 (Execution Loop)**：
   在 Swift/控制端中，写一个真正的 `while` 或 `forEach` 异步大循环。

   ```swift
   let sessionID = "全局共享的任务ID"
   for step in plan {
       // 更新 UI 状态
       self.uiState = "正在执行: \(step.name)"

       // 起一个子进程，带上 --resume 和具体的单一子任务
       let prompt = "当前处于任务阶段【\(step.name)】，请仅完成这一步工作。做完后请在末尾输出 <STEP_DONE>"
       let result = await spawnAgent(prompt: prompt, sessionID: sessionID)

       if result.contains("<STEP_DONE>") {
           continue // 进行下一步
       } else if result.contains("ERROR") {
           // 进入自修复子循环...
       }
   }
   ```

3. **自愈与重试层 (Self-Healing)**：
   如果检测到 CLI 进程最终因出错退出，或者生成的代码测试不通过，`while` 循环不需要挂掉，而是再次发号施令：
   `claude --resume <ID> -p "刚刚上面的测试报错了，请修复这个问题然后再试一次。"`

### C. 优雅架构的优势与最佳实践

采用**“客户端控制大循环 + CLI 负责具体的短流程”**的方式，非常优雅，有极高的工程价值：

1. **永不卡死的中断与接续**
   由于你的 `while` 循环是在宿主端（Mac App）控制的，如果你在中间发现它方向错了，可以随时“中止”当前的 Spawn 进程。此时，你依然握手里具有前置进度记忆的 Session ID。通过客户端修改了一下环境或方向后，直接拿着 ID 继续 `spawn` 就可以无缝接续（Resume）。
2. **无限长的全自动开发**
   只要大模型的上下文 Token 上限还能撑住（比如 Claude 3.5 Sonnet 的 200k），依靠这种“做完一步退出来，控制端再推一步进去”的齿轮转动机制，它可以通宵帮你执行长达数十个子步骤的任务，而你完全不需要盯着屏幕手动交互。
3. **沙盒权限动态缩放**
   利用客户端发起请求的优势，你可以在 **分析步骤** 调用 CLI 时加上只读权限 `--sandbox read-only`，在 **编码步骤** 时加上写权限 `--sandbox workspace-write`，做到极致的安全和灵活。

### D. 评估结论

将**“外围任务调度循环 (Task State Machine)”**与我们调研出来的**“无头直调 API (Headless CLI)”**相结合，**是开发本地 Agent 桌面应用的最前沿方向**！

你的 Mac 客户端不再是一个简单的终端皮肤，而是一个**“包工头”**；
三大厂商的 CLI (`claude`, `gemini`, `codex`) 就是被雇佣的**“施工队”**。
只要你捏住了 `session_id` 这个工程合同（记忆上下文），你可以随时在一套标准的大循环代码里调度它们完成端到端的自动化研发。

---

## 6. 附录：深度架构对比 (ClaudecodeUI vs Opcode)

在探索 Mac 客户端的最佳实现路径时，我们调研了两个极具代表性的开源项目：基于 Tauri 的 **Opcode** (`getAsterisk/opcode`) 和基于 Web 技术栈的 **ClaudecodeUI** (`siteboon/claudecodeui`)。它们代表了两种截然不同的架构哲学。

### A. 两种架构的核心机制对比

#### 1. Opcode 架构：主动接管模式 (Active Process Wrapper)

其实质是本文前述详细讨论的**“无头直调挂载架构”**。

- **强控制**：后端（Tauri/Rust）主动 `spawn` 出 `claude` 的子进程。
- **接管流**：通过 `Stdio::piped()` 接听标准输出，注入 `--output-format stream-json`。
- **权限剥夺**：注入 `--dangerously-skip-permissions` 完全剥夺命令行交互权限，防止进程挂起。

#### 2. ClaudecodeUI 架构：被动监听模式 (Passive Watcher & Log Sync)

这是一种**旁路监听与流式同步架构**：

- **弱控制 (旁路)**：核心是一个运行在后台的 Daemon（如 Node 守护进程）。它**不负责启动** CLI。终端里依然跑着原生的 `claude` 命令。
- **日志增量解析**：Daemon 死死盯住 `~/.claude/projects/` 目录下的 JSONL 历史日志文件。一旦 CLI 写入了新 Token 或发生了状态改变，Daemon 就通过 Tailing 捕获变化。
- **Durable Streams 总线**：Daemon 解析日志后，将状态更新发送到基于开放协议 Durable Streams 的实时消息总线上。
- **UI 订阅机制**：前端 (React) 只是 Durable Streams 的订阅者，无需与 CLI 通信，从而实现基于 Web/Mobile 的无缝跨设备同步。

### B. 架构差异详尽对比

| 维度               | Opcode 模式 (主动挂载)                                                             | ClaudecodeUI 模式 (旁路监听)                                                           |
| :----------------- | :--------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------- |
| **CLI 进程关系**   | **父子关系**。UI 是“宿主”，CLI 是子进程。必须从 GUI 发起调用。                     | **平行关系**。用户即使在原生 iTerm 里敲命令，Web UI 也能实时同步看到。                 |
| **数据流转通道**   | 截获内存中的 `Stdout` 管道流。                                                     | 监听磁盘文件变化 (`fs.watch`) 加读取增量数据。                                         |
| **打断与安全交互** | **暴力跳过**。通过强制注入参数放行一切危险操作，把控制权上交给客户端的 Kill 按钮。 | **原生保留**。Daemon 甚至能捕获原生的 `PermissionRequest` 给客户端发送“等待授权”通知。 |
| **跨设备网络能力** | **单机环境绑定**。深度绑定本地 App。                                               | **云原生友好**。借助网络推流组件，可以在云端查看本地跑的任务大盘。                     |

### C. 架构选型最终建议

这两个项目本质上是在解决两个不同层面的需求：

- **ClaudecodeUI 是一个完美的“仪表盘 (Dashboard)”**。它最大的优势是极其**非侵入性**。你仍然可以用最高效的终端工作，界面仅仅作为你的高级扩展显示器存在。
- **Opcode 则是一个“指挥中心 (Controller)”**。它的目的是完全消灭交互终端，让你在一个可视化的沙盒里完成所有事情。

**针对你打算开发的 Mac App（包含大循环 Task 自动调度功能）：**
**请毫不犹豫地选择彻底落实 Opcode 的主动接管模式！**

只有主动握住子进程的生死大权（`spawn` 和 `kill`），你才能在外围写一个大循环（如我们在**第 5 节**展示的那样），控制着大模型一步步执行 Task，并在代码出错时强制复流重试。ClaudecodeUI 那种温柔的旁路监听模式对于实现全自动工头调度来说，控制力是不够用的。不过，你可以借鉴 ClaudecodeUI 的设计，对于自己 Spawn 出来的进程对应的 JSONL 日志，做一个异常监测兜底策略，以提升整个框架的鲁棒性。
