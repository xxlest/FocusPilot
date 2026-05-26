# Focus 规划视图分级时间分组 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Focus 规划视图的时间分组粒度与筛选范围对齐——本月计划按周分组（新建 fp-month 子视图），本周计划按天/星期几分组（改造 fp-week 左侧）。

**Architecture:** 在 `docs/fp-ui/00-layout-prototype.html` 中新增 `#fp-month` 子视图 div（左侧按周分组树 + 右侧周列甘特），改造现有 `#fp-week` 左侧从扁平列表变为按星期几分组，最后更新 JS `modeMap` 和标题联动逻辑。所有变更都在同一个 HTML 文件中。

**Tech Stack:** HTML + CSS (inline) + vanilla JavaScript

---

## 文件结构

| 操作 | 文件 | 职责 |
|------|------|------|
| Modify | `docs/fp-ui/00-layout-prototype.html` | 新增 fp-month HTML、改造 fp-week 左侧、更新 JS |
| Modify | `docs/fp-ui/03-focus.md` | 同步规格描述（规划子视图说明） |

---

### Task 1: 新建 fp-month 子视图 HTML

**Files:**
- Modify: `docs/fp-ui/00-layout-prototype.html:1950` (在 `#fp-year` 的 `</div>` 之后、`#fp-week` 之前插入)

- [ ] **Step 1: 在 fp-year 和 fp-week 之间插入 fp-month div**

找到行 `<!-- 周规划 -->` （约第 1951 行），在它之前插入完整的 `#fp-month` 子视图。结构与 fp-year 完全对称（左侧树 + 右侧甘特的 grid 布局）。

在 `</div>` (fp-year 结束标签，约第 1950 行) 之后、`<!-- 周规划 -->` 之前，插入以下 HTML：

