# AICrew 页面设计

> **状态**：可开发
> **更新**：2026-05-28
> **原型**：[00-layout-prototype.html](00-layout-prototype.html)
> **关联**：[PRD §3.4 Crew 数字团队](../PRD.md)

---

## 1. 定位

AICrew 是 AI Agent 团队的**管理中心**。用户面对的不是 Agent、MCP、Skill 等底层概念，而是一个可管理的“数字团队”。

一句话职责：AICrew 管**谁能做什么、能调用哪些工具、什么时候自动做事**。

### 与 Settings 的职责边界

| 维度 | AICrew | Settings |
|------|--------|----------|
| 管理对象 | Crew 成员、能力、MCP、常驻职责 | 全局偏好、默认成员、快捷键、主题 |
| 操作粒度 | 单个成员级配置 | 应用级默认值 |
| 典型问题 | “代码工程师能不能访问 GitHub？” | “默认派给哪个成员？” |

**硬规则**：AICrew 管成员能力；Settings 只引用 AICrew 的结果，不重复配置成员能力。

---

## 2. 侧边栏

侧边栏展示团队成员列表和运行概况。

```
┌─ AICrew ───────────────────────┐
│ [+]                             │
│ [搜索成员...]                    │
│                                 │
│ 团队成员                         │
│ ● 代码工程师          2          │
│   claude-code · 本地 · 空闲       │
│ ● 架构师              1          │
│   claude-code · 本地 · 执行中     │
│ ● 数据分析师          0          │
│   research-agent · 云端 · 未连接  │
│                                 │
│ 运行概况                         │
│ 执行中 1 / 可用 MCP 4/6 / 待授权 2│
└─────────────────────────────────┘
```

成员行信息：

| 字段 | 说明 |
|------|------|
| 状态点 | 绿色空闲、黄色执行中、红色不可用 |
| 成员名 | 用户可见角色名 |
| Runtime | 如 `claude-code` / `codex-cli` / `research-agent` |
| 部署位置 | 本地 / 云端 |
| 计数 | 并发上限或当前可用执行槽 |

点击成员后，工作区切换到对应成员详情。

---

## 3. 工作区

工作区分两个顶部视图：

1. `成员详情`
2. `运行状态`

### 3.1 成员详情

成员详情采用左主右辅布局：

```
┌─ 成员详情 ────────────────────────────────────────────┐
│ 💻 代码工程师             本地 · 空闲   [复制] [删除]   │
│ 并发上限 / MCP / 常驻职责 / 本周执行                    │
│                                                       │
│ 基本信息                                               │
│ 角色名 / 头像 / Runtime / 部署位置 / 并发数 / 默认 Skill │
│ 擅长领域                                               │
│                                                       │
│ MCP Server                                             │
│ filesystem / github / terminal / browser               │
│                                                       │
│ 常驻职责                                               │
│ event 新 PR review                                     │
│ cron 每日同步待整合素材                                 │
│ manual Focus 任务阻塞诊断                               │
└───────────────────────────────────────────────────────┘

┌─ 右侧辅助 ─────────────────────┐
│ 职责编辑器                      │
│ 触发方式 / 条件 / 范围 / 输出位置 │
│                                │
│ 执行历史                        │
│ 最近 24h 执行记录               │
│                                │
│ 调用边界                        │
│ 可写目录 / 网络访问 / 自动执行条件 │
└────────────────────────────────┘
```

### 3.2 运行状态

运行状态用于看团队整体健康度，不做深度配置：

- 团队成员数
- 执行中任务数
- MCP 可用数量
- 常驻职责数量
- 运行队列
- MCP 健康状态

---

## 4. 核心交互

| 用户任务 | 操作路径 | 规则 |
|----------|----------|------|
| 查看成员详情 | 侧边栏点击成员 | 工作区切换到该成员配置 |
| 新建成员 | `[+]` 或 `新建成员` | V1 可展示配置草稿；云端执行预留 |
| 修改基本信息 | 成员详情直接编辑 | 自动保存，失败时保留本地草稿 |
| 配置 MCP Server | MCP 区域启用/停用、检测连接 | 待授权项显示 amber 状态，不静默失败 |
| 配置常驻职责 | 新增职责 -> 选择触发方式 -> 填条件和输出位置 | `event` / `cron` / `manual` 三类触发 |
| 查看运行状态 | 顶部切到 `运行状态` | 只看队列和健康状态，不编辑成员 |
| 删除成员 | 成员详情 `删除` | 系统成员需二次确认；有执行中任务时禁止删除 |

---

## 5. 状态与规则

### 5.1 成员状态

| 状态 | 含义 | 用户可操作 |
|------|------|------------|
| `idle` | 可接任务 | 可编辑、可分配 |
| `running` | 正在执行任务 | 可编辑非运行关键字段；不可删除 |
| `offline` | Runtime 或 MCP 不可用 | 可编辑配置；不可分配任务 |
| `draft` | 新建未保存完整 | 不参与任务分配 |

### 5.2 MCP 状态

| 状态 | 含义 |
|------|------|
| `connected` | 已连接且可调用 |
| `authorized` | 已授权，等待具体调用 |
| `local` | 本地能力，跟随应用权限 |
| `pending_auth` | 需要用户授权 |
| `disabled` | 未启用 |

### 5.3 常驻职责状态

| 状态 | 含义 |
|------|------|
| `enabled` | 已启用，会按触发规则进入调度 |
| `draft` | 规则未完整或尚未启用 |
| `paused` | 用户暂停，不进入调度 |
| `failed` | 最近一次执行失败，需要处理 |

### 5.4 V1 范围

V1 做：

- 预置 `代码工程师`
- 成员详情配置 UI
- MCP Server 列表、状态、授权提示
- 常驻职责编辑 UI
- 运行状态 / 执行历史展示
- Focus / Studio 可引用 Crew 成员

V1 暂不做：

- 真正的多云端成员执行
- 多 Agent 自动选择
- 常驻职责后台定时调度
- 自定义头像上传
- MCP 市场或公开插件管理

---

## 6. 数据对象

```yaml
CrewMember:
  id: "crew_code_engineer"
  name: "代码工程师"
  avatar: "💻"
  runtime: "claude-code"
  deployment: "local"        # local | cloud
  status: "idle"             # idle | running | offline | draft
  concurrency_limit: 2
  default_skill: "dev-story"
  specialties:
    - "Swift/AppKit"
    - "前端原型"
    - "测试修复"

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
```

---

## 7. 术语

| 术语 | 含义 |
|------|------|
| Crew 成员 | 一个面向用户的 AI 角色配置 |
| Runtime | 成员背后的执行器，如 claude-code |
| MCP Server | 成员可调用的工具能力 |
| 常驻职责 | 按事件、时间或手动入口触发的自动任务 |
| 执行槽 | 成员当前可同时处理的任务容量 |

---

*待定项：无。*
