# Studio 执行模型 — 文档同步实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把已定稿的执行模型 spec（`docs/superpowers/specs/2026-06-09-studio-execution-model-design.md`）同步进所有产品文档与 HTML 原型母版，消除存量旧模型残留，使文档体系自洽。

**Architecture:** 这是**文档同步计划**，非代码实现——V1 新界面仍在设计/原型阶段。产物是更新后的 5 个文档 + 母版 HTML。spec 是**唯一权威内容源**（已提交、稳定）；每个任务引用 spec 对应章节作为内容来源，列出具体增删点与目标位置，并用 grep 一致性检查 + 原型视觉验收替代 TDD。

**Tech Stack:** Markdown 文档、HTML/CSS 原型（`00-layout-prototype.html`，纯静态）、grep 一致性校验。

**权威内容源（下称 SPEC）:** `docs/superpowers/specs/2026-06-09-studio-execution-model-design.md`

**协作约定（CLAUDE.md 强约束）:**
- 每次更新 `docs/fp-ui/` 后必须输出 UI 设计进度表（见 Task 11）。
- 页面真实完成度以 `00-layout-prototype.html` 母版同步为准；仅改规格文档不得标 5/5。
- 原型变更联动规则：改原型必须检查 PRD 对应章节同步。
- 每完成一个功能/大修改自动用 `/commit` 提交并推送。

---

## 文件结构（改动地图）

| 文件 | 职责 | 本计划的改动 |
|------|------|------------|
| `docs/fp-ui/04-studio.md` | Studio 页面权威规格 | §3 重写（执行模型）、§2.4 状态机、§2.x 数据模型、§4 Workspace、§7.4 详情页、§8 评估、§15 V2 |
| `docs/PRD.md` | 主 PRD | §3.1 删 `auto_execute`、状态词汇对齐注 |
| `docs/fp-ui/07-ai-crew.md` | AICrew 页面规格 | §5.6 + §6 加 Agent `max_concurrent_tasks` |
| `docs/fp-ui/08-settings.md` | Settings 页面规格 | §3.8 Studio 删旧三模式、§3.5 Daemon 加扫描间隔+全局并发 |
| `docs/fp-ui/00-layout-prototype.html` | 原型母版 | 详情页对话流 + 看板卡片角标（🕐/⚡/🔒） |

**任务依赖顺序**：Task 1–6（04-studio）→ Task 7（PRD）→ Task 8（AICrew）→ Task 9（Settings）→ Task 10（HTML 母版）→ Task 11（一致性收尾 + 进度表）。文档任务相互独立，可并行；HTML 母版（Task 10）依赖前序规格定稿。

---

## Task 1: 04-studio.md §3 重写为执行模型

**Files:**
- Modify: `docs/fp-ui/04-studio.md`（§3「执行模式」整节，原 §3.1 三种模式 + 两个开关 / §3.2 步骤流 / §3.3 手动接管）

- [ ] **Step 1: 通读 SPEC §1–§6**

阅读 SPEC 的 §1 背景、§2 核心模型、§3 详情页、§4 状态机、§5 执行引擎、§6 评估接力，作为本任务的内容源。

- [ ] **Step 2: 把 04-studio §3 标题与定位段替换**

将 04-studio §3 标题从「## 3. 执行模式」改为「## 3. 执行模型（无模式化 + 单扫描器 + worktree 混合制）」，并在标题下写入一段总览（取 SPEC §5 开头"一句话总架构"）：

> 每个任务都是"Agent 自动干活 + 人随时插话校准"的一场多轮对话。不再有执行模式与开关：配了执行 Agent 就自动调度，配了评估 Agent 就带评估接力。一个中央扫描器（每 3~5s）读任务协调标记判"该谁干"→ 抢对应 Agent 并发槽 → 在该任务执行环境（git 项目用独立 worktree / 本地目录用路径锁原地执行）里跑。

- [ ] **Step 3: 写入 §3.1 无模式 + 配置项（来源 SPEC §2.1/§2.2）**

新增子节「### 3.1 创建任务的执行配置」，内容对齐 SPEC §2.1 表单 + §2.2 双 Agent + 配置约束（执行 Agent 留空=手动卡片；评估 Agent 空=无评估；executor 空+evaluator 非空非法）+ §2.3 执行范围（只执行当前节点、不递归，hybrid 不连带跑子节点，container 不展示，递归=V2）。把 SPEC §2.1 的新建任务弹窗 ASCII 原样搬入。

