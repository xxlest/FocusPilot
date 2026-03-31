# FocusCC 产品需求文档（PRD）

> 版本：v1.0
> 日期：2026-03-04
> 状态：Draft

---

## 一、产品概述

### 1.1 产品定位

FocusCC 是一款 macOS 原生桌面应用，为使用 Claude Code（Max 订阅）的开发者提供**任务级别的 Agent 管理与监控能力**。

核心价值：**让 Claude Code 从"命令行对话工具"升级为"可管理的研发执行引擎"**。

### 1.2 目标用户

| 用户画像 | 特征 | 核心痛点 |
|---------|------|---------|
| 独立开发者 | 使用 Claude Code Max 订阅，日常开发 | 多任务切换靠终端窗口，无全局视野 |
| 小团队 Tech Lead | 管理 2-5 人团队，用 Claude Code 加速开发 | 无法追踪 Agent 执行状态和结果 |
| AI 重度用户 | 日均 20+ 次 Claude Code 交互 | Max 用量配额消耗无感知，经常触发限流 |

### 1.3 核心假设

1. Claude Code Max 用户需要 GUI 化的任务管理（待验证）
2. 实时状态监控能提升开发效率和信心（待验证）
3. macOS 原生悬浮球入口有足够的使用频次（基于 PinTop 经验已部分验证）

### 1.4 非目标

- ❌ 不替代 IDE（Cursor/VS Code）的代码编辑能力
- ❌ 不做通用项目管理工具（不做 Linear/Jira 替代品）
- ❌ 不做跨平台（MVP 仅 macOS）
- ❌ 不做 API Key 中转或代理计费
- ❌ 不做 Claude Code 以外的 Agent 支持（MVP 阶段）

---

## 二、用户场景

### 场景 1：单任务派发与监控

> 开发者在写代码时，想让 Claude Code 帮忙重构一个模块。
> 他在悬浮球面板中快速输入任务描述，点击"执行"。
> 悬浮球变为蓝色旋转动画，表示 Agent 正在工作。
> hover 面板实时显示 Agent 正在调用的工具（Reading files... → Editing code...）。
> 任务完成后悬浮球变绿，面板显示修改了哪些文件的摘要。

### 场景 2：多任务并行

> Tech Lead 拆解了一个功能为 3 个子任务，分别指派给 3 个 Claude Code 会话。
> 主看板以 Kanban 视图展示 3 个任务的实时状态。
> 其中一个任务遇到错误暂停了，面板标红并展示错误信息。
> Lead 查看错误详情，手动修改 prompt 后重新派发。

### 场景 3：配额感知

> 开发者今天已经用了不少 Claude Code，不确定还剩多少配额。
> 悬浮球右上角有一个小指示器，颜色从绿→黄→红反映今日配额消耗进度。
> 点开面板可以看到近 5 小时的请求数和 token 估算。

### 场景 4：任务模板复用

> 开发者经常需要做代码审查。他预设了一个"Code Review"模板：
> prompt = "审查 {target_path} 中的代码质量，检查安全漏洞和性能问题"
> 每次只需选择目标路径，一键派发。

---

## 三、功能需求

### 3.1 功能总览

```
MVP (Phase 1)              增强 (Phase 2)            高级 (Phase 3)
───────────────────────    ──────────────────────    ──────────────────
[P0] 悬浮球状态入口        [P1] 任务看板 Kanban       [P2] 任务 DAG 可视化
[P0] 单任务派发            [P1] 多任务并行(≤5)        [P2] 任务模板市场
[P0] 实时状态流展示        [P1] 配额消耗监控          [P2] Agent Teams 管理
[P0] 任务结果摘要          [P1] 执行日志浏览          [P2] 外部系统桥接
[P0] 基础设置              [P1] 任务历史与搜索        [P2] 多 Agent 支持
```

### 3.2 P0 功能详细规格

#### F01：悬浮球状态入口

**复用 PinTop 悬浮球架构**，改造状态映射逻辑。

| 属性 | 规格 |
|------|------|
| 外观 | 毛玻璃圆球，直径 40pt |
| 层级 | NSPanel, statusWindow+100 |
| 状态颜色 | 见下方状态映射表 |
| 交互 | hover 弹出快捷面板，单击展开/收起，双击打开主看板 |
| 拖拽 | 支持拖拽吸附屏幕边缘，贴边半隐藏 |

**悬浮球颜色 → Agent 状态映射**：

