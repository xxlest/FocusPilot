# Focus Demo 数据一致性修复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 Focus 页面原型中"本月/本周/今日"scope 下三视图任务集不一致、日期冲突、数量标注错误的问题。

**Architecture:** 所有修改集中在 3 个文件：原型 HTML（demo 数据属性和硬编码日期）、03-focus.md（规格数量）、PRD.md（schedule 双轴描述矛盾）。每个 task 独立可验证。

**Tech Stack:** 静态 HTML + Markdown 文档

---

### Task 1: 修复看板 FP-001 从"本月"scope 排除

FP-001（数据模型设计，done 04-15）是历史完成项，不应出现在 5 月"本月计划"。当前 data-fp-month="5" 会被月过滤器放行。

**Files:**
- Modify: `docs/fp-ui/00-layout-prototype.html:2534`

- [ ] **Step 1: 移除 FP-001 看板卡片的 data-fp-month 属性**

将第 2534 行：
```html
<div class="task fp-card" style="opacity:.7" data-fp-schedule="" data-fp-month="5" data-fp-mode="auto">
```
改为：
```html
<div class="task fp-card" style="opacity:.7" data-fp-schedule="" data-fp-mode="auto">
```

- [ ] **Step 2: 验证**

在浏览器打开原型 → Focus → 点侧边栏"本月计划" → 看板应只有 FP-002/003/004/005/010/011 六项，无 FP-001。

- [ ] **Step 3: Commit**

```bash
git add docs/fp-ui/00-layout-prototype.html
git commit -m "fix(fp-ui): 移除 FP-001 看板 data-fp-month，排除历史 done 项出本月 scope"
```

---

### Task 2: 同步列表 FP-001 的 data-fp-schedule

看板 FP-001 已将 schedule 清空为 ""，但列表 FP-001 仍是 data-fp-schedule="week"，导致"本周"scope 下列表多出 FP-001 而看板不显示。

**Files:**
- Modify: `docs/fp-ui/00-layout-prototype.html:2591`

- [ ] **Step 1: 清空列表 FP-001 的 data-fp-schedule**

将第 2591 行：
```html
<tr class="fp-list-row" style="cursor:pointer" data-fp-schedule="week" data-fp-mode="auto">
```
改为：
```html
<tr class="fp-list-row" style="cursor:pointer" data-fp-schedule="" data-fp-mode="auto">
```

- [ ] **Step 2: 同步修改该行的"安排"列文本**

同一 tr 内（约第 2594 行），将：
```html
<td style="padding:8px 10px;font-size:12px;color:var(--dim)">本周</td>
```
改为：
```html
<td style="padding:8px 10px;font-size:12px;color:var(--dim)">—</td>
```

- [ ] **Step 3: 验证**

Focus → "本周计划" → 列表不应出现 FP-001（数据模型设计）。

- [ ] **Step 4: Commit**

```bash
git add docs/fp-ui/00-layout-prototype.html
git commit -m "fix(fp-ui): 列表 FP-001 schedule 同步清空，本周 scope 三视图一致"
```

---

### Task 3: 统一 FP-010/011 日期为 DEMO_TODAY (05-27)

DEMO_TODAY=2026-05-27，但 FP-010/011 在看板、fp-year、列表中的日期仍是 05-24，导致"今天"与任务日期冲突。

**Files:**
- Modify: `docs/fp-ui/00-layout-prototype.html` — 6 处 "05-24" 需改为 "05-27"

- [ ] **Step 1: 修改 fp-year 目标树中 FP-010/011 日期（第 1830、1843 行）**

将两处 `05-24` 改为 `05-27`。

- [ ] **Step 2: 修改看板 FP-010/011 日期（第 2480、2510 行）**

将两处 `05-24` 改为 `05-27`。

- [ ] **Step 3: 修改列表 FP-010/011 日期（第 2752、2762 行）**

将两处 `05-24` 改为 `05-27`。

- [ ] **Step 4: 验证**

Focus → "今日聚焦" → fp-day 中日期应与任务日期一致，无 05-24 出现。

- [ ] **Step 5: Commit**

```bash
git add docs/fp-ui/00-layout-prototype.html
git commit -m "fix(fp-ui): FP-010/011 日期统一为 DEMO_TODAY 05-27，消除今日与任务日期冲突"
```

---

### Task 4: 修正侧边栏和规格中的"本月"数量

侧边栏写 "(5)"，03-focus.md 也写 "(5)"，实际本月应为 6 项。

**Files:**
- Modify: `docs/fp-ui/00-layout-prototype.html:958`
- Modify: `docs/fp-ui/03-focus.md:511`

- [ ] **Step 1: 修改侧边栏计数**

第 958 行，将：
```html
<span>📆 本月计划</span><span class="count">5</span>
```
改为：
```html
<span>📆 本月计划</span><span class="count">6</span>
```

- [ ] **Step 2: 修改 03-focus.md 中的本月数量**

第 511 行，将 `本月计划  (5)` 改为 `本月计划  (6)`。

- [ ] **Step 3: Commit**

```bash
git add docs/fp-ui/00-layout-prototype.html docs/fp-ui/03-focus.md
git commit -m "fix(fp-ui): 侧边栏和规格中本月计划数量从 5 修正为 6"
```

---

### Task 5: 修正 PRD schedule 双轴描述矛盾

PRD 第 219 行写"frontmatter 通过 status + schedule 管理"，但 schedule 不是持久化字段。需改为 status + scheduled_date/due_date 双轴，schedule 明确为 UI 派生。

**Files:**
- Modify: `docs/PRD.md:219-224`

- [ ] **Step 1: 修改双轴描述**

将第 219~224 行：
```markdown
Task 的 frontmatter 通过 `status` + `schedule` 形成**双轴管理**：

- `status` 管**执行生命周期**：inbox → planning → ready → executing → done
- `schedule` 管**时间安排**：backlog → month → week → today

`schedule` 由 `scheduled_date` / `due_date` 相对当前日期自动派生（UI 派生字段，不持久化）。过滤关系：`全局规划 ⊃ 本月计划 ⊃ 本周计划 ⊃ 今日聚焦`。
```
改为：
```markdown
Task 的 frontmatter 通过 `status` + `scheduled_date` / `due_date` 形成**双轴管理**：

- `status` 管**执行生命周期**：inbox → planning → ready → executing → done
- `scheduled_date` / `due_date` 管**时间安排**：驱动任务在时间轴上的定位

`schedule`（today / week / month / backlog）是 UI 派生字段（不持久化），由 `scheduled_date` / `due_date` 相对当前日期自动计算。过滤关系：`全局规划 ⊃ 本月计划 ⊃ 本周计划 ⊃ 今日聚焦`。
```

- [ ] **Step 2: Commit**

```bash
git add docs/PRD.md
git commit -m "docs(PRD): 修正双轴描述为 status + scheduled_date，明确 schedule 为 UI 派生"
```

---

### Task 6: 最终验证

- [ ] **Step 1: 全 scope 验证**

浏览器打开原型，逐个点击侧边栏 scope，检查三视图任务集一致性：

| Scope | 预期任务集 |
|-------|-----------|
| 全局规划 | 全部 11 项 |
| 本月计划 | FP-002/003/004/005/010/011 = 6 项 |
| 本周计划 | FP-002/003/004/005/010/011 = 6 项 |
| 今日聚焦 | FP-010/011 = 2 项 |

- [ ] **Step 2: 日期一致性检查**

确认无 05-24 残留（`grep -c '05-24' docs/fp-ui/00-layout-prototype.html` 应为 0）。
确认无 04-xx 日期出现在本月/本周/今日视图任务中。
