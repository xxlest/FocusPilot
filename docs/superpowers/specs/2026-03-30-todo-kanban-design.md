# AI Tab 任务看板设计文档

> 日期：2026-03-30
> 版本：V4.2（基于 V4.1 AI Tab 扩展）

## 概述

在快捷面板 AI Tab 的项目文件夹下新增「任务看板」功能。以项目根目录的 `todo.md` 文件为唯一数据源，在面板中展示任务列表，支持状态流转、复制到 AI 执行器、删除条目。任务的新增和编辑在编辑器中完成。

## todo.md 文件格式

存储位置：项目工作目录根目录（即 session 的 `cwd`），如 `~/Workspace/FocusPilot/todo.md`。

采用看板列式 Markdown 格式，与 Obsidian Kanban 插件兼容：

```markdown
## Todo
- [ ] 实现用户登录模块
  需要支持 OAuth2 和本地账号两种方式，
  登录状态持久化到 Keychain

- [ ] 添加快捷键配置

## In Progress
- [ ] 重构 WindowService 刷新逻辑
  拆分两阶段刷新为独立方法，
  添加 titleCache 失效策略，
  更新 buildAXTitleMap 错误处理

## Done
- [x] 修复面板闪烁 bug
- [x] 设计数据模型
```

### 解析规则

- `## Todo` / `## In Progress` / `## Done`：三个看板列，决定任务状态
- `- [ ]` 或 `- [x]` 开头的行：任务标题行
- 标题行之后紧接的缩进行（2 空格或更多）：任务内容块
- 空行分隔任务条目
- 文件不存在时，该项目的任务折叠行不显示

## 面板 UI 设计

### 层级结构

```
AI Tab
├── 📁 项目文件夹 A（可展开/折叠）
│   ├── 📋 任务 (2/5) ✎           ← 任务折叠区（新增）
│   │   ├── ● 实现用户登录模块  ▶ ✕   ← 任务条目（展开后）
│   │   ├── ● 添加快捷键配置    ▶ ✕
│   │   ├── ● 重构 WindowService ▶ ✕
│   │   └── ▶ ✓ 2 项已完成          ← Done 折叠区
│   ├── ── 分隔线 ──
│   ├── ● Claude · a1b2c3d4  执行中  ← AI Session（已有）
│   └── ● Claude · e5f6g7h8  等待输入
└── 📁 项目文件夹 B
    └── ...
```

### 任务折叠区

- 位置：项目文件夹展开后的第一个子区域，在 Session 列表之上
- 折叠行：`▶ 📋 任务  2/5  ✎`
  - 左侧 chevron 指示折叠/展开
  - 📋 图标 + "任务" 标签
  - `2/5` 进度摘要（已完成/总数）
  - ✎ 按钮：在编辑器中打开 todo.md
- 缩进：28px（与 Session 行同级，在 `Constants.Panel.windowIndent`）
- 无 todo.md 文件时：整个折叠区不显示，不占空间
- 默认状态：折叠

### 任务条目行

单行布局，280px 面板内：

```
[色点●] [标题文字...截断] [▶执行] [✕删除]
```

- **色点**（左侧 10px）：可点击，循环切换状态
  - 🟡 `.systemYellow`：Todo
  - 🟢 `.systemGreen`：In Progress
  - ⚫ `nsTextTertiary`：Done
  - hover 时放大到 12px + 手形光标，暗示可点击
- **标题文字**：flex:1，单行截断（ellipsis）
- **▶ 执行按钮**（右侧 9px）：常驻，低透明度 0.35，hover 时 1.0
- **✕ 删除按钮**（右侧 9px）：常驻，低透明度 0.35，hover 时 1.0
- 缩进：44px（比折叠行多一级）
- 行高：与 session 窗口行一致（`Constants.Panel.windowRowHeight` = 24px）

### Done 区折叠

- 默认折叠为一行：`▶ ✓ N 项已完成`
- 字号 11px，颜色 `nsTextTertiary`
- 点击展开显示 Done 条目列表
- Done 条目样式：灰色色点 + 删除线 + 半透明（opacity 0.5）
- Done 条目只保留 ✕ 删除按钮（无 ▶ 执行按钮）

### 与 Session 列表的分隔

- 任务区和 Session 区之间用 1px 分隔线隔开
- 分隔线颜色使用 `nsSeparator`（适配浅色/深色主题），左右 margin 与 windowIndent 对齐

## 交互逻辑

### 状态流转（点击色点）

Todo → In Progress → Done → Todo 三态循环。

写回 todo.md 的操作：
1. 从文件重新读取（确保最新）
2. 将该任务条目（标题行 + 内容行）从原看板列移除
3. 追加到目标看板列末尾
4. 如果是移到 Done：将 `- [ ]` 改为 `- [x]`
5. 如果是从 Done 移出：将 `- [x]` 改为 `- [ ]`
6. 写回文件
7. 重新解析刷新面板

### 复制到 AI 执行（点击 ▶）

1. 确定复制内容：
   - 有内容块（缩进行）：复制内容块
   - 无内容块：复制标题
