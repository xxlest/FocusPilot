# Studio 页面设计

> **页面名**：Studio（合并原 Focus + 原 Studio）
> **状态**：可开发
> **更新**：2026-06-05
> **原型**：[00-layout-prototype.html](00-layout-prototype.html)
> **参考**：[Codex App macOS 竞品调研](../竞品分析/Codex%20App%20macOS%20竞品调研.md)、[Codex UI 功能层次梳理](../竞品分析/Codex%20UI%20功能层次梳理.md)
> **设计决策**：[Focus + Studio 合并设计](../superpowers/specs/2026-06-05-focus-studio-merge-design.md)
> **历史**：原 Focus 页面（[03-focus.md](03-focus.md)）已合并至本页；原 Studio 旧版备份见 [04-studio-backup-v1.md](04-studio-backup-v1.md)
> **关联**：[PRD §3.1 任务执行（Agent 配置驱动）](../PRD.md)、[PRD §3.3 Task 双轴管理](../PRD.md)

---

## 1. 定位

Studio 是 FocusPilot 的**跨项目 AI 工作台**，承载"规划 → 执行 → 评估 → 交付"全链路。

用户在这里看到所有项目的任务全貌，也能下钻到具体项目与 Agent 对话、审查代码、交付成果。不限于代码，任何需要 AI 协作的结构化任务都在这里完成。

**三层模型中的位置**：

```
Projects  ──→  Studio  ──→  Review
记忆层          执行层        内化层
信息在哪里      怎么加工      如何内化
```

### 与其他页面的职责边界

| 页面 | 职责 | 与 Studio 的边界 |
|------|------|-----------------|
| **Home** | AI 对话入口（含自由聊天）+ 全局概览 | Home = 自由对话 + 摘要跳转；Studio = 项目级结构化执行 |
| **Projects** | 信息收集（Inbox）+ 项目资产沉淀 | Projects = 文件组织/编辑/知识管道；Studio = AI 驱动的任务执行和交付 |
| **Review** | 复习与内化中心 | Review = 记忆/费曼复述/统计；Studio = 执行和产出 |
| **AICrew** | Agent 团队管理（角色/能力/MCP） | AICrew 定义 Agent 成员；Studio 消费 Agent 成员 |

### 核心交互原则

1. **两种视角无缝切换**。全局视图看跨项目任务全貌，项目视图深入某个项目执行
2. **不打断**。高频导航不弹确认框，顶栏和侧边栏已充分标识当前上下文
3. **Session = 交互容器**。Session 本身不占 Workspace 写锁，只有 Agent Runtime 写入时通过 ExecutionRun 占锁
4. **审查再交付**。AI 产出的代码变更必须经过 Diff 审查

---

## 2. 数据模型

### 2.1 工作项（WorkItem）

统一工作项模型，支持任意层级嵌套。

```yaml
WorkItem:
  # ── 身份 ──
  id: "FP-002"
  title: "看板状态模型实现"
  item_type: task               # epic | story | task | subtask | group
  item_role: executable         # container | executable | hybrid

  # ── 树结构 ──
  parent_id: "FP-US01"
  children_ids: []

  # ── 看板维度 ──
  status: in_progress           # backlog|todo|in_progress|in_review|done|blocked|cancelled
  blocked_from_status: null     # blocked 解除后回到的来源状态
  priority: p0                  # p0|p1|p2
  source: area_project          # inbox|area_project|adhoc

  # ── 时间维度 ──
  scheduled_date: "2026-04-21"  # 计划执行日期
  due_date: "2026-04-25"        # 截止日期
  start_date: "2026-04-18"      # 开始日期（可选）
  schedule: week                # today|week|month|backlog（由 scheduled_date 派生，不持久化）

  # ── Workspace（必填）──
  workspace_ref:
    type: temporary | local_project | git_project
    path: "{focuspilot_root}/workspaces/FP-002/"
    materialized: false                # 延迟物化：首次写入/启动/打开时创建真实目录

  # ── 归属（独立于 Workspace）──
  project_id: "proj_focuspilot"        # 资产归属（可选）
  goal_id: "FP-001-release"           # 规划归属（可选）

  # ── 执行配置（无模式：行为由 Agent 配置隐式推导，见 §3.1）──
  agents:
    executor: "agent_coder"       # 执行 Agent，可空（空=手动卡片，不自动调度）
    evaluator: "agent_evaluator"  # 评估 Agent，可空（空=无评估）
    # planner / dialog 字段废弃（无模式后不再使用）；解码向后兼容忽略
  evaluation_max_rounds: 3        # 评估轮数上限 N（≥1 任意整数；UI 为数字步进器，逐次增减），仅 evaluator 非空时有效

  # ── 多 Agent 接力协调标记（K2，见 §3.3）──
  has_pending_input: false             # 用户回复时置 true，executor 取走后清零
  last_run_id: null                    # executor 最近完成的 Run；reviewer 判"有新结果"
  last_reviewed_run_id: null           # reviewer 已审过的 Run；≠last_run_id 则需 review
  review_round: 0                      # 已 review 轮次，对比 N 判是否继续 ping-pong

  # ── 调度子状态（卡片角标，见 §2.4）──
  run_substate: queued | working | waiting_local_directory | null

  # ── 执行环境（worktree 混合制，见 §3.3/§4；local_directory/temporary 不填）──
  worktree_path: "~/.focuspilot/wt/FP-002"
  worktree_branch: "task/FP-002"

  # ── 执行状态 ──
  current_run_id: null                 # 非空=正在跑（防重复派发，Issue×Agent 闸）；落审核中置 null
  run_history_ids: ["run_prev01"]      # 历史 ExecutionRun 列表（executor/reviewer 各 Run）

  # ── Session 关联 ──
  primary_session_id: "session_abc"    # 当前 Run 的主对话（可为 null）
  related_session_ids: ["session_def"] # 参考上下文对话（不推进状态）

  # ── 容器聚合（item_role=container|hybrid 时自动计算）──
  progress:
    completion: 40%
    health: on_track            # on_track|at_risk|off_track
    children_total: 5
    children_done: 2
  lifecycle: active             # active|paused|archived（容器节点使用）
```

### 2.2 item_role 规则

| 角色 | 含义 | 看板 | 执行步骤 |
|------|------|:----:|:--------:|
| `container` | 有 children，自身不可执行 | 不显示 | 无 |
| `executable` | 无 children，可执行 | 显示 | 有 |
| `hybrid` | 有 children 且自身也有 ExecutionRun | 显示 | 有 |

### 2.3 工作项层级与项目模式

```
Agile:  Epic → User Story → Task (→ Sub-task)
Flow:   Phase → Task (→ Sub-task)
Lite:   Task (→ Sub-task)
Free:   Group → ... → Task (→ Sub-task)
```

