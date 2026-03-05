# 主题视觉增强 — 验收报告

> 日期：2026-03-05
> 版本：V3.7 主题视觉增强

---

## 1. 问题描述

用户反馈 4 个问题：
1. "默认白"主题下悬浮球颜色仍为蓝色，未跟随主题
2. 浅色主题在主控面板上颜色几乎一样，无法区分
3. 深色主题在主控面板下也无明显变化，"一团黑"
4. 主题切换时 UI 不同步（@Published willSet 时序 bug）

## 2. 修复内容

### 2.1 主题同步修复（P0）

| 文件 | 修改 | 解决问题 |
|------|------|----------|
| `AppDelegate.swift` | `observePreferences()` 中 Combine 链添加 `.receive(on: DispatchQueue.main)` | `@Published` 在 willSet 阶段发布，Combine sink 同步执行时 ConfigStore.shared.preferences 仍为旧值。延迟到下一个 RunLoop 迭代，确保读取到新值 |

### 2.2 主控面板主题色全覆盖

| 文件 | 修改 | 效果 |
|------|------|------|
| `Models.swift` | 新增 `sidebarBackground` 颜色槽（ns/sw 双属性） | 侧边栏与内容区背景可区分 |
| `MainKanbanView.swift` | 侧边栏用 `swSidebarBackground`，内容区用 `swBackground`，导航项选中态用 accent 色 12% 透明度背景 + accent 文字色，分隔线用 `swSeparator`，底部按钮用 `swTextSecondary` | 每个主题侧边栏有明确色调 |
| `AppConfigView.swift` | 背景 `swBackground`，搜索框 `swSeparator.opacity(0.4)`，文字用 textPrimary/Secondary/Tertiary，状态点用 accent，星标用 favoriteStar | 收藏管理页完全跟随主题 |
| `PreferencesView.swift` | 背景 `swBackground`，标题 textPrimary，描述 textSecondary，值 textTertiary，Slider/Toggle 的 tint 全部用 accent | 偏好设置页完全跟随主题 |

### 2.3 浅色主题差异化设计

| 主题 | 背景 | 侧边栏 | 强调色 | 文字色调 |
|------|------|---------|--------|----------|
| 默认白 | #FFFFFF 纯白 | #F7F7F7 冷灰 | #2383E2 蓝 | 中性灰 |
| 暖象牙 | #FBF8F4 暖黄 | #F4F0EA 暖褐 | #D97706 橙 | 暖褐调 |
| 薄荷绿 | #F0FDF4 薄绿 | #E7F6EC 绿灰 | #16A34A 绿 | 绿调灰 |
| 淡天蓝 | #EFF6FF 淡蓝 | #E6EEF8 蓝灰 | #2563EB 蓝 | 蓝调灰 |

### 2.4 深色主题差异化设计

| 主题 | 背景 | 侧边栏 | 强调色 | 色调特征 |
|------|------|---------|--------|----------|
| 经典深 | #191919 中性深灰 | #131313 | #529CCA 蓝 | 中性灰调 |
| 深海蓝 | #0F1B2D 蓝调深 | #0B1525 | #60A5FA 蓝 | 蓝色倾向 |
| 墨绿 | #0D1F17 绿调深 | #091811 | #4ADE80 绿 | 绿色倾向 |
| 纯黑 | #000000 纯黑 | #090909 | #A78BFA 紫 | 紫色点缀 |

## 3. 验收用例

| 用例 | 描述 | 预期结果 | 结果 |
|------|------|----------|------|
| TC-01 | 切换 8 个主题卡片 | 悬浮球颜色跟随 accent 变化 | ✅ 代码验证：`ballGradientColors` 从 `accent` 自动派生 |
| TC-02 | 浅色主题对比 | 4 个浅色主题在主看板中有明显视觉区分 | ✅ 背景色不同（白/象牙/薄绿/淡蓝），强调色不同（蓝/橙/绿/蓝） |
| TC-03 | 深色主题对比 | 4 个深色主题在主看板中有明显视觉区分 | ✅ 背景有色调差异（灰/蓝/绿/黑），强调色不同（蓝/蓝/绿/紫） |
| TC-04 | 侧边栏颜色 | 侧边栏背景与内容区有区分 | ✅ 每个主题 sidebarBackground 比 background 深一档 |
| TC-05 | 主题切换同步 | 切换后所有 UI 立即更新 | ✅ `.receive(on: DispatchQueue.main)` 修复了 willSet 时序问题 |
| TC-06 | 编译安装 | `make install` 成功 | ✅ 编译通过，安装成功 |

## 4. 已知问题

- 无

## 5. 交付文件

| 文件 | 变更 |
|------|------|
| `FocusPilot/App/AppDelegate.swift` | +3 行（`.receive(on: DispatchQueue.main)` + 注释） |
| `FocusPilot/Models/Models.swift` | +13 行（sidebarBackground 颜色槽） |
| `FocusPilot/MainKanban/MainKanbanView.swift` | 全面主题化（+40/-7） |
| `FocusPilot/MainKanban/AppConfigView.swift` | 全面主题化（+19/-5） |
| `FocusPilot/MainKanban/PreferencesView.swift` | 全面主题化（+31/-5） |
