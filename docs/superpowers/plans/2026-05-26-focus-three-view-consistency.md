# Focus 三视图数据一致性 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 统一 Focus 页面五个子视图（fp-year/fp-week/fp-day/kanban/list）的任务数据，确保三个视图（规划/看板/列表）在任意 scope 下展示内容一致。

**Architecture:** 定义 12 条标准演示任务（Canonical Demo Tasks），以看板视图的现有数据为权威来源，重写规划视图（fp-year 目标树 + 甘特）、列表视图、周视图（fp-week）、日视图（fp-day）的静态 HTML，使所有视图共享相同任务集合。通过 `data-fp-schedule` 属性统一标记，JS `applyFocusFilter()` 函数统一过滤五个视图。

**Tech Stack:** 纯静态 HTML + 内联 JS（原型文件 `00-layout-prototype.html`），Markdown（`03-focus.md`）

---

## 标准演示任务表（Canonical Demo Tasks）

以下为五个视图的唯一数据源，所有视图必须从此表派生。12 条任务 = 11 活跃 + 1 阻塞。

| ID | Title | Status | Schedule | Priority | Mode | Agent | Goal | Source | Due |
|---|---|---|---|---|---|---|---|---|---|
| FP-001 | 数据模型设计 | done | week | P0 | auto | 代码工程师 | Q2/4月/WS | area | ✓04-15 |
| FP-002 | 看板状态模型实现 | in_progress | week | P0 | auto | 代码工程师 | Q2/4月/WS | area | 04-20 |
| FP-003 | Agent Pull 执行管道 | todo | week | P1 | auto | 代码工程师 | Q2/4月/WS | area | 04-25 |
| FP-004 | Terminal 手动执行模式 | todo | week | P1 | manual | — | Q2/4月/WS | area | 04-28 |
| FP-005 | 规划引擎接口设计 | in_evaluation | week | P0 | auto | 代码工程师 | Q2/4月/WS | area | 04-17 |
| FP-006 | 主题系统适配 | backlog | month | P2 | auto | 代码工程师 | Q2/5月/AI | area | — |
| FP-007 | PRD 文档整合 | done | week | P1 | manual | — | — | area | ✓04-16 |
| FP-008 | 配置迁移脚本 | blocked | — | P2 | auto | — | — | area | — |
| FP-009 | Anki 同步接口设计 | backlog | month | P2 | auto | 代码工程师 | Q2/5月/AI Crew | area | — |
| FP-010 | 整理本周会议记录 | todo | today | P2 | manual | — | — | adhoc | 05-24 |
| FP-011 | 研究 Multica 执行模型 | in_progress | today | P1 | manual | — | — | adhoc | 05-24 |

> FP-008（blocked）在所有视图中折叠/隐藏显示，不参与 scope 过滤计数。

### Scope 过滤推导

| Scope | 过滤条件 | 匹配任务 | 数量 |
|---|---|---|---|
| 全局规划 | 无筛选 | FP-001~011 + FP-008 | 12 |
| 本月计划 | schedule ∈ {today, week, month} | FP-001~007, FP-009~011 | 10 |
| 本周计划 | schedule ∈ {today, week} | FP-001~005, FP-007, FP-010, FP-011 | 8 |
| 今日聚焦 | schedule = today | FP-010, FP-011 | 2 |
| Agent 执行中 | agent 标记 | FP-002, FP-011 | 2 |
| 等我决策 | decision 标记 | FP-005 | 1 |

### 视图 × Scope 展示预期

| 视图 | 全局(12) | 本月(10) | 本周(8) | 今日(2) |
|---|---|---|---|---|
| 规划(fp-year) | 完整目标树+甘特 | 过滤后树+甘特 | 切换fp-week | 切换fp-day |
| 看板 | 全部卡片 | 过滤卡片 | 过滤卡片 | 过滤卡片 |
| 列表 | 全部行 | 过滤行 | 过滤行 | 过滤行 |

---

## 文件结构

| 操作 | 文件 | 职责 |
|---|---|---|
| Modify | `docs/fp-ui/00-layout-prototype.html:2218-2330` | 列表视图 — 补齐缺失任务 |
| Modify | `docs/fp-ui/00-layout-prototype.html:1615-1760` | fp-year 左侧目标树 — 补齐缺失任务+新增未关联目标组 |
| Modify | `docs/fp-ui/00-layout-prototype.html:1765-1845` | fp-year 右侧甘特 — 同步目标树任务 |
| Modify | `docs/fp-ui/00-layout-prototype.html:1850-1962` | fp-week 左+右 — 用标准任务替换幽灵任务 |
| Modify | `docs/fp-ui/00-layout-prototype.html:1965-2058` | fp-day 左+右 — 用标准任务替换幽灵任务 |
| Modify | `docs/fp-ui/00-layout-prototype.html:3303-3355` | JS applyFocusFilter — 扩展 fp-week/fp-day 过滤 |
| Modify | `docs/fp-ui/03-focus.md:506-560` | 侧边栏计数与规则同步 |

---

### Task 1: 列表视图补齐

**Files:**
- Modify: `docs/fp-ui/00-layout-prototype.html:2218-2330`

**现状问题：** 列表只有 7 行（Group1: FP-001~004+006, Group2: FP-010~011），缺少 FP-005/FP-007/FP-008/FP-009。且 FP-006 错误归入"4月/WS"组。

**目标：** 三个分组，共 12 行（含 1 行 blocked 隐藏）。

- [ ] **Step 1: 重写列表 Group 1 — Q2/4月 WS原型**

替换 `docs/fp-ui/00-layout-prototype.html` 中列表 Group 1 的 tbody 内容。原来 5 行，改为 5 行（FP-001~005），移除 FP-006（它属于 5月目标组）。

新增 FP-005（in_evaluation）行：
```html
<tr class="fp-list-row" onclick="openTaskDetail()" style="cursor:pointer" data-fp-schedule="week" data-fp-mode="auto" data-fp-decision="yes">
  <td style="padding:8px 10px"><span class="pill" style="font-size:10px;padding:1px 6px;border-color:rgba(167,139,250,.3);color:var(--purple)">◈ 评估</span></td>
  <td style="padding:8px 10px"><strong>规划引擎接口设计</strong></td>
  <td style="padding:8px 10px;font-size:12px;color:var(--muted)">本周</td>
  <td style="padding:8px 10px"><span class="pill" style="font-size:9px;padding:1px 5px;border-color:rgba(248,113,113,.3);color:var(--red)">P0</span></td>
  <td style="padding:8px 10px;font-size:12px">🤖</td>
  <td style="padding:8px 10px;font-size:11px;color:var(--amber)">等你处理评估</td>
  <td style="padding:8px 10px;font-size:11px;color:var(--dim)">area</td>
  <td style="padding:8px 10px;font-size:11px;font-family:var(--mono);color:var(--muted)">04-17</td>
</tr>
```

