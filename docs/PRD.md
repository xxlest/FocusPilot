# FocusPilot 产品需求文档（PRD）

> **版本**：0.0.1
> **状态**：设计中
> **日期**：2026-04-06
> **基于**：FocusPilot V4.3（内部开发版）→ FocusPilot 0.0.1（首个正式版本）
> **关联文档**：[Architecture.md](Architecture.md)（技术架构）、[DesignGuide.md](DesignGuide.md)（设计规范）、[Editions.md](Editions.md)（版本规划）
> **参考文档**：[PRD-v4-legacy.md](archive/PRD-v4-legacy.md)（V4.3 内部开发版功能参考，后续按需迁移）

---

## 1. 产品概述

### 1.1 产品定位

**FocusPilot** 是一个多端 AI Agent 编排平台（本地龙虾），在本地操作系统之上提供智能 AIOS 层。

- **VaultOne** 管知识（笔记、项目规划、知识卡片）
- **FocusPilot** 管执行（Agent 编排、任务调度、技能系统）
- 两者构成"认知 → 执行"自迭代闭环

原 FocusPilot V4.3（悬浮球 + 窗口管理 + 番茄钟）功能全部保留，升级为 FocusPilot 0.0.1。

核心命题源自 VaultOne 系统理念——**"Everything is Code. Project ships. FocusPilot builds."**

- **人的职责**：探索、研究、规划（Project/Epic/US/Task），在任意粒度上细化意图
- **Task 即指令**：用自然语言表达意图，发送给 FocusPilot 执行
- **FocusPilot 即执行层**：连接人的思考，调度 AI 工具，将 Task 转化为代码、文档、数据、报告

### 1.2 目标用户

| 用户画像 | 核心需求 |
|---------|---------|
| 独立开发者 | 项目管理 + AI 编码调度 + 窗口快切 |
| 重度知识工作者 | 多项目并行 + 知识管道 + 跨设备访问 |
| 终身学习者 | 素材收集 → 报告整合 → 知识卡片 → Anki 间隔重复 |
| 自由职业者 | 轻量项目管理 + 番茄钟 + AI 辅助 |

### 1.3 核心痛点

| 痛点 | 现有方案的不足 |
|------|--------------|
| AI 工具散落各处，缺乏统一调度 | Claude Code/Codex/Cursor 各自为战，无项目级编排 |
| 项目规划与执行断裂 | 规划在笔记里，执行在终端里，进度靠脑记 |
| 知识碎片化，学了就忘 | 素材堆积，无系统化加工 → 提炼 → 记忆链路 |
| 打开 App 太多，切换效率低 | `⌘Tab` 在 15+ App 时几乎不可用 |
| 缺少"今日聚焦"视图 | 任务散落在不同工具，不知道现在该做什么 |

### 1.4 竞品对标

| 能力 | FocusPilot | OpenClaw | WorkBuddy | Cursor | Devin |
|------|----------|----------|-----------|--------|-------|
| AIOS 定位 | 本地智能 OS 层 | Agent 框架 | 办公 Agent | IDE + Agent | 纯云端 Agent |
| 项目管理 | 四模式 Markdown 引擎 | — | 文档管理 | — | Playbook |
| 无模式 Agent 编排 | 配执行/评估 Agent 自动调度 + 接力 | — | — | — | — |
| 多 AI 工具调度 | MCP 统一 | 模型 Gateway | 多模型切换 | 内置 | 内置 |
| 知识管道 | Materials→Reports→KB→Anki | — | — | — | — |
| 窗口管理 | 有（内置） | — | — | — | — |
| 番茄钟 | 有（内置） | — | — | — | — |
| Today Dashboard | 有 | — | — | — | — |

**差异化定位**：FocusPilot 是本地优先的智能 AIOS，唯一同时提供"四模式项目管理 + 无模式 Agent 编排执行 + 窗口管理 + 番茄钟 + Today Dashboard"的桌面平台。

### 1.5 产品形态

| 形态 | 说明 | 状态 |
|------|------|------|
| **FocusPilot Local**（本地龙虾） | macOS App，指挥官模式，本地常驻。内置悬浮球、窗口管理、番茄钟 | V1 实现 |
| **FocusPilot Cloud**（云端龙虾） | 同一 Engine 部署到云服务器，提供离线常驻服务 | 预留 |
| **FocusPilot Mobile**（移动端） | 飞书 Bot（轻量指挥）+ Web App（详细操作），对话模式 | 预留 |

### 1.6 设计准则

- **干净**：Engine 与 UI 壳职责分离，模块之间不互相污染
- **高级**：V1 只做项目管理 + 单 Agent 调度，做到极致再扩展
- **克制**：云端/移动端/多技能全部预留不预做
- **专业**：Engine 作为独立服务，同一份代码可部署到本地/云端/Docker

---

## 2. 产品架构

### 2.1 三层 UI + Engine

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   Layer 1: 悬浮球（Floating Ball）                           │
│   ● 常驻屏幕的最小化入口，始终置顶                              │
│   │                                                         │
│   │── hover ──────▶  Layer 2: Quick Panel                   │
│   │── click ──────▶  活跃/关注/聚焦 三 Tab                    │
│   │                  窗口快切 + 今日聚焦                       │
│   │                                                         │
│   │── double-click ─▶  Layer 3: 主面板                       │
│   │── Dock 图标 ────▶  VS Code 风格多功能面板                  │
│   │                    项目管理 / Kanban / Crew / 对话         │
│   │                                                         │
│   └── Agent Engine ──▶  Layer 4: 后台服务                    │
│                          项目引擎 / MCP Host / 调度器         │
│                          localhost:19840                     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 AIOS 概念映射

| AIOS 概念 | FocusPilot 对应 |
|-----------|--------------|
| 桌面 | Today Dashboard |
| 文件系统 | Markdown 项目引擎（四模式） |
| 进程管理 | MCP Host Agent 编排 |
| 任务调度 | Scheduler |
| 应用商店 | Skill 技能系统 |
| 知识管道 | Materials → Reports → KB → Anki |
| 系统日志 | 自动日志 _logs/ |
| 远程访问 | 飞书 Bot + Web App（预留） |
| 数字员工 | Crew 数字团队 |
| 窗口管理 | 悬浮球 + 快捷面板（macOS 内置） |
| 番茄钟 | FocusByTime（macOS 内置） |

---

## 3. 功能需求

### 3.1 任务执行：Agent 配置驱动（无模式）

任务执行**不分阶段、无执行模式**，行为完全由创建时的 Agent 配置隐式推导（权威定义见 [04-studio §3](fp-ui/04-studio.md)）：

- **配执行 Agent**：任务拖入「待办」即被中央扫描器自动调度执行；留空则为纯手动卡片，靠人拖动状态。
- **配评估 Agent（自动评估）**：每轮执行后评估 Agent 自动审查、执行 Agent 据意见修复，在「进行中 ⇄ 审核中」间接力，至多 N 轮。
- **递归**：容器节点执行 = 其子节点依次执行（**V2**；V1 只执行当前节点自身）。

**任务状态模型**：`status` 字段统一采用看板状态模型，主甬道 6 态（与 04-studio §2.4、各原型 `taskStatusDefs` 完全一致）：

```
待规划(backlog) → 待办(todo) → 进行中(in_progress) ⇄ 审核中(in_review) → 已完成(done)；任意态 → 已阻塞(blocked)
```

