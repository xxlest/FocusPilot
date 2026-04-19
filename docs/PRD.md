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
| 两阶段模型 | planning → executing | — | — | — | — |
| 多 AI 工具调度 | MCP 统一 | 模型 Gateway | 多模型切换 | 内置 | 内置 |
| 知识管道 | Materials→Reports→KB→Anki | — | — | — | — |
| 窗口管理 | 有（内置） | — | — | — | — |
| 番茄钟 | 有（内置） | — | — | — | — |
| Today Dashboard | 有 | — | — | — | — |

**差异化定位**：FocusPilot 是本地优先的智能 AIOS，唯一同时提供"四模式项目管理 + 两阶段 Agent 编排 + 窗口管理 + 番茄钟 + Today Dashboard"的桌面平台。

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

### 3.1 两阶段模型：规划 → 执行

任意节点（Project / Epic / US / Task / 自定义层级）都有两个阶段：

```
任意节点
├── 规划阶段（人 + AI 协作）
│   "这个 Epic 应该拆成哪些 US？"
│   → AI 辅助拆分、细化、补全
│   → 人确认、调整、批准
│
└── 执行阶段（AI 自主）
    "规划好了，去做吧"
    → FocusPilot 调度 Agent 执行
    → 向下递归：容器执行 = 其子节点依次执行
```

**统一状态流转**：
```
inbox → planning（规划中，人+AI 协作）→ ready（规划完毕，可执行）→ executing（AI 执行中）→ done / blocked
```

| 状态 | 说明 |
|------|------|
| `planning` | FocusPilot 提供对话式交互，AI 帮助拆分和细化 |
| `ready` | 用户点击「执行」或设置 `auto_execute: true` 自动触发 |
| `executing` | Agent 工作中，实时反馈进度 |
| 容器节点执行 | 递归执行其子节点中所有 Task |

**不同层级的两阶段行为**：

| 颗粒度 | 规划阶段 AI 做什么 | 执行阶段 AI 做什么 |
|--------|-------------------|-------------------|
| Project | 拆分为 Epic / Phase / Task | 递归执行所有子节点 |
| Epic / Phase | 拆分为 US / Task | 递归执行所有子节点 |
| US | 拆分为 Task | 递归执行所有子 Task |
| Task | 细化描述、补全验收标准 | 直接调度 Agent 完成 |

**对话式交互**：

两个阶段都通过统一的**对话面板**进行，用户不需要感知 Skill、Agent 等技术概念：
- 规划阶段：用户输入"帮我拆分这个 Epic" → Engine 理解意图 → 自动调用合适的能力 → 返回拆分建议 → 用户确认/调整
- 执行阶段：用户输入"把这个 Task 交给代码工程师做" → Engine 理解意图 → 调度 Crew 成员执行 → 实时反馈

### 3.2 四种项目模式

Project/Epic/US/Task 是敏捷语境产物，不适用于所有场景。FocusPilot 提供四种模式，底层数据结构统一（树形 Markdown 节点），**模式定义：词汇表 + 层级规则 + AI 引导策略**。

#### 模式一：敏捷模式（Agile）— 软件开发

```
Project → Epic → User Story → Task
```
- 完整四级，planning 阶段 AI 按敏捷方法论引导拆分
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
- 两级，无 planning 阶段（可选），快速进出
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

Task 的 frontmatter 通过 `status` + `schedule` 形成**双轴管理**：

- `status` 管**执行生命周期**：inbox → planning → ready → executing → done
- `schedule` 管**时间安排**：backlog → month → week → today

两者独立：一个 Task 可以 `status: ready` + `schedule: week`（本周要做，已规划好，等待执行）。

| schedule 值 | 含义 | Dashboard 区域 |
|------------|------|---------------|
| `today` | 今日必做 | 🔥 今日待办 |
| `week` | 本周完成 | 📅 本周计划 |
| `month` | 本月目标 | 📆 本月目标 |
| `backlog` | 待排期 | 📥 Backlog |

**Task 创建规则**：每个 Task 必须有归属项目。两个创建入口：

| 入口 | 交互 | 归属项目 |
|------|------|---------|
| Dashboard「+ 新建任务」 | 输入内容 → 选择归属项目 → 选择时间维度 | 必选 |
| 项目树内右键创建 | 在某个项目/Epic/Phase 下创建 | 自动继承 |

### 3.4 Crew 数字团队

Crew 是 FocusPilot 的核心交互概念——**用户不直接面对 Agent/MCP/Skill 等技术概念，而是管理一个"数字团队"**。

每个 Crew 成员 = 一个配置好的 Agent 角色：