```html
            <!-- 月规划（按周分组） -->
            <div class="fp-sub" id="fp-month" style="display:none;grid-template-columns:380px 1fr;gap:0;border-radius:var(--radius);overflow:hidden;flex:1;">
              <!-- Left: Week-grouped Task Tree -->
              <div style="border-right:1px solid var(--line-soft);overflow-y:auto;padding:0;background:var(--surface);">
                <!-- Title -->
                <div id="fpMonthTitle" style="height:36px;display:flex;align-items:center;padding:0 12px;gap:6px;font-size:12px;font-weight:600;border-bottom:1px solid var(--line-soft);background:var(--surface);position:sticky;top:0;z-index:2;">
                  📆 本月计划 · 周视图
                  <span style="font-size:10px;font-weight:400;color:var(--dim);font-family:var(--mono);">5 项</span>
                </div>
                <div style="padding:16px;">
                  <!-- 目标: Q2 FocusPilot 0.0.1 -->
                  <div style="margin-bottom:2px;">
                    <div style="display:flex;align-items:center;gap:6px;padding:6px 8px;border-radius:var(--radius);cursor:pointer;font-size:13px;font-weight:500;">
                      <span style="font-size:10px;color:var(--dim);width:14px;text-align:center;transform:rotate(90deg);flex-shrink:0;">▶</span>
                      <span style="font-size:12px;flex-shrink:0;">📌</span>
                      <span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">Q2 — FocusPilot 0.0.1 发布</span>
                      <div style="display:flex;align-items:center;gap:8px;flex-shrink:0;">
                        <span style="font-size:10px;padding:1px 6px;border-radius:10px;font-weight:500;background:rgba(74,222,128,0.15);color:var(--green);">active</span>
                      </div>
                    </div>
                    <div style="padding-left:22px;">
                      <!-- W22 (5/25-5/31) -->
                      <div data-fp-plan-week="22" style="margin-bottom:2px;">
                        <div style="display:flex;align-items:center;gap:6px;padding:6px 8px;border-radius:var(--radius);cursor:pointer;font-size:13px;font-weight:500;">
                          <span style="font-size:10px;color:var(--dim);width:14px;text-align:center;transform:rotate(90deg);flex-shrink:0;">▶</span>
                          <span style="font-size:12px;flex-shrink:0;">📅</span>
                          <span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">W22 · 05-25 ~ 05-31</span>
                          <span style="font-size:10px;font-weight:400;color:var(--dim);font-family:var(--mono);">3 项</span>
                        </div>
                        <div style="padding-left:22px;">
                          <!-- FP-002: 看板状态模型实现 (in_progress) -->
                          <div class="fp-month-task" data-fp-schedule="week" style="margin-bottom:2px;">
                            <div onclick="openTaskDetail()" style="display:flex;align-items:center;gap:6px;padding:6px 8px;border-radius:var(--radius);cursor:pointer;font-size:13px;">
                              <span style="font-size:10px;width:14px;visibility:hidden;flex-shrink:0;">▶</span>
                              <span style="width:7px;height:7px;border-radius:50%;flex-shrink:0;border:1.5px solid #5b8af5;background:#5b8af5;"></span>
                              <span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">看板状态模型实现</span>
                              <div style="display:flex;align-items:center;gap:8px;flex-shrink:0;">
                                <span style="font-size:10px;padding:2px 6px;border-radius:3px;font-weight:500;background:rgba(248,113,113,0.15);color:var(--red);">P0</span>
                                <span style="font-size:10px;padding:2px 6px;border-radius:3px;font-weight:500;background:rgba(82,156,202,0.15);color:var(--accent);">auto</span>
                              </div>
                            </div>
                          </div>
                          <!-- FP-010: 整理本周会议记录 (todo) -->
                          <div class="fp-month-task" data-fp-schedule="today" style="margin-bottom:2px;">
                            <div style="display:flex;align-items:center;gap:6px;padding:6px 8px;border-radius:var(--radius);cursor:pointer;font-size:13px;">
                              <span style="font-size:10px;width:14px;visibility:hidden;flex-shrink:0;">▶</span>
                              <span style="width:7px;height:7px;border-radius:50%;flex-shrink:0;border:1.5px solid #9399b0;background:transparent;"></span>
                              <span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">整理本周会议记录</span>
                              <div style="display:flex;align-items:center;gap:8px;flex-shrink:0;">
                                <span style="font-size:10px;padding:2px 6px;border-radius:3px;font-weight:500;background:rgba(99,105,133,0.2);color:var(--dim);">P2</span>
                                <span style="font-size:10px;padding:2px 6px;border-radius:3px;font-weight:500;background:rgba(160,124,245,0.15);color:var(--purple);">manual</span>
                              </div>
                            </div>
                          </div>
                          <!-- FP-011: 研究 Multica 执行模型 (in_progress) -->
                          <div class="fp-month-task" data-fp-schedule="today" style="margin-bottom:2px;">
                            <div onclick="openTaskDetail()" style="display:flex;align-items:center;gap:6px;padding:6px 8px;border-radius:var(--radius);cursor:pointer;font-size:13px;">
                              <span style="font-size:10px;width:14px;visibility:hidden;flex-shrink:0;">▶</span>
                              <span style="width:7px;height:7px;border-radius:50%;flex-shrink:0;border:1.5px solid #5b8af5;background:#5b8af5;"></span>
                              <span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">研究 Multica 执行模型</span>
                              <div style="display:flex;align-items:center;gap:8px;flex-shrink:0;">
                                <span style="font-size:10px;padding:2px 6px;border-radius:3px;font-weight:500;background:rgba(249,115,22,0.15);color:#f97316;">P1</span>
                                <span style="font-size:10px;padding:2px 6px;border-radius:3px;font-weight:500;background:rgba(160,124,245,0.15);color:var(--purple);">manual</span>
                              </div>
                            </div>
                          </div>
                        </div>
                      </div>
                      <!-- W23 (6/1-6/7) -->
                      <div data-fp-plan-week="23" style="margin-bottom:2px;">
                        <div style="display:flex;align-items:center;gap:6px;padding:6px 8px;border-radius:var(--radius);cursor:pointer;font-size:13px;font-weight:500;">
                          <span style="font-size:10px;color:var(--dim);width:14px;text-align:center;transform:rotate(90deg);flex-shrink:0;">▶</span>
                          <span style="font-size:12px;flex-shrink:0;">📅</span>
                          <span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">W23 · 06-01 ~ 06-07</span>
                          <span style="font-size:10px;font-weight:400;color:var(--dim);font-family:var(--mono);">2 项</span>
                        </div>
                        <div style="padding-left:22px;">
                          <!-- FP-006: 主题系统适配 (backlog) -->
                          <div class="fp-month-task" data-fp-schedule="month" style="margin-bottom:2px;">
                            <div style="display:flex;align-items:center;gap:6px;padding:6px 8px;border-radius:var(--radius);cursor:pointer;font-size:13px;">
                              <span style="font-size:10px;width:14px;visibility:hidden;flex-shrink:0;">▶</span>
                              <span style="width:7px;height:7px;border-radius:50%;flex-shrink:0;border:1.5px solid #9399b0;background:transparent;"></span>
                              <span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">主题系统适配</span>
                              <div style="display:flex;align-items:center;gap:8px;flex-shrink:0;">
                                <span style="font-size:10px;padding:2px 6px;border-radius:3px;font-weight:500;background:rgba(99,105,133,0.2);color:var(--dim);">P2</span>
                                <span style="font-size:10px;padding:2px 6px;border-radius:3px;font-weight:500;background:rgba(82,156,202,0.15);color:var(--accent);">auto</span>
                              </div>
                            </div>
                          </div>
                          <!-- FP-009: Anki 同步接口设计 (backlog) -->
                          <div class="fp-month-task" data-fp-schedule="month" style="margin-bottom:2px;">
                            <div style="display:flex;align-items:center;gap:6px;padding:6px 8px;border-radius:var(--radius);cursor:pointer;font-size:13px;">
                              <span style="font-size:10px;width:14px;visibility:hidden;flex-shrink:0;">▶</span>
                              <span style="width:7px;height:7px;border-radius:50%;flex-shrink:0;border:1.5px solid #9399b0;background:transparent;"></span>
                              <span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">Anki 同步接口设计</span>
                              <div style="display:flex;align-items:center;gap:8px;flex-shrink:0;">
                                <span style="font-size:10px;padding:2px 6px;border-radius:3px;font-weight:500;background:rgba(99,105,133,0.2);color:var(--dim);">P2</span>
                                <span style="font-size:10px;padding:2px 6px;border-radius:3px;font-weight:500;background:rgba(82,156,202,0.15);color:var(--accent);">auto</span>
                              </div>
                            </div>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
              <!-- Right: Week-column Gantt -->
              <div style="flex:1;overflow-x:auto;overflow-y:auto;position:relative;background:var(--bg);">
                <!-- Gantt Header: W21~W25 (5 weeks covering May) -->
                <div style="position:sticky;top:0;z-index:5;display:flex;background:var(--surface);border-bottom:1px solid var(--line-soft);height:36px;">
                  <div style="min-width:144px;flex:1;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:500;color:var(--dim);border-right:1px solid var(--line-soft);position:relative;flex-direction:column;gap:0;">
                    <span>W21</span><span style="font-family:var(--mono);font-size:8px;opacity:0.5;">05-18</span>
                  </div>
                  <div style="min-width:144px;flex:1;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:500;color:var(--accent);border-right:1px solid var(--line-soft);position:relative;flex-direction:column;gap:0;">
                    <span>W22</span><span style="font-family:var(--mono);font-size:8px;opacity:0.5;">05-25</span>
                    <span style="position:absolute;bottom:0;left:0;right:0;height:2px;background:var(--accent);"></span>
                  </div>
                  <div style="min-width:144px;flex:1;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:500;color:var(--dim);border-right:1px solid var(--line-soft);position:relative;flex-direction:column;gap:0;">
                    <span>W23</span><span style="font-family:var(--mono);font-size:8px;opacity:0.5;">06-01</span>
                  </div>
                  <div style="min-width:144px;flex:1;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:500;color:var(--dim);border-right:1px solid var(--line-soft);position:relative;flex-direction:column;gap:0;">
                    <span>W24</span><span style="font-family:var(--mono);font-size:8px;opacity:0.5;">06-08</span>
                  </div>
                  <div style="min-width:144px;flex:1;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:500;color:var(--dim);position:relative;flex-direction:column;gap:0;">
                    <span>W25</span><span style="font-family:var(--mono);font-size:8px;opacity:0.5;">06-15</span>
                  </div>
                </div>
                <!-- Gantt Body -->
                <div style="padding:8px 0;min-height:100%;position:relative;min-width:720px;">
                  <!-- Today line (W22, early) -->
                  <div style="position:absolute;top:0;bottom:0;width:1px;background:var(--red);z-index:3;opacity:0.6;left:160px;"><span style="position:absolute;top:4px;left:-14px;font-size:9px;color:var(--red);font-weight:500;">今天</span></div>
                  <!-- Goal bar: Q2 spans W21~W25 -->
                  <div style="height:34px;display:flex;align-items:center;position:relative;">
                    <div style="position:absolute;height:20px;border-radius:4px;display:flex;align-items:center;padding:0 8px;font-size:10px;font-weight:500;cursor:pointer;overflow:hidden;white-space:nowrap;background:rgba(82,156,202,0.2);border:1px solid rgba(82,156,202,0.3);color:var(--accent);left:4px;width:716px;">
                      <div style="position:absolute;left:0;top:0;bottom:0;width:38%;background:rgba(82,156,202,0.15);border-radius:4px;"></div>
                      Q2 FocusPilot 0.0.1
                    </div>
                  </div>
                  <!-- W22 Tasks -->
                  <div data-fp-plan-week="22">
                    <!-- FP-002: 看板状态模型 W22 (in_progress) -->
                    <div class="fp-month-task" data-fp-schedule="week" style="height:34px;display:flex;align-items:center;position:relative;">
                      <div style="position:absolute;height:14px;border-radius:3px;cursor:pointer;overflow:hidden;white-space:nowrap;display:flex;align-items:center;padding:0 6px;font-size:9px;color:rgba(255,255,255,0.8);background:rgba(91,138,245,0.4);border:1px solid rgba(91,138,245,0.5);left:150px;width:130px;" title="看板状态模型实现">看板状态模型</div>
                    </div>
                    <!-- FP-010: 会议记录 W22 (todo) -->
                    <div class="fp-month-task" data-fp-schedule="today" style="height:34px;display:flex;align-items:center;position:relative;">
                      <div style="position:absolute;height:14px;border-radius:3px;cursor:pointer;overflow:hidden;white-space:nowrap;background:rgba(147,153,176,0.3);border:1px solid rgba(147,153,176,0.3);left:170px;width:40px;" title="整理本周会议记录"></div>
                    </div>
                    <!-- FP-011: Multica 研究 W22 (in_progress) -->
                    <div class="fp-month-task" data-fp-schedule="today" style="height:34px;display:flex;align-items:center;position:relative;">
                      <div style="position:absolute;height:14px;border-radius:3px;cursor:pointer;overflow:hidden;white-space:nowrap;display:flex;align-items:center;padding:0 6px;font-size:9px;color:rgba(255,255,255,0.8);background:rgba(91,138,245,0.4);border:1px solid rgba(91,138,245,0.5);left:150px;width:80px;" title="研究 Multica 执行模型">Multica</div>
                    </div>
                  </div>
                  <!-- W23 Tasks -->
                  <div data-fp-plan-week="23">
                    <!-- FP-006: 主题系统适配 W23 (backlog) -->
                    <div class="fp-month-task" data-fp-schedule="month" style="height:34px;display:flex;align-items:center;position:relative;">
                      <div style="position:absolute;height:14px;border-radius:3px;cursor:pointer;overflow:hidden;white-space:nowrap;background:rgba(255,255,255,0.06);border:1px solid rgba(147,153,176,0.2);color:var(--dim);left:300px;width:100px;" title="主题系统适配"></div>
                    </div>
                    <!-- FP-009: Anki 同步 W23 (backlog) -->
                    <div class="fp-month-task" data-fp-schedule="month" style="height:34px;display:flex;align-items:center;position:relative;">
                      <div style="position:absolute;height:14px;border-radius:3px;cursor:pointer;overflow:hidden;white-space:nowrap;background:rgba(255,255,255,0.06);border:1px solid rgba(147,153,176,0.2);color:var(--dim);left:310px;width:80px;" title="Anki 同步接口设计"></div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
```