| 状态 | key | 说明 |
|------|-----|------|
| 待规划 | `backlog` | 待排期，未进入执行流 |
| 待办 | `todo` | 拖入「待办」即被中央扫描器自动调度执行（取代原 `auto_execute` 字段；详见 [Studio 执行模型](fp-ui/04-studio.md) §3） |
| 进行中 | `in_progress` | Agent 工作中，实时反馈进度；内部含 AI 评估接力（见 04-studio §3.4） |
| 审核中 | `in_review` | 自动执行跑完一律落此态等人工确认；人在任务详情「变更」视图查看 diff/产物、「文件」视图浏览所属 Workspace 文件；确认即拖入「已完成」，回复即重新触发、回「进行中」 |
| 已完成 | `done` | 人工确认通过 |
| 已阻塞 | `blocked` | 外部依赖阻塞，解除后回来源状态 |
| 容器节点执行 | — | 递归执行其子节点中所有 Task（**V2**；V1 只执行当前节点自身，见 04-studio §3.1/§15） |

> 终止态 `cancelled` 进入归档，不在主甬道常驻。**状态机/流转图/运行子状态的权威定义见 [04-studio §2.4](fp-ui/04-studio.md)**，本文不重复维护枚举。

**对话式交互**：

任务的细化与执行都通过统一的**对话面板**进行，用户不需要感知 Skill、Agent 等技术概念——输入自然语言（如"帮我拆分这个 Epic"、"把这个 Task 交给代码工程师做"），Engine 理解意图、调用合适的能力或调度 Crew 执行并实时反馈。

全局右下角提供快捷对话助手，作为同一对话面板的轻量入口（Home 不再提供独立对话入口，自由对话统一由快捷助手承载）。它不新增独立历史：快捷助手对话和 Studio 项目视图 Session 共享 `StudioSession`；在 Studio 中优先使用当前 Workspace，在其他页面发起的临时对话归属 `tmp-quick-chat` 临时 Workspace。快捷面板标题区下拉只用于选择已有历史，历史按 Workspace 分组并显示 Workspace 项目符号；`+` 新建时进入 `新对话` 草稿态，发送首条消息后自动从内容提取标题并锁定所选 Agent。

### 3.2 四种项目模式

Project/Epic/US/Task 是敏捷语境产物，不适用于所有场景。FocusPilot 提供四种模式，底层数据结构统一（树形 Markdown 节点），**模式定义：词汇表 + 层级规则 + AI 引导策略**。

#### 模式一：敏捷模式（Agile）— 软件开发

```
Project → Epic → User Story → Task
```
- 完整四级，AI 按敏捷方法论引导拆分（重规划引导）
- 适用：软件开发、复杂工程项目

#### 模式二：流程模式（Flow）— 阶段制项目

```
Project → Phase → Task
```
- 三级，Phase 是时序阶段，Task 按阶段推进
- 适用：大客户跟踪（调研→分析→跟进→复盘）、季度报告、产品发布

#### 模式三：轻量模式（Lite）— 简单项目

```
Project → Task
```
- 两级，规划引导可选，快速进出
- 适用：写一篇文章、处理一批数据、日常运维巡检

#### 模式四：自由模式（Free）— 自定义层级

```
Project → 自由嵌套 → Task
```
- 用户创建任意深度的目录结构，最底层叶子节点为 Task
- 中间层级 `type: group`（容器），叶子节点 `type: task`（可执行）
- 适用：学术研究、探索性项目、非标项目

**模式对比**：

| | Agile | Flow | Lite | Free |
|---|---|---|---|---|
| 层级 | 4 级固定 | 3 级固定 | 2 级固定 | 不限 |
| 适用 | 软件开发 | 阶段制项目 | 简单任务 | 非标项目 |
| 规划引导 | 重（敏捷方法论） | 中（阶段引导） | 轻（可选） | 开放式对话 |

**落地方式**：Project frontmatter 中 `mode` 字段决定模式。项目右键菜单可切换模式（仅影响后续创建行为，已有节点不动）。

### 3.3 Task 双轴管理

Task 的 frontmatter 通过 `status` + `scheduled_date` / `due_date` 形成**双轴管理**：

- `status` 管**执行生命周期**：待规划 → 待办 → 进行中 ⇄ 审核中 → 已完成（旁路 已阻塞）
- `scheduled_date` / `due_date` 管**时间安排**：驱动任务在时间轴上的定位

`schedule`（today / week / month / backlog）是 UI 派生字段（不持久化），由 `scheduled_date` / `due_date` 相对当前日期自动计算。过滤关系：`今日聚焦 ⊂ 本周计划 ⊂ 本月计划 ⊂ 全局规划`（侧边栏按执行优先自上而下排列：今日聚焦 → 本周计划 → 本月计划 → 全局规划）。

两者独立：一个 Task 可以 `status: todo` + `scheduled_date` 落在本周（UI 派生 `schedule: week`，本周要做、等待调度执行）。

| schedule 值 | 含义 | Dashboard 区域 |
|------------|------|---------------|
| `today` | 今日必做 | 🔥 今日待办 |
| `week` | 本周完成 | 📅 本周计划 |
| `month` | 本月目标 | 📆 本月目标 |
| `backlog` | 待排期 | 📥 Backlog |

**Task 创建规则**：每个 Task 必须有 Workspace。Project 是资产归属，可与 Workspace 独立；临时任务和 Git 远程任务可以只归属对应 Workspace，不强制挂到本地 Project。

| 入口 | 交互 | 归属项目 |
|------|------|---------|
| Dashboard / Studio 看板状态列标题栏 `+` | 输入内容 → 选择 Workspace（临时 / 本地项目 / Git 远程）→ 确认初始状态（从某列 `+` 创建时自动预选该列状态，否则默认待规划） | Workspace 必选，Project 可选 |
| Studio 项目视图 / Session 右面板创建 | 当前 Workspace 已确定，创建弹窗灰色只读展示当前 Workspace | 自动继承当前 Workspace |
| 项目树内右键创建 | 在某个项目/Epic/Phase 下创建 | 自动继承本地 Project Workspace |

无项目上下文的快捷对话不创建 Task，默认创建到 `tmp-quick-chat` 临时 Workspace。后续如从对话中派生任务，再按 Task 创建规则选择或继承 Workspace。

#### Studio 任务视图

Studio 任务视图把计划范围和视图模式拆成两条轴：侧边栏 Scope 决定 `今日聚焦 / 本周计划 / 本月计划 / 全局规划 / 执行中 / 等我决策 / 来源` 等范围和时间粒度（时间范围按执行优先自上而下排列，今日聚焦置顶，默认选中今日聚焦）；主区域顶部只保留一个低调的视图下拉，默认选中 `▦ 看板`。下拉菜单用灰色分组标题隔开，上方为 `执行视图`（`▦ 看板 / 田 泳道 / ☰ 列表`），下方为 `规划视图`（`▱ 时间轴`）。顶部保留 `目标` 筛选，并把旧 `来源` 改为组合 `筛选` 入口：一级栏目为 `项目 / Agent / 优先级 / 标签 / 负责人 / 创建者`，二级选项支持多选，栏目内 OR、栏目间 AND，一级栏目显示已选数量，并同步作用于时间轴、看板、列表和泳道；时间范围不在顶部重复出现。切换视图模式不改变当前 Scope。看板主甬道固定显示为：待规划 / 待办 / 进行中 / 审核中 / 已完成 / 已阻塞；Task 卡片底部最后一行显示所属 Workspace 名称，便于跨项目扫描；卡片可拖到其他状态列，drop 后只改变任务状态。分组控件不再挂在全局工具栏，而是**内嵌于各视图自身头部**（统一形态：`分组方式` 文字标签 + 扁平下拉），因此切换视图时全局工具栏（视图下拉 / 目标 / 筛选）布局保持稳定。泳道采用参考 Multica 的**整行横幅**布局：顶部一行为状态列表头，每个分组各占一整行横幅（横跨所有状态列，含折叠箭头 + 名称 + 计数），横幅下方卡片按状态列排布，**点击整行横幅即可折叠/展开**，横幅左侧拖拽柄（⠿）**可上下拖动调整分组顺序**（参考 Multica，自定义顺序按分组维度记忆）；泳道头部提供 `▤ Workspace / ◉ 执行 Agent / ↳ 父级任务 / ◎ 负责人` 分组下拉；Workspace 分组时 drop 后同步改变任务归属与状态，Agent / 父级任务 / 负责人分组时分别同步对应字段与状态。列表模式头部同样提供分组下拉（`◉ 按状态 / ▱ 按目标 / ▤ 按项目 / ◈ 执行 Agent / ◎ 负责人`，**默认按状态**），采用单表格单列头（列标题只在最顶显示一次、不在每组重复），分组以整行标题分隔、可点击三角（已放大）折叠/展开，**分组标题前提供勾选框**实现该组全选/取消（部分选中显示 indeterminate），**顶部列头行提供总全选框**（全部可见全选）；列表还提供行首每行复选框、已选计数，并支持批量修改状态、优先级、负责人和删除。时间轴分组下拉为 `▤ 按项目 / ▱ 按目标`，**默认按项目**，按项目时每个项目行可折叠/展开。各视图均以 `+` 就地新建并带入对应上下文：看板各状态列 `+`（预选该列状态）、泳道每个「分组×状态」单元格底部 `+`（预选分组维度值 + 状态）、列表每个分组头 `+`（预选分组维度值）。看板视图无分组控件。