| 属性 | 说明 |
|------|------|
| 角色名 | 如"代码工程师"、"数据分析师"、"架构师" |
| 头像 | 可自定义 |
| 擅长领域 | 描述文本，影响 AI 任务分配 |
| 绑定 MCP Server | 底层实际调用的 AI 工具 |
| 部署位置 | 本地 / 云端 |
| 常驻职责 | 周期性任务（cron / event 触发） |

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
| 项目 Task（一次性） | 用户在对话面板中派遣，或从 Kanban 拖拽分配 | 手动 / auto_execute |
| 常驻职责（周期性） | 用户在 Crew 成员详情页配置 | cron 定时 / 事件触发 |

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
收集           加工             提炼            记忆           内化
─────         ─────           ─────          ─────         ─────
_materials/  →  _reports/    →  _kb/        →  Anki       →  智慧
原始素材         增量整合报告      知识卡片        间隔重复        费曼验证
Crew 自动抓取    对话+Task        极简要点        遗忘曲线        理解→应用
人手动放入       持续融入         框架记忆法       手机端复习
```

**五个阶段**：

| 阶段 | 说明 |
|------|------|
| **收集**（_materials/） | 人手动放入 + Crew 自动抓取 + 对话产生。新素材标记"待整合" |
| **加工**（_reports/） | 增量整合，每次新增素材 AI 融入现有报告。每层级各有章节报告 |
| **提炼**（_kb/ → Anki） | 从 reports 提炼原子化知识卡片，同步到 Anki（AnkiConnect API） |
| **记忆**（Anki 手机端） | 遵循遗忘曲线，间隔重复，碎片时间复习 |
| **内化**（费曼验证，预留） | FocusPilot 定期提问评估理解程度，标记掌握层次（know→understand→master） |

**KB 卡片格式**：

```yaml
---
type: kb-card
source: _reports/chapter-1.md
tags: [分布式, CAP]
anki_deck: "分布式系统"
anki_synced: false
mastery: know              # know → understand → master
---
## CAP 定理
**口诀**：一致可用分区，三选二
**类比**：像三个人传话，要么慢(C)，要么可能传错(A)，但电话线断了(P)总会发生
**费曼检验**：能否用一句话给外行解释 CAP？
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
| 👥 | Crew | 数字团队成员列表 + 状态 + 常驻职责 |
| 💬 | 对话 | 历史对话记录列表 |
| ⚙️ | 设置 | 偏好 / 数据目录 / 主题 / Crew 管理 |

**交互逻辑**：
- 点击活动栏图标切换侧边栏内容
- 侧边栏选中节点 → 主内容区联动
- 对话面板始终可用（底部固定或可折叠），针对当前选中上下文对话

#### 3.7.1 项目树按模式展示

**Agile**：
```
▾ 📁 FocusPilot V1                      [planning]
    ▾ 🎯 Epic: Engine 基础架构          [ready]
        ▾ 💼 US: 项目引擎               [executing]
            📄 Task: frontmatter 解析    [done ✓]
            📄 Task: 目录扫描            [executing 🔄]
```

**Flow**：
```
▾ 📁 Q2 大客户跟踪                     [executing]
    ▸ 📊 Phase 1: 数据收集     ████████░░ 80%
    ▾ 📊 Phase 2: 分析报告     ██░░░░░░░░ 20%
        📄 拉取 CRM 数据                 [done ✓]
        📄 生成客户画像                   [executing 🔄]
```

**Lite**：
```
▾ 📁 重构登录模块                       [executing]
    📄 分析现有代码                       [done ✓]
    📄 实现 JWT 认证                     [executing 🔄]
```

**Free**：
```
▾ 📁 学术论文                           [planning]
    ▾ 📂 文献综述
        📄 搜索相关论文                   [done ✓]
    ▾ 📂 实验
        ▾ 📂 实验设计
            📄 定义变量                   [ready]
```

#### 3.7.2 Crew 侧边栏

```
┌─ 👥 我的 Crew ──────────────────┐
│                                  │
│ 🟢 代码工程师        本地         │
│    claude-code | 空闲            │
│                                  │
│ 🟢 架构师           本地         │
│    claude-code | 执行中 🔄       │
│    └─ FocusPilot / MCP Host 设计   │
│                                  │
│ 🔴 数据分析师        云端         │
│    未连接                        │
│                                  │
│ [+ 添加成员]                     │
└──────────────────────────────────┘
```

选中 Crew 成员时主内容区展示：常驻职责表 + 执行历史 + 对话。

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

## 知识管道
- 3 条新素材已收集
- 2 张 KB 卡片已同步到 Anki
```

**设计要点**：完全自动生成，Markdown 格式 Git 可追踪，跨项目汇总，为 AI 提供"项目记忆"。

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
status: planning         # inbox → planning → ready → executing → done / blocked
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
status: ready
schedule: today          # today / week / month / backlog
priority: normal
tags: [backend]
created_date: 2026-04-01
code_path:               # 关联代码仓库路径（可选）
parent_project:
skill:                   # 默认根据上下文推断
agent:                   # 默认用首选 Agent
auto_execute: false
---
把登录接口从 session 改为 JWT，保持向后兼容
```

**执行策略字段说明**：
- `skill` / `agent` 不填时，Engine 按默认策略推断
- `auto_execute: true` 时，状态流转到 `executing` 自动触发 Agent
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
6. 完成后 PATCH Task frontmatter：`status: executing → done`

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
| **两阶段模型** | planning → ready → executing → done 状态流转 | 容器级递归自动执行 |
| **四模式** | Agile / Flow / Lite / Free 创建 + 展示 + 规划引导 | 模式切换迁移 |
| **MCP Host** | 单 Agent 调度（claude-code） | 多 Agent 并行、自动选择 |
| **Crew 数字团队** | 预置"代码工程师"1 个成员 + Crew 面板 | 自定义成员、常驻职责、云端成员 |
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
| Crew 成员 | 一个配置好的 Agent 角色（如"代码工程师"） |
| MCP Host | Agent 编排器，通过 MCP 协议调度 AI 工具 |
| Skill | 任务执行模板，定义如何将 Task 转化为 Agent 指令 |
| Pipeline | 知识管道编排链（collect→integrate→distill→sync） |
| Dashboard | Today 驾驶舱，四维时间管理视图 |
| Task 双轴 | status（执行生命周期）+ schedule（时间安排） |
| 两阶段模型 | 规划（人+AI 协作）→ 执行（AI 自主） |
| 四模式 | Agile / Flow / Lite / Free 项目组织模式 |
| KB 卡片 | 知识卡片，原子化要点，可同步 Anki |
| Actionable | 需要用户处理的状态（计入角标） |
