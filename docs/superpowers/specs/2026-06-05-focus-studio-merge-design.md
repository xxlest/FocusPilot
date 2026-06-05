# Focus + Studio 合并设计

> **状态**：设计完成，待实施
> **日期**：2026-06-05
> **前置**：Inbox + Projects 合并已完成（2026-06-04）
> **关联**：[03-focus.md](../../fp-ui/03-focus.md)、[04-studio.md](../../fp-ui/04-studio.md)、[PRD.md](../../PRD.md)

---

## 1. 目标

将 Focus（结构化行动工作台）和 Studio（项目级 AI 编程指挥台）合并为统一的 **Studio**——跨项目的 AI 工作台。

合并后的一级导航：

```
Home · Projects · Studio · Review · AICrew · Settings
```

6 项。原 Focus 和 Studio 共 2 项合并为 1 项。

### 1.1 为什么合并

Focus 和 Studio 的边界是人为的。真实用户路径是连续的：

> 看到 Task → 和 Agent 对话/执行 → 产出变更 → 审查 Diff → 更新状态 → 验收

这是同一个工作流的不同阶段，不应分成两个一级页面。

### 1.2 合并后的定位

~~Focus = 结构化行动工作台~~
~~Studio = 项目级 AI 编程指挥台~~

> **Studio = 跨项目的 AI 工作台**
>
> 承载"规划 → 执行 → 评估 → 交付"全链路。
> 用户在这里看到所有项目的任务全貌，也能下钻到具体项目与 Agent 对话、审查代码、交付成果。
> 不限于代码，任何需要 AI 协作的结构化任务都在这里完成。

### 1.3 三层模型

合并后的产品架构：

```
Projects  ──→  Studio  ──→  Review
记忆层          执行层        内化层
信息在哪里      怎么加工      如何内化
```

---

## 2. 侧边栏设计

侧边栏分两段：**全局视图**（跨项目筛选器）+ **项目列表**（按项目组织任务和对话）。不需要 Tab 切换，两段共存于同一个侧边栏。

```
┌─ 侧边栏 260px ─────────────────────┐
│                                      │
│  🔍 搜索任务和对话...                │
│                                      │
│  ── 全局视图 ──────────────────────  │
│  📅 今日聚焦        (3)              │
│  📆 本周计划        (8)              │
│  📋 本月计划       (12)              │
│  🌐 全局规划       (24)              │
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─  │
│  🤖 执行中          (2)              │
│  🔔 等我决策        (1)              │
│  📥 Triage          (3)              │
│                                      │
│  ── 项目 ──────────────────── [+]   │
│  ▾ 📂 FocusPilot                    │
│     📋 工作项 (5)              [+]  │
│     💬 对话   (3)              [+]  │
│     🔄 自动化 (2)                    │
│  ▸ 📂 PilotOne                      │
│  ▸ 📂 分布式系统学习                 │
│                                      │
│  [+ 添加项目]                        │
│                                      │
│  ── 自动化 ────────────── [▾ 折叠]  │
│  🔄 每日代码审查       ✅ 2h前       │
│  🔄 PR 自动检查       🔄 运行中      │
│                                      │
│  [⚙ 设置]                           │
└──────────────────────────────────────┘
```

### 2.1 全局视图筛选规则

继承原 Focus 侧边栏的筛选语义：

| 侧边栏选择 | 筛选条件 |
|-----------|---------|
| 今日聚焦 | schedule=today |
| 本周计划 | schedule=today\|week |
| 本月计划 | goal.month=当月 + 未关联目标中 schedule∈{today,week,month} |
| 全局规划 | 无筛选 |
| 执行中 | status=in_progress & execution_mode≠none |
| 等我决策 | status=in_evaluation \| (approval pending) |
| Triage | 自动化结果待处理 |

### 2.2 项目列表

每个项目展开后显示三个子节点：

