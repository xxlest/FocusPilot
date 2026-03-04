# IDE-Proxy 技术架构与验证方案

> **状态**：V1.0
> **日期**：2026-02-23
> **关联文档**：`IDE-Proxy-设计梳理.md`（概念设计）、`FocusPilot-PRD-V1.md`、`FocusPilot-总架构设计.md`

---

## 1. 文档定位

本文档是 IDE-Proxy 的**技术实现方案**，在 `IDE-Proxy-设计梳理.md`（概念设计 V0.2）基础上，补充：

- **可运行的 PoC 验证脚本**（Phase 0）
- **完整的 IDE Proxy 服务实现**（TypeScript）
- **并行处理架构设计与实现**
- **请求模拟与输出监控工具**
- **配置说明与验证方法**

---

## 2. 架构总览

### 2.1 系统架构图

```
                    ┌─────────────────────────────────────────────────────────┐
                    │                    FocusPilot (Tauri)                      │
                    │                                                         │
                    │  DispatchService ──→ CursorAdapter ──HTTP──┐            │
                    │                                            │            │
                    │  MonitorStore  ←── Tauri Event ←── Webhook │            │
                    └────────────────────────────────────────────┼────────────┘
                                                                 │
                                                                 ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                          IDE Proxy (Node.js)                               │
│                          http://127.0.0.1:9801                             │
│                                                                            │
│  ┌──────────────┐  ┌──────────────────┐  ┌──────────────────────────────┐  │
│  │ HTTP Server   │  │ Session Manager  │  │ Parallel Dispatcher          │  │
│  │ (Express)     │  │ (状态机 + 存储)   │  │ (并发控制 + 等待队列)        │  │
│  └──────┬───────┘  └──────────────────┘  └──────────────────────────────┘  │
│         │                                                                  │
│  ┌──────┴───────┐  ┌──────────────────┐  ┌──────────────────────────────┐  │
│  │ Callback     │  │ Cursor Automator │  │ Hook Configurator            │  │
│  │ Server       │  │ (CLI+AppleScript)│  │ (settings.local.json 管理)   │  │
│  └──────────────┘  └──────────────────┘  └──────────────────────────────┘  │
│                                                                            │
│  ┌────────────────────────────────────────────────────────────────────┐    │
│  │ Webhook Client (状态变更 → HTTP POST → FocusPilot callback_url)      │    │
│  └────────────────────────────────────────────────────────────────────┘    │
└────────────────────────────────────────────────────────────────────────────┘
          │ cursor CLI                              ▲ Claude Code Hook
          │ + AppleScript                           │ (curl → Callback Server)
          ▼                                         │
┌─────────────────────────────────────────────────────────┐
│                  Cursor IDE 窗口 #1                      │
│  ┌─────────────────────────────────────────────────┐    │
│  │ 编辑器区域                                       │    │
│  ├─────────────────────────────────────────────────┤    │
│  │ 集成终端: $ claude "$(cat /tmp/xxx.prompt)"     │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────┐
│                  Cursor IDE 窗口 #2（并行）              │
│  ┌─────────────────────────────────────────────────┐    │
│  │ 编辑器区域                                       │    │
│  ├─────────────────────────────────────────────────┤    │
│  │ 集成终端: $ claude "$(cat /tmp/yyy.prompt)"     │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

### 2.2 核心组件

| 组件 | 文件 | 职责 |
|------|------|------|
| **HTTP Server** | `server.ts` | Express 路由，对外 API + 内部 Hook 回调 |
| **Session Manager** | `session-manager.ts` | Session CRUD + 状态机 + 超时清理 |
| **Parallel Dispatcher** | `parallel-dispatcher.ts` | 并发控制 + 等待队列 + 自动调度 |
| **Cursor Automator** | `cursor-automator.ts` | cursor CLI 启动 + AppleScript 终端自动化 |
| **Hook Configurator** | `hook-configurator.ts` | .claude/settings.local.json Hook 注入与清理 |
| **Webhook Client** | `webhook-client.ts` | 状态变更推送到 FocusPilot（含重试） |

---

## 3. 并行处理架构

### 3.1 并行策略

```
                    ┌─────────────────────────────┐
                    │     Parallel Dispatcher      │
                    │                              │
  dispatch ────────>│  活跃数 < max_concurrent?    │
                    │     │ YES          │ NO      │
                    │     ▼              ▼         │
                    │  立即执行      入等待队列     │
                    │     │              │         │
                    │     ▼              │         │
                    │  Cursor 启动      │         │
                    │  Claude Code 执行  │         │
                    │     │              │         │
                    │     ▼ (completed)  │         │
                    │  活跃数 -1 ────────┘         │
                    │     │ 队列非空时自动出列       │
                    │     ▼                        │
                    │  下一个任务立即执行            │
                    └─────────────────────────────┘
