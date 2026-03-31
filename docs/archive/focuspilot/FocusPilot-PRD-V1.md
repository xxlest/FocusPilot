# FocusPilot 产品需求文档（PRD）

> **版本**：V1.0
> **状态**：Draft
> **日期**：2026-02-23
> **基于**：FocusPilot 架构模块设计（Draft, 2026-02-23）

---

## 1. 产品概述

### 1.1 产品定位

FocusPilot 是一款面向个人开发者的**桌面端专注管理与任务调度工具**。它以 Obsidian Vault 为 Task 唯一数据源，融合两大核心能力：

- **FocusByTime**（专注计时）：番茄钟式循环工作节奏，通过"专注-休息"cycle 训练注意力觉察
- **FocusByTask**（任务调度）：任务树视图、看板、Today 视图、IDE 派发与执行监控

两者互补而非互斥：FocusByTask 回答"做什么"，FocusByTime 回答"怎么做"。

### 1.2 核心理念

- **Obsidian 为主数据源**：所有 Project / Epic / US / Task 数据存储在 Obsidian Vault 的 Markdown Frontmatter 中，FocusPilot 对其只读访问，不写回任何字段
- **任务管理与任务执行解耦**：管理侧负责层级结构展示与调度，执行侧仅做 Task ↔ IDE 窗口的松绑定
- **人工验收闭环**：IDE 执行结果由人工判断，FocusPilot 不感知执行成功或失败
- **专注节奏驱动**：通过循环计时建立稳定的工作节奏，辅助注意力觉察训练

### 1.3 产品边界

| 维度 | FocusPilot 负责 | Obsidian 负责 |
|------|-------------|---------------|
| Task 数据存储 | ❌ | ✅ Markdown + Frontmatter |
| Task 状态变更 | ❌ | ✅ 用户在 OB 中手动修改 status |
| Inbox 捕捉与处理 | ❌ | ✅ 通过 QuickAdd / BTT 脚本 |
| Task 树视图 / 看板 / Dashboard | ✅ | ❌ 移除看板和 Dashboard |
| IDE 派发与绑定 | ✅ | ❌ |
| 窗口监控 Widget | ✅ | ❌ |
| 知识管理与笔记 | ❌ | ✅ |

---

## 2. 目标用户

### 2.1 用户画像

**多项目并行推进的个人开发者 / 技术负责人**，具备以下特征：

- 使用 Obsidian 管理个人知识库与项目任务
- 采用 P.A.R.A. 方法论组织 Project / Epic / US / Task 层级
- 同时在多个 IDE 窗口中处理不同任务（Cursor、Claude Code 等 AI IDE）
- 需要快速掌握各任务执行状态，不想在 IDE 间频繁切换来追踪进度

### 2.2 使用场景

| 场景 | 描述 |
|------|------|
| 晨间规划 | 打开 FocusPilot 查看 Today 视图，确认今日要推进的 Task，逐一派发到 IDE |
| 并行执行 | 同时 3-5 个 IDE 窗口在执行不同 Task，通过 Widget 实时监控进度 |
| 快速切换 | 点击 Widget 或看板中的 Task 条目，一键跳转到对应 IDE 窗口 |
| 验收闭环 | IDE 完成后，人工检查结果，在 Obsidian 中将 Task 状态标记为 done |
| 全局概览 | 通过 Dashboard 查看各 Project 进度、本周 / 今日任务统计 |

---

## 3. 功能需求

### 3.1 模块总览

系统分为 **四个业务模块 + 一个基础设施模块**，归属两大子能力：

| 模块 | 类型 | 归属 | 核心职责 |
|------|------|------|---------|
| **Timer** | 业务 | FocusByTime | 专注/休息 cycle 计时、阶段切换、声音提醒 |
| **Task** | 业务 | FocusByTask | 任务全生命周期展示：树视图、Today 视图、看板、Dashboard |
| **Dispatch** | 业务 | FocusByTask | IDE 派发与绑定：选择 IDE → 启动 → 建立 Task ↔ 窗口绑定 |
| **Monitor** | 业务 | FocusByTask | 窗口监控：后台轮询窗口存活状态 |
| **Sync** | 基础设施 | 共享 | Obsidian 只读索引：全量扫描 + OB 通知增量刷新 |

