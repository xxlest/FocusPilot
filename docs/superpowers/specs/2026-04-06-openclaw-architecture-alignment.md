# OpenClaw 架构对齐设计文档

> **日期**：2026-04-06
> **状态**：设计确认
> **范围**：Editions.md + PRD.md 架构对齐
> **决策**：从自建 Python Engine 切换到 OpenClaw Gateway + 自建 MCP Server

---

## 1. 架构变更总览

### 1.1 前后对比

```
原架构：
┌─ Swift UI 壳 ─┐     ┌─ Python Engine（全部自建）──┐
│ 悬浮球/面板/番茄钟 │ ──→ │ FastAPI + WebSocket        │
│               │     │ 项目引擎 / MCP Host         │
│               │     │ Scheduler / Pipeline        │
└───────────────┘     └────────────────────────────┘
                       自建比例 ≈ 100%

新架构：
┌─ Swift UI 壳 ─┐     ┌─ OpenClaw Gateway（现成）──┐
│ 悬浮球/面板/番茄钟 │ ──→ │ WebSocket RPC ✓            │
│               │ WS  │ Agent Runtime ✓             │
│               │ RPC │ Skill 系统 ✓                │
│               │     │ 多渠道路由 ✓                 │
│               │     │ Scheduler ✓                 │
│               │     ├────────────────────────────┤
│               │     │ 自建 MCP Server（独立进程）  │
│               │     │ focuspilot-executor         │
│               │     │ focuspilot-project-engine   │
└───────────────┘     └────────────────────────────┘
                       自建比例 ≈ 20%
```

### 1.2 关键架构决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 后台底座 | OpenClaw Gateway | 省 80% 基础设施开发（Agent 编排、WebSocket、Skill、多渠道） |
| 扩展方式 | MCP Server 注册 | 不改 OpenClaw 源码，方便后续升级 |
| 两产品线关系 | 共用底座 | 同一套 Skills/MCP Server，不同部署模式 |
| Swift↔后台通信 | WebSocket RPC | OpenClaw 标准协议 |
| 代码执行 | Code Executor MCP + spawn claude-p | Claude Code 是完整 Agent，不能被 OpenClaw LLM 指挥 |
| 两阶段衔接 | Markdown 文件为契约 | 人可读、Git 可追踪、支持手动/自动两种模式 |
| 仓库结构 | 暂不拆分 | PilotOne 未开始开发，等真正启动时再评估 |

---

## 2. Pilot 产品家族统一架构

### 2.1 分层架构

```
┌─────────────── 前端层（客户端）───────────────┐
│                                               │
│  FocusPilot          飞书/微信 Bot   Web App  │
│  (Swift macOS)       (OpenClaw 内置)  (预留)  │
│  个人版主入口         远程轻量指挥     预留     │
│                                               │
│  PilotOne                                     │
│  飞书/钉钉 Bot + Web App（OpenClaw 内置）      │
│  企业版主入口                                  │
│                                               │
└───────────┬───────────────────┬───────────────┘
            │ WebSocket RPC     │ WebSocket RPC
            ▼                   ▼
┌─────── OpenClaw Gateway（不改源码）───────────┐
│                                               │
│  Agent Runtime    Skill 系统    多渠道路由     │
│  Agent 编排+调度   内置+自建     飞书/微信/钉钉 │
│                                               │
│  Scheduler        Session 管理   Canvas/A2UI  │
│  定时/事件触发     会话隔离       可视化工作区   │
│                                               │
├─────── 注册 MCP Server（自建，独立进程）──────┤
│                                               │
│  focuspilot-executor          MCP Server      │
│  代码执行（spawn claude-p）    stdio 通信      │
│                                               │
│  focuspilot-project-engine    MCP Server      │
│  项目管理（Markdown CRUD）     stdio 通信      │
│                                               │
├─────── Personal Assistant Agent（OpenClaw 内）┤
│                                               │
│  个人助理 Agent（OpenClaw LLM Agent）          │
│  任务拆解 / Dashboard / 知识管道 / 对话        │
│  调用 Brainstorming Skill 进行规划             │
│  规划完成后通过 RPC 触发 Code Executor         │
│                                               │
└───────────────────────────────────────────────┘

部署模式：
  FocusPilot → 本地 OpenClaw（launchd 守护，localhost）
  PilotOne  → 云端 OpenClaw（Docker，公网+认证）
```

### 2.2 两产品线共用底座

| | FocusPilot（个人版） | PilotOne（企业版） |
|---|---|---|
| 前端 | Swift macOS App | Web + 飞书/钉钉 Bot |
| 后台 | OpenClaw（本地 launchd） | OpenClaw（云端 Docker） |
| 通信 | WebSocket RPC | WebSocket RPC |
| 共用 | MCP Server + Skills 代码完全相同 | 同左 |
| 差异 | 单用户，本地数据 | 多用户+权限，云端数据 |
| 专属 Skills | 知识管道（素材→报告→KB→Anki） | 数字专家团（五角色）、简报系统 |