- **📋 工作项**：该项目关联的 WorkItem 数量
- **💬 对话**：该项目的 Studio Session 数量
- **🔄 自动化**：该项目的 Automation 规则数量

项目列表与原 Studio 的 Workspace 列表合并。项目的添加/移除/置顶/右键菜单规则沿用原 Studio 的 Workspace 管理规则。

---

## 3. 主区域设计

主区域内容根据侧边栏选择动态切换。

### 3.1 场景 A：选中全局视图

显示跨项目的任务视图，顶部 Tab 切换三种展示模式：

```
┌─ 主区域 ──────────────────────────────────────────────────────┐
│                                                                │
│  今日聚焦                    [📐 规划]  [📋 看板]  [📄 列表]    │
│  ───────────────────────────────────────────────────────────── │
│                                                                │
│  （继承原 Focus 三视图能力：四级甘特 / 七态看板 / 全量列表）     │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

继承原 Focus 的筛选语义和三视图能力：
- 四级同构甘特（全局/月/周/日）
- 七态看板（backlog → done）
- 列表视图（多维排序和分组）
- 侧边栏全局视图筛选联动（合并后侧边栏还包含 Triage、Session、Automation 等项目级内容）

### 3.2 场景 B：选中某个项目

显示项目上下文，Tab 切换两个维度：

```
┌─ 主区域 ──────────────────────────────────────────────────────┐
│                                                                │
│  📂 FocusPilot                       [📋 工作项 | 💬 对话]      │
│  ───────────────────────────────────────────────────────────── │
│                                                                │
│  📋 工作项 Tab:                                                │
│    可切换视图：[看板] [列表]                                     │
│    该项目的 WorkItem 看板/列表（按项目自动过滤）                  │
│    [+ 新建任务]                                                 │
│                                                                │
│  💬 对话 Tab:                                                   │
│    Session 列表 → 点击进入对话执行视图                           │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

### 3.3 场景 C：进入对话（Session）

点击某个 Session 后进入对话执行视图——原 Studio 的核心体验：

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
│  │ 描述内容...    [↑ 发送]  │         │                       │
│  └──────────────────────────┘         │  📝 Diff Tab:          │
│  ┌─ 终端面板 ──────────────┐         │  （与原 Studio 一致）   │
│  │ T1✕│T2✕│[+]            │         │                       │
│  │ $ make build             │         │  📁 Git Tab:           │
│  └──────────────────────────┘         │  （Stage/Commit/Push）  │
└───────────────────────────────────────┴───────────────────────┘
```

右面板新增 **📋 任务 Tab**（与 Diff、Git 并列）：
- 显示当前项目的任务列表（紧凑模式）
- 点击任务 → 关联到当前 Session，上下文注入对话
- [+ 新建任务] → 自动关联当前项目 + 当前 Session

### 3.4 场景 D：打开 Task 详情

从任何视图点击 Task 后打开详情面板，与原 Focus 的 Task 详情页一致，增加关联对话区域：

```
┌─ Task 详情 ──────────────────────────────────────────────────┐
│  ← 返回    FP-002 看板状态模型实现           ● in_progress   │
│                                                               │
│  ┌─ 执行步骤进度条 ────────────────────────────────────────┐ │
│  │  ✅ ──── ✅ ──── ● ──── ○ ──── ○                       │ │
│  │  规划    确认    执行    评估    验收                     │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                               │
│  ┌─ Agent Live Card（运行中时显示）────────────────────────┐ │
│  │  🤖 代码工程师 · Running · 00:03:42                     │ │
│  │  > 正在修改 Models.swift...                             │ │
│  │  [停止]  [手动接管]  [查看 Transcript]                   │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                               │
│  [📄 规划 ✓] [⚡ 执行 ●] [📝 评估] [✅ 验收]                │
│  （Tab 内容区）                                               │
│                                                               │
│  ── 关联对话 ──────────────────────────────────              │
│  💬 重构 auth · ✳ Claude Code · 30min                       │
│  💬 Bug fix #12 · ⚡ Codex · 15min                           │
│  [+ 新建关联对话]                                             │
│                                                               │
│  ── 属性 ───────────────────────────────────────             │
│  状态 / 优先级 / Workspace / 归属项目 / 目标 / 执行方式       │
└───────────────────────────────────────────────────────────────┘
```

---

## 4. 执行模式简化

### 4.1 从 4 模式简化为 3 模式 + 2 开关

| 新模式 | 原模式 | 定位 | 执行模型 |
|-------|--------|------|---------|
| **无 Agent** | `none` | 普通任务，手动管理 | 不启动 Agent Runtime，不创建 ExecutionRun，但仍有 Workspace |
| **对话** | `manual` | 和 Agent 交互式协作 | 启动 dialog ExecutionRun，创建/绑定 primary Session |
| **自动** | `semi_auto` + `auto` | Agent 自主规划执行 | 启动 auto ExecutionRun，可绑定 primary Session 展示日志和交互 |

自动模式的两个开关：

| 开关 | 默认 | 开启 | 关闭 |
|------|------|------|------|
| 审批计划 | ✅ 开 | plan → 等用户批准 → execute | plan → 直接执行 |
| 启用评估 | ❌ 关 | execute → Evaluation Agent 审查 | execute → 直接验收 |

### 4.2 步骤流

```
无 Agent:     (无步骤) → 手动打勾 → done

