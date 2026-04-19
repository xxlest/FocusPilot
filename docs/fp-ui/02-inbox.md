# Inbox 收集箱页面设计

> **状态**：草稿
> **更新**：2026-04-18
> **参考**：Plane Stickies

---

## 定位

收集箱负责管理待阅读内容、灵感、临时任务和便签，是信息的统一入口。

## 侧边栏

管理以下分类：
- **待阅读**（to-read）
- **灵感**
- **临时任务**
- **便签**（参考 Plane Stickies）
- **自动采集任务**（待定）

## 录入功能

弹窗输入框：

1. **类型**：待阅读 / 灵感 / 临时任务
2. **分类**：来自 Settings 配置
3. **标题与 URL**：
   - URL 解析支持多种媒体来源：B站、公众号、YouTube 等
   - 根据录入内容及配置模板，生成 Markdown 文件

## 自动采集

- 需配置 Agent 和信息源平台（待定）
- Agent 根据信息源平台内容自动采集
- 生成 Markdown 文件
- 提供合并到哪个 AreaProject 的申请待审批

## 与 Workspace 的关系

Inbox 条目可通过「移入 Workspace」操作导入 Workspace，成为 Task（source=inbox）。

---

*详细设计待补充*