2. 写入系统剪贴板（`NSPasteboard.general`）
3. 智能窗口切换：
   - 查找该项目下所有 active 的 AI session
   - 单个 session：直接切换到其宿主窗口
   - 多个 session：弹出选择菜单，用户选择后切换
   - 无 session：仅复制，不切换

### 删除条目（点击 ✕）

1. 从文件重新读取
2. 移除该条目的标题行和所有缩进内容行
3. 写回文件
4. 重新解析刷新面板

### 在编辑器中打开（点击 ✎）

复用现有的窗口切换机制，打开 todo.md 所在项目的编辑器窗口。如果没有关联的编辑器窗口，调用 `NSWorkspace.shared.open(fileURL)` 用默认编辑器打开。

## 数据模型

### TodoItem

```swift
struct TodoItem {
    let title: String           // 任务标题（- [ ] 后的文字）
    let content: String?        // 任务内容（缩进块文字，nil 表示无内容）
    let status: TodoStatus      // todo / inProgress / done
    let lineRange: Range<Int>   // 在文件中的起止行号（标题行到最后一行内容行）
}
```

### TodoStatus

```swift
enum TodoStatus {
    case todo           // ## Todo 区
    case inProgress     // ## In Progress 区
    case done           // ## Done 区

    var dotColor: NSColor   // 🟡 / 🟢 / ⚫
    var next: TodoStatus    // 循环：todo → inProgress → done → todo
}
```

### TodoFile

```swift
struct TodoFile {
    let items: [TodoItem]       // 所有任务条目
    let path: String            // todo.md 文件路径

    var todoCount: Int          // Todo 区任务数
    var inProgressCount: Int    // In Progress 区任务数
    var doneCount: Int          // Done 区任务数
    var activeCount: Int        // todoCount + inProgressCount
    var totalCount: Int         // 所有任务数
}
```

## 架构

### 新增文件

- `FocusPilot/Services/TodoService.swift`：独立单例，管理 todo.md 解析和写回

### 修改文件

- `FocusPilot/QuickPanel/QuickPanelView.swift`：AI Tab 内容构建，新增任务折叠区渲染
- `FocusPilot/QuickPanel/QuickPanelRowBuilder.swift`：新增 `createTodoFoldRow()` + `createTodoItemRow()` + `createDoneSummaryRow()`
- `FocusPilot/Helpers/Constants.swift`：新增任务相关常量（todoIndent 等）
- `FocusPilot/Models/CoderSession.swift`：无修改（TodoItem 独立定义在 TodoService 中）

### TodoService 职责

```swift
class TodoService {
    static let shared = TodoService()

    /// 解析指定目录的 todo.md，返回 TodoFile（每次调用都重新读取文件）
    func parse(cwd: String) -> TodoFile?

    /// 变更任务状态（循环切换），写回文件
    func cycleStatus(item: TodoItem, in file: TodoFile)

    /// 删除任务条目，写回文件
    func deleteItem(_ item: TodoItem, in file: TodoFile)

    /// 获取任务的复制内容（有内容返回内容，无内容返回标题）
    func copyContent(for item: TodoItem) -> String

    /// 在编辑器中打开 todo.md
    func openInEditor(cwd: String)
}
```

### 数据流

```
展开任务折叠区
  → TodoService.parse(cwd)
  → 从 todo.md 重新读取解析
  → 返回 TodoFile
  → QuickPanelRowBuilder 渲染任务行

点击色点（状态变更）
  → TodoService.parse(cwd)  // 重新读取确保最新
  → TodoService.cycleStatus(item, file)
  → 写回 todo.md
  → QuickPanelView.forceReload()
  → 重新渲染

点击 ▶（复制到 AI 执行）
  → TodoService.copyContent(item) → NSPasteboard
  → CoderBridgeService.shared 查找该 cwd 的 active sessions
  → 单个：切换到宿主窗口
  → 多个：弹出 session 选择菜单 → 选择后切换
  → 无：仅复制
```

### 面板渲染集成

在 `QuickPanelView.buildAITabContent()` 中，每个 SessionGroup 渲染时：

1. 渲染文件夹 header（已有）
2. **新增**：检查该 group 的 `cwdNormalized` 是否存在 todo.md
   - 存在：渲染任务折叠区（`createTodoFoldRow`）
   - 展开时：渲染活跃任务条目 + Done 折叠摘要
3. 渲染分隔线（新增，仅在有任务时）
4. 渲染 Session 行（已有）

### 折叠状态管理

复用现有 `collapsedGroups` 模式，新增：
- `collapsedTodoGroups: Set<String>`：按 cwdNormalized 追踪任务区折叠状态
- `collapsedDoneGroups: Set<String>`：按 cwdNormalized 追踪 Done 区折叠状态

默认值：任务区折叠，Done 区折叠。

## 设计约束

- **无 todo.md = 无任务区**：不主动创建文件，不显示空状态占位
- **文件为唯一事实源**：不维护内存缓存，每次展开/操作都重新读取
- **最小写操作**：面板只做状态流转和删除，新增/编辑在编辑器完成
- **格式容错**：解析时忽略不认识的 `##` 标题区，只识别 Todo/In Progress/Done 三个列
- **主题兼容**：色点颜色使用系统色（systemYellow/systemGreen/systemGray），适配 8 主题