对话:         dialog → (evaluation) → 验收

自动:
  审批开+评估关:  plan → 批准 → execute → 验收
  审批开+评估开:  plan → 批准 → execute → evaluation → 验收
  审批关+评估关:  plan → execute → 验收
  审批关+评估开:  plan → execute → evaluation → 验收
```

### 4.3 底层兼容

`execution_mode` 字段保持 `none | manual | semi_auto | auto`。用户面向的"自动"模式在底层映射为：

- 审批开 → `semi_auto`
- 审批关 → `auto`

### 4.4 不变的部分

- WorkItem 数据模型核心字段不变
- 7 态状态机不变（backlog → done）
- ExecutionRun 步骤链模型不变
- 评估系统（EvaluationReport / EvaluationCycle）不变
- 手动接管机制不变

---

## 5. Workspace 模型

### 5.1 核心契约

**每个 WorkItem 创建时必须有 `workspace_ref`**。`none` 模式不启动 Agent，但仍绑定 Workspace（用于存放笔记、附件、未来升级为对话/自动时无缝衔接）。

### 5.2 V1 两种 Workspace 类型

| 类型 | 路径 | 适用场景 | 产出交付 |
|------|------|---------|---------|
| `temporary` | `{focuspilot_root}/workspaces/{task_id}/` | 快速任务、无关联项目 | 用户手动取用或复制到项目 |
| `local_project` | 用户选定的 Project 目录 | 有明确归属项目 | Studio Diff 审查 → Stage → Commit → Push |

V2 预留：`remote_git`（clone Git repo 到临时目录，产出以 PR 交付）。

### 5.3 默认策略

| 场景 | 默认 Workspace |
|------|---------------|
| 创建任务时未选项目 | `temporary` |
| 创建任务时选了本地 Project | `local_project` |

### 5.4 延迟物化

创建 Task 时分配稳定路径（`workspace_ref.path`），但不立即创建目录：

```yaml
workspace_ref:
  type: temporary
  path: "{focuspilot_root}/workspaces/{task_id}/"
  materialized: false    # 目录尚未创建
```

首次写入附件、启动执行或用户打开目录时创建真实目录，`materialized` 变为 `true`。

### 5.5 WorkspaceWriteLease（写入租约）

Session 本身不占用 Workspace 写锁。只有当 Session 启动会写入文件、执行命令或进行 Git 操作的 Agent Runtime 时，才创建 ExecutionRun 并申请 WorkspaceWriteLease。

```
层次分离：
  Session = 交互容器（对话 UI），不占锁
  Agent Runtime = 启动执行、写文件、跑命令，占 lease
  ExecutionRun = 一次完整执行，持有 lease
  Workspace = 目录，被 lease 保护