Group 1 标题计数改为 `5 项`，移除 FP-006（主题系统适配）行。

- [ ] **Step 2: 新增列表 Group 2 — Q2/5月 AI+Crew**

在 Group 1 末尾后、原 Group 2（未关联目标）之前，插入新 Group：

```html
<!-- Group 2: 5月目标 -->
<div style="display:flex;align-items:center;gap:8px;padding:12px 0 6px;font-size:12px;font-weight:700;color:var(--muted);border-bottom:1px solid var(--line-soft);margin-top:8px">
  📆 Q2 / 5月 — AI + Crew 集成
  <span style="font-weight:400;color:var(--dim);font-family:var(--mono);font-size:11px" class="fp-list-group-count">2 项</span>
</div>
<table style="width:100%;border-collapse:collapse" class="fp-list-table">
  <thead>...(复制 Group 1 thead)</thead>
  <tbody>
    <!-- FP-006 主题系统适配 -->
    <tr class="fp-list-row" style="cursor:pointer" data-fp-schedule="month" data-fp-mode="auto">
      <td style="padding:8px 10px"><span class="pill" style="font-size:10px;padding:1px 6px;border-color:rgba(112,120,135,.3);color:var(--dim)">◦ 待排</span></td>
      <td style="padding:8px 10px"><strong>主题系统适配</strong></td>
      <td style="padding:8px 10px;font-size:12px;color:var(--dim)">本月</td>
      <td style="padding:8px 10px"><span class="pill" style="font-size:9px;padding:1px 5px;border-color:rgba(112,120,135,.3);color:var(--dim)">P2</span></td>
      <td style="padding:8px 10px;font-size:12px">🤖</td>
      <td style="padding:8px 10px;font-size:11px;color:var(--muted)">代码工程师</td>
      <td style="padding:8px 10px;font-size:11px;color:var(--dim)">area</td>
      <td style="padding:8px 10px;font-size:11px;font-family:var(--mono);color:var(--muted)">—</td>
    </tr>
    <!-- FP-009 Anki 同步接口设计 -->
    <tr class="fp-list-row" style="cursor:pointer" data-fp-schedule="month" data-fp-mode="auto">
      <td style="padding:8px 10px"><span class="pill" style="font-size:10px;padding:1px 6px;border-color:rgba(112,120,135,.3);color:var(--dim)">◦ 待排</span></td>
      <td style="padding:8px 10px"><strong>Anki 同步接口设计</strong></td>
      <td style="padding:8px 10px;font-size:12px;color:var(--dim)">本月</td>
      <td style="padding:8px 10px"><span class="pill" style="font-size:9px;padding:1px 5px;border-color:rgba(112,120,135,.3);color:var(--dim)">P2</span></td>
      <td style="padding:8px 10px;font-size:12px">🤖</td>
      <td style="padding:8px 10px;font-size:11px;color:var(--muted)">代码工程师</td>
      <td style="padding:8px 10px;font-size:11px;color:var(--dim)">area</td>
      <td style="padding:8px 10px;font-size:11px;font-family:var(--mono);color:var(--muted)">—</td>
    </tr>
  </tbody>
</table>
```

- [ ] **Step 3: 重写列表 Group 3 — 未关联目标**

原 Group 2 改为 Group 3，从 2 行扩充到 4 行，新增 FP-007（done）和 FP-008（blocked）：

```html
<!-- FP-007 PRD 文档整合 -->
<tr class="fp-list-row" style="cursor:pointer" data-fp-schedule="week" data-fp-mode="manual">
  <td style="padding:8px 10px"><span class="pill green" style="font-size:10px;padding:1px 6px">✓ 完成</span></td>
  <td style="padding:8px 10px;text-decoration:line-through;color:var(--dim)"><strong style="color:var(--dim)">PRD 文档整合</strong></td>
  <td style="padding:8px 10px;font-size:12px;color:var(--dim)">本周</td>
  <td style="padding:8px 10px"><span class="pill" style="font-size:9px;padding:1px 5px;border-color:rgba(242,196,15,.3);color:var(--amber)">P1</span></td>
  <td style="padding:8px 10px;font-size:12px">🖐</td>
  <td style="padding:8px 10px;font-size:11px;color:var(--muted)">手动完成</td>
  <td style="padding:8px 10px;font-size:11px;color:var(--dim)">area</td>
  <td style="padding:8px 10px;font-size:11px;font-family:var(--mono);color:var(--green)">✓ 04-16</td>
</tr>
<!-- FP-008 配置迁移脚本 (blocked) -->
<tr class="fp-list-row" style="cursor:pointer;opacity:.5" data-fp-schedule="" data-fp-mode="auto">
  <td style="padding:8px 10px"><span class="pill" style="font-size:10px;padding:1px 6px;border-color:rgba(249,115,22,.3);color:rgba(249,115,22,1)">⊘ 阻塞</span></td>
  <td style="padding:8px 10px"><strong>配置迁移脚本</strong></td>
  <td style="padding:8px 10px;font-size:12px;color:var(--dim)">—</td>
  <td style="padding:8px 10px"><span class="pill" style="font-size:9px;padding:1px 5px;border-color:rgba(112,120,135,.3);color:var(--dim)">P2</span></td>
  <td style="padding:8px 10px;font-size:12px">🤖</td>
  <td style="padding:8px 10px;font-size:11px;color:var(--muted)">代码工程师</td>
  <td style="padding:8px 10px;font-size:11px;color:var(--dim)">area</td>
  <td style="padding:8px 10px;font-size:11px;font-family:var(--mono);color:var(--muted)">—</td>
</tr>
```

Group 3 标题计数改为 `4 项`。

- [ ] **Step 4: 验证列表视图**

打开浏览器检查：
- 全局规划 scope 下列表显示 3 组共 12 行（含 1 行 blocked 半透明）
- 切换到"本月计划"，FP-008（schedule=""）被过滤隐藏，剩余 10 行可见
- 切换到"本周计划"，FP-006/FP-009（schedule=month）也被过滤，剩余 8 行
- 切换到"今日聚焦"，仅 FP-010/FP-011 可见

- [ ] **Step 5: Commit**

```bash
git add docs/fp-ui/00-layout-prototype.html
git commit -m "fix(fp-ui): Focus 列表视图补齐缺失任务并重组目标分组"
```

---

### Task 2: fp-year 左侧目标树补齐

