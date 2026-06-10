# Studio 执行模型重构设计

> **主题**：Studio 看板任务的执行模型（无模式化 + 单扫描器/worktree 混合制/三层并发 + 多 Agent 自治接力 + 对话式详情页）
> **状态**：设计定稿，待落地
> **日期**：2026-06-09
> **关联**：[04-studio.md §3 执行模式](../../fp-ui/04-studio.md)、[PRD §3.1 两阶段模型](../../PRD.md)
> **取代**：04-studio.md 原 §3「三种模式 + 两个开关」、§3.2 步骤流、§3.3 手动接管

---

## 1. 背景与动机

原设计把任务执行拆成「3 种用户模式（普通/对话/自动）+ 2 个开关（审批计划/启用评估）」，自动模式下还派生出 4 条步骤链。问题：

- **决策负担重**：用户创建任务时要在模式、开关之间做多次选择，违背产品「克制」准则。
- **概念重复**：「对话模式」与已有的 Session 自由对话能力重叠，是冗余选项。
- **缺自动调度**：任务靠「创建并启动」或手动点 `▶` 启动，`待办` 不会被自动拉起，无法做到"录入即自动执行"。

本设计把执行模型**彻底收敛为单一交互**：每个任务都是"Agent 自动干活 + 人随时插话校准"的一场多轮对话，由看板状态驱动自动调度，不再有模式与开关。

---

## 2. 核心模型

### 2.1 无模式：靠 Agent 配置隐式决定行为

创建任务时不再选「执行模式」，只配置：

```
┌──── 新建任务 ──────────────────────────────┐
│  标题: [                              ]      │
│  描述: [                              ]      │
│  Workspace:   [本地项目 ▾]                  │
│  执行 Agent:  [代码工程师 ▾]   ← 可留空      │
│  ☑ 开启自动评估                              │
│     评估 Agent: [质量审查员 ▾]              │
│     评估轮数:   [3 轮 ▾]   （最低 1 轮）     │
│  安排: [本周 ▾]   优先级: [P1 ▾]            │
│  归属目标: [4月/FP 0.0.1 ▾]  （可选）        │
│           [创建]  [创建并放入待办]            │
└──────────────────────────────────────────────┘
```

两个创建按钮的落点：**「创建」→「待规划」(`backlog`)**（暂存、不调度，可继续在描述里规划）；**「创建并放入待办」→「待办」(`todo`)**（直接进自动调度）。

执行行为由两项配置**隐式推导**，不再有 `execution_mode` 枚举：

| 配置 | 取值 | 推导出的行为 |
|------|------|------------|
| **执行 Agent** | 已选 | 拖到「待办」即被自动调度执行 |
| **执行 Agent** | 留空 | 纯手动卡片，不自动执行，靠人拖状态（覆盖非 AI 的线下事务，吸收原「普通任务」） |
| **自动评估** | 关 | 执行后无评估关卡 |
| **自动评估** | 开（选评估 Agent + 轮数） | 每轮执行后评估 Agent 自动审查，执行 Agent 据意见自动修复，循环至多 N 轮 |

### 2.2 双 Agent 角色

| 角色 | 职责 | 必填 |
|------|------|:----:|
| **执行 Agent** | 自主规划 + 执行任务，产出结果 | 否（留空 = 手动卡片） |
| **评估 Agent** | 审查执行 Agent 的产出，给出意见 | 否（不选 = 无评估） |

**配置约束**：

- **执行 Agent 留空 + 评估 Agent 非空 = 非法组合**，UI 禁止（无执行产出则评估无对象）。执行 Agent 留空时，评估配置区一并隐藏。

### 2.3 执行范围：只执行当前节点自身，不递归（V1）

嵌套树可以照常建，但执行**只针对被拖入「待办」的那个任务节点自身**的工作，与它在树里是否有子节点无关：

