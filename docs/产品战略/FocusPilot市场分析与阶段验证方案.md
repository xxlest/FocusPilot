---
type: strategy
parent_project: FocusPilot
tags:
  - strategy
  - FocusPilot
  - 市场分析
  - 阶段验证
  - 获客
  - 定价
  - 成本测算
created_date: 2026-04-17
updated_date: 2026-04-17
related:
  - ./FocusPilot产品理念与市场定位.md
  - ./FocusPilot-V1-MVP-Scope与市场策略.md
  - ../PRD.md
  - ../Editions.md
---

# FocusPilot 市场分析与阶段验证方案

> 结论先行：FocusPilot 不应定位为 AI CLI 聚合器，也不应先用“中国用户需要翻墙”作为核心商业理由。真正的市场机会是 AI 执行成本下降后，个人工作系统缺少一个能把信息、项目、Agent 执行、状态追踪、复盘日志和长期记忆串起来的本地优先工作层。
>
> 推荐路径：**中国硬核前排首发验证 -> 本地 Pro 买断收费 -> 云端订阅后置 -> 海外灰度跟进**。

---

## 1. 战略定位

### 1.1 一句话定位

**FocusPilot 是给 AI-heavy 独立开发者和研究型工作者的 macOS 个人 AI 工作层。**

它用 Markdown workspace 承载长期记忆，用 Project 组织认知与实践，用 Agent 承接执行，用 Dashboard 和 Quick Panel 管理今日聚焦、AI 会话、执行状态和复盘日志，最终把信息转化为能力，把执行沉淀为系统。

### 1.2 内部北极星

来自 [《FocusPilot产品理念与市场定位》](./FocusPilot产品理念与市场定位.md)：

```text
Everything is Code.
Project is Everything.
System is Everything.
FocusPilot runs the system.
```

对外不要直接卖“AIOS”或“知行一体化系统”，这两个表达适合作为内部战略和深度用户教育。首版对外应使用更具体的价值表达：

```text
你的 AI agent 很强，但你的工作系统还没准备好。
FocusPilot 把 AI 会话、项目任务、执行状态和 Markdown 记忆连成一个闭环。
```

### 1.3 当前产品资产

从 [PRD](../PRD.md) 和 [Editions](../Editions.md) 看，FocusPilot 已经具备三类资产：

| 资产 | 已有或规划能力 | 市场意义 |
|---|---|---|
| 桌面入口 | 悬浮球、Quick Panel、窗口管理、番茄钟 | 形成 macOS 高频触点，区别于普通 Web 工具 |
| Agent 执行层 | coder-bridge、Claude Code / Codex / Gemini CLI 会话管理、后续 MCP Host | 能切入 AI-heavy developer 的真实痛点 |
| 工作记忆层 | Project、Task、Markdown frontmatter、Execution Log、Knowledge Pipeline | 决定它不是“启动器”，而是长期系统 |

---

## 2. 市场背景

### 2.1 大趋势：AI 编码和 Agent 已进入高采用、低信任阶段

公开数据支持三个判断：

| 事实 | 证据 | 对 FocusPilot 的含义 |
|---|---|---|
| AI 工具采用率已经很高 | Stack Overflow 2025 Developer Survey 显示，84% 开发者使用或计划使用 AI 工具；但 46% 不信任 AI 输出准确性 | 用户不缺 AI 工具，缺验证、状态、上下文、日志和人类验收机制 |
| Agent 热度高，但价值验证不足 | Gartner 预测到 2027 年底超过 40% Agentic AI 项目会因成本、价值不清或风险控制不足被取消 | 不能卖“Agent 平台”概念，必须卖清晰场景和可验证 ROI |
| 组织级 AI 仍处在试验期 | McKinsey 2025 State of AI 显示，多数组织仍在实验或试点，62% 至少在实验 AI agents，高绩效组织更强调 workflow redesign | FocusPilot 的机会不是模型能力，而是个人 workflow redesign |
| 官方 AI coding 产品快速扩张 | Claude Code 已覆盖 terminal、IDE、desktop app、browser；Codex 已覆盖 app、CLI、IDE、cloud tasks；Gemini CLI 是开源 terminal agent 且支持 MCP | FocusPilot 不能和官方工具抢“执行入口”，要做跨工具的工作系统层 |

### 2.2 品类判断：从“执行稀缺”变成“判断和系统稀缺”

