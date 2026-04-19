# PilotOne 产品架构设计文档

> **产品代号**：PilotOne（开发阶段代号，正式品牌上线前确定）
> **版本**：V1.0 设计稿
> **日期**：2026-04-01
> **状态**：设计中
> **基于**：FocusPilot V4.3 + VaultOne 系统理念

---

## 1. 产品愿景

**PilotOne** 是一个多端 AI Agent 编排平台（本地龙虾），在本地操作系统之上提供智能 AIOS 层。

- **VaultOne** 管知识（笔记、项目规划、知识卡片）
- **PilotOne** 管执行（Agent 编排、任务调度、技能系统）
- 两者构成"认知 → 执行"自迭代闭环

原 FocusPilot（悬浮球 + 窗口管理 + 番茄钟）功能全部保留，统一归入 PilotOne 品牌。

核心命题源自 VaultOne 系统理念——**"Everything is Code. Project ships. PilotOne builds."**

- **人的职责**：探索、研究、规划（Project/Epic/US/Task），在任意粒度上细化意图
- **Task 即指令**：用自然语言表达意图，发送给 PilotOne 执行
- **PilotOne 即执行层**：连接人的思考，调度 AI 工具，将 Task 转化为代码、文档、数据、报告

### 1.1 两阶段模型：规划 → 执行

任意节点（Project / Epic / US / Task / 自定义层级）都有两个阶段：

```
任意节点
├── 规划阶段（人 + AI 协作）
│   "这个 Epic 应该拆成哪些 US？"
│   "这个 Task 的验收标准是什么？"
│   → AI 辅助拆分、细化、补全
│   → 人确认、调整、批准
│
└── 执行阶段（AI 自主）
    "规划好了，去做吧"
    → PilotOne 调度 Agent 执行
    → 向下递归：容器执行 = 其子节点依次执行
```

**统一状态流转**：
```
inbox → planning（规划中，人+AI 协作）→ ready（规划完毕，可执行）→ executing（AI 执行中）→ done / blocked
```

- `planning` 状态：PilotOne 提供对话式交互，AI 帮助拆分和细化
- `ready` 状态：用户点击「执行」或设置 `auto_execute: true` 自动触发
- `executing` 状态：Agent 工作中，实时反馈进度
- 容器节点执行 = 递归执行其子节点中所有 Task

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

Skill 是 Engine 内部实现细节（参见 3.4 节），用户不直接接触。

### 1.2 四种项目模式

Project/Epic/US/Task 是敏捷语境产物，不适用于所有场景。PilotOne 提供四种模式，底层数据结构统一（树形 Markdown 节点），**模式定义：词汇表 + 层级规则 + AI 引导策略**。

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
- 无预设词汇表，AI 按用户指令自由拆分
- 适用：学术研究、探索性项目、非标项目

**模式对比**：

| | Agile | Flow | Lite | Free |
|---|---|---|---|---|
| 层级 | 4 级固定 | 3 级固定 | 2 级固定 | 不限 |
| 适用 | 软件开发 | 阶段制项目 | 简单任务 | 非标项目 |
| 规划引导 | 重（敏捷方法论） | 中（阶段引导） | 轻（可选） | 开放式对话 |
| 图标体系 | 📁🎯💼📄 | 📁📊📄 | 📁📄 | 📁📂📄 |

**落地方式**：Project frontmatter 中 `mode` 字段决定模式：

```yaml
---
type: project
mode: agile          # agile / flow / lite / free
status: planning
---
```

**可切换**：项目右键菜单可切换模式（仅影响后续创建行为，已有节点不动）。

### 1.3 项目产出模型与知识管道

#### 1.3.1 项目的通用产出结构

所有项目都交付产物，同时积累知识沉淀。每个层级（Project / Epic / Phase / 自定义）都可包含：

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

**示例：Flow 模式下的"写书"项目**：
```
📁 分布式系统实战              mode: flow
├── 📊 Phase 1: 基础理论（= Chapter 1）
│   ├── 📄 Task: 调研 CAP 定理
│   ├── 📄 Task: 调研一致性模型
│   ├── _materials/            ← 阅读的论文、文章
│   ├── _kb/                   ← 提炼的知识卡片
│   └── _reports/chapter-1.md  ← AI 从 KB + 对话汇总成章节
├── 📊 Phase 2: 实践案例（= Chapter 2）
│   └── ...
└── _reports/
    └── full-report.md         ← AI 自动合并所有章节 → 完整的"书"
```

#### 1.3.2 知识管道（Knowledge Pipeline）

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

**① 收集（_materials/）**
- **人手动**：放入文章、PDF、截图、会议记录
- **Crew 自动**：常驻职责定时抓取（如"每天 8:00 收集 AI 领域新闻"）
- **对话产生**：规划/讨论过程中的对话记录自动归档
- 新素材到达后标记为"待整合"，推送到 Today Dashboard

**② 加工（_reports/）**
- **增量整合**，不是做完才写：每次新增 materials 或完成 Task，AI 将新内容融入现有报告
- 粒度：Phase/Epic 级别各有章节报告，Project 级别有完整报告
- 触发方式：
  - 手动：Today Dashboard 点击「同步整合」
  - 自动：项目配置 `auto_sync: true` 后，收集完自动触发加工

```
第 1 天：读了 3 篇论文 → report v1（基础框架）
第 3 天：做了实验     → report v2（加入实践数据）
第 7 天：和同事讨论   → report v3（加入新观点）
...持续生长
```

**③ 提炼（_kb/ → Anki）**
- 从 reports 和 materials 中提炼**原子化知识卡片**
- 格式遵循框架记忆法（费曼学习法）：

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

**要点**：
- C(一致性): 所有节点同一时刻数据相同
- A(可用性): 每个请求都能收到响应
- P(分区容错): 网络分区时系统仍运行

**类比**：像三个人传话，要么慢(C)，要么可能传错(A)，
但电话线断了(P)总会发生

**费曼检验**：能否用一句话给外行解释 CAP？
```

- 提炼后自动同步到 Anki（通过 AnkiConnect API）
- 卡片类型：问答 / 填空 / 口诀 / 类比

**④ 记忆（Anki 手机端）**
- 遵循遗忘曲线，间隔重复
- 手机端碎片时间复习（通勤、等人）
- 复习数据可回传 PilotOne（标记掌握程度）

**⑤ 内化（费曼验证，预留）**
- PilotOne 定期提问："用自己的话解释一下 CAP 定理？"
- 用户回答后 AI 评估理解程度
- 掌握层次标记：`know`（能认出）→ `understand`（能解释）→ `master`（能应用/教人）
- 未达标的卡片增加 Anki 复习频率

#### 1.3.3 自动收集 + 一键同步

**Crew 常驻职责负责自动收集**，Today Dashboard 提供一键同步入口：

```
Crew 常驻职责（定时收集）           用户（每日 Review）
──────────────────              ─────────────────
每天 8:00                        
  📰 新闻 Crew 抓取行业资讯       
  💬 消息 Crew 汇总飞书群         → _materials/（自动）