- [ ] **Step 2: 验证 HTML 结构**

在浏览器中打开 `docs/fp-ui/00-layout-prototype.html`，点击 Focus 页面，此时 fp-month 应该 `display:none`（不可见）。确认页面无报错。

- [ ] **Step 3: Commit**

```bash
git add docs/fp-ui/00-layout-prototype.html
git commit -m "feat(fp-ui): 新增 fp-month 子视图 HTML（按周分组树+周列甘特）"
```

---

### Task 2: 改造 fp-week 左侧为按天分组

**Files:**
- Modify: `docs/fp-ui/00-layout-prototype.html:1952-2015` (fp-week 左侧面板)

- [ ] **Step 1: 将 fp-week 左侧从扁平列表改为按星期几分组**

找到 `#fp-week` 的左侧 div（从 `<!-- Left: Task List -->` 到 `</div>` 结束标签），将原来的扁平任务列表替换为按天分组结构。

将 fp-week 左侧面板的 `<!-- Scheduled tasks -->` 到 `</div>` 闭合标签（即 `<div style="padding:6px 0 0;">` 开始的整个块）替换为以下内容：

```html
                <!-- Day-grouped tasks -->
                <div style="padding:6px 0 0;">
                  <!-- 周一 (5/25) — 当天高亮 -->
                  <div data-fp-week-day="1" style="margin-bottom:2px;">
                    <div style="display:flex;align-items:center;gap:6px;padding:4px 12px;font-size:11px;font-weight:600;color:var(--accent);">
                      <span style="font-size:10px;color:var(--dim);width:10px;text-align:center;transform:rotate(90deg);flex-shrink:0;">▶</span>
                      周一 · 05-25
                      <span style="font-size:9px;padding:1px 5px;border-radius:3px;background:var(--accent);color:#fff;font-weight:500;">今天</span>
                      <span style="font-size:10px;font-weight:400;color:var(--dim);font-family:var(--mono);margin-left:auto;">4 项</span>
                    </div>
                    <div style="padding-left:10px;">
                      <div class="fp-week-task" data-fp-schedule="week" onclick="openTaskDetail()" style="height:34px;display:flex;align-items:center;gap:6px;padding:0 12px;cursor:pointer;border-radius:var(--radius);font-size:12px;">
                        <span style="width:7px;height:7px;border-radius:50%;flex-shrink:0;border:1.5px solid #5b8af5;background:#5b8af5;"></span>
                        <span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">看板状态模型实现</span>
                        <span style="font-size:10px;padding:2px 6px;border-radius:3px;font-weight:500;background:rgba(248,113,113,0.15);color:var(--red);">P0</span>
                        <span style="font-size:11px;flex-shrink:0;">🤖</span>
                      </div>
                      <div class="fp-week-task" data-fp-schedule="today" onclick="openTaskDetail()" style="height:34px;display:flex;align-items:center;gap:6px;padding:0 12px;cursor:pointer;border-radius:var(--radius);font-size:12px;">
                        <span style="width:7px;height:7px;border-radius:50%;flex-shrink:0;border:1.5px solid #9399b0;background:transparent;"></span>
                        <span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">整理本周会议记录</span>
                        <span style="font-size:10px;padding:2px 6px;border-radius:3px;font-weight:500;background:rgba(99,105,133,0.2);color:var(--dim);">P2</span>
                        <span style="font-size:11px;flex-shrink:0;">🖐</span>
                      </div>
                      <div class="fp-week-task" data-fp-schedule="today" onclick="openTaskDetail()" style="height:34px;display:flex;align-items:center;gap:6px;padding:0 12px;cursor:pointer;border-radius:var(--radius);font-size:12px;">
                        <span style="width:7px;height:7px;border-radius:50%;flex-shrink:0;border:1.5px solid #5b8af5;background:#5b8af5;"></span>
                        <span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">研究 Multica 执行模型</span>
                        <span style="font-size:10px;padding:2px 6px;border-radius:3px;font-weight:500;background:rgba(249,115,22,0.15);color:#f97316;">P1</span>
                        <span style="font-size:11px;flex-shrink:0;">🖐</span>
                      </div>
                      <div class="fp-week-task" data-fp-schedule="week" style="height:34px;display:flex;align-items:center;gap:6px;padding:0 12px;cursor:pointer;border-radius:var(--radius);font-size:12px;opacity:.6;">
                        <span style="width:7px;height:7px;border-radius:50%;flex-shrink:0;border:1.5px solid var(--green);background:var(--green);"></span>
                        <span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;text-decoration:line-through;color:var(--dim);">数据模型设计</span>
                        <span style="font-size:10px;color:var(--green);">✓</span>
                      </div>
                    </div>
                  </div>
                  <!-- 周二 (5/26) -->
                  <div data-fp-week-day="2" style="margin-bottom:2px;">
                    <div style="display:flex;align-items:center;gap:6px;padding:4px 12px;font-size:11px;font-weight:600;color:var(--text);">
                      <span style="font-size:10px;color:var(--dim);width:10px;text-align:center;transform:rotate(90deg);flex-shrink:0;">▶</span>
                      周二 · 05-26
                      <span style="font-size:10px;font-weight:400;color:var(--dim);font-family:var(--mono);margin-left:auto;">1 项</span>
                    </div>
                    <div style="padding-left:10px;">
                      <div class="fp-week-task" data-fp-schedule="week" onclick="openTaskDetail()" style="height:34px;display:flex;align-items:center;gap:6px;padding:0 12px;cursor:pointer;border-radius:var(--radius);font-size:12px;">
                        <span style="width:7px;height:7px;border-radius:50%;flex-shrink:0;border:1.5px solid var(--purple);background:var(--purple);"></span>
                        <span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">规划引擎接口设计</span>
                        <span style="font-size:10px;padding:2px 6px;border-radius:3px;font-weight:500;background:rgba(248,113,113,0.15);color:var(--red);">P0</span>
                        <span style="font-size:10px;padding:2px 6px;border-radius:3px;font-weight:500;background:rgba(242,196,15,0.15);color:var(--amber);">等你决策</span>
                      </div>
                    </div>
                  </div>
                  <!-- 周三 (5/27) -->
                  <div data-fp-week-day="3" style="margin-bottom:2px;">
                    <div style="display:flex;align-items:center;gap:6px;padding:4px 12px;font-size:11px;font-weight:600;color:var(--text);">
                      <span style="font-size:10px;color:var(--dim);width:10px;text-align:center;transform:rotate(90deg);flex-shrink:0;">▶</span>
                      周三 · 05-27
                      <span style="font-size:10px;font-weight:400;color:var(--dim);font-family:var(--mono);margin-left:auto;">2 项</span>
                    </div>
                    <div style="padding-left:10px;">
                      <div class="fp-week-task" data-fp-schedule="week" onclick="openTaskDetail()" style="height:34px;display:flex;align-items:center;gap:6px;padding:0 12px;cursor:pointer;border-radius:var(--radius);font-size:12px;">
                        <span style="width:7px;height:7px;border-radius:50%;flex-shrink:0;border:1.5px solid #9399b0;background:transparent;"></span>
                        <span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">Agent Pull 执行管道</span>
                        <span style="font-size:10px;padding:2px 6px;border-radius:3px;font-weight:500;background:rgba(249,115,22,0.15);color:#f97316;">P1</span>
                        <span style="font-size:11px;flex-shrink:0;">🤖</span>
                      </div>
                      <div class="fp-week-task" data-fp-schedule="week" onclick="openTaskDetail()" style="height:34px;display:flex;align-items:center;gap:6px;padding:0 12px;cursor:pointer;border-radius:var(--radius);font-size:12px;">
                        <span style="width:7px;height:7px;border-radius:50%;flex-shrink:0;border:1.5px solid #9399b0;background:transparent;"></span>
                        <span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">Terminal 手动执行模式</span>
                        <span style="font-size:10px;padding:2px 6px;border-radius:3px;font-weight:500;background:rgba(249,115,22,0.15);color:#f97316;">P1</span>
                        <span style="font-size:11px;flex-shrink:0;">🖐</span>
                      </div>
                    </div>
                  </div>
                  <!-- 周四~周日 无任务，折叠显示 -->
                  <div data-fp-week-day="4" style="margin-bottom:2px;">
                    <div style="display:flex;align-items:center;gap:6px;padding:4px 12px;font-size:11px;font-weight:600;color:var(--dim);opacity:0.5;">
                      <span style="font-size:10px;color:var(--dim);width:10px;text-align:center;flex-shrink:0;">▶</span>
                      周四 · 05-28
                    </div>
                  </div>
                  <div data-fp-week-day="5" style="margin-bottom:2px;">
                    <div style="display:flex;align-items:center;gap:6px;padding:4px 12px;font-size:11px;font-weight:600;color:var(--dim);opacity:0.5;">
                      <span style="font-size:10px;color:var(--dim);width:10px;text-align:center;flex-shrink:0;">▶</span>
                      周五 · 05-29
                      <span style="font-size:10px;font-weight:400;color:var(--dim);font-family:var(--mono);margin-left:auto;">1 项</span>
                    </div>
                    <div style="padding-left:10px;">
                      <div class="fp-week-task" data-fp-schedule="week" style="height:34px;display:flex;align-items:center;gap:6px;padding:0 12px;cursor:pointer;border-radius:var(--radius);font-size:12px;opacity:.6;">
                        <span style="width:7px;height:7px;border-radius:50%;flex-shrink:0;border:1.5px solid var(--green);background:var(--green);"></span>
                        <span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;text-decoration:line-through;color:var(--dim);">PRD 文档整合</span>
                        <span style="font-size:10px;color:var(--green);">✓</span>
                      </div>
                    </div>
                  </div>
                  <div data-fp-week-day="6" style="margin-bottom:2px;">
                    <div style="display:flex;align-items:center;gap:6px;padding:4px 12px;font-size:11px;font-weight:600;color:var(--dim);opacity:0.5;">
                      <span style="font-size:10px;color:var(--dim);width:10px;text-align:center;flex-shrink:0;">▶</span>
                      周六 · 05-30
                    </div>
                  </div>
                  <div data-fp-week-day="7" style="margin-bottom:2px;">
                    <div style="display:flex;align-items:center;gap:6px;padding:4px 12px;font-size:11px;font-weight:600;color:var(--dim);opacity:0.5;">
                      <span style="font-size:10px;color:var(--dim);width:10px;text-align:center;flex-shrink:0;">▶</span>
                      周日 · 05-31
                    </div>
                  </div>
                </div>
```

