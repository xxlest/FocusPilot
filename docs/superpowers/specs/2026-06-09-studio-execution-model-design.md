# Studio 执行模型重构设计

> **主题**：Studio 看板任务的执行模型（无模式化 + 两层循环/多 Agent 自治接力 + 对话式详情页）
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
│ 🤖 代码工程师 · 自动执行              00:03:42  ⚡     │  ← 创建/入队后
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

1. **创建后第一个动作是 Agent 自动执行**（不等人），开场白就是任务描述本身。
2. **每一轮 🤖 executor 执行后 🔍 reviewer 独立接力评估**：配了评估 Agent 时，executor Run 与 reviewer Run 交替（执行→评估→有意见再执行→再评估），在 N 轮内全自动来回，同一持锁 ping-pong 区间（见 §5.5、§6）。
3. **人回复 = 触发下一轮自动执行**：人在对话里回一句话，就是"继续"的扳机，Agent 据此再自动跑一轮。"打回继续修"和"人工回复"是同一个动作。
4. **整页从上往下无限堆叠**：执行结果、评估结果、人工回复按时间顺序追加，像聊天记录。
5. **回复时序随状态分流**：
   - 任务在「审核中」（Agent 已停、等人）时回复 → 启动新一轮 ping-pong 并申请写锁：拿到锁则进「进行中」（⚡）；锁被同 Workspace 别的任务占用则回 `todo` 入队、显示「🕐 正在排队中」，拿到锁后再进「进行中」（与 §5.5/§5.6 一致）。
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
| `todo` | 待办 | **拖入即扫描** | 调度器扫到 → 拿到写锁就进「进行中」；没拿到（同 Workspace 写锁被占）停这里，显示「🕐 正在排队中」 |
| `in_progress` | 进行中 | 执行中 | executor↔reviewer ping-pong 在跑（同一持锁区间），显示「⚡ 正在工作」；落「审核中」时释放 lease（见 §5.5） |
| `in_review` | 审核中 | 等人回复 | 自动执行一轮跑完一律落这里。人**回复**→ 弹回「进行中」再跑；人**满意**→ 拖到「已完成」 |
| `done` | 已完成 | — | 人工拖入确认。AI 产出必须经人审查再交付（删除原"验收开关"） |
| `blocked` | 已阻塞 | — | 外部依赖阻塞，解除后回 `blocked_from_status`（见 §4.4） |
| `cancelled` | 已取消 | — | 终止状态，进归档/历史，不在主甬道常驻展示 |

### 4.3 关键规则

- **「待规划」承担规划职能**：原"规划模式"砍掉，规划改为在「待规划」列由人/对话完成（丰富任务描述），无独立执行模式。
- **「待办」拖入即自动执行**：这是自动调度的唯一触发口。
- **「审核中」是强制的人工确认关卡（必经站，非终点）**：**仅对配置了执行 Agent 的自动任务**——每轮自动执行跑完都落「审核中」等人；它会与「进行中」来回，真正的终点是「已完成」。删除原"是否需要验收"开关。
- **手动卡片（无执行 Agent）不进自动调度，也不触发强制审核中**：状态完全由人自由拖动（待规划 → 待办 → 进行中 → 已完成），无 Agent 执行、无「审核中」强制关卡、无运行子状态角标。
- **「进行中」⇄「审核中」可来回**：人在审核中回复即重新触发执行，回到进行中；满意则拖到已完成。
- **运行子状态做成卡片角标**（`正在排队中` / `正在工作`），不新增看板列，保持 6 列主甬道干净。

### 4.4 已阻塞（blocked）的触发与恢复

- **进入**：仅**人工**标记 blocked（V1 不做 Agent 自检自动阻塞）。执行 Agent 卡住时表现为评估循环耗尽 → 落「审核中」交人，由人判断是否标 blocked。
- **记录来源**：标 blocked 时写 `blocked_from_status`（通常是 `todo` 或 `in_review`）。若任务正在「进行中」被标 blocked，当前 ping-pong 的 Run 按 aborted 处理、释放 lease（见 §5.5）。
- **恢复**：解除阻塞 → 回到 `blocked_from_status`；若回到 `todo` 则重新进入自动调度队列，不自动续跑上一个 Run。

