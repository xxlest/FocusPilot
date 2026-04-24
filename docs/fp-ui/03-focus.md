# Focus 页面设计

> **状态**：设计中
> **更新**：2026-04-21
> **原型**：[03-workspace-prototype.html](03-workspace-prototype.html)
> **关联**：[PRD §3.1 两阶段模型](../PRD.md)、[PRD §3.3 Task 双轴管理](../PRD.md)

---

## 1. 定位

Focus 是 FocusPilot 的**结构化行动工作台**，承载"规划 → 执行 → 评估 → 验收"全链路。

- 规划层：从年度到每日的目标拆解，AI 辅助多轮对话
- 执行层：4 种执行模式 + 可选评估开关
- 验收层：用户最终验收，AI 不做 pass/fail 判定

**三个视图**：`[📐 规划]  [📋 看板]  [📄 列表]`

---

## 2. 数据模型

### 2.1 工作项（WorkItem）

统一工作项模型，支持任意层级嵌套。

```yaml
WorkItem:
  # ── 身份 ──
  id: "FP-002"
  title: "看板状态模型实现"
  item_type: task # epic | story | task | subtask | group
  item_role: executable # container | executable | hybrid

  # ── 树结构 ──
  parent_id: "FP-US01"
  children_ids: []

  # ── 看板维度 ──
  status: in_progress # backlog|todo|in_progress|in_evaluation|done|blocked|cancelled
  blocked_from_status: null # blocked 解除后回到的来源状态
  priority: p0 # p0|p1|p2
  source: area_project # inbox|area_project|adhoc
  goal_id: "Q2-04-WS" # 归属目标

  # ── 时间维度 ──
  scheduled_date: "2026-04-21" # 计划执行日期（驱动周视图/日视图定位）
  due_date: "2026-04-25" # 截止日期（驱动甘特条右端点）
  start_date: "2026-04-18" # 开始日期（驱动甘特条左端点，可选）
  schedule: week # 自动派生: today|week|month|backlog（由 scheduled_date 相对当前日期计算）

  # ── 执行配置 ──
  execution_mode: semi_auto # none|manual|semi_auto|auto
  evaluation_enabled: true # 评估开关
  agents:
    planner: "agent_architect" # semi_auto/auto 时使用
    executor: "agent_coder" # semi_auto/auto + 修复执行
    dialog: "agent_coder" # manual 时使用
    evaluator: "agent_evaluator" # evaluation_enabled=true 时使用
  current_run_id: "run_abc123" # 当前 ExecutionRun

  # ── 容器聚合（item_role=container|hybrid 时自动计算）──
  progress:
    completion: 40%
    health: on_track # on_track|at_risk|off_track
    children_total: 5
    children_done: 2
  lifecycle: active # active|paused|archived（容器节点使用）
```

### 2.2 item_role 规则

| 角色         | 含义                                |  看板  | 执行步骤 |
| ------------ | ----------------------------------- | :----: | :------: |
| `container`  | 有 children，自身不可执行           | 不显示 |    无    |
| `executable` | 无 children，可执行                 |  显示  |    有    |
| `hybrid`     | 有 children 且自身也有 ExecutionRun |  显示  |    有    |

典型场景：Task 执行中拆出 Sub-task → 变为 hybrid，自身 ExecutionRun 继续，同时聚合子任务进度。

### 2.3 工作项层级与项目模式

项目模式决定层级标签：

```
Agile:  Epic → User Story → Task (→ Sub-task)
Flow:   Phase → Task (→ Sub-task)
Lite:   Task (→ Sub-task)
Free:   Group → ... → Task (→ Sub-task)
```

核心规则：

- 只有 `executable` 或 `hybrid` 的节点才能出现在看板上、被分配 Agent、有执行模式
- 容器节点自动聚合 progress，有 lifecycle（active/paused/archived），不可直接执行
- 任何叶子都可以通过"拆解"变成容器或 hybrid

### 2.4 Task 状态机

```
创建 ──▶ backlog ──▶ todo ──▶ in_progress ──▶ in_evaluation ──▶ done
              │         │         │               │
              │         │         │               ├─ 采纳评估意见 ──▶ in_progress（修复）
              │         │         │               ├─ 忽略并完成 ──▶ done
              │         │         │               └─ 手动接管 ──▶ in_progress（dialog）
              │         │         │
              │         │         └──▶ blocked（外部依赖阻塞）
              │         │                 └─ 解除 ──▶ blocked_from_status（回到阻塞前状态）
              └─────────┴──── cancelled
```

