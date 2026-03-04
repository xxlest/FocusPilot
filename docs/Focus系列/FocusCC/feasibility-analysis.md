# FocusCC 产品可行性分析报告

> 生成日期：2026-03-04
> 基于 Claude Code SDK、API 定价、竞品格局的综合调研

---

## 一、产品定义

### 1.1 一句话定位

**FocusCC = macOS 原生的 AI Agent 任务控制中心**

通过管理研发需求 → 形成任务列表 → 以任务维度派发和监控 Claude Code 执行 → 实时展示进度和状态。

### 1.2 核心价值主张

| 痛点 | FocusCC 方案 |
|------|-------------|
| Claude Code 多任务无法可视化监控 | 悬浮球 + 面板实时展示所有 Agent 状态 |
| 任务派发靠手动输入 CLI | GUI 化任务管理，一键派发到 Claude Code |
| Token 消耗无感知，成本不可控 | 实时成本仪表盘 + 预算预警 |
| Agent Teams 只有 CLI 界面 | 可视化团队看板，展示任务依赖图 |
| 开发需求与 Agent 执行脱节 | 需求 → 任务 → 执行 → 验收的闭环管理 |

### 1.3 目标用户

- **主要**：使用 Claude Code 的独立开发者 / 小团队 Tech Lead
- **次要**：需要管理多个 AI Agent 并行开发的团队

---

## 二、需求完善（PRD 补充）

### 2.1 功能模块拆解

#### 模块 1：需求管理

| 功能 | 描述 | 优先级 |
|------|------|--------|
| 需求录入 | 支持文本/Markdown 格式录入需求 | P0 |
| 需求拆解 | 调用 Claude API 将需求自动拆解为子任务 | P1 |
| 需求模板 | 预设 Bug 修复/新功能/重构等模板 | P2 |

#### 模块 2：任务管理

| 功能 | 描述 | 优先级 |
|------|------|--------|
| 任务看板 | Kanban 视图（待办/执行中/已完成） | P0 |
| 任务 DAG | 可视化任务依赖关系图 | P1 |
| 任务模板 | 映射到 Claude Code 的 Skill/Prompt 模板 | P1 |
| 批量操作 | 多任务并行派发、批量暂停/恢复 | P2 |

#### 模块 3：Claude Code 执行引擎

| 功能 | 描述 | 优先级 |
|------|------|--------|
| 任务派发 | 通过 SDK 向 Claude Code 发送任务 | P0 |
| 实时状态 | 解析 stream-json 事件流，展示执行进度 | P0 |
| 会话管理 | 启动/暂停/恢复/终止会话 | P0 |
| 工具监控 | 展示 Agent 调用了哪些工具（Read/Write/Bash 等） | P1 |
| 权限控制 | 配置 allowedTools / permissionMode | P1 |
| 多会话并行 | 同时运行多个 Claude Code 实例 | P1 |
| 结果审查 | 展示 Agent 的文件变更 diff | P1 |

#### 模块 4：监控仪表盘

| 功能 | 描述 | 优先级 |
|------|------|--------|
| Agent 状态面板 | 每个 Agent 的运行状态（idle/running/error/done） | P0 |
| Token 消耗统计 | 按任务/会话/日/月统计 token 用量 | P0 |
| 成本估算 | 基于 API 定价实时计算费用 | P1 |
| 预算预警 | 单任务/日/月成本超阈值告警 | P1 |
| 执行日志 | 完整的工具调用日志和输出 | P1 |

#### 模块 5：悬浮入口（复用 PinTop 架构）

| 功能 | 描述 | 优先级 |
|------|------|--------|
| 状态悬浮球 | 常驻桌面，颜色/动画反映全局 Agent 状态 | P0 |
| 快捷面板 | hover 弹出，显示当前活跃任务概览 | P0 |
| 主看板 | 双击进入完整管理界面 | P0 |

### 2.2 状态转换矩阵

