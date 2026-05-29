# AICrew 页面设计

> **状态**：可开发
> **更新**：2026-05-29
> **原型**：[00-layout-prototype.html](00-layout-prototype.html)
> **关联**：[PRD §3.4 Crew 数字团队](../PRD.md)

---

## 1. 定位

AICrew 是 AI Agent 团队的**管理中心**。用户面对的不是 Agent、MCP、Skill 等底层概念，而是一个可管理的“数字团队”。

一句话职责：AICrew 管**谁能做什么、能调用哪些工具、什么时候自动做事**。

参考 Multica 的 Runtime/Agent 配置模型后，AICrew 明确采用三层对象：

- `CrewMember`：面向用户的数字成员，承载角色、人设、职责、技能、授权和任务容量。
- `CrewRuntime`：成员背后的执行环境，承载本地/云端、Provider、CLI/daemon、心跳、模型发现和可见性。
- `CrewRun`：一次真实执行记录，承载动态 Task、配置快照、执行日志、统计指标和 Focus 项目定位。

**硬规则**：成员不是 Runtime；一个成员必须绑定一个 Runtime，Runtime 可以服务多个成员。AICrew 对用户仍保持“团队管理”隐喻，但不能把 Runtime 简化成一个不可解释的字符串，也不能把执行历史简化成不可追溯的一行状态。

### 与 Settings 的职责边界

| 维度 | AICrew | Settings |
|------|--------|----------|
| 管理对象 | Crew 成员、能力、MCP、常驻职责 | 全局偏好、默认成员、快捷键、主题 |
| 操作粒度 | 单个成员级配置 | 应用级默认值 |
| 典型问题 | “代码工程师能不能访问 GitHub？” | “默认派给哪个成员？” |

**硬规则**：AICrew 管成员能力；Settings 只引用 AICrew 的结果，不重复配置成员能力。

---

## 2. 侧边栏

侧边栏展示团队成员列表和运行概况。

```
┌─ AICrew ───────────────────────┐
│ [+]                             │
│ [搜索成员...]                    │
│                                 │
│ 团队成员                         │
│ ● 代码工程师          2          │
│   claude-code · 本地 · 空闲       │
│ ● 架构师              1          │
│   claude-code · 本地 · 执行中     │
│ ● 数据分析师          0          │
│   research-agent · 云端 · 未连接  │
│                                 │
│ 运行概况                         │
│ 执行中 1 / 30天成功率 85% / 待授权 2│
└─────────────────────────────────┘
```

成员行信息：

| 字段 | 说明 |
|------|------|
| 状态点 | 绿色空闲、黄色执行中、红色不可用 |
| 成员名 | 用户可见角色名 |
| Runtime | 如 `Claude Code · MacBook` / `Codex CLI · MacBook` / `Research Cloud` |
| 部署位置 | 本地 / 云端 |
| 计数 | 并发上限、当前可用执行槽或最近成功次数 |
| 统计摘要 | 最近 30 天运行次数、成功率、失败数，可折叠为短摘要 |

点击成员后，工作区切换到对应成员详情。

---

## 3. 工作区

工作区采用 Multica 风格的轻量三 Tab。默认先看状态和最近工作，配置只在需要时进入第二层。

1. `动态`
2. `配置`
3. `运行时`

`Tasks`、`指令`、`Skills`、`环境变化` 不再作为一级 Tab 常驻展示：Task 和记录留在动态页；Instructions、Skill、Runtime 绑定进入配置页；Env / Args / MCP JSON / 环境变化进入高级折叠区或运行记录详情。

### 3.1 动态

动态是成员详情的默认页，回答“这个成员最近做了什么、做得怎么样、能不能追溯”。