- [ ] **Step 4: 写入 §3.2 看板状态机（来源 SPEC §4）**

新增子节「### 3.2 看板状态机（乒乓模型）」，搬入 SPEC §4.1 状态流转图、§4.2 各状态语义表（含 `in_review` 改名、`cancelled`、角标列）、§4.3 关键规则（含手动卡片不进调度）、§4.4 blocked 触发与恢复。**注意**：此处与 §2.4 状态机（Task 2）会有重叠，§3.2 聚焦"执行视角"，§2.4 聚焦"数据/状态枚举"，互相 `见 §X` 交叉引用，不重复全文。

- [ ] **Step 5: 写入 §3.3 执行引擎（来源 SPEC §5）**

新增子节「### 3.3 执行引擎」，搬入 SPEC §5.1 单扫描器、§5.2 协调标记 K2 表、§5.3 worktree 混合制表（git/local_directory/temporary）+ 路径锁任务级持有、§5.4 三层并发闸 + 排序、§5.5 派发与 ping-pong（槽按轮取还 / 路径锁持到落定 / 审核中释放槽不释放锁）、§5.6 K6+H2、§5.7 重启对账、§5.8 对话跨 Run。

- [ ] **Step 6: 写入 §3.4 评估接力（来源 SPEC §6）**

新增子节「### 3.4 评估接力（reviewer 自治 Run）」，搬入 SPEC §6.1 ping-pong 逻辑、§6.2 终止与交接、§6.3 与原评估系统差异表。

- [ ] **Step 7: 删除原 §3.1–§3.3 旧内容**

删除 04-studio 原「三种模式 + 两个开关」表、原 §3.2「步骤流」四链 ASCII、原 §3.3「手动接管」（手动接管已降级为详情页人工回复，在 §3.1/§7.4 体现）。

- [ ] **Step 8: 一致性校验**

Run: `grep -nE "普通任务|semi_auto|审批计划|启用评估开关|手动接管" docs/fp-ui/04-studio.md`
Expected: §3 内无残留（其他章节如有引用一并清理或改写）。

Run: `grep -cE "worktree|waiting_local_directory|评估接力|协调标记" docs/fp-ui/04-studio.md`
Expected: 均 ≥1。

- [ ] **Step 9: Commit**

```bash
git add docs/fp-ui/04-studio.md
git commit -m "docs(studio): §3 重写为执行模型（无模式+worktree+评估接力）"
```

---

## Task 2: 04-studio.md §2.4 状态机对齐

**Files:**
- Modify: `docs/fp-ui/04-studio.md`（§2.4 Task 状态机）

- [ ] **Step 1: 枚举改名**

把 §2.4 状态机里的 `in_evaluation` 全部改为 `in_review`（中文名「审核中」不变）。保留 7 态（含 `cancelled`）。

- [ ] **Step 2: 状态流转图补乒乓 + 角标**

把 §2.4 的状态流转 ASCII 更新为 SPEC §4.1 的乒乓图（`进行中 ⇄ 审核中`、`任意状态 → 已取消`），并在图下补一句卡片角标说明：「运行子状态 `run_substate` 做卡片角标（🕐 queued / ⚡ working / 🔒 waiting_local_directory），不新增看板列」。

- [ ] **Step 3: 中文甬道名核对**

确认 §2.4 主甬道 6 列中文名仍为：待规划 / 待办 / 进行中 / 审核中 / 已完成 / 已阻塞；`已取消` 走归档不常驻。与 SPEC §4.2 一致。

- [ ] **Step 4: 校验**

Run: `grep -n "in_evaluation" docs/fp-ui/04-studio.md`
Expected: 无输出（全部已改 in_review）。

- [ ] **Step 5: Commit**

```bash
git add docs/fp-ui/04-studio.md
git commit -m "docs(studio): §2.4 状态机 in_review 改名 + 乒乓流转 + 角标"
```

---

## Task 3: 04-studio.md 数据模型对齐

**Files:**
- Modify: `docs/fp-ui/04-studio.md`（§2.1 WorkItem、§2.5 ExecutionRun）

- [ ] **Step 1: WorkItem 删 execution_mode**

在 §2.1 WorkItem YAML 中删除 `execution_mode` 字段（及「审批计划」「是否需要验收」相关注释）。

- [ ] **Step 2: WorkItem 加新字段（来源 SPEC §7.2）**