**时间轴：四级同构甘特**

时间轴视图统一采用「左侧任务列表 + 右侧甘特时间轴」布局，四种模式按时间粒度递进：

| 侧边栏选择 | 展示模式 | 甘特列 |
|---|---|---|
| 全局规划 | 目标树 + 月级甘特 | 月列 |
| 本月计划 | 目标树 + 周级甘特 | 周列(4~5) |
| 本周计划 | 按天分组 + 天级甘特 | 天列(7) |
| 今日聚焦 | 任务列表 + 小时级甘特 | 小时列(10) |

时间轴默认按目标树展示；切换为 `▤ 按项目` 后以 Workspace/项目为行轴，右侧仍使用同一甘特时间轴定位任务，用于跨项目查看同一计划范围内的排期分布。

**本月计划过滤规则**：按日历月过滤，显示 `goal.month = 当前月` 的任务 + 未关联目标中 `schedule ∈ {today, week, month}` 的任务。非当月目标容器及其任务整体隐藏。

**任务管理能力**：任务详情面板支持字段内联编辑（状态/优先级/标签/安排/执行 Agent/归属目标，点击就地弹下拉，标签为多值可加删）与删除（二次确认）；看板/泳道/列表三视图均支持**同状态（同分组）内拖拽调整卡片顺序**（跨列拖拽仍改状态/分组）。详见 [04-studio §7.4 / §6 视图](fp-ui/04-studio.md)。

### 3.4 Crew 数字团队

Crew 是 FocusPilot 的核心交互概念——**用户不直接面对 Agent/MCP/Skill 等技术概念，而是管理一个"数字团队"**。

参考 Multica 的 Runtime/Agent 设计，FocusPilot 将 Crew 成员和 Runtime 分离：

- **CrewMember**：面向用户的数字成员，定义角色、职责、技能、授权、并发和长期指令。
- **CrewRuntime**：成员背后的执行环境，定义本地/云端、Provider、CLI/daemon、心跳、模型发现和可见性。
- **CrewRun**：一次执行记录，连接动态 Task、Skill、Runtime、配置快照、执行日志和 Focus 项目定位。

一个 Crew 成员必须绑定一个 Runtime；一个 Runtime 可以服务多个成员。用户主要管理“团队成员”，但 AICrew 必须展示 Runtime 健康和绑定关系，避免把执行环境隐藏成不可诊断的字符串。

每个 Crew 成员 = 一个配置好的 Agent 角色 + 一个绑定的 Runtime：

| 属性 | 说明 |
|------|------|
| 角色名 | 如"代码工程师"、"数据分析师"、"架构师" |
| 头像 | 可自定义 |
| Owner / 可见性 | 私有成员或当前工作区成员 |
| 擅长领域 | 描述文本，影响 AI 任务分配 |
| Runtime 绑定 | 绑定到本地或云端执行环境 |
| 模型 / 推理强度 | 默认跟随 Runtime/CLI，可按成员覆盖 |
| Instructions / Skills | 成员长期指令和可用技能 |
| Env / Args / MCP JSON | 成员级高级执行配置；secret 默认隐藏 |
| 绑定 MCP Server | 底层实际调用的 AI 工具 |
| 部署位置 | 本地 / 云端 |
| 常驻职责 | 周期性任务（cron / event 触发） |
| 并发上限 | 单成员最大同时执行任务数 |
| 运行状态 | availability: online / unstable / offline；workload: idle / queued / working |
| 运行统计 | 最近 30 天运行次数、成功次数、失败次数、成功率、平均耗时 |
| 最近工作 | 最近执行的 CrewRun 列表，可跳转 Focus Task 或查看记录 |

每个 CrewRuntime 至少包含：

| 属性 | 说明 |
|------|------|
| Provider | Claude Code / Codex CLI / Gemini / Kimi / 自定义 runtime |
| Runtime mode | local / cloud |
| 可见性 | private / public，用于控制是否可被其他成员绑定 |
| Owner | Runtime 所属用户或设备 |
| daemon id / CLI version | 用于诊断本地 daemon 与命令行版本 |
| launch header | Runtime 启动命令摘要，只展示安全摘要 |
| last seen / heartbeat | 用于判断 Runtime 健康 |
| health | online / recently_lost / offline / about_to_gc |
| supported models / thinking | Runtime 可发现的模型和推理强度能力 |

每个 CrewRun 至少包含：

| 属性 | 说明 |
|------|------|
| Crew 成员 | 哪个数字成员执行 |
| Runtime / Host | 由哪台本机或远程节点上的哪个执行器执行 |
| Focus Project / Task | 对应项目和 Task，支持回跳定位 |
| Skill | 本次实际使用或主要关联的 Skill |
| status | running / success / failed / cancelled |
| started_at / ended_at / duration | 开始、结束、耗时 |
| tool_call_count / event_count | 工具调用数和事件数 |
| config_snapshot | 运行开始时的实际配置快照 |
| log_path | 详细执行日志位置 |
| output_refs | 产物、评论、文件或报告引用 |

**V1 预置 Crew 成员**：
```
🧑‍💻 代码工程师     — claude-code, 本地
```

**用户可自定义添加（预留）**：
```
📊 数据分析师     — research-agent, 云端
✂️ 剪辑专家       — video-agent, 云端
📝 内容编辑       — writing-agent, 云端
🏗️ 架构师         — architect-agent, 本地
```

**Crew 成员的两种任务**：

| 任务类型 | 来源 | 触发方式 |
|---------|------|---------|
| 项目 Task（一次性） | 用户在对话面板中派遣，或从 Kanban 拖拽分配 | 手动 / 拖入「待办」自动调度 |
| 常驻职责（周期性） | 用户在 Crew 成员详情页配置 | cron 定时 / 事件触发 |

**AICrew 侧边栏**：

侧边栏分"智能体成员"和"Runtime"两个 Tab 切换。操作按钮放在各 Tab 列表下方：

- 智能体成员 Tab：展示团队成员列表（状态点、角色名、Runtime 绑定、部署位置）；列表下方"+ 新建智能体"按钮和模板入口
- Runtime Tab：按本机 / 远程节点 / 云端分组展示执行节点；列表下方"+ 添加执行节点"按钮

