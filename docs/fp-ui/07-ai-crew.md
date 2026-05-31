# AICrew 页面设计

> **状态**：可开发
> **更新**：2026-05-30
> **原型**：[00-layout-prototype.html](00-layout-prototype.html)
> **关联**：[PRD §3.4 Crew 数字团队](../PRD.md)

---

## 1. 定位

AICrew 是 AI Agent 团队的**管理中心**。用户面对的不是 Agent、MCP、Skill 等底层概念，而是一个可管理的"数字团队"。

一句话职责：AICrew 管**谁能做什么、能调用哪些工具、什么时候自动做事**。

参考 Multica 的 Runtime/Agent 配置模型后，AICrew 明确采用三层对象：

- `CrewMember`：面向用户的数字成员，承载角色、人设、职责、技能、授权和任务容量。
- `CrewRuntime`：成员背后的执行环境，承载本地/云端、Provider、CLI/daemon、心跳、模型发现和可见性。
- `CrewRun`：一次真实执行记录，承载动态 Task、配置快照、执行日志、统计指标和 Focus 项目定位。

**硬规则**：成员不是 Runtime；一个成员必须绑定一个 Runtime，Runtime 可以服务多个成员。AICrew 对用户仍保持"团队管理"隐喻，但不能把 Runtime 简化成一个不可解释的字符串，也不能把执行历史简化成不可追溯的一行状态。

### 与 Settings 的职责边界

| 维度 | AICrew | Settings |
|------|--------|----------|
| 管理对象 | Crew 成员、能力、MCP、常驻职责 | 全局偏好、默认成员、快捷键、主题 |
| 操作粒度 | 单个成员级配置 | 应用级默认值 |
| 典型问题 | "代码工程师能不能访问 GitHub？" | "默认派给哪个成员？" |

**硬规则**：AICrew 管成员能力；Settings 只引用 AICrew 的结果，不重复配置成员能力。

---

## 2. 侧边栏

侧边栏顶部标题区域仅显示 `AICrew` 标题和搜索框，无操作按钮。标题下方使用分段切换 `智能体成员 / Runtime`，每个分段底部有对应的新建按钮。

### 2.1 智能体成员分段

默认进入此分段。列表展示已有成员，底部提供新建入口和模板。

```
┌─ AICrew ───────────────────────┐
│ [搜索...]                       │
│ [智能体成员] [Runtime]           │
│                                 │
│ 团队成员                         │
│ ● 代码工程师          85%        │
│   claude-code · 本地 · 空闲       │
│                                 │
│ + 新建智能体                     │
│                                 │
│ 模板                             │
│ 架构师              模板         │
│ 数据库工程师         模板         │
│ 数据分析师           模板         │
│                                 │
│ 运行概况                         │
│ 执行中 1 / 30天成功率 85% / 本机执行器 5 │
└─────────────────────────────────┘
```

成员行信息：

| 字段 | 说明 |
|------|------|
| 状态点 | 绿色空闲、黄色执行中、红色不可用 |
| 成员名 | 用户可见角色名 |
| Runtime | 如 `claude-code · 本地 · 空闲` |
| 计数 | 成功率百分比 |

点击成员后，工作区切换到对应成员详情（默认显示动态 Tab）。

### 2.2 Runtime 分段

切到 Runtime 后展示本机、远程电脑和云端执行环境，避免把"人"和"机器"平铺在同一列表里。

```
┌─ AICrew ───────────────────────┐
│ [搜索...]                       │
│ [智能体成员] [Runtime]           │
│                                 │
│ 本机                             │
│ ● MacBook-Pro-10.local     5    │
│   本机 · 5 个执行器 · 空闲        │
│                                 │
│ 远程电脑                         │
│ ○ remote-dev-01            0    │
│   未连接 · 手动添加               │
│                                 │
│ + 添加执行节点                   │
│                                 │
│ 检测范围                         │
│ 本机配置 自动检测 / 远程电脑 需授权 / 执行器 5 在线 │
└─────────────────────────────────┘
```

点击机器后，工作区切换到对应的运行时详情（默认显示执行器 Tab）。

---

## 3. 工作区

工作区根据侧边栏选中对象动态切换：选中成员时显示成员工作区，选中 Runtime 节点时显示 Runtime 工作区。顶部面包屑和 Tab 栏由统一的 `crewState` 状态对象驱动。

