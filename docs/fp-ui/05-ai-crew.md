# AICrew 页面设计

> **状态**：草稿
> **更新**：2026-04-18
> **关联**：[PRD §3.4 Crew 数字团队](../PRD.md)

---

## 定位

AICrew 页面管理 AI Agent 团队，用户面对的不是技术概念（Agent/MCP/Skill），而是管理一个"数字团队"。

## 核心功能

### Agent 管理

每个 Crew 成员的配置项：
- 角色名（如"代码工程师"）
- 头像
- 擅长领域
- 绑定 MCP Server / Runtime
- 部署位置（本地/云端）
- 常驻职责（cron / event 触发）
- 并发数限制

### V1 预置

```
🧑‍💻 代码工程师 — claude-code, 本地, 并发 2
```

### 与 Workspace 的关系

- Workspace 中 Task 的 `assigned_agent` 从 AICrew 配置中选择
- Settings 中的默认 Agent 也引用 AICrew 的配置
- Agent 并发数在此配置，Workspace 执行时受限于此值

---

*详细设计待补充*