---

## 5. 执行引擎：两层循环 + 多 Agent 自治队列

执行引擎建模为**多个自治 worker（执行 Agent / 评估 Agent 各算一个）通过任务状态标记互相接力**的黑板（blackboard）/生产者-消费者架构。executor 与 reviewer 是对称的自治 worker：各自扫描"哪些任务归我、该不该入我的队"，靠任务上的协调标记字段（§5.3）接力，互不直接调用。

### 5.1 两层循环

- **第一层（状态层扫描）**：周期性遍历看板，只扫 `todo / in_progress / in_review` 三态（§5.4），捞出候选任务。
- **第二层（任务层判定）**：对每个候选任务，各 Agent 按自己的判据决定是否入队：
  - **(a) 新任务**：从未执行过（无 `last_run_id`）→ executor 入队 → 执行完落「审核中」。
  - **(b) 新回复 = 新需求**：审核中/队列里发现 `has_pending_input` → executor 入队再执行。
  - **(c) 执行中补需求**：正跑时用户又回复 → 本轮 ping-pong 跑完后检查 `has_pending_input`，有则再执行；多条回复合并为一个需求批次（§5.6）。

### 5.2 多 Agent 队列的落地方式（K1：逻辑多队列 / 物理单循环）

语义上"每个 Agent 跑自己的扫描 + 自己的队列"；**实现上 V1 采用单个调度循环承载所有 Agent 的逻辑队列**，每个 Agent 一条逻辑队列：

- 语义与"每 Agent 一个独立线程"完全等价，但**避免多线程并发读写同一份任务状态的竞态**（executor 写结果 / reviewer 读，reviewer 写意见 / executor 读）。
- 物理去中心化（每 Agent 独立线程/进程）留待 V2，届时需对任务状态加锁/事务。
- 扫描间隔可在 Settings 配置（默认值待定，量级为秒）。

### 5.3 协调标记字段（K2，模型命门）

两个 Agent 靠任务状态接力，定义以下字段（落库见 §7.2）：

| 字段 | 写者 | 读者 | 作用 |
|------|------|------|------|
| `has_pending_input` | 用户回复时置 true | executor | 驱动 (b)(c) 再执行；executor 取走后清零 |
| `last_run_id` | executor 完成时写 | reviewer | reviewer 判"有新结果" |
| `last_reviewed_run_id` | reviewer 完成时写 | reviewer | `last_run_id != last_reviewed_run_id` → 需 review |
| `review_round` | reviewer 自增 | executor & reviewer | 对比 N，判是否继续 ping-pong |

- **executor 入队判据**：`has_pending_input == true`，或（新任务且无 `last_run_id`），或（reviewer 留下未解决意见且 `review_round < N`）。
- **reviewer 入队判据**：配了评估 Agent 且 `last_run_id != last_reviewed_run_id` 且 `review_round < N`。

### 5.4 第一层扫描范围（K4：只扫 3 态）

只扫 `todo / in_progress / in_review`：

- `done` 不重开、`blocked` 不抢跑、`backlog`（待规划）是人工规划区，三态都不扫。
- 手动卡片（无执行 Agent）即使处于这 3 态也不被任何 Agent 入队。

### 5.5 写锁与 ping-pong 持锁区间（K3）

- executor 写文件需 WorkspaceWriteLease（同 `resolved_workdir` 同时只允许一个 active lease，沿用 04-studio §4.5）；reviewer 只读审查，**不另抢锁**，在任务已持有的锁内跑。
- **整个 executor↔reviewer ping-pong（从首次执行到落「审核中」）= 一个持锁区间**：锁在首个 executor Run 启动时获取，期间 executor Run 与 reviewer Run 交替都在这把**已持有的锁**内跑，直到落「审核中」才释放。
  - 理由：若 ping-pong 中途释放锁，两轮 executor 之间同 Workspace 别的任务插进来改文件，reviewer 审的就不是同一份产出，一致性崩。
