<!--
 * @Author: xxl
 * @Date: 2026-04-16 10:49:11
 * @LastEditors: xxl
 * @LastEditTime: 2026-05-15
 * @Description: FocusPilot UI 设计总览
 * @FilePath: /FocusPilot/docs/FP-UI.md
-->

# FocusPilot UI 设计总览

> **版本**：0.0.2
> **状态**：设计中
> **更新**：2026-05-23

---

## 1. 整体布局

类似 VS Code 布局：左活动栏 + 侧边栏 + 工作区。点击活动栏切换对应的侧边栏及工作区内容，选中项高亮显示。Studio 页面额外支持右侧栏和终端面板。

-> 详见 [00-layout.md](fp-ui/00-layout.md)

---

## 2. 文档职责边界

每个页面由两类文件组成，各守边界：

| 载体 | 命名规则 | 放这些 | 不放这些 |
|------|---------|--------|---------|
| `.md`（页面规格） | `NN-name.md` | 定位、职责边界、侧边栏内容、工作区区域职责、信息层级、核心状态、ASCII 粗线框、操作规则、数据对象简述、术语 | 精确尺寸（px/rem）、颜色值、动画参数、hover/focus 视觉细节、CSS、响应式断点 |
| `.html`（交互原型） | `NN-name-prototype.html` | 精确布局与尺寸、视觉样式、状态切换、点击交互、动效 | 需求定义、数据模型、业务规则、验收标准 |

**判断标准**：如果删掉某段内容后开发者仍能从 `.html` 原型中获取精确布局信息，则该内容不应出现在 `.md` 中。反之，如果某段业务规则只写在 `.html` 注释里，应迁移到 `.md`。

**历史参考**：PRD.md 中残留的 UI 线框图视为历史参考，后续 UI 细节以 `docs/fp-ui/` 为准。

**设计流程**：页面级最小规格 -> 关键原型探索与验证 -> 冻结后规格回写 -> 开发实现

---

## 3. 页面规格模板

所有 `fp-ui/*.md` 页面文档统一使用以下结构（各节可按需省略，但顺序不变）：

```markdown
# {页面名} 页面设计

> **状态**：{草稿 | 设计中 | 可开发}
> **更新**：{YYYY-MM-DD}
> **原型**：[NN-name-prototype.html](NN-name-prototype.html)（有原型时标注）
> **关联**：[PRD §X.X 章节名](../PRD.md)（关联时标注）

---

## 1. 定位
一句话说清页面职责。与相邻页面有歧义时，列职责边界对照表。

## 2. 侧边栏
该页面的侧边栏展示什么内容、分区结构、交互行为。
壳层结构（活动栏 + 侧边栏框架）不重复描述，参见 00-layout.md。

## 3. 工作区
工作区的区域划分（ASCII 粗线框）、各区域职责说明。
精确尺寸和视觉样式留给原型。

## 4. 核心交互
用户核心任务 -> 操作路径。按优先级排列。

## 5. 状态与规则
状态转换、硬规则、边界约束、允许/禁止的操作清单。

## 6. 数据对象
页面涉及的核心数据实体简述，详细模型引用 PRD 或 Architecture.md。

## 7. 术语
页面特有术语定义。

---

*待定项（如有未决设计问题，列在此处）*
```

**样板参考**：[01-home.md](fp-ui/01-home.md) 作为第一个按此模板编写的页面。

---

## 4. 全局交互规范

跨页面共性行为在此统一定义，各页面文档不重复描述。

### 4.1 页面切换

- 活动栏点击切换页面，侧边栏和工作区同步替换
- 切回某页面时恢复该页面上次的视图状态（Tab 选择、滚动位置）
- 键盘快捷键：`Cmd+1` ~ `Cmd+8` 切换对应页面

### 4.2 侧边栏

- `Cmd+B` 收起/展开侧边栏
- 收起后活动栏仍可见，点击活动栏图标同时展开侧边栏
- 各页面侧边栏宽度统一，不单独指定