```
需求状态：
  Draft → Ready → In Progress → Done / Cancelled

任务状态：
  Pending → Queued → Dispatched → Running → Completed / Failed / Cancelled
                                     ↓
                                  Paused → Running (恢复)

Agent 会话状态：
  Init → Connected → Executing → Streaming → Idle → Terminated
                        ↓
                     Error → Retry → Executing (最多 3 次)
```

---

## 三、技术可行性评估

### 3.1 Claude Code SDK 能力匹配度

| FocusCC 需求 | SDK 支持情况 | 可行性 |
|-------------|-------------|--------|
| 任务派发 | `query()` API + `ClaudeSDKClient` 持续会话 | ✅ 完全支持 |
| 实时状态流 | `stream-json` + `include_partial_messages` | ✅ 完全支持 |
| 会话恢复 | `resume` + `fork_session` API | ✅ 完全支持 |
| 权限控制 | `allowed_tools` / `disallowed_tools` / `permission_mode` | ✅ 完全支持 |
| 工具调用监控 | `PreToolUse` / `PostToolUse` Hooks | ✅ 完全支持 |
| Token 统计 | `ResultMessage.usage` 字段 | ✅ 完全支持 |
| 多会话并行 | 多进程 + Git Worktree 隔离 | ⚠️ 可行但需自建会话池 |
| 任务中断 | `Query.interrupt()` API | ✅ 完全支持 |
| 成本上限 | `max_budget_usd` 参数 | ✅ 完全支持 |
| 自定义工具 | SDK MCP Server（进程内工具注入） | ✅ 完全支持 |

### 3.2 技术栈选择

**核心决策：用什么语言调用 Claude Code SDK？**

Claude Agent SDK 提供 Python 和 TypeScript 两个版本。但 FocusCC 的 GUI 是 macOS 原生（Swift/AppKit）。

**方案对比**：

| 方案 | 架构 | 优点 | 缺点 |
|------|------|------|------|
| A. Swift GUI + Python Bridge | Swift 主进程 ↔ Python 子进程（SDK） | SDK 功能完整，Hook/MCP 全支持 | 双语言维护，IPC 复杂 |
| B. Swift GUI + CLI 子进程 | Swift 直接 spawn `claude -p --output-format stream-json` | 最简单，无额外依赖 | 无 Hook、无持续会话、每次 50K token 开销 |
| C. Swift GUI + TypeScript Bridge | Swift ↔ Node.js 子进程（SDK） | SDK 完整，TypeScript 生态更成熟 | 需要 Node.js 运行时 |
| D. Electron/Tauri + TypeScript | 放弃原生，全 TypeScript | SDK 原生集成，开发最快 | 非 macOS 原生，资源占用高 |

**推荐方案：A 或 B（分阶段）**

- **MVP 阶段用方案 B**：直接 spawn CLI 子进程，解析 stream-json 输出，快速验证产品价值
- **正式版升级到方案 A**：引入 Python SDK Bridge，获得 Hook、持续会话、MCP 等高级能力

### 3.3 关键技术实现路径

#### 3.3.1 任务派发（MVP - CLI 方式）

```swift
// Swift 端：spawn claude 子进程
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/local/bin/claude")
process.arguments = [
    "-p", taskPrompt,
    "--output-format", "stream-json",
    "--verbose",
    "--allowedTools", "Read,Write,Edit,Bash,Grep,Glob",
    "-C", projectPath  // 工作目录
]

// 通过 Pipe 读取 stream-json 输出
let pipe = Pipe()
process.standardOutput = pipe

pipe.fileHandleForReading.readabilityHandler = { handle in
    let data = handle.availableData
    // 逐行解析 NDJSON → 更新 UI 状态
    parseStreamEvent(data)
}
```

#### 3.3.2 实时状态解析

stream-json 事件流结构：

```
message_start → 会话开始
content_block_start → 内容块开始（text / tool_use）
content_block_delta → 增量文本或工具输入
content_block_stop → 内容块结束
message_delta → 消息完成（含 stop_reason）
message_stop → 消息流结束
AssistantMessage → 完整消息对象（含 usage）
```

可从事件流中提取的状态信息：

