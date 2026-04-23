# Studio 页面设计

> **状态**：设计中
> **更新**：2026-04-21
> **关联**：[03-workspace.md (Focus)](03-workspace.md)、[04-area-projects.md](04-area-projects.md)
> **参考**：[Z Code 竞品分析](../竞品分析/Z%20Code%20UI%20功能层次梳理.md)、[Codex 竞品分析](../竞品分析/Codex%20UI%20功能层次梳理.md)

---

## 1. 定位

Studio 是 FocusPilot 的**会话式 Agent 工作区**，负责项目 WorkDIR、Chat Session、代码/文档改动、终端和版本控制。

**V1 主体验 = Chat Session**。文件浏览、Git、终端是当前 WorkDIR 的辅助面板，不替代 AreaProjects 的项目资产管理。

与其他页面的职责边界：

| 页面 | 职责 |
|------|------|
| **Focus** | 计划和任务怎么推进（规划/看板/列表/Task 执行闭环） |
| **Studio** | 和 Agent 怎么工作（对话/编码/调试/Diff/终端） |
| **AreaProjects** | 资料和产物沉淀在哪里（文件管理/Markdown 编辑/长期资产） |

### Studio 📁 文件 Tab 与 AreaProjects 的硬规则

> Studio 文件 Tab 是当前 Session 的 WorkDIR 上下文选择器，只服务当前会话（添加到对话上下文、查看变更 Diff）。AreaProjects 是项目资产管理和长期沉淀页面（文件创建/编辑/组织/预览）。Studio 不做长期文件编辑和资产管理。

---

## 2. 页面布局

### 2.1 整体结构：侧边栏（顶部 Tab 条）+ 主区域

```
┌─ 侧边栏 260px ────┬─ 主区域 flex ─────────────────────────────────────┐
│                    │                                                    │
│ (🤖)  (📁)  (🌿)  │ ┌─ 顶栏 ──────────────────────────────────────┐   │
│ ━━━                │ │ 项目 · Agent · 模型 · 权限                   │   │
│                    │ │ [Resume] [Fork] [📋→Task] [转为 Task]       │   │
│ Tab 内容区          │ └────────────────────────────────────────────┘   │
│ 随顶部 Tab 切换     │                                                    │
│                    │ 对话流（内联 Diff + 审批 + 变更摘要）              │
│                    │                                                    │
│                    │ 输入框                                             │
│                    │                                                    │
│ [⚙ Studio 设置]   │ 终端（可折叠底部面板，⌘J 切换）                    │
└────────────────────┴────────────────────────────────────────────────────┘
```

### 2.2 侧边栏顶部 Tab 条

```
┌──────────────────────────────────────┐
│  ( 🤖 )   ( 📁 )   ( 🌿 )          │  ← 3 个图标 Tab
│   ━━━                                │     选中项下方指示线
└──────────────────────────────────────┘
```

### 2.3 三个 Tab 内容

#### 🤖 会话 Tab

```
[+ 新建会话] ⌘N

── 进行中 ──
● 调试看板拖拽  3m
  🤖 代码工程师
  📋→FP-002

● 研究 CAAnimation  15m
  🤖 代码工程师

── 今天 ──
✅ 测试 Agent Pull  1h
  🤖 代码工程师

── 昨天 ──
✅ 快速原型验证  30m
  ⚡ Codex

── 按 Agent ──
🤖 代码工程师 (3)
⚡ Codex     (1)

── 关联 ──
📋 已关联 Task (3)
💭 独立会话   (2)
```

#### 📁 文件 Tab

```
FocusPilot/
├── FocusPilot/
│   ├── App/
│   │   ├── AppDelegate.swift
│   │   └── ...
│   ├── Models/
│   │   ├── Models.swift ●       ← ● 已修改标记
│   │   └── ...
│   ├── Services/
│   └── ...
├── docs/
│   ├── fp-ui/
│   └── PRD.md
└── Makefile
```