> Timer 模块详细需求见 `docs/focus-by-time/FocusByTime-PRD.md`

### 3.2 Timer 模块（FocusByTime）

Timer 模块的完整功能需求见独立文档 `docs/focus-by-time/FocusByTime-PRD.md`，此处仅列要点：

- **FR-FT01~02**：专注阶段（默认 60 分钟）+ 休息阶段（默认 5 分钟），支持暂停/恢复
- **FR-FT03**：专注结束后自动切换为休息
- **FR-FT04**：阶段结束时声音提醒
- **FR-FT05**：可配置自动循环或手动开始下一轮
- **FR-FT06**：启动专注时可关联一个 Obsidian Task（不维护独立任务列表）

### 3.3 Task 模块

#### FR-T01：Project 树视图

**描述**：展示 Project → Epic → US → Task 四级层级树，支持展开 / 折叠、按状态筛选。

**详细需求**：
- 从 Obsidian Vault 目录结构和 Frontmatter 解析层级关系
- 树节点显示名称、状态标签、Task 数量统计
- 支持按 status 筛选（backlog / week / today / doing / done）
- 点击 Task 节点可查看详情（标题、描述、标签、所属 US / Epic / Project）
- 已绑定 IDE 的 Task 显示绑定状态图标，点击可激活对应 IDE 窗口

**验收标准**：
- 树结构与 Obsidian Vault 目录层级一致
- 筛选后只展示匹配 Task 及其祖先节点
- 树视图在 200 个 Task 规模下渲染无明显卡顿

#### FR-T02：Today 视图

**描述**：聚焦展示 status=today 的 Task 列表，作为每日执行的主操作界面。

**详细需求**：
- 展示所有 status=today 的 Task，按 Project 分组
- 每个 Task 卡片显示：标题、所属 US / Project、绑定状态
- 提供"派发"按钮入口，触发 Dispatch 模块的 DispatchModal
- 已绑定 IDE 的 Task 显示 IDE 类型图标和窗口状态（存活 / 已关闭）
- 点击已绑定的 Task 可跳转到对应 IDE 窗口

**验收标准**：
- 仅展示 status=today 的 Task
- 派发按钮正确触发 DispatchModal
- IDE 窗口状态与实际一致（3 秒内刷新）

#### FR-T03：看板视图

**描述**：按 Task 状态分列展示，提供直观的任务全景。

**详细需求**：
- 列划分：Backlog | Week | Today | Doing | Done
- 每列展示对应 status 的 Task 卡片
- Task 卡片信息：标题、所属 Project、标签
- Doing 列的 Task 显示绑定的 IDE 类型，点击可激活对应 IDE 窗口
- 看板为只读展示（状态变更在 Obsidian 中完成）

**验收标准**：
- 各列 Task 数量与 Obsidian 中对应 status 的 Task 一致
- Doing 列 Task 点击可正确激活 IDE 窗口

#### FR-T04：Dashboard 面板

**描述**：汇总展示各维度的任务统计数据，替代 Obsidian 中的 Dashboard。

**详细需求**：
- 各状态 Task 数量统计（backlog / week / today / doing / done）
- 按 Project 维度的进度概览（完成率）
- 本周完成数 / 今日完成数
- 当前执行中的 Task 数量及绑定的 IDE 列表

**验收标准**：
- 统计数据与 Obsidian Vault 实际数据一致
- 同步刷新后数据实时更新

### 3.4 Dispatch 模块

#### FR-D01：IDE 派发

**描述**：用户选中 Task 后，选择目标 IDE 类型，系统自动启动 IDE 并建立绑定。

**详细需求**：
- 弹出 DispatchModal，展示可用 IDE 列表（Cursor、Claude Code）
- 前置校验：Task 必须处于 today 状态才可派发
- 派发流程：
  1. 调用对应 IDE Adapter 启动 IDE（传入 Task 所属 Project 的代码仓库路径）
  2. 获取 IDE 进程 PID / 窗口 ID
  3. 写入 ExecutionBinding 记录（taskId ↔ ideType ↔ processId ↔ windowId）
- 派发成功后 UI 提示确认

**验收标准**：
- 仅 status=today 的 Task 可触发派发
- Cursor 和 Claude Code 均可成功启动
- ExecutionBinding 记录正确写入 SQLite
- 派发耗时 < 5 秒