| 事件 | 可提取信息 |
|------|-----------|
| `content_block_start (tool_use)` | Agent 正在调用哪个工具 |
| `content_block_delta (text_delta)` | Agent 的思考过程文本 |
| `content_block_delta (input_json_delta)` | 工具调用参数 |
| `AssistantMessage.usage` | 本轮 input/output token 数 |
| `message_delta.stop_reason` | "end_turn" / "tool_use" / "max_tokens" |

#### 3.3.3 多会话管理

```
SessionManager
├── sessions: [SessionID: ClaudeSession]
├── createSession(task, projectPath) → SessionID
├── pauseSession(id) → interrupt()
├── resumeSession(id) → resume API
└── terminateSession(id) → kill process

ClaudeSession
├── process: Process (系统进程)
├── status: .idle / .running / .paused / .error / .completed
├── tokenUsage: (input: Int, output: Int)
├── currentTool: String?  // 正在调用的工具
├── outputBuffer: [StreamEvent]
└── startTime / duration
```

---

## 四、定价分析

### 4.1 Claude Code 的成本结构

#### API 按量付费（FocusCC 推荐方式）

| 模型 | 输入 ($/百万token) | 输出 ($/百万token) | 适用场景 |
|------|-------------------|-------------------|---------|
| Opus 4.6 | $5.00 | $25.00 | 复杂架构/推理任务 |
| Sonnet 4.6 | $3.00 | $15.00 | 日常开发（推荐默认） |
| Haiku 4.5 | $1.00 | $5.00 | 简单任务/预处理 |

#### 典型任务成本估算

| 任务类型 | 输入 token | 输出 token | 模型 | 单次成本 |
|---------|-----------|-----------|------|---------|
| 简单 Bug 修复 | ~10K | ~5K | Sonnet | ~$0.11 |
| 中等功能开发 | ~50K | ~20K | Sonnet | ~$0.45 |
| 复杂架构重构 | ~150K | ~50K | Opus | ~$2.00 |
| 多文件批量修改 | ~100K | ~80K | Sonnet | ~$1.50 |

#### 成本优化杠杆

| 优化手段 | 节省幅度 | 实现方式 |
|---------|---------|---------|
| Prompt Caching | 90% 输入成本 | CLAUDE.md 自动缓存，重复上下文只付 10% |
| 模型分级 | 60-80% | 80% 任务用 Sonnet，仅复杂推理用 Opus |
| 持续会话 | 10x | SDK ClaudeSDKClient 避免重复注入 50K context |
| Batch API | 50% | 非实时任务批量处理 |
| 预算上限 | 可控 | `max_budget_usd` 参数 |

#### 月度成本模型（单开发者）

| 使用强度 | 日均任务数 | 月均成本（Sonnet 为主） | 月均成本（Opus 为主） |
|---------|----------|----------------------|---------------------|
| 轻度 | 5-10 | $30-60 | $80-150 |
| 中度 | 15-30 | $100-200 | $250-500 |
| 重度 | 50+ | $300-600 | $800-1500 |

### 4.2 FocusCC 产品定价建议

#### 订阅 vs API 中转

| 模式 | 说明 | 适合 |
|------|------|------|
| A. 纯工具（用户自带 API Key） | FocusCC 只收工具费，用户自己承担 API 成本 | MVP 阶段，降低用户信任门槛 |
| B. API 中转加价 | FocusCC 代理 API 调用，加 10-20% 服务费 | 成熟阶段，增加收入 |
| C. 绑定 Max 计划 | 用户使用自己的 Max 订阅，FocusCC 通过 CLI 调用 | 最低成本，但受 Max 用量限制 |

**MVP 阶段推荐模式 A**：

| FocusCC 计划 | 月费 | 包含内容 |
|-------------|------|---------|
| 免费版 | $0 | 单任务执行，基础监控，3 个历史任务 |
| Pro | $19/月 | 多任务并行（5 个），成本追踪，任务历史无限 |
| Team | $49/人/月 | 团队看板，共享任务模板，权限管理 |

### 4.3 API 速率限制对产品的影响