点击智能体成员时，工作区切到该成员详情；点击 Runtime 中的机器时，工作区切到该执行节点详情。

**新建智能体弹窗**（个人版）：

点击"+ 新建智能体"或模板行打开弹窗，包含：头像占位（可选 emoji）+ 名称（必填）+ 描述（255 字限制）+ 运行时 select + 模型 select（默认"跟随 Runtime"）+ 指令 textarea（默认收起，可展开）。个人版不展示可见性选项（Owner/可见性归后续多人/团队版）。名称为空时禁止创建并高亮输入框。创建后在侧边栏插入一条草稿成员行（"草稿"pill + offline 状态点），弹窗关闭并重置表单。

**智能体成员工作区**（三个 Tab）：

- **概览**（默认）：展示 Hero 卡片（头像+成员名+Runtime 摘要+在线状态+查看记录）、状态网格（30 天运行次数/成功率/平均耗时/当前负载）、7 天活动柱状图（可点击联动最近工作列表）、当前工作和最近工作
- **Tasks**：展示该成员关联的 Focus Task，Multica 紧凑列表风格，按状态分组（进行中 / 待办 / 待规划 / 已完成），点击行直接跳转 Focus 看板并打开对应 Task 详情面板（重置筛选为"全部" → 切看板 → 定位卡片高亮 → `renderFocusTaskDetail` 渲染完整详情内容 → 打开详情）
- **配置**：采用子 Tab 切换（基础信息 / 指令 / Skill / MCP / 环境变量 / 自定义参数），各子 Tab 展示对应配置项。Env secret 必须显式 Reveal 后才可编辑；MCP Server 展示 connected / authorized / local / pending_auth / disabled 状态；常驻职责支持 event / cron / manual 三类触发规则

**Runtime 工作区**（单页执行端监控，无顶部 Tab）：

Runtime 背后由 daemon 进程负责自动扫描本机 CLI、读取环境配置、维护健康度和日志，UI 只展示状态和操作控制，不暴露 Env / Args / MCP 等编辑配置（高级配置留给 Settings）。

- **Runtime Header**：节点名 + 状态摘要 + daemon 版本 + 最后心跳 + 操作按钮（View logs / Restart / Stop）。Stop 为危险操作，需确认；停止后隐藏 Restart 仅保留 Start，恢复 online 后重新显示 Restart / Stop
- **执行器表格**：4 列精简（执行器 / 健康度 / 智能体 / 工作负载）。远程节点未连接时整页显示单一空状态
- **Daemon 日志区**：内联展示，支持刷新。View logs 按钮滚动到此区域

**运行记录**：展示 CrewRun 详情、事件时间线、工具调用、配置快照、日志复制和筛选

**crewState 统一状态管理**：AICrew 页面通过统一的 `crewState` 驱动侧边栏选中、工作区面板切换和面包屑路径同步。`crewState` 记录当前对象类型（智能体成员 / Runtime）、选中的成员或执行节点、当前活跃的工作区 Tab，确保侧边栏切换与工作区联动一致

**AICrew 定位跳转规则**：

- 点击 Task 标题或 Focus 编号，切换到 Focus 页面并选中对应项目节点。
- 点击最近工作整行，打开 CrewRun 详情。
- 点击最近工作中的外跳图标，定位到对应 Focus Task。
- 点击“查看记录”，打开完整运行记录列表或当前 CrewRun 详情。
- 点击成功次数或成功率，打开运行记录列表并过滤 `status=success`。
- 点击 Skill 或 Skill 成功次数，切换到 Skills 详情或过滤该 Skill 的运行记录；记录中的 Task 仍可回跳 Focus。

**运行配置边界**：

- 本机配置：V1 自动检测本机所有可见 Runtime、CLI 版本、daemon 心跳、执行器、Env key、Args、MCP 配置摘要和工作目录摘要。
- 远程节点：不从本机扫描远程磁盘，只展示远程 daemon 主动上报、用户手动添加或历史连接留下的 Runtime 信息。
- 云端 Runtime：V1 只保留分组和空状态，不提供真实执行。
- secret value 不在列表、记录和远程上报中明文展示；只展示 key、key count、redacted 状态和授权状态。

V1 中常驻职责先完成配置与展示，后台定时/事件调度由 Scheduler 后续接入。

V1 默认只展示预置 `代码工程师` 一个真实智能体成员；架构师、数据库工程师、数据分析师作为”新建智能体”模板出现。侧边栏智能体成员/Runtime 双 Tab、成员工作区三 Tab（概览/Tasks/配置）、Runtime 工作区单页监控（Header + 执行器表格 + Daemon 日志）、crewState 统一状态管理和运行记录先完成 UI 壳、本机静态配置与历史记录结构；daemon 自动发现、模型实时同步、Runtime CLI 升级、Runtime GC、远程磁盘扫描和云端执行后续接入。

**用户始终面对"团队管理"这个隐喻，不需要理解底层技术。**

### 3.5 项目产出模型与知识管道

#### 3.5.1 项目的通用产出结构

所有项目都交付产物，同时积累知识沉淀。每个层级都可包含：

```
任意层级/
├── task-*.md              ← Task（可执行单元）
├── _materials/            ← 原始素材（文章/PDF/笔记/数据/会议记录）
├── _kb/                   ← 知识卡片（从素材和报告中提炼的原子化要点）
└── _reports/              ← 增量整合报告（AI 持续加工的综合文档）
```

| 产出类型 | 说明 | 生成方式 |
|---------|------|---------|
| 交付物 | 代码/视频/PPT/设计稿等外部产物 | Task 执行产出 |
| _materials/ | 原始输入素材 | 人手动放入 + Crew 自动收集 |
| _kb/ | 知识卡片（极简要点，可同步 Anki） | AI 从 materials + reports 中提炼 |
| _reports/ | 增量整合报告 / 章节 / 完整书籍 | AI 持续加工，每次新素材融入后更新 |

#### 3.5.2 知识管道（Knowledge Pipeline）

知识管道定义了从原始素材到内化智慧的完整加工链路：

```
收集           加工             提炼            记忆              内化
─────         ─────           ─────          ─────            ─────
_materials/  →  _reports/    →  _kb/        →  Review         →  智慧
原始素材         增量整合报告      知识卡片        间隔重复           费曼验证/场景应用
Crew 自动抓取    对话+Task        极简要点        今日复习队列       理解→应用
人手动放入       持续融入         框架记忆法       可选同步 Anki
```

**五个阶段**：

| 阶段 | 说明 |
|------|------|
| **收集**（_materials/） | 人手动放入 + Crew 自动抓取 + 对话产生。新素材标记"待整合" |
| **加工**（_reports/） | 增量整合，每次新增素材 AI 融入现有报告。每层级各有章节报告 |
| **提炼**（_kb/） | 从 reports 提炼原子化知识卡片，可选同步到 Anki（AnkiConnect API） |
| **记忆**（Review 今日复习） | 遵循遗忘曲线形成今日复习队列，用“忘了 / 模糊 / 记得 / 熟练”四档反馈更新记忆强度 |
| **内化**（Review 内化挑战） | 通过费曼复述和场景应用评估理解迁移，标记内化程度（未内化→能解释→能应用→已融会） |

**KB 卡片格式**：