**7 种状态**（Multica 标准 7 态）：backlog / todo / in_progress / in_evaluation / done / blocked / cancelled。

**V1 不设 `failed` 状态**：步骤失败在 ExecutionRun/Step 层记录，看板层映射为 `blocked` + 错误徽标（🔴），用户可手动接管或重试。步骤失败进入 blocked 时，`blocked_from_status` 写入失败前的状态（通常为 `in_progress`）。

**`blocked` 规则**：任意状态进入 blocked 时必须写入 `blocked_from_status`；解除后回到来源状态。例如 in_evaluation → blocked → 解除 → in_evaluation。

**进入 in_evaluation 的两种情况**：

1. Evaluation 完成，等用户决策（评估意见已产出）
2. 最终验收，等用户确认

**其余所有"进行中"状态**（规划中/等待批准/执行中/评估中/修复中）统一为 in_progress。

---

## 3. 执行模式

### 3.1 四种模式 + 评估开关

```
4 模式:  无执行器 | 手动 | 半自动 | 全自动
评估:    可选开关（手动/半自动/全自动均可启用）
```

| 模式        | 定位                                         | 需要 Agent | 评估可用 |
| ----------- | -------------------------------------------- | :--------: | :------: |
| `none`      | 普通待办，手动打勾完成                       |     ✗      |    ✗     |
| `manual`    | 用户全程指挥 Agent 对话协作                  |   ✓(1个)   |    ✓     |
| `semi_auto` | Agent 规划(多轮交互) → 用户确认 → Agent 执行 |  ✓(1-2个)  |    ✓     |
| `auto`      | Agent 自主规划+执行                          |  ✓(1-2个)  |    ✓     |

### 3.2 各模式步骤流

**无执行器**：

```
(无步骤) → 用户手动打勾 → done
```

**手动，评估关**：

```
dialog → 最终验收
```

**手动，评估开**：

```
dialog → 打包结果(ManualExecutionPackage) → evaluation → 用户决策 → 最终验收
```

**半自动，评估关**：

```
plan(交互式，必须多轮对话) → 批准规划 → execute → 最终验收
```

**半自动，评估开**：

```
plan(交互式) → 批准规划 → execute → evaluation → 用户决策 → 最终验收
```

**全自动，评估关**：

```
plan(自主，遇不确定按假设推进) → execute → 最终验收
```

**全自动，评估开**：

```
plan(自主) → execute → evaluation → 用户决策 → 最终验收
```

### 3.3 规划步骤的交互策略

| 模式   | 规划行为                                                       | interaction            |
| ------ | -------------------------------------------------------------- | ---------------------- |
| 半自动 | Agent 主导但**必须多轮对话**确认关键决策，用户不在线则暂停等待 | `interactive_required` |
| 全自动 | Agent 自主规划，遇到不确定按假设推进，事后告知用户             | `assumptions_allowed`  |

### 3.4 手动接管

任何模式执行中，用户都可点击"手动接管"：

- 当前 Run 暂停
- 打开 dialog Tab
- 注入当前全部上下文（plan.md、execution_log、evaluation_report、changed_files）
- 用户和 Agent 对话微调
- 完成后提交验收或标记 done

### 3.5 Settings 全局配置

```
Settings → Workspace
├── 默认执行模式: none
├── 默认启用评估: 否
├── 默认 Agent: 代码工程师
├── 默认评估 Agent: Evaluation Agent
└── Agent 并发数: 3
```

Task 级配置可覆盖全局默认值。

---

## 4. 评估（Evaluation）

### 4.1 核心定义

> Evaluation Agent 只产出评估意见（修改建议），不产出 pass/fail。
> 用户在 Evaluation 阶段查看建议，可以编辑建议后交给执行 Agent 处理，也可以忽略建议并直接标记完成。
> Evaluation cycle 可循环，但每一轮修复都必须由用户显式触发。
> severity（critical/important/nit）只帮助用户排序，不自动阻断流程。

### 4.2 Evaluation 步骤流程