```

**核心规则**：

1. 每个任务独占一个 Cursor 窗口（`cursor --new-window`），Claude Code 实例完全隔离
2. `max_concurrent` 控制同时运行的 Cursor 窗口数（默认 3，可配置）
3. 超出限制的任务自动入队，当有 Session 进入终态时自动出列
4. 每个 Session 独立的 Hook 配置和回调标识，互不干扰

### 3.2 并行时序图

```
时间 →

Task A: ████████████████████ (executing) ──── completed
Task B: ████████████████████████████████ (executing) ──── completed
Task C: ████████████████████████████ (executing) ──── completed
                                                          │
Task D: ═══════════════════ (queued) ───────────────── ██████████ (auto-dispatched)
Task E: ═══════════════════════════════ (queued) ──────── ████████████ (auto-dispatched)

█ = 活跃执行  ═ = 在队列中等待
max_concurrent = 3 → 前 3 个立即执行，后 2 个排队
```

### 3.3 并行 API

**POST /dispatch/batch** — 批量并行派发

```json
// 请求
{
  "tasks": [
    { "task_id": "t1", "repo_path": "/path/to/repo1", "prompt": "实现功能 A" },
    { "task_id": "t2", "repo_path": "/path/to/repo2", "prompt": "实现功能 B" },
    { "task_id": "t3", "repo_path": "/path/to/repo3", "prompt": "实现功能 C" }
  ],
  "max_concurrent": 3
}

// 响应 202
{
  "batch_id": "batch-a1b2c3d4",
  "sessions": [
    { "session_id": "sess-xxx1", "status": "executing" },
    { "session_id": "sess-xxx2", "status": "executing" },
    { "session_id": "sess-xxx3", "status": "launching" }
  ],
  "total": 3,
  "dispatched": 3,
  "queued": 0
}
```

---

## 4. 状态机详解

### 4.1 状态流转图

```
                 dispatch 请求
                      │
                      ▼
              ┌──────────────┐
              │   launching  │  IDE Proxy 创建 Session
              └──────┬───────┘  注入 Hook → 启动 Cursor → 打开终端
                     │
                     │ Cursor + Claude Code 启动成功
                     ▼
              ┌──────────────┐
         ┌───>│  executing   │  Claude Code 正在执行任务
         │    └──────┬───────┘
         │           │
         │     Notification Hook（等待用户确认）
         │           │
         │           ▼
         │    ┌──────────────┐
         │    │waiting_input │  用户需要在 Cursor 终端中操作
         │    └──────┬───────┘
         │           │
         │     用户输入后 Claude Code 继续执行
         └───────────┘
                │
          Stop Hook（进程正常退出）
                │
                ▼
         ┌──────────────┐
         │  completed   │  终态：任务完成
         └──────────────┘

         ┌──────────────┐
         │    error     │  终态：可从任意非终态进入
         └──────────────┘  触发：启动失败 / 进程崩溃 / 超时
```

### 4.2 合法状态转移表

| 当前状态 → | launching | executing | waiting_input | completed | error |
|------------|:---------:|:---------:|:-------------:|:---------:|:-----:|
| **launching** | - | ✅ | - | - | ✅ |
| **executing** | - | - | ✅ | ✅ | ✅ |
| **waiting_input** | - | ✅ | - | ✅ | ✅ |
| **completed** | - | - | - | - | - |
| **error** | - | - | - | - | - |

### 4.3 Hook 事件 → 状态映射

| Hook 事件 | 映射状态 | 说明 |
|-----------|---------|------|
| `Stop` | `completed` | Claude Code 完成执行 |
| `Notification` | `waiting_input` | Claude Code 等待用户确认（权限/决策） |
| 启动失败/超时 | `error` | Cursor 或 Claude Code 启动异常 |

---

## 5. 完整派发流程

```
Step 1: FocusPilot 调用 POST /dispatch
        │
        ▼
Step 2: IDE Proxy 创建 Session (launching)
        │
        ▼
Step 3: 注入 Hook 配置
        写入 <repo>/.claude/settings.local.json
        含 Stop + Notification 回调 curl 命令
        │
        ▼
