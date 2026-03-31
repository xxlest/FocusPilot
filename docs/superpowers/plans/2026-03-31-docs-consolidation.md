# 文档整合实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将项目文档去重整合为 PRD / Architecture / DesignGuide 三份互不重叠的主文档，归档早期 Draft，更新 CLAUDE.md 为索引角色。

**Architecture:** 纯文档重组，无代码变更。三份主文档各有明确边界：PRD 回答"做什么"，Architecture 回答"怎么实现"，DesignGuide 回答"长什么样"。内容从现有 PRD.md、Architecture.md、CLAUDE.md、IconDesign.md 及 superpowers specs 中提取整合，消除重叠。

**Tech Stack:** Markdown, Git

**设计规格:** `docs/superpowers/specs/2026-03-31-docs-consolidation-design.md`

---

## 全局注意事项

- 本计划所有文档使用中文
- 不添加 `Co-Authored-By` 签名行
- 每个 Task 完成后执行 `git add` + `git commit`，不推送（最后统一推送）
- AI Tab / Coder-Bridge 相关内容需从 superpowers specs 和当前代码中补充到 PRD 和 Architecture
- 当前版本号统一标注为 V4.2

---

### Task 1: 归档早期 Draft 文件

**Files:**
- Create: `docs/archive/` 目录结构
- Move: 多个文件（见下方清单）

- [ ] **Step 1: 创建归档目录并移动文件**

```bash
cd /Users/bruce/Workspace/2-Code/01-work/FocusPilot

# 创建归档目录
mkdir -p docs/archive/FocusCC
mkdir -p docs/archive/ide-proxy
mkdir -p docs/archive/focus-by-time
mkdir -p docs/archive/focuspilot

# 移动 Focus系列 子目录内容
mv "docs/Focus系列/focuspilot/FocusPilot-PRD-V1.md" docs/archive/focuspilot/
mv "docs/Focus系列/focuspilot/FocusPilot-总架构设计.md" docs/archive/focuspilot/
mv "docs/Focus系列/FocusCC/prd.md" docs/archive/FocusCC/
mv "docs/Focus系列/FocusCC/feasibility-analysis.md" docs/archive/FocusCC/
mv "docs/Focus系列/FocusCC/Claude Code 非交互调用封号风险调研报告.md" docs/archive/FocusCC/
mv "docs/Focus系列/FocusCC/Opcode 项目技术分析文档：Claude Code 控制与实时交互机制.md" docs/archive/FocusCC/
mv "docs/Focus系列/ide-proxy/IDE-Proxy-设计梳理.md" docs/archive/ide-proxy/
mv "docs/Focus系列/ide-proxy/IDE-Proxy-技术架构与验证.md" docs/archive/ide-proxy/
mv "docs/Focus系列/ide-proxy/cli_wrap.md" docs/archive/ide-proxy/
mv "docs/Focus系列/focus-by-time/FocusByTime-PRD.md" docs/archive/focus-by-time/

# 移动根目录级历史文件
mv docs/acceptance-report.md docs/archive/
mv docs/monetization-strategy.md docs/archive/

# 清理空目录和重复文件
rm -f "docs/Focus系列/IDE-Proxy-设计梳理.md"
rm -f "docs/Focus系列/IDE-Proxy-技术架构与验证.md"
rm -rf "docs/Focus系列/"
```

- [ ] **Step 2: 提交**

```bash
git add docs/archive/ docs/Focus系列/ docs/acceptance-report.md docs/monetization-strategy.md
git commit -m "chore(docs): 归档早期 Draft 文件到 docs/archive/

- FocusPilot V1 PRD 和总架构设计（已被主文档取代）
- FocusCC PRD、可行性分析、调研报告（未实现产品线）
- IDE-Proxy 设计和技术架构（未实现产品线）
- FocusByTime 独立 PRD（已融入主 PRD）
- PinTop V1.1 验收报告和商业化策略（历史记录）
- 清理 Focus系列/ 重复文件和空目录"
```

---

### Task 2: 新建 DesignGuide.md

**Files:**
- Create: `docs/DesignGuide.md`
- Read: `CLAUDE.md`（设计基调 section）、`docs/IconDesign.md`、`docs/PRD.md`（主题/动画参数）、`FocusPilot/Helpers/Constants.swift`、`FocusPilot/Models/Models.swift`（ThemeColors）