```yaml
---
type: kb-card
source: _reports/chapter-1.md
tags: [分布式, CAP]
anki_deck: "分布式系统"
anki_synced: false         # 可选外部同步，不是主复习流程
memory_strength: fuzzy     # forgot → fuzzy → remembered → fluent
internalization_level: none # none → explain → apply → internalized
is_key: false              # 关键卡由 AI 推荐，用户确认或覆盖
---
## CAP 定理
**口诀**：一致可用分区，三选二
**类比**：像三个人传话，要么慢(C)，要么可能传错(A)，但电话线断了(P)总会发生
**费曼检验**：能否用一句话给外行解释 CAP？
**场景应用**：在一个真实系统设计里说明分区发生时牺牲哪一侧，以及如何恢复。
```

#### 3.5.3 自动收集 + 一键同步

**Crew 常驻职责负责自动收集**，Today Dashboard 提供一键同步入口：

```
Crew 常驻职责（定时收集）           用户（每日 Review）
──────────────────              ─────────────────
定时抓取行业资讯、汇总消息          用户打开 Today Dashboard
拉取业务指标                       看到：📥 3 条新素材待整合
  → _materials/（自动）             点击「同步整合」→ Engine 触发加工链：
                                   1. 新 materials → 融入 _reports/
                                   2. 从新内容提炼 → _kb/ 卡片
                                   3. 新卡片 → 同步 Anki
```

**同步模式可配置**：
- `auto_sync: false`（默认）：Crew 收集后等待用户手动点「同步整合」
- `auto_sync: true`：收集完自动触发加工链，用户只需 review 结果

### 3.6 Dashboard 驾驶舱

主面板活动栏点击 📁 项目图标时，默认展示 Dashboard 驾驶舱：

```
┌─ Dashboard ──────────────────────────────────────────┐
│                                                       │
│ 🔥 今日待办 (4/7)                        [+ 新建任务] │
│ ┌─────────────────────────────────────────────────┐  │
│ │ ☐ 实现 frontmatter 解析    FocusPilot V1   [执行]  │  │
│ │ ☐ 生成客户画像             大客户跟踪     [执行]  │  │
│ │ ─ ─ ─ ─ ─ ─ 已完成 ─ ─ ─ ─ ─ ─                 │  │
│ │ ☑ JWT 认证实现             FocusPilot V1   8min ✓  │  │
│ └─────────────────────────────────────────────────┘  │
│                                                       │
│ 📅 本周计划 (12/20)                  W14 进度 60%     │
│ ┌─────────────────────────────────────────────────┐  │
│ │ ▸ FocusPilot V1        5/8 Task    ██████░░ 63%  │  │
│ │ ▸ 大客户跟踪          4/6 Task    ████████ 67%  │  │
│ └─────────────────────────────────────────────────┘  │
│                                                       │
│ 📆 本月目标 (April)                                   │
│ 📥 Backlog (15)              📥 待整合素材 (3) [同步] │
└───────────────────────────────────────────────────────┘
```

**数据来源**：
- 🔥 今日待办 = 所有 `schedule: today` 的 Task（跨项目汇总）
- 📅 本周计划 = 所有 `schedule: week` 或 `schedule: today` 的 Task，按项目分组
- 📆 本月目标 = 所有 `schedule: month` 的项目级目标
- 📥 Backlog = 所有 `schedule: backlog` 的 Task
- 📥 待整合素材 = Pipeline 中 `status: new` 的 materials

**快速操作**：
- Backlog 中拖拽到今日 → `schedule: backlog → today`
- 今日 Task 完成 → 自动归入已完成区域，`status: done`
- 点击项目名 → 跳转到项目树视图
- 点击 [执行] → 调度 Crew 成员执行

### 3.7 主面板（VS Code 风格）

```
┌──┬─────────┬───────────────────────────────────────┐
│  │         │                                        │
│📁│ 项目树   │  ┌─ Kanban ──────────────────────────┐ │
│  │ ▾ 项目A  │  │ Ready │ Executing │ Done │ Blocked│ │
│  │ ▾ 项目B  │  │       │           │      │        │ │
│📋│ ▸ 项目C  │  └────────────────────────────────────┘ │
│  │         │                                        │
│  │         │  ┌─ 对话面板 ─────────────────────────┐ │
│👥│         │  │ > 帮我把这个 Epic 拆成 US            │ │
│  │         │  │ < 建议分 3 个 US：登录/注册/权限...  │ │
│💬│         │  └─────────────────────────────────────┘ │
│  │         │                                        │
│⚙️│         │                                        │
└──┴─────────┴───────────────────────────────────────┘
 ↑      ↑                       ↑
活动栏  侧边栏                 主内容区
```

**活动栏**：

| 图标 | 功能 | 侧边栏内容 |
|------|------|-----------|
| 📁 | 项目 | 项目树（四模式展示）+ Today Dashboard 入口 |
| 📋 | Kanban | 按状态分列的全局看板（跨项目） |
| 👥 | Crew | 智能体成员 / Runtime 双 Tab + 成员状态 + 执行节点 |
| 💬 | 对话 | 历史对话记录列表 |
| ⚙️ | 设置 | 偏好 / 数据目录 / 主题 / Crew 管理 |

**交互逻辑**：
- 点击活动栏图标切换侧边栏内容
- 侧边栏选中节点 → 主内容区联动
- 对话面板始终可用（底部固定或可折叠），针对当前选中上下文对话

#### 3.7.1 项目树按模式展示

**Agile**：
```
▾ 📁 FocusPilot V1                      [backlog]
    ▾ 🎯 Epic: Engine 基础架构          [todo]
        ▾ 💼 US: 项目引擎               [in_progress]
            📄 Task: frontmatter 解析    [done ✓]
            📄 Task: 目录扫描            [in_progress 🔄]
```

**Flow**：
```
▾ 📁 Q2 大客户跟踪                     [in_progress]
    ▸ 📊 Phase 1: 数据收集     ████████░░ 80%
    ▾ 📊 Phase 2: 分析报告     ██░░░░░░░░ 20%
        📄 拉取 CRM 数据                 [done ✓]
        📄 生成客户画像                   [in_progress 🔄]
```

**Lite**：
```
▾ 📁 重构登录模块                       [in_progress]
    📄 分析现有代码                       [done ✓]
    📄 实现 JWT 认证                     [in_progress 🔄]
```

**Free**：
```
▾ 📁 学术论文                           [backlog]
    ▾ 📂 文献综述
        📄 搜索相关论文                   [done ✓]
    ▾ 📂 实验
        ▾ 📂 实验设计
            📄 定义变量                   [todo]
```

#### 3.7.2 Crew 侧边栏

侧边栏使用"智能体成员 / Runtime"两个 Tab 切换，避免把"人"和"机器"平铺在同一列表里。

智能体成员 Tab：
```
┌─ 👥 AICrew ─────────────────────┐
│ [智能体成员] [Runtime]            │
│                                  │
│ 🟢 代码工程师        本地         │
│    claude-code · 空闲            │
│                                  │
│ [+ 新建智能体]                   │
│                                  │
│ 模板                             │
│ 架构师 / 数据库工程师 / 数据分析师 │
└──────────────────────────────────┘
```

Runtime Tab：
```
┌─ 👥 AICrew ─────────────────────┐
│ [智能体成员] [Runtime]            │
│                                  │
│ 本机                             │
│ 🟢 MacBook-Pro-10.local     5   │
│                                  │
│ 远程节点                         │
│ 🔴 remote-dev-01            0   │
│                                  │
│ [+ 添加执行节点]                 │
└──────────────────────────────────┘
```

选中智能体成员时，工作区切到该成员详情（概览 / Tasks / 配置三 Tab）；选中 Runtime 执行节点时，工作区切到该节点单页监控（Runtime Header / 执行器表格 / Daemon 日志）。

### 3.8 Quick Panel（升级）

Quick Panel 定位不变——快速一瞥，不做深度操作。

