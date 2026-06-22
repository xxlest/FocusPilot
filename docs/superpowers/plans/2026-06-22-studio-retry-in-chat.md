# Studio 对话消息级失败重试 Implementation Plan

> **⚠️ 已被取代（2026-06-22 后续迭代）**：本计划针对「失败条件重试 / `msg_state` / 气泡内嵌 ↻」设计；该设计已整体演进为 **「对话操作栏（复制·重新生成）」** 模型——每条 agent 回复带 **📋 复制**、最后一条带 **🔄 重新生成**（任务态 = `retryTask`，聊天态 = 重发上一轮），不再依赖失败条件、不再引入 `msg_state`。权威现状见 [DesignGuide §5.10](../../DesignGuide.md)、[04-studio.md](../../fp-ui/04-studio.md) 与原型 commit `a9abb44`。下文保留为实现过程快照。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development 或 superpowers:executing-plans 逐 task 实现。步骤用 `- [ ]` 跟踪。

**Goal:** 把失败/超时重试从"卡片/详情头部按钮"改为**对话流消息气泡内嵌**(详情对话 + chatWindow),并修好 `retryTask` 刷新口径。

**Architecture:** 一个统一片段函数 `retryBubbleHtml()` 生成「⚠报错+↻重试」气泡;详情对话流(`convHtml`/`renderRunDetail`)与聊天(`renderMessageBubbles`,Home+快捷共用)各调它;`retryTask` 改为"置 queued + 刷详情 + `refreshStudioTaskViews()`";移除上一轮卡片/头部按钮。

**Tech Stack:** 原型 HTML/JS(无构建/无测试框架) + Markdown 文档。**验证 = node headless 提取函数跑断言 + grep 自检**(浏览器自动化在本环境不可用,见 spec)。

**依据 spec:** [docs/superpowers/specs/2026-06-22-studio-retry-in-chat-design.md](../specs/2026-06-22-studio-retry-in-chat-design.md)(权威)。

**约束:** 在 `feat/studio-retry-in-chat` 分支;commit 用纯 git 单独 Bash(避免 grep 大输出吞 commit);**不动** main、`docs/index.md`、`.claude/`、`.codex/`。

---

## File Structure
- `docs/fp-ui/00-layout-prototype.html` — 原型:新增 `retryBubbleHtml`/`retryChatMessage`、改 `retryTask`/`renderMessageBubbles`/`buildTaskCardHtml`/`convHtml`(×2)/`renderRunDetail`、移除头部按钮、demo 数据。
- `docs/fp-ui/04-studio.md` — §7.1 删卡片按钮句、§7.4 改详情重试描述。
- `docs/fp-ui/00-layout.md` — §全局快捷对话助手补失败呈现。
- `docs/DesignGuide.md` — §5.10 改写为消息内嵌形态。
- `docs/PRD.md` — StudioSession message 加 `msg_state`。
- `docs/fp-ui/09-focusbar.md` — 一句指向 chatWindow 失败呈现。

---

## Task 0: 地基修复(移除按钮 + retryTask 刷新)— 前置必做

**Files:** Modify `docs/fp-ui/00-layout-prototype.html`

- [ ] **Step 1: 移除 buildTaskCardHtml 里的卡片重试按钮**

定位 `buildTaskCardHtml` 内 `return html;` 前(上一轮加的,约 7490 区)。Edit old:
```javascript
        if (ekey === 'failed' || ekey === 'timeout') {
          html += '<div style="margin-top:6px"><button class="btn fp-retry-btn" onclick="event.stopPropagation();retryTask(\'' + item.id + '\')" style="font-size:10px;padding:2px 10px;min-height:0;border-color:var(--line);color:var(--muted)">↻ 重试</button></div>';
        }
        return html;
```
new(删除按钮块,卡片不放按钮):
```javascript
        return html;
```

- [ ] **Step 2: 失败/超时卡片加 cursor/title 提示(nit)**

定位 `buildTaskCardHtml` 内 exec-badge 渲染处(`ekey !== 'idle'` 那段,约 7468)。在 `var em = EXEC_STATE_MODEL[ekey];` 后补一句把提示写进角标 title(失败/超时时):
```javascript
          var em = EXEC_STATE_MODEL[ekey];
          var hint = (ekey === 'failed' || ekey === 'timeout') ? ' title="点开详情可重试"' : '';
          html += '<span class="pill exec-badge"' + hint + ' style="font-size:9px;padding:1px 6px;font-weight:700;border:none;background:' + em.color + '22;color:' + em.color + '">' + em.icon + ' ' + em.label + '</span>';
```
(替换原无 title 的那行 exec-badge 拼接。)

