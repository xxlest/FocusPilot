# V3.1 验收报告 — 全部窗口 Tab + 收藏管理

**日期**：2026-03-02
**版本**：V3.1
**测试方法**：architect 架构设计 + 2 个 dev agent 并行开发 + team lead 集成审查 + 编译验证

---

## 1. 验收用例结果

| 用例 | 描述 | 结果 | 验证方式 | 备注 |
|------|------|------|---------|------|
| UC-1 | 全部 Tab 显示所有运行中 App | PASS | 代码审查+编译 | AppMonitor 遍历所有 regular App，按名称排序，排除自身 |
| UC-2 | 全部 Tab 实时响应 App 启退 | PASS | 代码审查 | NSWorkspace 通知 + 1s 定时器双路径，快照含运行状态 |
| UC-3 | 右键收藏 App | PASS | 代码审查 | createAppContextMenu 根据 isFavorite 动态切换菜单项 |
| UC-4 | 收藏 Tab 显示 | PASS | 代码审查 | buildFavoritesTabContent 从 appConfigs + runningApps 组合显示 |
| UC-5 | 收藏持久化 | PASS | 代码审查 | addApp/removeApp → save() → UserDefaults |
| UC-6 | 收藏 Tab 右键取消收藏 | PASS | 代码审查 | createFavoriteContextMenu → handleRemoveFavorite → removeApp |
| UC-7 | MainKanban 收藏管理 | PASS | 代码审查 | AppConfigView 重写为系统 App 列表 + 星标切换 |
| UC-8 | 数据迁移 | PASS | 代码审查 | migrateToV31 用 OldAppConfig 解码旧数据，过滤 isFavorite==true |

**汇总：8/8 项全部 PASS**

---

## 2. 架构符合度

| 检查项 | 结果 |
|--------|------|
| AppMonitor 解耦 ConfigStore | ✅ refreshRunningApps 不再依赖 appConfigs |
| AppConfig 移除 isFavorite | ✅ 在列表中即为收藏，decoder 向后兼容 |
| Tab 枚举 .selected → .all | ✅ 按钮文案"已选"→"全部" |
| 右键收藏菜单 | ✅ 全部Tab支持添加/移除，收藏Tab支持移除 |
| 数据迁移 | ✅ V3.1 迁移 key 防重复 |
| MainKanban 简化 | ✅ "快捷面板配置"→"收藏管理" |
| 无新增文件 | ✅ 修改 7 个现有文件 |

---

## 3. 变更文件清单

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `Models/Models.swift` | 修改 | AppConfig 移除 isFavorite，decoder 向后兼容 |
| `Services/ConfigStore.swift` | 修改 | 移除 toggleFavorite/favoriteAppConfigs，新增 isFavorite()，添加 V3.1 迁移 |
| `Services/AppMonitor.swift` | 修改 | refreshRunningApps 改为遍历所有 regular App，排除自身 |
| `QuickPanel/QuickPanelView.swift` | 重写 | Tab→全部/收藏，buildAllTabContent/buildFavoritesTabContent，App 行右键收藏 |
| `Helpers/Constants.swift` | 微调 | maxApps 注释更新 |
| `MainKanban/MainKanbanView.swift` | 微调 | Tab 标题→"收藏管理" |
| `MainKanban/AppConfigView.swift` | 重写 | 系统 App 列表 + 运行状态 + 收藏星标切换 |

---

## 4. 已知问题

| # | 级别 | 描述 |
|---|------|------|
| 1 | Info | AppMonitor.swift:80 编译警告 checkAccessibility() 返回值未使用 |
| 2 | Info | refreshAllWindows() 中 App 启退后 runningApps 可能包含已退出 App（下次 refreshRunningApps 才清理） |

---

## 5. 构建验证

- `make build` ✅ 成功（0 错误，1 已知 warning）
- `make install` ✅ 成功
- 应用已启动运行