在 §2.1 WorkItem 的 `agents` 块改为 `executor` / `evaluator`（可空），并新增：
```yaml
  evaluation_max_rounds: 3
  # 协调标记（K2）
  current_run_id: null
  has_pending_input: false
  last_run_id: null
  last_reviewed_run_id: null
  review_round: 0
  # 调度子状态（卡片角标）
  run_substate: queued | working | waiting_local_directory | null
  # 执行环境（worktree 混合制；local_directory/temporary 不填）
  worktree_path: "~/.focuspilot/wt/FP-002"
  worktree_branch: "task/FP-002"
```

- [ ] **Step 2b: 保留 agents 中既有角色字段的兼容说明**

04-studio 原 `agents` 含 `planner/executor/dialog/evaluator`。本设计 V1 只用 `executor`/`evaluator`；在 YAML 注释标注「`planner`/`dialog` 字段废弃（无模式后不再使用），解码向后兼容忽略」。

- [ ] **Step 3: ExecutionRun 对齐（来源 SPEC §7.3）**

§2.5 ExecutionRun：删 `mode` 字段；新增 `agent_role: executor | reviewer`；补说明「一个 ping-pong 区间含多个 Run（executor/reviewer 交替），同一执行环境内，槽按轮取还；进入审核中 `current_run_id=null`、释放槽，local_directory 路径锁保持到任务落定」。删除/改写原「WorkspaceWriteLease 共享」相关描述（见 Task 4）。

- [ ] **Step 4: 校验**

Run: `grep -nE "execution_mode|mode: semi_auto" docs/fp-ui/04-studio.md`
Expected: §2.1/§2.5 无残留（仅迁移说明里作为"已删除"提及可接受）。

Run: `grep -cE "agent_role|run_substate|worktree_branch" docs/fp-ui/04-studio.md`
Expected: 均 ≥1。

- [ ] **Step 5: Commit**

```bash
git add docs/fp-ui/04-studio.md
git commit -m "docs(studio): §2.1/§2.5 数据模型删 execution_mode、加 K2/worktree/agent_role"
```

---

## Task 4: 04-studio.md §4 Workspace 模型 worktree 化

**Files:**
- Modify: `docs/fp-ui/04-studio.md`（§4.2 三类 Workspace、§4.5 WorkspaceWriteLease、§4.6 脏检测、§4.7 临时 Workspace GC、§4.8）

- [ ] **Step 1: §4.2 三类 Workspace 加隔离方式（来源 SPEC §5.3）**

在 §4.2 三类 Workspace 表补「隔离方式」与「并发」语义：
- `git_project` → 独立 worktree（共享 bare repo 缓存建，分支 `task/{task_id}`），真并行，push 分支 / PR 交付。
- `local_project`（指向用户本机目录 = local_directory）→ 不建 worktree、原地执行 + **路径级互斥锁**（等待态 `waiting_local_directory`），同目录串行。
- `temporary` → 独立目录，并行。

- [ ] **Step 2: §4.5 WorkspaceWriteLease 瘦身（来源 SPEC §5.3/§5.5）**

把 §4.5 WorkspaceWriteLease 改写为「**local_directory 路径锁**」：
- 不再是 app 级共享写锁；只在 local_directory 场景存在；git worktree / temporary 无锁。
- **任务级持有**：从首次执行持到任务离开执行流（落 `done`/`cancelled`/被拖出审核中），审核中也不释放（防同目录并发污染）。escape hatch：拖出审核中即释放。
- 不做分支快照（git/非 git 统一此规则）。
- 删除原「同一 active lease / 心跳 TTL / orphaned」机制中与 app 级共享锁绑定的部分；保留"重启对账"语义并指向 SPEC §5.7（清 `current_run_id` + `git worktree prune`）。

- [ ] **Step 3: §4.6 脏检测语义调整**

§4.6 脏检测改为「仅 local_directory 涉及」：worktree（git 项目）在独立副本干活、不碰用户工作树，无需脏检测；local_directory 原地执行时保留"未提交改动"提示与"创建任务分支"选项。

- [ ] **Step 4: §4.7 worktree GC（来源 SPEC §9）**

在 §4.7 临时 Workspace 生命周期补一句：worktree 磁盘 GC 复用本节策略（done/cancelled 超期清理 + 有未 push commit 保护），孤儿 worktree 用 `git worktree prune`。

- [ ] **Step 5: 校验**

Run: `grep -nE "WorkspaceWriteLease|路径锁|worktree" docs/fp-ui/04-studio.md`
Expected: §4 出现，且 WorkspaceWriteLease 处均为"瘦身/路径锁"语境。