传统任务管理工具解决的是“别漏事”。AI coding 工具解决的是“帮你做事”。FocusPilot 应解决的是：

```text
该做什么
为什么做
交给谁做
做到哪里了
结果是否可靠
经验如何沉淀
下一轮如何调整
```

这意味着 FocusPilot 不在单一品类里竞争，而是在几个品类交汇处创建新位置：

| 原有品类 | 用户买它为了什么 | FocusPilot 的切入方式 |
|---|---|---|
| Raycast / Alfred | 快速启动、命令入口、效率层 | FocusPilot 也有桌面入口，但重点不是命令，而是 AI 执行状态 |
| Things / Todoist / 滴答 | 任务记录和今日安排 | FocusPilot 的 Task 是可交给 Agent 执行的意图单元 |
| Notion / Obsidian | 知识组织、笔记、第二大脑 | FocusPilot 使用 Markdown 记忆，但增加执行和复盘闭环 |
| Cursor / Claude Code / Codex | 写代码、改代码、修 bug | FocusPilot 不替代它们，而是管理它们的任务、状态和产物 |
| Linear / Jira | 团队协作和 issue 流转 | FocusPilot 是个人工具，不做团队协作 |

### 2.3 核心机会

**AI-heavy 个人工作者正在从“我用 AI 写代码”进入“我同时调度多个 AI 执行流”的阶段，但个人系统仍停留在待办、笔记、终端和聊天记录碎片中。**

FocusPilot 的机会是成为这类人的：

```text
Personal AI Work Layer
Local-first Project Memory
Agent Execution Cockpit
Markdown-native Self-Iteration System
```

---

## 3. 目标市场与用户分层

### 3.1 首发 ICP

首发不要面向“大众生产力用户”。首发 ICP 应极窄：

| 优先级 | 用户 | 特征 | 核心痛点 | 首版钩子 |
|---|---|---|---|---|
| P0 | AI-heavy 独立开发者 | macOS，已用 Claude Code / Codex / Cursor / Gemini CLI | 多个 AI 会话散落在终端、IDE 和项目目录中，结果难追踪 | AI Session Radar + Quick Panel |
| P0 | 一人公司 / Side Project 开发者 | 同时做代码、内容、研究、产品 | 项目规划和执行断裂，AI 产物没有沉淀 | Project + Execution Log |
| P1 | 研究型工作者 / 技术写作者 | 有大量 to-read、材料、报告需求 | 信息过载，知识不能转成判断和实践 | Markdown Workspace + Report |
| P1 | Obsidian / Markdown power user | 已接受文件化工作流 | 笔记系统没有执行层 | Markdown frontmatter 契约 |
| P2 | 普通任务管理用户 | 主要需要提醒和待办 | 认知成本高，付费意愿不确定 | 暂不主攻 |

### 3.2 中国先发还是全球先发

推荐：**中国先发验证，全球不关闭。**

| 维度 | 中国首发 | 全球首发 |
|---|---|---|
| ICP 触达 | 即刻、V2EX、公众号、少数派、小红书、B 站、AI 开发者群可以快速触达硬核用户 | Product Hunt、HN、Reddit、X 分散，需要强英文表达和成熟 demo |
| 痛点强度 | AI 工具可用性、代理、多工具绕路、中文知识流和本地项目管理叠加 | 官方工具可用性强，用户对“中间层”要求更高 |
| 产品教育 | “第二大脑、知识复利、费曼、个人系统”中文语境有土壤 | 英文需转译为 personal AI work system / local-first execution layer |
| 付费能力 | 大众低，但硬核前排可付费 | 更高，但竞争和完成度要求更高 |
| 风险 | 容易被误解为翻墙/代理工具 | 容易被误解为又一个 Agent wrapper |

结论：首发应选择中国硬核前排用户，用中文内容完成品类教育和真实使用验证；英文站点和海外 waitlist 可以同步开，但不作为前 3 个月的主战场。

---

## 4. 竞品与价格锚点

### 4.1 竞品地图