| 颜色 | 状态 | 动画 |
|------|------|------|
| 灰色 | 空闲（无活跃任务） | 无 |
| 蓝色 | 执行中（Agent 正在工作） | 呼吸动画 |
| 青色 | 思考中（Agent 正在推理/规划） | 慢速脉冲 |
| 橙色 | 等待确认（Agent 需要用户输入） | 快速闪烁 |
| 绿色 | 已完成（最近任务成功） | 静态 3 秒后回灰 |
| 红色 | 错误（最近任务失败） | 静态直到用户查看 |

#### F02：快捷面板

**复用 PinTop 快捷面板架构**，重新设计内容区。

| 属性 | 规格 |
|------|------|
| 层级 | NSPanel, statusWindow+50 |
| 展开方式 | 从悬浮球中心弹出（复用 PinTop 动画） |
| 固定宽度 | 320pt |
| 最大高度 | 屏幕高度 60% |

**面板内容结构**：

```
┌──────────────────────────┐
│ 🟢 FocusCC        [⚙️]  │  ← 标题栏 + 设置按钮
├──────────────────────────┤
│ 📝 快速任务              │  ← 输入区
│ ┌──────────────────────┐ │
│ │ 输入任务描述...       │ │  ← 文本框（支持多行）
│ └──────────────────────┘ │
│ [项目: ~/myproject ▼]    │  ← 工作目录选择
│ [模型: sonnet ▼] [执行▶] │  ← 模型选择 + 执行按钮
├──────────────────────────┤
│ 活跃任务                  │  ← 任务列表区
│ ┌──────────────────────┐ │
│ │ 🔵 重构登录模块       │ │  ← 任务卡片
│ │ Reading auth.ts...    │ │  ← 当前工具调用
│ │ ██████░░░░ 62%       │ │  ← 进度指示
│ │ 3m 12s | ⏸ ⏹         │ │  ← 时长 + 控制按钮
│ └──────────────────────┘ │
│ ┌──────────────────────┐ │
│ │ ✅ 修复 CSS 布局      │ │  ← 已完成任务
│ │ 完成 · 2 files changed│ │
│ └──────────────────────┘ │
├──────────────────────────┤
│ 今日: 23 次请求 · ~45K tok│  ← 配额概览
└──────────────────────────┘
```

#### F03：任务派发

| 属性 | 规格 |
|------|------|
| 输入 | 任务描述（文本/Markdown），1-5000 字符 |
| 工作目录 | 下拉选择，默认最近使用的目录，支持手动浏览 |
| 模型选择 | sonnet（默认）/ opus / haiku |
| 权限模式 | 下拉选择：default / acceptEdits / plan |
| 工具白名单 | 可选，默认全部启用 |
| 执行方式 | spawn `claude -p "..." --output-format stream-json -C {dir}` |

**派发流程**：

```
用户输入任务描述
  → 校验（非空、目录存在）
  → 创建 Task 记录（status: queued）
  → spawn claude 子进程
  → 任务状态 → dispatched → running
  → 实时解析 stream-json 事件
  → 更新 UI 状态
  → 进程退出 → completed / failed
```

#### F04：实时状态流展示

**stream-json 事件解析规格**：

| 事件类型 | UI 映射 |
|---------|---------|
| `content_block_start (type: text)` | 显示"Agent 正在思考..." |
| `content_block_delta (type: text_delta)` | 实时显示思考文本片段 |
| `content_block_start (type: tool_use)` | 显示工具名称（如"Reading files..."） |
| `content_block_delta (type: input_json_delta)` | 解析工具参数（如文件路径） |
| `content_block_stop` | 工具调用完成标记 |
| `message_delta (stop_reason: end_turn)` | 任务完成 |
| `message_delta (stop_reason: tool_use)` | Agent 继续下一步 |
| `AssistantMessage` | 提取 usage 统计，更新 token 计数 |

**状态机**：

```
Init
  ↓ (进程启动)
Connecting
  ↓ (首个事件到达)
Running
  ├── Thinking   (text content block)
  ├── ToolCalling (tool_use content block)
  │     └── tool 名称 + 参数摘要
  └── Responding  (最终 text block)
  ↓ (进程退出 code=0)
Completed
  ↓ (进程退出 code≠0)
Failed (含错误信息)

特殊状态：
  Running → Paused (用户手动暂停 → kill -STOP)
  Paused → Running (用户恢复 → kill -CONT)
  Any → Cancelled (用户终止 → kill -TERM)
```