注意：保留 fp-week 的 Title 行和 Legend 行不变，仅替换从 `<!-- Scheduled tasks -->` 开始的内容。原来的 `已排期 · 8 项` 分区和任务列表全部删除，替换为按天分组。

- [ ] **Step 2: 验证浏览器中 fp-week 显示正常**

打开原型文件，点击侧边栏"本周计划"，确认左侧显示按天分组的任务列表（周一~周日），右侧甘特不变。

- [ ] **Step 3: Commit**

```bash
git add docs/fp-ui/00-layout-prototype.html
git commit -m "feat(fp-ui): fp-week 左侧改造为按天/星期几分组"
```

---

### Task 3: 更新 JS — modeMap + fp-month 过滤 + 标题联动

**Files:**
- Modify: `docs/fp-ui/00-layout-prototype.html` (JS `applyFocusFilter` 函数区域)

- [ ] **Step 1: 更新 modeMap 添加 month 映射**

找到 JS 中的这行（约第 3463 行）：

```javascript
const modeMap = { today: 'fp-day', week: 'fp-week' };
```

替换为：

```javascript
const modeMap = { today: 'fp-day', week: 'fp-week', month: 'fp-month' };
```

- [ ] **Step 2: 添加 fp-month-task 过滤逻辑**

在 `// 日视图任务行过滤` 块（`document.querySelectorAll('.fp-day-task')` 循环）之后，添加月视图任务行过滤：