```
┌─ 代码工程师 / 动态 ─────────────────────────────────────┐
│ 当前  无进行中的工作                                      │
│ 这个智能体当前没有在跑任何 task。                         │
│                                                       │
│ 近 30 天 表现                                           │
│ 20 次运行 / 17 次成功 / 3 次失败 / 85% 成功 / 平均 1m57s │
│                                                       │
│ 最近工作 5 / 19                              [查看记录] │
│ ✓ # TES-12 任务执行间隔        49 分钟前 · 7m18s  ↗  ▤ │
│ ✓ # TES-11 调研核心功能以及竞品 52 分钟前 · 5m51s  ↗  ▤ │
│ ✓ # TES-9  二级测试issue      1 小时前 · 1m01s   ↗  ▤ │
└───────────────────────────────────────────────────────┘
```

动态页信息：

| 区块 | 内容 | 交互 |
|------|------|------|
| 当前工作 | 正在执行的 `CrewRun`，无任务时显示空状态 | 点击进入运行详情；点击 Focus 编号定位 Task |
| 近 30 天表现 | 运行次数、成功次数、失败次数、成功率、平均耗时、小趋势图 | 点击成功次数或成功率，进入记录列表并过滤 `status=success` |
| 最近工作 | 最近 5 条执行记录，显示 `Focus 编号 + Task 标题 + 时间 + 耗时 + 状态` | 点击整行进入运行详情；点击 `↗` 定位 Focus Task；点击 `▤` 查看日志记录 |

### 3.2 配置

配置页只保留高频字段：

- 角色名
- Runtime
- 默认 Skill
- 并发数
- Instructions

低频项进入 `高级配置` 折叠区：Skills / MCP、Env / Args、MCP JSON、环境变化。默认不展开，避免成员详情页变成配置后台。

### 3.3 运行时

运行配置页将 Runtime Pool 与执行器合并展示，参考 Settings / Runtimes 的本机与远程电脑结构：

```
┌─ 机器 ─────────────────┐ ┌─ MacBook-Pro-10.local ──────────────────────────┐
│ 搜索机器...             │ │ 本地 · 这台机器 · 在线 · daemon 019e6da2        │
│ 全部 1  在线 1  异常 0  │ │ [View logs] [Restart] [Stop]                  │
│                         │ │                                                │
│ 本机                    │ │ Runtime        健康度  智能体  工作负载  CLI     │
│ ● MacBook-Pro-10.local  │ │ Claude         在线    代码工程师  空闲   0.3.11 │
│                         │ │ Codex          在线    -          空闲   0.3.11 │
│ 远程电脑                │ │ Cursor         在线    -          空闲   0.3.11 │
│ ○ remote-dev-01         │ │ Gemini         在线    -          空闲   0.3.11 │
└─────────────────────────┘ └────────────────────────────────────────────────┘
```

运行配置规则：

- 左侧按 `本机 / 远程电脑 / 云端` 分组。
- V1 只自动检测本机配置；远程电脑来自手动添加、历史连接或远程 daemon 心跳。
- 点击机器后，右侧展示该机器上的执行器：Claude、Codex、Cursor、Gemini、Hermes、其他已注册 CLI。
- 执行器行展示健康度、绑定智能体、工作负载、最近 7 天费用或 token、CLI 版本、工作目录摘要。
- `View logs` 打开机器或执行器级日志；成员级记录仍通过动态页的 `查看记录` 进入。

运行时页必须展示本机电脑的最近内容：

- 最近运行：最近 3-5 条 CrewRun，显示成员、Task、耗时、状态。
- 最近日志：daemon / executor 摘要日志，`View logs` 打开完整记录。
- 执行器列表：Claude / Codex / Cursor / Gemini / Hermes，显示健康度、绑定成员、CLI 版本和负载。

### 3.4 运行记录详情

点击 `查看记录` 或最近工作中的 `▤` 打开运行记录详情。详情可作为右侧抽屉或全屏页，但结构固定：