#### FR-D02：IDE Adapter 扩展

**描述**：通过统一接口（IDEAdapter trait）支持多种 IDE，新增 IDE 仅需添加一个 Adapter 实现。

**详细需求**：
- 统一接口定义：`launch(task) -> Result<ProcessInfo>`、`get_window_id(pid) -> Option<WindowId>`
- MVP 支持两个 Adapter：
  - **CursorAdapter**：通过 `cursor` CLI 打开项目 + AppleScript 获取窗口信息
  - **ClaudeCodeAdapter**：通过 `claude` CLI 启动会话
- Adapter 注册机制：启动时自动发现并注册可用 Adapter

**验收标准**：
- 两个 Adapter 独立工作，互不影响
- 新增 Adapter 无需修改 DispatchService 代码

#### FR-D03：绑定管理

**描述**：管理 Task 与 IDE 窗口的绑定关系，支持查询和手动解绑。

**详细需求**：
- 查询当前所有活跃绑定列表
- 手动解除指定 Task 的绑定（IDE 窗口异常关闭时使用）
- 绑定记录包含：taskId、ideType、processId、windowId、status、boundAt
- 绑定状态：active（活跃）、stale（窗口已关闭但未手动清理）

**验收标准**：
- 绑定列表与实际 IDE 窗口状态一致
- 手动解绑后 SQLite 记录正确更新

### 3.5 Monitor 模块

#### FR-M01：窗口状态轮询

**描述**：后台线程定期检查所有绑定 IDE 窗口的存活状态，推送变更事件到前端。

**详细需求**：
- MonitorWorker 独立后台线程，轮询间隔可配置（默认 3 秒）
- 读取 SQLite 中所有 active 状态的 Binding，逐一检查窗口存活
- 窗口存活检测：通过 macOS Accessibility API / AppleScript 检查进程和窗口
- 状态变更时 emit Tauri Event（`monitor:status-changed`）通知前端

**验收标准**：
- IDE 窗口关闭后 ≤ 3 秒内检测到状态变更
- 多个绑定并行检测，不阻塞 UI
- 轮询线程异常不影响主应用

#### FR-M02：三层窗口架构

**描述**：FocusPilot 采用三层窗口架构，统一承载 FocusByTime 和 FocusByTask 的 UI。

**a) 悬浮球（Bubble）**

- 独立 Tauri 窗口，始终置顶、无边框、透明背景、可拖动，约 80x80 像素
- 中心：倒计时数字（Timer 空闲时显示执行中任务数）
- 外环：环形进度条，当前阶段剩余比例
- 背景色指示状态：Focus=绿 / Rest=蓝 / Idle=灰
- 右上角角标：执行中任务数
- 点击 Bubble 展开/收起 Cockpit

**b) Cockpit（驾驶舱）**

- 独立 Tauri 窗口，始终置顶、无边框、可固定(pin)为常驻/可切换为弹出
- 约 360x520 像素
- 包含三个区域：
  - **Timer 区域**：倒计时大字、阶段/轮次指示、开始/暂停/停止按钮、关联 Task 选择
  - **任务状态区域**：执行中 N / 待验收 N 摘要 + 任务列表 + IDE 跳转按钮
  - **快捷操作**：同步、设置、打开主面板

**c) 主面板（MainPanel）**

- 标准 Tauri 窗口，非置顶，约 1200x800 像素
- 包含所有完整功能页面：ProjectTree、Today、Kanban、Dashboard
- 包含 Timer 配置页面和全局设置页面

**验收标准**：
- 悬浮球始终置顶，不遮挡 IDE 工作区核心内容
- Cockpit 可通过点击 Bubble 或 pin 按钮切换显示模式
- 任务状态数字与实际一致，≤ 3 秒刷新
- 点击跳转正确激活对应 IDE 窗口

#### FR-M03：IDE 窗口跳转

**描述**：从 FocusPilot 任意界面（Widget、看板、Today 视图）点击 Task 条目，激活对应 IDE 窗口。

**详细需求**：
- 通过 macOS 窗口 API 将目标 IDE 窗口激活并置前
- 支持从 Widget TaskStatusList、KanbanPage Doing 列、TodayPage 已绑定 Task 触发
- 窗口已关闭时显示提示，建议用户重新派发或手动解绑

**验收标准**：
- 窗口存活时正确激活并置前
- 窗口已关闭时给出明确提示

