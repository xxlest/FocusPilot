# Studio 对话消息级失败重试 — 设计 spec

> 日期：2026-06-22 ｜ 载体：**V1 设计层**（文档 + 原型）
> 上一轮（任务级重试）：[2026-06-21-studio-retry-design.md](2026-06-21-studio-retry-design.md)
> 来源：本会话头脑风暴 —— 用户提出"对话失败与任务失败合并、重试=重发上一轮 prompt"的简化。

## 1. 背景与动机

上一轮做了**任务级** `run_state` 重试（整卡变色 + 卡片底部按钮 + 详情头部右上角按钮）。本轮按用户反馈调整为**对话消息级**呈现：对话流里某一轮 AI 回复失败/超时时，在**那条消息气泡内部**嵌报错 + 重试，覆盖 Studio 详情对话 + 全局快捷对话助手 `#chatWindow`；并**移除**详情头部右上角那个按钮。

## 2. 核心模型（统一·简化）

**一个概念**：对话流里 assistant 这一轮 `failed/timeout` → 气泡内显示 `⚠ 报错文案` + 紧跟一行「↻ 重试」；点击 = **在保留的会话上下文里重发上一轮 user prompt**（resume）。

- **一处真相、两处呈现**（有任务时）：同一个 executor Run 失败 = `run_state=failed/timeout`，在**看板卡片**=整卡变色+底部按钮（任务级，上一轮，保留），在**详情对话流**=失败 Run 消息内嵌重试（消息级，本轮）。**同一个 `retryTask` 动作**，不是两套逻辑。
- **自由聊天**（`#chatWindow`，无任务）：assistant 消息加轻量状态 `msg_state: ok | failed | timeout`；失败时同样气泡内 `⚠ 报错` + 「↻ 重试」；点击 = 重发上一轮 user prompt。
- **边界**：任务内**自动接力 Run**（无 user prompt，如评估 Agent 接力）失败时，重试 = resume 重跑这一步（用户无感、无 prompt 重发，但语义等价"再试一次这一轮"）。

> **明确砍掉**（相对最初构想）：不做结构化 `message.error{ kind, text }` 分类建模（auth/network/...），报错文案直接展示即可。属过度设计。

## 3. 数据模型

- **任务对话**：直接**复用 `run_state`**（[04-studio §2.4](../../fp-ui/04-studio.md)），不新增字段。
- **自由聊天**：`StudioSession` 的 assistant 消息加 `msg_state: ok | failed | timeout`（轻量标记；报错文案取失败原因直接展示，不结构化）。

## 4. 呈现形态（消息气泡内嵌）

失败消息气泡内，自上而下：`⚠ <报错文案>`（如「未登录 · 请先 /login」「执行超时」）→ 紧跟一行「↻ 重试」按钮。
- **配色**：沿用 [DesignGuide §5.10](../../DesignGuide.md) —— 中性描边（`separator`）+ `textSecondary` 文字，**不用任何状态色**。
- **位置**：气泡内、报错正下方。**不**在界面右上角、**不**在项目视图固定区域。

## 5. 移除

详情头部右上角「↻ 重试」（上一轮 Task 6，原型 [00-layout-prototype.html:4323](../../fp-ui/00-layout-prototype.html:4323)；04-studio §7.4 "详情头部在删除旁显示重试" 那句）→ **移除**，失败重试改由对话流内消息承载。

## 6. 保留

看板/各视图卡片整卡变色 + 卡片底部「↻ 重试」（任务级，上一轮，不动）。

## 7. 文档/原型同步清单

| 文件 | 落点 | 改动 |
|------|------|------|
| `docs/fp-ui/04-studio.md` | §7.4 详情对话 | 失败 Run 消息块内嵌「⚠报错 + ↻重试」；**删除**上一轮加的"详情头部在删除旁显示重试"那句 |
| `docs/fp-ui/00-layout.md` | §全局快捷对话助手（[91](../../fp-ui/00-layout.md:91)） | 补"消息失败呈现：assistant 消息 `failed/timeout` 时气泡内 `⚠报错 + ↻重试`，点击=重发上一轮 prompt" |
| `docs/fp-ui/09-focusbar.md` | 对话入口 | 一句指向 chatWindow 失败呈现（不重复规格） |
| `docs/PRD.md` / `docs/Architecture.md` | StudioSession message | assistant 消息加 `msg_state: ok\|failed\|timeout`（自由聊天失败） |
| `docs/DesignGuide.md` | §5.10 | 补"对话消息内嵌重试"形态，与任务级卡片按钮并列说明位置差异（消息内 vs 卡片底部） |
| `docs/fp-ui/00-layout-prototype.html` | 详情对话流（[4343 静态](../../fp-ui/00-layout-prototype.html:4343) / [8737 动态 convHtml](../../fp-ui/00-layout-prototype.html:8737)）、chatWindow（[14443](../../fp-ui/00-layout-prototype.html:14443)）、头部按钮（[4323](../../fp-ui/00-layout-prototype.html:4323)） | 失败 Run 消息块加「⚠报错 + ↻重试」；chatWindow 失败消息加「⚠报错 + ↻重试」+ 重发逻辑；**移除** 4323 头部重试按钮 |

## 8. 验收用例

1. 详情对话流里一个 `failed/timeout` 的 Run 消息：气泡内显示 `⚠报错 + ↻重试`；点击 → `run_state→queued`（复用 `retryTask`）。
2. chatWindow 一条 `failed` 的 assistant 消息：气泡内 `⚠报错 + ↻重试`；点击 → 重发上一轮 user prompt。
3. 详情头部**不再有**右上角重试按钮。
4. 看板卡片整卡变色 + 底部按钮保持不变。
5. 重试按钮中性色，不含任何状态色。

## 9. 非目标 / V2

结构化 error 分类（kind: auth/network/...）；多轮失败的批量重试。

## 10. 自检记录

- **占位**：无 TBD（chatWindow 消息渲染的精确 HTML 结构留 writing-plans 阶段定位）。
- **一致性**：消息级与任务级是同一失败的两处呈现，`retryTask` 复用；自由聊天用轻量 `msg_state`。
- **scope**：单一实现计划可覆盖（6 处同步）。
- **简化**：相对最初构想，砍掉了 ①②两套模型 + `message.error` 结构化建模。
