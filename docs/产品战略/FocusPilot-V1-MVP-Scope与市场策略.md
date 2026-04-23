---
type: strategy
parent_project: FocusPilot
tags:
  - strategy
  - FocusPilot
  - MVP
  - V1
  - 市场策略
  - 产品定位
  - 定价
created_date: 2026-04-17
updated_date: 2026-04-17
related:
  - ../PRD.md
  - ./FocusPilot产品理念与市场定位.md
---

# FocusPilot · V1 MVP Scope 与市场策略一页纸

> 本文是 [《FocusPilot 产品理念与市场定位》](./FocusPilot产品理念与市场定位.md) 的**落地补充**，回答三个问题：
>
> 1. V1 应该做什么、不做什么（Scope）
> 2. V1 面向谁、首发在哪里（Market）
> 3. 怎么卖、卖多少钱（Pricing）
>
> 作为 [PRD](../PRD.md) 的战略附录使用，与 PRD 有冲突时以 PRD 为准。

---

## 〇、一句话定位

> **FocusPilot = AI 执行层 + 知识复利系统。**
>
> **把信息 Project 化，让 AI 承接执行，把经验沉淀成你自己的 System。**

对应理念文档的顶层命题：

```text
Everything is Code.
Project is Everything.
System is Everything.
FocusPilot runs the system.
```

---

## 一、定位校准：三次迭代的错与对

| 版本 | 定位 | 错在哪里 |
|---|---|---|
| 初版（AI CLI 兼容聚合） | 工具聚合器 | **列表范式错误**，会被 Claude/Codex/Gemini 官方产品快速覆盖 |
| Codex 修正版（Multi-Agent 执行 cockpit） | Agent 指挥中心 | **只覆盖实践系统**，丢了认知系统半边，仍停在"执行"层 |
| **本版（知行一体化自迭代系统）** | **调度范式** | **认知系统 + 实践系统双循环**，人做判断，AI 做执行 |

**核心差异化**（其他家做不到，也不会做）：

- Claude Code / Codex / Gemini CLI：永远只做**单一 Agent 能力**，不做**跨认知-实践编排层**
- Notion / Obsidian：只做**认知系统**容器，没有 Agent 执行
- Things / Linear：只做**实践系统**容器，没有信息加工与认知沉淀
- **FocusPilot：把"信息→认知规律→智慧→实践→能力"整条链路跑起来的 AI 工作层**

---

## 二、MVP 三同心圆

```text
            ┌──────────────────────────────────────────┐
            │   外圈 V3+ · 自迭代闭环                  │
            │   （认知卡片+费曼+间隔重复 + 双系统循环）│
            │  ┌────────────────────────────────────┐  │
            │  │  中圈 V2 · Project 化调度层        │  │
            │  │  （Project + Intake + Markdown     │  │
            │  │   沉淀 + Agent 任务分发）          │  │
            │  │  ┌──────────────────────────────┐  │  │
            │  │  │ 最里圈 V1 · AI 执行层        │  │  │
            │  │  │  coder-bridge + Quick Panel  │  │  │
            │  │  │  + 番茄钟 + 窗口切换         │  │  │
            │  │  └──────────────────────────────┘  │  │
            │  └────────────────────────────────────┘  │
            └──────────────────────────────────────────┘
```

### V1 Scope = 最里圈 + 中圈最小集

**核心叙事**：

> 你把一切想做的事情 **Project 化**，FocusPilot 用 AI 帮你**执行**，并把经验**沉淀成 Markdown 资产**。

**V1 必做（In Scope）**：

| 模块 | 范围 | 对应理念 |
|---|---|---|
| 悬浮球 + Quick Panel | 活跃 / 关注 / AI 三 Tab，已有 | Shell |
| coder-bridge | Claude Code / Codex / Gemini CLI 会话跟踪 | Agent 执行进程 |
| 番茄钟 + 引导休息 | FocusByTime 已有 | 专注入口 |
| 窗口切换 + 关注 | 已有 | 桌面环境 |
| **Project 容器** | 最小字段：name / type (cognition\|practice) / status / owner | Project is Everything |
| **Intake 收集箱** | to-read / 灵感 / stickies 三类；URL / 剪藏 / 快捷捕捉 | 信息采集入口 |
| **Markdown Workspace** | 内置创建 + 管理；soft schema frontmatter | 工作记忆介质 |
| **Task → Markdown Artifact** | Task 完成产生结构化产物（代码 / 文档 / 报告）入 Project | 项目化加工 |