### 3.6 Sync 模块

#### FR-S01：启动全量同步

**描述**：应用启动时扫描 Obsidian Vault，解析所有 Task 文件的 Frontmatter，构建内存索引。

**详细需求**：
- 扫描路径：配置的 Obsidian Vault 根路径下的 `1-Focus/` 目录
- 解析 Markdown 文件的 YAML Frontmatter，提取：
  - `type`（project / epic / us / task）
  - `status`（backlog / week / today / doing / done）
  - `parent_project` / `parent_epic` / `parent_us`（层级关系）
  - `title`、`tags`、`priority`、`created`、`updated` 等
- 构建内存索引：`HashMap<TaskId, TaskMeta>` + 树结构缓存
- 启动完成后 emit 事件通知前端加载完毕

**验收标准**：
- 索引数据与 Obsidian Vault 文件一致
- 500 个 Task 文件的全量扫描 < 2 秒
- 索引构建失败时给出错误提示，不阻塞应用启动

#### FR-S02：OB 通知增量同步

**描述**：Obsidian 端 Task 文件变更时，通过 IPC 通知 FocusPilot 刷新指定文件的内存索引。

**详细需求**：
- 支持接收 OB 端通知的通道：HTTP / WebSocket / CLI（MVP 先实现一种）
- 通知内容：变更文件路径
- 收到通知后：解析该文件 Frontmatter → 更新内存索引对应条目
- 刷新完成后 emit `sync:index-updated` 事件通知前端

**验收标准**：
- OB 端修改 Task status 后，FocusPilot 在 ≤ 2 秒内反映变更
- 通知文件不存在（已删除）时正确从索引中移除

#### FR-S03：手动全量同步

**描述**：UI 提供"同步"按钮，触发全量重新扫描 Vault 并重建内存索引。

**详细需求**：
- MainWindow 提供同步按钮
- 同步过程中显示加载状态
- 完成后 emit 事件通知前端刷新

**验收标准**：
- 手动同步后数据与 Vault 完全一致
- 同步过程不阻塞 UI 操作

---

## 4. 非功能需求

### 4.1 性能

| 指标 | 目标值 |
|------|--------|
| 启动全量同步（500 Task） | < 2 秒 |
| 内存索引查询响应 | < 50ms |
| Task 派发到 IDE 启动 | < 5 秒 |
| Widget 状态刷新延迟 | ≤ 3 秒 |
| 应用内存占用（稳态） | < 150MB |

### 4.2 可靠性

- **本地优先**：核心数据（Task）存储在本地 Obsidian Vault，断网完全可用
- **IDE 失联容错**：IDE 崩溃或窗口关闭仅影响 Binding 记录，不污染 Task 数据
- **同步兜底**：OB 通知失效时，手动全量同步可恢复数据一致性
- **轮询线程隔离**：MonitorWorker 异常不影响主应用和其他模块

### 4.3 可扩展性

- **IDE Adapter 插件化**：新增 IDE 只需实现 `IDEAdapter` trait，无需修改其他模块
- **同步通道可替换**：OB 通知的 IPC 方式可从 HTTP 切换到 WebSocket 或 CLI
- **模块间无循环依赖**：Task → Dispatch → Monitor 单向调用链

### 4.4 可用性

- **Widget 轻量**：悬浮窗小巧、可折叠、可拖动，不干扰正常工作
- **一键跳转**：从任意界面点击 Task 即可跳转到对应 IDE 窗口
- **状态一目了然**：Dashboard 和 Widget 数字化呈现执行概况

### 4.5 平台约束

- **操作系统**：macOS（首版仅支持，因 Accessibility API / AppleScript 依赖）
- **前置依赖**：已安装 Obsidian 并配置 VaultOne 知识库
- **IDE 支持**：Cursor（AppleScript + CLI）、Claude Code（CLI）

---

## 5. 数据模型

### 5.1 数据归属

| 数据 | 存储位置 | 读写方式 |
|------|---------|---------|
| Project / Epic / US / Task 层级 | Obsidian Vault（Markdown + Frontmatter） | FocusPilot 只读 |
| Task 状态（status 字段） | Obsidian Frontmatter | FocusPilot 只读 |
| Task 树索引 / 聚合缓存 | 内存 HashMap | 启动全量扫描 + OB 通知刷新 |
| ExecutionBinding（Task ↔ IDE 窗口） | SQLite | CRUD |