### 2.4 Task 状态机

```
创建 ──▶ backlog ──▶ todo ──▶ in_progress ⇄⇄⇄ in_review ──▶ done
        (待规划)    (🕐排队)   (⚡执行)        (等人回复)    (人拖入)
                                  ▲              │
                                  └── 人一回复 ──┘（回复=打回继续，自动再跑）

  任意状态 ──▶ blocked（外部依赖阻塞，解除回 blocked_from_status；触发细则见 §3.2）
  任意状态 ──▶ cancelled（终止，归档不在主甬道常驻）
```

**7 种状态**（Multica 标准 7 态）：backlog / todo / in_progress / **in_review** / done / blocked / cancelled。
看板主甬道展示其中 6 个操作状态，中文名称固定为：待规划 / 待办 / 进行中 / 审核中 / 已完成 / 已阻塞；`cancelled` 作为终止状态进入归档/历史，不在主看板常驻展示。

> **命名变更**：原 `in_evaluation` 重命名为 `in_review`——AI 评估接力在「进行中」内部进行（§3.4），该态真实语义是"人工审核/等回复"。中文名「审核中」不变。

**运行子状态 `run_substate`**（卡片角标，独立于 `status`，不新增看板列）：🕐 `queued`（等并发槽）/ ⚡ `working`（执行中）/ 🔒 `waiting_local_directory`（本地目录被同目录另一任务占用，仅 local_directory 任务）。

乒乓流转、自动调度触发、手动卡片、blocked 触发细则等**执行视角**见 §3.2/§3.3。

### 2.5 ExecutionRun

> 一个 ping-pong 区间含多个 Run：executor Run 与 reviewer Run 交替，在**同一执行环境**（git worktree / local_directory 路径锁）内跑；**槽按轮取还**；进入「审核中」时 `current_run_id=null`、释放槽，local_directory 路径锁保持到任务落定（§3.3）。

```yaml
ExecutionRun:
  id: "run_abc123"
  work_item_id: "FP-002"
  agent_role: executor          # executor | reviewer（区分两类自治 Run）
  status: running               # pending|running|paused|completed|aborted

  # Agent
  agent_id: "agent_coder"
  session_id: "session_abc"     # 该 Run 所在任务 session（上下文连续性载体）

  # Workspace 快照（启动时冻结）
  workspace_snapshot:
    resolved_workdir: "~/.focuspilot/wt/FP-002"   # git 项目=worktree 路径；local_directory=用户目录
    source_type: git_project    # git_project | local_directory | temporary
    isolation: worktree         # worktree | local_dir_path_lock | temp_dir
    base_commit: "3764760"
    branch: "task/FP-002"       # git 项目的任务分支
    created_at: "2026-06-05T10:00:00"

  # 并发占用（槽按轮取还；local_directory 路径锁任务级持有，见 §4.5）
  daemon_slot: held             # held | released
  agent_slot: held              # held | released
  local_dir_lock: null          # 仅 local_directory：held（任务级）| null
```

> **Run 完成迁移**：Run completed/aborted → append `run_history_ids` → 释放槽；若是 ping-pong 的收尾（落审核中）则 `current_run_id=null`（local_directory 路径锁保持到任务落定）。`mode` / `evaluation_enabled` / `steps`（plan/approval 四链）字段删除——无模式后由协调标记驱动接力。

如需展示最近一次 Run，通过 `run_history_ids[-1]` 反查（一场任务跨多个 executor/reviewer Run）。

### 2.6 StudioSession

```yaml
StudioSession:
  id: "session_abc"
  title: "重构 auth 模块"
  project_id: "proj_focuspilot"
  workdir: "/Users/bruce/.../FocusPilot"

  # Agent（创建时绑定，不可更改）
  crew_member_id: "crew_code_engineer"
  agent_display_snapshot:
    name: "代码工程师"
    icon: "🧑‍💻"
    specialty: "全栈开发、调试、重构、代码审查"
  runtime: claude_code          # claude_code | codex_cli | gemini_cli
  model: "claude-opus-4"

  status: active                # active | idle | done | ended
  entry_source: studio          # studio | home | quick_chat
  transcript_ref: "sessions/session_abc/transcript.jsonl"
  created_at: "2026-06-05T10:00:00"
  last_active_at: "2026-06-05T10:30:00"
```

### 2.7 AutomationRule / TriageItem

沿用原 Studio 定义，不变。

---

## 3. 执行模型（无模式化 + 单扫描器 + worktree 混合制）

> **设计来源**：[执行模型 spec](../superpowers/specs/2026-06-09-studio-execution-model-design.md)（已定稿）。本节取代原「三种模式 + 两个开关」「步骤流」「手动接管」。

每个任务都是"Agent 自动干活 + 人随时插话校准"的一场多轮对话。**不再有执行模式与开关**：配了执行 Agent 就自动调度，配了评估 Agent 就带评估接力。一个中央扫描器（每 3~5s）读任务协调标记判"该谁干" → 抢对应 Agent 并发槽 → 在该任务执行环境（git 项目用独立 worktree / 本地目录用路径锁原地执行）里跑。任务隔离靠 worktree（物理）或本地目录路径锁，不靠 app 级共享写锁。

### 3.1 创建任务的执行配置

创建任务不再选「执行模式」，只配置：

```
┌──── 新建任务 ──────────────────────────────┐
│  标题 / 描述 / Workspace                     │
│  执行 Agent:  [代码工程师 ▾]   ← 可留空      │
│  ☑ 开启自动评估                              │
│     评估 Agent: [质量审查员 ▾]              │
│     评估轮数:   [− 3 +]  数字步进器（≥1）    │
│  安排 / 优先级 / 归属目标（可选）            │
│           [创建]  [创建并放入待办]            │
└──────────────────────────────────────────────┘
```

执行行为由两项配置**隐式推导**（不再有 `execution_mode` 枚举）：

| 配置 | 取值 | 行为 |
|------|------|------|
| 执行 Agent | 已选 | 拖到「待办」即被自动调度执行 |
| 执行 Agent | 留空 | 纯手动卡片，不自动执行、靠人拖状态（吸收原「普通任务」，覆盖非 AI 事务） |
| 自动评估 | 关（无评估 Agent） | 执行后无评估关卡 |
| 自动评估 | 开（评估 Agent + 轮数 N） | 每轮执行后评估 Agent 自动审查、执行 Agent 据意见自动修复，至多 N 轮 |

**配置约束**：执行 Agent 留空 + 评估 Agent 非空 = 非法（UI 禁止）。
**创建按钮落点**：「创建」→「待规划」（不调度）；「创建并放入待办」→「待办」（进自动调度）。
**执行范围（V1）**：只执行被拖入「待办」的**当前节点自身**，**不递归**——含子节点的任务（`hybrid`）只跑自身、不连带跑子节点；纯容器（`container`）不展示、不入调度；递归执行为 V2（见 §15）。