```javascript
        // 月视图任务行过滤
        document.querySelectorAll('.fp-month-task').forEach(function(el) {
          if (filter === 'all') { el.style.display = ''; return; }
          if (filter === 'month') {
            if (el.dataset.fpMonth) { el.style.display = el.dataset.fpMonth === curMonth ? '' : 'none'; }
            else { el.style.display = monthSet.includes(el.dataset.fpSchedule) ? '' : 'none'; }
            return;
          }
          if (filter === 'week') { el.style.display = weekSet.includes(el.dataset.fpSchedule) ? '' : 'none'; return; }
          if (filter === 'today') { el.style.display = el.dataset.fpSchedule === 'today' ? '' : 'none'; return; }
          el.style.display = '';
        });
```

- [ ] **Step 3: 更新标题联动逻辑**

找到标题联动代码块（约第 3540-3548 行）。将 `fpYearTitle` 的更新逻辑改为根据当前活跃的子视图显示不同标题。

将现有的标题联动代码：

```javascript
        var titleEl = document.getElementById('fpYearTitle');
        if (titleEl) {
          var visCount = 0;
          document.querySelectorAll('#fp-year .fp-plan-task').forEach(function(el) { if (el.style.display !== 'none') visCount++; });
          visCount = Math.round(visCount / 2);
          var labels = { all: '📋 全局规划', month: '📆 本月计划', week: '📅 本周计划', today: '🔥 今日聚焦' };
          var label = labels[filter] || '📋 全局规划';
          titleEl.innerHTML = label + ' · 月视图 <span style="font-size:10px;font-weight:400;color:var(--dim);font-family:var(--mono);">' + visCount + ' 项</span>';
        }
```