### 5.2 核心实体

#### Task（来源：Obsidian Frontmatter，只读）

```yaml
# Obsidian Markdown Frontmatter
type: task
title: "实现用户登录功能"
status: today          # backlog / week / today / doing / done
priority: high
tags: [auth, frontend]
parent_project: "ProjectA"
parent_epic: "用户系统"
parent_us: "登录注册"
created: 2026-02-20
updated: 2026-02-23
```

#### Project / Epic / US（来源：Obsidian 目录结构 + Frontmatter，只读）

```yaml
# Project Frontmatter
type: project
title: "ProjectA"
repo_path: "/Users/bruce/Workspace/2-Code/01-work/project-a"
status: active

# Epic Frontmatter
type: epic
title: "用户系统"
parent_project: "ProjectA"

# US Frontmatter
type: us
title: "登录注册"
parent_epic: "用户系统"
parent_project: "ProjectA"
```

#### ExecutionBinding（存储：SQLite）

```sql
CREATE TABLE execution_binding (
    id          TEXT PRIMARY KEY,
    task_id     TEXT NOT NULL,       -- 关联的 Task 文件路径或唯一标识
    ide_type    TEXT NOT NULL,       -- cursor / claude_code
    process_id  INTEGER,            -- IDE 进程 PID
    window_id   TEXT,               -- macOS 窗口标识
    status      TEXT NOT NULL,       -- active / stale
    bound_at    TEXT NOT NULL,       -- ISO 8601
    updated_at  TEXT NOT NULL
);
```

### 5.3 状态定义

FocusPilot 复用 Obsidian 的 `status` 字段，统一管理调度状态和执行状态：

| status 值 | 含义 | 阶段 |
|-----------|------|------|
| `backlog` | 待处理，暂不安排时间 | 调度 |
| `week` | 本周内完成 | 调度 |
| `today` | 今日完成 | 调度 |
| `doing` | 已派发，IDE 执行中 | 执行 |
| `done` | 完成 | 终态 |

> 状态变更在 Obsidian 中由用户手动完成，FocusPilot 不写回。

---

## 6. 用户流程

### 6.1 核心流程：从 Today 到验收

```
用户在 OB 中将 Task status 设为 today
        ↓
FocusPilot Sync 检测到变更 → 刷新内存索引
        ↓
用户在 FocusPilot Today 视图看到该 Task
        ↓
用户点击「派发」→ 选择 IDE 类型 → 确认
        ↓
DispatchService 启动 IDE → 建立 Binding → Task 在看板 Doing 列显示
        ↓
MonitorWorker 轮询检测窗口状态 → Widget 实时展示
        ↓
用户在 IDE 中完成工作 → 人工验收
        ↓
用户在 OB 中将 Task status 改为 done
        ↓
FocusPilot Sync 检测到变更 → Widget 和看板更新
```

### 6.2 专注计时 + 任务派发联合流程

```
用户在 Today 视图选中 Task-A → 点击「派发」→ Cursor 启动
        ↓
用户在 Cockpit Timer 区域选择关联 Task-A → 点击「开始专注」
        ↓
Bubble 显示倒计时 59:59 → 环形进度条绿色 → 角标显示执行中 1
        ↓
60 分钟专注结束 → 提示音响铃 → 自动切换为休息 5 分钟
        ↓
Bubble 变蓝色，显示 4:59 倒计时
        ↓
休息结束 → 自动开始下一轮专注（cycle 2）
        ↓
用户可随时暂停 Timer 或手动停止
```

### 6.3 并行多任务流程

```
Today 视图展示 5 个 Task
        ↓
用户逐一派发到不同 IDE（Cursor × 3, Claude Code × 2）
        ↓
Widget 显示：执行中 5
        ↓
Task-A 的 IDE 完成 → 用户点击 Widget 跳转到该窗口 → 人工验收
        ↓
用户在 OB 中标记 Task-A done → Widget 更新：执行中 4 / 今日完成 1
        ↓
继续处理其他 Task...
```

### 6.4 异常场景处理