```
execute/dialog 完成
     │
     ▼
evaluation 开始（Evaluation Agent 接收输入）
     │
     │  输入（半自动/全自动）:
     │    plan.md + execution_log + changed_files
     │
     │  输入（手动模式，ManualExecutionPackage）:
     │    task_description + acceptance_criteria +
     │    completion_summary + changed_artifacts +
     │    transcript_ref + user_notes
     │
     ▼
Evaluation Agent 产出 EvaluationReport（只读）
     │
     ▼
WorkItem.status → in_evaluation
用户三选一：

  [按建议处理]  [忽略建议并完成]  [手动接管]
```

### 4.3 用户三个选择

**按建议处理**：

1. 打开 EvaluationInstruction 编辑界面
2. 用户可编辑/筛选/补充建议内容
3. 确认后发送给 executor Agent
4. WorkItem.status → in_progress
5. 修复完成后再次进入 evaluation（新一轮 EvaluationCycle）
6. 每轮都由用户显式触发，不自动循环

**忽略建议并完成**：

- 如果存在 Critical/Important 建议，弹出二次确认
- 确认后 WorkItem.status → done
- 记录 `user_action: ignore_and_complete` + `ignored_report_id`

**手动接管**：

- WorkItem.status → in_progress
- 打开 dialog Tab，注入 evaluation_report 作为上下文
- 用户手动处理

### 4.4 手动模式的评估衔接

手动模式 dialog 完成后，底部按钮：

```
[✅ 标记完成]  [📤 提交评估]  [📤 提交最终验收]
```

点击"提交评估"：

1. 系统从对话记录中自动提取 ManualExecutionPackage
2. 弹出确认，用户可编辑摘要和附加备注
3. 发送给 Evaluation Agent
4. 进入标准 evaluation 流程

ManualExecutionPackage 结构：

```yaml
ManualExecutionPackage:
  task_description: (从 WorkItem)
  acceptance_criteria: (优先从 WorkItem.acceptance_criteria → 其次 plan.md → 用户提交时补充 → 可为空)
  completion_summary: (AI 从对话中自动摘要)
  changed_artifacts: (对话中产出的文件列表)
  transcript_ref: (对话记录路径)
  user_notes: (用户可选填写)
```

Evaluation Agent 主要审 package，transcript 作为补充参考。

### 4.5 评估数据模型

```yaml
EvaluationReport:
  id: "rr_001"
  run_id: "run_abc123"
  cycle_no: 1
  generated_by: "agent_evaluator"
  source_artifacts: ["plan.md", "execution.log", "changed_files"]
  findings:
    - id: "f1"
      severity: critical # critical|important|nit
      title: "状态转换缺少 blocked→todo 路径"
      rationale: "用户解除阻塞后无法回到 todo"
      suggested_change: "在 TaskStatus.validTransitions 中添加 blocked→todo"
      target_artifact: "Models.swift"
    - id: "f2"
      severity: important
      title: "拖拽动画帧率偏低"
      rationale: "NSAnimationContext 在大量行时性能不足"
      suggested_change: "替换为 CAAnimation"
      target_artifact: "KanbanDataSource.swift"
    - id: "f3"
      severity: nit
      title: "变量命名风格不一致"
      suggested_change: "统一使用 camelCase"
      target_artifact: "KanbanDataSource.swift"
  summary: "2 处需修改，1 处建议优化"
  readonly: true # 原始报告不可修改

EvaluationInstruction:
  id: "ri_001"
  report_id: "rr_001"
  cycle_no: 1
  edited_by: user
  selected_findings: ["f1", "f2"] # 引用 EvaluationReport.findings[].id
  instruction_text: "按建议修改，另外把动画时长改为 0.2s" # 用户补充指令
  created_at: "2026-04-19T10:30:00"

EvaluationCycle:
  cycle_no: 1
  report_id: "rr_001"
  instruction_id: "ri_001" # 用户编辑后的指令（可为 null）
  user_action: apply_instruction # pending|apply_instruction|ignore_and_complete|manual_takeover
  revision_run_ref: "step_index_5" # 修复执行的步骤引用
  completed_at: "2026-04-19T11:00:00"
```

### 4.6 修复由谁执行

| 来源模式 | 修复 Agent     | 说明         |
| -------- | -------------- | ------------ |
| 手动     | dialog Agent   | 回到对话继续 |
| 半自动   | executor Agent | 自动修复     |
| 全自动   | executor Agent | 自动修复     |

Evaluation Agent 不负责修复，只负责评估。用户可在 EvaluationInstruction 中临时改派 Agent。