- **不递归**：拖一个含子节点的任务（`item_role = hybrid`，自身有 ExecutionRun）去执行，**只跑它自身的工作，不连带自动跑子节点**；子任务需各自单独拖入「待办」。
- **纯容器**（`item_role = container`，仅分组、无自身执行内容）本就不在看板展示（04-studio §2.2），不会被拖入调度。
- PRD §3.1 描述的「拖父节点 → 递归依次执行所有子任务」为 **V2 能力**，V1 不做。

---

## 3. 详情页 = 自动执行驱动的多轮对话

任务详情页本身就是一场对话，**Agent 一方是自动执行的**。节奏：Agent 自动跑 → 人回复 → Agent 又自动跑 → 人再回复 …

```
┌─ FP-002 看板状态模型实现 ────────────────────────────┐
│                                                        │
│ 📄 任务描述（= 这场对话的开场）                        │
│    实现看板 6 态拖拽 + 状态持久化…                     │
│ ──────────────────────────────────────────────────── │
│ 🤖 代码工程师 · 自动执行              00:03:42  ⚡     │  ← 入队/被拉起后
│    修改 Models.swift…  [Diff] [Transcript]            │     第一个自动启动
│ 🔍 质量审查员 · 评估                                   │  ← 配了评估 Agent
│    ⚠ 2 条意见：状态枚举缺 blocked 回退…              │     自动跟评估
│ 🤖 代码工程师 · 自动修复（第 2 轮）                   │  ← 评估循环
│ 🔍 质量审查员 · 评估  ✓ 通过                           │     N 轮内自动来回
│ ──────────────────────────────────────────────────── │
│ 👤 你：blocked 的回退逻辑再补一下边界情况              │  ← 人工回复
│ 🤖 代码工程师 · 自动执行                               │  ← 回复触发，
│    补充 blocked_from_status 边界…                      │     Agent 又自动跑
│ 🔍 质量审查员 · 评估  ✓ 通过                           │
│ ──────────────────────────────────────────────────── │
│ 👤 你：[输入…]                              [↑ 发送]   │  ← 继续聊 / 或拖到已完成
└────────────────────────────────────────────────────────┘
```

**规则**：

1. **任务进入「待办」（或被拖入「进行中」）、被扫描器首次拉起后**，第一个动作是 Agent 自动执行（不等人），开场白就是任务描述本身。（走「创建」落「待规划」的任务不调度，见 §2.1）
2. **每一轮 🤖 executor 执行后 🔍 reviewer 独立接力评估**：配了评估 Agent 时，executor Run 与 reviewer Run 交替（执行→评估→有意见再执行→再评估），在 N 轮内全自动来回，同一执行环境内（worktree / 路径锁，见 §5.5、§6）。
3. **人回复 = 触发下一轮自动执行**：人在对话里回一句话，就是"继续"的扳机，Agent 据此再自动跑一轮。"打回继续修"和"人工回复"是同一个动作。
4. **整页从上往下无限堆叠**：执行结果、评估结果、人工回复按时间顺序追加，像聊天记录。
5. **回复时序随状态分流**：
   - 任务在「审核中」（Agent 已停、等人）时回复 → 启动新一轮 ping-pong：抢 Agent 并发槽（local_directory 的路径锁在审核中一直由本任务持有、无需重抢，§5.5）；拿到槽则进「进行中」（⚡）；槽满则显示「🕐 正在排队中」，下次扫描重捞（与 §5.4/§5.5 一致）。
   - 任务在「进行中」（Agent 仍在跑）时回复 → 置 `has_pending_input`，**本轮 ping-pong 结束、落「审核中」后**再作为下一轮的输入处理（与聊天体验一致）。

---

## 4. 看板状态机

### 4.1 状态流转（"乒乓"模型）

