# Focus 甘特下钻 + 评估验收交互 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Focus 原型补齐甘特下钻导航和评估/验收可交互流程，达到 5/5 可开发标准

**Architecture:** 纯 JS 交互补齐，复用现有 `applyFocusFilter()` 实现下钻跳转。用 `data-drill-scope` + `data-drill-event` 属性标记可下钻元素及其触发方式，DOMContentLoaded 统一绑定事件。评估/验收 Tab 按钮使用 inline onclick（函数定义在全局 script 作用域）+ 状态反馈 + 重置逻辑。仅当前月(5月)/当前周(W22)/当天可下钻，非当前时间段不可下钻。

**Tech Stack:** Vanilla JS, HTML prototype

---

### Task 1: 甘特下钻导航

**Files:**
- Modify: `docs/fp-ui/00-layout-prototype.html` — `<script>` 区域 + HTML data 属性

**约束：仅当前时间段可下钻**
- fp-year：仅 5月（当前月）的 Goal bar 和左侧月份头可下钻 → fp-month
- fp-month：仅 W22（当前周）的周分组头和右侧周标签可下钻 → fp-week
- fp-week：仅周三 05-27（当天）的天分组头可下钻 → fp-day
- 4月/6月、非当周、非当天不添加下钻，避免跳转到错误数据

- [ ] **Step 1: 给可下钻元素添加 data 属性**

fp-year 5月左侧月份头行（`data-fp-plan-month="5"` 容器内第一个 display:flex 子 div）添加 `data-drill-scope="month" data-drill-event="dblclick"`。

fp-year 5月右侧甘特 Goal bar（`data-fp-plan-month="5"` 容器内 `<!-- May Goal bar -->` 后的 height:34px div）添加 `data-drill-scope="month" data-drill-event="click"`。

fp-month W22 左侧周分组头（`data-fp-plan-week="22"` 容器内第一个 display:flex 子 div）添加 `data-drill-scope="week" data-drill-event="dblclick"`。

fp-month W22 右侧甘特标签行（`data-fp-plan-week="22"` 容器内 height:28px 的 div）添加 `data-drill-scope="week" data-drill-event="click"`。

fp-week 周三天分组头（`data-fp-week-day="3"` 容器内第一个 display:flex 子 div）添加 `data-drill-scope="today" data-drill-event="dblclick"`。

共 5 处 HTML 修改。每个元素显式标记触发方式，左侧分组头用 dblclick（避免与折叠单击冲突），右侧甘特行用 click。

- [ ] **Step 2: 在 `<script>` 中添加 drillDown 函数和统一绑定**

在已有的 `toggleGroup` / `syncGantt` 代码块之后、DOMContentLoaded 回调内，添加下钻绑定：

```javascript
function drillDown(scope) {
  var item = document.querySelector('[data-focus-filter="' + scope + '"]');
  if (item) applyFocusFilter(item);
}

document.querySelectorAll('[data-drill-scope]').forEach(function(el) {
  var scope = el.dataset.drillScope;
  var eventType = el.dataset.drillEvent || 'click';
  if (eventType === 'dblclick') {
    el.addEventListener('dblclick', function(e) { e.stopPropagation(); drillDown(scope); });
  } else {
    el.style.cursor = 'pointer';
    el.addEventListener('click', function() { drillDown(scope); });
  }
});
```

- [ ] **Step 3: 验证下钻**

浏览器打开原型：
1. 全局规划 → 双击左侧 "5月" 标题 → 切换到本月计划，侧边栏 active 变为"本月计划"
2. 全局规划 → 单击右侧 5月 Goal bar → 同上
3. 双击 4月/6月标题 → 不应有下钻反应（无 data-drill-scope）
4. 本月计划 → 双击 "W22" 标题 → 切换到本周计划
5. 本周计划 → 双击 "周三 · 05-27" → 切换到今日聚焦
6. 双击周一/周二/周五 → 不应有下钻反应

- [ ] **Step 4: 提交**