```
V4.3 三 Tab                     FocusPilot
─────────                       ─────────
[活跃] [关注] [AI]               [活跃] [关注] [聚焦]
  ↓      ↓     ↓                  ↓      ↓      ↓
 本地   本地  CoderBridge         本地   本地   Engine
```

- **活跃/关注 Tab**：不变（详见 [PRD-v4-legacy.md §3.2](archive/PRD-v4-legacy.md)）
- **聚焦 Tab（替代 AI Tab）**：展示 Dashboard 精华摘要

```
Quick Panel（hover 弹出）
┌─ [活跃] [关注] [聚焦] ──────────┐
│                                  │
│ 🔥 今日 (3 剩余)                 │
│   ☐ frontmatter 解析  FocusPilot  │
│   ☐ 客户画像         大客户      │
│   ☐ 审阅 PR #18     FocusPilot   │
│                                  │
│ 📅 本周 12/20       60% ████░░  │
│                                  │
│ 🔄 执行中 (1)                    │
│   客户画像  ████░░ 60%  2min    │
│                                  │
│ 📥 待整合 (3)                    │
└──────────────────────────────────┘
```

**Quick Panel vs 主面板 Dashboard 分工**：

| | Quick Panel 聚焦 Tab | 主面板 Dashboard |
|---|---|---|
| 触发 | hover 悬浮球 / 单击 | 双击悬浮球 / Dock 图标 |
| 信息量 | 今日 3-5 条 + 本周进度条 + 执行中 | 完整四维（今日/周/月/Backlog）|
| 操作 | 只看（点击跳转到主面板） | 创建/拖拽/执行/同步 |
| 定位 | 快速确认"现在该做什么" | 完整的工作规划和管理 |

### 3.9 自动日志

Engine 后台自动记录每次状态变更，每日归档为 Markdown 文件：

```
{projects_dir}/_logs/
├── 2026-04-01.md
├── 2026-04-02.md
├── runs/
│   └── run_tes12_20260529_1913.jsonl
└── weekly/
    └── 2026-W14.md     # 自动周报（预留）
```

日志内容自动生成，无需用户操作：

```markdown
---
date: 2026-04-02
tasks_completed: 3
tasks_created: 2
agent_runs: 4
---
## 完成
- [FocusPilot V1] frontmatter 解析 — Agent: claude-code, 耗时 8min

## 新增
- [FocusPilot V1] WebSocket 推送 (schedule: week)

## Agent 执行摘要
- claude-code #session-42: 实现了 frontmatter.py，新增 3 个文件
- crew_code_engineer run_tes12_20260529_1913: TES-12 成功，耗时 7m18s，69 次工具调用

## 知识管道
- 3 条新素材已收集
- 2 张 KB 卡片已同步到 Anki
```

**设计要点**：完全自动生成，Markdown 格式 Git 可追踪，跨项目汇总，为 AI 提供"项目记忆"。每日 Markdown 记录摘要，`_logs/runs/` 保留 CrewRun 事件流，供 AICrew 的“查看记录”打开完整执行日志。

### 3.10 现有桌面功能（保留）

以下功能从 V4.3 内部开发版继承，保持现有行为不变。详细规格参见 [PRD-v4-legacy.md](archive/PRD-v4-legacy.md)（V4.3 参考文档），后续按需迁移到本文档。

| 功能 | 参考 | 说明 |
|------|------|------|
| 悬浮球 | PRD-v4-legacy.md §3.1 | 常驻入口，拖拽吸附，贴边半隐藏，AI 角标 |
| 快捷面板（活跃/关注 Tab） | PRD-v4-legacy.md §3.2 | hover 弹出，钉住模式，App/窗口快切 |
| 主看板（关注管理+偏好设置） | PRD-v4-legacy.md §3.3 | 双击悬浮球/Dock 图标进入 |
| 全局快捷键 | PRD-v4-legacy.md §3.4 | ⌘⇧B 显示/隐藏（可自定义） |
| FocusByTime 番茄钟 | PRD-v4-legacy.md §3.5 | 专注计时，引导休息，悬浮球进度环 |
| AI Tab（Coder-Bridge） | PRD-v4-legacy.md §3.6 | AI 编码会话管理，窗口绑定 |
| 辅助功能权限 | PRD-v4-legacy.md §3.7 | AX API 权限检测与引导 |

**升级说明**：悬浮球 Agent 角标将从"AI 会话数"扩展为"执行中 Task 数"，不区分项目模式。

### 3.11 悬浮球新形态（设计原型）

新形态在 [`docs/fp-ui/floating-ball-options-prototype.html`](fp-ui/floating-ball-options-prototype.html) 中迭代，已收敛以下设计决策：

- **Doubao 式 hover 浮层**：移入自动展开、移走延迟收起、点击浮球切换展开。菜单收束为三项一级入口：`实时状态`、`今日聚焦`、`本周计划`（番茄钟不再单列，已并入 Focus Bar）。
- **全局快捷聊天助手**：面向全部项目 / Workspace / 运行状态，不默认绑定当前任务，仅提供范围筛选。
- **Focus Bar（实时状态）**：菜单「实时状态」打开整页浮出的状态条，条内可点 × 关闭。状态项按 `待规划 · 进行中 · 审核中 · 已完成 ┃ 今日聚焦` 分组（执行流水在前、聚焦在后，中间分隔符），各状态用不同颜色标记、数字放大；每组 hover 下拉列任务。状态词汇与 §3.1.x 看板 6 态（待规划/待办/进行中/审核中/已完成/已阻塞）对齐。
- **番茄钟入栏**：Focus Bar 右侧承载番茄钟。待命态显示「开始专注 / 休息」双按钮（分别弹方案弹窗，选完即开始，不自动弹引导步骤）；专注中点状态块弹「停止 / 暂停」，休息中点状态块弹当前休息动作 + 暂停/停止；点弹窗外空白处自动关闭。
- **任务详情卡片**：状态条分组、菜单二级列表点任意任务，统一右下角浮出**悬浮卡片**（非全屏抽屉，不接管整屏、点外部即关），内容与主看板任务详情一致（标题+状态、运行块、任务描述、执行轮次时间线、属性 chip 条），不再二次跳转 Studio。
- **任务字段内联编辑**：详情卡片的属性 chip 条中，`状态 / 优先级 / Agent / 调度 / 评估` 可点击就地弹下拉修改，状态遵循看板 6 态流转（待规划/待办/进行中/审核中/已完成/已阻塞，与 00-layout `taskStatusDefs` 一致）；系统自动流转（启动→进行中、完成→审核中）与手动修改走同一套机制。每个可枚举字段以 `{ key → label }` 模型驱动，存储 key 而非展示串。

---

## 4. 数据模型

### 4.1 项目数据目录

```
{projects_dir}/                  # 可配置，默认 ~/.pilotone/projects/
├── work/
│   └── MyProject/
│       ├── _project.md          # frontmatter: type/status/tags/mode
│       ├── _materials/          # 项目级原始素材
│       ├── _kb/                 # 项目级知识卡片
│       ├── _reports/            # 项目级综合报告
│       ├── epic-auth/
│       │   ├── _epic.md
│       │   ├── _materials/
│       │   ├── _kb/
│       │   ├── _reports/
│       │   ├── us-login/
│       │   │   ├── _us.md
│       │   │   ├── task-api.md
│       │   │   └── task-ui.md
│       │   └── us-oauth/
│       │       └── _us.md
│       └── ...
├── _logs/                       # 自动日志（跨项目）
└── tech/
    └── ...
```

### 4.2 Frontmatter 数据契约

**Project 级别**：