### 3.1 智能体成员工作区

成员工作区顶部三个 Tab：`动态 / Tasks / 配置`。

面包屑格式：`AICrew / 智能体成员 / 代码工程师`

#### 3.1.1 动态 Tab

动态是成员详情的默认页，回答"这个成员最近做了什么、做得怎么样、能不能追溯"。

```
┌─ AICrew / 智能体成员 / 代码工程师 ──────────────────────────┐
│ 代码工程师                          [动态] [Tasks] [配置]   │
├──────────────────────────────────────────────────────────┤
│ Hero 卡片                                                │
│ 💻 代码工程师                                              │
│ Claude · 本机 · 空闲                    ● 在线  [查看记录]  │
│                                                          │
│ 状态网格                                                  │
│ 20 近30天运行 │ 85% 成功率 │ 1m57s 平均耗时 │ 0/2 当前负载  │
│                                                          │
│ 7 天活动                                         趋势     │
│ █▅▇▃█▆▂                                                 │
│ 周一 周二 周三 周四 周五 周六 周日                           │
│                                                          │
│ 当前                                   无进行中的工作       │
│ 这个智能体当前空闲。                                       │
│                                                          │
│ 最近工作                                      [全部记录]   │
│ ✓ TES-12 任务执行间隔    49分钟前 · 7m18s · dev-story      │
│ ✓ TES-11 调研核心功能以及竞品 52分钟前 · 5m51s · research   │
│ ✓ TES-9  二级测试 issue   1小时前 · 1m01s · quick-dev      │
└──────────────────────────────────────────────────────────┘
```

动态页区块：

| 区块 | 内容 | 交互 |
|------|------|------|
| Hero 卡片 | 头像 + 成员名 + Runtime 摘要（`Claude · 本机 · 空闲`）+ 在线状态 pill + `查看记录` 按钮 | 点击 `查看记录` 打开完整记录列表 |
| 状态网格 | 四格：近 30 天运行次数 / 成功率 / 平均耗时 / 当前负载（`0 / 2`） | 点击成功率过滤 `status=success` |
| 7 天活动 | 柱状图展示最近 7 天运行分布，附 `趋势` pill | 只读 |
| 当前状态 | 正在执行的 `CrewRun`；无任务时显示空状态文案 | 有任务时点击进入运行详情 |
| 最近工作 | 最近 3 条执行记录，显示 `状态图标 + Focus 编号 + Task 标题 + 时间 + 耗时 + Skill` | 点击行打开运行记录详情；点击 `全部记录` 打开完整列表 |

#### 3.1.2 Tasks Tab

Tasks 展示与该成员关联的 Focus 任务，按状态分组（Multica 紧凑列表风格）。每行有 `data-focus-task-id`，点击行标题直接跳转到 Focus 看板并打开对应 Task 详情面板。

跳转行为：`openCrewTaskInFocus(taskId)` → 切换到 Focus 页 → 重置筛选为"全部"（确保卡片可见）→ 激活看板视图 → 定位 `[data-task-id]` 卡片 → 高亮闪烁 2s → 调用 `renderFocusTaskDetail(taskId)` 渲染完整详情（编号、标题、状态、描述、规划、Agent 执行卡、侧边栏元数据）→ 打开详情面板。详情数据来源于 `focusTaskDemoData` 对象（11 个 FP-* 任务的 mock 数据）。

```
┌─ 关联任务                     点击跳转 Focus Task 详情     ─┐
│                                                           │
│ ⏳ 进行中 (2)                                             │
│   FP-002  看板状态模型实现                                 │
│   FP-003  Agent Pull 执行管道                              │
│                                                           │
│ 📋 待办 (1)                                               │
│   FP-006  主题系统适配                                     │
│                                                           │
│ ✅ 已完成 (3)                                             │
│   FP-001  数据模型设计                                     │
│   FP-007  PRD 文档整合                                     │
│   FP-004  Terminal 手动执行模式                             │
└───────────────────────────────────────────────────────────┘
```

分组规则：

| 分组 | 含义 | 视觉 |
|------|------|------|
| ⏳ 进行中 | 正在执行的任务 | amber 状态点 + 计数 |
| 📋 待办 | 已分配待执行 | blue 状态点 + 计数 |
| 📝 待规划 | 尚未分配智能体 | dim 状态点 + 计数 |
| ✅ 已完成 | 执行完毕 | green 状态点 + 计数 |