### 3.2 看板状态机（执行视角）

> 状态枚举与流转图见 **§2.4**（数据视角，权威）。本节只写执行视角差异点。

- **乒乓**：`进行中 ⇄ 审核中`——自动执行（含评估接力）跑完一律落「审核中」等人；人**回复**即重新触发执行、回到「进行中」（抢到并发槽则进，槽满/路径锁被占则先排队）；人**满意**则拖到「已完成」。「审核中」是强制的人工确认关卡（必经站，非终点）。
- **卡片角标**（运行子状态 `run_substate`，不新增看板列）：🕐 `queued` 等并发槽 / ⚡ `working` 执行中 / 🔒 `waiting_local_directory` 本地目录被同目录另一任务占用。
- **调度行为**：仅扫 `todo / in_progress / in_review` 三态；`backlog`（规划区）/`done`/`blocked`/`cancelled` 不扫。手动卡片（无执行 Agent）任何状态都不进调度、不触发强制审核中、状态全人工拖动。
- **blocked 触发与恢复**：V1 仅人工标 blocked；标时写 `blocked_from_status`，进行中被标则当前 Run aborted、释放槽/路径锁；解除回到来源状态，回 `todo` 则重新入调度、不自动续跑旧 Run。

### 3.3 执行引擎

**单中央扫描器**：一个调度循环（间隔可配，Settings，默认 3~5s），扫到任务靠协调标记判"该谁干"（过滤谓词，非多层循环）；槽满则跳过、下次扫描重捞（隐式排队）。

**协调标记（多 Agent 接力命门）**：

| 字段 | 写者 | 用途 |
|------|------|------|
| `current_run_id` | 调度器 | 非空 = 正在跑 → 跳过（防重复派发，= Issue×Agent 闸） |
| `has_pending_input` | 用户回复时置 | 驱动"新需求再执行"；executor 取走后清零 |
| `last_run_id` / `last_reviewed_run_id` | executor / reviewer | 二者不等 = 有未 review 新结果 → reviewer 该上 |
| `review_round` vs `evaluation_max_rounds` | reviewer | 判 ping-pong 是否继续 |

**隔离：worktree 混合制**：

| Workspace 类型 | 隔离 | 并发 | 交付 |
|---|---|---|---|
| git 项目 | 独立 worktree（共享 bare repo 缓存建，分支 `task/{task_id}`） | 真并行 | push 分支 / PR |
| local_directory | 不建 worktree、原地执行 + 路径级互斥锁（等待态 `waiting_local_directory`） | 同目录串行 | 改动在用户工作副本 |
| temporary | 独立目录 | 并行 | 手动取用 |

- **local_directory 路径锁 = 任务级持有**：从首次执行持到任务离开执行流（落 `done`/`cancelled`/被拖出审核中），**审核中也不释放**（防同目录并发污染）；git/非 git 统一此规则、不做分支快照。escape hatch：拖出审核中即释放。
- WorkspaceWriteLease 不全退役，瘦身为 local_directory 路径锁；git worktree / temporary 无 app 级锁。

**三层并发闸 + 排序**：

| 层 | 字段（位置） | 作用 |
|---|---|---|
| Daemon 全局 | `daemon_max_concurrent_tasks`（Settings，默认 4） | 整机总并发（信号量） |
| Agent 级 | `max_concurrent_tasks`（AICrew，每 Agent，默认 1） | 单 Agent 并发 |
| Issue×Agent | 固定 1 | 同 Agent 同任务最多 1（= `current_run_id` 非空跳过） |

候选按 `priority DESC, created_at ASC` 取；槽满跳过、下轮重捞。

**派发与 ping-pong**：建/复用 worktree（git）或取路径锁（local_directory，若未持有）→ 在任务 session 内 resume 上下文（类 `claude -p --resume`）→ executor Run 执行 → 写 `last_run_id` → reviewer Run 接力评估 → 有意见 executor 再跑、通过/满 N 轮则落「审核中」。**槽按轮取还**（轮开始取、轮结束释放）；**审核中释放槽、local_directory 路径锁保持**。

**需求合并与新需求优先级**：多回复合并为一批一次执行（不真并行）；executor 跑到一半用户回复且配了评估 → 先走完当前 ping-pong 评估循环、落审核中，再由 `has_pending_input` 触发下一个全新 ping-pong（不插队进正在进行的评估轮）。

**重启对账**：CoderSession 不持久化（重启清空内存池）。启动时扫 `current_run_id != null` 的任务 → 进程已不在 → 清 `current_run_id`、标 Run aborted → 下轮重新派发；`git worktree prune` 清孤儿 worktree。

**对话跨 Run 连续性**：详情页多轮堆叠跨多个 Run（executor/reviewer），连续性靠 session / worktree 上下文，不靠 Run 边界；`run_history_ids` 记录每 Run，`current_run_id` 仅 ping-pong 进行中非空。

### 3.4 评估接力（reviewer 自治 Run）

评估不是 executor Run 内部子步骤，而是**独立评估 Agent 的独立 Run**，与 executor Run 在同一执行环境内交替：

```
executor Run 执行 → 写 last_run_id
   → reviewer Run 审查 → 写 last_reviewed_run_id、review_round++
        ├─ 有未解决意见 且 review_round < N → executor 接力修复 → …
        └─ 评估通过 或 review_round == N → 落「审核中」
```

- **`evaluation_max_rounds`（N，≥1）是自动修复上限，不是终点**。
- 评估通过（reviewer 判无未解决意见）→ 落「审核中」等人。
- 跑满 N 轮仍有意见 → executor 停止自动接力，带"未解决意见"落「审核中」，人二选一：回复/打回继续 或 直接拖「已完成」。永不丢弃、永不无限烧。
- 原「手动接管」降级为详情页**人工回复**通用能力（§7.4）：任何时候人回复一句即注入上下文、触发下一轮。

---

## 4. Workspace 模型

### 4.1 核心契约

**每个 WorkItem 创建时必须有 `workspace_ref`**。普通任务不启动 Agent，但仍绑定 Workspace。

### 4.2 V1 三种 Workspace 类型

| 类型 | 路径 | 隔离方式 | 并发 | 产出交付 |
|------|------|---------|------|---------|
| `temporary` | `{focuspilot_root}/workspaces/{task_id}/` | 独立目录 | 并行 | 用户手动取用或复制到项目 |
| `local_project`（= local_directory） | 用户选定的 Project 目录 | **不建 worktree、原地执行 + 路径级互斥锁**（等待态 `waiting_local_directory`） | 同目录**串行** | 改动在用户工作副本 → Studio Diff 审查 → Stage → Commit → Push |
| `git_project` | 独立 **worktree**（共享 bare repo 缓存建，分支 `task/{task_id}`） | worktree 物理隔离 | **真并行** | 在 worktree 执行 → Commit → Push → Create PR |