- [ ] **Step 1: 从源文件提取设计内容，创建 DesignGuide.md**

创建 `docs/DesignGuide.md`，内容结构：

```markdown
# Focus Copilot 设计规范

> **版本**：V4.2
> **日期**：2026-03-31
> **读者**：UI 修改、视觉调整、新增界面元素时必读

---

## 1. 设计基调与哲学

### 核心基调：干净 · 高级 · 克制 · 专业

[从 CLAUDE.md「设计基调与风格 > 核心基调」提取，保持原文]

### 产品哲学：专注 × 禅意

[从 CLAUDE.md「设计基调与风格 > 产品哲学」提取，保持原文]

---

## 2. 品牌图标设计：禅圆（Enso）

[整合 docs/IconDesign.md 全部内容]

### 2.1 图标构成
- 底层：渐变球体（蓝色径向渐变 + 左上高光 + 底部暗影）
- 上层：禅圆 Enso（白色未闭合弧线 300 度，起笔墨滴 → 渐隐散点收束）

### 2.2 与 FocusPilot 的寓意关联
[从 IconDesign.md 提取 6 点寓意]

### 2.3 技术实现
- 图标生成脚本：`scripts/gen-icon.swift`
- 悬浮球绘制：`FloatingBallView.createBrandLogoImage`
- **修改时两处必须同步**

---

## 3. 视觉准则

### 3.1 克制用色
Notion 风格 8 色主题（浅 4 + 深 4），每主题 9 色槽覆盖全 UI。accent 仅用于关键操作和状态指示，大面积留白/留灰，不滥用彩色。

### 3.2 原生质感
毛玻璃（NSVisualEffectView）、系统动画曲线（ease-out/ease-in）、SF Symbols，不引入自定义图标库。

### 3.3 层次分明
textPrimary / textSecondary / textTertiary 三级文字层次严格区分，信息权重一目了然。

### 3.4 精致细节
悬浮球径向渐变 + 高光 + 暗区 + 内边缘光 + accent 呼吸光晕；hover 缩放 1.06x；贴边吸附动画——细节服务于高级感，而非炫技。

---

## 4. Notion 风格主题系统

### 4.1 主题概览

| 主题 | 类型 | Accent | 适用场景 |
|---|---|---|---|
| defaultWhite | 浅色 | #E53935（红） | 默认主题，高对比度 |
| warmIvory | 浅色 | #C7873B（暖金） | 温暖文艺感 |
| mintGreen | 浅色 | #2E9E6E（薄荷绿） | 清新自然 |
| lightBlue | 浅色 | #2383E2（蓝） | 专业冷静 |
| classicDark | 深色 | #5B9BF2（亮蓝） | 经典暗色 |
| deepOcean | 深色 | #6BB8F0（海洋蓝） | 深邃沉浸 |
| inkGreen | 深色 | #4DAB8C（墨绿） | 护眼长时间使用 |
| pureBlack | 深色 | #A09DE4（薰衣草紫） | OLED 省电 |

### 4.2 ThemeColors 9 色槽

每个主题通过 `ThemeColors` 结构体提供 9 个语义色槽，同时提供 `ns*`（NSColor）和 `sw*`（SwiftUI Color）双套属性：

| 色槽 | 语义 | 用途 |
|---|---|---|
| background | 主背景 | 面板、窗口背景 |
| sidebarBackground | 侧边栏背景 | 主看板侧边栏 |
| accent | 强调色 | 按钮、活跃状态、悬浮球渐变 |
| textPrimary | 一级文字 | 标题、App 名称 |
| textSecondary | 二级文字 | 副标题、窗口标题 |
| textTertiary | 三级文字 | 辅助信息、时间戳 |
| rowHighlight | 行高亮 | hover/选中行背景 |
| separator | 分隔线 | Tab 分隔、区域分隔 |
| favoriteStar | 关注星号 | 已关注=金色，未关注用 textTertiary |

### 4.3 主题刷新链路

```
PreferencesView → @Published → AppDelegate.applyPreferences()
  → NSApp.appearance 更新（浅色/深色）
  → ballView.updateColorStyle()（悬浮球渐变从 accent 派生）
  → quickPanelWindow.applyTheme()（背景+毛玻璃+叠加层）
  → panelView.forceReload()（全量重建 UI）
  → post themeChanged 通知（FloatingBall 等监听者响应）