每行列：编号（mono 字体）/ 标题。无独立跳转按钮，点击整行即跳转。

#### 3.1.3 配置 Tab

配置页采用子 Tab 切换，不再是卡片堆叠。6 个子 Tab：

`基础信息 / 指令 / Skill / MCP / 环境变量 / 自定义参数`

**基础信息**子 Tab：

| 字段 | 控件 | 说明 |
|------|------|------|
| 角色名 | input | 可编辑 |
| Runtime 绑定 | select | `Claude · MacBook-Pro-10.local` / `Codex · MacBook-Pro-10.local` / `Cursor · MacBook-Pro-10.local` |
| 模型 | select | `跟随 Runtime` / `claude-sonnet-4.5` / `claude-opus-4.6`；只有 Runtime 声明支持时才显示可选项 |
| 推理强度 | select | `跟随 Runtime` / `low` / `medium` / `high` |
| 并发上限 | select | 1 / 2 / 3 |
| 默认 Skill | select | `dev-story` / `quick-dev` / `code-review` |

自动保存，失败时保留本地草稿。

**指令**子 Tab：Instructions 文本域，成员长期指令，影响所有派发给该成员的任务。自动保存。

**Skill** 子 Tab：pill 列表展示已绑定 Skill（`dev-story` / `code-review` / `quick-dev` / `research`），`管理` 按钮进入添加/移除/优先级调整。

**MCP** 子 Tab：pill 列表展示 MCP Server 状态（绿色已连接 / amber 待授权），`管理` 按钮进入启用/停用/检测连接。

**环境变量**子 Tab：key-value 列表，secret value 默认 password 隐藏，`Reveal` 按钮显式显示。`+ 添加变量` 新增行。

**自定义参数**子 Tab：单行 input（mono 字体），提交前转换为 argv 数组，不做 shell 拼接。自动保存。

### 3.2 Runtime 工作区

Runtime 工作区为**单页滚动布局**（无顶部 Tab），依次展示：Hero 区 → 执行器表格 → 三列底部卡片 → 节点配置（子 Tab） → Daemon 日志。面包屑栏不显示分段控件。

面包屑格式：`AICrew / Runtime / MacBook-Pro-10.local`

#### 3.2.1 执行器区

执行器区是 Runtime 页面的主体。远程未连接节点显示空状态，本机节点显示完整详情。

**空状态实现**：执行器 / 配置 / 日志三个区域各自采用双 DOM 面板（`*-local` + `*-empty`），通过 `display` 切换，统一由 `setRuntimeHostAvailability(isLocal)` 函数管理。

**远程未连接空状态**：

```
┌─────────────────────────────────────────────────────┐
│                      🖥️                             │
│              remote-dev-01                           │
│                  未连接                               │
│                                                      │
│ 远程节点尚未建立连接。请在目标机器上                      │
│ 安装 FocusPilot Agent 并配置连接凭据。                  │
│                                                      │
│           [配置连接]  [安装指南]                        │
└─────────────────────────────────────────────────────┘
```

**本机详情**：