| 类别 | 产品 | 价格锚点 | 对 FocusPilot 的启发 |
---|---|---:|---|
| Mac 效率工具 | Raycast | Pro $8/月年付或 $10/月月付 | 免费基础能力 + AI/Cloud 订阅是可接受模型 |
| Mac 买断工具 | CleanShot X | $29 买断，含一年更新，续更 $19/年 | 本地工具适合买断 + 年更新 |
| Apple 个人任务管理 | Things 3 | Mac $49.99 买断 | 高质量个人工具可以卖 $49 左右 |
| AI coding IDE | Cursor | Pro $20/月，Pro+ $60/月，Ultra $200/月 | 若包含模型额度，可高订阅；BYOK 本地工具不能直接对标 |
| AI coding agent | Codex / Claude Code / Gemini CLI | 多数包含在官方订阅或免费额度中 | 官方已覆盖执行层，FocusPilot 应做跨工具系统层 |

### 4.2 定价原则

1. 本地版不承担模型成本，不宜一开始做高额月订阅。
2. 本地版应按高质量 Mac 工具卖买断。
3. 云端 Engine、远程访问、自动采集、Bot、同步和备份有持续成本，可以订阅。
4. 早期用户购买的是产品方向和长期信任，价格要低于正式版，但不能免费到底。

### 4.3 推荐定价

| 阶段 | 中国区 | 海外 | 说明 |
|---|---:|---:|---|
| Private Beta | 免费，邀请制 | Free beta | 用于验证，不用于收入 |
| Early Supporter | ¥68-98 买断 | $19-29 买断 | 前 100-300 人，含 V1 正式版和一年更新 |
| Local Pro 正式版 | ¥198 买断 | $39-49 买断 | 本地完整能力，BYOK |
| 年度更新包 | ¥68-98/年 | $19/年 | 可选，继续拿大版本更新 |
| Cloud | ¥29-39/月或 ¥199-299/年 | $6-8/月或 $59-79/年 | 云端 Engine、远程访问、自动采集 |
| Cloud + AI Quota | ¥69-99/月 | $12-15/月 | 仅在你承担模型成本后推出 |

---

## 5. 推出节奏

### 5.1 总体路线

```text
Phase 0: 定位验证和用户访谈，2 周
Phase 1: 私测可用闭环，4-6 周
Phase 2: 付费 Early Access，6-8 周
Phase 3: V1 正式发布，8-12 周
Phase 4: 云端和海外灰度，12-24 周
```

### 5.2 Phase 0: 定位验证

目标：验证用户是否理解并认同“个人 AI 工作层”。

| 项目 | 内容 |
|---|---|
| 时间 | 2 周 |
| 产品状态 | 可以只有 demo、截图、录屏、当前可运行版本 |
| 核心问题 | 用户痛点到底是 AI 会话管理、项目执行日志、Markdown 记忆，还是只是代理和工具兼容 |
| 目标样本 | 30 个深度访谈，至少 20 个来自 P0 ICP |
| 成功标准 | 15 人以上明确表达“我现在就有这个问题”；8 人以上愿意加入私测；3 人以上愿意预付或明确价格接受 |
| 失败信号 | 大多数人只关心翻墙、API、Claude 平替、普通番茄钟 |

输出物：

| 输出 | 用途 |
|---|---|
| Landing Page v0 | 测试一句话定位 |
| 90 秒 demo 视频 | 测试用户是否看得懂 |
| 访谈记录模板 | 归纳高频痛点 |
| Waitlist 表单 | 筛选 ICP |

### 5.3 Phase 1: 私测可用闭环

目标：验证用户是否连续使用，而不是只觉得概念好。

| 项目 | 内容 |
|---|---|
| 时间 | 4-6 周 |
| 用户 | 30-50 个私测用户 |
| 产品闭环 | Quick Panel -> AI Session Radar -> Project -> Task -> Execution Log -> 今日复盘 |
| 核心指标 | 7 日留存、每周打开次数、Agent 会话追踪数、Project 创建数、Execution Log 数 |
| 成功标准 | 7 日留存 >= 35%；30 个用户中至少 10 人每周使用 3 次以上；至少 10 人创建真实项目 |
| 失败信号 | 用户只使用窗口切换和番茄钟，不使用 AI 会话和 Project |

V1 私测必须保留的能力：

| 能力 | 理由 |
|---|---|
| AI Session Radar | 最容易展示差异化 |
| Project 容器 | 防止沦为工具启动器 |
| Execution Log | 形成可复盘和可沉淀的证据 |
| Today Focus | 提高日常打开频率 |
| Markdown Workspace | 形成长期资产 |