每周一 9:00                      
  📊 数据 Crew 拉取业务指标       

                                 用户打开 Today Dashboard
                                 看到：📥 3 条新素材待整合
                                 点击「同步整合」
                                        ↓
                                 Engine 触发加工链：
                                 1. 新 materials → 融入 _reports/
                                 2. 从新内容提炼 → _kb/ 卡片
                                 3. 新卡片 → 同步 Anki
                                 4. 更新 _logs/ 日志
```

**Today Dashboard 新增入口**：
```
┌─ 今日聚焦 ──────────────────────────┐
│                                      │
│ 📥 待整合素材 (3)         [同步整合]  │
│   📰 AI 行业日报 (新闻 Crew, 今天)    │
│   💬 飞书群摘要 (消息 Crew, 今天)      │
│   📊 业务周数据 (数据 Crew, 周一)      │
│                                      │
│ 🔥 待办 ...                           │
└──────────────────────────────────────┘
```

**同步模式可配置**：
- `auto_sync: false`（默认）：Crew 收集后等待用户手动点「同步整合」
- `auto_sync: true`：收集完自动触发加工链，用户只需 review 结果

#### 1.3.4 收集任务的部署位置

| 环节 | 本地 Engine | 云端 Engine | 推荐 |
|------|-----------|-----------|------|
| 定时收集 | ⚠️ 电脑必须开着 | ✅ 7×24 运行 | 云端 |
| 加工整合 | ✅ 点击触发 | ✅ 远程触发 | 都行 |
| KB 提炼 | ✅ | ✅ | 都行 |
| Anki 同步 | ✅ AnkiConnect 在本地 | ⚠️ 需 AnkiWeb API | 本地 |
| 费曼验证 | ✅ 对话面板 | ✅ 飞书 Bot | 都行 |

**V1（纯本地）**：收集 + 加工全在本地 Engine，电脑需开着。
**长期方案**：云端 Crew 7×24 收集 → Git 同步到本地 → 用户打开 PilotOne 点「同步」→ 本地加工 + Anki 同步。

### 1.4 产品形态

- **PilotOne Local（本地龙虾）**：macOS App，指挥官模式，本地常驻。内置悬浮球、窗口管理、番茄钟
- **PilotOne Cloud（云端龙虾）**：同一 Engine 部署到云服务器，提供离线常驻服务（预留）
- **PilotOne Mobile（移动端）**：飞书 Bot（轻量指挥）+ Web App（详细操作），对话模式（预留）

**产品矩阵**：
```
VaultOne（知识层）          PilotOne（执行层）
  Obsidian 笔记系统            AI Agent 编排平台
  Project/Epic/US 规划         Task 调度 + Agent 执行
  知识卡片 + 周期笔记          技能系统 + 自动日志
       └──── REST API / Git 同步 ────┘
```

### 1.5 设计准则

- **干净**：Engine 与 UI 壳职责分离，模块之间不互相污染
- **高级**：V1 只做项目管理 + 单 Agent 调度，做到极致再扩展
- **克制**：云端/移动端/多技能全部预留不预做
- **专业**：Engine 作为独立服务，同一份代码可部署到本地/云端/Docker

### 1.6 AIOS 定位

PilotOne 本质是在本地操作系统之上的智能 AIOS 层：

| AIOS 概念 | PilotOne 对应 |
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

### 1.7 Crew 数字团队

Crew 是 PilotOne 的核心交互概念——**用户不直接面对 Agent/MCP/Skill 等技术概念，而是管理一个"数字团队"**。

每个 Crew 成员 = 一个配置好的 Agent 角色：

| 属性 | 说明 |
|------|------|
| 角色名 | 如"代码工程师"、"数据分析师"、"架构师" |
| 头像 | 可自定义 |
| 擅长领域 | 描述文本，影响 AI 任务分配 |
| 绑定 MCP Server | 底层实际调用的 AI 工具 |
| 部署位置 | 本地 / 云端 |
| 常驻职责 | 周期性任务（cron / event 触发） |

**预置 Crew 成员（V1）**：
```
🧑‍💻 代码工程师     — claude-code, 本地
```

**用户可自定义添加（预留）**：
```
📊 数据分析师     — research-agent, 云端
✂️ 剪辑专家       — video-agent, 云端
📝 内容编辑       — writing-agent, 云端
🏗️ 架构师         — architect-agent, 本地
🔧 运维值班       — ops-agent, 云端
📈 市场专家       — marketing-agent, 云端
```

**Crew 成员的两种任务**：

| 任务类型 | 来源 | 触发方式 |
|---------|------|---------|
| 项目 Task（一次性） | 用户在对话面板中派遣，或从 Kanban 拖拽分配 | 手动 / auto_execute |
| 常驻职责（周期性） | 用户在 Crew 成员详情页配置 | cron 定时 / 事件触发 |

**常驻职责示例**：
```yaml
# 数据分析师的常驻职责
- name: "客户周报"
  trigger: "cron: 0 9 * * MON"      # 每周一 9:00
  task_template: "生成本周大客户数据报告"

- name: "飞书消息汇总"
  trigger: "cron: 0 18 * * *"       # 每天 18:00
  task_template: "汇总今日飞书群消息要点"

- name: "异常告警"
  trigger: "event: api_latency > 500ms"
  task_template: "检查 API 延迟异常并生成报告"
```

**Crew 与底层模块的映射**：

| 用户看到的 | Engine 内部 |
|-----------|------------|
| Crew 成员 | MCP Server 注册 + Agent 配置 |
| 派遣任务 | `POST /api/agents/execute` |
| 常驻职责 | Scheduler jobs（trigger_type: cron/event） |
| 执行历史 | Scheduler runs |

用户始终面对"团队管理"这个隐喻，不需要理解底层技术。

---

## 2. 整体架构

```
┌─────────────── 用户接入层 ───────────────┐
│  PilotOne         飞书Bot       Web App  │
│  (Swift macOS)   (对话模式)    (移动/桌面) │
│  指挥官模式       消息驱动      混合模式    │
│  [V1 实现]       [预留]        [预留]     │
└────────┬──────────┬──────────┬────────────┘
         │          │          │
         ▼          ▼          ▼