```
┌─ Multica Helper                         已完成 │ ✕ ─┐
│ Claude Code · Claude (MacBook-Pro-10.local) · 7m18s │
│ 69 次工具调用 / 145 个事件 / Focus TES-12 / Skill dev-story │
│ 时间顺序  最新在前  筛选  全部复制                       │
│ █▁▁▂▃▁▁▁▂▁▁▃▁▁▁▁▁▂▁▁▁▂▁▁▁▁▁▃▁▁▁▁▁▁▁▂▁▁▁▁▁▁▁▁█ │
│ Grep   server/internal/handler/issue.go:2644...      #130 │
│ Read   .../handler/issue.go                          #131 │
│ Agent  Let me check the daemon-side polling mechanism. #135 │
│ Bash   Post analysis comment to issue                 #141 │
└────────────────────────────────────────────────────────────┘
```

记录详情顶部展示成员名、运行状态、Runtime、Focus Task、Skill、工作目录、开始时间、耗时、工具调用数、事件数和配置快照入口。事件时间线支持按类型筛选：Agent / Bash / Read / Grep / MCP / Error / Status。

### 3.5 团队运行状态

团队运行状态用于看整体健康度，不做深度配置：

- 团队成员数
- 执行中任务数
- Runtime 在线数量
- MCP 可用数量
- 常驻职责数量
- Runtime Pool：按本机、远程、云端分组展示执行环境
- 运行队列
- Agent 负载：区分可用性和工作负载
- MCP 健康状态

---

## 4. 核心交互

| 用户任务 | 操作路径 | 规则 |
|----------|----------|------|
| 查看成员详情 | 侧边栏点击成员 | 工作区切换到该成员配置 |
| 新建成员 | `[+]` 或 `新建成员` | V1 可展示配置草稿；云端执行预留 |
| 修改基本信息 | 成员详情直接编辑 | 自动保存，失败时保留本地草稿 |
| 绑定 Runtime | `Runtime 绑定` 区域选择 Runtime | 支持 `Mine / All` 筛选；私有 Runtime 不可被他人绑定 |
| 覆盖模型/推理强度 | 成员基本信息选择模型和 thinking level | 默认跟随 Runtime/CLI；只有 Runtime 声明支持时才显示可选项 |
| 配置 MCP Server | MCP 区域启用/停用、检测连接 | 待授权项显示 amber 状态，不静默失败 |
| 配置高级 Agent 参数 | 右侧 `Agent 配置` Tab 编辑 Instructions / Skills / Env / Args / MCP JSON | Env secret 默认隐藏；MCP JSON 必须是对象，空对象等价于清空 |
| 配置常驻职责 | 新增职责 -> 选择触发方式 -> 填条件和输出位置 | `event` / `cron` / `manual` 三类触发 |
| 查看动态 | 顶部切到 `动态` | 默认视图，展示当前工作、近 30 天表现和最近工作 |
| 查看运行记录 | 动态页 `查看记录` 或最近工作 `▤` | 打开运行记录详情，包含工具调用、事件、配置快照和原始日志 |
| 定位 Focus Task | 点击 Task 标题、Focus 编号或 `↗` | 切换到 Focus 页面，展开项目并选中对应节点 |
| 过滤成功记录 | 点击成功次数或成功率 | 打开记录列表并默认过滤 `status=success` |
| 查看 Skill 记录 | 点击 Skill 或 Skill 成功次数 | 打开记录列表并过滤对应 Skill |
| 查看运行时 | 顶部切到 `运行时` | 按本机 / 远程电脑 / 云端分组展示机器、执行器、最近运行和最近日志 |
| 查看团队运行状态 | 团队级 `运行状态` 入口 | 只看队列和健康状态，不编辑成员 |
| 删除成员 | 成员详情 `删除` | 系统成员需二次确认；有执行中任务时禁止删除 |

---

## 5. 状态与规则

### 5.1 Runtime 健康状态