- [ ] **Step 6: Commit**

```bash
git add docs/fp-ui/04-studio.md
git commit -m "docs(studio): §4 Workspace 加 worktree 混合制 + lease 瘦身为路径锁"
```

---

## Task 5: 04-studio.md §7.4 详情页 + §8 评估系统

**Files:**
- Modify: `docs/fp-ui/04-studio.md`（§7.4 场景 D Task 详情、§8 评估系统）

- [ ] **Step 1: §7.4 详情页改对话流（来源 SPEC §3）**

把 §7.4 Task 详情的「执行步骤进度条」替换为 SPEC §3 的对话流详情页 ASCII（任务描述 → executor 自动执行块 → reviewer 评估块 → 人工回复 → … 堆叠 + 底部输入框）。保留「关联对话 / 属性」区。补 SPEC §3 的 5 条规则（含规则 1「入队/被拉起后第一个动作自动执行」、规则 5 回复时序分流）。

- [ ] **Step 2: §8 评估系统改写（来源 SPEC §6.3）**

把 §8「沿用原 Focus 评估系统，不变」整段改写：
- 删除「Evaluation Agent 只产出评估意见，不产出 pass/fail」「每轮修复由用户显式触发」。
- 改为：reviewer 是**独立评估 Agent 的独立 Run**，输出结构化 pass/fail（是否仍有未解决意见）；N 轮内 executor 自动接力修复；跑满 N 轮仍有意见 → 停、带未解决意见落审核中交人（采纳/打回继续/直接完成）。
- severity 排序、EvaluationCycle 可循环等可保留并对齐 `review_round`。

- [ ] **Step 3: 校验**

Run: `grep -nE "不产出 pass/fail|每轮修复由用户显式触发" docs/fp-ui/04-studio.md`
Expected: 无输出（旧表述已删）。

Run: `grep -cE "对话流|人工回复|reviewer" docs/fp-ui/04-studio.md`
Expected: ≥1。

- [ ] **Step 4: Commit**

```bash
git add docs/fp-ui/04-studio.md
git commit -m "docs(studio): §7.4 详情页改对话流 + §8 评估系统改 pass/fail 自动接力"
```

---

## Task 6: 04-studio.md §15 V2 预留调整

**Files:**
- Modify: `docs/fp-ui/04-studio.md`（§15 V2 预留）

- [ ] **Step 1: worktree 上移 V1、Handoff 留 V2**

在 §15「V2 预留」中：
- 删除「Git worktree 并行隔离执行」（已上移 V1，见 §4）。
- **保留**「Handoff（Worktree 变更迁移到主工作区）」并加注：git 项目靠 PR 交付、local_directory 原地改，V1 不需要合并回工作副本；Handoff 仍 V2。
- 新增 V2 项：「容器节点递归自动执行」（PRD §3.1 的拖父节点递归，本期只执行当前节点）。

- [ ] **Step 2: 校验**

Run: `grep -n "worktree" docs/fp-ui/04-studio.md`
Expected: §15 不再把 worktree 列为 V2；§4 有 worktree。

- [ ] **Step 3: Commit**

```bash
git add docs/fp-ui/04-studio.md
git commit -m "docs(studio): §15 worktree 上移 V1，Handoff/容器递归留 V2"
```

---

## Task 7: PRD.md §3.1 对齐

**Files:**
- Modify: `docs/PRD.md`（§3.1 两阶段模型）

- [ ] **Step 1: 删除/替换 auto_execute**

在 §3.1 状态表中，把 `ready` 行的触发条件「用户点击「执行」或设置 `auto_execute: true` 自动触发」改为「拖入「待办」即被中央扫描器自动调度（取代 `auto_execute` 字段）」。删除 `auto_execute` 字段引用。

- [ ] **Step 2: 加状态词汇对齐注**

在 §3.1 末尾加一条注：「PRD §3.1（`inbox/planning/ready/executing`）与 04-studio §2.4（`backlog/todo/in_progress/in_review`）为既存的两套状态词汇；本期只对齐 `auto_execute` 字段，完全统一两套词汇另起独立任务处理。」

- [ ] **Step 3: 校验**

Run: `grep -n "auto_execute" docs/PRD.md`
Expected: 仅在"已取代/对齐说明"语境出现，无作为活跃触发字段。

- [ ] **Step 4: Commit**

```bash
git add docs/PRD.md
git commit -m "docs(prd): §3.1 删 auto_execute，补状态词汇对齐注"
```