#### F05：任务结果摘要

| 属性 | 规格 |
|------|------|
| 文件变更列表 | 从 tool_use (Write/Edit) 事件中提取修改的文件路径 |
| 变更统计 | N files changed, N insertions, N deletions |
| Agent 回复摘要 | 最后一个 text content block 的内容 |
| 执行时长 | 从 dispatch 到完成的时间 |
| Token 统计 | input_tokens + output_tokens |

#### F06：基础设置

| 设置项 | 类型 | 默认值 |
|--------|------|--------|
| Claude CLI 路径 | 文本 | 自动检测（`which claude`） |
| 默认工作目录 | 路径选择器 | ~/ |
| 默认模型 | 下拉 | sonnet |
| 默认权限模式 | 下拉 | default |
| 悬浮球显示 | 开关 | 开 |
| 开机自启 | 开关 | 关 |
| 全局快捷键 | 快捷键录制 | ⌘⇧F |

### 3.3 P1 功能概要

#### F07：任务看板（Kanban）

- 三列视图：待办 / 执行中 / 已完成
- 支持拖拽排序
- 任务卡片点击展开详情
- 筛选：按项目、按状态、按日期

#### F08：多任务并行

- 同时运行最多 5 个 Claude Code 会话
- 并行任务有独立的进度显示
- 限流检测：当 Claude Code 返回 rate limit 错误时，自动排队等待
- Max 配额感知：5 小时滚动窗口内的请求数追踪

#### F09：配额消耗监控

- 统计维度：按 5 小时窗口 / 日 / 周 / 月
- 可视化：柱状图展示每日请求数和估算 token 量
- 预警：接近 Max 配额上限时悬浮球变黄

#### F10：执行日志

- 完整的 stream-json 原始事件日志
- 格式化展示：工具调用 → 参数 → 结果
- 支持搜索和过滤
- 导出为 Markdown

#### F11：任务历史

- 所有已完成/失败任务的记录
- 按项目/日期/状态筛选
- 支持从历史任务"重新执行"
- 持久化存储（SQLite 或 JSON 文件）

### 3.4 P2 功能概要（远期）

| 功能 | 描述 |
|------|------|
| 任务 DAG 可视化 | 任务间依赖关系的有向图展示 |
| 任务模板库 | 预设和自定义任务模板，一键复用 |
| Agent Teams 管理 | 可视化展示 Claude Code Agent Teams 的协作状态 |
| GitHub Issues 桥接 | 从 Issue 创建任务，完成后自动更新 Issue 状态 |
| 多 Agent 支持 | 支持 Codex / Gemini Code 等其他 AI Agent |
| 通知系统 | 任务完成/失败时推送 macOS 通知 |

---

## 四、交互设计

### 4.1 三层交互架构（复用 PinTop 模式）

```
层级 1: 悬浮球（常驻入口）
  ↓ hover / 单击
层级 2: 快捷面板（任务概览 + 快速操作）
  ↓ 双击 / 面板内按钮
层级 3: 主看板（完整管理界面）
```

### 4.2 主看板布局

```
┌─────────────────────────────────────────────────────┐
│  FocusCC                              [_] [□] [×]   │
├──────────┬──────────────────────────────────────────┤
│          │                                          │
│  📋 任务  │         任务看板 / 仪表盘 / 设置          │
│          │                                          │
│  📊 监控  │  ┌──────────┬──────────┬──────────┐    │
│          │  │ 待办 (3)  │ 执行中(2)│ 完成 (8) │    │
│  📝 日志  │  │          │          │          │    │
│          │  │ ┌──────┐ │ ┌──────┐ │ ┌──────┐ │    │
│  ⚙️ 设置  │  │ │Task 1│ │ │Task 4│ │ │Task 6│ │    │
│          │  │ └──────┘ │ │ 🔵62% │ │ │ ✅   │ │    │
│          │  │ ┌──────┐ │ └──────┘ │ └──────┘ │    │
│          │  │ │Task 2│ │ ┌──────┐ │ ┌──────┐ │    │
│          │  │ └──────┘ │ │Task 5│ │ │Task 7│ │    │
│          │  │ ┌──────┐ │ │ 🔵38% │ │ │ ✅   │ │    │
│          │  │ │Task 3│ │ └──────┘ │ └──────┘ │    │
│          │  │ └──────┘ │          │          │    │
│          │  └──────────┴──────────┴──────────┘    │
│          │                                          │
│          │  ── 执行详情 ──────────────────────────   │
│          │  Task 4: 重构登录模块                      │
│          │  状态: Running · Reading auth.ts          │
│          │  时长: 3m 12s · Token: 12,340             │
│          │  日志: [展开]                              │
├──────────┴──────────────────────────────────────────┤
│  今日: 23 请求 · ~45K token · 配额: ████░░ 62%      │
└─────────────────────────────────────────────────────┘
```