### 4.3 弹窗行为

- 弹窗一律失焦自动关闭（NSApp.didResignActive -> dismiss）
- 弹窗关闭后如有未处理动作，通过 pending 状态标记供用户后续触发
- 确认类弹窗（删除、取消等）使用系统 NSAlert，不自定义样式

### 4.4 空状态

- 每个列表/区域定义专属空状态文案和引导操作
- 空状态不显示为错误，用中性语气引导用户下一步操作

### 4.5 跳转规则

- 跨页面跳转携带筛选条件（如 Home -> Focus 携带"今日"筛选）
- 跳转后目标页面高亮对应数据项
- 跳转不新开窗口，在当前工作区内切换

---

## 5. 页面清单

一级导航 6 项，文档规格 9 个（含已合并的 02-inbox 和 03-focus 历史参考）。

| 活动栏 | 页面 | 说明 | 规格状态 | 规格文档 | 原型 |
|--------|------|------|---------|---------|------|
| 🏠 | **Home** | 全局概览入口：摘要数字条 + 重点列表 + 对话视图（与快捷助手/Studio Session 同源） | **可开发** | [01-home.md](fp-ui/01-home.md) | [00-layout-prototype.html](fp-ui/00-layout-prototype.html) |
| 📂 | **Projects** | 记忆与输入管理层：Inbox 收集（Tab）+ 项目资产沉淀（Tab） | **可开发** | [05-area-projects.md](fp-ui/05-area-projects.md) | [00-layout-prototype.html](fp-ui/00-layout-prototype.html) |
| 💻 | **Studio** | 跨项目 AI 工作台：任务视图（默认看板 + 泳道/列表/时间轴视图，时间轴支持按目标/项目分组，泳道支持 Workspace/执行 Agent 分组）+ 项目视图（工作项/对话/Diff/终端）+ Workspace + ExecutionRun | **可开发** | [04-studio.md](fp-ui/04-studio.md) | [00-layout-prototype.html](fp-ui/00-layout-prototype.html) |
| 🧠 | **Review** | 复习与内化中心：今日复习 / 内化挑战 / 卡片库 / 统计 | **可开发** | [06-review.md](fp-ui/06-review.md) | [00-layout-prototype.html](fp-ui/00-layout-prototype.html)、[06-review-today-prototype.html](fp-ui/06-review-today-prototype.html)、[06-review-challenge-prototype.html](fp-ui/06-review-challenge-prototype.html) |
| 🤖 | AICrew | Agent 团队管理（成员 / Runtime 侧栏分段 + 成员动态 / 配置 / 执行记录） | **可开发** | [07-ai-crew.md](fp-ui/07-ai-crew.md) | [00-layout-prototype.html](fp-ui/00-layout-prototype.html) |
| ⚙️ | Settings | 全局配置：Studio/AICrew/Projects/通用 | **可开发** | [08-settings.md](fp-ui/08-settings.md) | [00-layout-prototype.html](fp-ui/00-layout-prototype.html) |

> **已合并**：原 Inbox（[02-inbox.md](fp-ui/02-inbox.md)）→ Projects 的 Inbox Tab；原 Focus（[03-focus.md](fp-ui/03-focus.md)）→ Studio 的全局视图。两份旧文档保留为历史参考。

### 原型策略

所有原型统一内嵌在壳层母版 `00-layout-prototype.html` 中，通过活动栏切换页面。不再为各页面维护独立的壳层代码。

| 优先级 | 页面 | 保真度 |
|:------:|------|--------|
| P0 | 00-layout（全局壳层，含全部页面工作区） | 高保真，可点击切换，已建母版 |
| P1 | 05-area-projects（含 Inbox Tab） | 中保真 |
| P2 | 08-settings | 暂保留规格，后补 |

### 原型命名规则