---

## Task 8: 07-ai-crew.md 加 Agent 并发配置

**Files:**
- Modify: `docs/fp-ui/07-ai-crew.md`（§5.6 Agent 配置规则、§6 数据对象、§3.1 智能体成员工作区表单）

- [ ] **Step 1: §5.6 加并发规则**

在 §5.6 Agent 配置规则补一条：「**并发上限（`max_concurrent_tasks`，默认 1）**：单个 Agent 同时能跑多少个任务（不同任务/Workspace 间并行）；与 Daemon 全局上限、Issue×Agent=1 共同构成三层并发控制（详见 04-studio §3.3）。」

- [ ] **Step 2: §6 数据对象加字段**

在 §6 数据对象的 Agent/CrewMember 模型补 `max_concurrent_tasks: 1` 字段及注释。

- [ ] **Step 3: §3.1 成员工作区表单加控件**

在 §3.1 智能体成员工作区的配置表单（Instructions/Skills/Env/Args/MCP 同级）补一项「并发上限 | stepper/select：1–8 | 默认 1」。

- [ ] **Step 4: 校验**

Run: `grep -c "max_concurrent_tasks" docs/fp-ui/07-ai-crew.md`
Expected: ≥2（规则 + 数据对象）。

- [ ] **Step 5: Commit**

```bash
git add docs/fp-ui/07-ai-crew.md
git commit -m "docs(ai-crew): Agent 新增 max_concurrent_tasks 并发配置"
```

---

## Task 9: 08-settings.md Studio/Daemon 对齐

**Files:**
- Modify: `docs/fp-ui/08-settings.md`（§3.8 Studio、§3.5 Daemon、§6 数据对象）

- [ ] **Step 1: §3.8 Studio 删旧三模式**

把 §3.8 Studio 表中「默认执行方式 | radio：普通 / 对话 / 自动」**整行删除**（无模式后不存在执行方式选择）。「默认 Agent」保留（= 默认 executor）。「默认启用评估」改为「默认评估 Agent | select（引用 AICrew 成员，可空=不评估）」+「默认评估轮数 | select：1/2/3」。「并发上限」行迁移到 §3.5 Daemon（见 Step 2）。

- [ ] **Step 2: §3.5 Daemon 加扫描间隔 + 全局并发**

在 §3.5 Daemon 配置块补两项：
- 「扫描间隔 | select：3s / 5s / 10s（默认 5s） | 中央扫描器轮询任务的周期」。
- 「全局并发上限（`max_concurrent_tasks`）| select：2 / 4 / 6 / 8（默认按个人 Mac 取小，建议 4） | 整机同时运行的最大 Task 数（Daemon 级信号量）」。
（这条整合自原 §3.8 的「并发上限 1/2/3」，数值范围上调到 2–8 并迁此处。）

- [ ] **Step 3: §6 数据对象补字段**

在 §6 数据对象的 Settings/Preferences 模型补 `scan_interval_seconds`、`daemon_max_concurrent_tasks` 字段。

- [ ] **Step 4: 校验**

Run: `grep -nE "普通 / 对话 / 自动|默认执行方式" docs/fp-ui/08-settings.md`
Expected: 无输出（旧三模式行已删）。

Run: `grep -cE "扫描间隔|scan_interval|全局并发" docs/fp-ui/08-settings.md`
Expected: ≥1。

- [ ] **Step 5: 更新 spec §10 文件名笔误**

把 SPEC（`docs/superpowers/specs/2026-06-09-studio-execution-model-design.md`）§10 中的 `07-settings.md` 全部改为 `08-settings.md`。

Run: `grep -n "07-settings.md" docs/superpowers/specs/2026-06-09-studio-execution-model-design.md`
Expected: 无输出。

- [ ] **Step 6: Commit**

```bash
git add docs/fp-ui/08-settings.md docs/superpowers/specs/2026-06-09-studio-execution-model-design.md
git commit -m "docs(settings): §3.8 删旧三模式、§3.5 加扫描间隔+全局并发；修 spec 文件名笔误"
```

---

## Task 10: 00-layout-prototype.html 母版同步

**Files:**
- Modify: `docs/fp-ui/00-layout-prototype.html`（Studio 详情页视图 + 看板卡片）

- [ ] **Step 1: 定位 Studio 相关 DOM**

Run: `grep -nE "studio|kanban|看板|详情|in_review|审核中" docs/fp-ui/00-layout-prototype.html | head -40`
阅读 Studio 看板与 Task 详情现有结构，确定要改的节点。