```
  卡片角标（运行子状态，不是看板列）：
    扫描入队 → 🕐 正在排队中  ｜  Agent 执行中 → ⚡ 正在工作

  待规划 ──▶ 待办 ──▶ 进行中 ⇄⇄⇄ 审核中 ──▶ 已完成
 (规划区)  (🕐排队)  (⚡Agent跑)  (等你回复)  (你拖入)
                        ▲            │
                        └─ 人一回复 ─┘
                       （回复 = 打回继续，自动再跑）

  任意状态 ──▶ 已阻塞（外部依赖阻塞，解除后回来源状态）
  任意状态 ──▶ 已取消（cancelled，归档，不在主甬道常驻展示）
```

> 状态枚举沿用 04-studio §2.4 的 7 态（含 `cancelled`）。本图聚焦执行流转的 6 个操作状态，`cancelled` 走归档不在主甬道展示。
> **命名变更**：原 `in_evaluation` 重命名为 `in_review`——新模型里 AI 评估接力（reviewer Run）发生在「进行中」内部，该状态的真实语义是"人工审核/等回复"，旧名 `in_evaluation` 名不副实。中文名「审核中」不变。

### 4.2 各状态语义

| 状态 | 中文名 | 调度行为 | 说明 |
|------|--------|---------|------|
| `backlog` | 待规划 | **不扫描** | 规划区。任务有名称 + 描述，人（或多人对话）在描述里把目标需求规划丰富好，再拖到「待办」 |
| `todo` | 待办 | **拖入即扫描** | 调度器扫到 → 抢到并发槽（local_directory 还需路径锁）就进「进行中」；**槽满** → 停这里显示「🕐 正在排队中」（`queued`）；**local_directory 路径锁被同目录另一任务占用** → 显示「🔒 等待本地目录」（`waiting_local_directory`） |
| `in_progress` | 进行中 | 执行中 | executor↔reviewer ping-pong 在跑（同一 worktree / 路径锁内），显示「⚡ 正在工作」；落「审核中」时释放槽，**local_directory 路径锁保持到任务落定**（见 §5.5） |
| `in_review` | 审核中 | 等人回复 | 自动执行一轮跑完一律落这里。人**回复**→ 抢到并发槽则弹回「进行中」再跑、槽满则先排队（🕐，见 §3 规则 5）；人**满意**→ 拖到「已完成」 |
| `done` | 已完成 | — | 人工拖入确认。AI 产出必须经人审查再交付（删除原"验收开关"） |
| `blocked` | 已阻塞 | — | 外部依赖阻塞，解除后回 `blocked_from_status`（见 §4.4） |
| `cancelled` | 已取消 | — | 终止状态，进归档/历史，不在主甬道常驻展示 |

### 4.3 关键规则

- **「待规划」承担规划职能**：原"规划模式"砍掉，规划改为在「待规划」列由人/对话完成（丰富任务描述），无独立执行模式。
- **「待办」拖入即自动执行**：这是触发口**之一**；扫描器还会拉起被直接拖入「进行中」但未启动的任务、以及「审核中」收到新回复的任务（§5.1/§5.2）。
- **「审核中」是强制的人工确认关卡（必经站，非终点）**：**仅对配置了执行 Agent 的自动任务**——每轮自动执行跑完都落「审核中」等人；它会与「进行中」来回，真正的终点是「已完成」。删除原"是否需要验收"开关。
- **手动卡片（无执行 Agent）不进自动调度，也不触发强制审核中**：状态完全由人自由拖动（待规划 → 待办 → 进行中 → 已完成），无 Agent 执行、无「审核中」强制关卡、无运行子状态角标。
- **「进行中」⇄「审核中」可来回**：人在审核中回复即重新触发执行（抢到并发槽回到进行中，槽满则先排队，§3 规则 5）；满意则拖到已完成。
- **运行子状态做成卡片角标**（`正在排队中` / `正在工作`），不新增看板列，保持 6 列主甬道干净。

### 4.4 已阻塞（blocked）的触发与恢复