```bash
git add docs/fp-ui/00-layout-prototype.html
git commit -m "feat(fp-ui): Focus 甘特下钻导航——当前月/周/天可双击跳转下级视图"
```

---

### Task 2: 评估/验收流程交互

**Files:**
- Modify: `docs/fp-ui/00-layout-prototype.html` — 评估 Tab(`fp-t-eval`) + 验收 Tab(`fp-t-accept`) + `<script>`

- [ ] **Step 1: 添加评估/验收操作 JS 函数 + 重置函数**

在 `<script>` 中 `closeNewTaskModal` 之前添加。注意：这些函数必须定义在全局 script 作用域（不在 DOMContentLoaded 回调内），因为 Step 3/4 的 HTML inline onclick 需要全局访问：

```javascript
function handleEvalAction(action) {
  var evalDiv = document.getElementById('fp-t-eval');
  evalDiv.querySelectorAll('.btn').forEach(function(b) { b.style.opacity = '0.4'; b.style.pointerEvents = 'none'; });
  var feedback = document.createElement('div');
  feedback.style.cssText = 'margin-top:14px;padding:10px 12px;border-radius:var(--radius);font-size:12px;font-weight:500;';
  if (action === 'apply') {
    feedback.style.background = 'rgba(74,222,128,0.1)'; feedback.style.color = 'var(--green)';
    feedback.textContent = '✓ 已按建议处理，Agent 正在修复中...';
  } else if (action === 'ignore') {
    feedback.style.background = 'rgba(251,191,36,0.1)'; feedback.style.color = 'var(--amber)';
    feedback.textContent = '⚠ 已忽略评估建议，任务标记为待验收';
  } else {
    feedback.style.background = 'rgba(82,156,202,0.1)'; feedback.style.color = 'var(--accent)';
    feedback.textContent = '🖐 已切换为手动接管模式';
  }
  feedback.className = 'eval-feedback';
  var old = evalDiv.querySelector('.eval-feedback'); if (old) old.remove();
  evalDiv.appendChild(feedback);
}

function handleAcceptAction(action) {
  var div = document.getElementById('fp-t-accept');
  div.querySelectorAll('.btn').forEach(function(b) { b.style.opacity = '0.4'; b.style.pointerEvents = 'none'; });
  var feedback = document.createElement('div');
  feedback.style.cssText = 'margin-top:14px;padding:10px 12px;border-radius:var(--radius);font-size:12px;font-weight:500;';
  if (action === 'pass') {
    feedback.style.background = 'rgba(74,222,128,0.1)'; feedback.style.color = 'var(--green)';
    feedback.textContent = '✓ 验收通过！任务已标记为 Done';
  } else {
    feedback.style.background = 'rgba(248,113,113,0.1)'; feedback.style.color = 'var(--red)';
    feedback.textContent = '↩ 已退回修改，Agent 将重新执行';
  }
  feedback.className = 'accept-feedback';
  var old = div.querySelector('.accept-feedback'); if (old) old.remove();
  div.appendChild(feedback);
}

function resetTaskDetailActions() {
  document.querySelectorAll('#fp-t-eval .btn, #fp-t-accept .btn').forEach(function(b) {
    b.style.opacity = ''; b.style.pointerEvents = '';
  });
  var ef = document.querySelector('.eval-feedback'); if (ef) ef.remove();
  var af = document.querySelector('.accept-feedback'); if (af) af.remove();
}

function openTaskDetailTab(tabId) {
  openTaskDetail();
  var tab = document.querySelector('.fp-dtab[data-t="' + tabId + '"]');
  if (tab) tab.click();
}
```

- [ ] **Step 2: 修改 openTaskDetail 调用 resetTaskDetailActions**

将现有 `openTaskDetail` 函数改为：

```javascript
function openTaskDetail() {
  resetTaskDetailActions();
  document.getElementById('fpDetailOverlay').style.opacity = '1';
  document.getElementById('fpDetailOverlay').style.pointerEvents = 'all';
  document.getElementById('fpDetailPanel').style.transform = 'translateX(0)';
}
```

