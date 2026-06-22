# Studio 对话消息级失败重试 — 设计 spec (v2)

> 日期：2026-06-22 ｜ 载体：**V1 设计层**（文档 + 原型）
> 上一轮（任务级重试）：[2026-06-21-studio-retry-design.md](2026-06-21-studio-retry-design.md) —— 其"看板/泳道卡片底部重试按钮"被本轮 v2 收敛移除。
> 来源：本会话头脑风暴 + 两轮 review。v2 关键决策：**重试唯一入口 = 任务详情对话框**；卡片只显示状态、不放按钮。

## 1. 背景与动机

最初诉求（用户 Multica 截图）：失败时重试按钮在**对话框内部**、不在角落。上一轮误做成"任务级卡片按钮 + 详情头部右上角按钮"，且经核实**覆盖只 2/5**（看板+泳道有、列表/Inspector/Home 无，因后三者独立渲染不调 `buildTaskCardHtml`）、`retryTask` 只刷看板。本轮 v2 回到原诉求并彻底简化。

## 2. 核心模型（统一·v2）

- **重试唯一入口 = 任务详情对话框**：任何视图（看板/泳道/列表/Inspector/Home）的失败任务，**点开详情对话框**即可重试；各视图卡片**不放**重试按钮 → "覆盖不全"问题从根消除。
- **统一呈现、两类承载**（措辞修正，非"同一个 retryTask"）：
  - **任务对话**（详情）：失败 Run 消息 = `run_state ∈ {failed,timeout}` → 气泡内嵌重试 = `retryTask`（重跑 Run）。
  - **自由聊天**（`#chatWindow`）：assistant 消息 = `msg_state ∈ {failed,timeout}` → 气泡内嵌重试 = 重发上一轮 user prompt。
  - 二者**共享同一种气泡呈现**（`⚠报错 + ↻重试`），**承载不同**（`run_state` vs `msg_state`）。
- **边界**：任务内自动接力 Run（无 user prompt）失败，重试 = resume 重跑这一步（用户无感）。

## 3. 数据模型

- **任务对话**：复用 `run_state`，不新增。
- **自由聊天**：`StudioSession` 的 assistant 消息加 `msg_state: ok | failed | timeout`（轻量；报错文案直接展示，不结构化）。落 **PRD / 04-studio**，**不进 Architecture**（那是 V4.3 Swift 架构，勿混入 V1 设计态字段）。

## 4. 呈现形态（消息气泡内嵌）

失败气泡内：`⚠ <报错文案>` → 紧跟一行「↻ 重试」按钮。中性色（沿用 [DesignGuide §5.10](../../DesignGuide.md)：`separator` 描边 + `textSecondary`，**不用状态色**）。位置在气泡内、报错正下方。

## 5. `retryTask` 刷新口径（关键·v2 修正）

`retryTask(id)`：`run_state → queued` 后必须**两处都刷**：
1. **刷新详情对话流**（失败气泡 → 排队态，若详情打开）；
2. **调 [`refreshStudioTaskViews()`](../../fp-ui/00-layout-prototype.html:7396)** —— 重渲染看板/Focus列表/泳道/时间轴的整卡 tint。

> **为什么不能只刷详情**：整卡 tint 由 `execStateOf(run_state)` **渲染时现算**；详情是**半透明覆盖层**（`rgba(0,0,0,.4)`），背景卡片露得出来、关闭后更直接可见。只刷详情则背景红卡 tint 不重算 → 反向重犯"刷新太窄"。
> **待 writing-plans 核**：`refreshStudioTaskViews` 覆盖看板/列表/泳道/时间轴；**Inspector 任务投影 / Home 若也显示 run_state tint，需一并刷**（不够则补刷或扩这个函数）。

## 6. 移除 / 保留 / 提示