---

## 3. 两种执行模式

### 3.1 手动模式（现有，保留不动）

```
用户手动在终端启动 Claude Code
  → coder-bridge hook 拦截事件
  → DistributedNotification
  → CoderBridgeService（Swift）
  → Quick Panel AI Tab 显示状态

Code Executor MCP 完全不参与。
```

### 3.2 自动模式（新增）

```
用户在 FocusPilot 点"执行"
  → WebSocket RPC → OpenClaw
  → Code Executor MCP
  → spawn `claude -p <task>` --output-format stream-json
  → 流式回传状态 → WebSocket RPC → Swift UI 更新
  → 完成后更新 Task markdown: status → done

coder-bridge 完全不参与。
```

两条链路独立，互不干扰。

---

## 4. 两阶段模型衔接

### 4.1 Markdown 文件作为契约

Personal Assistant Agent（规划阶段）和 Code Executor MCP（执行阶段）通过 Markdown 文件交接：

```
规划阶段（Personal Assistant Agent）
    │
    │ 1. 用户输入："帮我实现用户认证模块"
    │ 2. 调用 Brainstorming Skill，和用户对话澄清
    │ 3. 拆解为多个 Task，写入 markdown 文件
    │    status: ready
    │
    ▼
task-jwt-api.md ← 契约文件
    │
    │ ---
    │ type: task
    │ status: ready
    │ agent: claude-code
    │ code_path: ~/projects/myapp
    │ ---
    │ 实现 JWT 认证接口，保持向后兼容，添加单元测试
    │
    ▼
执行阶段（Code Executor MCP）
    │
    │ 1. 收到 RPC: execute(task_path)
    │ 2. 读取 markdown 文件，提取内容 + code_path
    │ 3. 更新 status: ready → executing
    │ 4. spawn `claude -p "<内容>" --cwd <code_path>`
    │ 5. 流式回传输出
    │ 6. 完成后更新 status: executing → done
    │
    ▼
Claude Code（自主 Agent，自己推理执行）
```

### 4.2 为什么用文件而非直接 RPC

| 优势 | 说明 |
|------|------|
| 人可读 | 打开 markdown 就能看到任务内容和状态 |
| Git 可追踪 | 规划历史、执行记录全有 |
| 手动模式兼容 | 用户可以手动复制内容去终端执行 |
| 断点续做 | 重启后 status: ready 的任务继续执行 |
| 审计 | 谁规划的、什么时候执行的、结果如何 |

---

## 5. Code Executor MCP 设计

### 5.1 职责

独立 MCP Server 进程，不改 OpenClaw 源码，通过 stdio 注册到 OpenClaw。

**核心定位：直通管道，不是 LLM Agent**。不推理、不拆解、不决策，只做：接收 Task → spawn 子进程 → 流式回传。

### 5.2 提供的 Tool

```
execute_code_task(task_path, agent?)
  读取 markdown → spawn 对应 agent → 流式回传 → 更新状态

get_task_status(task_path)
  返回当前执行状态

stop_task(task_path)
  终止正在执行的任务
```

### 5.3 多 Agent 适配器

```
Code Executor MCP
    │
    ├── claude-code adapter
    │   spawn: claude -p <task> --cwd <path> --output-format stream-json
    │
    ├── codex adapter（预留）
    │   spawn: codex -p <task> --cwd <path>
    │
    └── gemini adapter（预留）
        spawn: gemini -p <task> --cwd <path>
```

根据 Task frontmatter 的 `agent` 字段选择 adapter。默认 `claude-code`。

### 5.4 风控策略

**策略一：高频调用限制**

| 参数 | 默认值 | 说明 |
|------|--------|------|
| max_concurrent | 1 | 同时执行的最大任务数 |
| min_interval_seconds | 30 | 两次 spawn 之间的最小间隔 |
| max_daily_executions | 50 | 每日最大执行次数 |
| queue_mode | fifo | 超出并发时排队，不丢弃 |

超出限制时任务进入队列等待，不直接拒绝。日志记录每次调用的时间戳和 token 消耗。

**策略二：订阅额度监控**

| 参数 | 默认值 | 说明 |
|------|--------|------|
| daily_token_budget | 0（不限） | 每日 token 预算，0 表示不限 |
| warning_threshold | 80% | 接近预算时发出警告 |
| hard_limit_action | pause | 超出预算时：pause（暂停队列）/ warn（仅警告） |

通过解析 `claude -p` 的 stream-json 输出中的 usage 字段统计 token 消耗。接近上限时：
1. 推送通知到 FocusPilot UI（"今日额度已用 80%"）
2. 达到上限时暂停执行队列，等待用户确认