```yaml
---
type: project
mode: agile              # agile / flow / lite / free
status: backlog          # backlog → todo → in_progress ⇄ in_review → done / blocked
priority: normal         # low / normal / high / urgent
tags: [backend, auth]
created_date: 2026-04-01
pipeline:
  auto_collect: false
  auto_sync: false
  anki_deck:
---
```

**Task 级别**：

```yaml
---
type: task
status: todo
schedule: today          # today / week / month / backlog
priority: normal
tags: [backend]
created_date: 2026-04-01
code_path:               # 关联代码仓库路径（可选）
parent_project:
skill:                   # 默认根据上下文推断
agent:                   # 默认用首选 Agent（执行 Agent；留空=手动卡片）
---
把登录接口从 session 改为 JWT，保持向后兼容
```

**执行策略字段说明**：
- `skill` / `agent` 不填时，Engine 按默认策略推断；`agent` 留空 = 手动卡片、不自动调度
- **自动执行靠"拖入「待办」"触发**（取代原 `auto_execute` 字段）：配了执行 Agent 的任务拖到「待办」即被中央扫描器调度（见 04-studio §3）
- 遵循「克制」原则：默认覆盖 90% 场景，高级用户可通过 frontmatter 精确控制

**Task 不是"代码指令"，而是"意图指令"**：

| 场景 | Task 内容 | Skill | Agent | 产物 |
|------|----------|-------|-------|------|
| 写代码 | "把登录改成 JWT" | code-execute | claude-code | 代码 PR |
| 写报告 | "分析大客户 Q1 数据" | report-generate | research-agent | Markdown 文档 |
| 运维监控 | "检查 API 延迟" | ops-check | ops-agent | 状态报告 |
| 信息收集 | "汇总本周飞书消息" | data-collect | msg-agent | 摘要文档 |

### 4.3 与 VaultOne 的关系

FocusPilot 脱离 Obsidian 依赖，Engine 内建 Markdown 项目引擎。用户可将数据目录指向 `~/Workspace/1-Vault/1-Focus/`，此时：
- Engine 直接读写 Vault 文件（frontmatter 格式兼容 VaultOne 数据契约）
- Obsidian 可同时打开同目录浏览笔记（只读共存）
- Engine 不依赖 Obsidian REST API 运行

---

## 5. Agent Engine

### 5.1 整体架构

```
┌─────────── Agent Engine (Python) ─────────┐
│                                            │
│  项目引擎    MCP Host    任务调度   技能系统 │
│  md CRUD    Agent 编排   定时/事件  可扩展   │
│  frontmatter 多工具调度  执行队列   内置模板 │
│                                            │
│  Gateway API: FastAPI REST + WebSocket     │
│  端口: localhost:19840                      │
└────────────────────────────────────────────┘
```

### 5.2 项目引擎（Project Engine）

**职责**：Markdown 项目数据的 CRUD、解析、监听、搜索。

**对外接口**：
```
GET    /api/projects                    # 项目树（递归扫描）
GET    /api/projects/{path}             # 单个节点详情
POST   /api/projects/{path}            # 创建节点
PATCH  /api/projects/{path}            # 更新 frontmatter 字段
DELETE /api/projects/{path}            # 删除节点
WS     /api/events                     # 文件变更 + Agent 进度实时推送
```

### 5.3 MCP Host（Agent 编排）

**职责**：接收 Task 执行请求，选择并调度 MCP Server（AI 工具），监控执行进度。

**对外接口**：
```
GET    /api/agents/servers              # 已注册 MCP Server 列表
POST   /api/agents/execute              # 执行 Task
GET    /api/agents/sessions             # 活跃会话列表
GET    /api/agents/sessions/{id}        # 会话详情
POST   /api/agents/sessions/{id}/stop   # 终止会话
```

**执行流程**：
1. UI 发送 `POST /api/agents/execute {task_path, skill}`
2. Orchestrator 读取 Task markdown，提取上下文
3. 从 Registry 选择 MCP Server（V1 默认 claude-code）
4. 通过 MCP 协议启动 Agent 会话
5. 实时通过 WebSocket 推送进度事件
6. 完成后 PATCH Task frontmatter：`status: in_progress → in_review`（人工确认通过后 → done）

**与现有 coder-bridge 的关系**：
- V1 初期：coder-bridge 保留兼容，Engine 新增 MCP 通道
- 后续迁移：coder-bridge 逐步替换为 MCP 协议

### 5.4 任务调度器（Scheduler）

**职责**：管理任务执行的触发、排队、记录。

**存储**：SQLite `~/.pilotone/scheduler.db`

**V1 scope**：仅支持 `immediate` 触发 + 执行记录查询。`cron` 和 `event` 触发为云端预留。

### 5.5 技能系统（Skill System）

**职责**：可扩展的任务执行模板，定义如何将 Task 转化为 Agent 指令。

```
~/.pilotone/skills/
├── builtin/
│   ├── code-execute/              # 代码执行
│   │   ├── manifest.json
│   │   └── prompt.md
│   └── project-manage/            # 项目管理操作
└── custom/                        # 用户自定义技能（预留）
```

**V1 scope**：仅实现 `code-execute` 和 `plan-decompose` 两个内置技能。

### 5.6 知识管道编排（Pipeline）

**职责**：编排多个 Skill 的执行顺序，形成完整加工链。一键「同步整合」= 触发一条 pipeline。

**对外接口**：
```
POST   /api/pipeline/sync           # 触发同步整合
GET    /api/pipeline/status          # 当前 pipeline 执行状态
GET    /api/pipeline/pending         # 待整合素材列表
POST   /api/pipeline/anki-sync      # 手动触发 Anki 同步
```

### 5.7 Dashboard API

```
GET    /api/dashboard/today          # 今日待办
GET    /api/dashboard/week           # 本周计划
GET    /api/dashboard/month          # 本月目标
GET    /api/dashboard/backlog        # Backlog 列表
PATCH  /api/dashboard/reschedule     # 调整时间维度
```

---

## 6. macOS App 集成

### 6.1 三层 UI 职责分离

```
悬浮球 + Quick Panel  → 快速一瞥（窗口切换 / 今日聚焦 / Agent 角标）
主面板                → 深度操作（项目管理 / Kanban / Crew / 对话）
```

- **悬浮球 + Quick Panel**：保留现有全部功能，不做改动
- **主面板**：从"关注管理 + 偏好设置"升级为 VS Code 风格多功能面板

### 6.2 Engine 进程管理（EngineManager）

FocusPilot 负责 Engine 的完整生命周期：

**启动流程**：
1. 定位 Engine 二进制（开发期 `uvicorn`，发布期 `.app/Contents/Resources/engine/`）
2. 启动子进程，绑定 `localhost:19840`
3. 健康检查轮询 `GET /api/health`（间隔 1s，超时 30s）
4. 连接 WebSocket `/api/events`

**退出流程**：发送 SIGTERM → 等待 5s → SIGKILL

**崩溃恢复**：自动重启最多 3 次，窗口管理/番茄钟不受影响（纯本地功能）。

### 6.3 通信架构

```
FocusPilot (Swift)
    │
    ├── HTTP  → localhost:19840/api/*    请求-响应：项目CRUD、Agent操作
    ├── WS    → localhost:19840/api/events  实时推送：文件变更、Agent进度
    │
    └── 本地功能不经过 Engine：
        ├── WindowService      窗口枚举/前置
        ├── AppMonitor         App 运行监控
        ├── FocusTimerService  番茄钟
        ├── HotkeyManager      全局快捷键
        ├── FloatingBallView   悬浮球交互
        └── ConfigStore        偏好设置
```

---

## 7. 部署架构

### 7.1 本地部署（V1 实现）

