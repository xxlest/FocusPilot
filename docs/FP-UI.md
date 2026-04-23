<!--
 * @Author: xxl
 * @Date: 2026-04-16 10:49:11
 * @LastEditors: xxl
 * @LastEditTime: 2026-04-21
 * @Description: FocusPilot UI 设计总览
 * @FilePath: /FocusPilot/docs/FP-UI.md
-->

# FocusPilot UI 设计总览

> **版本**：0.0.1
> **状态**：设计中
> **更新**：2026-04-21

---

## 整体布局

类似 VS Code 布局：左活动栏（52px）+ 侧边栏（260px）+ 工作区（flex）。点击活动栏切换对应的侧边栏及工作区内容，选中项高亮显示。

→ 详见 [00-layout.md](fp-ui/00-layout.md)

---

## 页面清单

| 活动栏 | 页面 | 说明 | 状态 | 设计文档 |
|--------|------|------|------|---------|
| 🏠 | Home | AI 对话入口 + 最近操作（参考 Plane Home 页 Widget 化） | 草稿 | [01-home.md](fp-ui/01-home.md) |
| 📥 | Inbox | 收集箱：待阅读/灵感/临时任务/便签（参考 Plane Stickies） | 草稿 | [02-inbox.md](fp-ui/02-inbox.md) |
| 🎯 | **Focus** | 结构化行动工作台：规划+看板+列表+Task 执行闭环（原 Workspace） | **设计中** | [03-workspace.md](fp-ui/03-workspace.md) |
| 💻 | **Studio** | 项目级 AI 工作区：对话/文件浏览/Git 历史（参考 Z Code + Codex） | **设计中** | [04-studio.md](fp-ui/04-studio.md) |
| 📁 | AreaProjects | 项目资产沉淀（执行类+知识类），文件树+编辑器 | 草稿 | [05-area-projects.md](fp-ui/05-area-projects.md) |
| 🤖 | AICrew | Agent 团队管理（角色/头像/擅长/MCP/并发数） | 草稿 | [06-ai-crew.md](fp-ui/06-ai-crew.md) |
| ⚙️ | Settings | 全局配置：Focus/Studio/AICrew/Projects/通用 | 草稿 | [07-settings.md](fp-ui/07-settings.md) |

---

## 交互式原型

- [Focus 原型](fp-ui/03-workspace-prototype.html) — Focus 页面交互原型（规划三模式+看板+列表+Task 详情页+新建弹窗）

---

## 技术架构

前端：Swift 5 + AppKit/SwiftUI（macOS 原生）

后端整合方向：
- **Multica**（裁剪后个人版）：Agent Runtime 执行能力、Workspace 数据模型、Task Queue
- **Plane**：项目管理结构参考（Cycles/Modules/Views/Stickies）
- **Z Code / Codex**：Studio 会话模式、多 Agent 框架切换、对话式开发 ADE

→ 详见 [PRD.md](PRD.md) §2 产品架构