- **落「审核中」释放锁**（与 C2 饿死修复一致）：等人期间不写文件，释放锁让同 Workspace 排队任务继续；人回复 → 重新获取锁（被占则排队，§5.6）。

调度流程：

```
第一层扫到候选（todo/in_progress/in_review，有执行 Agent）
  executor 判据命中 → 入 executor 逻辑队列 → 标「🕐 正在排队中」
    └─ 申请/复用 ping-pong 写锁
         ├─ 拿到 → in_progress，标「⚡ 正在工作」，executor Run 执行
         └─ 没拿到（写锁被占）→ 留 todo 队列，保持「🕐 正在排队中」
  executor Run 完成 → 写 last_run_id
  reviewer 判据命中（last_run_id≠last_reviewed_run_id 且 review_round<N）
    → reviewer Run（同一锁内）审查 → 写 last_reviewed_run_id、review_round++
         ├─ 有意见 → executor 接力再执行（同锁）→ …
         └─ 通过 / review_round==N → 释放锁 → 落 in_review（审核中）
```

### 5.6 需求合并与回复遇锁（K6）

- 用户一次/连续回复多条 → 合并为**一个新需求批次、一次执行**（同 Workspace 写锁串行，不真并行）。"并发扫描合并多需求"指的是合并成批，不是多线程并行跑同一任务。
- 审核中回复 → executor 申请锁：拿到进「进行中」（⚡）；被占则回 `todo` 入队、「🕐 正在排队中」，拿到锁后再进「进行中」。

### 5.7 对话跨 Run 连续性

- 详情页的多轮堆叠跨多个 ExecutionRun（executor Run 与 reviewer Run），对话连续性靠 **Task 级 transcript / Session** 维持，不靠单个 Run。
- `run_history_ids` 记录每一个 Run；`current_run_id` 仅在 ping-pong 进行中非空，落「审核中」置 null。

---

## 6. 评估接力（reviewer 自治 Run）

评估不再是 executor Run 内部的子步骤，而是**独立评估 Agent 的独立 Run**，与 executor Run 在同一持锁 ping-pong 区间（§5.5）内交替（K5）。

### 6.1 ping-pong 逻辑

```
executor Run 执行 → 写 last_run_id
   → reviewer Run 审查 → 写 last_reviewed_run_id、review_round++
        ├─ 有未解决意见 且 review_round < N → executor Run 接力修复 → …
        └─ 评估通过  或  review_round == N
                          ▼
              释放 ping-pong 锁 → 落「审核中」
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

  # 多 Agent 接力协调标记（K2，§5.3）
  has_pending_input: false         # 用户回复时置 true，executor 取走后清零
  last_run_id: "run_07"            # executor 最近完成的 Run；reviewer 判"有新结果"
  last_reviewed_run_id: "run_05"   # reviewer 已审过的 Run；≠last_run_id 则需 review
  review_round: 2                  # 已 review 轮次，对比 N 判是否继续 ping-pong

  run_substate: queued | working | null   # 运行子状态，驱动卡片角标，详见 §7.4
```

### 7.3 ExecutionRun 调整（executor / reviewer 两类 Run，见 §5.5/§6）

- `mode` 字段（`manual|semi_auto|auto`）删除；新增 `run_kind: executor | reviewer` 区分两类自治 Run。
- **一个持锁 ping-pong 区间内含多个 Run**：executor Run 与 reviewer Run 交替，**共享同一把 WorkspaceWriteLease**（K3，§5.5）；锁在首个 executor Run 启动时获取，落「审核中」才释放。
- 进入「审核中」时 `current_run_id = null`、释放 lease；人回复开启新一轮 ping-pong（新 executor Run）。一场任务跨多个 Run，`run_history_ids` 串起全部 executor/reviewer Run。
- `in_evaluation` 重命名为 `in_review`（见 §4.1）；涉及该枚举的字段（如 `blocked_from_status` 取值）同步。
- 详情页跨 Run 按时间堆叠（executor 结果块 + reviewer 评估块交替）。`review_round` 记录 ping-pong 评估轮次，供详情页与终止判定共用。