```
┌─ AICrew / Runtime / MacBook-Pro-10.local ──────────────────┐
│ MacBook-Pro-10.local                [执行器] [配置] [日志]   │
├─────────────────────────────────────────────────────────────┤
│ Hero 区域                                                   │
│ MacBook-Pro-10.local                                        │
│ 5 个运行时 · 5 个在线 · 全部空闲 · 0.3.11 · daemon 019e6da2 │
│ 本地 · 这台机器          [View logs] [Restart] [Stop]        │
│                                                             │
│ 执行器表格                                                   │
│ 执行器    健康度  智能体      工作负载  费用·7天  CLI     配置 │
│ ✳ Claude  在线    代码工程师  空闲      $0.20    0.3.11  [配置]│
│ ◎ Codex   在线    -           空闲      $0.13    0.3.11  [配置]│
│ ◆ Cursor  在线    -           空闲      -        0.3.11  [配置]│
│ ✦ Gemini  在线    -           空闲      -        0.3.11  [配置]│
│ ◉ Hermes  在线    -           空闲      -        0.3.11  [配置]│
│                                                             │
│ 三列底部卡片                                                 │
│ ┌─ Claude 配置 ──┐ ┌─ 最近运行 ────┐ ┌─ 最近日志 ────┐      │
│ │启动命令: claude │ │TES-12 7m18s  │ │daemon heartbeat│      │
│ │工作目录:当前Proj│ │TES-11 5m51s  │ │Claude config   │      │
│ │模型: 跟随 CLI  │ │TES-9  1m01s  │ │Codex registered│      │
│ │Env: 2 keys    │ │[查看全部]     │ │[View logs]     │      │
│ │MCP: fs,github │ │              │ │                │      │
│ └────────────────┘ └──────────────┘ └────────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

执行器表格列：

| 列 | 说明 |
|------|------|
| 执行器 | 图标 + 名称（Claude / Codex / Cursor / Gemini / Hermes） |
| 健康度 | 在线 pill（green） |
| 智能体 | 已绑定的成员名，未绑定显示 `-` |
| 工作负载 | 空闲 / 执行中 |
| 费用 · 7 天 | 最近 7 天 token 费用 |
| CLI | CLI 版本号（mono 字体） |
| 配置 | `配置` 按钮，打开执行器配置详情 |

三列底部卡片：

| 卡片 | 内容 |
|------|------|
| 执行器配置 | 启动命令、工作目录、模型策略、Env key count（`2 keys hidden`）、MCP 摘要（`filesystem, github`）。Secret 仍然 redacted |
| 最近运行 | 最近 3 条 CrewRun，显示 Task 标题 + 耗时 + 状态。`查看全部` 按钮 |
| 最近日志 | daemon / executor 摘要日志。`View logs` 按钮滚动到页面底部日志区 |

#### 3.2.2 节点配置区

页面内联展示（无独立 Tab），位于底部卡片下方，用 `line-soft` 分隔线和"节点配置"小标题标识。采用子 Tab 切换。4 个子 Tab：

`基础信息 / 执行器 / 环境变量 / 自定义参数`

**基础信息**子 Tab：

| 字段 | 控件 | 说明 |
|------|------|------|
| 机器名 | input readonly | `MacBook-Pro-10.local` |
| 类型 | input readonly | `本地 · 这台机器` |
| Daemon ID | input readonly (mono) | `019e6da2` |
| App 版本 | input readonly (mono) | `0.3.11` |

附在线状态 pill。

**执行器**子 Tab：检测配置信息——检测模式（自动 PATH 扫描 + 版本号）、检测频率（启动时 + 每 30 分钟）、已发现 CLI 数量。

**环境变量**子 Tab：全局级环境变量，key-value 列表，`Reveal` 显示 / `+ 添加变量` 新增。标记为"全局"pill。

**自定义参数**子 Tab：节点级参数，所有执行器共用。合并到每个执行器参数列表末尾。

#### 3.2.3 Daemon 日志区

页面内联展示（无独立 Tab），位于节点配置区下方。`刷新` 按钮手动刷新。Hero 区和底部卡片的 `View logs` 按钮滚动到此区域。

```
┌─ Daemon 日志 ─────────────────────────── [刷新] ─┐
│ daemon heartbeat          12s 前 · all executors idle   │
│ Claude config loaded      2m 前 · 2 env keys redacted   │
│ Codex registered          18m 前 · CLI 0.3.11           │
│ Gemini detected           20m 前 · /usr/local/bin/gemini │
│ Hermes detected           20m 前 · /usr/local/bin/hermes │
│ Cursor Agent detected     21m 前 · via cursor extension  │
│ daemon started            22m 前 · pid 41882 · macOS 15.2│
└─────────────────────────────────────────────────────────┘
```

### 3.3 运行记录详情

点击 `查看记录` 或最近工作中的记录行打开运行记录详情。详情可作为右侧抽屉或全屏页，但结构固定：

```
┌─ Multica Helper                         已完成 │ ✕ ─┐
│ Claude Code · Claude (MacBook-Pro-10.local) · 7m18s │
│ 69 次工具调用 / 145 个事件 / Focus TES-12 / Skill dev-story │
│ 时间顺序  最新在前  筛选  全部复制                       │
│ █▁▁▂▃▁▁▁▂▁▁▃▁▁▁▁▁▂▁▁▁▂▁▁▁▁▁▃▁▁▁▁▁▁▁▂▁▁▁▁▁▁▁▁█ │
│ Grep   server/internal/handler/issue.go:2644...      #130 │
│ Read   .../handler/issue.go                          #131 │
│ Agent  Let me check the daemon-side polling mechanism. #135 │
│ Bash   Post analysis comment to issue                 #141 │
└────────────────────────────────────────────────────────────┘
```

记录详情顶部展示成员名、运行状态、Runtime、Focus Task、Skill、工作目录、开始时间、耗时、工具调用数、事件数和配置快照入口。事件时间线支持按类型筛选：Agent / Bash / Read / Grep / MCP / Error / Status。

---

## 4. 核心交互

| 用户任务 | 操作路径 | 规则 |
|----------|----------|------|
| 查看成员详情 | 侧边栏点击成员 | 工作区切到该成员，默认动态 Tab |
| 新建智能体 | 侧边栏 `+ 新建智能体` 或模板行 | V1 可展示配置草稿；云端执行预留 |
| 修改基本信息 | 配置 Tab → 基础信息子 Tab | 自动保存，失败时保留本地草稿 |
| 绑定 Runtime | 配置 Tab → 基础信息 → Runtime 绑定 select | 支持本机和远程 Runtime 选择 |
| 覆盖模型/推理强度 | 配置 Tab → 基础信息 → 模型/推理强度 | 默认跟随 Runtime/CLI；只有 Runtime 声明支持时才显示可选项 |
| 配置 MCP Server | 配置 Tab → MCP 子 Tab | 待授权项显示 amber 状态，不静默失败 |
| 配置指令 | 配置 Tab → 指令子 Tab | Instructions 自动保存 |
| 配置 Skill | 配置 Tab → Skill 子 Tab → 管理 | 添加/移除/调整优先级 |
| 配置环境变量 | 配置 Tab → 环境变量子 Tab | Env secret 默认隐藏，Reveal 显示 |
| 配置自定义参数 | 配置 Tab → 自定义参数子 Tab | 提交前转 argv，不做 shell 拼接 |
| 查看 Tasks | Tasks Tab | 按状态分组，点击行跳转 Focus |
| 定位 Focus Task | Tasks Tab 点击 `→ Focus` | 切换到 Focus 页面，展开项目并选中对应节点 |
| 查看动态 | 动态 Tab | 默认视图，展示 Hero 卡片、状态网格、活动图、当前工作和最近工作 |
| 查看运行记录 | 动态页 `查看记录` 或最近工作行 | 打开运行记录详情，包含工具调用、事件、配置快照和原始日志 |
| 过滤成功记录 | 点击成功率 | 打开记录列表并默认过滤 `status=success` |
| 查看 Runtime 详情 | 侧边栏 Runtime 分段 → 点击机器 | 默认执行器 Tab |
| 查看 Runtime 配置 | Runtime 工作区 → 配置 Tab | 子 Tab 切换：基础信息/执行器/环境变量/自定义参数 |
| 查看 Daemon 日志 | Runtime 工作区 → 日志 Tab | 日志列表 + 刷新按钮 |
| 添加执行节点 | 侧边栏 Runtime 分段 → `+ 添加执行节点` | 远程电脑来自手动添加、历史连接或远程 daemon 心跳 |
| 删除成员 | 成员详情 `删除` | 系统成员需二次确认；有执行中任务时禁止删除 |

---

## 5. 状态与规则

### 5.1 统一状态管理

`crewState` 对象驱动侧边栏、面包屑、工作区 Tab、工作面板同步：

```javascript
crewState = {
  objectType: 'agent' | 'runtime',   // 当前选中的对象类型
  selectedAgentId: 'engineer',        // 当前选中的成员 ID
  selectedRuntimeHostId: 'macbook',   // 当前选中的 Runtime Host ID
  agentTab: 'crew-activity',          // 成员工作区当前 Tab
  runtimeTab: 'crew-runtime'          // Runtime 工作区当前 Tab
}
```

状态切换规则：

| 触发 | 状态变更 | 视觉联动 |
|------|----------|----------|
| 侧边栏点击成员 | `objectType='agent'`，`agentTab` 重置为 `crew-activity` | 面包屑更新、顶部 Tab 切为 `动态/Tasks/配置`、工作面板切换 |
| 侧边栏 Tab 切到 `智能体成员` | `objectType='agent'`，恢复上次选中的成员 | 同上 |
| 侧边栏点击 Runtime 机器 | `objectType='runtime'`，`runtimeTab` 重置为 `crew-runtime` | 面包屑更新、顶部 Tab 切为 `执行器/配置/日志`、工作面板切换 |
| 侧边栏 Tab 切到 `Runtime` | `objectType='runtime'`，自动选中列表第一台机器 | 同上 |
| 工作区 Tab 切换 | 更新 `agentTab` 或 `runtimeTab` | 工作面板切换，其他不变 |

面包屑格式：

- 成员模式：`AICrew / 智能体成员 / {成员名}`
- Runtime 模式：`AICrew / Runtime / {机器名}`

### 5.2 Runtime 健康状态

| 状态 | 含义 | UI 表达 |
|------|------|---------|
| `online` | 心跳正常，可接收任务 | 绿色在线点 |
| `recently_lost` | 最近丢失心跳，短时间内可能恢复 | amber 提示，不自动派新任务 |
| `offline` | 超过恢复窗口，视为不可用 | 红色不可用 |
| `about_to_gc` | 离线时间接近清理阈值 | amber 风险提示 |

Runtime 详情至少展示 Provider、运行模式、本机/云端、可见性、Owner、daemon id、CLI 版本、last seen、已绑定成员数。

### 5.3 成员可用性与负载

AICrew 不把"在线"和"忙"混成一个状态。成员状态拆成两轴：

| 状态 | 含义 | 用户可操作 |
|------|------|------------|
| `availability: online` | Runtime 与关键授权可用 | 可编辑、可分配 |
| `availability: unstable` | Runtime recently lost 或关键能力降级 | 可编辑；派发前提示风险 |
| `availability: offline` | Runtime 或必要授权不可用 | 可编辑配置；不可分配任务 |
| `workload: idle` | 当前无任务 | 可分配 |
| `workload: queued` | 有排队任务等待执行槽 | 可继续排队 |
| `workload: working` | 正在执行任务 | 可编辑非运行关键字段；不可删除 |
| `draft` | 新建未保存完整 | 不参与任务分配 |
| `archived` | 已归档成员 | 不展示在默认成员列表，可恢复 |

### 5.4 MCP 状态

| 状态 | 含义 |
|------|------|
| `connected` | 已连接且可调用 |
| `authorized` | 已授权，等待具体调用 |
| `local` | 本地能力，跟随应用权限 |
| `pending_auth` | 需要用户授权 |
| `disabled` | 未启用 |

### 5.5 常驻职责状态

| 状态 | 含义 |
|------|------|
| `enabled` | 已启用，会按触发规则进入调度 |
| `draft` | 规则未完整或尚未启用 |
| `paused` | 用户暂停，不进入调度 |
| `failed` | 最近一次执行失败，需要处理 |

### 5.6 Agent 配置规则

- Instructions：成员长期指令，影响所有派发给该成员的任务。
- Skills：从本地 Skill 注册表选择；成员可有多个技能，默认 Skill 只影响快速派发。
- Env：只展示 key 数和 key 名；secret value 必须通过 Reveal 动作显式显示，关闭页面后重新隐藏。
- Args：展示为参数行，提交前转换为 argv；不能用字符串拼接执行 shell。
- MCP JSON：只接受 JSON object；无权限查看 secret 时展示 `redacted` 状态，保存时不得覆盖不可见字段。

### 5.7 执行记录与配置快照规则

- 每次执行创建一个 `CrewRun`，运行结束后保留为历史记录。
- 每次执行开始时写入 `CrewRunConfigSnapshot`，包含动态 Task、Instructions、Skills、Env key、Args、MCP、Runtime、模型、推理强度和工作目录。
- 历史记录详情读取快照，不读取当前成员配置，避免后续配置修改污染历史解释。
- 最近工作默认展示 3 条（动态页），完整记录列表展示全部可检索历史。
- 成功率按用户选择的窗口计算，默认近 30 天：`success / (success + failed + cancelled)`；正在执行不进入分母。
- 失败数点击后过滤 `status=failed`；成功次数和成功率点击后过滤 `status=success`。
- 日志事件按顺序编号，支持折叠长 payload；原始 payload 存储为引用，列表只展示摘要。

### 5.8 本机与远程配置检测规则

- V1 只能自动检测本机所有可见配置，包括本机 Runtime、CLI 版本、daemon 心跳、可执行文件路径、工作目录摘要、Env key、Args 和本机 MCP 配置摘要。
- 远程电脑不由本机扫描磁盘；只展示远程 daemon 主动上报、用户手动添加、或历史连接留下的 Runtime 信息。
- 远程 Runtime 的 Env secret 与 MCP secret 永远不回传明文，只显示 key count、redacted 状态和授权状态。
- 云端 Runtime 在 V1 只保留分组和空状态，不提供真实执行。

### 5.9 V1 范围

V1 做：

- 预置 `代码工程师`
- 侧边栏 `智能体成员 / Runtime` 分段切换，标题区域无操作按钮
- 智能体成员分段：成员列表 + `+ 新建智能体` + 模板 + 运行概况
- Runtime 分段：本机/远程分组 + `+ 添加执行节点` + 检测范围
- 成员工作区三 Tab：动态 / Tasks / 配置
- 动态 Tab：Hero 卡片 + 状态网格 + 7 天活动柱状图 + 当前状态 + 最近工作
- Tasks Tab：按状态分组（进行中/待办/待规划/已完成），点击跳转 Focus
- 配置 Tab：子 Tab 切换（基础信息/指令/Skill/MCP/环境变量/自定义参数）
- Runtime 工作区三 Tab：执行器 / 配置 / 日志
- 执行器 Tab：Hero 区域 + 执行器表格 + 三列底部卡片（配置/最近运行/最近日志）
- 配置 Tab：子 Tab 切换（基础信息/执行器/环境变量/自定义参数）
- 日志 Tab：Daemon 日志列表
- 远程节点未连接空状态
- `crewState` 统一状态管理：侧边栏、面包屑、Tab、面板同步
- Runtime 健康状态、心跳和已绑定成员数展示
- 模型覆盖、推理强度覆盖、并发数配置
- MCP Server 列表、状态、授权提示
- 常驻职责编辑 UI
- 运行记录详情：事件时间线、工具调用、配置快照、复制和筛选
- Task / 最近工作 / 成功记录到 Focus 项目的定位跳转
- Focus / Studio 可引用 Crew 成员

V1 暂不做：

- 真正的多云端成员执行
- 默认展示多个真实成员；架构师、数据库工程师、数据分析师只作为新建模板出现
- 远程电脑磁盘扫描
- 云端 Runtime 真实执行
- Runtime daemon 自动发现与模型实时同步（本机已注册 daemon 状态可展示）
- Runtime CLI 升级、删除和 GC 流程
- 多 Agent 自动选择
- 常驻职责后台定时调度
- 自定义头像上传
- MCP 市场或公开插件管理

---

## 6. 数据对象

```yaml
CrewRuntime:
  id: "rt_claude_macbook"
  name: "Claude Code · MacBook"
  provider: "claude-code"
  runtime_mode: "local"       # local | cloud
  visibility: "private"       # private | public
  owner_id: "user_bruce"
  daemon_id: "fp-local-01"
  launch_header: "claude --model ..."
  cli_version: "2.1.121"
  health: "online"            # online | recently_lost | offline | about_to_gc
  last_seen_at: "2026-05-28T14:21:00+08:00"
  supported_models:
    - "claude-sonnet-4.5"
  supports_thinking: true