**V1 不做（Out of Scope，放 V2+）**：

- ❌ 费曼学习法 / 间隔重复 / Anki 集成（→ V3 认知系统）
- ❌ 公众号 / 视频平台自动采集（→ V2，API/爬虫成本高）
- ❌ Obsidian / Logseq 适配器（→ V2，V1 只做自建 workspace）
- ❌ 飞书 Bot / 微信 Bot / Web 端（→ V2 云端能力）
- ❌ iOS 原生 App（长期不做，移动端走 Web/Bot）
- ❌ 团队协作 / 多人 Project（本品永远是个人工具，不做）

---

## 三、目标用户画像（ICP）

**不是大众，是硬核前排**：

### P0 · 首发 ICP（中国，V1 验证）

| 用户 | 痛点 | 钩子 |
|---|---|---|
| **Vibe Coder** | 同时跑 Claude Code / Codex / Gemini，缺执行指挥层 | coder-bridge（已可演示） |
| **独立开发者 / 一人公司** | 想把工作、内容、认知串起来，缺"把执行让出去"的系统 | Project + Agent + Markdown |
| **高密度 AI 终身学习者** | 信息过载，to-read 和 inbox 永远清不完 | Intake + AI 加工 |

### P1 · 中期扩张（V2 海外开发者）

- Obsidian Power User（Markdown 原教旨主义者）
- Readwise / Matter 深度用户（信息消化需求）
- Claude Code / Cursor heavy user（已有工具链）

### 不做的用户（划红线）

- ❌ 团队 PM（走 Jira / Linear / Plane）
- ❌ 一般消费者（走 Things / 滴答）
- ❌ 重协作场景（走 Notion / 飞书）

---

## 四、市场策略：中国首发，海外跟进

### 为什么中国区先发（反直觉但成立）

| 维度 | 中国区 | 海外 |
|---|---|---|
| **品类心智土壤** | ⭐⭐⭐ 得到 / 罗辑思维 / 小宇宙 / 小红书已训练过"第二大脑/费曼/认知方法论" | ⭐⭐ 分散在 BASB/Naval/Dalio 各自圈层 |
| **ICP 聚集度** | ⭐⭐⭐ 小红书/即刻/公众号独立开发者 + AI 学习者已在一起讨论 | ⭐⭐ 分散于 r/ObsidianMD、HN、X 等 |
| **coder-bridge 实用性** | ⭐⭐⭐ 中国 AI 用户需绕路使用 Claude/Codex，多工具切换更高频 | ⭐⭐ 官方 desktop/IDE 体验已完整 |
| **付费意愿** | ⭐⭐ 中（硬核前排愿付） | ⭐⭐⭐ 高（SaaS 订阅文化成熟） |
| **品类教育成本** | ⭐ 低 | ⭐⭐⭐ 高（新品类无直接对标） |
| **生态钩子** | ⭐⭐⭐ 飞书/微信/Anki中文/Obsidian中文圈 | ⭐⭐ Slack/Notion/Readwise |

**结论**：中国首发 **= 品类土壤好 + ICP 密度高 + coder-bridge 效用强 + 教育成本低**。付费意愿是唯一短板，但硬核前排用户（独立开发者、一人公司、Vibe Coder）付费意愿不是"中国均值"。

### 分阶段市场节奏

```text
Phase 1 · 中国首发验证（V1，~3 个月）
  渠道：小红书 / 即刻 / 公众号 / Twitter 中文圈 / B站
  钩子：coder-bridge 演示 → 引流到 Project + Markdown 叙事
  目标：100 付费用户验证 PMF

Phase 2 · 中国放量 + 海外灰度（V2，~6 个月）
  中国：飞书/微信 Bot + 云端信息采集 + Obsidian 适配器
  海外：Product Hunt + Hacker News + X 开发者圈灰度
  目标：1000 付费用户 / 海外 TOP 100 种子

Phase 3 · 海外正式（V3+，~12 个月）
  换叙事：从"知识复利系统"换成"Agent-Native Second Brain"
  对标 Notion AI + Claude / Dust.tt / Cognosys
  定价切换美元档
```

---

## 五、定价策略

**核心原则**：

1. **本地核心买断**（护城河 = Markdown-Native，不能锁定用户）
2. **云端能力订阅**（有真实成本：信息采集算力、Agent 调度、Bot 托管）
3. **永远有免费版**（验证"Markdown Workspace 本身有价值"的命题）

### 分档（中国区起步价）