| 状态 | 含义 | UI 表达 |
|------|------|---------|
| `online` | 心跳正常，可接收任务 | 绿色在线点 |
| `recently_lost` | 最近丢失心跳，短时间内可能恢复 | amber 提示，不自动派新任务 |
| `offline` | 超过恢复窗口，视为不可用 | 红色不可用 |
| `about_to_gc` | 离线时间接近清理阈值 | amber 风险提示 |

Runtime 详情至少展示 Provider、运行模式、本机/云端、可见性、Owner、daemon id、CLI 版本、last seen、已绑定成员数。

### 5.2 成员可用性与负载

AICrew 不把“在线”和“忙”混成一个状态。成员状态拆成两轴：

| 状态 | 含义 | 用户可操作 |
|------|------|------------|
| `availability: online` | Runtime 与关键授权可用 | 可编辑、可分配 |
| `availability: unstable` | Runtime recently lost 或关键能力降级 | 可编辑；派发前提示风险 |
| `availability: offline` | Runtime 或必要授权不可用 | 可编辑配置；不可分配任务 |
| `workload: idle` | 当前无任务 | 可分配 |
| `workload: queued` | 有排队任务等待执行槽 | 可继续排队 |
| `workload: working` | 正在执行任务 | 可编辑非运行关键字段；不可删除 |
| `draft` | 新建未保存完整 | 不参与任务分配 |
| `archived` | 已归档成员 | 不展示在默认成员列表，可恢复 |

### 5.3 MCP 状态

| 状态 | 含义 |
|------|------|
| `connected` | 已连接且可调用 |
| `authorized` | 已授权，等待具体调用 |
| `local` | 本地能力，跟随应用权限 |
| `pending_auth` | 需要用户授权 |
| `disabled` | 未启用 |

### 5.4 常驻职责状态

| 状态 | 含义 |
|------|------|
| `enabled` | 已启用，会按触发规则进入调度 |
| `draft` | 规则未完整或尚未启用 |
| `paused` | 用户暂停，不进入调度 |
| `failed` | 最近一次执行失败，需要处理 |

### 5.5 Agent 配置规则

- Instructions：成员长期指令，影响所有派发给该成员的任务。
- Skills：从本地 Skill 注册表选择；成员可有多个技能，默认 Skill 只影响快速派发。
- Env：只展示 key 数和 key 名；secret value 必须通过 Reveal 动作显式显示，关闭页面后重新隐藏。
- Args：展示为参数行，提交前转换为 argv；不能用字符串拼接执行 shell。
- MCP JSON：只接受 JSON object；无权限查看 secret 时展示 `redacted` 状态，保存时不得覆盖不可见字段。

### 5.6 执行记录与配置快照规则

- 每次执行创建一个 `CrewRun`，运行结束后保留为历史记录。
- 每次执行开始时写入 `CrewRunConfigSnapshot`，包含动态 Task、Instructions、Skills、Env key、Args、MCP、Runtime、模型、推理强度和工作目录。
- 历史记录详情读取快照，不读取当前成员配置，避免后续配置修改污染历史解释。
- 最近工作默认展示 5 条，完整记录列表展示全部可检索历史。
- 成功率按用户选择的窗口计算，默认近 30 天：`success / (success + failed + cancelled)`；正在执行不进入分母。
- 失败数点击后过滤 `status=failed`；成功次数和成功率点击后过滤 `status=success`。
- 日志事件按顺序编号，支持折叠长 payload；原始 payload 存储为引用，列表只展示摘要。

### 5.7 本机与远程配置检测规则

- V1 只能自动检测本机所有可见配置，包括本机 Runtime、CLI 版本、daemon 心跳、可执行文件路径、工作目录摘要、Env key、Args 和本机 MCP 配置摘要。
- 远程电脑不由本机扫描磁盘；只展示远程 daemon 主动上报、用户手动添加、或历史连接留下的 Runtime 信息。
- 远程 Runtime 的 Env secret 与 MCP secret 永远不回传明文，只显示 key count、redacted 状态和授权状态。
- 云端 Runtime 在 V1 只保留分组和空状态，不提供真实执行。