### 4.3 关键交互流

#### 快速任务派发流（最短路径）

```
悬浮球 hover → 面板弹出 → 输入任务 → 按 ⌘+Enter 执行
                                         ↓
                              悬浮球变蓝 + 面板显示进度
                                         ↓
                              完成后悬浮球变绿 + 通知
```

#### 任务管理流（完整路径）

```
主看板 → 新建任务 → 填写描述/选目录/选模型 → 加入待办
  → 拖入"执行中"列（或点击执行按钮） → Agent 开始工作
  → 实时查看执行详情 → 完成后查看结果摘要 → 归档
```

---

## 五、技术约束

### 5.1 Claude Code CLI 调用规格

**基础调用命令**：

```bash
claude -p "{task_prompt}" \
  --output-format stream-json \
  --verbose \
  -C {project_path} \
  --model {model_name} \
  --permission-mode {mode}
```

**可选参数**：

```bash
--allowedTools "Read,Write,Edit,Bash,Grep,Glob"  # 工具白名单
--max-turns 50                                     # 最大轮次
```

### 5.2 stream-json 事件解析

每行一个 JSON 对象（NDJSON 格式），需逐行读取和解析：

```swift
// Swift 伪代码
pipe.fileHandleForReading.readabilityHandler = { handle in
    let data = handle.availableData
    guard !data.isEmpty else { return }

    let lines = String(data: data, encoding: .utf8)?
        .components(separatedBy: "\n")
        .filter { !$0.isEmpty }

    for line in lines ?? [] {
        if let jsonData = line.data(using: .utf8),
           let event = try? JSONDecoder().decode(StreamEvent.self, from: jsonData) {
            DispatchQueue.main.async {
                self.handleStreamEvent(event)
            }
        }
    }
}
```

### 5.3 Max 计划限制

| 限制 | 说明 | FocusCC 应对 |
|------|------|-------------|
| 5 小时滚动窗口 | 用量在 5 小时窗口内有上限 | 追踪窗口内请求数，接近上限时提醒 |
| 每周总额限制 | Max 20x 有每周总用量上限 | 周维度统计展示 |
| 共享用量池 | Claude Code 与 claude.ai 共享配额 | 提醒用户注意分配 |
| 无精确 API | Max 计划无法通过 API 查询剩余配额 | 本地估算（累计请求数 + 估算 token） |

### 5.4 进程管理约束

| 约束 | 说明 |
|------|------|
| 并行上限 | 建议 ≤5 个子进程（内存约 2-3GB） |
| 进程隔离 | 每个任务独立 claude 进程，独立 cwd |
| 进程生命周期 | 正常退出 code=0，异常退出 code≠0 |
| 暂停/恢复 | SIGSTOP / SIGCONT（系统级暂停） |
| 终止 | SIGTERM → 等 5s → SIGKILL |
| 僵尸进程 | 必须 waitpid 回收 |

### 5.5 数据持久化

| 数据 | 存储方式 | 位置 |
|------|---------|------|
| 任务记录 | JSON 文件 | ~/Library/Application Support/FocusCC/tasks/ |
| 设置 | UserDefaults | com.focuscopilot.FocusCC |
| 执行日志 | 按任务 ID 的日志文件 | ~/Library/Application Support/FocusCC/logs/ |
| 任务模板 | JSON 文件 | ~/Library/Application Support/FocusCC/templates/ |

---

## 六、数据模型

### 6.1 Task（任务）