- **移除**：① 看板/泳道卡片底部 `fp-retry-btn` 按钮（上一轮，原型 [7469](../../fp-ui/00-layout-prototype.html:7469) 区）；② 详情头部右上角按钮（[4323](../../fp-ui/00-layout-prototype.html:4323)）。
- **保留**：各视图卡片**整卡变色**（`run_state` tint，纯状态显示）。
- **提示（nit）**：`failed/timeout` 卡片加 `cursor:pointer` + `title="点开详情可重试"`，让用户知道入口在详情。

## 7. 文档/原型同步清单

| 文件 | 落点 | 改动 |
|------|------|------|
| `docs/fp-ui/00-layout-prototype.html` | 详情对话流（[4343 静态](../../fp-ui/00-layout-prototype.html:4343) / [8737 动态](../../fp-ui/00-layout-prototype.html:8737)）、chatWindow（[14443](../../fp-ui/00-layout-prototype.html:14443)）、`retryTask`、卡片按钮（[7469](../../fp-ui/00-layout-prototype.html:7469)）、头部按钮（[4323](../../fp-ui/00-layout-prototype.html:4323)） | 失败 Run / chatWindow 消息气泡内嵌「⚠报错+↻重试」；`retryTask` 改"刷详情 + `refreshStudioTaskViews()`"；**移除** 7469 卡片按钮 + 4323 头部按钮；失败卡加 cursor/title 提示 |
| `docs/fp-ui/04-studio.md` | §7.1（[582](../../fp-ui/04-studio.md:582)）、§7.4 | §7.1 **删**"常驻↻重试…列表/泳道同款"整段卡片按钮描述；§7.4 写"失败 Run 消息气泡内嵌重试 + 点击刷新详情与各视图 tint"，删头部右上角那句 |
| `docs/fp-ui/00-layout.md` | §全局快捷对话助手（[91](../../fp-ui/00-layout.md:91)） | 补"消息失败呈现：assistant `failed/timeout` 时气泡内 ⚠报错+↻重试，点击重发上一轮 prompt" |
| `docs/fp-ui/09-focusbar.md` | 对话入口 | 一句指向 chatWindow 失败呈现 |
| `docs/PRD.md` | StudioSession message | 加 `msg_state: ok\|failed\|timeout` |
| `docs/DesignGuide.md` | §5.10 | **改写**为"消息内嵌重试"形态，**删除**卡片底部按钮规格（上一轮写的） |

## 8. 验收用例

1. 任意视图（看板/泳道/列表/Inspector/Home）的卡片**无**重试按钮，仅整卡变色 + cursor/title 提示。
2. 任意视图点开任务详情 → 对话流失败 Run 消息内嵌「↻ 重试」；点击 → `run_state→queued`。
3. 重试后**所有显示 tint 的视图**卡片同步变排队琥珀（不只详情）—— 关闭详情看背景卡已不是红。
4. chatWindow 一条 `failed` 消息：气泡内 ⚠报错+↻重试；点击 → 重发上一轮 prompt。
5. 详情头部**无**右上角重试按钮。
6. 重试按钮中性色，不含状态色。

## 9. 前置 Task 0（实现计划第一个 task）

地基修复，必须先做：① 移除 7469 卡片按钮 + 4323 头部按钮；② `retryTask` 改为"刷详情对话流 + `refreshStudioTaskViews()`"（核 Inspector/Home tint 是否需补刷）。这是本轮功能正确的硬前提，否则内嵌重试点了背景卡不变。

## 10. 非目标 / V2

结构化 error 分类（auth/network/...）；多轮失败批量重试。

## 11. 自检记录

- **占位**：无（chatWindow/详情对话消息渲染的精确 HTML 留 writing-plans 定位）。
- **一致性**：单一入口（详情对话框）消除覆盖问题；`retryTask` 刷新口径含 `refreshStudioTaskViews` 解决背景 tint；自由聊天用 `msg_state`、措辞"统一呈现两类承载"不再夸大。
- **scope**：单一实现计划可覆盖（前置 Task 0 + 同步清单）。
- **相对 v1 的变更**：移除卡片按钮（不再 2/5 假覆盖）；`retryTask` 刷新口径修正；`msg_state` 不进 Architecture。