| 异常场景 | 系统行为 | 用户操作 |
|---------|---------|---------|
| IDE 窗口意外关闭 | Monitor 检测到窗口不存活，Binding 标记为 stale | Widget 显示"待验收"，用户可重新派发或手动解绑 |
| IDE 启动失败 | Dispatch 返回错误，不创建 Binding | UI 提示错误信息，用户排查后重试 |
| OB 通知失效 | 数据不同步 | 用户点击"手动同步"按钮 |
| Obsidian 未运行 | 同步功能不受影响（直接读取文件） | 正常使用 |
| 绑定残留 | 应用重启时检测到 stale Binding | 自动清理或提示用户处理 |

---

## 7. 技术架构摘要

> 完整技术设计见 `FocusPilot-总架构设计.md`

### 7.1 技术栈

| 层 | 技术选型 |
|----|---------|
| 桌面框架 | Tauri（三层窗口：Bubble + Cockpit + MainPanel） |
| 后端 | Rust |
| 前端 | React / TypeScript |
| 状态管理 | Zustand |
| 本地数据库 | SQLite（仅 ExecutionBinding） |
| 窗口监控 | macOS Accessibility API / AppleScript |
| 日志 | Rust tracing 框架 |

### 7.2 分层架构

```
UI Layer（React/TS）
  → Application Layer（Tauri Commands：参数校验 + 路由）
    → Service Layer（业务编排）
      → Domain Layer（纯逻辑：实体 + 状态机 + 规则）
      → Infrastructure Layer（Obsidian FS / 内存索引 / SQLite / IDE Adapter / 窗口 API）
```

### 7.3 通信机制

| 方向 | 机制 | 场景 |
|------|------|------|
| 前端 → 后端 | `tauri::invoke()` | 用户主动操作 |
| 后端 → 前端 | `tauri::Event emit()` | Monitor 状态变更、同步完成通知 |
| OB → FocusPilot | IPC 通知（HTTP / WS / CLI） | Task 变更通知 |

---

## 8. 版本规划

### 8.1 V1（MVP）

**目标**：打通核心闭环——从 Obsidian Task 同步 → 树视图 / Today 视图 → IDE 派发 → Widget 监控 → 人工验收。

| 里程碑 | 核心交付 |
|--------|---------|
| **M0：基础层** | Frontmatter 解析器 + 内存索引 + 全量同步 + SQLite Binding Schema |
| **M1：Task 视图** | Project 树视图 + Today 视图 + 看板视图 + Dashboard 面板 |
| **M2：执行层** | IDE Dispatcher（Cursor + Claude Code）+ ExecutionBinding + Window Monitor |
| **M3：三层窗口** | Bubble 悬浮球 + Cockpit 驾驶舱 + MainPanel 主面板 |
| **M4：Timer 引擎** | 专注/休息 cycle 计时 + 阶段切换 + 声音提醒 + Cockpit Timer 控制区 |
| **M5：打磨** | OB 通知增量同步 + 错误处理完善 + 稳定性优化 |

### 8.2 V1.5（增强）

- 任务模板（常见 US / Task 模板快速创建）
- 执行历史与耗时统计
- Widget 快速备注（执行过程中的临时记录）
- 更多 IDE Adapter（VS Code、WebStorm 等）

### 8.3 V2（智能化）

- 分发规则引擎（按 Task 类型 / 标签自动推荐 IDE）
- 流程编排（分析 → 验收规则 → 编码 → 自验的 ralph 模式）
- 风险预警（长时间无动作、依赖冲突检测）
- 跨平台支持（Windows / Linux）

---

## 9. 验收标准（MVP）

### 9.1 功能验收