```

### 4.4 悬浮球颜色派生

悬浮球渐变色由 `AppTheme.ballGradientColors` 从 accent 自动派生，不再独立配置。

---

## 5. 交互原则

### 5.1 非侵入
悬浮球常驻但不抢焦点（nonactivating NSPanel），面板 hover 弹出 / 离开收起，钉住才持久。

### 5.2 三层递进
悬浮球（零信息，纯入口）→ 快捷面板（紧凑列表，操作为主）→ 主看板（完整配置），信息密度逐层递增。

### 5.3 不打断工作流
弹窗失焦自动关闭，PendingAction 保留上下文，回来后一键继续。

### 5.4 一致性
同一主题下 AppKit + SwiftUI 颜色统一，通过 ThemeColors ns*/sw* 双套桥接。

---

## 6. 动画规范

### 6.1 Design Token（Constants.Design.Anim）

| Token | 时长 | 用途 |
|---|---|---|
| micro | 0.1s | hover 色变、步骤切换文案渐变 |
| fast | 0.15s | 悬浮球 hover 缩放反馈 |
| normal | 0.25s | 面板展开/收起、折叠/展开 |

### 6.2 面板动画

| 动画 | 时长 | 曲线 | 说明 |
|---|---|---|---|
| 弹出 | 250ms | ease-out | 从悬浮球方向缩放+滑出+淡入 |
| 收起 | 120ms | ease-in | 淡出 |
| hover 延迟 | 150ms | - | 悬浮球 hover 到面板弹出的等待时间 |
| 离开延迟 | 500ms | - | 鼠标离开到面板收起的等待时间 |

### 6.3 悬浮球动画

| 动画 | 参数 | 说明 |
|---|---|---|
| hover 缩放 | 1.06x, fast (0.15s) | 鼠标悬浮时微缩放 |
| 贴边吸附 | normal (0.25s), ease-out | 拖拽结束后吸附到最近边缘 |
| 钉住发光环 | 脉冲动画，持续 | 红色发光边框环 |
| accent 光晕 | 常驻 | 从 accent 色派生的阴影光晕 |

---

## 7. 间距规范

### Design Token（Constants.Design.Spacing）

| Token | 数值 | 用途 |
|---|---|---|
| xs | 4pt | 图标与文字间距、紧凑元素间隔 |
| sm | 8pt | 行内元素间距、按钮内边距 |
| md | 12pt | 区域间距、卡片内边距 |
| lg | 16pt | 模块间距 |
| xl | 24pt | 大区域分隔 |

### 圆角规范（Constants.Design.Corner）

| Token | 数值 | 用途 |
|---|---|---|
| sm | 4pt | 图标、小元素 |
| md | 6pt | 行、按钮 |
| lg | 10pt | 卡片、弹窗内组件 |
| xl | 14pt | 面板、窗口 |

---

## 8. 修改时必须遵守的规则

1. **配色**：新增 UI 元素必须使用 ThemeColors 取色，禁止硬编码颜色值，确保 8 主题视觉一致
2. **动画**：参照 `Constants.Design.Anim`（micro/fast/normal），节奏统一，禁止花哨过渡
3. **间距**：参照 `Constants.Design.Spacing`（xs/sm/md/lg/xl），避免随意数值
4. **图标一致**：悬浮球视觉修改必须同步 `FloatingBallView.createBrandLogoImage` 和 `scripts/gen-icon.swift`
5. **弹窗规范**：新增弹窗默认添加失焦自动关闭（`didResignActiveNotification` → `abortModal`）
6. **克制原则**：不加装饰性阴影、不加多余分割线、不加无意义动画，每个元素都应能回答"为什么需要它"
```

注意：主题色值表需从 `Models.swift` 中 `ThemeColors` 的实际定义提取 hex 值填入。读取 Models.swift 中每个主题的 `colors` 属性实现，确保色值准确。

- [ ] **Step 2: 提交**