### 5.8 V1 范围

V1 做：

- 预置 `代码工程师`
- 成员详情三 Tab：动态 / 配置 / 运行时
- Runtime Pool 与 Runtime 绑定选择器
- 运行时页：本机 / 远程电脑分组、执行器列表、最近运行、最近日志、日志入口
- Runtime 健康状态、心跳和已绑定成员数展示
- 模型覆盖、推理强度覆盖、并发数配置
- Instructions / Skills / Env / Args / MCP JSON 配置壳；低频项默认折叠
- MCP Server 列表、状态、授权提示
- 常驻职责编辑 UI
- 动态页：当前工作、近 30 天表现、最近工作、成功次数和成功率
- 运行记录详情：事件时间线、工具调用、配置快照、复制和筛选
- Task / Skill / 最近工作 / 成功记录到 Focus 项目的定位跳转
- 运行状态 / 执行历史展示
- Focus / Studio 可引用 Crew 成员

V1 暂不做：

- 真正的多云端成员执行
- 默认展示多个真实成员；架构师、数据库工程师、数据分析师只作为新建模板出现
- 远程电脑磁盘扫描
- 云端 Runtime 真实执行
- Runtime daemon 自动发现与模型实时同步（本机已注册 daemon 状态可展示）
- Runtime CLI 升级、删除和 GC 流程
- 多 Agent 自动选择
- 常驻职责后台定时调度
- 自定义头像上传
- MCP 市场或公开插件管理

---

## 6. 数据对象