**Files:**
- Modify: `docs/fp-ui/00-layout-prototype.html:1615-1760`

**现状问题：** 左侧目标树只有 4月目标下 5 个任务（FP-001~004 + 主题适配），缺少 FP-005 规划引擎接口设计。5月/6月目标下没有展开的任务行。没有"未关联目标"组。

**目标：** 左侧树包含全部 12 个任务，结构如下：

```
Q2 FocusPilot 0.0.1
├─ 4月 WS + Engine 原型 (5 tasks)
│  ├─ FP-001 数据模型设计 ✓           schedule=week
│  ├─ FP-002 看板状态模型实现 ●       schedule=week
│  ├─ FP-003 Agent Pull 执行管道 ○    schedule=week
│  ├─ FP-004 Terminal 手动执行模式 ○  schedule=week
│  └─ FP-005 规划引擎接口设计 ◈      schedule=week
├─ 5月 AI + Crew 集成 (2 tasks)
│  ├─ FP-006 主题系统适配 ◦          schedule=month
│  └─ FP-009 Anki 同步接口设计 ◦     schedule=month
└─ 6月 测试发布 (placeholder)
未关联目标 (4 tasks)
├─ FP-007 PRD 文档整合 ✓             schedule=week
├─ FP-008 配置迁移脚本 ⊘             schedule="" (blocked)
├─ FP-010 整理本周会议记录 ○         schedule=today
└─ FP-011 研究 Multica 执行模型 ●    schedule=today
```

- [ ] **Step 1: 4月目标组新增 FP-005**

在 4月目标树的"主题系统适配"行（当前最后一个任务）之前，插入 FP-005 行：

```html
<!-- Task: 规划引擎接口设计 (in_evaluation) -->
<div class="fp-plan-task" data-fp-schedule="week" style="margin-bottom:2px;">
  <div style="display:flex;align-items:center;gap:6px;padding:6px 8px;border-radius:var(--radius);cursor:pointer;font-size:13px;">
    <span style="font-size:10px;width:14px;visibility:hidden;flex-shrink:0;">▶</span>
    <span style="width:7px;height:7px;border-radius:50%;flex-shrink:0;border:1.5px solid var(--purple);background:var(--purple);"></span>
    <span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">规划引擎接口设计</span>
    <span style="font-size:10px;padding:1px 5px;border-radius:3px;background:rgba(248,113,113,0.12);color:var(--red);font-weight:500;">P0</span>
    <span style="font-size:9px;color:var(--amber);font-weight:500;">等你决策</span>
    <span style="font-size:10px;color:var(--dim);font-family:var(--mono);">04-17</span>
  </div>
</div>
```

更新 4月目标摘要文本从 `5 项 · 完成 1` 改为 `6 项 · 完成 1`。
（注意：当前 April 下实际只有 5 个任务行，但里面 FP-006 主题适配应该移到 5月组。所以移除主题适配后加入 FP-005，仍然是 5 个。保持 `5 项 · 完成 1`。）

实际操作：移除 4月组的"主题系统适配"行 → 新增 FP-005 行。4月组保持 5 个任务。

- [ ] **Step 2: 5月目标组展开任务**

当前 5月目标只有折叠的概要行。展开它并添加 FP-006 和 FP-009 两个任务：

替换 5月目标的 `<div data-fp-plan-month="5"...>` 内容为：

```html
<div data-fp-plan-month="5" style="margin-bottom:2px;">
  <div style="display:flex;align-items:center;gap:6px;padding:6px 8px;border-radius:var(--radius);cursor:pointer;font-size:13px;font-weight:500;">
    <span style="font-size:10px;color:var(--dim);width:14px;text-align:center;transform:rotate(90deg);flex-shrink:0;">▶</span>
    <span style="font-size:12px;flex-shrink:0;">📆</span>
    <span style="flex:1;">5月 AI + Crew 集成</span>
    <span style="font-size:10px;color:var(--dim);font-family:var(--mono);">2 项</span>
  </div>
  <div style="padding-left:22px;">
    <!-- FP-006 主题系统适配 (backlog) -->
    <div class="fp-plan-task" data-fp-schedule="month" style="margin-bottom:2px;">
      <div style="display:flex;align-items:center;gap:6px;padding:6px 8px;border-radius:var(--radius);cursor:pointer;font-size:13px;">
        <span style="font-size:10px;width:14px;visibility:hidden;flex-shrink:0;">▶</span>
        <span style="width:7px;height:7px;border-radius:50%;flex-shrink:0;border:1.5px solid #636985;background:transparent;"></span>
        <span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">主题系统适配</span>
        <span style="font-size:10px;padding:1px 5px;border-radius:3px;background:rgba(99,105,133,0.15);color:var(--dim);font-weight:500;">P2</span>
        <span style="font-size:11px;flex-shrink:0;">🤖</span>
        <span style="font-size:10px;color:var(--dim);font-family:var(--mono);">—</span>
      </div>
    </div>
    <!-- FP-009 Anki 同步接口设计 (backlog) -->
    <div class="fp-plan-task" data-fp-schedule="month" style="margin-bottom:2px;">
      <div style="display:flex;align-items:center;gap:6px;padding:6px 8px;border-radius:var(--radius);cursor:pointer;font-size:13px;">
        <span style="font-size:10px;width:14px;visibility:hidden;flex-shrink:0;">▶</span>
        <span style="width:7px;height:7px;border-radius:50%;flex-shrink:0;border:1.5px solid #636985;background:transparent;"></span>
        <span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">Anki 同步接口设计</span>
        <span style="font-size:10px;padding:1px 5px;border-radius:3px;background:rgba(99,105,133,0.15);color:var(--dim);font-weight:500;">P2</span>
        <span style="font-size:11px;flex-shrink:0;">🤖</span>
        <span style="font-size:10px;color:var(--dim);font-family:var(--mono);">—</span>
      </div>
    </div>
  </div>
</div>
```

- [ ] **Step 3: 新增"未关联目标"组**

在 Q3 placeholder 之后、目标树容器结束之前，新增独立组：