Step 4: 启动 Cursor
        执行: cursor --new-window <repo_path>
        AppleScript 轮询等待窗口出现
        │
        ▼
Step 5: 终端自动化
        AppleScript: 聚焦窗口 → Ctrl+` 打开终端
        AppleScript: keystroke "claude \"$(cat /tmp/xxx.prompt)\""
        AppleScript: keystroke return
        │
        ▼
Step 6: 状态转为 executing
        Webhook 推送给 FocusPilot
        │
        ▼
Step 7: Claude Code 执行中...
        Hook 按事件触发回调 → IDE Proxy 更新状态 → Webhook 推送
        │
        ▼
Step 8: Stop Hook 触发 → completed
        清理临时文件 + Hook 配置
        Webhook 推送最终状态给 FocusPilot
```

---

## 6. API 接口一览

### 6.1 对外 API（供 FocusPilot 调用）

| 方法 | 路径 | 说明 |
|------|------|------|
| `POST` | `/dispatch` | 单任务派发 |
| `POST` | `/dispatch/batch` | 批量并行派发 |
| `GET` | `/sessions` | 列出所有 Session |
| `GET` | `/sessions/:id` | 查询 Session 详情 |
| `DELETE` | `/sessions/:id` | 终止并清理 Session |
| `GET` | `/status` | 服务状态（统计 + 队列） |

### 6.2 内部 API（供 Claude Code Hook 调用）

| 方法 | 路径 | 说明 |
|------|------|------|
| `POST` | `/internal/callback` | Hook 回调（stop / notification / error） |

---

## 7. 代码结构

```
ide-proxy/
├── package.json              # 项目依赖
├── tsconfig.json             # TypeScript 配置
├── src/
│   ├── index.ts              # 入口：配置加载 + 组件初始化 + 服务启动
│   ├── types.ts              # 类型定义：Session、API、配置
│   ├── server.ts             # HTTP 路由：Express 路由定义
│   ├── session-manager.ts    # Session 管理：CRUD + 状态机
│   ├── cursor-automator.ts   # Cursor 自动化：CLI + AppleScript
│   ├── hook-configurator.ts  # Hook 管理：注入 + merge + 清理
│   ├── parallel-dispatcher.ts # 并行派发：并发控制 + 队列
│   └── webhook-client.ts     # Webhook：状态推送 + 重试
└── scripts/
    ├── simulate-dispatch.sh  # 单任务派发模拟
    ├── simulate-parallel.sh  # 并行派发模拟
    └── monitor-sessions.sh   # 实时 Session 监控面板
```

---

## 8. 配置说明

### 8.1 IDE Proxy 启动配置

```bash
# 默认启动
cd ide-proxy && npx tsx src/index.ts

# 自定义端口和并发数
npx tsx src/index.ts --port 9801 --max-concurrent 5
```

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--port` | `9801` | HTTP 服务端口 |
| `--host` | `127.0.0.1` | 监听地址 |
| `--max-concurrent` | `5` | 最大并发 Session 数 |

### 8.2 Claude Code Hook 配置

IDE Proxy 自动注入到 `<repo>/.claude/settings.local.json`：

```json
{
  "hooks": {
    "Stop": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": "curl -s -X POST http://127.0.0.1:9801/internal/callback -H 'Content-Type: application/json' -d '{\"session_id\":\"sess-xxx\",\"event\":\"stop\",\"marker\":\"focuspilot-ide-proxy\"}'",
        "timeout": 5
      }]
    }],
    "Notification": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": "curl -s -X POST http://127.0.0.1:9801/internal/callback -H 'Content-Type: application/json' -d '{\"session_id\":\"sess-xxx\",\"event\":\"notification\",\"marker\":\"focuspilot-ide-proxy\"}'",
        "timeout": 5
      }]
    }]
  }
}
```

**Merge 策略**：保留用户已有 Hook 配置，追加 FocusPilot 的回调 Hook。通过 `focuspilot-ide-proxy` 标记识别，清理时只移除带标记的 Hook。

### 8.3 环境要求

| 依赖 | 版本要求 | 验证命令 |
|------|---------|---------|
| macOS | 12+ | `sw_vers` |
| Node.js | 18+ | `node -v` |
| Cursor CLI | - | `which cursor` |
| Claude Code CLI | - | `which claude` |
| 辅助功能权限 | - | 系统偏好设置 → 隐私与安全性 → 辅助功能 |

---

## 9. PoC 验证方案（Phase 0）

### 9.1 验证脚本

```
poc/
├── README.md                 # 验证指南
├── 01-cursor-launch.sh       # P0-1: Cursor CLI 启动项目
├── 02-window-detect.sh       # P0-2: AppleScript 窗口定位
├── 03-terminal-control.sh    # P0-3: AppleScript 终端自动化
├── 04-hook-callback-test.sh  # P0-4: Hook 回调机制验证
└── 05-e2e-verify.sh          # P0-5: 端到端完整链路
```

### 9.2 验证清单

| 编号 | 验证内容 | 脚本 | 判定标准 |
|------|---------|------|---------|
| P0-1 | `cursor --new-window` 启动项目 | `01-cursor-launch.sh` | 窗口出现且标题含项目名 |
| P0-2 | AppleScript 窗口匹配 + AXRaise | `02-window-detect.sh` | 返回窗口名称并聚焦 |
| P0-3 | AppleScript 终端打开 + 命令输入 | `03-terminal-control.sh` | 终端中看到预期输出 |
| P0-4 | Claude Code Hook 回调 | `04-hook-callback-test.sh` | 回调服务器收到事件 |
| P0-5 | 端到端: dispatch → callback | `05-e2e-verify.sh` | 状态流转完整 |

### 9.3 执行方式

```bash
cd poc/