| Tier | 并发请求上限 (RPM) | 对 FocusCC 的影响 |
|------|-------------------|------------------|
| Tier 1 ($5 充值) | 50 RPM | 最多 ~5 个并行任务 |
| Tier 2 ($40) | 1,000 RPM | 足够大多数场景 |
| Tier 3 ($200) | 2,000 RPM | 团队级使用 |
| Tier 4 ($400) | 4,000 RPM | 企业级 |

**关键约束**：每个 Claude Code 会话的一个 turn 通常包含多次 API 调用（思考 + 工具调用 + 结果处理）。5 个并行任务在 Tier 1 下可能触发限流。

---

## 五、推荐架构方案

### 5.1 MVP 架构（方案 B：CLI 子进程）

```
┌─────────────────────────────────────────────┐
│              FocusCC.app (Swift/AppKit)       │
├──────────┬──────────┬───────────────────────┤
│ 悬浮球   │ 快捷面板  │     主看板 (SwiftUI)   │
│ BallView │ PanelView│  TaskBoard / Dashboard │
├──────────┴──────────┴───────────────────────┤
│              核心服务层                        │
│  ┌─────────┐ ┌──────────┐ ┌───────────────┐ │
│  │TaskStore│ │SessionMgr│ │ CostTracker   │ │
│  │(需求/   │ │(会话池)   │ │(Token 统计)   │ │
│  │ 任务)   │ │          │ │               │ │
│  └────┬────┘ └────┬─────┘ └───────┬───────┘ │
│       │           │               │          │
│  ┌────┴───────────┴───────────────┴────────┐ │
│  │         StreamParser (NDJSON 解析)       │ │
│  └────────────────┬────────────────────────┘ │
├───────────────────┼─────────────────────────┤
│  Process 层        │                          │
│  ┌────────────────┴────────────────────────┐ │
│  │  claude -p "..." --output-format         │ │
│  │    stream-json --verbose                 │ │
│  │  (每个任务一个子进程)                      │ │
│  └─────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

#### 文件结构（预估）

```
FocusCC/
├── App/
│   ├── FocusCCApp.swift           # @main 入口
│   └── AppDelegate.swift          # 生命周期
├── FloatingBall/                  # 复用 PinTop
│   ├── FloatingBallWindow.swift
│   └── FloatingBallView.swift     # 颜色映射 Agent 状态
├── QuickPanel/                    # 复用 PinTop，改造内容
│   ├── QuickPanelWindow.swift
│   └── QuickPanelView.swift       # 活跃任务概览
├── MainKanban/                    # 复用 PinTop 结构
│   ├── MainKanbanWindow.swift
│   ├── TaskBoardView.swift        # 任务看板 (SwiftUI)
│   ├── DashboardView.swift        # 监控仪表盘 (SwiftUI)
│   └── SettingsView.swift         # 配置 (API Key, 模型等)
├── Models/
│   ├── Requirement.swift          # 需求模型
│   ├── Task.swift                 # 任务模型
│   ├── Session.swift              # 会话模型
│   └── StreamEvent.swift          # stream-json 事件模型
├── Services/
│   ├── TaskStore.swift            # 任务持久化
│   ├── SessionManager.swift       # Claude Code 会话管理
│   ├── StreamParser.swift         # NDJSON 解析器
│   ├── CostTracker.swift          # Token/成本追踪
│   └── ProcessManager.swift       # 子进程生命周期
├── Helpers/
│   └── Constants.swift
└── Resources/
    └── Info.plist