- **进入**：仅**人工**标记 blocked（V1 不做 Agent 自检自动阻塞）。执行 Agent 卡住时表现为评估循环耗尽 → 落「审核中」交人，由人判断是否标 blocked。
- **记录来源**：标 blocked 时写 `blocked_from_status`（通常是 `todo` 或 `in_review`）。若任务正在「进行中」被标 blocked，当前 ping-pong 的 Run 按 aborted 处理、释放槽/路径锁（见 §5.5）。
- **恢复**：解除阻塞 → 回到 `blocked_from_status`；若回到 `todo` 则重新进入自动调度队列，不自动续跑上一个 Run。

---

## 5. 执行引擎：单中央扫描器 + worktree 混合制 + 三层并发

**一句话总架构**：一个中央扫描器（每 3~5s）→ 读任务协调标记判"该谁干" → 抢对应 Agent 的并发槽 → 在该任务的执行环境（git 项目用独立 worktree / 本地目录用路径锁原地执行）里跑。**任务隔离靠 worktree（物理）或本地目录路径锁，不靠 app 级共享写锁**；这把前几轮"锁怎么持有/何时释放/会不会饿死"的纠结一次性消解。

### 5.1 单中央扫描器（K1）

- 一个调度循环，间隔可配（Settings，默认 3~5s）。
- **扫描范围（K4）：仅 `todo / in_progress / in_review` 三态**；`backlog / done / blocked / cancelled` 不扫。
- 无 executor 的手动卡片任何状态都跳过。
- **不维护显式队列**：扫到任务靠协调标记（§5.2）判"该谁干"——这是单循环里的**过滤谓词**，不是第二层循环。槽满则跳过、下次扫描重捞（隐式排队）。

### 5.2 协调标记（K2，单扫描器命门）

扫到任务后靠这些标记判"派给谁、还要不要继续"（落库见 §7.2）：

| 字段 | 写者 | 用途 |
|------|------|------|
| `current_run_id` | 调度器 | 非空 = 正在跑 → 跳过（防重复派发，= Issue×Agent 闸） |
| `has_pending_input` | 用户回复时置 | 驱动"新需求再执行"；executor 取走后清零 |
| `last_run_id` / `last_reviewed_run_id` | executor / reviewer | 二者不等 = 有未 review 的新结果 → reviewer 该上 |
| `review_round` vs `evaluation_max_rounds` | reviewer | 判 ping-pong 是否继续 |

判据：
- **executor 入队**：`has_pending_input == true`，或（新任务且无 `last_run_id`），或（reviewer 留下未解决意见且 `review_round < N`）。
- **reviewer 入队**：配了评估 Agent 且 `last_run_id != last_reviewed_run_id` 且 `review_round < N`。

### 5.3 隔离：worktree 混合制

| Workspace 类型 | 隔离方式 | 并发 | 交付 | Handoff |
|---|---|---|---|:---:|
| **git 项目** | 独立 worktree（共享 bare repo 缓存建，分支 `task/{task_id}`） | 真并行 | push 分支 / PR | 否（PR 即交付） |
| **local_directory** | **不建 worktree，原地执行** + 路径级互斥锁（等待态 `waiting_local_directory`） | 同目录**串行** | 改动在用户工作副本 | 否（原地） |
| **temporary** | 本就独立目录 | 并行 | 手动取用 | 否 |

- **local_directory 路径锁 = 任务级持有**（从首次执行到任务离开执行流，审核中也不释放，§5.5）；git / 非 git 本地目录统一此规则，**不做分支快照**。
- **WorkspaceWriteLease 不完全退役，而是"瘦身"为 local_directory 的路径锁**——只在本地目录场景存在；git worktree / temporary 无 app 级锁。
- **Handoff（worktree 变更合并回主工作区）仍留 V2**（04-studio §15）：git 项目靠 PR 交付、local_directory 原地改，V1 都不需要合并回工作副本。