```

**V1 硬规则**：
- 同一 `resolved_workdir` 同时只允许一个 active WorkspaceWriteLease
- 同一 ExecutionRun 内的 Primary Agent 与 Sub Agents 共享同一个 lease
- 纯对话 / 只读上下文读取：不占用写锁，多个 Session 可同时存在
- 启动 Agent 修改文件 / 执行命令 / Git 操作：必须申请写锁

启动执行时检查：如果该目录已有活跃 lease，弹出提示"该工作区正在被任务 [FP-XXX] 使用，请先完成或取消"。

```
Task
└── ExecutionRun（持有 WorkspaceWriteLease）
    └── Primary Agent
        ├── Sub Agent A  ← 共享同一个 lease
        ├── Sub Agent B
        └── Sub Agent C
并发上限和调度由 Agent 层管理，Workspace 层不关心
```

**Lease 生命周期**：

```yaml
WorkspaceWriteLease:
  lease_id: "lease_001"
  run_id: "run_abc123"               # 持有该 lease 的 ExecutionRun
  resolved_workdir: "/Users/bruce/Workspace/FocusPilot"
  status: active | released | orphaned
  acquired_at: "2026-06-05T10:00:00"
  heartbeat_at: "2026-06-05T10:05:00"  # Runtime 定期更新
  released_at: null
  expires_at: "2026-06-05T10:10:00"    # heartbeat 超时阈值
```

| 事件 | Lease 行为 |
|------|-----------|
| ExecutionRun completed / aborted | 自动释放（status → released） |
| Runtime 心跳超时（heartbeat_at + TTL < now） | 标记 orphaned |
| App 重启时扫描 | 扫描 active lease；心跳超时则标记 orphaned，并提示用户确认释放 |
| 用户强制释放 orphaned lease | 二次确认后释放，关联 Run 标记 aborted |

### 5.6 Project 与 Workspace 的关系

- `Project` = 资产归属实体（Projects 页面管理），一个 Project 有一个本地目录
- `Workspace` = 执行目录实体（WorkItem 的执行场所）
- V1：一个 Project 最多绑定一个 local workspace（= 项目目录本身）
- temporary workspace 可选关联 Project（通过 `project_id`），但不自动成为 Project 的 workspace
- temporary workspace 关联 Project 时，产物不自动写回项目目录；需显式操作（"归档到项目"/"复制到项目"）迁移
- 项目视图中 Workspace 类型和路径应可见，避免用户不清楚产物实际位置
- 侧边栏项目列表的"工作项"计数 = 该 `project_id` 下的 WorkItem 数，与 Workspace 类型无关

### 5.7 本地项目的脏检测

默认直接在项目目录执行（与 Claude Code / Cursor 一致）。启动执行时如果检测到未提交改动，弹出提示：

```
⚠️ 项目中有未提交的修改（3 个文件）
建议先提交或创建独立分支再启动执行。

[忽略继续]  [创建任务分支]  [取消]
```

"创建任务分支"：自动 `git checkout -b task/{task_id}`，执行完成后用户可合并回主分支。

### 5.8 临时 Workspace 生命周期

```
物化: 首次写入附件、启动执行或打开目录时创建真实目录（延迟物化，见 §5.4）
使用: Agent 在其中执行
完成: 任务 done 后目录保留
清理: done/cancelled 超过 30 天自动 GC
保护: 有未 push commit 或用户标记保留时不清理
复用: 同一任务重新启动时复用原目录
配置: Settings 可调 GC 天数和磁盘上限
```

### 5.9 数据模型

三层字段分离，UI 联动默认值但数据模型独立：

```yaml
WorkItem:
  # 执行目录（必填）
  workspace_ref:
    type: temporary | local_project       # V2 增加 remote_git
    path: "{focuspilot_root}/workspaces/FP-002/"
    materialized: false                   # 目录是否已创建（延迟物化）
    
  # 资产归属（可选）
  project_id: "proj_focuspilot"           # 关联 Projects 页面的项目
  
  # 规划归属（可选）
  goal_id: "FP-001-release"              # 关联目标树

  # 执行历史
  current_run_id: "run_abc123"            # 当前活跃 ExecutionRun（至多一个）
  run_history_ids: ["run_prev01"]         # 历史 ExecutionRun 列表（含旧 primary session 和 snapshot）

  # Session 关联
  primary_session_id: "session_abc"       # 当前 Run 的主对话（可为 null）
  related_session_ids: ["session_def"]    # 参考上下文对话（不推进状态）