---

## 5. 执行运行实例（ExecutionRun）

```yaml
ExecutionRun:
  id: "run_abc123"
  work_item_id: "FP-002"
  mode: semi_auto # manual|semi_auto|auto
  evaluation_enabled: true
  status: running # pending|running|paused|completed|aborted
  current_step_index: 3
  active_evaluation_cycle: 1 # 当前评估轮次

  agents:
    planner: "agent_architect"
    executor: "agent_coder"
    evaluator: "agent_evaluator"

  steps:
    - step_run_id: "step_plan"
      type: plan
      status: completed
      agent_id: "agent_architect"
      interaction: interactive_required
      artifacts:
        - { type: plan, path: "runs/run_abc123/plan.md" }
      transcript_ref: "runs/run_abc123/s0_transcript.jsonl"

    - step_run_id: "step_approval"
      type: approval
      status: completed
      user_action: approved
      comment: "方案可行，第 3 步用 NSTableView"

    - step_run_id: "step_exec"
      type: execute
      status: completed
      agent_id: "agent_coder"
      interaction: autonomous
      artifacts:
        - { type: execution_log, path: "runs/run_abc123/execution.log" }
        - {
            type: changed_files,
            data: ["Models.swift", "KanbanDataSource.swift"],
          }

    - step_run_id: "step_eval_c1"
      type: evaluation
      status: completed
      agent_id: "agent_evaluator"
      evaluation_cycle: 1
      artifacts:
        - { type: evaluation_report, ref: "rr_001" }

    # ── 用户采纳评估意见后，动态追加 revision step ──
    - step_run_id: "step_rev_c1"
      type: revision_execute
      status: completed
      agent_id: "agent_coder"
      evaluation_cycle: 1 # 对应哪轮评估
      instruction_id: "ri_001" # 对应哪份 EvaluationInstruction
      artifacts:
        - { type: execution_log, path: "runs/run_abc123/revision_c1.log" }
        - { type: changed_files, data: ["Models.swift"] }

    # ── 修复后再次评估 ──
    - step_run_id: "step_eval_c2"
      type: evaluation
      status: completed
      agent_id: "agent_evaluator"
      evaluation_cycle: 2
      artifacts:
        - { type: evaluation_report, ref: "rr_002" }

    - step_run_id: "step_acceptance"
      type: acceptance
      status: pending

  evaluation_cycles:
    - cycle_no: 1
      report_id: "rr_001"
      instruction_id: "ri_001"
      user_action: apply_instruction
      revision_step_run_id: "step_rev_c1" # 稳定引用，不依赖数组下标
      completed_at: "2026-04-19T10:30:00"
    - cycle_no: 2
      report_id: "rr_002"
      instruction_id: null
      user_action: pending # 等用户决策

  history:
    - { timestamp: "2026-04-19T09:00", event: "run_started" }
    - { timestamp: "2026-04-19T09:15", event: "plan_completed" }
    - { timestamp: "2026-04-19T09:16", event: "approval_approved" }
    - { timestamp: "2026-04-19T09:16", event: "execute_started" }
    - { timestamp: "2026-04-19T10:00", event: "execute_completed" }
    - { timestamp: "2026-04-19T10:00", event: "evaluation_started", cycle: 1 }
    - { timestamp: "2026-04-19T10:05", event: "evaluation_completed", cycle: 1 }
    - {
        timestamp: "2026-04-19T10:10",
        event: "user_apply_instruction",
        cycle: 1,
      }
    - {
        timestamp: "2026-04-19T10:10",
        event: "revision_execute_started",
        cycle: 1,
      }
    - {
        timestamp: "2026-04-19T10:25",
        event: "revision_execute_completed",
        cycle: 1,
      }
    - { timestamp: "2026-04-19T10:25", event: "evaluation_started", cycle: 2 }
    - { timestamp: "2026-04-19T10:30", event: "evaluation_completed", cycle: 2 }
```

### 状态映射

