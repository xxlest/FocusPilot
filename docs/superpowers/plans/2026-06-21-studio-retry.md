# Studio 执行失败/超时一键重试 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 V1 Studio 的 `run_state=failed/timeout` 任务补上「↻ 重试」动作（状态转换 + 各视图入口），在 4 个权威文档 + 原型里落地。

**Architecture:** 纯文档/原型改动。重试 = `run_state: failed/timeout → queued`，`status` 不变，worktree/session resume 起新 Run（对齐 04-studio §3.3，非走 blocked）。原型靠统一函数 `buildTaskCardHtml` 一处改、多视图覆盖。

**Tech Stack:** Markdown 文档 + 原型 HTML/JS（无构建、无测试框架）。**验证方式 = grep/读确认 + 原型在浏览器渲染验证**，无单元测试。

**依据 spec:** [docs/superpowers/specs/2026-06-21-studio-retry-design.md](../specs/2026-06-21-studio-retry-design.md)（§6 同步清单为本计划的来源）。

**全程约束:** 改 `run_state` 任一语义/颜色/转换须同步 04-studio §2.4/§3.2 + PRD + DesignGuide §4.8（CLAUDE.md 权威源规则）；提交不加 `Co-Authored-By`；在 `feat/studio-retry-design` 分支上做。

---

## Task 1: 04-studio.md — 状态语义（§2.4 表 + §3.2 新增转换）

**Files:**
- Modify: `docs/fp-ui/04-studio.md:161-169`（§2.4 run_state 表）
- Modify: `docs/fp-ui/04-studio.md:283`（§3.2 blocked 条后新增）

- [ ] **Step 1: §2.4 表 — failed/timeout 含义列补重试出口**

Edit old（[161-169](../../fp-ui/04-studio.md:161) 中两行）：
```
| 执行超时 | `timeout` | `#EF4444` 红 | ⏱ | Run 运行时长超过上限（Settings 可配）→ 中止，等人工重试/干预 |
| 执行失败 | `failed` | `#DC2626` 深红 | ✕ | Run 报错/崩溃中止，等人工处理 |
```
new：
```
| 执行超时 | `timeout` | `#EF4444` 红 | ⏱ | Run 运行时长超过上限（Settings 可配）→ 中止，等人工重试/干预；可经人工「重试」回 `queued`（§3.2） |
| 执行失败 | `failed` | `#DC2626` 深红 | ✕ | Run 报错/崩溃中止，等人工处理；可经人工「重试」回 `queued`（§3.2） |
```

- [ ] **Step 2: §3.2 — 在 blocked 条之后新增「重试触发与恢复」**

定位 [04-studio.md:283](../../fp-ui/04-studio.md:283) 行末（以 `…回 todo 则重新入调度、不自动续跑旧 Run。` 结尾），在其后新增一整条 bullet：
```
- **重试触发与恢复**：`run_state ∈ {failed, timeout}` 的任务在卡片/详情提供「↻ 重试」。触发后清当前（已 aborted）Run 标记、`run_state → queued`、`status` **不变**（仍 in_progress），下轮扫描器在**保留的 worktree / 路径锁 + 同一 session** 上 resume 上下文、起一个**新 executor Run**（对齐 §3.3 派发范式，**非走 blocked**）。失败/超时**不释放** worktree / 路径锁（任务未离开执行流）。与 blocked 区分：blocked = 外部依赖（人工标/解除），failed/timeout = 引擎内失败（一键重试）。
```

- [ ] **Step 3: 验证**

Run: `grep -n "重试触发与恢复\|可经人工「重试」回" docs/fp-ui/04-studio.md`
Expected: 命中 3 处（§2.4 两行 + §3.2 一条）。

- [ ] **Step 4: Commit**

```bash
git add docs/fp-ui/04-studio.md
git commit -m "docs(studio): §2.4/§3.2 补 run_state 失败/超时的重试转换"
```

---

## Task 2: 04-studio.md — 视图入口（§7.1 各视图 + §7.4 详情）

**Files:**
- Modify: `docs/fp-ui/04-studio.md`（§7.1 看板条目 ~568；§7.4 详情 ~684）

- [ ] **Step 1: §7.1 看板条目补重试入口说明**

定位 [04-studio.md:568](../../fp-ui/04-studio.md:568)（`- **看板**：…` 那条）末尾，追加一句：
```
；`run_state=failed/timeout` 的卡片底部常驻「↻ 重试」按钮（中性色，详见 §7.4 与 DesignGuide §5.10），列表/泳道卡片同款
```

- [ ] **Step 2: §7.4 详情面板补重试 + 日志说明**

定位 [04-studio.md:684](../../fp-ui/04-studio.md:684)（属性内联编辑那段，含「🗑 删除」按钮描述）末尾，追加：
```
 当 `run_state=failed/timeout` 时，详情头部在「🗑 删除」旁显示「↻ 重试」（语义同 §3.2，中性色）；查看失败原因**复用对话视图**——失败 executor Run 行已带 `[日志]`，点击滚到该 Run 最后输出，不新造组件。