- [ ] **Step 2: 看板卡片加运行子状态角标**

在看板卡片模板里加右上角角标区，三态样式：
- `🕐 正在排队中`（queued，灰）
- `⚡ 正在工作`（working，蓝/绿）
- `🔒 等待本地目录`（waiting_local_directory，橙/锁色）
对齐 SPEC §7.4 角标映射表的语义与配色（配色遵循 DesignGuide.md 主题色，**改前必读 DesignGuide.md**）。

- [ ] **Step 3: Task 详情改对话流**

把 Task 详情的「执行步骤进度条」替换为对话流（SPEC §3 ASCII 的 HTML 实现）：任务描述块 → 🤖 executor 自动执行块（含 Diff/Transcript 链接）→ 🔍 reviewer 评估块 → 👤 人工回复块（堆叠）→ 底部追加指令输入框。

- [ ] **Step 4: 状态机改名**

母版里看板列/状态相关文案 `in_evaluation` → `in_review`（中文「审核中」不变）。

- [ ] **Step 5: 视觉验收（替代自动化测试）**

用浏览器打开 `docs/fp-ui/00-layout-prototype.html`，停在 Studio 页面，人工核对：① 卡片三态角标渲染正确；② Task 详情为对话流而非进度条；③ 无旧「普通/对话/自动」模式控件残留。**不用截图替代用户验收**（CLAUDE.md），停留等用户查看。

Run: `open docs/fp-ui/00-layout-prototype.html`
Expected: 浏览器打开母版，Studio 视图呈现对话流详情 + 卡片角标。

- [ ] **Step 6: Commit**

```bash
git add docs/fp-ui/00-layout-prototype.html
git commit -m "docs(proto): 母版同步 Studio 对话流详情 + 卡片三态角标"
```

---

## Task 11: 一致性收尾 + UI 进度表

**Files:**
- 全体 `docs/fp-ui/*` + `docs/PRD.md`（只读校验）

- [ ] **Step 1: 跨文档术语一致性扫描**

Run: `grep -rnE "execution_mode|in_evaluation|普通 / 对话 / 自动|auto_execute" docs/fp-ui/ docs/PRD.md`
Expected: 仅在"已删除/对齐说明"语境出现；无活跃旧模型残留。

Run: `grep -rc "worktree" docs/fp-ui/04-studio.md docs/fp-ui/08-settings.md`
Expected: 04-studio ≥1。

- [ ] **Step 2: 原型↔PRD 联动检查（CLAUDE.md 规则）**

确认 04-studio 状态机/数据模型/详情页与 PRD §3.1 无矛盾；如有，回对应任务补修。

- [ ] **Step 3: 输出 UI 设计进度表（CLAUDE.md 强制）**

在回复中输出各页面完整度与状态表（04-studio 因母版已同步可维持/标记完成度），并**用浏览器打开** `docs/fp-ui/00-layout-prototype.html` 停留等用户验收（不用截图替代）。

- [ ] **Step 4: 终审提交（如有零散修正）**

```bash
git add -A docs/
git commit -m "docs: Studio 执行模型文档同步一致性收尾"
```

---

## Self-Review 检查清单（撰写者自检，已执行）

- **Spec 覆盖**：SPEC §2→Task1/3、§3→Task1/5/10、§4→Task1/2/10、§5→Task1/4、§6→Task1/5、§7→Task3、§8 删除项→Task1/9、§9 待定→Task4/9、§10 联动清单 5 文件全部有对应任务（04-studio→T1-6、PRD→T7、AICrew→T8、Settings→T9、母版→T10）。✅ 无遗漏。
- **占位符**：无 TBD/TODO；内容源统一指向已提交 SPEC 的具体章节（稳定、版本锁定），非计划内跨任务"similar to"。
- **类型一致**：字段名 `executor`/`evaluator`/`evaluation_max_rounds`/`current_run_id`/`has_pending_input`/`last_run_id`/`last_reviewed_run_id`/`review_round`/`run_substate`/`worktree_path`/`worktree_branch`/`agent_role`/`max_concurrent_tasks`/`scan_interval_seconds` 在 Task 3/8/9 间一致，与 SPEC §7 对齐。
- **存量冲突**：已显式处理 08-settings §3.8 旧三模式（Task9-S1）、原 `agents.planner/dialog` 废弃（Task3-S2b）、spec §10 文件名笔误（Task9-S5）。