### 5.4 Phase 2: 付费 Early Access

目标：验证愿意为本地个人 AI 工作层付费，而不只是免费试用。

| 项目 | 内容 |
|---|---|
| 时间 | 6-8 周 |
| 定价 | ¥68-98 买断，限前 100-300 人 |
| 获客 | 中文内容矩阵 + 小范围社群 + 开发者社区 |
| 成功标准 | 100 个付费用户；付费转化 >= 8%；退款率 < 8%；30 日留存 >= 20% |
| 失败信号 | 付费转化 < 3%；用户付费理由集中在“支持作者”，而不是真实工作流价值 |

推荐只卖一个 SKU：

```text
FocusPilot Early Supporter
¥98，一次性买断
包含 V1 正式版 + 一年更新 + 私测群 + 路线投票权
```

### 5.5 Phase 3: V1 正式发布

目标：验证公开市场能否稳定获客，并形成可重复渠道。

| 项目 | 内容 |
|---|---|
| 时间 | 8-12 周 |
| 定价 | Free + Local Pro ¥198 |
| 渠道 | 少数派、V2EX、即刻、公众号、B 站、X 中文圈 |
| 成功标准 | 1000 下载；300 激活；100 付费；30 日留存 >= 20%；自然传播 >= 10 条 |
| 失败信号 | 下载多但激活低，说明定位不清或安装阻力高 |

### 5.6 Phase 4: 云端和海外灰度

目标：验证云端订阅价值和英文市场反应。

| 项目 | 内容 |
|---|---|
| 时间 | 12-24 周 |
| 云端能力 | 远程查看、Bot 通知、自动采集、跨设备同步、备份 |
| 海外渠道 | Product Hunt、Hacker News、Reddit、X、Indie Hackers |
| 成功标准 | 50 个云端订阅；海外 waitlist 500；英文 demo 转化率 >= 5% |
| 失败信号 | 云端订阅只被当作同步功能，不能支撑月费 |

---

## 6. 获客营销方案

### 6.1 内容主线

不要泛泛讲“AI 提效”。内容应围绕三个冲突展开：

| 冲突 | 标题方向 |
|---|---|
| AI 很强，但工作系统没准备好 | “为什么你用 Claude Code 越多，项目反而越乱？” |
| 待办工具只记事，不承接 AI 执行 | “任务管理工具在 AI 时代为什么不够用了？” |
| 笔记系统只沉淀认知，不驱动实践 | “Obsidian 是记忆，FocusPilot 是执行层” |

### 6.2 中国区渠道

| 渠道 | 用法 | 目标 |
|---|---|---|
| 即刻 | Build in public，每周发一次产品进展和真实工作流 | 触达独立开发者和 AI 工具用户 |
| V2EX | 发布具体问题和 Mac 工具 demo，不发宏大愿景 | 获得技术用户和早期反馈 |
| 少数派 | 长文讲“个人 AI 工作层”和 macOS 工具体验 | 建立高质量工具心智 |
| 公众号 | 连载产品理念、AI 工作流、案例复盘 | 积累信任和搜索资产 |
| B 站 | 3-5 分钟 demo，展示多 Agent 会话和项目执行闭环 | 让用户看懂产品 |
| 小红书 | 更轻量地讲“AI 自我管理系统”和视觉 demo | 测试非开发者扩展 |
| 微信群 / 飞书群 | 私测群、访谈、Bug 反馈和路线投票 | 提升留存和转化 |

### 6.3 海外渠道

| 渠道 | 用法 | 前置条件 |
|---|---|---|
| Product Hunt | V1 稳定后发布，强调 local-first personal AI work system | 英文官网、视频、支付、文档完善 |
| Hacker News | Show HN，突出技术实现和 Markdown/local-first | 开源部分协议或 CLI 更容易被接受 |
| Reddit | r/macapps、r/ClaudeAI、r/cursor、r/ObsidianMD | 需要真实截图和避免营销口吻 |
| X / Indie Hackers | Build in public，持续展示路线 | 创始人英文表达稳定 |
| YouTube | 3-5 个 workflow demo | 产品完成度足够 |

### 6.4 Lead Magnet

早期不要靠广告。用可下载资产换 waitlist：