```

- [ ] **Step 3: 验证**

Run: `grep -n "↻ 重试\|常驻「↻ 重试」" docs/fp-ui/04-studio.md`
Expected: §7.1、§7.4 各命中。

- [ ] **Step 4: Commit**

```bash
git add docs/fp-ui/04-studio.md
git commit -m "docs(studio): §7.1/§7.4 各视图与详情加重试入口"
```

---

## Task 3: PRD.md — run_state 转换表补重试来源

**Files:**
- Modify: `docs/PRD.md:168`

- [ ] **Step 1: → queued 行补重试来源**

Edit old（[PRD.md:168](../../PRD.md:168)）：
```
| → `queued` | 配了执行 Agent 且 `status ∈ {todo, in_progress, in_review, done}`，被扫描到但并发槽满 / 路径锁被占 / 未到开始时间 |
```
new：
```
| → `queued` | 配了执行 Agent 且 `status ∈ {todo, in_progress, in_review, done}`，被扫描到但并发槽满 / 路径锁被占 / 未到开始时间；**或 `failed`/`timeout` 任务经人工「重试」**（`status` 不变、worktree resume 起新 Run） |
```

- [ ] **Step 2: 验证**

Run: `grep -n "经人工「重试」" docs/PRD.md`
Expected: 命中 168 行。

- [ ] **Step 3: Commit**

```bash
git add docs/PRD.md
git commit -m "docs(prd): run_state 转换表补 failed/timeout 经重试回 queued"
```

---

## Task 4: DesignGuide.md — 新增 §5.10 重试按钮控件规格

**Files:**
- Modify: `docs/DesignGuide.md`（§5.9 之后、§6 之前，约 344 行处）

- [ ] **Step 1: 在 §5.9 末尾后插入 §5.10**

定位 §5.9（可编辑 chip）结束、`## 6. 动画规范`（[DesignGuide.md:345](../../DesignGuide.md:345)）之前，插入：
```

### 5.10 执行失败/超时重试控件

`run_state = failed/timeout` 的任务卡片底部常驻「↻ 重试」按钮，详情面板头部（🗑 删除 旁）提供同款。

- **配色（强约束）**：**中性描边**——边框取 `separator` 槽、文字取 `textSecondary` 槽（主题相关、随主题刷新）。`↻` 图标本身已表达"重跑"。
- **禁止用色**：不得用任何 run_state 状态色（`#14B8A6` running / `#E6A23C` queued / `#DC2626` failed / `#EF4444` timeout 等）；**也不得用 `accent`**（warmIvory `#D97706` / defaultWhite `#E53935` 等会与失败红撞）。守住"颜色=状态"不变量（见 §4.8）。
- **点击反馈**：点击后按钮转禁用态、文案「排队中…」；整卡 tint 由失败红切到排队琥珀（`run_state` 已 → `queued`）。
```

- [ ] **Step 2: 验证**

Run: `grep -n "5.10 执行失败/超时重试控件\|禁止用色" docs/DesignGuide.md`
Expected: 命中。并确认 `grep -n "^## 6" docs/DesignGuide.md` 仍在新小节之后。

- [ ] **Step 3: Commit**

```bash
git add docs/DesignGuide.md
git commit -m "docs(designguide): 新增 §5.10 重试按钮控件规格（中性色、禁用状态色）"
```

---

## Task 5: 原型 — 统一卡片函数加重试按钮 + retryTask()

**Files:**
- Modify: `docs/fp-ui/00-layout-prototype.html`（`buildTaskCardHtml` ~7489；新增 `retryTask` 函数）

- [ ] **Step 1: 定位视图刷新函数名（供 retryTask 调用）**

Run: `grep -nE "function renderKanban|function applyFocusFilter|function renderStudio|function renderAll" docs/fp-ui/00-layout-prototype.html`
记下统一刷新函数名（下一步用，记为 `<REFRESH>`，多为 `applyFocusFilter` 或 `renderKanban`）。

- [ ] **Step 2: buildTaskCardHtml 在 return 前插入重试按钮**

定位 [00-layout-prototype.html:7490](../../fp-ui/00-layout-prototype.html:7490)（`return html;`，在 `buildTaskCardHtml` 内），在其前插入：
```javascript
        if (ekey === 'failed' || ekey === 'timeout') {
          html += '<div style="margin-top:6px"><button class="btn fp-retry-btn" onclick="event.stopPropagation();retryTask(\'' + item.id + '\')" style="font-size:10px;padding:2px 10px;min-height:0;border-color:var(--line);color:var(--muted)">↻ 重试</button></div>';
        }