┌─────────── Agent Engine (Python) ─────────┐
│                                            │
│  项目引擎    MCP Host    任务调度   技能系统 │
│  md CRUD    Agent 编排   定时/事件  可扩展   │
│  frontmatter 多工具调度  执行队列   OpenClaw │
│                                            │
│  Gateway API: FastAPI REST + WebSocket     │
│  端口: localhost:19840                      │
└────────┬──────────┬──────────┬────────────┘
         │          │          │
         ▼          ▼          ▼
┌─────────── 数据与执行层 ──────────────────┐
│  项目数据      AI 工具       云端(预留)     │
│  Markdown     Claude Code   远程 Engine   │
│  可配置目录    Codex/Cursor  状态中枢      │
│  Git 管理     via MCP       定时任务      │
└───────────────────────────────────────────┘
```

### 2.1 关键架构决策

| 决策 | 选择 | 理由 |
|------|------|------|
| Engine 技术栈 | Python + FastAPI | AI 生态最成熟，MCP SDK 一等支持，云端部署零摩擦 |
| Engine 与 App 关系 | 独立进程，HTTP/WS 通信 | 同一 Engine 可部署到本地/云端，UI 壳可替换 |
| AI 工具调度协议 | MCP (Model Context Protocol) | 标准化协议，扩展性强 |
| 项目数据格式 | Markdown + YAML frontmatter | 脱离 Obsidian 依赖，Git 友好，人类可读 |
| 数据目录 | 可配置（默认 ~/.pilotone/projects/） | 可指向 VaultOne 目录实现兼容 |
| 部署方式 | PyInstaller 打包进 .app bundle | 用户感知单 App，无需安装 Python |
| 交互模式 | 本地指挥官 + 远程对话（混合） | 本地结构化操作，远程消息驱动 |

### 2.2 与 VaultOne 的关系

PilotOne 脱离 Obsidian 依赖，Engine 内建 Markdown 项目引擎。用户可将数据目录指向 `~/Workspace/1-Vault/1-Focus/`，此时：
- Engine 直接读写 Vault 文件（frontmatter 格式兼容 VaultOne 数据契约）
- Obsidian 可同时打开同目录浏览笔记（只读共存）
- 但 Engine 不依赖 Obsidian REST API 运行

---

## 3. Agent Engine 模块设计

### 3.1 项目引擎（Project Engine）

**职责**：Markdown 项目数据的 CRUD、解析、监听、搜索。

**数据目录结构**：
```
{projects_dir}/                  # 可配置，默认 ~/.pilotone/projects/
├── work/
│   └── MyProject/
│       ├── _project.md          # frontmatter: type/status/tags/mode
│       ├── _materials/          # 项目级原始素材
│       ├── _kb/                 # 项目级知识卡片（可同步 Anki）
│       ├── _reports/            # 项目级综合报告（AI 自动合并章节）
│       ├── epic-auth/
│       │   ├── _epic.md
│       │   ├── _materials/      # Epic 级素材
│       │   ├── _kb/             # Epic 级知识卡片
│       │   ├── _reports/        # Epic 级章节报告
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

**Frontmatter 数据契约**（兼容 VaultOne）：

Project 级别：
```yaml
---
type: project
mode: agile              # agile / flow / lite / free
status: planning         # inbox → planning → ready → executing → done / blocked
priority: normal         # low / normal / high / urgent
tags: [backend, auth]
created_date: 2026-04-01
finished_date:           # 完成时写入
progress:                # done 时自动 100%
# 知识管道配置（可选）
pipeline:
  auto_collect: false    # Crew 是否自动收集 materials
  auto_sync: false       # 收集后是否自动触发加工链
  anki_deck:             # 关联的 Anki 牌组名称
  collect_sources:       # 收集源（绑定 Crew 常驻职责）
    - crew: "新闻 Crew"
      schedule: "0 8 * * *"
---
```

容器级别（Epic / Phase / US / Group）：
```yaml
---
type: epic               # epic / phase / us / group（按模式而异）
status: planning
tags: [auth]
created_date: 2026-04-01
parent_project:          # 父项目引用
---
```

Task 级别（最小可执行单元）：
```yaml
---
type: task
status: ready            # inbox → planning → ready → executing → done / blocked
priority: normal
tags: [backend]
created_date: 2026-04-01
finished_date:
code_path:               # 关联代码仓库路径（可选）
parent_project:          # 父项目引用
parent_epic:             # 父容器引用（epic/phase/us/group）
# 执行策略（可选，有默认值）
skill:                   # 默认根据上下文推断
agent:                   # 默认用首选 Agent
auto_execute: false      # 状态变为 executing 时是否自动触发
---
把登录接口从 session 改为 JWT，保持向后兼容
```

**执行策略字段说明**：
- `skill` / `agent` 不填时，Engine 按默认策略推断（code 类 Task 默认 `code-execute` + `claude-code`）
- `auto_execute: true` 时，状态流转到 `executing` 自动触发 Agent，无需手动点击
- 遵循「克制」原则：默认覆盖 90% 场景，高级用户可通过 frontmatter 精确控制

**非 code 场景同样适用**：

| 场景 | Task 内容 | Skill | Agent | 产物 |
|------|----------|-------|-------|------|
| 写代码 | "把登录改成 JWT" | code-execute | claude-code | 代码 PR |
| 写报告 | "分析大客户 Q1 数据" | report-generate | research-agent | Markdown 文档 |
| 运维监控 | "检查 API 延迟" | ops-check | ops-agent | 状态报告 |
| 信息收集 | "汇总本周飞书消息" | data-collect | msg-agent | 摘要文档 |
| 文档生成 | "根据架构图生成 PPT" | doc-create | creator-agent | PPT 文件 |

Task 不是"代码指令"，而是"意图指令"。Skill 决定用什么能力执行，Agent 决定谁来执行。

**对外接口**：
```
GET    /api/projects                    # 项目树（递归扫描）
GET    /api/projects/{path}             # 单个节点详情（frontmatter + body）
POST   /api/projects/{path}            # 创建节点（自动创建目录 + _*.md）
PATCH  /api/projects/{path}            # 更新 frontmatter 字段
DELETE /api/projects/{path}            # 删除节点（目录 + 文件）
POST   /api/projects/search            # 全文搜索（V1 预留）
WS     /api/events                     # 文件变更 + Agent 进度实时推送
```

**核心实现**：
- `python-frontmatter` 解析 YAML frontmatter
- `watchfiles`（基于 Rust 的 FSEvents 绑定）监听文件变更
- 目录递归扫描构建项目树，内存缓存 + 增量更新
- 状态流转校验：只允许合法的状态转换路径

### 3.2 MCP Host（Agent 编排）

**职责**：接收 Task 执行请求，选择并调度 MCP Server（AI 工具），监控执行进度。