```html
<!-- 未关联目标 -->
<div style="margin-top:8px;border-top:1px solid var(--line-soft);padding-top:4px;">
  <div style="display:flex;align-items:center;gap:6px;padding:6px 8px;border-radius:var(--radius);cursor:pointer;font-size:13px;font-weight:500;">
    <span style="font-size:10px;color:var(--dim);width:14px;text-align:center;transform:rotate(90deg);flex-shrink:0;">▶</span>
    <span style="font-size:12px;flex-shrink:0;">✏️</span>
    <span style="flex:1;">未关联目标</span>
    <span style="font-size:10px;color:var(--dim);font-family:var(--mono);">4 项</span>
  </div>
  <div style="padding-left:22px;">
    <!-- FP-007 PRD 文档整合 (done) -->
    <div class="fp-plan-task" data-fp-schedule="week" style="margin-bottom:2px;">
      <div style="display:flex;align-items:center;gap:6px;padding:6px 8px;border-radius:var(--radius);cursor:pointer;font-size:13px;">
        <span style="font-size:10px;width:14px;visibility:hidden;flex-shrink:0;">▶</span>
        <span style="width:7px;height:7px;border-radius:50%;flex-shrink:0;border:1.5px solid var(--green);background:var(--green);"></span>
        <span style="flex:1;text-decoration:line-through;color:var(--dim);">PRD 文档整合</span>
        <span style="font-size:10px;padding:1px 5px;border-radius:3px;background:rgba(249,115,22,0.12);color:var(--amber);font-weight:500;">P1</span>
        <span style="font-size:11px;flex-shrink:0;">🖐</span>
        <span style="font-size:10px;color:var(--green);font-family:var(--mono);">✓ 04-16</span>
      </div>
    </div>
    <!-- FP-008 配置迁移脚本 (blocked) -->
    <div class="fp-plan-task" data-fp-schedule="" style="margin-bottom:2px;opacity:.5;">
      <div style="display:flex;align-items:center;gap:6px;padding:6px 8px;border-radius:var(--radius);cursor:pointer;font-size:13px;">
        <span style="font-size:10px;width:14px;visibility:hidden;flex-shrink:0;">▶</span>
        <span style="width:7px;height:7px;border-radius:50%;flex-shrink:0;border:1.5px solid rgba(249,115,22,.7);background:rgba(249,115,22,.3);"></span>
        <span style="flex:1;color:var(--dim);">配置迁移脚本</span>
        <span style="font-size:9px;color:rgba(249,115,22,1);">阻塞</span>
      </div>
    </div>
    <!-- FP-010 整理本周会议记录 (todo) -->
    <div class="fp-plan-task" data-fp-schedule="today" style="margin-bottom:2px;">
      <div style="display:flex;align-items:center;gap:6px;padding:6px 8px;border-radius:var(--radius);cursor:pointer;font-size:13px;">
        <span style="font-size:10px;width:14px;visibility:hidden;flex-shrink:0;">▶</span>
        <span style="width:7px;height:7px;border-radius:50%;flex-shrink:0;border:1.5px solid #9399b0;background:transparent;"></span>
        <span style="flex:1;">整理本周会议记录</span>
        <span style="font-size:10px;padding:1px 5px;border-radius:3px;background:rgba(99,105,133,0.15);color:var(--dim);font-weight:500;">P2</span>
        <span style="font-size:11px;flex-shrink:0;">🖐</span>
        <span style="font-size:10px;color:var(--dim);font-family:var(--mono);">05-24</span>
      </div>
    </div>
    <!-- FP-011 研究 Multica 执行模型 (in_progress) -->
    <div class="fp-plan-task" data-fp-schedule="today" style="margin-bottom:2px;">
      <div style="display:flex;align-items:center;gap:6px;padding:6px 8px;border-radius:var(--radius);cursor:pointer;font-size:13px;">
        <span style="font-size:10px;width:14px;visibility:hidden;flex-shrink:0;">▶</span>
        <span style="width:7px;height:7px;border-radius:50%;flex-shrink:0;border:1.5px solid #5b8af5;background:#5b8af5;"></span>
        <span style="flex:1;">研究 Multica 执行模型</span>
        <span style="font-size:10px;padding:1px 5px;border-radius:3px;background:rgba(249,115,22,0.12);color:var(--amber);font-weight:500;">P1</span>
        <span style="font-size:11px;flex-shrink:0;">🖐</span>
        <span style="font-size:10px;color:var(--dim);font-family:var(--mono);">05-24</span>
      </div>
    </div>
  </div>
</div>
```

- [ ] **Step 4: 更新目标树标题计数**

fpYearTitle 中 `12 项` 保持不变（全局确实 12 项含 blocked）。

- [ ] **Step 5: Commit**

```bash
git add docs/fp-ui/00-layout-prototype.html
git commit -m "fix(fp-ui): Focus 规划视图目标树补齐全部任务"
```

---

### Task 3: fp-year 右侧甘特同步

**Files:**
- Modify: `docs/fp-ui/00-layout-prototype.html:1765-1845`

**现状问题：** 右侧甘特有 5 个 April 条 + 3 个 May 条（Crew配置/知识管道/Anki同步），但 "知识管道" 不对应任何标准任务；缺少 FP-005 的甘特条；没有未关联目标的甘特条。

**目标：** 右侧甘特条与左侧目标树一一对应。

- [ ] **Step 1: 4月甘特区新增 FP-005 条**

在 4月最后一个甘特条（主题适配 → 但主题适配要移到 5月）之前，新增 FP-005 条。同时移除主题适配条（移到 5月区域）。

实际操作：将 4月区域 `<div data-fp-plan-month="4">` 内的甘特条改为 5 条：
- FP-001 数据模型设计 ✓ (green, ~190-240px)
- FP-002 看板状态模型 (blue, ~240-310px)
- FP-003 Agent Pull (gray, ~280-340px)
- FP-004 Terminal (gray, ~300-350px)
- FP-005 规划引擎接口 (purple, ~250-280px)

移除原来的"主题适配"条。

```html
<!-- FP-005 规划引擎 (in_evaluation) -->
<div class="fp-plan-task" data-fp-schedule="week" style="height:34px;display:flex;align-items:center;position:relative;">
  <div style="position:absolute;height:14px;border-radius:3px;cursor:pointer;overflow:hidden;white-space:nowrap;background:rgba(167,139,250,0.3);border:1px solid rgba(167,139,250,0.4);left:250px;width:30px;" title="规划引擎接口设计 ◈ 等你决策"></div>
</div>
```

- [ ] **Step 2: 5月甘特区重写**

替换 `<div data-fp-plan-month="5">` 中的 3 个任务条为 2 个标准任务条：

```html
<!-- FP-006 主题系统适配 (backlog) -->
<div class="fp-plan-task" data-fp-schedule="month" style="height:34px;display:flex;align-items:center;position:relative;">
  <div style="position:absolute;height:14px;border-radius:3px;cursor:pointer;overflow:hidden;white-space:nowrap;background:rgba(255,255,255,0.06);color:var(--dim);left:370px;width:50px;" title="主题系统适配"></div>
</div>
<!-- FP-009 Anki 同步接口设计 (backlog) -->
<div class="fp-plan-task" data-fp-schedule="month" style="height:34px;display:flex;align-items:center;position:relative;">
  <div style="position:absolute;height:14px;border-radius:3px;cursor:pointer;overflow:hidden;white-space:nowrap;background:rgba(255,255,255,0.06);color:var(--dim);left:420px;width:60px;" title="Anki 同步接口设计"></div>
</div>
```