# 按顺序执行（每个脚本独立，可跳过已验证项）
./01-cursor-launch.sh /path/to/test-repo
./02-window-detect.sh TestProject
./03-terminal-control.sh TestProject
./04-hook-callback-test.sh /path/to/test-repo
./05-e2e-verify.sh /path/to/test-repo
```

### 9.4 判定标准

- **P0-1 ~ P0-4 全部通过** → 进入 Phase 1（IDE Proxy 实现）
- **P0-2 ~ P0-3 失败** → 评估 Cursor Extension 方案
- **P0-4 失败** → 检查 Claude Code Hook 配置格式或版本兼容性

---

## 10. 模拟与监控工具

### 10.1 单任务派发模拟

```bash
cd ide-proxy

# 启动 IDE Proxy
npx tsx src/index.ts &

# 模拟单任务
./scripts/simulate-dispatch.sh /path/to/repo "实现登录功能"
```

脚本行为：发送 dispatch → 轮询状态 → 输出状态流转直到完成或超时。

### 10.2 并行派发模拟

```bash
# 模拟 5 个任务，最大并发 3
./scripts/simulate-parallel.sh 5 3
```

脚本行为：
1. 构造 5 个任务的 batch 请求
2. 发送 `POST /dispatch/batch`
3. 监控所有 Session 直到全部完成
4. 输出并行执行的统计信息

### 10.3 实时监控面板

```bash
# 启动监控面板（每 3 秒刷新）
./scripts/monitor-sessions.sh 3
```

面板展示：
- 服务运行时间、并发数、队列长度
- 各状态 Session 统计
- 每个 Session 的 ID、Task、状态、更新时间

---

## 11. 风险与缓解

| 风险 | 严重度 | 缓解策略 |
|------|--------|---------|
| AppleScript 脆弱性 | 高 | Phase 0 先验证；保留 Cursor Extension 备选 |
| 多窗口定位 | 中 | 窗口标题匹配项目名 + AXRaise |
| 终端状态不确定 | 中 | 新建终端而非切换现有 |
| 长 Prompt 传递 | 低 | 临时文件 + `$(cat)` 展开 |
| Hook 事件覆盖度 | 中 | Phase 0 验证 Notification 覆盖度 |
| 并行窗口资源 | 中 | `max_concurrent` 限制 + 队列缓冲 |
| Session 泄漏 | 低 | 定时清理器 + 超时机制 |

---

## 12. 实施路径

### Phase 0: PoC 验证（当前阶段）

执行 `poc/` 下的脚本，验证核心技术假设。

### Phase 1: 最小可用 IDE Proxy

1. 安装依赖：`cd ide-proxy && npm install`
2. 启动服务：`npx tsx src/index.ts`
3. 单任务派发验证
4. 并行派发验证

### Phase 2: 与 FocusPilot 集成

1. FocusPilot CursorAdapter 改为调用 IDE Proxy API
2. ExecutionBinding 表增加 `proxy_session_id`
3. FocusPilot 接收 Webhook 更新 Monitor 状态

### Phase 3: 稳定性完善

1. 进程异常检测
2. Session 超时与清理
3. Hook 配置版本兼容
4. 日志与错误追踪

---

_文档版本：V1.0 | 最后更新：2026-02-23_
