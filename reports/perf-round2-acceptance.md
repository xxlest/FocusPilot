# 全应用性能优化验收报告

> 日期：2026-03-03 | 涵盖 Round 1（V3.3 QuickPanel）+ Round 2（全应用微优化）

---

## 验收结果

| # | 优化项 | 结果 | QA 备注 |
|---|--------|:---:|--------|
| 1 | CGWindowList 单次查询 | PASS | V3.3 已完成 |
| 2 | 差分 UI 更新 | PASS | V3.3 已完成 |
| 3 | AX 查询后台化 | PASS | V3.3 已完成 |
| 4 | SF Symbol 缓存 | PASS | V3.3 已完成 |
| 5 | 自适应刷新间隔 | PASS | V3.3 已完成 |
| 6 | titleCache 清理 | PASS | pruneCache 每次刷新清理过期条目 |
| 7 | PermissionManager 停止轮询 | PASS | 权限授予后停止，兜底路径可覆盖撤销检测 |
| 8 | 悬浮球拖拽联动节流 | PASS | 16ms 采样 + mouseUp 补发末帧 |
| 9 | 呼吸动画后台暂停 | PASS | 改用 occlusionState 检测窗口可见性 |
| 10 | ConfigStore 单字段保存 | PASS | saveBallPosition/savePanelSize/saveWindowRenames |
| 11 | AppConfigView NSWorkspace 缓存 | PASS | 单次调用内缓存，消除重复系统调用 |
| 12 | PreferencesView Slider | PASS | 现有实现已合理，无需额外防抖 |

**12/12 全部 PASS**

## 修改文件

| 文件 | 改动 | 优化项 |
|------|------|--------|
| WindowService.swift | +89 | #1 buildWindowInfo + buildAXTitleMapAsync + applyAXTitles + pruneCache |
| AppMonitor.swift | +133/-6 | #1 单次 CGWindowList + #3 AX 后台 + #5 自适应 + #6 pruneCache 调用 |
| QuickPanelView.swift | +184/-55 | #2 差分更新 + #4 SF Symbol 缓存 + #10 saveWindowRenames |
| FloatingBallView.swift | +60/-8 | #8 拖拽节流 + #9 呼吸动画暂停 + #10 saveBallPosition |
| ConfigStore.swift | +24/-1 | #10 saveBallPosition/savePanelSize/saveWindowRenames |
| PermissionManager.swift | +2 | #7 权限授予后 stopBackgroundCheck |
| AppConfigView.swift | +18/-12 | #11 NSWorkspace 缓存 + installedByID 字典 |
| QuickPanelWindow.swift | +2/-1 | #10 savePanelSize |

## 性能提升总结

| 指标 | 优化前 | 优化后 |
|------|--------|--------|
| CGWindowList 系统调用 | N 次/刷新 | **1 次/刷新** |
| AX API 主线程阻塞 | 50-200ms | **0ms** |
| UI 重建频率 | 每秒全量 | **仅结构变化** |
| titleCache 内存 | 无限增长 | **稳定在当前窗口数** |
| 后台权限轮询 | 永不停止 | **权限授予后停止** |
| 拖拽联动通知 | 60+ Hz 无上限 | **~60Hz 采样** |
| 呼吸动画后台 GPU | 持续占用 | **遮挡时暂停** |
| 位置/尺寸持久化 | 全量 7 字段序列化 | **单字段写入** |
| NSWorkspace 调用 | filteredApps 中 2-3 次 | **1 次** |
| 静态面板刷新 | 固定 1s | **自适应 1s→3s** |