CrewMember:
  id: "crew_code_engineer"
  name: "代码工程师"
  avatar: "💻"
  visibility: "workspace"     # private | workspace
  owner_id: "user_bruce"
  runtime_id: "rt_claude_macbook"
  runtime_mode: "local"        # local | cloud
  availability: "online"       # online | unstable | offline
  workload: "idle"             # idle | queued | working
  status: "active"             # active | draft | archived
  concurrency_limit: 2
  model: "claude-sonnet-4.5"   # empty means follow runtime/CLI
  thinking_level: "medium"     # empty means follow runtime/CLI
  default_skill: "dev-story"
  skill_ids:
    - "dev-story"
    - "code-review"
  specialties:
    - "Swift/AppKit"
    - "前端原型"
    - "测试修复"
  instructions: "负责 FocusPilot 代码实现、测试修复和提交说明。"
  custom_args:
    - "--dangerously-skip-permissions"
    - "--model claude-sonnet-4.5"
  has_custom_env: true
  custom_env_key_count: 2
  mcp_config_redacted: false
  mcp_config:
    mcpServers:
      filesystem:
        command: "mcp-server-filesystem"

  mcp_servers:
    - id: "filesystem"
      state: "connected"
      permission_scope: "current_project"
    - id: "github"
      state: "authorized"
      permission_scope: "repo"
    - id: "browser"
      state: "pending_auth"
      permission_scope: "manual"

  duties:
    - id: "duty_pr_review"
      trigger_type: "event"  # event | cron | manual
      trigger_condition: "github.pull_request.opened"
      scope: "current_project"
      output_target: "studio.review_stream"
      state: "enabled"