- [ ] **Step 3: 给评估 Tab 按钮添加 onclick**

找到 `fp-t-eval` 内 `<div style="display:flex;gap:8px;margin-top:14px">` 的三个按钮，替换为：

```html
<button class="btn primary" style="font-size:11px;min-height:28px" onclick="handleEvalAction('apply')">按建议处理</button>
<button class="btn" style="font-size:11px;min-height:28px" onclick="handleEvalAction('ignore')">忽略并完成</button>
<button class="btn" style="font-size:11px;min-height:28px" onclick="handleEvalAction('manual')">手动接管</button>
```

- [ ] **Step 4: 给验收 Tab 按钮添加 onclick**

找到 `fp-t-accept` 内 `<div style="display:flex;gap:8px">` 的两个按钮，替换为：

```html
<button class="btn" style="font-size:11px;min-height:28px;background:rgba(46,204,113,.15);color:var(--green);border-color:rgba(46,204,113,.3)" onclick="handleAcceptAction('pass')">验收通过 → Done</button>
<button class="btn" style="font-size:11px;min-height:28px" onclick="handleAcceptAction('reject')">退回修改</button>
```

- [ ] **Step 5: "等我决策"卡片/列表行直达评估 Tab**

看板 FP-005 卡片（`data-fp-decision="yes"` 的 `fp-card`）：`onclick="openTaskDetail()"` → `onclick="openTaskDetailTab('fp-t-eval')"`。

列表 FP-005 行（`data-fp-decision="yes"` 的 `fp-list-row`）：同上修改 onclick。

共 2 处。

- [ ] **Step 6: 验证评估/验收流程**

1. 看板点击"等我决策"卡片 → 详情面板打开且自动切到评估 Tab
2. 点击"按建议处理" → 按钮变灰，绿色反馈
3. 关闭详情面板 → 重新打开 → 按钮恢复正常，feedback 已清除
4. 切到验收 Tab → "验收通过" → 按钮变灰，绿色反馈
5. 关闭重开 → 状态恢复

- [ ] **Step 7: 提交**

```bash
git add docs/fp-ui/00-layout-prototype.html
git commit -m "feat(fp-ui): Focus 评估/验收 Tab 可交互——状态反馈 + 重置 + 等我决策直达"
```

---

### Task 3: 状态更新 + 文档联动检查

**Files:**
- Modify: `CLAUDE.md` — UI 设计进度表 Focus 行
- Modify: `docs/FP-UI.md` — 确认 Focus 行规格状态
- Modify: `docs/fp-ui/03-focus.md` — 顶部状态行
- Check: `docs/PRD.md` — Focus 三视图是否需补"下钻交互"
- Check: `docs/DesignGuide.md` — 是否需新增视觉规范

- [ ] **Step 1: 更新 CLAUDE.md 进度表**

找到 `| 03-focus |` 行，改为：
```
| 03-focus | 5/5 | 可开发 | — |
```

- [ ] **Step 2: 确认 FP-UI.md Focus 状态**

检查 `docs/FP-UI.md` 页面清单中 Focus 行的"规格状态"列。确认为 `可开发`；如果已经是，则无需修改，也不 git add。FP-UI.md 无完整度列，以 CLAUDE.md 进度表为准。

- [ ] **Step 3: 更新 03-focus.md 顶部状态 + 补充下钻交互契约**

将第 3 行：
```
> **状态**：设计中（规格可开发，母版待补齐验收/评估流程）
```
改为：
```
> **状态**：可开发
```

将第 4 行 `> **更新**：2026-05-25` 改为 `> **更新**：2026-05-28`。

在 03-focus.md 中找到 Mode A（全局规划）相关章节，添加下钻交互契约：

