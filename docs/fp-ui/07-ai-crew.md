# AICrew 页面设计

> **状态**：可开发
> **更新**：2026-05-28
> **原型**：[00-layout-prototype.html](00-layout-prototype.html)
> **关联**：[PRD §3.4 Crew 数字团队](../PRD.md)

---

## 1. 定位

AICrew 是 AI Agent 团队的**管理中心**。用户面对的不是 Agent、MCP、Skill 等底层概念，而是一个可管理的“数字团队”。

一句话职责：AICrew 管**谁能做什么、能调用哪些工具、什么时候自动做事**。

参考 Multica 的 Runtime/Agent 配置模型后，AICrew 明确采用两层对象：

- `CrewMember`：面向用户的数字成员，承载角色、人设、职责、技能、授权和任务容量。
- `CrewRuntime`：成员背后的执行环境，承载本地/云端、Provider、CLI/daemon、心跳、模型发现和可见性。

**硬规则**：成员不是 Runtime；一个成员必须绑定一个 Runtime，Runtime 可以服务多个成员。AICrew 对用户仍保持“团队管理”隐喻，但不能把 Runtime 简化成一个不可解释的字符串。

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
| Runtime | 如 `Claude Code · MacBook` / `Codex CLI · MacBook` / `Research Cloud` |
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
│ 并发上限 / Runtime 健康 / 常驻职责 / 本周运行             │
│                                                       │
│ 基本信息                                               │
│ 角色名 / 头像 / 可见性 / Owner / Runtime / 模型 / 推理强度│
│ 并发数 / 默认 Skill / 擅长领域                          │
│                                                       │
│ Runtime 绑定                                           │
│ Mine / All 筛选；本地 / 云端；私有 / 公开；心跳 / CLI 版本 │
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
│ Agent 配置                      │
│ Instructions / Skills / Env / Args / MCP JSON │
│ Env 默认只显示 key 数，Reveal 后才编辑 secret     │
│                                │
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
- Runtime 在线数量
- MCP 可用数量
- 常驻职责数量
- Runtime Pool：按本机、远程、云端分组展示执行环境
- 运行队列
- Agent 负载：区分可用性和工作负载
- MCP 健康状态

---

## 4. 核心交互

| 用户任务 | 操作路径 | 规则 |
|----------|----------|------|
| 查看成员详情 | 侧边栏点击成员 | 工作区切换到该成员配置 |
| 新建成员 | `[+]` 或 `新建成员` | V1 可展示配置草稿；云端执行预留 |
| 修改基本信息 | 成员详情直接编辑 | 自动保存，失败时保留本地草稿 |
| 绑定 Runtime | `Runtime 绑定` 区域选择 Runtime | 支持 `Mine / All` 筛选；私有 Runtime 不可被他人绑定 |
| 覆盖模型/推理强度 | 成员基本信息选择模型和 thinking level | 默认跟随 Runtime/CLI；只有 Runtime 声明支持时才显示可选项 |
| 配置 MCP Server | MCP 区域启用/停用、检测连接 | 待授权项显示 amber 状态，不静默失败 |
| 配置高级 Agent 参数 | 右侧 `Agent 配置` Tab 编辑 Instructions / Skills / Env / Args / MCP JSON | Env secret 默认隐藏；MCP JSON 必须是对象，空对象等价于清空 |
| 配置常驻职责 | 新增职责 -> 选择触发方式 -> 填条件和输出位置 | `event` / `cron` / `manual` 三类触发 |
| 查看运行状态 | 顶部切到 `运行状态` | 只看队列和健康状态，不编辑成员 |
| 删除成员 | 成员详情 `删除` | 系统成员需二次确认；有执行中任务时禁止删除 |

---

## 5. 状态与规则

### 5.1 Runtime 健康状态

| 状态 | 含义 | UI 表达 |
|------|------|---------|
| `online` | 心跳正常，可接收任务 | 绿色在线点 |
| `recently_lost` | 最近丢失心跳，短时间内可能恢复 | amber 提示，不自动派新任务 |
| `offline` | 超过恢复窗口，视为不可用 | 红色不可用 |
| `about_to_gc` | 离线时间接近清理阈值 | amber 风险提示 |

Runtime 详情至少展示 Provider、运行模式、本机/云端、可见性、Owner、daemon id、CLI 版本、last seen、已绑定成员数。

### 5.2 成员可用性与负载

AICrew 不把“在线”和“忙”混成一个状态。成员状态拆成两轴：

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

### 5.3 MCP 状态

| 状态 | 含义 |
|------|------|
| `connected` | 已连接且可调用 |
| `authorized` | 已授权，等待具体调用 |
| `local` | 本地能力，跟随应用权限 |
| `pending_auth` | 需要用户授权 |
| `disabled` | 未启用 |

### 5.4 常驻职责状态

| 状态 | 含义 |
|------|------|
| `enabled` | 已启用，会按触发规则进入调度 |
| `draft` | 规则未完整或尚未启用 |
| `paused` | 用户暂停，不进入调度 |
| `failed` | 最近一次执行失败，需要处理 |

### 5.5 Agent 配置规则

- Instructions：成员长期指令，影响所有派发给该成员的任务。
- Skills：从本地 Skill 注册表选择；成员可有多个技能，默认 Skill 只影响快速派发。
- Env：只展示 key 数和 key 名；secret value 必须通过 Reveal 动作显式显示，关闭页面后重新隐藏。
- Args：展示为参数行，提交前转换为 argv；不能用字符串拼接执行 shell。
- MCP JSON：只接受 JSON object；无权限查看 secret 时展示 `redacted` 状态，保存时不得覆盖不可见字段。

### 5.6 V1 范围

V1 做：

- 预置 `代码工程师`
- 成员详情配置 UI
- Runtime Pool 与 Runtime 绑定选择器
- Runtime 健康状态、心跳和已绑定成员数展示
- 模型覆盖、推理强度覆盖、并发数配置
- Instructions / Skills / Env / Args / MCP JSON 配置壳
- MCP Server 列表、状态、授权提示
- 常驻职责编辑 UI
- 运行状态 / 执行历史展示
- Focus / Studio 可引用 Crew 成员

V1 暂不做：

- 真正的多云端成员执行
- Runtime daemon 自动发现与模型实时同步
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
```

---

## 7. 术语

| 术语 | 含义 |
|------|------|
| Crew 成员 | 一个面向用户的 AI 角色配置 |
| Runtime | 成员背后的执行环境，如本机 Claude Code daemon 或云端 Research runtime |
| Runtime 绑定 | 把 Crew 成员连接到某个可用 Runtime 的配置关系 |
| Agent 配置 | Instructions、Skills、Env、Args、MCP JSON 等影响成员执行行为的高级配置 |
| MCP Server | 成员可调用的工具能力 |
| 常驻职责 | 按事件、时间或手动入口触发的自动任务 |
| 执行槽 | 成员当前可同时处理的任务容量 |

---

*待定项：无。*