> **worktree 混合制**：git 项目用独立 worktree（真并行）；local_directory 原地干活、靠路径锁串行；temporary 独立目录。详见 §3.3、§4.5。

### 4.3 默认策略

| 场景 | 默认 Workspace |
|------|---------------|
| 创建任务时未选项目 | `temporary` |
| 创建任务时选了本地 Project | `local_project` |

### 4.4 延迟物化

创建 Task 时分配稳定路径，增加 `materialized: false`。首次写入附件、启动执行或打开目录时创建真实目录，`materialized` 变为 `true`。

### 4.5 local_directory 路径锁（原 WorkspaceWriteLease 瘦身）

worktree 化后，**WorkspaceWriteLease 不再是 app 级共享写锁**——git 项目用独立 worktree 物理隔离、temporary 用独立目录，都无锁。只有 **local_directory**（指向用户本机工作副本）因多任务共享同一目录，才需要**路径级互斥锁**。

**V1 硬规则**：
- 同一 local_directory 同时只允许一个任务持有路径锁（同目录串行，等待者显示 `waiting_local_directory`）。
- git worktree / temporary 无路径锁；纯对话 / 只读不占锁。

**路径锁生命周期 = 任务级持有**（关键，防并发污染）：
- 从首次执行持到**任务离开执行流**（落 `done` / `cancelled` / 被拖出审核中），**审核中也不释放**——否则同目录另一任务进来改文件、人回复续跑时工作副本已被污染。
- git / 非 git 本地目录统一此规则，**不做分支快照**。
- **escape hatch**：把任务拖出审核中，路径锁即释放。
- **重启对账**：App 重启内存池清空，扫 `current_run_id != null` 的任务 → 进程不在 → 清 `current_run_id`、标 Run aborted、释放锁；`git worktree prune` 清孤儿 worktree（见 §3.3）。

### 4.6 本地项目的脏检测（仅 local_directory）

> worktree（git 项目）在独立副本干活、不碰用户工作树，**无需脏检测**；本节仅 local_directory（原地执行）适用。

默认直接在项目目录执行。启动执行时如果检测到未提交改动，弹出提示：

```
⚠️ 项目中有未提交的修改（3 个文件）
建议先提交或创建独立分支再启动执行。

[忽略继续]  [创建任务分支]  [取消]
```

"创建任务分支"：自动 `git checkout -b task/{task_id}`。

### 4.7 临时 Workspace 生命周期

```
物化: 首次写入附件、启动执行或打开目录时创建真实目录（延迟物化）
使用: Agent 在其中执行
完成: 任务 done 后目录保留
清理: done/cancelled 超过 30 天自动 GC
保护: 有未 push commit 或用户标记保留时不清理
复用: 同一任务重新启动时复用原目录
配置: Settings 可调 GC 天数和磁盘上限
```

> **worktree 磁盘 GC**：git 项目的任务 worktree 复用本节策略（done/cancelled 超期清理 + 有未 push commit 保护），孤儿 worktree 用 `git worktree prune`（§3.3）。

### 4.8 Project 与 Workspace 的关系

- `Project` = 资产归属实体（Projects 页面管理），一个 Project 有一个本地目录
- `Workspace` = 执行目录实体（WorkItem 的执行场所）
- V1：一个 Project 最多绑定一个 local workspace（= 项目目录本身）
- temporary workspace 可选关联 Project（通过 `project_id`），产物不自动写回项目目录，需显式操作迁移
- 项目视图中 Workspace 类型和路径应可见

---

## 5. Task / Session / ExecutionRun 关系

### 5.1 关系模型

```
Workspace (执行目录)
├── Session A: 💬 自由对话（无关联 Task）
├── Session B: 💬 Task 主对话（primary_session）
└── Session C: 💬 参考对话（related_context）

WorkItem (Task)
├── current_run_id ──→ ExecutionRun（一对一，同时只有一个活跃）
│   └── primary_agent_id + primary_session_id
├── run_history_ids: [旧 Run]
├── related_sessions[]: 参考上下文
└── workspace_ref ──→ Workspace
```

**硬规则**：
- 一个 Task 同一时刻只有一个活跃 ExecutionRun（`current_run_id`）；一个 ping-pong 内 executor Run 与 reviewer Run **交替**（每轮一个 Run）
- 隔离靠 worktree（git 项目，物理）或 local_directory 路径锁（任务级持有，§4.5），不靠 app 级共享写锁
- Session 不占锁；对话上下文连续性靠 session / worktree，不靠 Run 边界
- Run 完成/停止后：append `run_history_ids` → 释放槽；落「审核中」时 `current_run_id = null`（local_directory 路径锁保持到任务落定）

### 5.2 primary_session 转换规则

| 当前状态 | 操作 | 结果 |
|---------|------|------|
| Task 无 primary_session | 关联 Session | 设为 primary |
| Task 有 primary，无 active Run | 关联新 Session | 默认 related；可右键"设为主对话"替换 |
| Task 有 primary，有 active Run | 关联新 Session | 只能成为 related；不允许替换 |
| Active Run 完成/停止后 | 替换 primary | 允许，旧 primary 降为 related |

### 5.3 任务创建的双向规则

| 创建入口 | 行为 |
|---------|------|
| 任务视图（看板展示）→ 新建任务 | 选 Workspace（临时 / 本地项目 / Git 远程）→ 对应 Workspace 项目视图同步可见 |
| 项目 Inspector 任务列表 → 新建任务 | 当前 Workspace 已确定；Workspace 配置灰色只读展示，不可修改 → 任务视图同步可见 |
| Session 右面板 → 新建任务 | 当前 Workspace 已确定；Workspace 配置灰色只读展示，不自动关联 Session |
| Inbox → 转为工作项 | 选归属项目 → 同上 |

---

## 6. 侧边栏

侧边栏顶部用 Tab 切换两种视角：`[📋 任务视图 | 📂 项目视图]`。同一时刻只显示一个 Tab 的内容，切换时侧边栏内容和主区域同步替换。`任务视图` 承载跨项目 WorkItem 的范围筛选与显示模式；`看板` 只作为任务显示模式出现，不再作为 Studio 顶层视角命名。

### 6.0 整体结构

