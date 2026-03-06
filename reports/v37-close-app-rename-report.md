## 验收报告：关闭应用 + 收藏改关注

**日期**：2026-03-06
**规模**：S（小）
**场景**：B（已有项目新增功能）

### 1. 验收用例结果

| 用例 | 结果 | 验证方式 | 备注 |
|------|------|----------|------|
| 活跃 Tab App 行右键显示"关闭应用" | PASS | 代码审查 | `createRunningAppRow` 设置 `contextMenuProvider` 调用 `createRunningAppContextMenu` |
| 关注 Tab 运行中 App 右键显示"关闭应用" | PASS | 代码审查 | `createFavoriteContextMenu(bundleID:, isRunning:)` 在 `isRunning` 时添加菜单项 |
| 关注 Tab 未运行 App 右键不显示"关闭应用" | PASS | 代码审查 | `isRunning` 为 false 时跳过菜单项 |
| 点击"关闭应用"终止 App 进程 | PASS | 代码审查 | `handleTerminateApp` 调用 `NSRunningApplication.terminate()` + 0.5s 延迟 `forceReload()` |
| 全局"收藏"→"关注"文案替换 | PASS | grep 验证 | `grep -c "收藏"` 在所有 .swift 文件中返回 0 |
| 主看板"收藏管理"→"关注管理" | PASS | 代码审查 | `KanbanTab.appConfig.rawValue = "关注管理"` |
| 编译通过 | PASS | `make build` | 仅有已知 warnings，无新增错误 |
| 安装运行正常 | PASS | `make install` | 签名+安装+启动成功 |

### 2. 架构符合度

- 代码变更符合现有架构设计（extension 拆分、通知驱动）
- `handleTerminateApp` 遵循现有模式（`handleCloseWindow` 的延迟刷新模式）
- 右键菜单设置通过 `contextMenuProvider` 闭包，与 `createFavoriteAppRow` 一致
- 未引入新类型或新文件

### 3. 非目标确认

- 未做强制终止（`forceTerminate`），仅使用 `terminate()` 优雅关闭
- 未修改变量名/函数名（保持 `isFavorite`、`favorites` 等英文标识符）
- 未改动 ConfigStore 逻辑代码

### 4. 已知问题清单

无 P0/P1/P2 缺陷

### 5. 交付物清单

| 文件 | 职责 |
|------|------|
| QuickPanelMenuHandler.swift | 新增 `createRunningAppContextMenu`、`handleTerminateApp`；`createFavoriteContextMenu` 增加 `isRunning` 参数 |
| QuickPanelRowBuilder.swift | `createRunningAppRow` 增加右键菜单；`createFavoriteAppRow` 传递 `isRunning` |
| QuickPanelView.swift | "收藏"→"关注"文案 |
| MainKanbanView.swift | "收藏管理"→"关注管理" |
| AppConfigView.swift | "收藏"→"关注"文案（Tab、右键菜单、计数） |
| PreferencesView.swift | "收藏星标色"→"关注星标色" |
| Constants.swift | 注释"收藏"→"关注" |
| ConfigStore.swift | 注释"收藏"→"关注" |
| docs/PRD.md | 同步文案 + 新增关闭应用功能描述 |
| docs/Architecture.md | 同步文案 + 新增关闭应用流程 |
| CLAUDE.md | 同步文案 |

### 6. Git 提交记录

- `cdc02da` feat(QuickPanel): 添加右键"关闭应用"功能
- `5299081` style(UI): 将全局"收藏"文案改为"关注"
- `d417580` docs(PRD,Architecture): 同步"关注"文案 + 补充"关闭应用"功能文档
- `e239b04` docs(CLAUDE): 同步"关注"文案和关闭应用功能描述