```markdown
### 甘特下钻导航

| 视图 | 可下钻元素 | 触发方式 | 目标视图 | 约束 |
|------|-----------|---------|---------|------|
| fp-year | 当前月左侧月份头 | 双击 | fp-month | 仅当前月（DEMO_TODAY 所在月） |
| fp-year | 当前月右侧 Goal bar | 单击 | fp-month | 同上 |
| fp-month | 当前周左侧周分组头 | 双击 | fp-week | 仅当前周（DEMO_TODAY 所在周） |
| fp-month | 当前周右侧周标签行 | 单击 | fp-week | 同上 |
| fp-week | 当天左侧天分组头 | 双击 | fp-day | 仅当天（DEMO_TODAY） |

非当前时间段不添加下钻属性，避免跳转到无对应数据的视图。

实现方式：`data-drill-scope` 标记目标 scope，`data-drill-event` 标记触发事件类型（click/dblclick），DOMContentLoaded 统一绑定。
```

- [ ] **Step 4: 检查 PRD.md Focus 章节**

读取 `docs/PRD.md` 中 Focus 三视图相关章节。下钻行为是 UI 交互细节，已在 03-focus.md 规格中覆盖。如果 PRD 未提及下钻，不需要新增——PRD 定义功能边界，不定义交互细节。在提交消息中注明"PRD 无需变更：下钻为 UI 交互细节，已在 03-focus.md 覆盖"。

- [ ] **Step 5: 检查 DesignGuide.md**

读取 `docs/DesignGuide.md`。本次无新增视觉规范（无新色值、无新动画参数），仅复用已有交互模式。在提交消息中注明"DesignGuide 无需变更：无新增视觉规范"。

- [ ] **Step 6: 提交**

```bash
git add CLAUDE.md docs/fp-ui/03-focus.md
# 仅当 FP-UI.md 有实际修改时才 git add docs/FP-UI.md
git commit -m "docs(fp-ui): Focus 状态更新为 5/5 可开发

- CLAUDE.md 进度表 03-focus 更新为 5/5 可开发
- 03-focus.md 顶部状态从'设计中'改为'可开发'，更新日期，补充下钻交互契约
- FP-UI.md 已检查，无需修改（已为可开发）
- PRD 无需变更：下钻为 UI 交互细节，已在 03-focus.md 覆盖
- DesignGuide 无需变更：无新增视觉规范"
```

---

### Task 4: 最终串联验收

- [ ] **Step 1: 全流程串联测试**

浏览器打开原型，按以下路径完整走一遍：

1. **下钻链路**：侧边栏"全局规划" → 双击 5月标题 → 本月计划 → 双击 W22 → 本周计划 → 双击"周三 05-27" → 今日聚焦
2. **非当前时间段不可下钻**：返回全局规划 → 双击 4月/6月 → 无反应 ✓
3. **评估流程**：看板视图 → 点击"等我决策"卡片 → 自动进入评估 Tab → 点击"按建议处理" → 绿色反馈 → 关闭面板 → 重新打开 → 按钮已恢复
4. **验收流程**：切到验收 Tab → 点击"验收通过" → 绿色反馈 → 关闭重开 → 状态恢复
5. **折叠展开**：各视图时间分组仍可折叠/展开，左右同步
6. **侧边栏切换**：各 scope 切换正常，顶部 filter 按钮文案同步

全部通过后，Focus 页面达到 5/5 可开发标准。

- [ ] **Step 2: 确认工作区干净并推送**

```bash
git status --short
git push
```

确认无未提交文件，推送所有 commit 到远程仓库。

---

## Self-Review

1. **Spec coverage**: 甘特下钻（仅当前月/周/天）✓；评估三选一 ✓；验收通过/退回 ✓；等我决策直达 ✓；状态重置 ✓；状态更新 ✓；03-focus.md 下钻交互契约 ✓；PRD/DesignGuide 联动检查 ✓；最终串联验收 ✓；git push ✓
2. **Placeholder scan**: 无 TBD/TODO，所有步骤含完整代码或明确操作
3. **Type consistency**: `drillDown` / `handleEvalAction` / `handleAcceptAction` / `resetTaskDetailActions` / `openTaskDetailTab` 命名一致；`data-drill-scope` + `data-drill-event` 属性名在 HTML 和 JS 绑定中一致；评估/验收函数在全局作用域，下钻绑定在 DOMContentLoaded 内