CrewRuntimeHost:
  id: "host_macbook_pro_10"
  name: "MacBook-Pro-10.local"
  host_kind: "local"          # local | remote | cloud
  is_this_machine: true
  health: "online"
  daemon_id: "019e6da2"
  daemon_version: "0.3.11"
  last_seen_at: "2026-05-29T19:13:00+08:00"
  executors:
    - runtime_id: "rt_claude_macbook"
      provider: "claude-code"
      cli_version: "0.3.11"
      workload: "idle"
      bound_member_ids:
        - "crew_code_engineer"

CrewRun:
  id: "run_tes12_20260529_1913"
  crew_member_id: "crew_code_engineer"
  runtime_id: "rt_claude_macbook"
  runtime_host_id: "host_macbook_pro_10"
  focus_project_id: "project_focuspilot"
  focus_task_id: "TES-12"
  focus_task_title: "任务执行间隔"
  skill_id: "dev-story"
  status: "success"          # running | success | failed | cancelled
  started_at: "2026-05-29T19:13:00+08:00"
  ended_at: "2026-05-29T19:20:18+08:00"
  duration_seconds: 438
  tool_call_count: 69
  event_count: 145
  config_snapshot_id: "snap_run_tes12"
  log_path: "{projects_dir}/_logs/runs/run_tes12_20260529_1913.jsonl"
  output_refs:
    - kind: "focus_comment"
      ref: "TES-12#comment-145"