| 步骤状态                          | WorkItem.status   | 看板列                              |
| --------------------------------- | ----------------- | ----------------------------------- |
| plan 进行中                       | in_progress       | In Progress                         |
| approval 等待用户                 | in_progress       | In Progress（详情页显示"等待批准"） |
| execute 进行中                    | in_progress       | In Progress                         |
| dialog 进行中                     | in_progress       | In Progress                         |
| evaluation 进行中（Agent 评估中） | in_progress       | In Progress                         |
| evaluation 完成，等用户决策       | **in_evaluation** | **In Evaluation**                   |
| 用户采纳意见，revision_execute 中 | in_progress       | In Progress                         |
| 最终验收等待用户                  | **in_evaluation** | **In Evaluation**                   |
| 用户验收通过                      | done              | Done                                |
| 步骤失败（Run/Step 层）           | blocked           | Blocked（+ 🔴 错误徽标）            |

---

## 6. 页面布局

### 6.1 整体结构

```
┌─ 侧边栏（Scope 筛选器）─┬─ 主区域 ───────────────────────────┐
│                          │                                     │
│ 快捷视图                 │  [📐 规划]  [📋 看板]  [📄 列表]    │
│  全部任务  (12)          │                                     │
│  今日聚焦  (3)           │  视图内容（随侧边栏筛选联动）        │
│  本周计划  (7)           │                                     │
│  Agent 执行中 (2)        │                                     │
│                          │                                     │
│ 目标树                   │                                     │
│  Q2 FocusPilot 38%       │                                     │
│    4月 WS原型  40%       │                                     │
│    ...                   │                                     │
│                          │                                     │
│ 来源                     │                                     │
│  AreaProject (8)         │                                     │
│  Inbox 导入  (2)         │                                     │
│  临时创建    (2)         │                                     │
└──────────────────────────┴─────────────────────────────────────┘
```

### 6.2 侧边栏 = 全局 Scope 筛选器

侧边栏的每一项都是筛选条件，切换后**三个视图同步过滤**。三个区域可叠加筛选。顶部 filter 按钮与侧边栏双向同步。

| 侧边栏选择   | 筛选条件                                 |
| ------------ | ---------------------------------------- |
| 全部任务     | 无筛选                                   |
| 今日聚焦     | schedule=today                           |
| 本周计划     | schedule=today\|week                     |
| Agent 执行中 | status=in_progress & execution_mode≠none |
| 目标树某节点 | goal_id=选中目标及其子目标               |
| 来源项       | source=对应值                            |

---

## 7. 三个视图

### 7.1 规划视图

**根据侧边栏的时间粒度自动切换展示模式**：

| 侧边栏选择                          | 展示模式                    |
| ----------------------------------- | --------------------------- |
| 全部任务 / 目标树节点 / Agent执行中 | **模式 A：目标树 + 甘特图** |
| 本周计划                            | **模式 B：周规划**          |
| 今日聚焦                            | **模式 C：日规划**          |

#### 模式 A：目标树 + 甘特图

```
左侧：目标树                      │  右侧：甘特时间轴
                                  │
▾ Q2 FocusPilot 0.0.1             │  ▏Apr         ▏May        ▏Jun
  ● active  38% ON TRACK          │  ██████████████████████████████
  ▾ 4月 Workspace 原型             │  ████████████░│
    ● 看板模型   in_progress       │    ▓▓▓▓░░     │
    ○ Agent Pull todo              │       ▓▓▓░░░  │
  ▸ 5月 AI Crew                    │              │████████████░
```

- Goal 节点显示 lifecycle + health + progress
- Task 节点显示 status dot
- 甘特条颜色映射 status，Goal 条 = 子节点时间范围自动聚合
- 时间缩放随选中层级自动调整

#### 模式 B：周规划

```
┌─ 周一 4/14 ─┬─ 周二 4/15 ─┬─ 周三 4/16 ─┬─ 周四 4/17 ─┬─ 周五 ─┐
│             │             │             │             │        │
│ ● 看板模型  │ ○ Agent Pull│             │ ○ Terminal  │        │
│   P0 🤖     │   P1 🤖     │             │   P1 🖐     │        │
│   → 4月/WS  │   → 4月/WS  │             │   → 4月/WS  │        │
│             │             │             │             │        │
│ ○ 读《xx》  │             │ ○ 整理记录  │             │        │
└─────────────┴─────────────┴─────────────┴─────────────┴────────┘
```

- 每列 = 一天，卡片 = 当天的 Task
- 可拖拽卡片跨天调整 `scheduled_date`（`schedule` 由日期自动派生，不直接修改）

#### 模式 C：日规划