移除原来的"知识管道"条。

- [ ] **Step 3: 新增未关联目标甘特区**

在 `<div data-fp-plan-month="6">` 结束之后、甘特容器结束之前，添加：

```html
<!-- 未关联目标 -->
<div style="height:6px;"></div>
<div style="height:6px;border-top:1px solid var(--line-soft);"></div>
<!-- FP-007 PRD 文档整合 (done) -->
<div class="fp-plan-task" data-fp-schedule="week" style="height:34px;display:flex;align-items:center;position:relative;">
  <div style="position:absolute;height:14px;border-radius:3px;cursor:pointer;overflow:hidden;white-space:nowrap;background:rgba(74,222,128,0.3);border:1px solid rgba(74,222,128,0.4);left:210px;width:30px;opacity:0.5;" title="PRD 文档整合 ✓"></div>
</div>
<!-- FP-008 配置迁移脚本 (blocked) -->
<div class="fp-plan-task" data-fp-schedule="" style="height:34px;display:flex;align-items:center;position:relative;opacity:.5;">
  <div style="position:absolute;height:14px;border-radius:3px;cursor:pointer;overflow:hidden;white-space:nowrap;background:rgba(249,115,22,0.15);border:1px dashed rgba(249,115,22,0.3);left:280px;width:30px;" title="配置迁移脚本 ⊘"></div>
</div>
<!-- FP-010 整理本周会议记录 (todo, today) -->
<div class="fp-plan-task" data-fp-schedule="today" style="height:34px;display:flex;align-items:center;position:relative;">
  <div style="position:absolute;height:14px;border-radius:3px;cursor:pointer;overflow:hidden;white-space:nowrap;background:rgba(147,153,176,0.3);border:1px solid rgba(147,153,176,0.3);left:305px;width:10px;" title="整理本周会议记录"></div>
</div>
<!-- FP-011 研究 Multica 执行模型 (in_progress, today) -->
<div class="fp-plan-task" data-fp-schedule="today" style="height:34px;display:flex;align-items:center;position:relative;">
  <div style="position:absolute;height:14px;border-radius:3px;cursor:pointer;overflow:hidden;white-space:nowrap;background:rgba(91,138,245,0.4);border:1px solid rgba(91,138,245,0.5);left:305px;width:10px;" title="研究 Multica 执行模型"></div>
</div>
```

- [ ] **Step 4: Commit**

```bash
git add docs/fp-ui/00-layout-prototype.html
git commit -m "fix(fp-ui): Focus 规划甘特条与目标树同步"
```

---

### Task 4: fp-week 用标准任务替换幽灵任务

**Files:**
- Modify: `docs/fp-ui/00-layout-prototype.html:1850-1962`

**现状问题：** fp-week 左侧有 4 个已排期 + 3 个未排期，其中 3 个未排期（读书/写周报/Anki卡片整理）是幽灵任务（不存在于 kanban）。已排期也只有 4 个，缺少 FP-001/FP-005/FP-007/FP-011。

**目标：** 本周 scope 应显示 8 个任务（schedule ∈ {today, week}）。

左侧列表按状态分两区：
- 已排期 · 8 项（全部 week/today 任务都在天级甘特上有位置）
- 未排期 · 0 项（移除幽灵任务后无未排期任务）

实际上，week scope 的所有 8 个任务都有确切的 schedule，所以都应该在甘特图上有条。但为了视觉效果，done 任务可以单独标记。

- [ ] **Step 1: 重写 fp-week 左侧任务列表**

替换 `已排期 · 4 项` 区域 + `未排期 · 3 项` 区域为：