### 5.4 三层并发闸 + 排序

| 层 | 字段（配置位置） | 作用 |
|---|---|---|
| **Daemon 全局** | `max_concurrent_tasks`（Settings，默认待定，量级 4~8） | 整机总并发（信号量） |
| **Agent 级** | `max_concurrent_tasks`（每 Agent，AICrew 定义） | 单 Agent 并发上限 |
| **Issue×Agent** | 固定 1 | 同 Agent 在同任务最多 1 个（= `current_run_id` 非空跳过） |

- **排序（P4）**：候选按 `priority DESC, created_at ASC` 确定性取，防高优先级被反复插队饿死。
- **槽满 → 跳过**，下次扫描重捞（隐式排队，无显式队列结构）。

### 5.5 派发与 ping-pong 接力

- **派发动作**：建/复用 worktree（git）或取路径锁（local_directory，若未持有）→ 在该任务 session 内 resume 上下文（类 `claude -p --resume`，上下文存于 worktree/session，与 Run 边界无关）→ 发给 Agent 执行。
- **槽与锁的释放粒度不对称**：
  - **并发槽（Daemon / Agent）：按轮取还**——轮开始取槽、轮结束释放；审核中（等人）不占槽。
  - **local_directory 路径锁：任务级持有**——从首次执行一直持到**任务离开执行流**（落 `done` / `cancelled` / 被拖出审核中），**审核中也不释放**。否则同目录另一任务进来改文件 → 你回复续跑时工作副本已被污染（git/非 git 本地目录同此风险，故统一持锁到落定，不做分支快照）。escape hatch：把任务拖出审核中，路径锁即释放。
  - **worktree（git 项目）：无 app 级锁**，天然无此问题。
- **不会饿死其他 Workspace**：路径锁只约束同一本地目录（本就只能串行），不影响别的 Workspace；worktree 场景更无锁。

调度流程：

```
中央扫描（todo/in_progress/in_review，有 executor）
  按 (priority DESC, created_at ASC) 取候选；current_run_id 非空 → 跳过
  抢 Daemon 槽 + Agent 槽 → 满则跳过、下轮重捞（🕐 正在排队中 / queued）
  建/复用 worktree（git）或取路径锁（local_directory，若未持有）
     └─ 路径锁被同目录另一任务占用 → 🔒 等待本地目录（waiting_local_directory）
  executor Run 执行（⚡ 正在工作）→ 写 last_run_id → 释放 executor 槽
  reviewer 判据命中（last_run_id≠last_reviewed_run_id 且 review_round<N）
    → 抢 reviewer 槽 → reviewer Run 审查 → 写 last_reviewed_run_id、review_round++
         ├─ 有意见 → executor 再跑
         └─ 通过 / review_round==N → 落 in_review（审核中）：释放槽；
            local_directory 路径锁继续持有，git worktree 无锁
```

### 5.6 需求合并与新需求优先级（K6 + H2）

- **合并（K6）**：用户一次/连续回复多条 → 合并为**一个需求批次、一次执行**，不是多线程并行跑同一任务。
- **新需求 vs 评估优先级（H2）**：executor 跑到一半用户回复（`has_pending_input=true`）且同时配了评估 → **先把当前 ping-pong 的评估循环走完、落「审核中」，再由 `has_pending_input` 触发下一个全新 ping-pong**。新需求不插队进正在进行的评估轮（否则 `review_round` 计数与 transcript 顺序错乱）。

### 5.7 重启对账（H1，单扫描器运维命门）

CoderSession 不持久化（项目约定，见 CLAUDE.md），App 重启后内存池清空。启动时必须对账：

- 扫所有 `current_run_id != null` 的任务 → 进程已不在 → 清 `current_run_id`、标 Run aborted → 让扫描器下轮重新派发。
- **prune 孤儿 worktree**（无对应活跃任务的 `wt/*`），复用 git 原生 `git worktree prune`。