```
📅 2026-04-19 · 周六 · 3 项任务

┌─ 进行中 ──────────────────────────────────┐
│  ● 看板状态模型实现                         │
│    P0 · 🤖 代码工程师 · 执行中              │
│    → Q2/4月/Workspace 原型                 │
└────────────────────────────────────────────┘

┌─ 待执行 ──────────────────────────────────┐
│  ○ 读《Designing Data Apps》第 3 章        │
│    P2 · 🖐 手动 · → 知识沉淀              │
│                                            │
│  ○ 整理本周会议记录                         │
│    P2 · 无执行器 · 临时任务                 │
└────────────────────────────────────────────┘
```

- 按状态分组（进行中 → 待执行 → 已完成）
- 类似 Todoist 今日视图

### 7.2 看板视图

仅展示 `executable` 和 `hybrid` 角色的 WorkItem，按 Multica 状态分列。

```
backlog    │ todo       │ in_progress │ in_evaluation  │ done
───────────┼────────────┼─────────────┼────────────┼──────
卡片...    │ 卡片...    │ 卡片...     │ 卡片...    │ 卡片...
```

卡片信息：ID、标题、优先级、执行模式标签、归属目标、Agent。

执行模式标签视觉区分：

- `none`：无标签（最简洁）
- `manual`：🖐 手动
- `semi_auto`：🤖 半自动
- `auto`：🤖 全自动
- 启用评估时追加 📝 标记

blocked/cancelled 独立折叠区。

### 7.3 列表视图

全量表格化展示，支持多维排序和分组（按目标/状态/来源/优先级/执行模式）。支持多选批量操作。

---

## 8. Task 创建

### 8.1 创建入口

1. **顶部全局按钮**："+ 新建任务"
2. **看板 backlog/todo 列底部**："+ 新建"，创建后进入对应列状态（仅 backlog 和 todo 列提供新建入口，in_progress/in_evaluation/done 列不允许直接创建）
3. **规划视图日/周模式空白区**："+ 添加任务"，`scheduled_date` 自动设为对应日期（日视图=当天，周视图=对应日），`schedule` 自动派生

### 8.2 创建弹窗

```
┌──── 新建工作项 ────────────────────────────────────┐
│                                                     │
│  类型: [Task ▾]    父项: [无（顶层）▾]              │
│  标题: [                                        ]   │
│  描述: [                                        ]   │
│  安排: [本周 ▾]    优先级: [P1 ▾]                   │
│                                                     │
│  ── 执行模式 ────────────────────────────────────── │
│  [✅ 无]   [手动]   [半自动]   [全自动]              │
│                                                     │
│  选中"半自动"时:                                    │
│  ┌──────────────────────────────────────────────┐  │
│  │ 规划 Agent: [代码工程师 ▾]                    │  │
│  │ 执行 Agent: [代码工程师 ▾]                    │  │
│  │ ☐ 启用评估                                    │  │
│  │   └ 评估 Agent: [Evaluation Agent ▾]              │  │
│  └──────────────────────────────────────────────┘  │
│                                                     │
│  来源: [临时创建 ▾]  归属: [Q2/4月 ▾]               │
│                                                     │
│           [创建]  [创建并拆解]  [创建并启动]         │
└─────────────────────────────────────────────────────┘
```

- **创建**：仅创建 → backlog
- **创建并拆解**：Epic/US 通过 AI 对话拆分为子工作项（decompose）
- **创建并启动**：Task 启动 ExecutionRun 第一步

按钮显示规则：

- 创建 Epic/US/Group → 显示 [创建] 和 [创建并拆解]
- 创建 Task → 显示 [创建] 和 [创建并启动]
- execution_mode=none 时只显示 [创建]

### 8.3 拆解（Decompose）

拆解和规划是不同动作：

- **拆解**（decompose）：把一个大工作项分解为多个子工作项（产出 children）
- **规划**（plan）：把一个可执行 Task 细化为实现步骤（产出 plan.md）

两者都通过多轮对话完成，但 step type 不同。

---

## 9. Task 详情页

### 9.1 整体布局