```html
<div style="padding:6px 0 0;">
  <div style="padding:0 12px 4px;font-size:9px;font-weight:600;text-transform:uppercase;letter-spacing:0.05em;color:var(--dim);">已排期 · 8 项</div>
  <!-- FP-002 看板状态模型实现 (in_progress) -->
  <div class="fp-week-task" data-fp-schedule="week" onclick="openTaskDetail()" style="height:34px;display:flex;align-items:center;gap:6px;padding:0 12px;cursor:pointer;border-radius:var(--radius);font-size:12px;">
    <span style="width:7px;height:7px;border-radius:50%;flex-shrink:0;border:1.5px solid #5b8af5;background:#5b8af5;"></span>
    <span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">看板状态模型实现</span>
    <span style="font-size:10px;padding:2px 6px;border-radius:3px;font-weight:500;background:rgba(248,113,113,0.15);color:var(--red);">P0</span>
    <span style="font-size:11px;flex-shrink:0;">🤖</span>
  </div>
  <!-- FP-003 Agent Pull 执行管道 (todo) -->
  <div class="fp-week-task" data-fp-schedule="week" onclick="openTaskDetail()" style="height:34px;display:flex;align-items:center;gap:6px;padding:0 12px;cursor:pointer;border-radius:var(--radius);font-size:12px;">
    <span style="width:7px;height:7px;border-radius:50%;flex-shrink:0;border:1.5px solid #9399b0;background:transparent;"></span>
    <span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">Agent Pull 执行管道</span>
    <span style="font-size:10px;padding:2px 6px;border-radius:3px;font-weight:500;background:rgba(249,115,22,0.15);color:#f97316;">P1</span>
    <span style="font-size:11px;flex-shrink:0;">🤖</span>
  </div>
  <!-- FP-004 Terminal 手动执行模式 (todo) -->
  <div class="fp-week-task" data-fp-schedule="week" onclick="openTaskDetail()" style="height:34px;display:flex;align-items:center;gap:6px;padding:0 12px;cursor:pointer;border-radius:var(--radius);font-size:12px;">
    <span style="width:7px;height:7px;border-radius:50%;flex-shrink:0;border:1.5px solid #9399b0;background:transparent;"></span>
    <span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">Terminal 手动执行模式</span>
    <span style="font-size:10px;padding:2px 6px;border-radius:3px;font-weight:500;background:rgba(249,115,22,0.15);color:#f97316;">P1</span>
    <span style="font-size:11px;flex-shrink:0;">🖐</span>
  </div>
  <!-- FP-005 规划引擎接口设计 (in_evaluation) -->
  <div class="fp-week-task" data-fp-schedule="week" onclick="openTaskDetail()" style="height:34px;display:flex;align-items:center;gap:6px;padding:0 12px;cursor:pointer;border-radius:var(--radius);font-size:12px;">
    <span style="width:7px;height:7px;border-radius:50%;flex-shrink:0;border:1.5px solid var(--purple);background:var(--purple);"></span>
    <span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">规划引擎接口设计</span>
    <span style="font-size:10px;padding:2px 6px;border-radius:3px;font-weight:500;background:rgba(248,113,113,0.15);color:var(--red);">P0</span>
    <span style="font-size:9px;color:var(--amber);font-weight:500;">等你决策</span>
  </div>
  <!-- FP-010 整理本周会议记录 (todo, today) -->
  <div class="fp-week-task" data-fp-schedule="today" onclick="openTaskDetail()" style="height:34px;display:flex;align-items:center;gap:6px;padding:0 12px;cursor:pointer;border-radius:var(--radius);font-size:12px;">
    <span style="width:7px;height:7px;border-radius:50%;flex-shrink:0;border:1.5px solid #9399b0;background:transparent;"></span>
    <span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">整理本周会议记录</span>
    <span style="font-size:10px;padding:2px 6px;border-radius:3px;font-weight:500;background:rgba(99,105,133,0.2);color:var(--dim);">P2</span>
    <span style="font-size:11px;flex-shrink:0;">🖐</span>
  </div>
  <!-- FP-011 研究 Multica 执行模型 (in_progress, today) -->
  <div class="fp-week-task" data-fp-schedule="today" onclick="openTaskDetail()" style="height:34px;display:flex;align-items:center;gap:6px;padding:0 12px;cursor:pointer;border-radius:var(--radius);font-size:12px;">
    <span style="width:7px;height:7px;border-radius:50%;flex-shrink:0;border:1.5px solid #5b8af5;background:#5b8af5;"></span>
    <span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">研究 Multica 执行模型</span>
    <span style="font-size:10px;padding:2px 6px;border-radius:3px;font-weight:500;background:rgba(249,115,22,0.15);color:#f97316;">P1</span>
    <span style="font-size:11px;flex-shrink:0;">🖐</span>
  </div>
  <!-- FP-001 数据模型设计 (done) -->
  <div class="fp-week-task" data-fp-schedule="week" onclick="openTaskDetail()" style="height:34px;display:flex;align-items:center;gap:6px;padding:0 12px;cursor:pointer;border-radius:var(--radius);font-size:12px;opacity:.6;">
    <span style="width:7px;height:7px;border-radius:50%;flex-shrink:0;border:1.5px solid var(--green);background:var(--green);"></span>
    <span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;text-decoration:line-through;color:var(--dim);">数据模型设计</span>
    <span style="font-size:10px;color:var(--green);">✓</span>
  </div>
  <!-- FP-007 PRD 文档整合 (done) -->
  <div class="fp-week-task" data-fp-schedule="week" onclick="openTaskDetail()" style="height:34px;display:flex;align-items:center;gap:6px;padding:0 12px;cursor:pointer;border-radius:var(--radius);font-size:12px;opacity:.6;">
    <span style="width:7px;height:7px;border-radius:50%;flex-shrink:0;border:1.5px solid var(--green);background:var(--green);"></span>
    <span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;text-decoration:line-through;color:var(--dim);">PRD 文档整合</span>
    <span style="font-size:10px;color:var(--green);">✓</span>
  </div>
</div>
```

移除原来的"未排期 · 3 项"区域（幽灵任务）。

- [ ] **Step 2: 重写 fp-week 右侧甘特条**

替换甘特条区域，8 个条对应 8 个任务：

```html
<div style="padding:6px 0 0;">
  <div style="padding:0 12px 4px;font-size:9px;font-weight:600;text-transform:uppercase;letter-spacing:0.05em;color:var(--dim);">时间线</div>
  <!-- FP-002 看板状态模型 Mon~Wed (in_progress) -->
  <div class="fp-week-task" data-fp-schedule="week" style="height:34px;display:flex;align-items:center;position:relative;">
    <div style="position:absolute;height:14px;border-radius:3px;cursor:pointer;overflow:hidden;white-space:nowrap;display:flex;align-items:center;padding:0 6px;font-size:9px;color:rgba(255,255,255,0.8);background:rgba(91,138,245,0.4);border:1px solid rgba(91,138,245,0.5);left:4px;width:305px;" title="看板状态模型实现">看板状态模型实现</div>
  </div>
  <!-- FP-003 Agent Pull Wed~Thu (todo) -->
  <div class="fp-week-task" data-fp-schedule="week" style="height:34px;display:flex;align-items:center;position:relative;">
    <div style="position:absolute;height:14px;border-radius:3px;cursor:pointer;overflow:hidden;white-space:nowrap;display:flex;align-items:center;padding:0 6px;font-size:9px;color:rgba(255,255,255,0.6);background:rgba(147,153,176,0.3);border:1px solid rgba(147,153,176,0.3);left:210px;width:200px;" title="Agent Pull 执行管道">Agent Pull</div>
  </div>
  <!-- FP-004 Terminal Fri (todo) -->
  <div class="fp-week-task" data-fp-schedule="week" style="height:34px;display:flex;align-items:center;position:relative;">
    <div style="position:absolute;height:14px;border-radius:3px;cursor:pointer;overflow:hidden;white-space:nowrap;display:flex;align-items:center;padding:0 6px;font-size:9px;color:rgba(255,255,255,0.6);background:rgba(147,153,176,0.3);border:1px solid rgba(147,153,176,0.3);left:416px;width:99px;" title="Terminal 手动执行模式">Terminal</div>
  </div>
  <!-- FP-005 规划引擎 Tue (in_evaluation) -->
  <div class="fp-week-task" data-fp-schedule="week" style="height:34px;display:flex;align-items:center;position:relative;">
    <div style="position:absolute;height:14px;border-radius:3px;cursor:pointer;overflow:hidden;white-space:nowrap;display:flex;align-items:center;padding:0 6px;font-size:9px;color:rgba(255,255,255,0.6);background:rgba(167,139,250,0.3);border:1px solid rgba(167,139,250,0.4);left:107px;width:99px;" title="规划引擎接口设计 ◈">规划引擎</div>
  </div>
  <!-- FP-010 整理会议记录 Mon (todo, today) -->
  <div class="fp-week-task" data-fp-schedule="today" style="height:34px;display:flex;align-items:center;position:relative;">
    <div style="position:absolute;height:14px;border-radius:3px;cursor:pointer;overflow:hidden;white-space:nowrap;display:flex;align-items:center;padding:0 6px;font-size:9px;color:rgba(255,255,255,0.6);background:rgba(147,153,176,0.3);border:1px solid rgba(147,153,176,0.3);left:50px;width:50px;" title="整理本周会议记录">会议记录</div>
  </div>
  <!-- FP-011 研究 Multica Mon (in_progress, today) -->
  <div class="fp-week-task" data-fp-schedule="today" style="height:34px;display:flex;align-items:center;position:relative;">
    <div style="position:absolute;height:14px;border-radius:3px;cursor:pointer;overflow:hidden;white-space:nowrap;display:flex;align-items:center;padding:0 6px;font-size:9px;color:rgba(255,255,255,0.8);background:rgba(91,138,245,0.4);border:1px solid rgba(91,138,245,0.5);left:4px;width:99px;" title="研究 Multica 执行模型">Multica 研究</div>
  </div>
  <!-- FP-001 数据模型设计 Mon (done) -->
  <div class="fp-week-task" data-fp-schedule="week" style="height:34px;display:flex;align-items:center;position:relative;">
    <div style="position:absolute;height:14px;border-radius:3px;cursor:pointer;overflow:hidden;white-space:nowrap;display:flex;align-items:center;padding:0 6px;font-size:9px;color:rgba(255,255,255,0.5);background:rgba(74,222,128,0.3);border:1px solid rgba(74,222,128,0.4);left:4px;width:99px;opacity:0.5;" title="数据模型设计 ✓">数据模型设计 ✓</div>
  </div>
  <!-- FP-007 PRD 文档整合 Mon (done) -->
  <div class="fp-week-task" data-fp-schedule="week" style="height:34px;display:flex;align-items:center;position:relative;">
    <div style="position:absolute;height:14px;border-radius:3px;cursor:pointer;overflow:hidden;white-space:nowrap;display:flex;align-items:center;padding:0 6px;font-size:9px;color:rgba(255,255,255,0.5);background:rgba(74,222,128,0.3);border:1px solid rgba(74,222,128,0.4);left:4px;width:80px;opacity:0.5;" title="PRD 文档整合 ✓">PRD 文档整合 ✓</div>
  </div>
</div>
```