```yaml
CrewRuntime:
  id: "rt_claude_macbook"
  name: "Claude Code · MacBook"
  provider: "claude-code"
  runtime_mode: "local"       # local | cloud
  visibility: "private"       # private | public
  owner_id: "user_bruce"
  daemon_id: "fp-local-01"
  launch_header: "claude --model ..."
  cli_version: "2.1.121"
  health: "online"            # online | recently_lost | offline | about_to_gc
  last_seen_at: "2026-05-28T14:21:00+08:00"
  supported_models:
    - "claude-sonnet-4.5"
  supports_thinking: true

CrewMember:
  id: "crew_code_engineer"
  name: "代码工程师"
  avatar: "💻"
  visibility: "workspace"     # private | workspace
  owner_id: "user_bruce"
  runtime_id: "rt_claude_macbook"
  runtime_mode: "local"        # local | cloud
  availability: "online"       # online | unstable | offline
  workload: "idle"             # idle | queued | working
  status: "active"             # active | draft | archived
  concurrency_limit: 2
  model: "claude-sonnet-4.5"   # empty means follow runtime/CLI
  thinking_level: "medium"     # empty means follow runtime/CLI
  default_skill: "dev-story"
  skill_ids:
    - "dev-story"
    - "code-review"
  specialties:
    - "Swift/AppKit"
    - "前端原型"
    - "测试修复"
  instructions: "负责 FocusPilot 代码实现、测试修复和提交说明。"
  custom_args:
    - "--dangerously-skip-permissions"
    - "--model claude-sonnet-4.5"
  has_custom_env: true
  custom_env_key_count: 2
  mcp_config_redacted: false
  mcp_config:
    mcpServers:
      filesystem:
        command: "mcp-server-filesystem"

  mcp_servers:
    - id: "filesystem"
      state: "connected"
      permission_scope: "current_project"
    - id: "github"
      state: "authorized"
      permission_scope: "repo"
    - id: "browser"
      state: "pending_auth"
      permission_scope: "manual"

  duties:
    - id: "duty_pr_review"
      trigger_type: "event"  # event | cron | manual
      trigger_condition: "github.pull_request.opened"
      scope: "current_project"
      output_target: "studio.review_stream"
      state: "enabled"

CrewRuntimeHost:
  id: "host_macbook_pro_10"
  name: "MacBook-Pro-10.local"
  host_kind: "local"          # local | remote | cloud
  is_this_machine: true
  health: "online"
  daemon_id: "019e6da2"
  daemon_version: "0.3.11"
  last_seen_at: "2026-05-29T19:13:00+08:00"
  executors:
    - runtime_id: "rt_claude_macbook"
      provider: "claude-code"
      cli_version: "0.3.11"
      workload: "idle"
      bound_member_ids:
        - "crew_code_engineer"

CrewRun:
  id: "run_tes12_20260529_1913"
  crew_member_id: "crew_code_engineer"
  runtime_id: "rt_claude_macbook"
  runtime_host_id: "host_macbook_pro_10"
  focus_project_id: "project_focuspilot"
  focus_task_id: "TES-12"
  focus_task_title: "任务执行间隔"
  skill_id: "dev-story"
  status: "success"          # running | success | failed | cancelled
  started_at: "2026-05-29T19:13:00+08:00"
  ended_at: "2026-05-29T19:20:18+08:00"
  duration_seconds: 438
  tool_call_count: 69
  event_count: 145
  config_snapshot_id: "snap_run_tes12"
  log_path: "{projects_dir}/_logs/runs/run_tes12_20260529_1913.jsonl"
  output_refs:
    - kind: "focus_comment"
      ref: "TES-12#comment-145"

CrewRunConfigSnapshot:
  id: "snap_run_tes12"
  run_id: "run_tes12_20260529_1913"
  dynamic_task: "分析任务执行间隔并发布评论"
  instructions:
    member: "负责 FocusPilot 代码实现、测试修复和提交说明。"
    project: "遵守 CLAUDE.md"
    task: "定位 TES-12 并输出结论"
  skill_ids:
    - "dev-story"
  env_keys:
    - "ANTHROPIC_API_KEY"
  env_changes:
    - key: "FOCUSPILOT_PROJECT"
      change: "added"
  runtime:
    host_kind: "local"
    host_name: "MacBook-Pro-10.local"
    provider: "claude-code"
    cli_version: "0.3.11"
  mcp_servers:
    - id: "filesystem"
      state: "connected"
  cwd: "/Users/bruce/Workspace/2-Code/01-work/FocusPilot"
  model: "claude-sonnet-4.5"
  thinking_level: "medium"

CrewRunEvent:
  id: "event_0135"
  run_id: "run_tes12_20260529_1913"
  seq: 135
  timestamp: "2026-05-29T19:18:00+08:00"
  type: "agent"              # agent | tool_call | tool_result | read | grep | bash | mcp | error | status
  title: "Let me check the daemon-side polling mechanism."
  summary: "Agent 说明下一步检查 daemon 轮询机制"
  payload_ref: "{projects_dir}/_logs/runs/run_tes12_20260529_1913/0135.json"
```

---

## 7. 术语

| 术语 | 含义 |
|------|------|
| Crew 成员 | 一个面向用户的 AI 角色配置 |
| Runtime | 成员背后的执行环境，如本机 Claude Code daemon 或云端 Research runtime |
| Runtime 绑定 | 把 Crew 成员连接到某个可用 Runtime 的配置关系 |
| Agent 配置 | Instructions、Skills、Env、Args、MCP JSON 等影响成员执行行为的高级配置 |
| MCP Server | 成员可调用的工具能力 |
| 常驻职责 | 按事件、时间或手动入口触发的自动任务 |
| 执行槽 | 成员当前可同时处理的任务容量 |
| CrewRun | 成员的一次执行记录，连接 Focus Task、Skill、Runtime、日志和配置快照 |
| 配置快照 | 某次运行开始时的实际配置副本，供历史记录追溯 |
| 运行配置 | 按本机 / 远程电脑 / 云端展示的 Runtime Host 与执行器状态 |

---

*待定项：无。*