```

### 5.2 正式版架构（方案 A：Python SDK Bridge）

```
┌───────────────────────────────────────────────────┐
│               FocusCC.app (Swift/AppKit)            │
│  ┌──────────────────────────────────────────────┐  │
│  │                  UI 层（同 MVP）               │  │
│  └──────────────────┬───────────────────────────┘  │
│                     │ (NotificationCenter)          │
│  ┌──────────────────┴───────────────────────────┐  │
│  │              核心服务层 (Swift)                 │  │
│  │  TaskStore + CostTracker + UIState            │  │
│  └──────────────────┬───────────────────────────┘  │
│                     │ (Unix Socket / JSON-RPC)      │
├─────────────────────┼──────────────────────────────┤
│  ┌──────────────────┴───────────────────────────┐  │
│  │         Python Bridge (SDK 层)                │  │
│  │  ┌─────────────┐ ┌────────────────────────┐  │  │
│  │  │SessionPool  │ │ HookManager            │  │  │
│  │  │(持续会话池) │ │ (PreToolUse/PostToolUse)│  │  │
│  │  └──────┬──────┘ └─────────┬──────────────┘  │  │
│  │         │                  │                  │  │
│  │  ┌──────┴──────────────────┴──────────────┐  │  │
│  │  │     Claude Agent SDK (Python)           │  │  │
│  │  │     ClaudeSDKClient × N (持续会话)      │  │  │
│  │  └────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────┘
```

正式版相比 MVP 的增量：

| 能力 | MVP (CLI) | 正式版 (SDK) |
|------|-----------|-------------|
| 持续会话 | ❌ 每次新进程 | ✅ 复用会话，节省 10x token |
| Hook 拦截 | ❌ | ✅ PreToolUse/PostToolUse |
| MCP 自定义工具 | ❌ | ✅ SDK MCP Server |
| 权限动态切换 | ❌ | ✅ setPermissionMode |
| 子代理编排 | ❌ | ✅ Agent Teams |
| 会话分支 | ❌ | ✅ fork_session |

---

## 六、重点难点评估

### 6.1 核心难点

| # | 难点 | 难度 | 说明 |
|---|------|------|------|
| 1 | **stream-json 实时解析与 UI 映射** | ★★★★ | NDJSON 事件种类多（10+ 种），需正确映射到 UI 状态机，处理乱序/截断/重连 |
| 2 | **多会话并行管理** | ★★★★ | SDK 无内置会话池，需自建进程/会话管理器，处理资源竞争和错误恢复 |
| 3 | **Swift ↔ Python IPC（正式版）** | ★★★★ | 跨语言通信（Unix Socket / stdio），序列化/反序列化，错误传播，进程生命周期 |
| 4 | **Claude Code 版本兼容** | ★★★ | Claude Code 更新频繁（周级），stream-json 事件 schema 可能变化 |
| 5 | **状态一致性** | ★★★ | 进程异常退出/网络断开时，任务状态与实际执行状态可能不一致 |
| 6 | **成本精确计算** | ★★ | 需要从 stream 事件中提取 usage 信息，处理 Prompt Caching 折扣计算 |

### 6.2 技术风险点

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| Claude Code CLI 接口不稳定 | 重大 - 核心依赖 | 抽象 adapter 层，版本锁定 + 兼容性测试 |
| API 限流导致任务阻塞 | 中等 | 任务队列 + 退避重试 + Tier 级别感知 |
| 子进程意外退出 | 中等 | 进程监控 + 心跳检测 + 自动恢复 |
| Token 消耗超预期 | 中等 | max_budget_usd + 预算预警 + 自动暂停 |
| macOS 权限问题（辅助功能） | 低（复用 PinTop 经验） | 自签名证书持久化 |

---

## 七、风险评估

### 7.1 产品风险

| 风险 | 概率 | 影响 | 应对 |
|------|------|------|------|
| **Anthropic 自己做了类似产品** | 高 | 致命 | 差异化定位（macOS 原生 + 成本管控 + 外部系统桥接）；Claude Code 原生 Tasks 系统已经在做类似的事，但无 GUI |
| **用户数太少（市场太窄）** | 中 | 高 | MVP 先验证需求；考虑支持多 Agent（不只 Claude Code） |
| **Claude Code 免费替代品涌现** | 中 | 中 | 开源竞品已有 10+ 个（Nimbalyst, Ruflo, ccswarm 等），需要差异化 |
| **定价敏感** | 中 | 中 | 免费版兜底，Pro 版强调 ROI（节省的时间 vs 工具费用） |

### 7.2 技术风险

| 风险 | 概率 | 影响 | 应对 |
|------|------|------|------|
| **SDK 破坏性更新** | 中 | 高 | 锁定版本 + 抽象层 + 自动化兼容性测试 |
| **多进程资源消耗** | 中 | 中 | 5 个并行 Claude Code 进程 ≈ 2-3GB RAM；设上限 |
| **NDJSON 解析边界情况** | 中 | 低 | 完善的错误处理 + 事件重放机制 |

### 7.3 商业风险

| 风险 | 概率 | 影响 | 应对 |
|------|------|------|------|
| **竞品先发优势** | 高 | 高 | Nimbalyst 已经在做类似产品且获 SOC 2 认证；聚焦 macOS 原生 + 中文市场差异化 |
| **平台依赖（Anthropic）** | 高 | 高 | 长期考虑支持 Codex / Gemini Code 等多 Agent |
| **付费意愿低** | 中 | 中 | 开源核心 + 增值服务模式 |

---

## 八、竞品格局

### 8.1 直接竞品

| 产品 | 类型 | 优势 | 劣势 | FocusCC 差异点 |
|------|------|------|------|---------------|
| **Nimbalyst** | Electron 桌面 App | 功能全面，SOC 2 认证，iPhone 配对 | 重，非原生，功能过多 | macOS 原生，轻量，聚焦 |
| **Claude Code Tasks** | CLI 内置 | Anthropic 官方，DAG 依赖，零成本 | 无 GUI，纯 CLI | GUI 可视化 |
| **Cursor Agent** | IDE 内置 | 8 并行 Agent，云 VM | 绑定 IDE，无独立管理 | 独立于 IDE |
| **Devin** | SaaS | 异步执行，端到端 | 贵（$500/月），黑盒 | 本地运行，透明可控 |

### 8.2 开源竞品

| 项目 | Stars | 特点 | 状态 |
|------|-------|------|------|
| Ruflo | - | 多 Agent 蜂群，自学习 | 活跃 |
| ComposioHQ/agent-orchestrator | - | Planner+Executor，40K 行 TS | 活跃 |
| ccswarm | - | Rust，Git Worktree 隔离 | 活跃 |
| claude-octopus | - | 多模型对抗审查 | 早期 |

---

## 九、实施路线图建议

### Phase 1: MVP（4-6 周）

- 复用 PinTop 悬浮球 + 面板架构
- 实现单任务派发（CLI 子进程方式）
- stream-json 解析 + 基础状态展示
- Token 计数 + 简单成本统计
- 目标：**验证"GUI 管理 Claude Code 任务"的核心价值**

### Phase 2: 多任务管理（4 周）

- 任务看板（Kanban）
- 多会话并行（最多 5 个）
- 任务模板（Bug/Feature/Refactor）
- 成本仪表盘 + 预算预警

### Phase 3: SDK 集成（6 周）

- Python SDK Bridge（持续会话）
- Hook 系统接入（工具监控）
- 会话恢复/分支
- 高级权限控制

### Phase 4: 团队与生态（8 周）

- Agent Teams 可视化
- 外部系统桥接（GitHub Issues）
- 任务 DAG 可视化
- 多 Agent 支持（Codex 等）

---

## 十、总结

### 可行性结论：✅ 技术可行，但需分阶段验证产品价值

**核心判断**：
1. Claude Code SDK 的能力**完全支持** FocusCC 的所有核心需求
2. MVP 可用 CLI 子进程方式快速实现，技术风险低
3. 最大风险不是技术，而是**市场**——Anthropic 自己可能做类似产品，开源竞品已有 10+
4. 差异化定位是关键：**macOS 原生 + 中文市场 + 轻量常驻 + 成本管控**

### 成本结论

| 场景 | 月成本 |
|------|--------|
| 个人开发者（Sonnet 为主，中度） | $100-200 API 费用 |
| 小团队（5 人，Sonnet 混合 Opus） | $500-1500 API 费用 |
| Max 20x 订阅替代 | $200/人/月 固定（重度使用更划算） |

FocusCC 本身的价值在于**让这些成本可见、可控、可优化**。