操作：
- 右键文件 → "添加到对话上下文" / "在对话中引用(@)" / "查看 Diff"
- ● 标记表示当前 Session 中已修改的文件
- 不提供文件创建/编辑功能（长期编辑回 AreaProjects）

#### 🌿 Git Tab

```
Branch: main ▾
──────────────
变更文件 (3)
  ~ Models.swift
  ~ KanbanDataSource.swift
  + NewFile.swift

暂存区 (0)
──────────────
(空)

[Stage All] [Commit] [Push]

── 最近提交 ──
a319f37 docs(fp-ui): Workspace 完整设计
0e2d922 docs: 文档体系重组
```

---

## 3. 主区域

### 3.1 顶栏

```
┌────────────────────────────────────────────────────────────────┐
│ 📁 FocusPilot · 🤖 代码工程师 · claude-opus-4 · 🔒 逐步确认▾  │
│ 📋→FP-002 看板状态模型                [Resume] [Fork] [转为Task]│
└────────────────────────────────────────────────────────────────┘
```

| 元素 | 说明 |
|------|------|
| 📁 项目名 | 当前 WorkDIR 的项目名 |
| 🤖 Agent | 当前 Session 使用的 Agent，可点击切换 |
| 模型 | 当前模型，可点击切换 |
| 🔒 权限 | 审批策略（逐步确认/自动批准/仅请求时/全自动） |
| 📋→ | 关联的 Focus Task（点击跳转） |
| Resume | 恢复之前的 Session |
| Fork | 从当前 Session 分叉新 Session |
| 转为 Task | 将独立 Session 转为 Focus Task |

### 3.2 对话流

对话流是 Studio 的核心交互区，承载富内容：

```
👤 拖拽到 done 列时闪烁，看看什么原因

🤖 检查 KanbanDataSource.swift 的 animateRow 方法...
   发现缺少 completion handler，修复如下：

┌─ 内联 Diff ─── KanbanDataSource.swift ──────────────┐
│ L42  - animateRow(at: idx)                           │
│ L42  + animateRow(at: idx) {                         │
│ L43  +     self.tableView.reloadData()               │
│ L44  + }                                             │
│                          [✓ 应用]  [✗ 拒绝]  [✎ 编辑] │
└──────────────────────────────────────────────────────┘

🤖 同时建议优化动画时序...

┌─ 命令审批 ───────────────────────────────────────────┐
│ $ make build                                          │
│                                                       │
│ [✅ 允许]  [❌ 拒绝]  [⚡ 始终允许]                    │
└───────────────────────────────────────────────────────┘

🤖 编译通过 ✓

┌─ 变更摘要 ───────────────────────────────────────────┐
│ ~ KanbanDataSource.swift  +8 -2                       │
│ ~ QuickPanelView.swift    +3 -1                       │
│                                      [查看全部变更 ↓] │
└───────────────────────────────────────────────────────┘
```

#### 对话流内联元素

| 元素 | 展示 | 操作 |
|------|------|------|
| 文本消息 | 普通对话气泡 | — |
| 内联 Diff | 文件名 + 代码差异块，语法高亮 | [应用] [拒绝] [编辑] |
| 命令审批 | 命令内容 + 权限级别 | [允许] [拒绝] [始终允许] |
| 变更摘要 | 文件列表 + 增删行数 | [查看全部变更] → 侧边栏切到 🌿 |
| 编译/测试结果 | 状态图标 + 摘要 | 点击展开完整日志 |
| Task 卡片 | 关联的 Focus Task 小卡片 | 点击跳转 Focus |

### 3.3 输入框

```
┌──────────────────────────────────────────────────────┐
│ 描述内容...                                           │
│                                                       │
│ 📎 附件  @引用  𓊆技能  /命令              [发送 ↑]   │
└──────────────────────────────────────────────────────┘
```

### 3.4 底部面板（终端）

文件和 Git 已移到侧边栏，底部面板只保留终端。默认折叠，`⌘J` 切换。