```bash
git add docs/DesignGuide.md
git commit -m "docs: 新建 DesignGuide.md 设计规范文档

- 从 CLAUDE.md 提取设计基调与哲学、视觉准则、交互原则、修改规则
- 整合 IconDesign.md 品牌图标设计（禅圆 Enso）全部内容
- 从 Constants.swift 提取动画/间距/圆角 Design Token 参数表
- 从 Models.swift 提取 8 主题概览和 ThemeColors 9 色槽定义
- 补充主题刷新链路和悬浮球颜色派生说明"
```

---

### Task 3: 重写 PRD.md

**Files:**
- Modify: `docs/PRD.md`
- Read: 当前 `docs/PRD.md`、`docs/superpowers/specs/2026-03-28-coder-bridge-ai-tab-design.md`、`docs/superpowers/specs/2026-03-29-coder-bridge-ai-tab-v2-design.md`、`docs/superpowers/specs/2026-03-30-host-kind-binding-strategy.md`、`FocusPilot/Models/CoderSession.swift`

**改动要点：**

1. **新增 §3.6 AI Tab（Coder-Bridge）** — 从 superpowers specs 和 CLAUDE.md 提取：
   - 功能描述：第三个 Tab "AI" 展示 AI 编码工具会话
   - 会话生命周期：session.start → session.update → session.end
   - 会话数据：工具类型（Claude/Codex/Gemini）、工作目录、宿主应用、状态（registered/working/idle/done/error）
   - 目录分组展示：按 cwdNormalized 分组，同名消歧
   - 双行 Session 行：主信息行（工具图标+displayName+宿主图标+状态）+ 最近 query 摘要行
   - 窗口绑定与切换：点击 session 行切换到关联宿主窗口
   - HostKind 策略分化：IDE（Cursor/VSCode）多 session 共享窗口，Terminal 独占绑定
   - 两条绑定入口：点击行（隐式绑定，terminal 冲突拦截）vs 右键菜单"绑定到当前窗口"（显式，terminal 允许确认替换）
   - 右键菜单：绑定/解绑窗口、重命名、复制 Session ID、忽略提醒、移除会话
   - isDismissed：idle/error 状态可忽略提醒（降灰+不计角标），状态变化时自动重置
   - 会话不持久化（纯运行时，重启后清空）
   - AI 会话偏好持久化（displayName，按 tool+cwdNormalized+hostApp 索引）

2. **移出数据模型 Swift 定义** — 替换为自然语言描述：
   - AppConfig：保留字段说明表格，移除 Swift 代码块
   - Preferences：保留设置项表格（已有），移除 Swift 定义
   - 技术方案概要 §6（技术栈+架构概要图）精简为 2-3 句话指向 Architecture.md

3. **移出状态转换矩阵** — FocusByTime §3.5.5 状态机保留简化版流程图（给产品看），完整表格移至 Architecture

4. **精简主题相关描述** — §3.3.2 偏好设置中主题行改为"Notion 风格 8 色主题（详见 DesignGuide.md）"，不列色值

5. **更新验收标准** — 新增 AI Tab 相关验收项（F45-F52）：
   - F45: AI Tab 会话列表显示
   - F46: 会话状态实时更新
   - F47: 点击 session 行切换宿主窗口
   - F48: 窗口绑定（自动+手动）
   - F49: HostKind 策略分化
   - F50: 右键菜单操作
   - F51: isDismissed 忽略提醒
   - F52: 悬浮球 AI 角标

- [ ] **Step 1: 读取所有源文件，提取 AI Tab 功能描述**

从以下来源汇总 AI Tab 功能需求：
- `docs/superpowers/specs/2026-03-28-coder-bridge-ai-tab-design.md`（V1 基础设计）
- `docs/superpowers/specs/2026-03-29-coder-bridge-ai-tab-v2-design.md`（V2 目录分组）
- `docs/superpowers/specs/2026-03-30-host-kind-binding-strategy.md`（HostKind 策略）
- `CLAUDE.md`（设计决策条目）
- `FocusPilot/Models/CoderSession.swift`（当前实际模型）
- `FocusPilot/Services/CoderBridgeService.swift`（当前实际服务）

- [ ] **Step 2: 重写 PRD.md**

按照设计规格 §3.1 的目录结构重写，要点：
- §1-§2 基本保持不变（产品概述、产品架构）
- §3.1-§3.5 保持现有内容，精简状态机为简图
- 新增 §3.6 AI Tab（Coder-Bridge）
- §3.7-§3.8 重新编号（辅助功能权限、菜单栏/Dock 图标）
- §4 边界场景新增 AI Tab 相关条目
- §5 非功能需求保持
- §6 技术方案概要精简为 3 句话 + 指向 Architecture.md
- §7 里程碑保持
- §8 验收标准新增 F45-F52
- 附录保持