### 7.4 字段命名说明

`run_substate`（`queued | working | null`）驱动卡片角标，独立于看板 `status`：`queued` ↔ 「🕐 正在排队中」（status=todo 且已入队等锁），`working` ↔ 「⚡ 正在工作」（status=in_progress）。

---

## 8. 删除项汇总（相对原 04-studio.md §3）

- ❌ 「普通任务 / 对话 / 自动」三种用户模式 → 无模式
- ❌ 「审批计划」开关 → 删除（无规划模式审批关卡）
- ❌ 「启用评估」布尔开关 → 改为"是否配置评估 Agent"
- ❌ 「是否需要验收」开关 → 删除（审核中为强制人工确认关卡）
- ❌ 自动模式 4 条步骤链 → 单一对话轮次流
- ❌ 独立「手动接管」按钮 → 降级为详情页"人工回复"通用能力

---

## 9. 待定 / 后续

- **扫描间隔默认值**：Settings 暴露，量级为秒，具体默认值落地时定（建议同步检查 07-settings.md）。
- **规划模式**：本期不做显式规划模式；后续若需要，在「待规划」状态内增强（如调用规划 Agent 协助丰富描述）。
- **多人审核**：「审核中」当前为单人验收；多人协作审核为企业版/后续能力。
- **评估 Agent 的 pass/fail 判定标准**：评估 Agent prompt 需能稳定输出"是否仍有未解决意见"，实现时定义结构化输出契约。
- **全局并发上限**：V1 排队的唯一原因是 WorkspaceWriteLease 锁竞争（同 Workspace 串行），不设跨 Workspace 全局并发上限。若后续本机资源/API 速率出现瓶颈，再考虑在 Settings 增"全局最多 N 个 Run 并行"配置（V2）。

---

## 10. 联动更新清单

落地时需同步：

- [ ] `docs/fp-ui/04-studio.md`：
  - 重写 §3（执行模式 → 执行模型）：无模式 + **两层循环 + 多 Agent 自治队列（黑板接力，K1=B 逻辑多队列/物理单循环）**
  - §2.4 状态机：`in_evaluation` → `in_review`、补乒乓流转与卡片角标、保留 `cancelled`
  - §7.4 详情页改为 executor/reviewer 接力的对话流
  - §2.1/2.5 数据模型：删 `execution_mode`；新增 `evaluation_max_rounds` / `run_substate` / **K2 协调字段（`has_pending_input` / `last_run_id` / `last_reviewed_run_id` / `review_round`）**；ExecutionRun 新增 `run_kind: executor|reviewer`，一个 ping-pong 区间多 Run 共享一把锁
  - **§8 评估系统改写**：原文「Evaluation Agent 只产出意见、不判 pass/fail、每轮修复人工触发、不变」与本设计冲突 → 改为"**独立 reviewer Agent 的独立 Run**，输出结构化 pass/fail（是否仍有未解决意见）+ N 轮内 executor 自动接力修复 + 耗尽落审核中交人"
  - §4.5 写锁：补「ping-pong 全程持一把锁、落审核中释放」（§5.5）
  - §3 重写中明确：手动卡片（无执行 Agent）不进调度、不触发强制审核中、状态全人工拖动（§4.3）；第一层只扫 `todo/in_progress/in_review` 三态（§5.4）
- [ ] `docs/PRD.md`：
  - §3.1 删除/替换 `auto_execute` 字段（被"拖入待办即调度"取代），状态名对齐说明
  - 注：PRD §3.1（`planning/ready/executing`）与 04-studio §2.4（`backlog/todo/in_progress`）为**既存的两套状态词汇不一致**，非本设计引入；本期只对齐 `auto_execute` 字段，**完全统一两套词汇另起一个独立任务处理**
- [ ] `docs/fp-ui/07-settings.md`：新增"自动调度扫描间隔"配置项
- [ ] `docs/fp-ui/00-layout-prototype.html`：母版同步（详情页对话流 + 卡片角标）后才可标 5/5