**组件**：
```
MCP Host
├── Orchestrator（编排器）
│   ├── 接收 Task → 解析意图 → 选择 Agent
│   ├── 通过 MCP 协议启动 Agent 会话
│   ├── 监控进度 → 实时推送 → 回写 Task 状态
│   └── 多 Agent 并行协调（V1 仅单 Agent）
│
├── Server Registry（MCP Server 注册表）
│   ├── claude-code   (本地进程, stdio)
│   ├── codex         (云端 API, SSE)（预留）
│   ├── cursor        (IDE 扩展)（预留）
│   └── custom        (用户自定义)（预留）
│
└── Session Manager（会话管理）
    ├── 会话生命周期：created → running → done/error
    ├── 执行日志持久化
    └── 结果收集与归档
```

**对外接口**：
```
GET    /api/agents/servers              # 已注册 MCP Server 列表
POST   /api/agents/execute              # 执行 Task（指定 skill + task_path）
GET    /api/agents/sessions             # 活跃会话列表
GET    /api/agents/sessions/{id}        # 会话详情（状态 + 日志）
POST   /api/agents/sessions/{id}/stop   # 终止会话
```

**执行流程**：
1. PilotOne UI 发送 `POST /api/agents/execute {task_path, skill: "code-execute"}`
2. Orchestrator 读取 Task markdown，提取上下文（code_path、parent 信息）
3. 从 Registry 选择 MCP Server（V1 默认 claude-code）
4. 通过 MCP 协议（stdio transport）启动 Agent 会话
5. 实时通过 WebSocket 推送进度事件
6. 完成后 PATCH Task frontmatter：`status: doing → done`，附加执行摘要

**与现有 coder-bridge 的关系**：
- V5.0 初期：coder-bridge 保留兼容，Engine 新增 MCP 通道
- 后续迁移：coder-bridge 的 DistributedNotification 链路逐步替换为 MCP 协议
- CoderBridgeService 最终演变为 Engine MCP Host 的 Swift 客户端

### 3.3 任务调度器（Task Scheduler）

**职责**：管理任务执行的触发、排队、记录。

**存储**：SQLite `~/.pilotone/scheduler.db`
```sql
-- 任务定义
CREATE TABLE jobs (
    id TEXT PRIMARY KEY,
    task_path TEXT NOT NULL,        -- 关联的 Task markdown 路径
    skill TEXT NOT NULL,            -- 执行技能
    trigger_type TEXT NOT NULL,     -- immediate / cron / event
    trigger_config TEXT,            -- cron 表达式 / 事件类型
    created_at TIMESTAMP,
    status TEXT DEFAULT 'active'    -- active / paused / deleted
);

-- 执行记录
CREATE TABLE runs (
    id TEXT PRIMARY KEY,
    job_id TEXT REFERENCES jobs(id),
    session_id TEXT,                -- MCP 会话 ID
    status TEXT NOT NULL,           -- pending / running / done / error
    started_at TIMESTAMP,
    finished_at TIMESTAMP,
    summary TEXT,                   -- 执行摘要
    log_path TEXT                   -- 详细日志文件路径
);
```

**V1 scope**：仅支持 `immediate` 触发 + 执行记录查询。`cron` 和 `event` 触发为云端预留。

**对外接口**：
```
GET    /api/scheduler/runs              # 执行记录列表
GET    /api/scheduler/runs/{id}         # 执行详情
```

### 3.4 技能系统（Skill System）

**职责**：可扩展的任务执行模板，定义如何将 Task 转化为 Agent 指令。

**技能目录结构**：
```
~/.pilotone/skills/
├── builtin/
│   ├── code-execute/              # 代码执行
│   │   ├── manifest.json          # 元数据：名称/描述/所需 MCP Server
│   │   └── prompt.md              # Agent 执行提示词模板
│   └── project-manage/            # 项目管理操作
│       ├── manifest.json
│       └── prompt.md
└── custom/                        # 用户自定义技能（预留）
    ├── ppt-generate/
    ├── video-process/
    └── msg-collect/
```

**manifest.json 示例**：
```json
{
  "name": "code-execute",
  "description": "将 Task 分配给 AI 编码工具执行",
  "version": "1.0.0",
  "requires_server": ["claude-code"],
  "input": {
    "task_path": "string",
    "code_path": "string (optional, from frontmatter)"
  },
  "output": {
    "summary": "string",
    "artifacts": ["string (file paths)"]
  }
}
```

**V1 scope**：仅实现 `code-execute` 和 `plan-decompose` 两个内置技能。OpenClaw 兼容和自定义技能为未来预留。

### 3.5 知识管道编排（Pipeline）

**职责**：编排多个 Skill 的执行顺序，形成完整的加工链。一键「同步整合」= 触发一条 pipeline。

**组件**：
```
Pipeline
├── Chain（加工链定义）
│   ├── collect     → 收集（Crew 常驻职责产出 → _materials/）
│   ├── integrate   → 整合（_materials/ 新内容 → 融入 _reports/）
│   ├── distill-kb  → 提炼（_reports/ 更新内容 → _kb/ 知识卡片）
│   └── sync-anki   → 同步（_kb/ 新卡片 → Anki 牌组）
│
├── Trigger（触发方式）
│   ├── manual      → Today Dashboard「同步整合」按钮
│   ├── auto        → auto_sync: true 时收集完自动触发
│   └── scheduled   → cron 定时（如每天 22:00 自动整合当天素材）
│
└── Status Tracker（状态追踪）
    ├── 每步执行状态（pending/running/done/error）
    └── 素材标记（new → integrated → distilled → synced）
```

**对外接口**：
```
POST   /api/pipeline/sync           # 触发同步整合（一键按钮）
GET    /api/pipeline/status          # 当前 pipeline 执行状态
GET    /api/pipeline/pending         # 待整合素材列表
POST   /api/pipeline/anki-sync      # 手动触发 Anki 同步
```

**素材生命周期标记**：
```
_materials/ 中的文件 frontmatter:
---
type: material
status: new          # new → integrated → distilled → synced
source: crew:news    # 来源（crew 自动收集 / manual 手动放入）
collected_at: 2026-04-02T08:00:00
---
```

Engine 根据 `status` 字段判断哪些素材需要加工，避免重复处理。

### 3.6 四模式的产品功能体现

#### 3.5.1 创建项目时：模式选择

Quick Panel 项目 Tab → 右键「新建项目」→ 弹出模式选择面板，四种模式可选（Agile / Flow / Lite / Free），每种模式附带一行说明。选定后 `_project.md` 自动写入 `mode` 字段。项目右键菜单可切换模式（仅影响后续创建行为，已有节点不动）。