| 免费资产 | 作用 |
|---|---|
| AI Project Workspace Template | 吸引 Markdown / Obsidian 用户 |
| Claude Code 多会话管理指南 | 吸引 AI coding 用户 |
| Agent Execution Log 模板 | 证明 FocusPilot 不只是工具 |
| Vibe Coding 项目复盘模板 | 把用户从“玩 AI”拉到“做项目” |

### 6.5 转化漏斗

```text
内容 / Demo
  -> Landing Page
  -> Waitlist / 私测申请
  -> 访谈筛选
  -> 私测群
  -> 连续 7 天使用任务
  -> Early Supporter 付费
  -> 案例复盘
  -> 公开传播
```

关键点：不要让用户下载后自由探索。必须给一个 7 天 onboarding 任务：

| Day | 用户任务 |
|---|---|
| Day 1 | 创建第一个 Project |
| Day 2 | 绑定或追踪一个 AI coding session |
| Day 3 | 把一个 Task 交给 AI 执行 |
| Day 4 | 查看 Execution Log |
| Day 5 | 用 Today Focus 安排当日工作 |
| Day 6 | 把一个产物沉淀到 Markdown workspace |
| Day 7 | 做一次周复盘，并回答是否愿意付费 |

---

## 7. 验证指标

### 7.1 核心假设

| 假设 | 验证方式 | 通过标准 |
|---|---|---|
| H1: 用户确实有 AI 会话和项目执行碎片化痛点 | 30 个访谈 | >= 50% 主动提到“任务/会话/结果散落” |
| H2: 用户理解 Project-first 工作方式 | 私测 onboarding | >= 40% 用户创建真实 Project |
| H3: AI Session Radar 能形成高频使用 | 产品埋点 | 私测用户每周平均 >= 5 次打开 Quick Panel |
| H4: Execution Log 是付费理由 | 付费问卷 | >= 30% 付费用户把“执行记录/复盘”列为前三理由 |
| H5: 本地买断可成立 | Early Access | 100 个付费用户，退款率 < 8% |
| H6: 云端订阅有独立价值 | Cloud waitlist | >= 20% 付费本地用户愿意预订云端 |

### 7.2 北极星指标

早期北极星不要用下载数。建议使用：

```text
Weekly Executed Projects
```

定义：一周内至少有 1 个 Task 被 AI 执行或产生 Execution Log 的 Project 数。

辅助指标：

| 指标 | 目标 |
|---|---:|
| 私测 7 日留存 | >= 35% |
| 私测 30 日留存 | >= 20% |
| Early Access 付费转化 | >= 8% |
| 平均每用户 Project 数 | >= 2 |
| 平均每用户 Agent session 追踪数 | >= 5/周 |
| NPS | >= 35 |
| 退款率 | < 8% |

### 7.3 阶段性 Go / No-Go

| 阶段 | Go 条件 | No-Go 或 Pivot 条件 |
|---|---|---|
| Phase 0 | 30 访谈中 15 个强痛点，8 个愿私测 | 用户只认为它是番茄钟或启动器 |
| Phase 1 | 50 私测中 15 个周活跃，10 个真实 Project | AI Session Radar 无人高频使用 |
| Phase 2 | 100 付费，30 日留存 >= 20% | 付费 < 30 或退款 > 15% |
| Phase 3 | 1000 下载，100 付费，至少 10 个自然传播案例 | 获客完全依赖创始人私域 |
| Phase 4 | 50 云端订阅或 200 云端 waitlist | 用户不愿为云端持续付费 |

---

## 8. 阶段成本测算

### 8.1 成本口径

本方案拆成两类成本：

| 类型 | 说明 |
|---|---|
| 现金成本 | 实际支出，包括服务器、域名、设计、工具、激励、投放、支付手续费 |
| 全成本 | 现金成本 + 创始人时间机会成本。若按独立开发者月机会成本 ¥30,000-50,000 估算，验证总成本会显著上升 |

### 8.2 Phase 0 成本，2 周

| 项目 | 低配 | 标准 |
|---|---:|---:|
| 域名 / 邮箱 / landing page | ¥200 | ¥800 |
| 访谈激励，30 人 | ¥0 | ¥1,500-3,000 |
| Demo 视频录制和剪辑 | ¥0 | ¥500-2,000 |
| 问卷 / 表单 / 分析工具 | ¥0 | ¥300 |
| 小额社群推广 | ¥0 | ¥1,000 |
| 合计现金成本 | **¥200-1,000** | **¥3,000-7,000** |
| 创始人时间，全成本参考 | +¥15,000-25,000 | +¥15,000-25,000 |