```
（`ekey` 已在 7467 由 `execStateOf(item)` 取得；按钮用 `var(--line)`/`var(--muted)` 中性色，不受 `compact` 限制，列表/泳道同样显示。）

- [ ] **Step 3: 新增 retryTask() 函数**

在 `buildTaskCardHtml` 函数之后（[7491](../../fp-ui/00-layout-prototype.html:7491) `}` 后）插入：
```javascript
      // 重试：failed/timeout → queued（status 不变；演示态直接重渲染）
      function retryTask(id) {
        var list = (typeof workItems !== 'undefined') ? workItems : [];
        var it = list.find(function (x) { return x.id === id; });
        if (!it) return;
        it.run_state = 'queued';
        if (typeof <REFRESH> === 'function') <REFRESH>();
      }
```
把 `<REFRESH>` 替换为 Step 1 查到的函数名。

- [ ] **Step 4: 验证（浏览器）**

确认存在 `run_state:'failed'` 或 `'timeout'` 的 demo 任务：
Run: `grep -nE "run_state:\s*'(failed|timeout)'" docs/fp-ui/00-layout-prototype.html`
若无，将某 demo 任务（如 in_progress 的 FP-xxx）加 `run_state:'failed'` 以便演示。
然后浏览器打开原型 Studio 看板 → 失败卡片底部出现「↻ 重试」(中性色) → 点击后整卡转琥珀(queued)、按钮消失。

- [ ] **Step 5: Commit**

```bash
git add docs/fp-ui/00-layout-prototype.html
git commit -m "docs(proto): 卡片统一函数加重试按钮 + retryTask（失败/超时→排队）"
```

---

## Task 6: 原型 — 详情面板重试按钮 + run_substate 保留 + 跨文档自检

**Files:**
- Modify: `docs/fp-ui/00-layout-prototype.html:4322`（详情删除按钮旁）

- [ ] **Step 1: 详情头部加重试按钮**

定位 [00-layout-prototype.html:4322](../../fp-ui/00-layout-prototype.html:4322)（`🗑 删除` 按钮），在该 `<button>` 之前插入：
```html
                            <button class="btn" title="重试任务（执行失败/超时）" onclick="retryTask('FP-002')" style="min-height:28px;padding:0 9px;border-color:var(--line);color:var(--muted)">↻ 重试</button>
```
（FP-002 为该静态详情的任务号；中性色与卡片一致。）

- [ ] **Step 2: 确认 run_substate 兼容映射未被动**

Run: `grep -n "run_substate" docs/fp-ui/00-layout-prototype.html`
Expected: 仍在 7193/7196/7197（execStateOf 内），**未删**（[§2.4:171](../../fp-ui/04-studio.md:171) 明文兼容）。

- [ ] **Step 3: 跨文档一致性自检**

Run:
```bash
grep -rn "14b8a6\|14B8A6" docs/fp-ui/00-layout-prototype.html docs/DesignGuide.md | grep -i retry   # 期望：空（重试按钮不含 running 青）
grep -n "fp-retry-btn\|↻ 重试" docs/fp-ui/00-layout-prototype.html                                   # 期望：卡片 + 详情各命中
```
确认：重试按钮无任何状态色/accent；术语「↻ 重试」「重试」在 4 文档一致；§8 spec 的"时间轴不加 / 批量 V2"未被误加。

- [ ] **Step 4: Commit**

```bash
git add docs/fp-ui/00-layout-prototype.html
git commit -m "docs(proto): 详情面板加重试按钮；保留 run_substate 兼容映射"
```

---

## Self-Review（计划对 spec 的覆盖核对）

- **spec §2 状态语义** → Task 1（§2.4 表 + §3.2 转换）✓
- **spec §3 交互形态（按钮中性色、详情日志复用）** → Task 4（DesignGuide 规格）+ Task 2（§7.4 日志复用）✓
- **spec §4 覆盖范围（看板/列表/泳道/详情/Inspector/Home）** → Task 5（统一函数覆盖前四 + Inspector/Home 投影同源）、Task 6（详情）✓；时间轴不加、批量 V2 → Task 6 Step 3 自检守住 ✓
- **spec §5 边界（手动卡片无重试、不改 status）** → Task 5 判断 `ekey==='failed'||'timeout'`（手动卡片 ekey=idle，天然不显示）✓
- **spec §6 同步清单 4 文档** → Task 1-6 全覆盖 ✓
- **占位扫描**：原型 `<REFRESH>` 在 Task 5 Step 1 明确为"grep 查实函数名"的执行动作，非设计占位 ✓
- **类型/命名一致**：`retryTask(id)`、`run_state`、`ekey`、`buildTaskCardHtml` 在 Task 5/6 一致 ✓