```
┌─ 侧边栏 260px ─────────────────────┐
│  [📋 任务视图· | 📂 项目视图]        │  ← Tab 切换
├──────────────────────────────────────┤
│                                      │
│  ── 任务视图 Tab ──                  │
│  🔍 搜索任务...                      │
│  快捷视图                            │
│  📅 今日聚焦        (3)              │
│  📆 本周计划        (8)              │
│  📋 本月计划       (12)              │
│  🌐 全局规划       (24)              │
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─  │
│  🤖 执行中          (2)              │
│  🔔 等我决策        (1)              │
│  目标树                              │
│  ▸ FocusPilot 0.0.1  38%            │
│  来源                                │
│  📁 Projects (8)                     │
│  📥 Inbox 导入 (2)                   │
│                                      │
│  ── 项目视图 Tab ──                  │
│  🔍 搜索对话...                      │
│  📥 Triage          (3)              │
│  ── Workspace 项目 ───── [全部折叠] │
│  ▾ 📂 FocusPilot                    │
│     ✳ 重构 auth        3 分钟前     │
│     ⚡ Bug fix #12     15 分钟前    │
│     ✳ 代码审查         1 小时前     │
│     ... 展开显示                    │
│  ▸ 📂 PilotOne                      │
│  [+ 添加项目]                        │
│  ── 自动化 ────────────── [▾ 折叠]  │
│  🔄 每日代码审查       ✅ 2h前       │
│  🔄 PR 自动检查       🔄 运行中      │
│                                      │
│  [⚙ 设置]                           │
└──────────────────────────────────────┘
```

### 6.1 全局视图筛选规则

继承原 Focus 的筛选语义：

| 侧边栏选择 | 筛选条件 |
|-----------|---------|
| 今日聚焦 | schedule=today |
| 本周计划 | schedule=today\|week |
| 本月计划 | goal.month=当月 + 未关联目标中 schedule∈{today,week,month} |
| 全局规划 | 无筛选 |
| 执行中 | status=in_progress & 有执行 Agent（非手动卡片） |
| 等我决策 | status=in_review |
| Triage | 自动化结果待处理 |

### 6.2 Workspace 项目列表

项目视图中的列表以 Workspace 为实体，而不是只展示本地 Project。顶部提供类型筛选：
- **所有**
- **临时项目**：系统按 ID 在默认 Workspace 根目录下物化的临时目录
- **本地项目**：目录与 Project 项目保持一致
- **Git 远程项目**：远程 repo clone 到默认 Workspace 根目录下，以 Workspace ID 执行

`tmp-quick-chat` 是 V1 固定保留的快捷对话临时 Workspace。Home 自由对话和非 Studio 页面发起的右下角快捷对话默认归属到这里；它在项目视图中按临时项目展示，不单独新增一级入口。

每个 Workspace 展开后显示：
- **📋 工作项**：该 `workspace_id` 下的 WorkItem 数量
- **💬 对话**：该 Workspace 的 Studio Session 数量
- **🔄 自动化**：该 Workspace 的 Automation 规则数量

对话历史采用 Codex 风格折叠规则：
- 默认每个 Workspace 只展示最近 5 条 Session，按 `last_activity_at` 倒序排列
- 点击 Workspace 项目名称会折叠 / 展开该 Workspace 下的全部对话历史，折叠态使用 `▸`，展开态使用 `▾`
- 超过 5 条时，在第 5 条后显示低视觉权重的灰色小字 `展开显示`
- 点击 `展开显示` 后展示该 Workspace 的全部 Session，并立即切换为 `折叠显示`
- 点击 `折叠显示` 后恢复为最近 5 条
- Workspace 项目列表提供全局切换按钮：存在任一项目展开时显示 `全部折叠`；全部项目已折叠时显示 `全部展开`
- 点击 `全部折叠` → 折叠所有 Workspace 项目，不显示项目下的 Session 历史；点击 `全部展开` → 展开所有 Workspace 项目，并展示项目下全部 Session 历史
- 每条 Session 显示相对时间：分钟 → 小时 → 天 → 周 → 月

---

## 7. 主区域

### 7.1 场景 A：选中全局视图

显示跨项目的任务视图。左侧侧边栏决定计划范围和时间粒度，主区域顶部只保留一个视图模式下拉：执行视图（看板 / 泳道 / 列表）在上，规划视图（时间轴）在下；默认打开看板。