Phase 0 不建议投广告。核心是访谈质量，不是线索数量。

### 8.3 Phase 1 成本，4-6 周

| 项目 | 低配 | 标准 |
|---|---:|---:|
| Apple Developer Program | 约 $99/年，折合约 ¥700-800 | 约 ¥700-800 |
| 崩溃/日志/下载分发 | ¥0-300/月 | ¥300-1,000/月 |
| 私测用户激励 | ¥0 | ¥2,000-5,000 |
| 设计素材 / 图标 / 官网优化 | ¥0-1,000 | ¥3,000-8,000 |
| AI 测试和演示成本 | ¥300-1,000 | ¥1,000-3,000 |
| 社群运营和内容制作 | ¥0 | ¥1,000-3,000 |
| 合计现金成本 | **¥2,000-5,000** | **¥10,000-20,000** |
| 创始人时间，全成本参考 | +¥45,000-75,000 | +¥45,000-75,000 |

### 8.4 Phase 2 成本，6-8 周

| 项目 | 低配 | 标准 |
|---|---:|---:|
| 支付和授权系统 | ¥0-1,000 | ¥2,000-5,000 |
| 官网和文档完善 | ¥500-2,000 | ¥5,000-10,000 |
| 内容制作，文章/视频 | ¥0-2,000 | ¥5,000-15,000 |
| KOL / 社群合作 | ¥0-3,000 | ¥10,000-30,000 |
| 用户支持和私测群 | ¥0 | ¥2,000-5,000 |
| 小额广告测试 | ¥0 | ¥5,000-10,000 |
| 合计现金成本 | **¥3,000-10,000** | **¥25,000-70,000** |
| 创始人时间，全成本参考 | +¥60,000-100,000 | +¥60,000-100,000 |

Phase 2 的收入目标：

| 目标 | 金额 |
|---|---:|
| 保守，30 人 × ¥98 | ¥2,940 |
| 目标，100 人 × ¥98 | ¥9,800 |
| 乐观，300 人 × ¥98 | ¥29,400 |

如果 100 个 Early Supporter 都拿不到，不建议直接进入大规模 V1 发布。

### 8.5 Phase 3 成本，8-12 周

| 项目 | 低配 | 标准 |
|---|---:|---:|
| 官网 / 文档 / 教程体系 | ¥2,000-5,000 | ¥10,000-30,000 |
| 发布素材，视频/图文/demo | ¥2,000-5,000 | ¥10,000-30,000 |
| PR / KOL / 媒体合作 | ¥0-10,000 | ¥20,000-60,000 |
| 客服和社群 | ¥0-3,000 | ¥5,000-15,000 |
| 基础云服务 | ¥300-1,000/月 | ¥1,000-3,000/月 |
| 合计现金成本 | **¥10,000-30,000** | **¥50,000-130,000** |
| 创始人时间，全成本参考 | +¥90,000-150,000 | +¥90,000-150,000 |

Phase 3 收入目标：

| 目标 | 金额 |
|---|---:|
| 保守，100 人 × ¥198 | ¥19,800 |
| 目标，300 人 × ¥198 | ¥59,400 |
| 乐观，1000 人 × ¥198 | ¥198,000 |

### 8.6 Phase 4 成本，12-24 周

| 项目 | 低配 | 标准 |
|---|---:|---:|
| 云端 Engine 和存储 | ¥1,000-3,000/月 | ¥5,000-15,000/月 |
| Bot 和同步基础设施 | ¥1,000-3,000/月 | ¥5,000-20,000/月 |
| 安全、备份、监控 | ¥500-2,000/月 | ¥3,000-10,000/月 |
| 英文官网 / 文档 / 支付 | ¥3,000-10,000 | ¥20,000-50,000 |
| Product Hunt / HN launch 素材 | ¥2,000-8,000 | ¥15,000-40,000 |
| 合计现金成本 | **¥20,000-60,000** | **¥100,000-300,000** |
| 创始人时间，全成本参考 | +¥120,000-300,000 | +¥120,000-300,000 |

### 8.7 阶段总成本

