# Studio 页面设计

> **状态**：设计中
> **更新**：2026-04-23
> **参考**：[Z Code 竞品分析](../竞品分析/Z%20Code%20UI%20功能层次梳理.md)、[Codex 竞品分析](../竞品分析/Codex%20UI%20功能层次梳理.md)

---

## 1. 定位

Studio 是 FocusPilot 的**项目级 AI 工作区**。打开项目目录，选择 Runtime，和 AI 对话工作。

**V1 核心体验 = 对话**。侧边栏提供会话管理、文件浏览、Git 历史三个辅助面板，照搬 Z Code 的侧边栏模式。

### 与其他页面的职责边界

| 页面 | 职责 |
|------|------|
| **Focus** | 计划和任务怎么推进（规划/看板/列表/Task 执行闭环） |
| **Studio** | 打开项目，和 AI 对话工作（纯对话，不涉及任务管理） |
| **AreaProjects** | 项目资产管理和长期沉淀（文件编辑/组织/预览） |

Studio 和 Focus 相互独立，不做 Task 关联和双向跳转。

---

## 2. 页面布局

```
┌─ 侧边栏 260px ────┬─ 主区域 flex ─────────────────────────┐
│                    │                                        │
│ (🤖)  (📁)  (🌿)  │ ┌─ 顶栏 ───────────────────────────┐  │
│ ━━━                │ │ 📂 FocusPilot · ✳ Claude Code    │  │
│                    │ └───────────────────────────────────┘  │
│ Tab 内容区          │                                        │
│ 随 Tab 切换        │  对话区（纯聊天）                       │
│                    │                                        │
│ [⚙ Studio 设置]   │  输入框                                 │
└────────────────────┴────────────────────────────────────────┘
```

---

## 3. 侧边栏

### 3.1 顶部 Tab 条（照搬 Z Code）

```
┌──────────────────────────────────────┐
│  ( 🤖 )   ( 📁 )   ( 🌿 )          │
│   ━━━                                │
└──────────────────────────────────────┘
```

### 3.2 🤖 会话 Tab

按项目分组展示会话列表，支持置顶。

```
[+ 新建会话] ⌘N

── 📌 置顶 ──
📌 调试看板拖拽 · ✳ Claude Code · 3m

── FocusPilot ──
● 研究 CAAnimation · ✳ Claude Code · 15m
✅ 测试 Agent Pull · ⚡ Codex · 1h
✅ 快速原型验证 · ⚡ Codex · 30m

── PilotOne ──
● 方案评审 · ◆ Gemini · 5m

── multica ──
(无会话)
```

会话卡片信息：标题 · Runtime 图标 · 时长

右键操作：置顶 / 取消置顶 / 归档 / 删除

### 3.3 📁 文件 Tab

显示当前选中会话所属项目的文件树，纯浏览。

```
FocusPilot/
├── FocusPilot/
│   ├── App/
│   │   ├── FocusPilotApp.swift
│   │   ├── AppDelegate.swift
│   │   └── PermissionManager.swift
│   ├── Models/
│   ├── Services/
│   └── Helpers/
├── docs/
├── coder-bridge/
└── Makefile
```

点击文件可查看内容。不提供文件创建/编辑功能（长期编辑回 AreaProjects）。

### 3.4 🌿 Git Tab

显示当前项目的 Git 提交历史。

```
Branch: main

── 最近提交 ──
c7268bf docs(fp-ui): 全局替换评估为 evaluation
57f4b0a docs(fp-ui): 拆分 Focus + Studio
a319f37 docs(fp-ui): Workspace 完整设计
0e2d922 docs: 文档体系重组
e8e3921 docs: 更新 CLAUDE.md
```

---

## 4. 主区域

### 4.1 顶栏

```
┌────────────────────────────────────────────────────┐
│ 📂 FocusPilot · ✳ Claude Code · claude-opus-4      │
└────────────────────────────────────────────────────┘
```

显示当前项目名、Runtime、模型。Runtime 创建时选定，不可切换。

### 4.2 对话区

纯对话界面，和 Claude Code / Codex CLI 一样的聊天体验。

```
👤 帮我把 animateRow 的动画改成 0.2s ease-out

🤖 好的，我来修改 KanbanDataSource 中的动画参数...

   已修改:
   ~ KanbanDataSource.swift +3 -2

👤 编译一下

🤖 $ make build
   ✓ Build succeeded

👤 安装测试

🤖 $ make install
   ✓ Build succeeded
   ✓ Signing with FocusPilot Dev
   ✓ Installed to /Applications
```

### 4.3 输入框

```
┌──────────────────────────────────────────────┐
│ 描述内容...                       [发送 ↑]   │
└──────────────────────────────────────────────┘
```

---

## 5. 新建会话

点击 [+ 新建会话] 弹出创建弹窗。

### 5.1 项目来源

两种方式选择项目：
- **从电脑打开文件夹**：系统文件选择器，选本地路径
- **从 AreaProjects 选择**：弹出 AreaProjects 项目列表

### 5.2 Runtime 选择

创建时选定 Runtime，不可中途切换。同一个 Runtime 的 Skill、配置、上下文逻辑在整个会话中保持一致。如需切换 Runtime，新建会话。

### 5.3 创建弹窗

```
┌──── 新建会话 ────────────────────────────────┐
│                                               │
│  项目:                                        │
│  ┌───────────────────────────────────────┐   │
│  │ 最近项目                               │   │
│  │  📂 FocusPilot                        │   │
│  │  📂 PilotOne                          │   │
│  │  📂 multica                           │   │
│  │ ─────────────────────────             │   │
│  │  📁 从电脑打开文件夹...                │   │
│  │  📋 从 AreaProjects 选择...            │   │
│  └───────────────────────────────────────┘   │
│                                               │
│  Runtime:                                     │
│  (✳)           (⚡)           (◆)             │
│  Claude Code    Codex CLI     Gemini CLI      │
│  ━━━━━━━━                                     │
│  ⚠ 创建后不可更换                              │
│                                               │
│  会话标题: [                              ]   │
│  (可选，留空则自动从首条消息生成)               │
│                                               │
│                       [取消]  [创建]           │
└───────────────────────────────────────────────┘
```

---

## 6. 数据模型

### 6.1 CodeSession

```yaml
CodeSession:
  id: "session_abc"
  title: "调试看板拖拽问题"

  # 项目
  project_id: "proj_focuspilot"
  workdir: "/Users/bruce/.../FocusPilot"

  # Runtime（创建时选定，不可更改）
  runtime: claude_code               # claude_code | codex_cli | gemini_cli
  model: "claude-opus-4"             # 由 runtime 决定可选模型

  # 会话状态
  status: active                     # active | idle | done | ended
  pinned: false                      # 是否置顶
  fork_from_session_id: null         # Fork 来源（nullable）

  transcript_ref: "sessions/session_abc/transcript.jsonl"

  created_at: "2026-04-23T10:00:00"
  last_active_at: "2026-04-23T10:30:00"
```

### 6.2 Runtime

| Runtime | 图标 | 说明 |
|---------|------|------|
| `claude_code` | ✳ | Claude Code，Anthropic 模型 |
| `codex_cli` | ⚡ | Codex CLI，OpenAI 模型 |
| `gemini_cli` | ◆ | Gemini CLI，Google 模型 |

V2 可扩展更多 Runtime。

---

## 7. V2 预留

- Resume（恢复历史会话）
- Fork（从当前会话分叉新会话）
- Worktree 执行模式（Git worktree 隔离）
- 更多 Runtime 支持