```

ExecutionRun 启动时记录 workspace 快照：

```yaml
ExecutionRun:
  primary_agent_id: "agent_coder"         # 推进状态机的主 Agent
  primary_session_id: "session_abc"       # 主对话
  sub_agent_runs: []                      # V1 字段保留、默认空；V2 开始写入多 Agent 记录
  workspace_snapshot:
    resolved_workdir: "/Users/bruce/Workspace/FocusPilot"
    source_type: local_project
    base_commit: "3764760"                # Git 项目记录启动时的 commit
    branch: "task/FP-002"                 # 当前分支
    created_at: "2026-06-05T10:00:00"
```

---

## 6. Task / Session / ExecutionRun 关系

### 6.1 关系模型

```
Workspace (执行目录)
├── Session A: 💬 自由对话（无关联 Task）
├── Session B: 💬 Task 主对话（primary_session）
└── Session C: 💬 参考对话（related_context）

WorkItem (Task)
├── current_run_id ──→ ExecutionRun（一对一，同时只有一个活跃）
│   └── primary_agent_id + primary_session_id
├── related_sessions[]: Session C, Session D（参考上下文，不推进状态）
└── workspace_ref ──→ Workspace

ExecutionRun
├── primary_agent_id: "agent_coder"     ← 推进状态机的主 Agent
├── primary_session_id: "session_B"     ← 主对话
├── sub_agent_runs: []                  ← V1 字段保留、默认空；V2 开始写入多 Agent 记录
├── steps: [plan, approval, execute, evaluation, acceptance]
├── workspace_write_lease: active       ← 持有 Workspace 写入租约
└── workspace_snapshot: { resolved_workdir, base_commit, branch }
```

**硬规则**：
- 一个 Task 同时只有一个活跃 ExecutionRun（`current_run_id`）
- 一个 ExecutionRun 由一个 primary Agent 推进；Primary Agent 与 Sub Agents 共享同一个 WorkspaceWriteLease
- 同一 `resolved_workdir` 同时只允许一个 active WorkspaceWriteLease（§5.5）
- Session 本身不占锁，只有 Agent Runtime 写入时才通过 ExecutionRun 占锁
- Task 可有多个 `related_sessions[]` 作为参考上下文，但只有 `primary_session` 关联 ExecutionRun
- 对话模式：启动 dialog ExecutionRun，创建/绑定 primary Session
- 自动模式：启动 auto ExecutionRun，可绑定 primary Session 展示日志和交互
- **Run 完成/停止后的状态迁移**：`current_run_id` 的 Run → append `run_history_ids` → `current_run_id = null` → release WorkspaceWriteLease。如需保留最近一次 Run 供 UI 展示，通过 `run_history_ids[-1]` 反查，不让 `current_run_id` 承担历史含义

### 6.2 关联规则

- Session 创建时可选关联一个 Task（也可以不关联，自由对话）
- Task 详情底部显示"主对话"和"参考对话"列表
- Session 顶栏显示关联 Task 状态徽标

### 6.3 primary_session 转换规则

| 当前状态 | 操作 | 结果 |
|---------|------|------|
| Task 无 primary_session | 关联 Session | 设为 primary |
| Task 有 primary_session，无 active Run | 关联新 Session | 默认为 related；可右键"设为主对话"替换 |
| Task 有 primary_session，有 active Run | 关联新 Session | 只能成为 related；不允许替换 primary |
| Active Run 完成/停止后 | 替换 primary | 允许，旧 primary 降为 related，run_history_ids 记录旧 Run |

### 6.4 任务创建的双向规则

| 创建入口 | 行为 |
|---------|------|
| 全局视图 → 新建任务 | 选 Workspace + 可选归属项目 → 项目工作项 Tab 同步可见 |
| 项目工作项 Tab → 新建任务 | 自动关联当前项目 + 使用项目 Workspace → 全局视图同步可见 |
| 对话右面板 → 新建任务 | 自动关联当前项目 + 当前 Session → 双向可见 |
| Inbox → 转为工作项 | 选归属项目 → 同上 |

---

## 7. 创建 UI

### 7.1 新建任务弹窗

```
┌──── 新建工作项 ────────────────────────────────────┐
│                                                     │
│  标题: [                                        ]   │
│  描述: [                                        ]   │
│                                                     │
│  ── Workspace ────────────────────────────────────  │
│  (●) 临时目录      （自动创建，适合快速任务）          │
│  ( ) 本地项目      [选择项目... ▾]                    │
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