#### 3.5.2 Quick Panel 项目 Tab 按模式展示

**Agile**：四级缩进树 + 敏捷标签（📁🎯💼📄）
```
▾ 📁 PilotOne V1                      [planning]
    ▾ 🎯 Epic: Engine 基础架构          [ready]
        ▾ 💼 US: 项目引擎               [executing]
            📄 Task: frontmatter 解析    [done ✓]
            📄 Task: 目录扫描            [executing 🔄]
```

**Flow**：三级 + 阶段进度条（📁📊📄）
```
▾ 📁 Q2 大客户跟踪                     [executing]
    ▸ 📊 Phase 1: 数据收集     ████████░░ 80%
    ▾ 📊 Phase 2: 分析报告     ██░░░░░░░░ 20%
        📄 拉取 CRM 数据                 [done ✓]
        📄 生成客户画像                   [executing 🔄]
```

**Lite**：两级平铺，最紧凑（📁📄）
```
▾ 📁 重构登录模块                       [executing]
    📄 分析现有代码                       [done ✓]
    📄 实现 JWT 认证                     [executing 🔄]
```

**Free**：自由缩进 + 通用图标（📁📂📄）
```
▾ 📁 学术论文                           [planning]
    ▾ 📂 文献综述
        📄 搜索相关论文                   [done ✓]
    ▾ 📂 实验
        ▾ 📂 实验设计
            📄 定义变量                   [ready]
```

#### 3.5.3 规划交互：模式决定 AI 对话策略

`planning` 状态下，用户点击节点触发规划对话。模式决定 AI 引导方式：

- **Agile**：结构化引导（"建议拆成 3 个 US，每个 US 下再细化 Task"）
- **Flow**：阶段引导（"这类项目建议分 4 个阶段：调研→分析→跟进→复盘"）
- **Lite**：直接列 Task（"建议分这几步：1. 分析 2. 实现 3. 测试"）
- **Free**：开放式对话（"请描述你的结构，或直接创建子文件夹"）

#### 3.5.4 执行触发：模式决定粒度

| 模式 | 可触发执行的层级 | 行为 |
|------|----------------|------|
| Agile | US 或 Task | 执行 US = 按序执行其下所有 Task |
| Flow | Phase 或 Task | 执行 Phase = 按序执行其下所有 Task |
| Lite | Project 或 Task | 执行 Project = 按序执行所有 Task |
| Free | 任意容器或 Task | 执行容器 = 递归执行其下所有叶子 Task |

所有模式中，**Task 永远是最小执行单元**。

#### 3.5.5 悬浮球 / 角标：模式无感

悬浮球的 Agent 角标只关心"有多少 Task 在执行中"，不区分模式。模式对悬浮球和关注 Tab 完全透明。

### 3.7 Dashboard 驾驶舱 + Quick Panel 联动 + 自动日志

#### 3.7.1 Task 时间维度（schedule 字段）

Task 的 frontmatter 新增 `schedule` 字段，与 `status` 形成**双轴管理**：

- `status` 管**执行生命周期**：inbox → planning → ready → executing → done
- `schedule` 管**时间安排**：backlog → month → week → today

两者独立：一个 Task 可以 `status: ready` + `schedule: week`（本周要做，已规划好，等待执行）。

```yaml
---
type: task
status: ready
schedule: today          # today / week / month / backlog
parent_project: PilotOne V1
created_date: 2026-04-02
---
实现 frontmatter 解析模块
```

| schedule 值 | 含义 | Dashboard 区域 |
|------------|------|---------------|
| `today` | 今日必做 | 🔥 今日待办 |
| `week` | 本周完成 | 📅 本周计划 |
| `month` | 本月目标 | 📆 本月目标 |
| `backlog` | 待排期 | 📥 Backlog |

#### 3.7.2 Task 创建规则

**核心约束：每个 Task 必须有归属项目。**

两个创建入口：

| 入口 | 交互 | 归属项目 |
|------|------|---------|
| Dashboard「+ 新建任务」 | 输入内容 → 选择归属项目 → 选择时间维度 | 必选 |
| 项目树内右键创建 | 在某个项目/Epic/Phase 下创建 | 自动继承 |

Dashboard 创建时弹出的快速输入面板：
```
┌─ 新建任务 ──────────────────────┐
│ 内容: [实现 frontmatter 解析]    │
│ 项目: [PilotOne V1 ▾]          │
│ 时间: ○今日 ○本周 ○本月 ○Backlog │
│                      [创建]     │
└──────────────────────────────────┘
```

#### 3.7.3 主面板 Dashboard 设计

主面板活动栏点击 📁 项目图标时，默认展示 Dashboard 驾驶舱：

```
┌─ Dashboard ──────────────────────────────────────────┐
│                                                       │
│ 🔥 今日待办 (4/7)                        [+ 新建任务] │
│ ┌─────────────────────────────────────────────────┐  │
│ │ ☐ 实现 frontmatter 解析    PilotOne V1   [执行]  │  │
│ │ ☐ 生成客户画像             大客户跟踪     [执行]  │  │
│ │ ☐ 审阅 PR #18              PilotOne V1           │  │
│ │ ☐ 准备周会材料             工作管理               │  │
│ │ ─ ─ ─ ─ ─ ─ 已完成 ─ ─ ─ ─ ─ ─                 │  │
│ │ ☑ JWT 认证实现             PilotOne V1   8min ✓  │  │
│ │ ☑ 拉取 CRM 数据           大客户跟踪     3min ✓  │  │
│ │ ☑ 飞书消息汇总             (Crew 自动)    ✓      │  │
│ └─────────────────────────────────────────────────┘  │
│                                                       │
│ 📅 本周计划 (12/20)                  W14 进度 60%     │
│ ┌─────────────────────────────────────────────────┐  │
│ │ ▸ PilotOne V1        5/8 Task    ██████░░ 63%  │  │
│ │ ▸ 大客户跟踪          4/6 Task    ████████ 67%  │  │
│ │ ▸ 分布式系统学习       3/6 Task    ████░░░░ 50%  │  │
│ └─────────────────────────────────────────────────┘  │
│                                                       │
│ 📆 本月目标 (April)                                   │
│ ┌─────────────────────────────────────────────────┐  │
│ │ 🎯 PilotOne V1 Engine 完成     ████░░░░ 40%    │  │
│ │ 🎯 Q2 客户分析报告交付          ██░░░░░░ 20%    │  │
│ │ 🎯 分布式系统前 3 章完成        ██████░░ 60%    │  │
│ └─────────────────────────────────────────────────┘  │
│                                                       │
│ 📥 Backlog (15)              📥 待整合素材 (3) [同步] │
│ ▸ 展开查看...                 📰 AI日报  💬 飞书  📊 数据│
└───────────────────────────────────────────────────────┘
```