```
┌─ 主区域 ──────────────────────────────────────────────────────┐
│                                                                │
│  今日聚焦             [▦ 看板 ▾]   目标：全部 ▾  筛选 · 3 ▾    │
│  ───────────────────────────────────────────────────────────── │
│                                                                │
│  继承原 Focus 能力：看板 / 泳道 / 列表 + 时间轴展示            │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

**两条轴**：

- **计划范围**：由侧边栏 `今日聚焦 / 本周计划 / 本月计划 / 全局规划 / 执行中 / 等我决策 / 来源` 决定（时间范围按执行优先自上而下排列，今日聚焦置顶），**默认选中「今日聚焦」**，并保持 `今日聚焦 ⊂ 本周计划 ⊂ 本月计划 ⊂ 全局规划` 的包含语义
- **视图模式**：用单一下拉控件切换，默认 `▦ 看板`；菜单上方分组为 `执行视图`（`▦ 看板 / 田 泳道 / ☰ 列表`），下方分组为 `规划视图`（`▱ 时间轴`）；切换视图模式不改变当前计划范围
- **工具栏稳定性**：全局工具栏固定只含 `视图下拉 / 目标 / 筛选`，切换任意视图模式都不增减控件；不再设独立「新建 Task」按钮；分组控件不再挂在工具栏，改为内嵌到各视图自身头部（详见时间轴、泳道、列表），消除"切换视图时按钮布局突变"的突兀感
- **就地新建入口**：各视图均以 `+` 就地新建，且自动带入对应上下文：看板各状态列标题栏 `+`（预选该列状态）；泳道每个「分组×状态」单元格底部 `+`（hover 出现，预选该分组维度值 + 该状态）；列表每个分组头 `+`（预选该分组维度值）。点 `+` 创建时新建弹窗的「初始状态」自动预选，不再一律落 backlog
- **时间轴**：四级同构甘特（全局 月级 / 本月 周级 / 本周 天级 / 今日 小时级），用于目标树、长期排期和下钻；时间轴内容上方提供**内嵌头部分组控件**（`分组方式` 文字标签 + `▤ 按项目 / ▱ 按目标` 扁平下拉，**默认按项目**），按项目时以 Workspace/项目为行轴展示同一范围内任务；**按项目的每个项目行可点击三角折叠/展开**（折叠后仅留单行标题，隐藏该项目的甘特条）
- **顶部筛选**：`目标` 仍按 WorkItem `goal` 过滤；`筛选` 是组合过滤入口，一级栏目包含 `项目 / Agent / 优先级 / 标签 / 负责人 / 创建者`，每个栏目提供二级多选项，栏目内为 OR、栏目间为 AND，一级栏目显示已选数量，并同步作用于时间轴、看板、列表和泳道。菜单采用级联交互：左栏列出一级栏目，鼠标悬停某个一级栏目即在右栏展开其二级多选项（一次只展开当前悬停栏目，不一次性平铺全部），在右栏勾选具体条件。时间范围不在顶部重复出现，统一由左侧 `今日聚焦 / 本周计划 / 本月计划 / 全局规划` 等 Scope 控制
- **看板**：仅展示 executable/hybrid 角色 WorkItem，按 6 个主甬道分列（待规划 / 待办 / 进行中 / 审核中 / 已完成 / 已阻塞）；每张卡片底部最后一行显示所属 Workspace 名称；**每个状态列标题栏右侧提供 `+` 作为唯一新建入口**（列底部不再放「＋ 新建任务」、顶部也不再有「新建 Task」按钮，避免功能重复）；从某列的 `+` 创建时，新建弹窗的「初始状态」自动预选该列状态（如在「进行中」列点 `+` 即默认 in_progress），不再一律落 backlog；卡片可拖到其他状态列，drop 后只改变任务状态；看板视图无分组控件
- **列表**：表格化展示，表格上方提供**内嵌头部分组控件**（`分组方式` 文字标签 + `◉ 按状态 / ▱ 按目标 / ▤ 按项目 / ◈ 执行 Agent / ◎ 负责人` 扁平下拉，**默认按状态**，不再按目标/月份）；采用**单表格 + 单列头**：状态/标题/安排/优先级/负责人/WS/模式/项目/截止 列标题**只在表格最顶显示一次**，不在每个分组下重复（消除冗余）；分组以**整行标题**分隔，分组头可点击三角（已放大）折叠/展开，并在右侧提供 `+` 就地新建（带入该分组维度值）；按状态分组时保留空状态分组，便于直接在某状态下新建；**每个分组标题前提供勾选框**：勾选=该组全选、取消=该组取消全选、部分选中显示 indeterminate；**顶部列头行提供总全选框**（勾选=全部可见全选）；行首每行提供复选框，选中后顶部显示已选数量，并支持批量修改状态、优先级、负责人和删除
- **泳道**：参考 Multica 的**整行横幅**布局——顶部一行为状态列表头（待规划 / 待办 / 进行中 / 审核中 / 已完成 / 已阻塞，sticky），分组各自占**一整行横幅**（横跨所有状态列，含折叠箭头 + 名称 + 计数），横幅下方卡片按状态列排布；网格上方提供**内嵌头部分组控件**（`分组方式` 文字标签 + `▤ Workspace / ◉ 执行 Agent / ↳ 父级任务 / ◎ 负责人` 扁平下拉）；**点击整行横幅即可折叠/展开**该分组；横幅左侧提供**拖拽柄（⠿）可上下拖动调整分组顺序**（参考 Multica，自定义顺序按分组维度记忆，新分组按字母补在末尾）；每个「分组×状态」单元格底部 hover 出现 `+` 就地新建；卡片跨单元格拖拽时，Workspace 分组同步改变任务状态与 Workspace 归属，Agent / 父级任务 / 负责人分组分别同步对应字段与状态

详细规格继承自原 Focus 设计（见 [03-focus.md](03-focus.md) 历史参考 §6-§7）。

### 7.2 场景 B：选中某个 Workspace 项目（未进入 Session）

项目视图把三类 Workspace 统一当作可进入的项目实体：临时 Workspace、本地项目 Workspace、Git 远程 Workspace。主区域显示 Workspace 概览 + Session 历史列表，右侧 Inspector 显示该 Workspace 下的任务投影。

```
┌─ 主区域 ──────────────────────────────┬─ 右面板（可显隐）──────┐
│                                       │                       │
│  📁 FocusPilot         [📋 任务列表]  │  📋 Workspace 任务列表 │
│  ──────────────────────────────────── │  ──────────────────── │
│                                       │  ● FP-002 看板拖拽 P0  │
│  对话历史                              │  ○ FP-003 列表视图 P1  │
│  ┌─────────────────────────────────┐ │  ✓ FP-001 数据模型     │
│  │ ✳ 重构 auth        3 分钟前      │ │                       │
│  │ ⚡ Bug fix #12     15 分钟前     │ │  [+ 新建任务]          │
│  │ ✳ 代码审查         1 小时前      │ │                       │
│  │ ... 展开显示                     │ │                       │
│  └─────────────────────────────────┘ │  任务列表展示当前       │
│                                       │  workspace_id 下的     │
│  [+ 新建对话]                         │  WorkItem 投影         │
│                                       │                       │
└───────────────────────────────────────┴───────────────────────┘
```

**关键交互**：
- 主区域以 Session 历史列表为主，默认展示最近 5 条；超过 5 条通过 `展开显示 / 折叠显示` 切换
- 点击 Session 进入对话执行视图（场景 C），同时更新聊天区、Diff、Terminal、右侧 Inspector 和当前 Workspace 上下文
- 右面板通过顶栏 `[📋 任务列表]` 按钮可显隐
- 侧栏项目视图提供类型筛选：所有 / 临时项目 / 本地项目 / Git 远程项目
- 任务列表展示该 `workspace_id` 下的 WorkItem（从统一 workItems 数据源过滤），不按 Session 归属
- 点击任务 → 打开 Task 详情（场景 D）
- 在任务视图创建且绑定该 Workspace 的任务，同步出现在这里
- 在项目任务列表中新建任务，同步出现在任务视图的对应显示模式中
- 进入 Session 后，任务列表仍可通过按钮随时打开（与 Diff/Git Tab 并存）

### 7.3 场景 C：进入对话（Session）

点击某个 Session 后进入对话执行视图：

```
┌─ 顶栏 ────────────────────────────────────────────────────────┐
│  ← 📂 FocusPilot · 重构 auth · ✳ Claude Code                 │
│                                        [🔧▾] [🖥] [◨]        │
├─ 对话区 ──────────────────────────────┬─ 右面板 ──────────────┤
│                                       │ [📋 任务|📝 Diff|📁 Git]│
│  👤 帮我改动画参数                     │                       │
│  🤖 好的，修改中...                   │  📋 任务 Tab:           │
│     ~ KanbanDataSource.swift [Diff →] │  ● FP-002 看板拖拽 P0  │
│                                       │  ○ FP-003 列表视图 P1  │
│  ┌─ 输入区 ────────────────┐         │  ✓ FP-001 数据模型     │
│  │ 描述内容...    [↑ 发送]  │         │  [+ 新建任务]           │
│  └──────────────────────────┘         │                       │
│  ┌─ 终端面板 ──────────────┐         │  📝 Diff / 📁 Git Tab:  │
│  │ T1✕│T2✕│[+]            │         │  （与原 Studio 一致）   │
│  │ $ make build             │         │                       │
│  └──────────────────────────┘         │                       │
└───────────────────────────────────────┴───────────────────────┘
```

右面板新增 **📋 任务 Tab**（与 Diff、Git 并列）：
- 显示当前 Workspace 的任务列表（紧凑模式），任务归属仍是 Workspace/Project，不归属 Session
- 点击任务标题 → 打开任务详情
- 点击任务行的 `▶` → 将任务发送到当前 Session 排队执行，并把任务状态调整为执行中
- [+ 新建任务] → 自动关联当前 Workspace；Workspace 配置灰色只读展示，不可修改

### 7.4 场景 D：打开 Task 详情

从任何视图点击 Task 打开详情面板：

**详情页 = 自动执行驱动的多轮对话**（取代原"执行步骤进度条"）。Agent 一方自动跑、人随时插话；执行结果与评估结果按轮次从上往下堆叠，像聊天记录：

```
┌─ FP-002 看板状态模型实现                  ● in_review  ⚡ ┐
│  📄 任务描述（= 这场对话的开场）                            │
│     实现看板 6 态拖拽 + 状态持久化…                         │
│  ──────────────────────────────────────────────────────── │
│  🤖 代码工程师 · 自动执行            00:03:42  [Diff][日志] │  ← 入队/被拉起后第一个自动启动
│     修改 Models.swift…                                      │
│  🔍 质量审查员 · 评估   ⚠ 2 条意见…                        │  ← reviewer 独立接力
│  🤖 代码工程师 · 自动修复（第 2 轮）                        │
│  🔍 质量审查员 · 评估   ✓ 通过 → 落「审核中」              │
│  ──────────────────────────────────────────────────────── │
│  👤 你：blocked 回退逻辑再补边界                            │  ← 人工回复=触发下一轮
│  🤖 代码工程师 · 自动执行 …                                 │
│  ┌─ 追加指令（人工介入）────────────┐                      │
│  │ 输入…让 Agent 继续调整    [↑ 发送] │                      │
│  └───────────────────────────────────┘                     │
│  ── 关联对话 ── / ── 属性（状态/优先级/Workspace/目标）──   │
└────────────────────────────────────────────────────────────┘
```

**5 条规则**（详见 [执行模型 spec §3](../superpowers/specs/2026-06-09-studio-execution-model-design.md)）：
1. **任务进入「待办」（或被拖入「进行中」）、被扫描器首次拉起后**，第一个动作是 Agent 自动执行（走「创建」落「待规划」的任务不调度）。
2. 每轮 🤖 executor 执行后 🔍 reviewer 独立接力评估（配了评估 Agent 时），N 轮内自动来回。
3. **人回复 = 触发下一轮自动执行**（"打回继续修"和"人工回复"是同一个动作；原"手动接管"降级为此通用能力）。
4. 整页从上往下无限堆叠。
5. 回复时序分流：审核中回复 → 抢槽进「进行中」（槽满则排队）；进行中回复 → 置 `has_pending_input`，本轮 ping-pong 结束落审核中后再处理。

---

## 8. 评估系统（reviewer 自治 Run）

评估由**独立评估 Agent 的独立 Run**承担，与 executor Run 在同一执行环境内交替（§3.4），核心要点：

- **reviewer 输出结构化 pass/fail**（是否仍有未解决意见），驱动 ping-pong 是否继续——这区别于旧设计"只产意见、不判 pass/fail"。
- **N 轮内 executor 自动接力修复**：reviewer 有意见且 `review_round < N` → executor 自动再跑；不再"每轮修复由用户显式触发"。
- **跑满 N 轮仍有意见** → executor 停止自动接力，带未解决意见落「审核中」交人：采纳/打回继续（回复即触发）/ 直接拖「已完成」。
- severity（critical/important/nit）帮助用户排序，不自动阻断。
- `review_round` 记录已评估轮次，对比 `evaluation_max_rounds`（N）。

---

## 9. 创建流程

### 9.1 新建任务弹窗

```
┌──── 新建工作项 ────────────────────────────────────┐
│                                                     │
│  标题: [                                        ]   │
│  描述: [                                        ]   │
│                                                     │
│  ── Workspace ────────────────────────────────────  │
│  (●) 临时 Workspace  （自动创建，适合快速任务）        │
│  ( ) 本地项目        [选择项目... ▾]                  │
│  ( ) Git 项目        [git@github.com:xxx/xxx.git  ]  │
│                                                     │
│  安排: [本周 ▾]    优先级: [P1 ▾]                    │
│                                                     │
│  ── 执行方式 ─────────────────────────────────────  │
│  [✅ 普通任务]   [💬 对话]   [🤖 自动]               │
│                                                     │
│  选中"对话"时:                                      │
│  ┌──────────────────────────────────────────────┐  │
│  │ Agent: [代码工程师 ▾]                         │  │
│  └──────────────────────────────────────────────┘  │
│                                                     │
│  选中"自动"时:                                      │
│  ┌──────────────────────────────────────────────┐  │
│  │ Agent: [代码工程师 ▾]                         │  │
│  │ ☑ 执行前需要我批准计划                         │  │
│  │ ☐ 完成后启用 AI 评估                           │  │
│  └──────────────────────────────────────────────┘  │
│                                                     │
│  归属目标: [4月/FP 0.0.1 ▾]  （可选）                │
│                                                     │
│           [创建]  [创建并启动]                        │
└─────────────────────────────────────────────────────┘
```

### 9.2 联动规则

- 选"本地项目"→ 自动填充 `project_id` 和 `workspace_ref`
- 选"临时目录"→ 自动生成临时 `workspace_id`，目录物化到默认 Workspace 根目录下
- 选"Git 项目"→ clone 到默认 Workspace 根目录下，以 Git Workspace ID 执行
- 从项目上下文或 Session 右面板新建任务时，Workspace 已确定；Workspace 配置区灰色只读展示当前 Workspace，不可更改
- 选"对话"或"自动"→ 必须确认 Agent
- 选"普通任务"→ Agent 配置区隐藏

### 9.3 新建 Session（项目对话 Tab）

入口：项目 💬 对话子节点的 [+] 按钮、⌘N、右下角快捷对话助手。

选择 Agent 执行器 → 新建对话。沿用原 Studio 的 Session 创建流程（Agent 选择 + Runtime 可用性 + 自定义 Agent）。

快捷助手创建规则：
- 在 Studio 项目/Session 上下文中发送第一条消息 → 归属当前 Workspace
- 在 Home / Projects / Review / AICrew / Settings 中发送第一条消息 → 归属 `tmp-quick-chat`
- 点击 `+` 先进入标题为 `新对话` 的草稿态；发送首条消息后自动提取标题
- Agent 在首条消息发送时锁定；继续历史对话时不可切换 Agent；历史对话按 Workspace 分组，并可从快捷面板标题区下拉菜单切换

---

## 10. 对话区 / 输入区 / 终端面板

沿用原 Studio 设计（六区布局中的 C/D/F 区），不变：

- **对话区**：消息流 + 内嵌 Diff 卡片 + 终端输出卡片 + 审批卡片
- **输入区**：多行自适应，Enter 发送，Shift+Enter 换行
- **终端面板**：⌘J 切换，多 Tab 终端，工作目录跟随 Session

---

## 11. Inspector 面板（项目级 + Session 级）

Inspector 是右侧的可显隐面板。项目上下文和 Session 上下文复用同一套右侧面板能力，点击项目或对话时只切换 Inspector 的数据上下文，不能让项目级环境 / Diff / Git 能力在进入 Session 后消失。

### 11.1 项目级 Inspector

当选中项目但未进入具体 Session 时，Inspector 显示项目级信息：

```
[📋 任务 | 📁 环境 | 📝 Diff | 📁 Git]
```

| Tab | 内容 |
|-----|------|
| **📋 任务** | 当前 `workspace_id` 下的 WorkItem 列表（从统一 workItems 过滤），可点击进入详情，可新建任务 |
| **📁 环境** | Workspace 类型/路径、Git 分支、最近提交、未提交变更数、自动化状态。随项目切换动态更新 |
| **📝 Diff** | 项目工作目录的未提交变更预览（文件级红绿 diff）。随项目切换动态更新 |
| **📁 Git** | 分支/远程/变更文件列表 + Stage All/Revert All/Commit/Push/PR 操作按钮 |

Inspector 通过项目顶栏的 `◨ Inspector` 按钮可显隐。

### 11.2 Session 级 Inspector（右面板）

进入具体 Session 后，右面板切换为 Session 上下文，同时保留当前项目 Workspace 摘要：

```
[📋 任务 | 📁 环境 | 📝 Diff | 📁 Git]
```

| Tab | 内容 |
|-----|------|
| **📋 任务** | 当前 Workspace 的 WorkItem 列表（同项目级），任务不归属 Session；点击 `▶` 时投递到当前 Session 执行 |
| **📁 环境** | 当前 Session 所在项目 Workspace 摘要：项目、Session、路径、分支、未提交变更 |
| **📝 Diff** | 当前 Session 产生的代码变更，文件 Tab 切换，红绿 diff + inline 评论 |
| **📁 Git** | 当前 Session 的变更文件列表 + Stage/Revert/Commit/Push/PR |

### 11.3 📋 任务 Tab 详细规格

显示当前 Workspace 的 WorkItem 列表（紧凑模式）：
- 按状态分组（执行中 / 待办 / 已完成）
- 每行：执行箭头 + 状态点 + ID + 标题 + 优先级
- 点击标题 → 打开任务详情
- 点击 `▶` → 等同于在当前 Session 输入框发送该任务：追加到当前 Session 队列，任务状态改为执行中
- [+ 新建任务] → 自动关联当前 Workspace，Workspace 配置灰色只读展示

### 11.4 📝 Diff Tab / 📁 Git Tab

沿用原 Studio 的 Diff 审查 + Git 操作规则，包括：
- 红绿对比 Diff 视图 + inline 评论
- 变更文件列表 + Stage/Revert
- Commit / Push / Create PR
- Stage/Revert 安全规则（只操作当前 Session changed files）

---

## 12. Triage + Automations

沿用原 Studio 设计，不变。

- **Triage**：侧边栏全局视图段，收纳需要用户处理的自动化结果
- **Automations**：侧边栏底部可折叠区域 + 项目级自动化子节点

---

## 13. 空状态与错误状态

| 场景 | 空状态文案 | 引导操作 |
|------|-----------|---------|
| 无今日任务 | 今日无计划任务 | [从 Backlog 安排] [新建任务] |
| 无 Agent 执行中 | 当前没有 Agent 在运行 | [启动任务] |
| 看板全空 | 还没有工作项 | [新建任务] [从 Inbox 转入] |
| 列表全空 | 没有匹配的工作项 | [清除筛选] [新建任务] |
| 项目无对话 | 还没有对话 | [新建对话] |
| 项目无工作项 | 该项目没有工作项 | [新建任务] |
| 任务 Blocked | 任务被阻塞 | [查看阻塞原因] [解除阻塞] |
| 新建对话空状态 | Agent 名 + Runtime + 擅长领域 | 开始对话，描述你的需求 |

---

## 14. 快捷键

| 快捷键 | 功能 |
|--------|------|
| ⌘B | 切换左侧边栏显隐 |
| ⌘⇧B | 切换右面板显隐 |
| ⌘J | 切换终端面板显隐 |
| ⌘N | 新建对话（当前项目下） |
| ⌘↩ | Git 提交（右面板内） |

---

## 15. V2 预留

不在 V1 展示：
- **Handoff（Worktree 变更迁移到主工作区）**——V1 不需要：git 项目靠 PR 交付、local_directory 原地改，都无需把 worktree 分支合并回用户工作副本
- **容器节点递归自动执行**（PRD §3.1 拖父节点递归依次执行子任务）——V1 只执行当前节点自身（§3.1）
- Cloud 执行模式（远程容器）
- Computer Use / Appshot
- 内置浏览器
- Resume / Fork Session
- Pop-out Window
- 右面板文件编辑能力

> **已上移 V1**：Git worktree 并行隔离执行（git 项目，见 §3.3/§4）——原列为 V2，本期作为执行引擎基座纳入 V1。

---

## 16. 术语

### 核心模型概念

| 术语 | 定义 |
|------|------|
| **Workspace / 工作区** | 执行目录实体，与 Project（资产归属）和 Goal（规划归属）独立 |
| **Project** | 资产归属实体（Projects 页面管理） |
| **Goal** | 规划归属实体（目标树节点） |
| **WorkItem / 工作项** | 统一工作项模型 |
| **Session / 对话** | 交互容器（对话 UI），承载任务对话上下文连续性，本身不占锁 |
| **ExecutionRun** | 一次执行实例（executor 或 reviewer，`agent_role` 区分）；一场任务跨多个 Run |
| **执行环境隔离** | git 项目用独立 **worktree**（分支 `task/{id}`）；local_directory 用**路径级互斥锁**（任务级持有）；temporary 用独立目录 |
| **local_directory 路径锁** | 原 WorkspaceWriteLease 瘦身：仅 local_directory 场景，同目录串行，任务级持有到落定（§4.5） |
| **三层并发** | Daemon 全局 `daemon_max_concurrent_tasks` + Agent 级 `max_concurrent_tasks` + Issue×Agent=1（§3.3） |
| **primary Session / 主对话** | 关联 ExecutionRun 的 Session，每个 Task 至多一个 |
| **related Sessions / 参考对话** | 仅作为上下文参考，不推进状态 |
| **Git 项目 Workspace** | git 项目用独立 worktree 执行，产出以 Commit/Push/PR 交付 |