- 壳层母版：`00-layout-prototype.html`
- 特殊状态/流程原型：`NN-page-state-prototype.html`（如 `03-focus-session-prototype.html`）

---

## 6. 交互式原型

| 原型文件 | 覆盖范围 | 说明 |
|---------|---------|------|
| [00-layout-prototype.html](fp-ui/00-layout-prototype.html) | 全局壳层 + 各页面工作区 | 活动栏+侧边栏+工作区，可切换所有页面；覆盖 Home / Projects（含 Inbox Tab）/ Studio（含原 Focus 全局视图）/ Review / AICrew / Settings，并包含右下角全局快捷对话助手 |
| [03-focus-prototype.html](fp-ui/03-focus-prototype.html) | Focus 深水流程（历史参考） | 规划三模式+看板+列表+Task 详情页+新建弹窗。核心结构已合入壳层母版，复杂状态继续作为专项参考 |
| [03-focus-session-prototype.html](fp-ui/03-focus-session-prototype.html) | Focus Session（专项参考） | Session 模式原型。保留为专项流程参考，不再维护全局壳层 |
| [06-review-today-prototype.html](fp-ui/06-review-today-prototype.html) | Review 今日复习（专项参考） | 队列概览、逐卡复习、完成后引导内化。核心状态已合入壳层母版，专项文件保留为流程参考 |
| [06-review-challenge-prototype.html](fp-ui/06-review-challenge-prototype.html) | Review 内化挑战（专项参考） | 费曼复述、场景应用、结果反馈。核心状态已合入壳层母版，专项文件保留为流程参考 |

### 6.1 浮球/Focus Bar 任务数据：单一同源池 + 常驻自检

母版 `00-layout-prototype.html` 中，浮球**规划清单**（今日/本周/本月/全局）与 **Focus Bar 各状态下拉**（未读/待规划/进行中/审核中/已完成/今日聚焦）的任务**全部从同一个 `FB_POOL` 任务池派生**，杜绝"同一任务在多处各写一份、可独立漂移"：

- `FB_POOL`：`id → {标题/状态/项目/未读标记/副标题}`，是浮球域任务属性的唯一来源；所有 id 均为 `RUN_DETAILS` 已有项，点击详情统一走 `openRunDetail`。
- `planScopes`：规划清单各 scope 仅存成员 id；**`all`（全局规划）自动 = 今日∪本周∪本月并集**，保证全局是各子集的超集（修复过去"全局 < 子集"的包含倒置）。
- Focus Bar 下拉内容与 `bar-num` 计数均由池按状态/未读派生，**计数恒等于列表条数**。
- **看板 `workItems` 是独立的真实任务数据，不并入本池**（轻量统一：不改动详情面板路径，浮球/bar 仍走 `openRunDetail`、看板走自身详情）。

**常驻自检（P3.7）**：母版内置一段不变量自检，访问 `00-layout-prototype.html?selfcheck`（或 `#selfcheck`）时运行，断言并在页面顶部显示 PASS/FAIL 横幅（结果亦写入 `window.__SELFCHECK__`）。校验项：全局=并集(I1)、三处计数一致(I2)、今日聚焦=今日规划(I3)、展示 id 详情可开(I4)、`.float-action` 行恰好 3 列即箭头不换行(I5)、下拉属性与池一致(I6)。改动浮球/Focus Bar 数据或结构后，应带 `?selfcheck` 复跑确认全绿，避免"断言只贴当轮功能"导致回归漏网。

---

## 7. 技术架构

前端：Swift 5 + AppKit/SwiftUI（macOS 原生）

后端整合方向：
- **Multica**（裁剪后个人版）：Agent Runtime 执行能力、Runtime/Agent 配置模型、Workspace 数据模型、Task Queue
- **Plane**：项目管理结构参考（Cycles/Modules/Views/Stickies）
- **Z Code / Codex**：Studio 会话模式、多 Agent 框架切换、对话式开发 ADE

-> 详见 [PRD.md](PRD.md) §2 产品架构