替换为：

```javascript
        // fp-year 标题
        var titleEl = document.getElementById('fpYearTitle');
        if (titleEl) {
          var visCount = 0;
          document.querySelectorAll('#fp-year .fp-plan-task').forEach(function(el) { if (el.style.display !== 'none') visCount++; });
          visCount = Math.round(visCount / 2);
          titleEl.innerHTML = '📋 全局规划 · 月视图 <span style="font-size:10px;font-weight:400;color:var(--dim);font-family:var(--mono);">' + visCount + ' 项</span>';
        }
        // fp-month 标题
        var monthTitleEl = document.getElementById('fpMonthTitle');
        if (monthTitleEl) {
          var monthVisCount = 0;
          document.querySelectorAll('#fp-month .fp-month-task').forEach(function(el) { if (el.style.display !== 'none') monthVisCount++; });
          monthVisCount = Math.round(monthVisCount / 2);
          monthTitleEl.innerHTML = '📆 本月计划 · 周视图 <span style="font-size:10px;font-weight:400;color:var(--dim);font-family:var(--mono);">' + monthVisCount + ' 项</span>';
        }
```

- [ ] **Step 4: 验证浏览器中切换 Scope 工作正常**

打开原型，依次点击侧边栏的"全局规划"、"本月计划"、"本周计划"、"今日聚焦"，验证：
1. 全局规划 → 显示 fp-year（月列甘特），标题"全局规划 · 月视图"
2. 本月计划 → 显示 fp-month（周列甘特），标题"本月计划 · 周视图"
3. 本周计划 → 显示 fp-week（天列甘特，左侧按天分组），标题不变
4. 今日聚焦 → 显示 fp-day（小时列甘特），标题不变