### 7.2 联动规则

- 选"本地项目"→ 自动填充 `project_id` 和 `workspace_ref`
- 选"临时目录"→ `project_id` 可选填，`workspace_ref` 自动生成
- 选"对话"或"自动"→ 必须确认 Agent
- 选"普通任务"→ Agent 配置区隐藏

---

## 8. 跨页面影响

### 8.1 文件变更清单

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `03-focus.md` | **归档** | 内容迁入新 Studio 规格，标注已合并 |
| `04-studio.md` | **重写** | 升级为合并后的完整 Studio 规格 |
| `00-layout.md` | 修改 | 活动栏 7→6 项，去掉 Focus |
| `00-layout-prototype.html` | 修改 | 导航、侧边栏、工作区全部合并 |
| `01-home.md` | 修改 | 跳转目标从 Focus 改为 Studio |
| `05-area-projects.md` | 修改 | 职责边界表更新 |
| `06-review.md` | 修改 | 职责边界表更新 |
| `08-settings.md` | 修改 | Focus 配置区合入 Studio |
| `FP-UI.md` | 修改 | 页面清单更新 |
| `Architecture.md` | **修改** | 新增 WorkspaceWriteLease / ExecutionRun 扩展字段（run_history_ids, sub_agent_runs）/ Workspace 模型；更新模块边界（Focus 模块合入 Studio） |
| `DesignGuide.md` | 检查/修改 | 确认 6 项导航、合并后 Studio 侧边栏结构、右面板 Tab（任务/Diff/Git）、Workspace 类型标识视觉规则 |
| `PRD.md` | 修改 | 两阶段模型、页面引用更新 |
| `CLAUDE.md` | 修改 | 进度表、页面列表更新 |

### 8.2 导航变更

```
Before (7 项):                After (6 项):
🏠 Home                      🏠 Home
📂 Projects                  📂 Projects
🎯 Focus      ← 移除         💻 Studio  ← 合并后
💻 Studio     ← 合并         🧠 Review
🧠 Review                    🤖 AICrew
🤖 AICrew                    ⚙️ Settings
⚙️ Settings
```

### 8.3 旧入口完整迁移表

