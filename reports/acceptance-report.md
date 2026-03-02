# V3.2 验收报告 — 三 Tab 过滤 + 快捷面板 Tab 记忆

**日期**：2026-03-02
**版本**：V3.2
**测试方法**：dev agent 开发 + team lead 集成审查 + 编译验证

---

## 1. 验收用例结果

| 用例 | 描述 | 结果 | 验证方式 |
|------|------|------|---------|
| 1 | 快捷面板三 Tab 显示 | PASS | 代码审查+编译 |
| 2 | "已打开"Tab 只显示有窗口的 App | PASS | 代码审查 |
| 3 | Tab 记忆：关闭面板再打开保持上次 Tab | PASS | 代码审查 |
| 4 | Tab 记忆持久化：重启 App 后恢复 | PASS | 代码审查 |
| 5 | 快捷面板已移除收藏右键菜单 | PASS | 代码审查 |
| 6 | 主看板三 Tab 过滤（全部/已打开/收藏） | PASS | 代码审查+编译 |
| 7 | 主看板三个 Tab 都支持收藏/取消 | PASS | 代码审查 |

**汇总：7/7 项全部 PASS**

---

## 2. 变更文件清单

| 文件 | 变更 | 说明 |
|------|------|------|
| `Helpers/Constants.swift` | 微调 | 新增 `Keys.lastPanelTab` |
| `Services/ConfigStore.swift` | 修改 | 新增 `lastPanelTab` 属性 + `saveLastPanelTab()` |
| `QuickPanel/QuickPanelView.swift` | 修改 | 三 Tab（全部/已打开/收藏）+ Tab 记忆 + 移除收藏右键 |
| `MainKanban/AppConfigView.swift` | 修改 | 三 Tab 过滤（全部/已打开/收藏）+ Picker |

---

## 3. 构建验证

- `make build` ✅ 成功（0 错误，1 已知 warning）
- `make install` ✅ 成功