| 路线 | 到 Phase 2，验证付费 | 到 Phase 3，V1 正式 | 到 Phase 4，云端/海外 |
|---|---:|---:|---:|
| 极简现金成本 | ¥5,000-20,000 | ¥20,000-60,000 | ¥60,000-150,000 |
| 标准现金成本 | ¥40,000-100,000 | ¥100,000-250,000 | ¥250,000-600,000 |
| 含创始人机会成本 | ¥120,000-250,000 | ¥250,000-500,000 | ¥600,000-1,200,000 |

建议以“极简现金成本 + 高强度创始人投入”启动。不要在没有 100 个付费 Early Supporter 前投入大额广告和云端基础设施。

---

## 9. 产品路线与验证绑定

### 9.1 V1 只验证实践系统闭环

V1 不应完整实现“采集 -> 规律 -> 智慧 -> 实践 -> 判断 -> 再采集”的大闭环。V1 只验证：

```text
Project
  -> Task
  -> Agent Session
  -> Execution Log
  -> Today Review
  -> Markdown Memory
```

V1 必须克制：

| 做 | 不做 |
|---|---|
| AI Session Radar | 不做多 Agent 自动编排 |
| Project / Task 最小模型 | 不做复杂敏捷管理 |
| Execution Log | 不做完整知识图谱 |
| Today Focus | 不做日历系统 |
| Markdown Workspace | 不做 Obsidian 插件优先 |

### 9.2 V2 验证认知系统入口

V2 再加入：

| 能力 | 验证问题 |
|---|---|
| Intake 收集箱 | 用户是否愿意把信息源交给 FocusPilot |
| Report 生成 | AI 加工是否足够可靠 |
| Obsidian/Logseq 适配 | 外部 Markdown 用户是否愿意迁移一部分工作流 |
| 云端/同步/Bot | 是否有订阅理由 |

### 9.3 V3 验证完整自迭代系统

V3 再加入：

| 能力 | 验证问题 |
|---|---|
| 知识卡片 | 用户是否真的 Review 和内化 |
| Anki / 间隔重复 | 认知系统是否形成习惯 |
| 费曼验证 | 用户是否愿意被系统反问 |
| 自动周报和自迭代建议 | 系统是否能指导下一轮行动 |

---

## 10. 关键风险与应对

| 风险 | 表现 | 应对 |
|---|---|---|
| 定位过抽象 | 用户说“听起来很大，但不知道怎么用” | 首屏只讲 AI 会话、项目执行、今日复盘 |
| 被官方 AI 工具覆盖 | Codex/Claude/Gemini 做了 app 和多 agent 管理 | 转向跨工具、Markdown 记忆、人类验收和复盘 |
| 用户只用桌面小工具 | 番茄钟和窗口切换使用高，Project 使用低 | Onboarding 强制创建 Project，Pro 价值绑定 Project |
| Markdown 契约太重 | 用户不愿填字段 | 使用 soft schema，只强制最小字段 |
| 付费意愿不足 | 大量免费用户不付费 | 缩窄 ICP，降低首版功能，做 Early Supporter 买断 |
| 云端成本失控 | 订阅收入覆盖不了模型和服务器 | Cloud 先 BYOK，AI quota 后置 |
| 国内渠道误解 | 被当作翻墙/Claude 工具 | 内容持续强调 personal AI work system |

---

## 11. 90 天执行计划

### 第 1-2 周

| 任务 | 交付物 |
|---|---|
| 完成 30 个 ICP 访谈 | 访谈结论和痛点排序 |
| 建 landing page | Waitlist 表单 |
| 录制 90 秒 demo | AI Session Radar + Project + Log |
| 建私测群 | 30-50 人候选池 |

### 第 3-6 周

| 任务 | 交付物 |
|---|---|
| 发布私测版 | 可下载 app |
| 完成 onboarding | 7 天任务 |
| 每周收集反馈 | 周报和问题列表 |
| 修复核心体验 | 留存优先，不扩功能 |

### 第 7-10 周

| 任务 | 交付物 |
|---|---|
| 开 Early Access | ¥98 买断 |
| 发布 5 篇内容 | 即刻、公众号、V2EX、少数派、B站 |
| 建案例库 | 3 个真实用户工作流 |
| 统计付费和留存 | 是否进入 V1 |

### 第 11-12 周

| 任务 | 交付物 |
|---|---|
| 做 Go / No-Go 评审 | 指标对照 |
| 决定 V1 scope | 删除非核心功能 |
| 更新定价和路线 | Pro 正式价 |
| 准备正式发布 | 官网、文档、视频、支付 |