移除旧的"未排期"甘特区域。

- [ ] **Step 3: Commit**

```bash
git add docs/fp-ui/00-layout-prototype.html
git commit -m "fix(fp-ui): Focus 周视图用标准任务替换幽灵任务"
```

---

### Task 5: fp-day 用标准任务替换幽灵数据

**Files:**
- Modify: `docs/fp-ui/00-layout-prototype.html:1965-2058`

**现状问题：** fp-day 显示数据模型设计和看板状态模型（schedule=week），但 today scope 应该只显示 schedule=today 的任务。未排期区有"读书"幽灵任务。

**目标：** fp-day 只显示 FP-010 和 FP-011（schedule=today），共 2 项。

- [ ] **Step 1: 重写 fp-day 左侧任务列表**

```html
<div style="padding:6px 0 0;">
  <div style="padding:0 12px 4px;font-size:9px;font-weight:600;text-transform:uppercase;letter-spacing:0.05em;color:var(--dim);">已排时间 · 1 项</div>
  <!-- FP-011 研究 Multica 执行模型 (in_progress, 10:00-14:00) -->
  <div class="fp-day-task" data-fp-schedule="today" onclick="openTaskDetail()" style="height:34px;display:flex;align-items:center;gap:6px;padding:0 12px;cursor:pointer;border-radius:var(--radius);font-size:12px;">
    <span style="width:7px;height:7px;border-radius:50%;flex-shrink:0;border:1.5px solid #5b8af5;background:#5b8af5;"></span>
    <span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">研究 Multica 执行模型</span>
    <span style="font-size:10px;padding:2px 6px;border-radius:3px;font-weight:500;background:rgba(249,115,22,0.15);color:#f97316;">P1</span>
    <span style="font-size:11px;flex-shrink:0;">🖐</span>
  </div>
</div>
<!-- Unscheduled -->
<div style="padding:4px 0 8px;border-top:1px dashed var(--line-soft);margin-top:4px;">
  <div style="padding:4px 12px;font-size:9px;font-weight:600;text-transform:uppercase;letter-spacing:0.05em;color:var(--dim);">未排时间 · 1 项</div>
  <!-- FP-010 整理本周会议记录 (todo) -->
  <div class="fp-day-task" data-fp-schedule="today" onclick="openTaskDetail()" style="height:28px;display:flex;align-items:center;gap:6px;padding:0 12px;cursor:pointer;font-size:11px;color:var(--dim);">
    <span style="width:6px;height:6px;border-radius:50%;border:1px solid #636985;flex-shrink:0;"></span>
    <span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">整理本周会议记录</span>
    <span style="font-size:9px;color:var(--dim);">P2</span>
  </div>
</div>
```

- [ ] **Step 2: 重写 fp-day 右侧甘特条**

```html
<div style="padding:6px 0 0;">
  <div style="padding:0 12px 4px;font-size:9px;font-weight:600;text-transform:uppercase;letter-spacing:0.05em;color:var(--dim);">时间线</div>
  <!-- FP-011 研究 Multica 10:00-14:00 (in_progress) -->
  <div class="fp-day-task" data-fp-schedule="today" style="height:34px;display:flex;align-items:center;position:relative;">
    <div style="position:absolute;height:14px;border-radius:3px;cursor:pointer;overflow:hidden;white-space:nowrap;display:flex;align-items:center;padding:0 6px;font-size:9px;color:rgba(255,255,255,0.8);background:rgba(91,138,245,0.4);border:1px solid rgba(91,138,245,0.5);left:148px;width:284px;" title="研究 Multica 执行模型">研究 Multica 执行模型</div>
  </div>
</div>
<!-- Unscheduled drop targets -->
<div style="padding:4px 0 8px;border-top:1px dashed var(--line-soft);margin-top:4px;">
  <div style="padding:4px 12px;font-size:9px;font-weight:600;text-transform:uppercase;letter-spacing:0.05em;color:var(--dim);opacity:0.5;">未排时间</div>
  <div class="fp-day-task" data-fp-schedule="today" style="height:28px;display:flex;align-items:center;position:relative;border-bottom:1px dashed rgba(99,105,133,0.1);"></div>
  <div style="height:28px;display:flex;align-items:center;justify-content:center;position:relative;">
    <span style="font-size:9px;color:var(--dim);opacity:0.3;">← 拖到小时列排时</span>
  </div>
</div>
```

- [ ] **Step 3: Commit**

```bash
git add docs/fp-ui/00-layout-prototype.html
git commit -m "fix(fp-ui): Focus 日视图用标准任务替换幽灵数据"
```