- [ ] **Step 3: 移除详情头部右上角重试按钮**

Edit old(4323 区,上一轮 Task 6 加的):
```html
              <!-- ↻ 重试：仅 run_state=failed/timeout 时显示；此处演示态常驻 -->
              <button class="btn" title="重试任务（执行失败/超时）" onclick="retryTask('FP-002')" style="min-height:28px;padding:0 9px;border-color:var(--line);color:var(--muted)">↻ 重试</button>
              <button class="btn" title="删除任务" onclick="deleteCurrentTask()"
```
new(只留删除按钮):
```html
              <button class="btn" title="删除任务" onclick="deleteCurrentTask()"
```

- [ ] **Step 4: 改写 retryTask(置 queued + 刷详情 + 全视图 tint)**

Edit old(现版):
```javascript
      function retryTask(id) {
        var it = (typeof workItems !== 'undefined' ? workItems : []).find(function (x) { return x.id === id; });
        if (!it) return;
        it.run_state = 'queued';
        if (typeof renderKanbanFromItems === 'function') {
          renderKanbanFromItems(typeof currentFocusFilter !== 'undefined' ? currentFocusFilter : 'all');
        }
      }
```
new:
```javascript
      function retryTask(id) {
        var it = (typeof workItems !== 'undefined' ? workItems : []).find(function (x) { return x.id === id; });
        if (!it) return;
        it.run_state = 'queued';
        // 全视图卡片整卡 tint 同步(看板/列表/泳道/时间轴)——背景卡片不再停留在失败红
        if (typeof refreshStudioTaskViews === 'function') refreshStudioTaskViews();
        // 刷新已打开的 FocusBar 详情对话流(失败气泡→排队)
        if (typeof currentDetailId !== 'undefined' && currentDetailId === id && typeof renderRunDetail === 'function') {
          renderRunDetail(id);
        }
        // 刷新已打开的主面板详情:若详情覆盖层可见且当前是该任务,重渲染
        var ov = document.getElementById('fpDetailOverlay');
        if (ov && ov.classList.contains('open') && typeof openTaskDetail === 'function' && window.__mainDetailId === id) {
          openTaskDetail(id);
        }
      }
```
> 执行确认:主面板详情的"当前打开 id"——读 `openTaskDetail`(9369)确认它是否已存全局 id;若用别的变量名/可见判断,按实际替换 `window.__mainDetailId` 与 `ov.classList.contains('open')`(锚点:`fpDetailOverlay` 4316)。FocusBar 详情用现成的 `currentDetailId`(15008)。

- [ ] **Step 5: headless 验证 Task 0**

写 `/tmp/v0.js`:提取 `buildTaskCardHtml`/`execStateOf`/`EXEC_STATE_MODEL`/`retryTask`,mock `getWorkspaceMeta`/`workspaceTypeInfo`/`taskChangesets`/`refreshStudioTaskViews`/`renderRunDetail`,断言:
```
node -e "..." # 1) buildTaskCardHtml(failed卡).includes('↻ 重试') === false（卡片无按钮）
            # 2) buildTaskCardHtml(failed卡).includes('点开详情可重试') === true（提示在）
            # 3) retryTask 源码 includes('refreshStudioTaskViews') === true
```
Expected: 三条全 true。

- [ ] **Step 6: Commit**
```bash
git add docs/fp-ui/00-layout-prototype.html
git commit -m "docs(proto): Task0 地基 — 移除卡片/头部重试按钮 + retryTask 刷详情与全视图tint"
```

---

## Task 1: 统一气泡函数 + 详情对话流失败重试

**Files:** Modify `docs/fp-ui/00-layout-prototype.html`

- [ ] **Step 1: 新增 retryBubbleHtml 统一片段函数**

在 `retryTask` 函数后插入:
```javascript
      // 失败/超时消息气泡内的「⚠报错 + ↻重试」统一片段(中性色按钮,DesignGuide §5.10)
      function retryBubbleHtml(reasonText, onclickExpr) {
        return '<div style="margin-top:8px;padding:8px 10px;background:rgba(220,38,38,.06);border:1px solid var(--line-soft);border-radius:6px">' +
          '<div style="font-size:11px;color:var(--red);margin-bottom:6px">⚠ ' + reasonText + '</div>' +
          '<button class="btn fp-retry-btn" onclick="' + onclickExpr + '" style="font-size:10px;padding:2px 10px;min-height:0;border-color:var(--line);color:var(--muted)">↻ 重试</button>' +
          '</div>';
      }
```