- [ ] **Step 3: 提交**

```bash
git add docs/PRD.md
git commit -m "docs(PRD): 重写 PRD — 新增 AI Tab、移出技术细节、消除重叠

- 新增 §3.6 AI Tab（Coder-Bridge）完整功能需求
- 移出数据模型 Swift 定义（改为自然语言描述，完整定义在 Architecture.md）
- 移出状态转换矩阵完整表格（保留简化版状态机图）
- 精简技术方案概要（指向 Architecture.md）
- 新增 AI Tab 验收标准 F45-F52
- 主题相关描述精简（详见 DesignGuide.md）"
```

---

### Task 4: 重写 Architecture.md

**Files:**
- Modify: `docs/Architecture.md`
- Read: 当前 `docs/Architecture.md`、`FocusPilot/Services/CoderBridgeService.swift`、`FocusPilot/Models/CoderSession.swift`、`FocusPilot/Helpers/Constants.swift`

**改动要点：**

1. **新增 CoderBridgeService 接口契约（§2.9）** — 从当前代码提取：

```swift
class CoderBridgeService: NSObject {
    static let shared = CoderBridgeService()

    private(set) var sessions: [CoderSession]

    // BindingState 统一 helper
    enum BindingState { case manual, autoValid, autoConflicted, missing }
    func bindingState(for session: CoderSession) -> BindingState
    func allowsSharedBinding(for session: CoderSession) -> Bool

    // 生命周期
    func start()   // 注册 DistributedNotification 监听 + 启动清理定时器

    // 会话查询
    var groupedSessions: [SessionGroup]          // 按目录分组，支持置顶
    var actionableCount: Int                      // 未读可操作会话数（角标用）
    func transcriptPath(for session: CoderSession) -> String?
    func latestQuerySummary(for session: CoderSession, maxLength: Int) -> String?

    // 窗口解析
    func resolveWindowForSession(_ session: CoderSession) -> (CGWindowID?, MatchConfidence)

    // 会话操作
    func markAsRead(sid: String)
    func dismissSession(sid: String)             // 忽略提醒（isDismissed = true）
    func bindSessionToWindow(sid: String, windowID: CGWindowID)
    func clearManualWindowID(sid: String)
    func removeSession(_ sid: String)
    func removeEndedSessions()

    // 置顶
    func pinGroup(_ cwdNormalized: String)
    func pinSession(_ sid: String)
}
```

2. **新增 CoderSession 数据模型（§2.1 扩展）** — 当前代码中的完整定义

3. **新增 Coder-Bridge 事件流（§3.4）**：

```
coder-bridge shell hook
  → DistributedNotification("com.focuscopilot.coder-bridge")
  → CoderBridgeService.handleDistributedNotification
    → session.start: 创建 CoderSession + 自动采样前台窗口
    → session.update: 更新状态 + 重置 isRead/isDismissed
    → session.end: lifecycle → .ended
  → post coderBridgeSessionChanged
  → QuickPanelView.reloadData() (AI Tab)
  → FloatingBallView (角标刷新)
```

4. **新增 AI 会话状态转换矩阵（§4.7）**

5. **新增 AI 会话清理机制（§4.8）**：
   - 已结束 session：2 分钟后自动清除
   - 僵尸 session：registered 状态超 30 秒无后续事件，自动清除
   - 清理定时器间隔：30 秒

6. **更新 Constants（§2.8）** — 补充 `coderBridgeSessionChanged`、`showPreferencesMultiBind`、`sessionPreferences` Key

7. **移出视觉参数** — 版本变更说明中的色值变更改为"详见 DesignGuide.md"

8. **更新文件清单（§7）** — 新增 `CoderSession.swift` 和 `CoderBridgeService.swift` 行数和职责

- [ ] **Step 1: 读取当前 Architecture.md 和代码文件，规划改动点**

- [ ] **Step 2: 重写 Architecture.md**