---

### Task 6: JS applyFocusFilter 扩展

**Files:**
- Modify: `docs/fp-ui/00-layout-prototype.html:3303-3355`

**现状问题：** 当前 `applyFocusFilter` 只过滤 `.fp-card`（看板）、`.fp-list-row`（列表）、`.fp-plan-task`（规划），不过滤 `.fp-week-task`（周视图）和 `.fp-day-task`（日视图）。当用户在 fp-week 显示时切换回"本月"scope，fp-week 隐藏但其内部任务不被过滤。

**目标：** 统一过滤所有 5 种标记类的元素。

- [ ] **Step 1: 在 applyFocusFilter 函数中添加 fp-week-task 和 fp-day-task 过滤**

在 `.fp-plan-task` 过滤块之后，新增：

```javascript
document.querySelectorAll('.fp-week-task').forEach(function(el) {
  if (filter === 'all') { el.style.display = ''; return; }
  if (filter === 'month') { el.style.display = monthSet.includes(el.dataset.fpSchedule) ? '' : 'none'; return; }
  if (filter === 'week') { el.style.display = weekSet.includes(el.dataset.fpSchedule) ? '' : 'none'; return; }
  if (filter === 'today') { el.style.display = el.dataset.fpSchedule === 'today' ? '' : 'none'; return; }
  el.style.display = '';
});
document.querySelectorAll('.fp-day-task').forEach(function(el) {
  if (filter === 'all') { el.style.display = ''; return; }
  if (filter === 'month') { el.style.display = monthSet.includes(el.dataset.fpSchedule) ? '' : 'none'; return; }
  if (filter === 'week') { el.style.display = weekSet.includes(el.dataset.fpSchedule) ? '' : 'none'; return; }
  if (filter === 'today') { el.style.display = el.dataset.fpSchedule === 'today' ? '' : 'none'; return; }
  el.style.display = '';
});
```

- [ ] **Step 2: 更新规划标题联动逻辑**

当前只处理 `all` 和 `month` 两种情况。补齐 `week` 和 `today`：

```javascript
var titleEl = document.getElementById('fpYearTitle');
if (titleEl) {
  if (filter === 'all') {
    titleEl.innerHTML = '📋 全局规划 · 月视图 <span style="font-size:10px;font-weight:400;color:var(--dim);font-family:var(--mono);">12 项</span>';
  } else if (filter === 'month') {
    var monthCount = 0;
    document.querySelectorAll('#fp-year .fp-plan-task').forEach(function(el) { if (monthSet.includes(el.dataset.fpSchedule)) monthCount++; });
    monthCount = Math.round(monthCount / 2);
    titleEl.innerHTML = '📆 本月计划 · 月视图 <span style="font-size:10px;font-weight:400;color:var(--dim);font-family:var(--mono);">' + monthCount + ' 项</span>';
  }
}
```

注意：`week` 和 `today` scope 会切换到 fp-week/fp-day 子视图，fp-year 不可见，所以不需要更新 fpYearTitle。保持现有逻辑即可。

- [ ] **Step 3: Commit**

```bash
git add docs/fp-ui/00-layout-prototype.html
git commit -m "fix(fp-ui): Focus 过滤逻辑扩展到周视图和日视图"
```

---

### Task 7: 03-focus.md 规格同步

**Files:**
- Modify: `docs/fp-ui/03-focus.md:506-560`

**现状问题：** ASCII 布局侧边栏计数仍为旧值（本月9/本周7/今日4），规格文档与原型不一致。

- [ ] **Step 1: 更新 ASCII 布局侧边栏计数**

```
全局规划  (12)     — 保持
本月计划  (10)     — 从 (9) 更新
本周计划  (8)      — 从 (7) 更新
今日聚焦  (2)      — 从 (4) 更新
Agent 执行中 (2)   — 保持
等我决策    (1)    — 保持
```

- [ ] **Step 2: 验证过滤表一致性**

确认过滤表中各 scope 的筛选条件与实际 JS 逻辑匹配。当前已正确，无需改动。

- [ ] **Step 3: Commit**

```bash
git add docs/fp-ui/03-focus.md
git commit -m "docs(fp-ui): Focus 规格侧边栏计数与原型同步"
```

---

### Task 8: 浏览器验收

**Files:** 无代码变更

- [ ] **Step 1: 打开浏览器验证**

用浏览器打开 `docs/fp-ui/00-layout-prototype.html`，切换到 Focus 页面。

- [ ] **Step 2: 全局规划 scope 验证**

点击侧边栏"全局规划"：
- 看板显示 6 列共 11 张卡片 + 1 blocked = 12
- 列表显示 3 组共 12 行（含 1 行 blocked 半透明）
- 规划视图显示完整目标树 + 甘特

- [ ] **Step 3: 本月计划 scope 验证**

点击侧边栏"本月计划"：
- 看板过滤后剩 10 张卡片（FP-008 hidden）
- 列表过滤后剩 10 行
- 规划视图目标树过滤后 FP-008 消失，其余任务可见

- [ ] **Step 4: 本周计划 scope 验证**

点击侧边栏"本周计划"：
- 视图切换到 fp-week
- 左侧显示 8 个任务
- 右侧甘特有 8 个条
- 看板过滤后剩 8 张卡片
- 列表过滤后剩 8 行

- [ ] **Step 5: 今日聚焦 scope 验证**

点击侧边栏"今日聚焦"：
- 视图切换到 fp-day
- 左侧显示 2 个任务（FP-010, FP-011）
- 右侧甘特有 1 个条（FP-011）
- 看板过滤后剩 2 张卡片
- 列表过滤后剩 2 行

- [ ] **Step 6: 三视图一致性交叉验证**

对每个 scope，在三个 Tab（规划/看板/列表）间来回切换，确认任务集合完全一致。

---

## 自审清单

### 规格覆盖

- [x] 用户核心需求：三视图展示内容一致 → Task 1-5 全覆盖
- [x] 包含层级过滤：全局⊃本月⊃本周⊃今日 → Task 6 JS 扩展
- [x] 03-focus.md 同步 → Task 7
- [x] 浏览器验收 → Task 8

### 占位符扫描

- [x] 无 TBD/TODO
- [x] 所有 HTML 代码块完整
- [x] 所有 commit 消息具体

### 类型一致性

- [x] CSS 类名一致：fp-plan-task, fp-week-task, fp-day-task, fp-card, fp-list-row
- [x] data 属性一致：data-fp-schedule, data-fp-mode, data-fp-agent, data-fp-decision
- [x] JS 函数名一致：applyFocusFilter, openTaskDetail