| 档位 | 内容 | 价格 |
|---|---|---|
| **Free** | 本地 Markdown workspace + 窗口切换 + 番茄钟 + 单 AI session 跟踪 | ¥0 |
| **Pro 买断** | 多 Agent 调度 + Intake 自动化 + Project 容器 + 知识卡片（V3+） | **¥128** 一次性 |
| **Cloud 订阅** | 信息源自动采集（RSS/公众号/Twitter）+ 跨设备同步 + 飞书/微信 Bot + 云端 Agent | **¥49/月** 或 **¥399/年** |
| Enterprise | 暂不做 | — |

### 海外档位（V3 启用）

| 档位 | 价格 |
|---|---|
| Free | $0 |
| Pro 买断 | **$49** 一次性 |
| Cloud | **$6/月** 或 **$49/年** |

**参照锚点**：Rectangle Pro $10 买断、Things 3 $49 买断、Raycast Pro $8/月、Readwise $9.99/月。我们位于中档偏低，但**不走 Raycast $15/月高价**（本地工具无云成本支撑不了订阅理由）。

---

## 六、V1 KPI 与成功标准

| 指标 | 3 个月目标 | 口径 |
|---|---|---|
| 注册用户 | 1000 | 下载并启动过 3 天以上 |
| 付费转化 | 10% | 买断或订阅任一档 |
| 留存 | 7 日 ≥ 40% / 30 日 ≥ 20% | 至少打开一次 Quick Panel |
| NPS | ≥ 40 | 硬核前排用户更宽容，但要求 40+ |
| 品类认知 | ≥ 3 次自发传播 | 小红书/公众号/播客等内容中提到"知识复利/自迭代系统" |

**核心验证问题**（从《产品理念》十二章转化）：

1. 谁会连续 7 天打开 FocusPilot？
2. 谁愿意为 "Multi-Agent Session Radar" 付费？
3. 谁愿意把 Project 作为工作的起点而不是 Task？
4. 有多少 Free 用户在 30 天内自发升级到 Pro？

**失败信号**（任一满足则 V2 需要重做定位）：

- ❌ 付费转化 < 3%
- ❌ 30 日留存 < 10%
- ❌ 用户把 FocusPilot 用成"番茄钟"或"AI CLI 启动器"（说明上半身未被感知）

---

## 七、回答《产品理念》十二章的 5 条关键张力

| # | 张力 | V1 决策 |
|---|---|---|
| 1 | 协议严格度 vs 接入门槛 | **Soft Schema**：必要字段（title / type / project / status）强约束，其余自由扩展 |
| 2 | 信息采集自动化范围 | V1 只做 to-read（URL剪藏）+ 灵感（快捷捕捉）+ stickies；公众号/视频平台延后 |
| 3 | 知识卡片质量控制 | V1 **不做卡片**；V3 启用时走"AI 生成草稿 → 人类 Review → Anki 导出"，不自动写入 |
| 4 | AI 闭环 vs 人回路 | 内容类（代码/文档/文章）**默认人回路验收**；工具类（整理/摘要/格式转换）可 AI 闭环 |
| 5 | 自建 vs 外部适配器 | V1 自建内置 Markdown workspace；Obsidian/Logseq 适配器放 V2 开放能力 |

---

## 八、立即行动清单（待用户批准后执行）

### P0 · 文档层

- [ ] 更新 [PRD.md](../PRD.md)：将本文核心判断（ICP、Scope、定价）同步进主 PRD
- [ ] 更新 [Editions.md](../Editions.md)：统一定价表与分档口径
- [ ] 归档或合并 [PRD-v4-legacy.md](../archive/PRD-v4-legacy.md)：避免与新定位冲突

### P1 · 产品层

- [ ] 新增 Project 容器模块设计（Models.swift + ConfigStore.swift）
- [ ] 新增 Intake 收集箱模块设计（复用 Quick Panel 结构）
- [ ] 新增 Markdown Workspace 管理器（新建文件夹 + frontmatter 契约）

### P2 · 市场层

- [ ] 准备 Product Hunt / Hacker News 预热素材（含 coder-bridge 演示视频）
- [ ] 准备小红书 / 公众号内容矩阵（"AI 搭建个人系统" 选题池）
- [ ] 设计 Free → Pro 升级漏斗（关键转化点：第 3 次使用 Intake 时弹出升级引导）

---

## 变更记录

| 日期 | 版本 | 说明 |
|---|---|---|
| 2026-04-17 | v1.0 | 初版：MVP 三同心圆 + 中国首发策略 + 分层定价 |