| # | 测试场景 | 预期结果 |
|---|---------|---------|
| 1 | 启动 FocusPilot，Vault 含 50+ Task | 全量同步完成，树视图正确展示层级 |
| 2 | 在 OB 中新增一个 Task 并通知 FocusPilot | 增量同步后 Task 出现在对应位置 |
| 3 | Today 视图展示 status=today 的 Task | 仅显示 today 的 Task，数量正确 |
| 4 | 看板视图各列 Task 数量 | 与 Obsidian 中各 status 的 Task 数一致 |
| 5 | 选中 today Task，选 Cursor，点击派发 | Cursor 启动，Binding 记录写入，Task 出现在 Widget 执行中列表 |
| 6 | 选中 today Task，选 Claude Code，点击派发 | Claude Code 启动，Binding 记录写入 |
| 7 | 同时派发 3 个 Task 到不同 IDE | Widget 显示执行中: 3，三个窗口均可通过点击跳转 |
| 8 | IDE 窗口关闭后 | Widget ≤ 3 秒内检测到，状态更新为待验收 |
| 9 | 点击 Widget 中的 Task 条目 | 正确跳转到对应 IDE 窗口并置前 |
| 10 | 在 OB 中将 Task status 改为 done | FocusPilot 同步后 Widget 执行中 -1，今日完成 +1 |
| 11 | 尝试派发 status=backlog 的 Task | 系统拒绝，提示"仅 today 的 Task 可派发" |
| 12 | 手动点击同步按钮 | 全量重建索引，数据与 Vault 一致 |
| 13 | Dashboard 面板统计 | 各状态数量、Project 进度与实际一致 |

### 9.2 性能验收

| 指标 | 目标 |
|------|------|
| 全量同步（500 Task） | < 2 秒 |
| 任意查询响应 | < 50ms |
| 派发到 IDE 启动 | < 5 秒 |
| Widget 状态刷新 | ≤ 3 秒 |
| 并行绑定上限（V1） | ≥ 5 个 IDE 窗口 |

---

## 10. 风险与缓解

| 风险 | 影响 | 缓解策略 |
|------|------|---------|
| macOS Accessibility API 权限受限 | 窗口检测和激活失败 | 优先用进程 PID 绑定，降级用窗口标题匹配；引导用户授权辅助功能权限 |
| IDE CLI 接口不稳定 | 派发失败 | Adapter 内做重试和超时处理；失败不影响 Task 状态 |
| Obsidian Frontmatter 格式不一致 | 同步解析错误 | 制定 Frontmatter 规范文档；解析容错处理（跳过格式异常文件并记录日志） |
| OB 通知机制未实现 | 无法增量同步 | MVP 优先实现手动全量同步作为兜底；OB 通知列为 M4 增强 |
| Vault 文件量过大 | 全量同步性能下降 | 限定扫描范围（仅 `1-Focus/` 目录）；增量同步减少全量扫描频率 |
| Tauri 多窗口通信复杂度 | Widget 和 MainWindow 状态不同步 | 使用 Tauri Event 统一推送，Zustand store 响应式更新 |

---

## 11. 约束与假设

### 11.1 约束

- 首版仅支持 macOS 平台
- Obsidian Vault 必须按照 VaultOne P.A.R.A. 规范组织目录和 Frontmatter
- FocusPilot 对 Obsidian 完全只读，用户通过 Obsidian 完成 Task 创建和状态变更
- SQLite 仅存储 ExecutionBinding，不存储 Task 副本

### 11.2 假设

- 用户已安装并使用 Obsidian 作为知识管理工具
- 用户已按照 Project → Epic → US → Task 层级组织任务
- 用户使用的 IDE（Cursor / Claude Code）已安装且 CLI 可用
- 用户的 macOS 已授权 FocusPilot 辅助功能权限（Accessibility）

---

## 12. 术语表

| 术语 | 定义 |
|------|------|
| **Project** | 顶层项目，对应一个代码仓库 |
| **Epic** | 项目下的功能模块或里程碑 |
| **US（User Story）** | 用户故事，Task 的归属单元 |
| **Task** | 可执行的最小工作单元，归属于某个 US |
| **ExecutionBinding** | Task 与 IDE 窗口的绑定关系记录 |
| **Dispatch（派发）** | 将 Task 分配到指定 IDE 并启动执行 |
| **Widget** | 悬浮监控窗口，实时展示任务执行状态 |
| **Sync** | Obsidian Vault 数据同步到 FocusPilot 内存索引的过程 |
| **Frontmatter** | Markdown 文件头部的 YAML 结构化元数据 |
| **Adapter** | IDE 适配器，封装特定 IDE 的启动和通信逻辑 |

---

## 附录 A：文档关联

| 文档 | 用途 |
|------|------|
| `docs/focus-by-time/FocusByTime-PRD.md` | FocusByTime 子模块需求文档 |
| `docs/focuspilot/FocusPilot-总架构设计.md` | 完整架构与模块设计文档 |
| `CLAUDE.md` | 项目开发指南与架构速查 |

---

_文档状态：Draft | 最后更新：2026-02-24_
