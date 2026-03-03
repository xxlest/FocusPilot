# Focus Copilot 性能测试报告

> 日期：2026-03-03 | 方法：运行时采集 + 静态代码分析

---

## 一、运行时性能数据

| 指标 | 值 | 评价 |
|------|------|------|
| 二进制大小 | 1.1 MB | 极轻量 |
| 启动 RSS | ~99 MB | 正常 |
| 稳态 RSS（数分钟） | ~106 MB | 正常 |
| 长期 RSS（数小时） | ~172 MB | ⚠️ 增长 66%，存在缓慢泄漏 |
| 空闲 CPU | 0.0% | 优秀，无不必要轮询 |
| 线程数 | 3~5（自动收缩） | 良好 |
| 文件描述符 | 36（新）→ 71（长期） | ⚠️ 翻倍增长 |

**关键发现**：
- 空闲性能优秀（0% CPU），说明定时器停止和呼吸动画暂停已生效
- 长时间运行后 RSS 从 99MB 增至 172MB（+73MB），文件描述符翻倍，**存在资源缓慢泄漏**

## 二、静态分析发现（按优先级排序）

### High（建议优化）

| # | 问题 | 位置 | 影响 | 优化方案 |
|---|------|------|------|----------|
| H1 | `refreshRunningApps()` 同步调用 AX API | AppMonitor:160 | App 启动/退出时主线程阻塞 50-200ms | 仅获取 CG 数据，AX 标题复用 `buildAXTitleMapAsync` 异步路径 |
| H2 | `refreshAllWindows()` 热循环中冗余系统调用 | AppMonitor:196 | 每 1-3s 对每个 App 调 `NSRunningApplication.runningApplications(withBundleIdentifier:)` | 改用 `app.nsApp?.isTerminated == false`，消除 N 次系统调用 |
| H3 | `scanInstalledApps()` 同步遍历文件系统 | AppMonitor:268 | 启动时主线程阻塞 100-500ms | 移至后台线程 |
| H4 | 两阶段刷新连续发两次 `windowsChanged` 通知 | AppMonitor:213+254 | 1-3s 内两次 UI 重建检查 | 合并去抖或 Phase 1 不发通知 |

### Medium（可选优化）

| # | 问题 | 位置 | 影响 | 优化方案 |
|---|------|------|------|----------|
| M1 | 收藏 Tab `runningApps.first(where:)` 线性查找 | QuickPanelView:408 | O(N*M) 每 1-3s | 预构建 `[bundleID: RunningApp]` 字典 |
| M2 | `buildStructuralKey()` 大量字符串拼接 | QuickPanelView:393 | 每 1-3s 生成数十个临时 String | 改用 hashValue 累加 |
| M3 | HotkeyRecorderButton 监听器泄漏 | PreferencesView:229 | 录制中切换 Tab 会泄漏 NSEvent 监听器 | `.onDisappear` 中清理 |
| M4 | `allCount`/`runningCount` 重复系统调用 | AppConfigView:103 | SwiftUI 渲染时多次调 `runningApplications` | 统一缓存 |
| M5 | `save()` 同步 7 次 JSON 编码 | ConfigStore:61 | `addApp`/`removeApp` 时主线程 I/O | 节流合并或后台 |

### Low（无需立即处理）

- symbolCache 只增不减（实际仅 ~10 个 key，可忽略）
- Logo 图像每次颜色变更重绘（频率极低）
- PermissionManager 可改为指数退避（当前开销可忽略）

## 三、资源管理审计

**资源管理整体优秀**：所有 Timer、Observer、TrackingArea 均有对应清理。

唯一风险点：
- `WindowService.logFileHandle` 无显式关闭（单例随进程退出，实际无影响）
- `HotkeyRecorderButton` NSEvent 监听器边缘泄漏（Medium 级别）

## 四、综合评价

| 维度 | 评分 | 说明 |
|------|:---:|------|
| 空闲性能 | A | 0% CPU，优化到位 |
| 内存效率 | B | 启动 99MB 合理，但长期增长至 172MB |
| 资源管理 | A- | Timer/Observer 全覆盖，仅一处边缘泄漏 |
| 代码复杂度 | B+ | 5546 行 17 文件，结构清晰 |
| 主线程安全 | B- | `refreshRunningApps`+`scanInstalledApps` 仍有同步阻塞 |
| 总体 | **B+** | 经过两轮优化后质量良好，剩余问题集中在 AppMonitor |