---

## 12. 建议的最小预算

如果你作为 solo founder 推进，建议设定三个预算闸门：

| 闸门 | 预算 | 触发条件 |
|---|---:|---|
| Gate 0: 定位验证 | ¥5,000 | 不需要产品完全稳定，只要能 demo |
| Gate 1: 私测验证 | 累计 ¥20,000 | 访谈通过，至少 30 人愿意私测 |
| Gate 2: 付费验证 | 累计 ¥60,000 | 私测 7 日留存 >= 35%，才扩大获客 |
| Gate 3: V1 发布 | 累计 ¥150,000 | 100 个 Early Supporter 达成 |
| Gate 4: 云端/海外 | 累计 ¥300,000+ | 本地版自然收入可覆盖基础开支 |

强建议：在 Gate 2 之前，不投入大额广告、不做云端、不做 iOS、不做多端同步。

---

## 13. 最终建议

### 13.1 市场策略

```text
中国硬核前排首发
  -> 以 AI Session Radar 切入
  -> 用 Project Execution Log 证明长期价值
  -> 用 Markdown Workspace 形成护城河
  -> 用 Cloud/Bot/自动采集建立订阅
  -> 海外以 local-first personal AI work system 灰度跟进
```

### 13.2 产品策略

首版只解决一个主问题：

```text
AI agent 已经能做事，但用户缺一个个人工作系统来承接、追踪、验收和沉淀这些执行。
```

### 13.3 商业策略

```text
Free 获取用户
Early Supporter 验证付费
Local Pro 买断建立现金流
Cloud 订阅建立长期收入
海外美元价后置
```

### 13.4 成功判定

如果 90 天内达到：

| 指标 | 目标 |
|---|---:|
| 私测用户 | 50 |
| 付费用户 | 100 |
| 30 日留存 | >= 20% |
| 自然传播案例 | >= 10 |
| 退款率 | < 8% |

则进入 V1 正式发布。

如果 90 天内未达到：

| 指标 | 问题 |
|---|---|
| 付费 < 30 | 定位或付费价值不成立 |
| 30 日留存 < 10% | 高频场景不成立 |
| Project 使用率低 | 产品被用成工具启动器，需要重做 onboarding |
| 用户只关心翻墙/API | 市场误解，需要重做叙事 |

则不应继续扩功能，应回到 ICP 和首屏价值重做。

---

## 参考资料

- [FocusPilot 产品需求文档](../PRD.md)
- [FocusPilot 产品家族与定价规划](../Editions.md)
- [FocusPilot 产品理念与市场定位](./FocusPilot产品理念与市场定位.md)
- [FocusPilot V1 MVP Scope 与市场策略](./FocusPilot-V1-MVP-Scope与市场策略.md)
- [Stack Overflow 2025 Developer Survey: AI](https://survey.stackoverflow.co/2025/ai)
- [Stack Overflow 2025 Developer Survey press release](https://stackoverflow.co/company/press/archive/stack-overflow-2025-developer-survey/)
- [Gartner: Over 40% of agentic AI projects will be canceled by end of 2027](https://www.gartner.com/en/newsroom/press-releases/2025-06-25-gartner-predicts-over-40-percent-of-agentic-ai-projects-will-be-canceled-by-end-of-2027)
- [McKinsey: The State of AI 2025](https://www.mckinsey.com/capabilities/quantumblack/our-insights/the-state-of-ai/)
- [Claude Code overview](https://code.claude.com/docs/en/overview)
- [OpenAI Codex app](https://openai.com/index/introducing-the-codex-app/)
- [OpenAI Codex cloud docs](https://platform.openai.com/docs/codex/overview)
- [OpenAI Codex CLI help](https://help.openai.com/en/articles/11096431-openai-codex-ci-getting-started)
- [Gemini CLI official documentation](https://google-gemini.github.io/gemini-cli/)
- [Gemini CLI GitHub repository](https://github.com/google-gemini/gemini-cli)
- [Raycast pricing](https://www.raycast.com/pricing)
- [Cursor pricing](https://cursor.com/pricing)
- [CleanShot X pricing](https://cleanshot.com/pricing)
- [Things 3 App Store](https://apps.apple.com/us/app/things-3/id904280696?mt=12)