```
┌─ 终端 ─────────────────────────────────── [▲ 展开] ──┐
│ $ make install                                        │
│ ✓ Build succeeded                                    │
│ ✓ Installed to /Applications                         │
└───────────────────────────────────────────────────────┘
```

---

## 4. 数据模型

### 4.1 CodeSession

```yaml
CodeSession:
  id: "session_abc"
  title: "调试看板拖拽问题"
  workdir: "/Users/bruce/.../FocusPilot"
  area_project_id: "ap_focuspilot"          # 关联的 AreaProject（nullable）
  linked_work_item_id: "FP-002"             # 关联的 Focus Task（nullable）
  is_primary: true                           # 是否为 Task 的主 Session
  source_type: focus_task                    # focus_task|area_project|local_path|adhoc
  fork_from_session_id: null                 # Fork 来源（nullable）

  initial_context:                           # 启动时的文件/目录上下文
    - { path: "/FocusPilot/Models/", kind: folder }
    - { path: "/FocusPilot/Services/KanbanDataSource.swift", kind: file }

  agent_id: "agent_coder"
  runtime: "claude-code"                     # Agent 使用的 runtime
  model: "default"                           # 中性默认值，实际由 Agent 配置决定
  sandbox_mode: workspace_write              # read_only|workspace_write|full_access
  approval_policy: on_request                # always_ask|on_request|never|full_auto

  status: active                             # active|idle|done|error|ended
  transcript_ref: "sessions/session_abc/transcript.jsonl"
  changed_artifacts: ["Models.swift", "KanbanDataSource.swift"]
  checkpoints: [...]

  created_at: "2026-04-21T10:00:00"
  last_active_at: "2026-04-21T10:30:00"
```

### 4.2 Session 与 Task 的关联规则

- 一个 WorkItem 默认只有一个 **primary CodeSession**
- Focus Task 手动模式优先打开 primary CodeSession；没有则创建
- Studio 可 fork 额外 Session，但不替换 primary，除非用户手动设为 primary
- 独立 Session（无关联 Task）可通过"转为 Task"创建 WorkItem

### 4.3 Session 来源

| source_type | 触发方式 | initial_context |
|-------------|---------|----------------|
| `focus_task` | Focus Task 详情页 → [💻 在 Studio 打开] | Task 的 plan.md + workdir |
| `area_project` | AreaProjects 右键 → [在 Studio 中打开] | 选中的项目/文件夹/文件 |
| `local_path` | Studio 内直接选择本地路径 | 指定路径 |
| `adhoc` | Studio 内 [+ 新建会话] 不选项目 | 无 |

---

## 5. 与其他页面的关联

### 5.1 Focus → Studio

```
Focus Task 详情页 → 手动模式

[🖐 内嵌对话]      ← Task 详情页内简化 Chat（快速处理）
[💻 在 Studio 打开] ← 跳转 Studio，打开 primary CodeSession
```

两者共享同一个 CodeSession，数据实时同步。

### 5.2 Studio → Focus

```
Session 顶栏 → 📋→FP-002    ← 点击跳转 Focus Task 详情页
Session → [转为 Task]        ← 创建 WorkItem（source=studio_session）
```

### 5.3 AreaProjects → Studio

```
文件/目录右键 →
  [在 Studio 中打开]          ← 跳转 Studio，WorkDIR=选中路径
  [添加到当前 Session 上下文]  ← 不跳转，追加到当前 Session 的 initial_context
  [创建 Focus Task]           ← 跳转 Focus 创建弹窗
```

---

## 6. V2 预留

- Resume / Fork 会话恢复和分叉（V1 可先只实现 Fork）
- 多 Runtime 切换（Claude Code / Codex / Gemini CLI）
- Sandbox 沙箱隔离执行
- Computer Use（macOS 桌面操控）
- Cloud Session（远程容器执行）
- Checkpoint 自动存档（逐轮对话快照）