### 5.8 对话跨 Run 连续性

- 详情页的多轮堆叠跨多个 ExecutionRun（executor Run 与 reviewer Run），连续性靠 **session / worktree 上下文**（类 `claude -p --resume`）维持，**不靠 Run 边界**。
- `run_history_ids` 记录每一个 Run；`current_run_id` 仅在 ping-pong 进行中非空，落「审核中」置 null。

---

## 6. 评估接力（reviewer 自治 Run）

评估不再是 executor Run 内部的子步骤，而是**独立评估 Agent 的独立 Run**，与 executor Run 在同一执行环境（git worktree / local_directory 路径锁，§5.3）内交替（K5）。

### 6.1 ping-pong 逻辑

```
executor Run 执行 → 写 last_run_id
   → reviewer Run 审查 → 写 last_reviewed_run_id、review_round++
        ├─ 有未解决意见 且 review_round < N → executor Run 接力修复 → …
        └─ 评估通过  或  review_round == N
                          ▼
       落「审核中」：释放槽；local_directory 路径锁持到任务落定
```

### 6.2 终止与交接（关键）

- **`evaluation_max_rounds`（N，≥1）是自动修复的上限，不是任务终点**。
- **评估通过**（reviewer 判无未解决意见）→ 立即落「审核中」等人最终确认。
- **跑满 N 轮仍有意见** → executor **停止自动接力**，任务带着"未解决意见"落「审核中」，由人介入二选一：
  1. **回复 / 打回「进行中」** 让 Agent 继续修；
  2. **直接拖到「已完成」** 收工。
- **永不丢弃、永不无限烧**：轮数上限是硬刹车。

### 6.3 与原评估系统的差异

| 维度 | 原设计（04-studio §8） | 本设计 |
|------|----------------------|--------|
| 评估开关 | 独立布尔「启用评估」 | 隐式：是否配置评估 Agent |
| 执行形态 | executor 内部子步骤 | **独立 reviewer Agent 的独立 Run**，与 executor Run 交替 |
| 评估产出 | 只产意见，不判 pass/fail | reviewer 需能判"是否还有未解决意见"以驱动 ping-pong 终止 |
| 修复触发 | 每轮修复由人显式触发 | N 轮内 executor 自动接力修复；耗尽后才交人 |
| 终点 | 人三选一 | 一律落「审核中」人工确认 |

---

## 7. 数据模型影响

### 7.1 删除

- `WorkItem.execution_mode`（`none|manual|semi_auto|auto` 枚举）—— 行为改为隐式推导。
- 「审批计划」开关、「是否需要验收」开关。

### 7.2 调整 / 新增

```yaml
WorkItem:
  # 执行配置（替代 execution_mode + 开关）
  agents:
    executor: "agent_coder"        # 执行 Agent，可空（空 = 手动卡片）
    evaluator: "agent_evaluator"   # 评估 Agent，可空（空 = 无评估）
  evaluation_max_rounds: 3         # 评估轮数上限 N（≥1），仅 evaluator 非空时有效

  # 多 Agent 接力协调标记（K2，§5.2）
  current_run_id: null             # 非空=正在跑→跳过（防重复派发，Issue×Agent 闸）
  has_pending_input: false         # 用户回复时置 true，executor 取走后清零
  last_run_id: "run_07"            # executor 最近完成的 Run；reviewer 判"有新结果"
  last_reviewed_run_id: "run_05"   # reviewer 已审过的 Run；≠last_run_id 则需 review
  review_round: 2                  # 已 review 轮次，对比 N 判是否继续 ping-pong

  # 执行环境（worktree 混合制，§5.3）—— git 项目用，local_directory/temporary 不填
  worktree_path: "~/.focuspilot/wt/FP-002"
  worktree_branch: "task/FP-002"

  run_substate: queued | working | waiting_local_directory | null   # 调度子状态，驱动卡片角标，详见 §7.4
```