- [ ] **Step 5: Commit**

```bash
git add docs/fp-ui/00-layout-prototype.html
git commit -m "feat(fp-ui): modeMap 新增 month→fp-month + 月视图过滤与标题联动"
```

---

### Task 4: 同步 03-focus.md 页面规格

**Files:**
- Modify: `docs/fp-ui/03-focus.md`

- [ ] **Step 1: 更新规划子视图描述**

在 `03-focus.md` 中找到规划子视图相关的描述段落，增加 fp-month 子视图说明，更新 fp-week 的左侧描述为"按天/星期几分组"。

具体需要在规格文档中体现：
- 新增 fp-month 子视图：左侧按周分组任务树 + 右侧周列甘特
- fp-week 子视图左侧从扁平列表改为按天分组
- modeMap 映射关系更新
- 分级时间粒度总表：全局→月列，本月→周列，本周→天列，今日→小时列

由于 `03-focus.md` 内容较长，实施时需先 Read 文件找到"规划"或"子视图"相关段落，然后定位修改。关键要更新的内容：

1. 规划模式子视图映射表（如果有的话）
2. 侧边栏 Scope 与子视图的对应关系说明
3. 甘特时间粒度描述

- [ ] **Step 2: Commit**

```bash
git add docs/fp-ui/03-focus.md
git commit -m "docs(fp-ui): 同步 Focus 规格——新增 fp-month 子视图、fp-week 按天分组"
```

---

### Task 5: 浏览器验收 + 最终提交

**Files:**
- All changes in `docs/fp-ui/00-layout-prototype.html` and `docs/fp-ui/03-focus.md`

- [ ] **Step 1: 完整验收**

在浏览器中打开 `docs/fp-ui/00-layout-prototype.html`，验收以下场景：

| 操作 | 预期结果 |
|------|---------|
| 点击"全局规划" | 显示 fp-year，左侧季度→月树，右侧月列甘特 |
| 点击"本月计划" | 显示 fp-month，左侧 W22/W23 分组，右侧 W21~W25 甘特列 |
| 点击"本周计划" | 显示 fp-week，左侧按周一~周日分组，右侧天列甘特 |
| 点击"今日聚焦" | 显示 fp-day，左侧时段分组，右侧小时列甘特 |
| 切回"全局规划" | fp-year 恢复正常显示 |
| 看板/列表 Tab 切换 | 不受影响，仍正常工作 |

- [ ] **Step 2: 推送到远程**

```bash
git push
```