CrewRunConfigSnapshot:
  id: "snap_run_tes12"
  run_id: "run_tes12_20260529_1913"
  dynamic_task: "分析任务执行间隔并发布评论"
  instructions:
    member: "负责 FocusPilot 代码实现、测试修复和提交说明。"
    project: "遵守 CLAUDE.md"
    task: "定位 TES-12 并输出结论"
  skill_ids:
    - "dev-story"
  env_keys:
    - "ANTHROPIC_API_KEY"
  env_changes:
    - key: "FOCUSPILOT_PROJECT"
      change: "added"
  runtime:
    host_kind: "local"
    host_name: "MacBook-Pro-10.local"
    provider: "claude-code"
    cli_version: "0.3.11"
  mcp_servers:
    - id: "filesystem"
      state: "connected"
  cwd: "/Users/bruce/Workspace/2-Code/01-work/FocusPilot"
  model: "claude-sonnet-4.5"
  thinking_level: "medium"

CrewRunEvent:
  id: "event_0135"
  run_id: "run_tes12_20260529_1913"
  seq: 135
  timestamp: "2026-05-29T19:18:00+08:00"
  type: "agent"              # agent | tool_call | tool_result | read | grep | bash | mcp | error | status
  title: "Let me check the daemon-side polling mechanism."
  summary: "Agent 说明下一步检查 daemon 轮询机制"
  payload_ref: "{projects_dir}/_logs/runs/run_tes12_20260529_1913/0135.json"
```

---

## 7. 术语

| 术语 | 含义 |
|------|------|
| Crew 成员 | 一个面向用户的 AI 角色配置 |
| Runtime | 成员背后的执行环境，如本机 Claude Code daemon 或云端 Research runtime |
| Runtime 绑定 | 把 Crew 成员连接到某个可用 Runtime 的配置关系 |
| 执行器 | 一台机器上的具体 CLI 工具（Claude / Codex / Cursor / Gemini / Hermes），承载健康度、负载和费用 |
| Agent 配置 | Instructions、Skills、Env、Args、MCP 等影响成员执行行为的高级配置，通过配置 Tab 的子 Tab 管理 |
| MCP Server | 成员可调用的工具能力 |
| 常驻职责 | 按事件、时间或手动入口触发的自动任务 |
| 执行槽 | 成员当前可同时处理的任务容量 |
| CrewRun | 成员的一次执行记录，连接 Focus Task、Skill、Runtime、日志和配置快照 |
| 配置快照 | 某次运行开始时的实际配置副本，供历史记录追溯 |
| crewState | 统一状态对象，驱动侧边栏选中态、面包屑、工作区 Tab 和面板同步 |

---

*待定项：无。*