- [ ] **Step 2: 详情对话流 convHtml 失败分支(两处:8853 区、8904 区)**

两处 `convHtml` 的 `else if (task.exec) {` 块里,执行块拼好后,把末尾的 `[查看 Diff][日志]` 行替换为"失败则气泡、否则原按钮":
old(每处该块结尾):
```javascript
              '<div style="display:flex;gap:6px;margin-top:6px"><button class="btn" style="font-size:9px;min-height:22px;padding:0 8px">查看 Diff</button><button class="btn" style="font-size:9px;min-height:22px;padding:0 8px">日志</button></div></div></div>';
```
new:
```javascript
              ((task.exec.run_state === 'failed' || task.exec.run_state === 'timeout')
                ? retryBubbleHtml(task.exec.run_state === 'timeout' ? '执行超时 · Run 已中止' : '执行失败 · Run 报错中止', 'retryTask(\'' + task.id + '\')')
                : '<div style="display:flex;gap:6px;margin-top:6px"><button class="btn" style="font-size:9px;min-height:22px;padding:0 8px">查看 Diff</button><button class="btn" style="font-size:9px;min-height:22px;padding:0 8px">日志</button></div>') +
              '</div></div>';
```

- [ ] **Step 3: FocusBar 详情 renderRunDetail 的失败轮**

`renderRunDetail`(14985)渲染 `d.rounds` 的循环里,某轮 `round.run_state==='failed'||'timeout'` 时,在该轮输出后追加 `retryBubbleHtml(..., 'retryTask(\'' + d.id + '\')')`。
> 执行确认:读 `renderRunDetail` 的 rounds 渲染段(15010+),在单轮 HTML 拼装处按上式插入(失败轮追加气泡,正常轮不变)。

- [ ] **Step 4: demo 数据 — 给一个详情任务的 exec 标失败**

定位 `RUN_DETAILS` 或 `task.exec` 的 demo(grep `task.exec` / `RUN_DETAILS`),给 `PO-002`(已 timeout)的详情 exec 加 `run_state:'timeout'`,使详情对话流出现失败气泡。

- [ ] **Step 5: headless 验证 + Commit**

提取 `retryBubbleHtml`,断言 `retryBubbleHtml('执行超时','retryTask(\'x\')')` 含 `↻ 重试` 且不含状态色(`14b8a6/dc2626` 不在按钮 style)。
```bash
git add docs/fp-ui/00-layout-prototype.html
git commit -m "docs(proto): Task1 详情对话流失败 Run 气泡内嵌重试 + retryBubbleHtml"
```

---

## Task 2: chatWindow/聊天失败消息内嵌重试(renderMessageBubbles)

**Files:** Modify `docs/fp-ui/00-layout-prototype.html`

- [ ] **Step 1: renderMessageBubbles 改签名带 sid + agent 失败分支**

`renderMessageBubbles`(10879)签名 `(messages, compact)` 改为 `(messages, compact, sid)`;两处调用补 sid:
- [10962](../../fp-ui/00-layout-prototype.html:10962) `renderMessageBubbles(session.messages, false, sid)`
- [11075](../../fp-ui/00-layout-prototype.html:11075) `renderMessageBubbles(session.messages, true, sid)`

forEach 改带 index,agent 消息 body 拼好后插失败气泡。old:
```javascript
        messages.forEach(function(m) {
          if (m.role === 'user') {
```
new:
```javascript
        messages.forEach(function(m, idx) {
          if (m.role === 'user') {
```
agent 分支 `html += '<div class="message agent"...>' + body + '</div>';` 前插:
```javascript
          if (m.msg_state === 'failed' || m.msg_state === 'timeout') {
            body += retryBubbleHtml(m.error || (m.msg_state === 'timeout' ? '回复超时' : '未完成 · 请重试'), 'retryChatMessage(\'' + (sid || '') + '\',' + idx + ')');
          }
```

- [ ] **Step 2: 新增 retryChatMessage(重发上一轮)**

在 `renderMessageBubbles` 后插入:
```javascript
      // 聊天消息重试 = 清失败态 + 重发上一轮(演示:清 msg_state 后重渲染当前对话)
      function retryChatMessage(sid, idx) {
        var session = (typeof studioSessions !== 'undefined') ? studioSessions[sid] : null;
        if (!session || !session.messages || !session.messages[idx]) return;
        session.messages[idx].msg_state = 'ok';
        if (typeof homeActiveSessionId !== 'undefined' && homeActiveSessionId === sid && typeof renderHomeChatFromSession === 'function') renderHomeChatFromSession(sid);
        if (typeof renderQuickChatHistory === 'function') renderQuickChatHistory();
      }
```
> 实际产品语义是"重发上一轮 user prompt 触发新回复";原型演示用"清失败态+重渲染"表达可重试。

