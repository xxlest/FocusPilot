# V3.5 验收报告

## 1. 验收用例结果

| 用例 | 结果 | 验证方式 | 备注 |
|------|------|----------|------|
| UC1 星号位置 | PASS | 代码审查 | 星号 -> 状态点 -> 图标 -> 名称，顺序正确 |
| UC2 星号功能不受影响 | PASS | 代码审查 | target/action、关联对象、尺寸约束均未改变 |
| UC3 收藏拖拽排序 | PASS | 代码审查 | 浮动快照 + 动画换位 + 持久化完整 |
| UC4 拖拽排序持久化 | PASS | 代码审查 | reorderApps() 正确调用并保存到 UserDefaults |
| UC5 拖拽阈值防误触 | PASS | 代码审查 | 5px 阈值判断正确，未超阈值触发 clickHandler |
| UC6 窗口重命名绑定实例 | PASS | 代码审查 | renameKey 使用 windowInfo.id (CGWindowID)，每窗口独立 |
| UC7 重命名跨重启失效 | PASS | 代码审查 | CGWindowID 临时性，App 重启后自然失效 |
| UC8 清除重命名 | PASS | 代码审查 | representedObject 传入 key 字符串，移除并保存正确 |

**验收用例通过率：8/8 (100%)**

## 2. 架构符合度

- 实际代码与 `reports/v35-architecture.md` 架构文档一致
- 仅修改 `QuickPanelView.swift`，未修改 ConfigStore / Models / Constants（符合非目标声明）
- 接口契约正确遵循：renameKey 签名变更、reorderApps 调用、isDragging 互斥机制
- HoverableRowView 拖拽支持采用了推荐方案（dragEnabled + handler 闭包组）

## 3. 非目标确认

- 未修改活跃 Tab 拖拽排序（runtimeOrder 不变）
- 未实现跨 Tab 拖拽
- 未迁移旧 windowRenames 数据（静默失效）
- 未添加窗口重命名跨重启持久化
- 未修改 ConfigStore / Models / Constants

## 4. 已知问题清单

### 已修复的 P1 缺陷

| # | 描述 | 修复方式 |
|---|------|----------|
| C1 | bitmapImageRepForCachingDisplay 强制解包崩溃风险 | 改为 guard let 安全解包 |
| C2 | isDragging 状态在面板关闭时未清理 | resetToNormalMode 增加拖拽状态清理 |

### 遗留的 P2 缺陷（不阻塞发布）

| # | 描述 | 影响 |
|---|------|------|
| B2 | 拖拽中切换 Tab 可能导致状态不一致 | 极低概率触发，拖拽中鼠标被捕获 |
| B3 | 只有 1 个收藏时拖拽闪烁 | 体验瑕疵，不影响功能 |
| B6 | 滚动状态下拖拽定位可能偏差 | 收藏上限 8 个，极少需要滚动 |
| C4 | 旧 renameKey 数据永久残留 | 数据量极小，不影响性能 |

### /simplify 审查修复

| # | 描述 | 修复方式 |
|---|------|----------|
| 1 | favDragMouseDown 死代码 | 删除未使用属性 |
| 2 | alpha 恢复表达式可读性 | 简化为 contains 检查 |
| 3 | dragIndex 闭包捕获陈旧值 | 改为动态 firstIndex 查找 |
| 4 | favDragSourceIndex! 强制解包 | 替换为 guard-bound sourceIndex |

## 5. 交付物清单

| 文件 | 职责 | 变更类型 |
|------|------|----------|
| `FocusPilot/QuickPanel/QuickPanelView.swift` | 三项功能实现 + P1 修复 | 修改（+243/-12） |
| `reports/v35-architecture.md` | V3.5 增量架构设计文档 | 新增 |
| `reports/v35-qa-report.md` | QA 缺陷检测报告 | 新增 |
| `reports/v35-acceptance-report.md` | 验收报告（本文件） | 新增 |

## 6. 结论

V3.5 三项功能全部实现并通过验收：
1. 活跃列表星号位置调整到状态点前面
2. 收藏 Tab 拖动排序（含浮动快照、动画、持久化）
3. 窗口重命名绑定窗口实例（CGWindowID）

0 个 P0、0 个 P1（已修复 2 个）、4 个 P2（不阻塞）。代码质量经过 /simplify 三维审查，修复了 4 项问题。**验收通过。**