AICrew Agent 定义新增 **`max_concurrent_tasks`（默认 1）**（P3，放 AICrew，**不放** Settings）；Daemon 全局 `max_concurrent_tasks` 放 Settings（§5.4）。

### 7.3 ExecutionRun 调整（executor / reviewer 两类 Run，见 §5.5/§6）

- `mode` 字段（`manual|semi_auto|auto`）删除；新增 `agent_role: executor | reviewer` 区分两类自治 Run。
- **一个 ping-pong 区间内含多个 Run**：executor Run 与 reviewer Run 在**同一执行环境**（git worktree / local_directory 路径锁，§5.3）内交替；**槽按轮取还**（§5.5），不再共享 app 级写锁。
- 进入「审核中」时 `current_run_id = null`、释放槽（local_directory 路径锁保持到任务落定，§5.5）；人回复开启新一轮 ping-pong（新 executor Run）。一场任务跨多个 Run，`run_history_ids` 串起全部 executor/reviewer Run。
- `in_evaluation` 重命名为 `in_review`（见 §4.1）；涉及该枚举的字段（如 `blocked_from_status` 取值）同步。
- 详情页跨 Run 按时间堆叠（executor 结果块 + reviewer 评估块交替）。`review_round` 记录 ping-pong 评估轮次，供详情页与终止判定共用。

### 7.4 字段命名说明

`run_substate` 驱动卡片角标，独立于看板 `status`：

| 值 | 角标 | 含义 | 用户动作 |
|----|------|------|---------|
| `queued` | 🕐 正在排队中 | 已扫描、在等并发槽（所有类型） | 被动等，槽腾出自动跑 |
| `working` | ⚡ 正在工作 | status=in_progress，Agent 在跑 | — |
| `waiting_local_directory` | 🔒 等待本地目录（某任务占用中） | **仅 local_directory 任务**：本地目录被同目录另一任务持锁占用 | 可去把占用任务拖出审核中（escape hatch）放行 |
| `null` | 无 | 非调度态 | — |

> `waiting_local_directory` 只对 local_directory 任务出现；git worktree / temporary 无路径锁，永不进此态。它与 `queued` 的关键区别：🕐 是被动等槽、🔒 可能要主动干预（否则会被挂在审核中的任务无限期挡住）。

---

## 8. 删除项汇总（相对原 04-studio.md §3）

- ❌ 「普通任务 / 对话 / 自动」三种用户模式 → 无模式
- ❌ 「审批计划」开关 → 删除（无规划模式审批关卡）
- ❌ 「启用评估」布尔开关 → 改为"是否配置评估 Agent"
- ❌ 「是否需要验收」开关 → 删除（审核中为强制人工确认关卡）
- ❌ 自动模式 4 条步骤链 → 单一对话轮次流
- ❌ 独立「手动接管」按钮 → 降级为详情页"人工回复"通用能力

**worktree 化连带废弃 / 调整（相对本 spec 前几轮）**：

- ⚠️ **WorkspaceWriteLease 不再是 app 级共享写锁**：瘦身为 local_directory 的路径锁（§5.3）；git / temporary 改 worktree 物理隔离，无锁。
- ❌ **"ping-pong 全程持一把锁、落审核中释放 lease 防饿死"**（前几轮 C2/K3）→ worktree（git 项目）无锁、不存在饿死；local_directory 路径锁仅约束同目录（本就只能串行、审核中持锁是正确行为，非饿死），改 worktree 隔离 + 槽按轮取还。
- ❌ **"回复遇写锁竞争排队"**（前几轮 RC-4）→ 改为"抢并发槽（local_directory 还需路径锁）"。
- ⚠️ 04-studio §4.6 脏检测：worktree 下不在用户工作副本干活，语义调整（仅 local_directory 仍涉及）。

---

## 9. 待定 / 后续