```
┌─ 头部 ─────────────────────────────────────────────────┐
│  ← 返回    FP-002 看板状态模型实现        ● in_progress │
│                                                         │
│  ┌─ 执行步骤进度条 ───────────────────────────────────┐ │
│  │  ✅ ──── ✅ ──── ● ──── ○ ──── ○                   │ │
│  │  规划    确认    执行    评估    验收                 │ │
│  │  架构师   👤    工程师  Evaluation   👤                   │ │
│  └────────────────────────────────────────────────────┘ │
│                                                         │
├─ 左侧主区域 ─────────────────────┬─ 右侧属性栏 ────────┤
│                                  │                      │
│  [📄 规划 ✓]  [⚡ 执行 ●]  ...   │  状态/优先级/安排    │
│                                  │  归属目标/来源        │
│  （Tab 内容区）                   │  执行配置/评估开关    │
│                                  │  时间                 │
└──────────────────────────────────┴──────────────────────┘
```

### 9.2 进度条

根据执行模式和评估开关动态生成步骤：

```
半自动 + 评估开:   规划 → 确认 → 执行 → 评估 → 验收
全自动 + 评估关:   规划 → 执行 → 验收
手动 + 评估开:     对话 → 评估 → 验收
手动 + 评估关:     对话 → 验收
```

已完成步骤 ✅，当前步骤 ●，未来步骤 ○。

### 9.3 Tab 动态显示

Tab 根据执行模式显示，已完成的步骤产物始终可回看：

| 步骤       | Tab 标签 | 内容                                 |
| ---------- | -------- | ------------------------------------ |
| plan       | 📄 规划  | 规划对话区（多轮）+ plan.md 产物区   |
| approval   | 📋 确认  | 上一步产物展示 + 批准/退回/修改按钮  |
| execute    | ⚡ 执行  | 只读执行输出流 + 产出物列表          |
| dialog     | 🖐 对话  | 交互式对话窗口                       |
| evaluation | 📝 评估  | EvaluationReport 展示 + 三个操作按钮 |
| acceptance | ✅ 验收  | 全部产物汇总 + 最终确认按钮          |

当前步骤的 Tab 高亮显示 ●，已完成的 Tab 显示 ✓（可点击回看，只读）。

### 9.4 规划 Tab（plan）

规划是多轮对话过程，不是一键生成：

```
阶段 1 — 未开始:
  [▶ 开始规划]  [✍️ 手动编写 plan.md]

阶段 2 — 对话中:
  🤖 规划引擎提问...
  👤 用户回答...
  🤖 追问/提方案...
  👤 确认/修改...
  [输入消息...]  [发送]

阶段 3 — plan.md 生成完毕:
  对话记录（可折叠）
  plan.md 内嵌渲染
  [重新规划]  [新窗口打开]
```

### 9.5 评估 Tab（evaluation）

```
┌──── 📝 评估 Tab ────────────────────────────────────┐
│                                                      │
│  评估意见（Evaluation Agent · 第 1 轮）                   │
│                                                      │
│  ■ Critical: 状态转换缺少 blocked→todo               │
│    → 补充转换规则 (Models.swift)                     │
│                                                      │
│  ■ Important: 拖拽动画帧率偏低                       │
│    → 改用 CAAnimation (KanbanDataSource.swift)       │
│                                                      │
│  · Nit: 变量命名风格不一致                            │
│    → 统一使用 camelCase                              │
│                                                      │
│  [按建议处理]  [忽略建议并完成]  [手动接管]            │
│                                                      │
│  点击"按建议处理":                                    │
│  → 打开 EvaluationInstruction 编辑界面                   │
│  → 用户可勾选要处理的建议、编辑内容、补充指令          │
│  → 确认后发送给 executor Agent                       │
│                                                      │
│  点击"忽略建议并完成":                                │
│  → Critical/Important 存在时弹出二次确认              │
│  → 确认后直接 → done                                 │
└──────────────────────────────────────────────────────┘
```

---

## 10. 参考项目

| 项目                                             | 参考内容                                                                |
| ------------------------------------------------ | ----------------------------------------------------------------------- |
| [Multica](https://github.com/multica-ai/multica) | 看板状态模型（7 态）、Agent Task Queue（Pull 模式）、Workspace 数据模型 |
| [Plane](https://github.com/makeplane/plane)      | Home 页 Widget 设计、Stickies 便签、State Groups、Project 组织结构      |

---

## 11. V2 预留

> 未来可扩展为自定义执行管道（Pipeline），允许用户配置规划、执行、评估、人工卡点等步骤的任意组合，指定每步的 Agent 和交互策略。V1 先固定为系统预设的 4 种执行模式 + 评估开关，降低使用和实现复杂度。