- [ ] **Step 3: demo 数据 — 一条 agent 消息标失败**

grep `studioSessions` 的 demo,给某 session 末尾 agent 消息加 `msg_state:'failed'` + `error:'未登录 · 请先 /login'`(呼应 Multica 截图)。

- [ ] **Step 4: headless 验证 + Commit**

提取 `renderMessageBubbles`+`retryBubbleHtml`,mock `escapeHtml`,断言:含 `msg_state:'failed'` 的 messages 渲染出 `↻ 重试` 与 `未登录`;正常消息不含。
```bash
git add docs/fp-ui/00-layout-prototype.html
git commit -m "docs(proto): Task2 chat 失败消息内嵌重试(renderMessageBubbles + retryChatMessage)"
```

---

## Task 3: 文档同步(spec §7)

**Files:** `04-studio.md` / `00-layout.md` / `DesignGuide.md` / `PRD.md` / `09-focusbar.md`

- [ ] **Step 1: 04-studio.md §7.1 删卡片按钮句**

删 [582](../../fp-ui/04-studio.md:582) 行尾上一轮加的"；`run_state=failed/timeout` 的卡片底部常驻「↻ 重试」按钮（中性色，详见 §7.4 与 DesignGuide §5.10），列表/泳道卡片同款"。

- [ ] **Step 2: 04-studio.md §7.4 改详情重试描述**

把上一轮加的"详情头部在「🗑 删除」旁显示「↻ 重试」"那句,改为:"`run_state=failed/timeout` 时,详情对话流里失败 Run 消息气泡内嵌「↻ 重试」;点击 → `run_state→queued`,刷新详情对话流与各视图卡片 tint(`refreshStudioTaskViews`)。卡片本身不放重试按钮,仅整卡变色 + `点开详情可重试` 提示。"

- [ ] **Step 3: 00-layout.md §全局快捷对话助手补失败呈现**

§全局快捷对话助手([91](../../fp-ui/00-layout.md:91))末尾加:"消息失败呈现:assistant 消息 `msg_state=failed/timeout` 时,气泡内显示 `⚠报错 + ↻重试`;点击 = 重发上一轮 user prompt。"

- [ ] **Step 4: DesignGuide.md §5.10 改写为消息内嵌**

§5.10 标题/正文从"卡片底部按钮"改为"对话消息内嵌重试":气泡内 `⚠报错 + ↻重试`,中性描边(`separator`)+ `textSecondary`,禁用状态色/accent(原因同前)。删除卡片底部按钮的描述。

- [ ] **Step 5: PRD.md StudioSession message 加 msg_state**

在 StudioSession message 相关处补 `msg_state: ok|failed|timeout`(自由聊天失败标记)。**不进 Architecture.md**。

- [ ] **Step 6: 09-focusbar.md 一句指向**

对话入口处补一句:"对话失败呈现见 [00-layout.md §全局快捷对话助手]。"

- [ ] **Step 7: Commit(纯 git)**
```bash
git add docs/fp-ui/04-studio.md docs/fp-ui/00-layout.md docs/DesignGuide.md docs/PRD.md docs/fp-ui/09-focusbar.md
git commit -m "docs: 同步对话消息级重试 — §7.1/§7.4/chatWindow/§5.10/msg_state/focusbar"
```

---

## Self-Review

- **spec 覆盖**:§2 模型→Task1/2(retryBubbleHtml 统一呈现、run_state/msg_state 两类承载);§5 retryTask 刷新→Task0 Step4;§6 移除/保留/提示→Task0 Step1-3;§7 同步→Task3;§8 验收→各 headless 断言 + 移除验证。✓
- **占位扫描**:两处"执行确认"(主详情刷新变量、renderRunDetail rounds 插入点)是带锚点(行号+函数名)的定位动作,非模糊占位;demo 数据步给了字段值。✓
- **命名一致**:`retryBubbleHtml(reasonText,onclickExpr)`、`retryTask(id)`、`retryChatMessage(sid,idx)`、`refreshStudioTaskViews()`、`msg_state` 跨 Task 一致。✓
- **DRY**:气泡用单一 `retryBubbleHtml`,详情/聊天/FocusBar 三处共用,不重复 HTML。✓
- **前置依赖**:Task 0 必须先做(retryTask 刷新是 Task1/2 内嵌按钮"点了有反应"的前提)。✓