**数据来源**：
- 🔥 今日待办 = 所有 `schedule: today` 的 Task（跨项目汇总），按 status 分为未完成 / 已完成
- 📅 本周计划 = 所有 `schedule: week` 或 `schedule: today` 的 Task，按项目分组显示进度
- 📆 本月目标 = 所有 `schedule: month` 的项目级目标
- 📥 Backlog = 所有 `schedule: backlog` 的 Task
- 📥 待整合素材 = Pipeline 中 `status: new` 的 materials

**快速操作**：
- Backlog 中拖拽到今日 → `schedule: backlog → today`
- 今日 Task 完成 → 自动归入已完成区域，`status: done`
- 点击项目名 → 跳转到项目树视图
- 点击 [执行] → 调度 Crew 成员执行

**Dashboard API**：
```
GET    /api/dashboard/today          # 今日待办（schedule: today）
GET    /api/dashboard/week           # 本周计划（schedule: week + today）
GET    /api/dashboard/month          # 本月目标（schedule: month）
GET    /api/dashboard/backlog        # Backlog 列表
PATCH  /api/dashboard/reschedule     # 调整时间维度（拖拽操作）
```

#### 3.7.4 Quick Panel 聚焦 Tab

Quick Panel 的第三个 Tab 从「AI」改为**「聚焦」**，展示 Dashboard 的精华摘要（快速一瞥，不做深度操作）：

```
Quick Panel（hover 弹出）
┌─ [活跃] [关注] [聚焦] ──────────┐
│                                  │
│ 🔥 今日 (3 剩余)                 │
│   ☐ frontmatter 解析  PilotOne  │
│   ☐ 客户画像         大客户      │
│   ☐ 审阅 PR #18     PilotOne   │
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

#### 3.7.5 自动日志（_logs/）

Engine 后台自动记录每次状态变更，每日归档为 Markdown 文件：

```
{projects_dir}/
├── _logs/
│   ├── 2026-04-01.md
│   ├── 2026-04-02.md
│   └── weekly/
│       └── 2026-W14.md     # 自动周报（预留）
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
- [PilotOne V1] frontmatter 解析 — Agent: claude-code, 耗时 8min
- [大客户跟踪] 拉取 CRM 数据 — Agent: data-collect, 耗时 3min
- [大客户跟踪] 飞书消息汇总 — Crew 自动

## 新增
- [PilotOne V1] WebSocket 推送 (schedule: week)
- [工作管理] 准备周会材料 (schedule: today)

## 状态变更
- 单元测试: ready → blocked (原因: 依赖 JWT 模块)

## Agent 执行摘要
- claude-code #session-42: 实现了 frontmatter.py，新增 3 个文件

## 知识管道
- 3 条新素材已收集（📰 AI日报 / 💬 飞书摘要 / 📊 业务数据）
- 2 张 KB 卡片已同步到 Anki
```

**设计要点**：
- 完全自动生成，是状态变更的副产品
- Markdown 格式，Git 可追踪，Obsidian 可查看
- 跨项目汇总——所有项目的变更集中在一个日志里
- 为 AI 提供"项目记忆"——规划时 AI 可回顾过去日志理解项目进展

#### 3.7.6 日常迭代闭环

```
早上打开 PilotOne
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

## 4. PilotOne Local（macOS App）集成

### 4.1 三层 UI 职责分离

```
悬浮球 + Quick Panel  → 快速一瞥（窗口切换 / 今日聚焦 / Agent 角标）
主面板                → 深度操作（项目管理 / Kanban / Crew / 对话）
```

- **悬浮球 + Quick Panel**：保留现有全部功能（窗口管理、番茄钟、关注 Tab），不做改动
- **主面板**：从简单的"关注管理 + 偏好设置"升级为 VS Code 风格的多功能面板

### 4.2 主面板布局（VS Code 风格）

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
│  │         │  │ > 确认，交给代码工程师执行            │ │
│💬│         │  └─────────────────────────────────────┘ │
│  │         │                                        │
│⚙️│         │                                        │
└──┴─────────┴───────────────────────────────────────┘
 ↑      ↑                       ↑
活动栏  侧边栏                 主内容区
```

**活动栏（最左侧图标列）**：

| 图标 | 功能 | 侧边栏内容 |
|------|------|-----------|
| 📁 | 项目 | 项目树（四模式展示）+ Today Dashboard 入口 |
| 📋 | Kanban | 按状态分列的全局看板（跨项目） |
| 👥 | Crew | 数字团队成员列表 + 状态 + 常驻职责 |
| 💬 | 对话 | 历史对话记录列表 |
| ⚙️ | 设置 | 偏好 / 数据目录 / 主题 / Crew 管理 |

**交互逻辑**：
- 点击活动栏图标切换侧边栏内容
- 侧边栏选中节点 → 主内容区联动（选项目节点→Kanban + 对话；选 Crew 成员→执行历史 + 常驻职责）
- Kanban 和对话面板可拖拽调整比例，或 tab 切换
- 对话面板始终可用（底部固定或可折叠），针对当前选中上下文对话

**Crew 侧边栏详情**：

```
┌─ 👥 我的 Crew ──────────────────┐
│                                  │
│ 🟢 代码工程师        本地         │
│    claude-code | 空闲            │
│                                  │
│ 🟢 架构师           本地         │
│    claude-code | 执行中 🔄       │
│    └─ PilotOne / MCP Host 设计   │
│                                  │
│ 🔴 数据分析师        云端         │
│    未连接                        │
│                                  │
│ ⚪ 剪辑专家         云端(预留)    │
│    未配置                        │
│                                  │
│ [+ 添加成员]                     │
└──────────────────────────────────┘
```

**选中 Crew 成员时主内容区**：

```
┌─ 数据分析师 ─────────────────────────────┐
│                                          │
│ 📋 常驻职责                               │
│ ┌──────────┬──────────┬────────┬───────┐ │
│ │ 任务      │ 触发      │ 上次执行│ 状态  │ │
│ ├──────────┼──────────┼────────┼───────┤ │
│ │ 客户周报  │ 每周一9:00│ 3/31   │ ✅    │ │
│ │ 飞书汇总  │ 每天18:00 │ 今天   │ 🔄   │ │
│ │ 异常告警  │ 事件触发  │ 3/28   │ ✅    │ │
│ └──────────┴──────────┴────────┴───────┘ │
│ [+ 添加常驻职责]                          │
│                                          │
│ 📜 执行历史                               │
│   4/1 18:00 飞书汇总 — 完成，产出摘要      │
│   3/31 9:00 客户周报 — 完成，产出 report   │
│                                          │
│ 💬 对话                                   │
│   > 把周报改成每周五生成                    │
│   < 已更新，下次执行时间：4/4 周五 9:00     │
└──────────────────────────────────────────┘
```

### 4.3 Engine 进程管理（EngineManager）

PilotOne 负责 Engine 的完整生命周期：

```swift
// EngineManager.swift（新增）
class EngineManager {
    static let shared = EngineManager()
    