- **扫描间隔默认值**：Settings 暴露，量级为秒（3~5s 量级），具体默认值落地时定（同步检查 08-settings.md）。
- **Daemon 全局并发上限默认值**：V1 已纳入三层并发的 Daemon 层（§5.4），默认值（量级 4~8）落地时定，放 Settings。
- **规划模式**：本期不做显式规划模式；后续若需要，在「待规划」状态内增强（如调用规划 Agent 协助丰富描述）。
- **多人审核**：「审核中」当前为单人验收；多人协作审核为企业版/后续能力。
- **评估 Agent 的 pass/fail 判定标准**：评估 Agent prompt 需能稳定输出"是否仍有未解决意见"，实现时定义结构化输出契约。
- **worktree 磁盘 GC 策略**：复用 04-studio §4.7 临时 workspace 的 GC（done/cancelled 超期清理 + 有未 push commit 保护），孤儿 worktree 用 `git worktree prune`（§5.7）。

---

## 10. 联动更新清单

落地时需同步：

- [ ] `docs/fp-ui/04-studio.md`：
  - 重写 §3（执行模式 → 执行模型）：无模式 + **单中央扫描器 + worktree 混合制 + 三层并发**
  - §2.4 状态机：`in_evaluation` → `in_review`、补乒乓流转与卡片角标、保留 `cancelled`
  - §7.4 详情页改为 executor/reviewer 接力的对话流
  - **§4 Workspace 模型**：加 worktree 混合制（git→worktree 分支 `task/{id}`；local_directory→原地+路径锁 `waiting_local_directory`；temporary→独立目录）；**§4.5 WorkspaceWriteLease 瘦身为 local_directory 路径锁（不再 app 级共享）**；§4.6 脏检测语义调整（仅 local_directory 涉及）；§4.7 worktree GC 复用
  - §2.1/2.5 数据模型：删 `execution_mode`；新增 `evaluation_max_rounds` / `run_substate` / **K2 协调字段（`current_run_id` / `has_pending_input` / `last_run_id` / `last_reviewed_run_id` / `review_round`）** / worktree 字段（`worktree_path` / `worktree_branch`）；ExecutionRun 新增 `agent_role: executor|reviewer`，删 `mode`
  - **§8 评估系统改写**：原文「Evaluation Agent 只产出意见、不判 pass/fail、每轮修复人工触发、不变」与本设计冲突 → 改为"**独立 reviewer Agent 的独立 Run**，输出结构化 pass/fail（是否仍有未解决意见）+ N 轮内 executor 自动接力修复 + 耗尽落审核中交人"
  - §3 重写中明确：手动卡片（无执行 Agent）不进调度、不触发强制审核中、状态全人工拖动（§4.3）；第一层只扫 `todo/in_progress/in_review` 三态（§5.4）；重启对账 + 孤儿 worktree prune（§5.7）
  - §15 V2 预留：worktree 上移到 V1，**Handoff 仍留 V2**（git 靠 PR、local_directory 原地，V1 不需合并回工作副本）
- [ ] `docs/PRD.md`：
  - §3.1 删除/替换 `auto_execute` 字段（被"拖入待办即调度"取代），状态名对齐说明
  - 注：PRD §3.1（`planning/ready/executing`）与 04-studio §2.4（`backlog/todo/in_progress`）为**既存的两套状态词汇不一致**，非本设计引入；本期只对齐 `auto_execute` 字段，**完全统一两套词汇另起一个独立任务处理**
- [ ] `docs/fp-ui/07-ai-crew.md`：Agent 定义新增 `max_concurrent_tasks`（默认 1，P3）
- [ ] `docs/fp-ui/08-settings.md`：新增「自动调度扫描间隔」+「Daemon 全局并发上限 `daemon_max_concurrent_tasks`」配置项
- [ ] `docs/fp-ui/00-layout-prototype.html`：母版同步（详情页对话流 + 卡片角标）后才可标 5/5