```
FocusPilot.app
├── Contents/MacOS/FocusPilot                # Swift 主进程
└── Contents/Resources/
    └── engine/
        ├── pilotone-engine                # PyInstaller 打包的 Engine 二进制
        └── skills/                        # 内置技能
```

用户双击 FocusPilot.app → Swift 主进程自动拉起 Engine 子进程 → 退出时自动终止。用户感知：单个 App，无需安装 Python。

### 7.2 云端部署（预留）

同一份 Engine 代码，Docker 部署，公网暴露 API（需认证）。

### 7.3 本地-云端协同（预留）

项目数据通过 Git 仓库同步，本地/云端 Engine 独立运行。

---

## 8. V1 范围（首版交付）

| 模块 | V1 范围 | 预留不做 |
|------|---------|---------|
| **Engine 基础** | FastAPI 服务 + 健康检查 + WebSocket | — |
| **项目引擎** | Markdown CRUD + frontmatter + 目录扫描 + FSEvents + 四模式 | 全文搜索 |
| **无模式 Agent 编排** | 配执行/评估 Agent 隐式驱动，看板状态自动流转 | 容器级递归自动执行 |
| **四模式** | Agile / Flow / Lite / Free 创建 + 展示 + 规划引导 | 模式切换迁移 |
| **MCP Host** | 单 Agent 调度（claude-code） | 多 Agent 并行、自动选择 |
| **Crew 数字团队** | 预置"代码工程师"1 个成员 + 侧边栏智能体成员/Runtime 双 Tab + 成员工作区三 Tab（概览/Tasks/配置）+ Runtime 单页监控（Header/执行器表格/Daemon 日志）+ crewState 统一状态管理 + MCP 状态 + 常驻职责配置 UI | 云端成员执行、多 Agent 自动选择、后台常驻调度 |
| **任务调度** | 即时执行 + 执行记录（SQLite） | 定时/事件触发 |
| **知识管道** | _materials/ + _reports/ 增量整合 + _kb/ 提炼 + 一键同步 | auto_sync 自动加工 |
| **Anki 同步** | KB 卡片 → AnkiConnect API 推送 | AnkiWeb 云端同步 |
| **费曼验证** | — | 对话面板提问 + 掌握层次标记 |
| **技能系统** | Engine 内部实现，用户不感知 | 自定义技能 |
| **Dashboard** | 四维驾驶舱 + 快速创建 Task | 日历拖拽视图 |
| **自动日志** | 每日归档 _logs/ | 自动周报 |
| **主面板** | VS Code 风格 | — |
| **对话面板** | 统一对话式交互 | — |
| **Swift App** | 主面板 + Quick Panel（聚焦 Tab）+ EngineManager | — |
| **部署** | PyInstaller 打包进 .app | Docker 云端 |
| **coder-bridge** | 保留兼容 | 逐步迁移到 Engine |
| **云端** | — | 全部预留 |
| **移动端** | — | 飞书 Bot + Web App |

---

## 9. 日常使用闭环

```
早上打开 FocusPilot
  → Quick Panel 聚焦 Tab 一瞥今日待办
  → 主面板 Dashboard 规划今日重点
  → 从 Backlog 拖拽 Task 到今日
  → 点击「同步整合」处理隔夜收集的素材

白天工作
  → 今日待办逐项执行（手动 / 派遣 Crew）
  → Agent 执行结果实时推送
  → 随时创建新 Task 归入项目

收尾
  → Dashboard 查看今日完成情况
  → 自动归档日志
  → 次日 Dashboard 自动更新
```

---

## 10. 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| Python Engine 增加 App 体积 | ~50MB | 桌面应用可接受；PyInstaller 可压缩 |
| Engine 崩溃影响体验 | 项目/Agent Tab 不可用 | EngineManager 自动重启；窗口管理/番茄钟不受影响 |
| MCP 协议各工具支持不一 | 部分工具无法接入 | V1 仅支持 claude-code；其他工具后续适配 |
| 双进程调试复杂度 | 开发效率降低 | make engine-start 独立调试 |
| 数据目录指向 Vault 时的冲突 | Obsidian 和 Engine 同时写文件 | Engine 写入前检查 mtime；建议 Obsidian 只读 |

---

## 11. 非功能需求

### 11.1 性能指标

现有桌面功能性能标准保持不变（参见 [PRD-v4-legacy.md §5.1](archive/PRD-v4-legacy.md)）。新增 Engine 相关指标：

| 指标 | 目标值 |
|------|-------|
| Engine 启动到就绪 | < 5s |
| API 请求响应 | < 200ms（CRUD 操作） |
| WebSocket 事件延迟 | < 100ms |
| 项目树扫描（100 节点） | < 1s |

### 11.2 兼容性

与现有版本一致（参见 [PRD-v4-legacy.md §5.2](archive/PRD-v4-legacy.md)）。

### 11.3 安全与隐私

- 保持现有安全策略（参见 [PRD-v4-legacy.md §5.3](archive/PRD-v4-legacy.md)）
- Engine 仅监听 `localhost:19840`，不暴露到网络
- API Key 由用户自行配置，FocusPilot 不上传不存储到云端

---

## 12. 新增文件结构

```
FocusPilot/
├── FocusPilot/                # Swift App（现有 + 新增模块）
│   └── Services/
│       └── EngineManager.swift    # 新增
├── engine/                  # 新增：Python Agent Engine
│   ├── pyproject.toml
│   ├── src/
│   │   ├── main.py
│   │   ├── project_engine/
│   │   ├── mcp_host/
│   │   ├── crew/
│   │   ├── scheduler/
│   │   ├── pipeline/
│   │   ├── skills/
│   │   └── api/
│   └── tests/
├── coder-bridge/            # 现有（保留）
├── docs/
└── Makefile
```

### Makefile 扩展

```makefile
# 现有命令保留
make build          # Swift App 编译
make install        # Swift App 编译+签名+安装+启动

# 新增 Engine 命令
make engine-setup   # 创建虚拟环境 + 安装依赖
make engine-start   # 开发模式启动 Engine
make engine-stop    # 停止 Engine
make engine-test    # 运行 Engine 测试
make engine-build   # PyInstaller 打包
make full-install   # Swift App + Engine 一起安装
```

---

## 附录 A：术语表

| 术语 | 定义 |
|------|------|
| FocusPilot | 个人版 AI Agent 编排平台，macOS 桌面应用 |
| PilotOne | 企业版 AI 经营系统，独立产品线（详见 Editions.md） |
| VaultOne | 知识管理系统（Obsidian），与 FocusPilot 互补 |
| Engine | Python Agent Engine，后台服务进程 |
| Crew | 数字团队，用户管理的 Agent 角色集合 |
| 智能体成员 | 一个配置好的 Agent 角色（如"代码工程师"），面向用户的数字团队成员 |
| 执行节点 | Runtime Host，承载执行器的本机、远程节点或云端机器 |
| crewState | AICrew 页面统一状态对象，驱动侧边栏选中、工作区 Tab 切换和面包屑同步 |
| MCP Host | Agent 编排器，通过 MCP 协议调度 AI 工具 |
| Skill | 任务执行模板，定义如何将 Task 转化为 Agent 指令 |
| Pipeline | 知识管道编排链（collect→integrate→distill→sync） |
| Dashboard | Today 驾驶舱，四维时间管理视图 |
| Task 双轴 | status（执行生命周期）+ schedule（时间安排） |
| 无模式 Agent 编排 | 配执行 Agent 自动调度 + 配评估 Agent 评估接力 |
| 四模式 | Agile / Flow / Lite / Free 项目组织模式 |
| KB 卡片 | 知识卡片，原子化要点，可同步 Anki |
| Actionable | 需要用户处理的状态（计入角标） |