    private var engineProcess: Process?
    private let port = 19840
    private let healthURL = URL(string: "http://localhost:19840/api/health")!
    
    func start()   // AppDelegate.applicationDidFinishLaunching 调用
    func stop()    // AppDelegate.applicationWillTerminate 调用
    func restart() // Engine 崩溃时自动重启（最多 3 次）
}
```

**启动流程**：
1. 定位 Engine 二进制（开发期：`engine/` 目录 `uvicorn`；发布期：`.app/Contents/Resources/engine/focuspilot-engine`）
2. 启动子进程，绑定 `localhost:19840`
3. 健康检查轮询 `GET /api/health`（间隔 1s，超时 30s）
4. 连接 WebSocket `/api/events`
5. 健康检查通过后通知 UI 层 Engine 就绪

**退出流程**：发送 SIGTERM → 等待 5s → SIGKILL

### 4.3 通信架构

```
PilotOne (Swift)
    │
    ├── HTTP  → localhost:19840/api/*    请求-响应：项目CRUD、Agent操作
    ├── WS    → localhost:19840/api/events  实时推送：文件变更、Agent进度
    │
    └── 本地功能不经过 Engine：
        ├── WindowService      窗口枚举/前置（AX API）
        ├── AppMonitor         App 运行监控
        ├── FocusTimerService  番茄钟
        ├── HotkeyManager      全局快捷键
        ├── FloatingBallView   悬浮球交互
        └── ConfigStore        偏好设置
```

### 4.5 Quick Panel 保持轻量

Quick Panel 定位不变——快速一瞥，不做深度操作。项目管理、Kanban、Crew、对话全部在主面板。

```
V4.3 三 Tab                     PilotOne
─────────                       ─────────
[活跃] [关注] [AI]               [活跃] [关注] [聚焦]
  ↓      ↓     ↓                  ↓      ↓      ↓
 本地   本地  CoderBridge         本地   本地   Engine
```

- **活跃/关注 Tab**：不变
- **聚焦 Tab（替代 AI Tab）**：展示 Dashboard 精华摘要——今日待办 + 本周进度 + 执行中 + 待整合素材（详见 3.7.4）
- 深度操作（项目树、Kanban、Crew 管理、对话规划、Task 创建）→ 双击悬浮球或点 Dock 图标进入主面板

### 4.5 核心数据流

**场景 1：用户在项目 Tab 选中 Task 点击执行**
```
PilotOne UI                      Engine
─────────────                    ──────
[项目 Tab] Task 行
  → 点击「执行」
  → POST /api/agents/execute
    {task_path, skill: "code"}   → Orchestrator 分析 Task
                                 → 选择 MCP Server (claude-code)
                                 → 启动 Agent 会话
  ← WS: {type: "agent.started"}
  → [Agent Tab] 自动切换显示      → Agent 执行中...
  ← WS: {type: "agent.progress",
         output: "正在分析..."}
  → 实时更新 Agent 行状态         → Agent 完成
  ← WS: {type: "agent.done",
         summary: "已完成"}      → PATCH task frontmatter
  → Task 状态自动更新为 done       status: doing → done
```

**场景 2：文件变更实时同步**
```
用户在 IDE 编辑了 task-api.md
  → FSEvents 检测到变更
  → Engine 项目引擎重新解析 frontmatter
  → WS: {type: "project.changed", path: "work/MyProject/..."}
  → PilotOne 项目 Tab 自动刷新
```

**场景 3：移动端飞书 Bot 下达指令（预留）**
```
飞书消息                         云端 Engine           本地 Engine
────────                         ──────────           ──────────
"把 login Task 分配给            → 解析意图
 Claude Code 执行"               → 判断：需本地执行
                                 → 转发给本地 Engine ──→ 接收指令
                                                      → 执行 Agent
                                 ← 结果回传 ←──────── → 完成
← 飞书回复："已完成，
  详情见 PR #42"
```

---

## 5. 部署架构

### 5.1 本地部署（V1 实现）

```
PilotOne.app
├── Contents/MacOS/PilotOne                # Swift 主进程
└── Contents/Resources/
    └── engine/
        ├── pilotone-engine                # PyInstaller 打包的 Engine 二进制
        └── skills/                        # 内置技能
```

- 用户双击 PilotOne.app → Swift 主进程自动拉起 Engine 子进程 → 退出时自动终止
- 用户感知：单个 App，无需安装 Python
- 开发期：`make engine-start` 单独启动 Python Engine 调试

### 5.2 云端部署（预留）

```
Docker
├── pilotone-engine                        # 同一份 Python Engine 代码
├── skills/
├── config.yaml                            # 云端配置（端口/认证/数据目录）
└── docker-compose.yml
```

- 同一份 Engine 代码，不同配置
- 云端 Engine 通过公网暴露 API（需认证）
- 飞书 Bot 和 Web App 连接云端 Engine

### 5.3 本地-云端协同（预留）

```
本地 Engine ←── Git 同步 ──→ 云端 Engine
     │                          │
     └── 项目数据（Markdown）────┘
```

- 项目数据通过 Git 仓库同步
- 本地/云端 Engine 独立运行，数据通过 Git 保持一致
- 任务分配：本地 Engine 处理需要 IDE 操控的任务，云端处理离线/定时任务

---

## 6. V1 范围（首版交付）

| 模块 | V1 范围 | 预留不做 |
|------|---------|---------|
| **Engine 基础** | FastAPI 服务 + 健康检查 + WebSocket | — |
| **项目引擎** | Markdown CRUD + frontmatter + 目录扫描 + FSEvents + 四模式支持 | 全文搜索 |
| **两阶段模型** | planning → ready → executing → done 状态流转 | 容器级递归自动执行 |
| **四模式** | Agile / Flow / Lite / Free 创建 + 展示 + 规划引导 | 模式切换迁移 |
| **MCP Host** | 单 Agent 调度（claude-code）| 多 Agent 并行、自动选择 |
| **Crew 数字团队** | 预置"代码工程师"1 个成员 + Crew 面板 | 自定义成员、常驻职责、云端成员 |
| **任务调度** | 即时执行 + 执行记录（SQLite）| 定时/事件触发（常驻职责） |
| **知识管道** | _materials/ + _reports/ 增量整合 + _kb/ 提炼 + 一键同步 | auto_sync 自动加工 |
| **Anki 同步** | KB 卡片 → AnkiConnect API 推送 | AnkiWeb 云端同步、复习数据回传 |
| **费曼验证** | — | 对话面板提问 + 掌握层次标记（预留） |
| **技能系统** | Engine 内部实现，用户不感知 | 自定义技能、OpenClaw 兼容 |
| **Dashboard** | 四维驾驶舱（今日/本周/本月/Backlog）+ 快速创建 Task | 本周日历拖拽视图 |
| **Task schedule** | today/week/month/backlog 四维时间管理 | — |
| **自动日志** | 每日自动归档 _logs/YYYY-MM-DD.md（含知识管道记录） | 自动周报 |
| **主面板** | VS Code 风格（活动栏 + 侧边栏 + 主内容区）| — |
| **对话面板** | 统一对话式交互（规划 + 执行） | — |
| **Swift App** | 主面板 + Quick Panel（聚焦 Tab）+ EngineManager | — |
| **部署** | PyInstaller 打包进 .app | Docker 云端部署 |
| **数据** | 可配置 Markdown 目录 | — |
| **coder-bridge** | 保留兼容，不删除 | 逐步迁移到 Engine |
| **云端** | — | 全部预留 |
| **移动端** | — | 飞书 Bot + Web App |
| **多技能** | — | PPT/视频/消息/报告等 |

### 6.1 新增文件结构

```
PilotOne/
├── PilotOne/                # Swift App（现有 ~11K 行 + 新增模块）
│   └── Services/
│       └── EngineManager.swift    # 新增：Engine 进程管理
├── engine/                  # 新增：Python Agent Engine
│   ├── pyproject.toml
│   ├── src/
│   │   ├── main.py                # FastAPI 入口
│   │   ├── project_engine/        # 项目引擎模块
│   │   │   ├── __init__.py
│   │   │   ├── scanner.py         # 目录扫描 + 项目树构建
│   │   │   ├── frontmatter.py     # YAML frontmatter 解析/写入
│   │   │   └── watcher.py         # FSEvents 文件监听
│   │   ├── mcp_host/              # MCP Host 模块
│   │   │   ├── __init__.py
│   │   │   ├── orchestrator.py    # Agent 编排器
│   │   │   ├── registry.py        # MCP Server 注册表
│   │   │   └── session.py         # 会话管理
│   │   ├── crew/                  # Crew 数字团队模块
│   │   │   ├── __init__.py
│   │   │   ├── member.py          # Crew 成员模型 + CRUD
│   │   │   └── duties.py          # 常驻职责管理
│   │   ├── scheduler/             # 任务调度模块
│   │   │   ├── __init__.py
│   │   │   ├── models.py          # SQLAlchemy 模型
│   │   │   └── runner.py          # 执行器
│   │   ├── pipeline/              # 知识管道编排模块
│   │   │   ├── __init__.py
│   │   │   ├── chain.py           # 加工链定义（collect→integrate→distill→sync）
│   │   │   ├── triggers.py        # 触发方式（manual/auto/scheduled）
│   │   │   └── anki_sync.py       # Anki 同步（AnkiConnect API）
│   │   ├── skills/                # 技能系统模块（内部实现，用户不感知）
│   │   │   ├── __init__.py
│   │   │   └── loader.py          # 技能加载器
│   │   └── api/                   # API 路由
│   │       ├── __init__.py
│   │       ├── projects.py        # /api/projects/*
│   │       ├── agents.py          # /api/agents/*
│   │       ├── crew.py            # /api/crew/*
│   │       ├── chat.py            # /api/chat/*（对话面板）
│   │       ├── scheduler.py       # /api/scheduler/*
│   │       └── ws.py              # WebSocket /api/events
│   └── tests/
├── coder-bridge/            # 现有（保留，逐步迁移）
├── docs/
└── Makefile                 # 扩展构建命令
```

### 6.2 Makefile 扩展

```makefile
# 现有命令保留
make build          # Swift App 编译
make install        # Swift App 编译+签名+安装+启动

# 新增 Engine 命令
make engine-setup   # 创建 Python 虚拟环境 + 安装依赖
make engine-start   # 开发模式启动 Engine（uvicorn --reload）
make engine-stop    # 停止 Engine
make engine-test    # 运行 Engine 测试
make engine-build   # PyInstaller 打包 Engine 二进制
make full-install   # Swift App + Engine 一起安装
```

---

## 7. 竞品对标

| 能力 | PilotOne | OpenClaw | WorkBuddy | Cursor | Devin |
|------|----------|----------|-----------|--------|-------|
| AIOS 定位 | 本地智能 OS 层 | Agent 框架 | 办公 Agent | IDE + Agent | 纯云端 Agent |
| 项目管理 | 四模式 Markdown 引擎 | — | 文档管理 | — | Playbook |
| 两阶段模型 | planning → executing | — | — | — | — |
| 多 AI 工具调度 | MCP 统一 | 模型 Gateway | 多模型切换 | 内置 | 内置 |
| 移动端 | 飞书Bot+WebApp(预留) | WhatsApp/TG | 企微/钉钉 | Web+移动 | Web+Slack |
| 云端执行 | 预留 | Mission Control | 云端模型 | Cloud VM | 纯云端 |
| 窗口管理 | 有（内置） | — | — | — | — |
| 番茄钟 | 有（内置） | — | — | — | — |
| Today Dashboard | 有 | — | — | — | — |
| 知识管道 | Materials→Reports→KB→Anki | — | — | — | — |
| 自动日志 | 有 | — | — | — | — |

**差异化定位**：PilotOne 是本地优先的智能 AIOS，唯一同时提供"四模式项目管理 + 两阶段 Agent 编排 + 窗口管理 + 番茄钟 + Today Dashboard"的桌面平台。Slogan：**"You plan. PilotOne builds."**

---

## 8. 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| Python Engine 增加 App 体积 | ~50MB | 桌面应用可接受；PyInstaller 可压缩 |
| Engine 崩溃影响体验 | 项目/Agent Tab 不可用 | EngineManager 自动重启（最多 3 次）；窗口管理/番茄钟不受影响（纯本地功能） |
| MCP 协议各工具支持不一 | 部分工具无法接入 | V1 仅支持 claude-code（MCP 支持最完善）；其他工具后续适配 |
| 双进程调试复杂度 | 开发效率降低 | make engine-start 独立调试；Engine 有独立日志和测试 |
| 数据目录指向 Vault 时的冲突 | Obsidian 和 Engine 同时写文件 | Engine 写入前检查文件 mtime；建议 Obsidian 侧只读 |