| 旧入口 | 旧目标 | 新目标 |
|--------|--------|--------|
| Home 摘要 "今日待办" 点击 | Focus 看板，筛选今日 | Studio 全局视图，筛选今日 |
| Home 摘要 "本周待办" 点击 | Focus 看板，筛选本周 | Studio 全局视图，筛选本周 |
| Home 摘要 "全部 TODO" 点击 | Focus 列表，全量 | Studio 全局视图，列表 |
| Home 摘要 "执行中" 点击 | Focus 看板，筛选执行中 | Studio 全局视图，筛选执行中 |
| Home 对话中 `data-go="focus"` | Focus 页面 | Studio 页面 |
| AICrew 成员详情 → Tasks 列表 → 点击行 | Focus 看板，定位 Task | Studio 全局视图，定位 Task 并打开详情 |
| AICrew 成员详情 → 最近工作 → 外跳图标 | Focus Task 详情 | Studio Task 详情 |
| Review → "Focus 实践" 链接 | Focus 页面 | Studio 页面 |
| 原型 `data-page="focus"` | Focus page/side-view | Studio page/side-view（全局视图模式） |
| 原型 Focus 侧边栏筛选状态 | Focus 侧边栏 Scope | Studio 侧边栏全局视图段 |
| 原型 Focus 三视图 Tab 状态 | Focus 三视图切换 | Studio 全局视图三视图切换 |
| 键盘快捷键 ⌘3（原 Focus） | Focus 页面 | Studio 页面（pageOrder 调整后） |

---

## 9. 完整保留的能力

以下功能从 Focus 和 Studio 迁入合并后的 Studio，所有交互规则不变：

**从 Focus 迁入**：
- 四级同构甘特规划（全局/月/周/日）
- 七态看板（backlog → done）
- 列表视图（多维排序分组）
- Task 详情页全部 Tab（规划/执行/评估/验收/对话）
- Agent Live Card
- Task 创建弹窗（拆解/启动）
- 评估系统（EvaluationReport/EvaluationCycle）
- 空状态与错误状态

**从 Studio 迁入**：
- Session 的 Chat + Diff + Terminal + Git 操作
- Triage + Automations
- Workspace 管理（添加/移除/右键菜单）
- 新建 Session 弹窗（Agent 选择 + Runtime 可用性）
- 六区布局（侧边栏 + 顶栏 + 对话区 + 输入区 + 右面板 + 终端面板）

---

## 10. V2 预留

不在 V1 展示，仅作为内部或后续扩展：

- `remote_git` Workspace 类型
- Git worktree 并行隔离执行
- Cloud 执行模式（远程容器）
- Handoff（Worktree 变更迁移到主工作区）
- Computer Use / Appshot
- 内置浏览器
- Resume / Fork Session
- Pop-out Window

---

## 11. 术语更新

### 核心模型概念

| 术语 | 定义 |
|------|------|
| **Workspace / 工作区** | 执行目录实体，与 Project（资产归属）和 Goal（规划归属）独立 |
| **Project** | 资产归属实体（Projects 页面管理），拥有一个本地目录 |
| **Goal** | 规划归属实体（目标树节点），驱动甘特和时间维度 |
| **WorkItem / 工作项** | 统一工作项模型，原 Focus Task |
| **Session / 对话** | 交互容器（对话 UI），本身不占 Workspace 写锁 |
| **ExecutionRun** | 一次完整执行实例，持有 WorkspaceWriteLease，推进 Task 状态机 |
| **WorkspaceWriteLease** | Workspace 写入租约。Agent Runtime 写文件/跑命令/Git 操作时占用；V1 同一 workdir 只允许一个 active lease |
| **primary Session / 主对话** | 关联 ExecutionRun 的 Session，每个 Task 至多一个 |
| **related Sessions / 参考对话** | 仅作为上下文参考，不推进状态 |

### 旧术语迁移

| 旧术语 | 新术语 | 说明 |
|--------|--------|------|
| Focus | Studio（全局视图） | 看板/规划/列表作为 Studio 的全局视图存在 |
| Studio | Studio（项目对话） | 对话/Diff/终端作为 Studio 的项目视图存在 |
| 半自动 / 全自动 | 自动（审批开/关） | 合并为一种模式 + 开关 |
| AreaProjects | Projects | 已在前序合并中完成 |
| 远程 Git Workspace | remote_git | V2 预留，clone Git repo 到临时目录执行，产出以 PR 交付。不在 V1 UI 展示 |