```swift
struct Task: Codable, Identifiable {
    let id: UUID
    var title: String                    // 任务标题
    var prompt: String                   // 发送给 Claude Code 的 prompt
    var projectPath: String              // 工作目录
    var model: String                    // sonnet / opus / haiku
    var permissionMode: String           // default / acceptEdits / plan
    var allowedTools: [String]?          // 工具白名单
    var status: TaskStatus               // 状态
    var createdAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var result: TaskResult?              // 执行结果
    var sessionLog: [StreamEvent]?       // 原始事件日志
}

enum TaskStatus: String, Codable {
    case draft       // 草稿
    case pending     // 待执行
    case queued      // 排队中（等待限流释放）
    case running     // 执行中
    case paused      // 已暂停
    case completed   // 已完成
    case failed      // 失败
    case cancelled   // 已取消
}

struct TaskResult: Codable {
    var summary: String                  // Agent 最终回复
    var filesChanged: [FileChange]       // 文件变更列表
    var inputTokens: Int                 // 输入 token 数
    var outputTokens: Int                // 输出 token 数
    var duration: TimeInterval           // 执行时长
    var toolCalls: [ToolCallRecord]      // 工具调用记录
    var exitCode: Int                    // 进程退出码
}

struct FileChange: Codable {
    var filePath: String
    var action: String                   // write / edit
}

struct ToolCallRecord: Codable {
    var toolName: String                 // Read / Write / Edit / Bash ...
    var input: String                    // 工具输入摘要
    var timestamp: Date
}
```

### 6.2 StreamEvent（事件）

```swift
struct StreamEvent: Codable {
    var type: String                     // "stream_event" / "assistant" / "result"
    var event: EventData?                // 原始 Claude API 事件
    var uuid: String?
    var sessionId: String?
}

struct EventData: Codable {
    var type: String                     // message_start / content_block_start / ...
    var delta: DeltaData?
    var contentBlock: ContentBlock?
    var message: MessageData?
}
```

---

## 七、成功指标

### MVP 阶段

| 指标 | 目标 |
|------|------|
| 任务派发成功率 | ≥ 95% |
| 状态流延迟 | < 500ms（从 Claude 输出到 UI 展示） |
| 内存占用 | < 100MB（空闲时） |
| 崩溃率 | < 1%（每 100 次操作） |

### 产品验证

| 指标 | 目标 |
|------|------|
| 日活跃用户 | MVP 内测 10+ 人 |
| 日均任务派发数 | 每用户 5+ 次 |
| 用户留存 | 7 日留存 > 50% |
| NPS | > 30 |

---

## 八、里程碑计划

| 阶段 | 时间 | 交付物 |
|------|------|--------|
| M0: 技术原型 | 第 1-2 周 | stream-json 解析 + 进程管理的最小验证 |
| M1: MVP | 第 3-6 周 | P0 全部功能，可日常使用 |
| M2: 增强版 | 第 7-10 周 | P1 功能（多任务、监控、日志） |
| M3: 高级版 | 第 11-18 周 | P2 功能（DAG、模板、桥接） |

---

## 九、风险与缓解

| 风险 | 级别 | 缓解措施 |
|------|------|---------|
| Claude Code CLI 接口变更 | 高 | 抽象 adapter 层，CI 自动兼容性测试 |
| Max 配额无 API 查询接口 | 中 | 本地估算 + 提示用户去 claude.ai 查看 |
| 多进程内存消耗大 | 中 | 限制并行数，完成后及时回收 |
| 用户不知道 FocusCC 存在 | 中 | 利用 PinTop 用户群推广 |
| Anthropic 推出官方 GUI | 高 | 差异化（macOS 原生、轻量、中文市场） |

---

## 十、附录

### A. 与 PinTop 的代码复用清单

| PinTop 模块 | FocusCC 复用方式 |
|-------------|-----------------|
| FloatingBallWindow/View | 直接复用，改造颜色映射逻辑 |
| QuickPanelWindow | 直接复用框架，重写内容区 |
| MainKanbanWindow | 复用窗口管理，重写 SwiftUI 视图 |
| AppDelegate | 复用生命周期管理模式 |
| Constants | 新建 FocusCC 常量文件 |
| ConfigStore | 复用 UserDefaults 模式 |
| HotkeyManager | 复用 Carbon 快捷键注册 |
| PermissionManager | 复用辅助功能权限检测 |

### B. Claude Code CLI 参数速查

```bash
# 基础执行
claude -p "prompt" --output-format stream-json -C /path/to/project

# 模型选择
--model claude-sonnet-4-6  # 或 claude-opus-4-6 / claude-haiku-4-5

# 权限控制
--permission-mode default|acceptEdits|plan

# 工具限制
--allowedTools "Read,Write,Edit,Bash,Grep,Glob"

# 输出控制
--output-format text|json|stream-json
--verbose  # 启用详细输出（stream-json 时建议开启）

# 会话管理
--resume SESSION_ID  # 恢复会话
```