**策略三：执行环境隔离**

| 策略 | 说明 |
|------|------|
| cwd 强制绑定 | 每个 Task 的 code_path 必须在允许的目录列表中 |
| 权限控制 | 默认不使用 `--dangerously-skip-permissions`，用户可按项目开启 |
| 超时控制 | 单任务最大执行时间（默认 30 分钟），超时自动终止 |
| 输出隔离 | 每个任务的 stdout/stderr 独立记录到 `_logs/` |
| 环境变量 | 不继承宿主全部环境变量，仅传递白名单（PATH、HOME、项目相关） |

### 5.5 配置文件

```yaml
# ~/.focuspilot/executor.yaml
concurrent:
  max_concurrent: 1
  min_interval_seconds: 30
  max_daily_executions: 50

budget:
  daily_token_budget: 0          # 0 = 不限
  warning_threshold: 0.8
  hard_limit_action: pause       # pause / warn

security:
  allowed_directories:            # 允许执行的代码目录
    - ~/Workspace
    - ~/projects
  skip_permissions: false         # 全局默认不跳过权限
  task_timeout_minutes: 30
  env_whitelist:                  # 传递给子进程的环境变量白名单
    - PATH
    - HOME
    - SHELL
    - LANG

adapters:
  claude-code:
    binary: claude                # 二进制路径
    default_model: sonnet         # 默认模型
    extra_args: []
  codex:
    binary: codex
    default_model: null
    extra_args: []
```

---

## 6. Swift 侧本地功能分界

| 功能 | 走 OpenClaw？ | 原因 |
|------|:---:|------|
| 窗口管理 / App 切换 | 否 | AX API，只能本地 |
| 番茄钟 | 否 | 纯本地计时 |
| 快捷键 | 否 | Carbon API，只能本地 |
| 悬浮球交互 | 否 | 纯 UI 层 |
| 项目管理（CRUD/四模式） | **是** | focuspilot-project-engine MCP |
| Agent 调度（执行 Task） | **是** | focuspilot-executor MCP |
| Dashboard 数据 | **是** | Personal Assistant Agent |
| 对话面板 | **是** | OpenClaw Agent 对话 |
| 知识管道 | **是** | Personal Assistant Agent + Skill |
| 聚焦 Tab 数据 | **是** | 从 OpenClaw 拉取今日待办 |

Swift 侧通过 `URLSessionWebSocketTask` 连接 OpenClaw WebSocket RPC，封装为 `OpenClawBridge`（类似现有 `CoderBridgeService`）。

---

## 7. 文档更新清单

### 7.1 Editions.md 更新

| 位置 | 变更 |
|------|------|
| §1 版本总览 | 部署方式更新为 OpenClaw |
| §2.1 前新增 | 新增"统一技术底座"小节，说明共用 OpenClaw |
| §3 功能对比表 B 区 | "Engine 核心"→"OpenClaw 底座"，B1-B5 内容更新 |

### 7.2 PRD.md 更新

| 位置 | 变更 |
|------|------|
| §2 产品架构 | 架构图更新为 OpenClaw |
| §5 Agent Engine | 整节重写为"OpenClaw 集成 + 自建 MCP Server" |
| §6 macOS App 集成 | EngineManager → OpenClawBridge |
| §7 部署架构 | PyInstaller → launchd + npm |
| §8 V1 范围 | Engine 相关行更新 |
| §12 文件结构 | engine/ Python → mcp-servers/ + executor.yaml |

---

## 8. 省掉了什么

| 不再需要 | 原因 |
|---------|------|
| Python FastAPI Engine | OpenClaw Gateway 替代 |
| EngineManager（Swift 进程管理） | launchd 守护替代 |
| PyInstaller 打包进 .app | npm 安装，独立守护 |
| Swift↔Python 双进程通信 | 统一走 WebSocket RPC |
| 自建 WebSocket 服务 | OpenClaw 内置 |
| 自建 Scheduler | OpenClaw 内置 |
| 自建多渠道接入（飞书/微信） | OpenClaw 内置 20+ 渠道 |

---

## 9. 风险与缓解

| 风险 | 严重度 | 缓解 |
|------|--------|------|
| OpenClaw 项目年轻（2025-11 创建） | 低 | 社区极活跃（349K star），大厂赞助 |
| OpenClaw API 变动 | 中 | MCP Server 方式解耦，不改 OpenClaw 源码 |
| OpenClawKit（Swift SDK）不成熟 | 中 | 不用它，直接用原生 WebSocket |
| Node.js 依赖 | 低 | `openclaw onboard --install-daemon` 自动化安装 |
| Claude Code 封号风险 | 中 | 三层风控：频率限制 + 额度监控 + 环境隔离 |
| 本地内存增加 | 低 | OpenClaw ~100-200MB vs 原 Python ~80-150MB，可接受 |