按照设计规格 §3.2 的目录结构重写，确保：
- §1 技术栈更新（补充 DistributedNotificationCenter）
- §2 文件结构更新（补充 CoderSession.swift、CoderBridgeService.swift）
- §2 数据模型新增 CoderSession、CoderTool、SessionStatus、SessionLifecycle、HostKind、MatchConfidence、BindingState、SessionGroup、CoderSessionPreference、HostAppMapping
- §2 接口契约新增 CoderBridgeService（§2.9）
- §3 模块间交互新增 Coder-Bridge 事件流（§3.4）
- §4 行为约束新增 AI 会话状态转换矩阵 + 清理机制
- §5 验收用例新增 TC-13（AI 会话生命周期）、TC-14（窗口绑定策略）
- §6 关键设计决策补充 coder-bridge 相关条目
- §7 文件清单更新行数

- [ ] **Step 3: 提交**

```bash
git add docs/Architecture.md
git commit -m "docs(Architecture): 重写架构文档 — 补充 Coder-Bridge 完整契约、移出视觉参数

- 新增 CoderSession/CoderBridgeService 完整数据模型和接口契约
- 新增 Coder-Bridge DistributedNotification 事件流
- 新增 AI 会话状态转换矩阵和清理机制
- 新增 TC-13/TC-14 验收用例
- Constants 补充 coderBridgeSessionChanged 等遗漏项
- 版本变更说明中色值变更指向 DesignGuide.md
- 更新文件清单行数"
```

---

### Task 5: 更新 CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`（项目根目录）

**改动要点：**

1. **替换「设计基调与风格」section** — 当前 CLAUDE.md 中从 `## 设计基调与风格` 到 `### 修改时必须遵守` 共约 30 行，替换为：

```markdown
## 文档体系

- **产品需求**：`docs/PRD.md` — 功能清单、交互规则、验收标准
- **技术架构**：`docs/Architecture.md` — 模块划分、接口契约、状态机
- **设计规范**：`docs/DesignGuide.md` — 视觉准则、主题色值、动画参数、修改规则

修改 UI 前必读 DesignGuide.md，修改业务逻辑前必读 Architecture.md。
```

2. **保留的内容不动**：
   - 项目概述
   - 架构（V4.0）及文件结构
   - 关键设计决策
   - 构建命令
   - 开发规范
   - 高频 Bug 防范
   - 配置迁移

3. **架构 section 中的关键设计决策列表** — 补充 coder-bridge 相关条目（与 Architecture.md 一致）

- [ ] **Step 1: 读取当前 CLAUDE.md，定位替换区域**

- [ ] **Step 2: 执行替换**

将 `## 设计基调与风格` 整个 section（从该标题到下一个 `##` 标题之前）替换为上述「文档体系」section。

- [ ] **Step 3: 提交**

```bash
git add CLAUDE.md
git commit -m "docs(CLAUDE.md): 设计规范替换为三文档索引

- 移除内联设计基调/视觉准则/交互原则/修改规则（已迁入 DesignGuide.md）
- 新增「文档体系」索引，指向 PRD / Architecture / DesignGuide"
```

---

### Task 6: 清理 IconDesign.md + 删除空目录

**Files:**
- Move: `docs/IconDesign.md` → `docs/archive/IconDesign.md`
- Delete: `docs/Focus系列/`（如果 Task 1 未完全清理）

- [ ] **Step 1: 归档 IconDesign.md**

```bash
mv docs/IconDesign.md docs/archive/IconDesign.md
```

- [ ] **Step 2: 验证目录结构**

```bash
ls docs/
# 预期输出：
# Architecture.md  DesignGuide.md  PRD.md  archive/  cc的一些概念及操作/  idea.md  superpowers/
```

- [ ] **Step 3: 提交**

```bash
git add docs/IconDesign.md docs/archive/IconDesign.md
git commit -m "chore(docs): 归档 IconDesign.md（已并入 DesignGuide.md）"
```

---

### Task 7: 统一推送 + 最终验证

- [ ] **Step 1: 验证所有文档的交叉引用正确**

检查：
- PRD.md 中对 Architecture.md 和 DesignGuide.md 的引用路径正确
- Architecture.md 中对 PRD.md 和 DesignGuide.md 的引用路径正确
- DesignGuide.md 中对代码文件的引用路径正确
- CLAUDE.md 中三份文档的路径正确

- [ ] **Step 2: 推送**

```bash
git push
```
