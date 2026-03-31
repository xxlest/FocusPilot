# FocusPilot 设计规范

> **版本**：V4.2
> **日期**：2026-03-31
> **读者**：UI 修改、视觉调整、新增界面元素时必读

---

## 1. 设计基调与哲学

### 核心基调：干净 · 高级 · 克制 · 专业

FocusPilot 追求 **macOS 原生级精致 UI**，像系统自带应用一样自然融入桌面。
设计上宁可少做，不可过度——每一个像素、每一帧动画都应有明确理由，拒绝装饰性元素。

### 产品哲学：专注 × 禅意

品牌灵魂来自禅圆（Enso）——一笔未闭合的弧线，画在悬浮的渐变球体上。
传递「一期一会的专注」「循环而非封闭」「柔和过渡」三层含义。
所有 UI 决策围绕「专注、轻量、不打断」展开。

---

## 2. 品牌图标设计：禅圆（Enso）

### 2.1 图标构成

图标由两个核心元素叠加而成：

1. **底层：渐变球体** — 蓝色径向渐变圆球，带有左上高光和底部暗影，营造出立体的「悬浮球」质感
2. **上层：禅圆 Enso** — 一条白色未闭合弧线（300 度），从起笔墨滴开始，笔触由粗渐细，尾部以三个渐隐散点收束

### 2.2 与 FocusPilot 的寓意关联

| 元素 | 寓意 |
|---|---|
| **禅圆** | 专注当下——一笔挥就，不可重来，正如番茄钟要求沉浸在当前时段 |
| **未闭合弧（300°）** | 循环但不封闭——每一轮专注都有起点和终点，但不是死循环，而是螺旋上升 |
| **笔触从粗到细** | 能量的自然消耗——从全神贯注到柔和收尾，而非戛然而止 |
| **起笔墨滴** | 启动的决心——每次点击「开始专注」时的果断投入 |
| **收笔散点（三个渐隐）** | 优雅的过渡——对应 FocusPilot 中弹窗提示、pending 状态的柔和过渡设计 |
| **悬浮球体** | 常驻陪伴——始终悬浮在屏幕边缘的小球，随时待命 |

### 2.3 技术实现

- 图标生成脚本：`scripts/gen-icon.swift`
- 悬浮球绘制：`FocusPilot/FloatingBall/FloatingBallView.swift` 中的 `createBrandLogoImage` 方法
- **修改时两处必须同步**，确保悬浮球与 App 图标视觉统一

### 2.4 绘制参数

| 参数 | 值 | 说明 |
|---|---|---|
| 弧线角度 | 300° | 起点到终点，留 60° 缺口 |
| 最大笔宽 | `size * 0.09` | 起笔粗度 |
| 最小笔宽 | `size * 0.02` | 收笔细度 |
| 透明度范围 | 0.88 → 0.73 | 从起笔到收笔渐降 |
| 缓出曲线 | `1.0 - pow(1.0 - t, 2.0)` | 模拟毛笔力度变化 |
| 墨滴半径 | `size * 0.07` | 起始墨滴 |
| 散点半径 | 0.042 → 0.030 → 0.020 | 三个渐隐收笔散点 |
| 散点透明度 | 0.65 → 0.42 → 0.22 | 渐隐效果 |

---

## 3. 视觉准则

### 3.1 克制用色

Notion 风格 8 色主题（浅 4 + 深 4），每主题 9 色槽覆盖全 UI。accent 仅用于关键操作和状态指示，大面积留白/留灰，不滥用彩色。

### 3.2 原生质感

毛玻璃（NSVisualEffectView）、系统动画曲线（ease-out/ease-in）、SF Symbols，不引入自定义图标库。

### 3.3 层次分明

textPrimary / textSecondary / textTertiary 三级文字层次严格区分，信息权重一目了然。

### 3.4 精致细节

悬浮球径向渐变 + 高光 + 暗区 + 内边缘光 + accent 呼吸光晕；hover 缩放 1.06x；贴边吸附动画——细节服务于高级感，而非炫技。

---

## 4. Notion 风格主题系统

### 4.1 主题概览

| 主题 | rawValue | 类型 | Accent 色 | 适用场景 |
|---|---|---|---|---|
| defaultWhite | 默认白 | 浅色 | `#E53935` 红 | 默认主题，高对比度 |
| warmIvory | 暖象牙 | 浅色 | `#D97706` 暖金 | 温暖文艺感 |
| mintGreen | 薄荷绿 | 浅色 | `#16A34A` 绿 | 清新自然 |
| lightBlue | 淡天蓝 | 浅色 | `#2563EB` 蓝 | 专业冷静 |
| classicDark | 经典深 | 深色 | `#529CCA` 亮蓝 | 经典暗色 |
| deepOcean | 深海蓝 | 深色 | `#60A5FA` 海洋蓝 | 深邃沉浸 |
| inkGreen | 墨绿 | 深色 | `#4ADE80` 亮绿 | 护眼长时间使用 |
| pureBlack | 纯黑 | 深色 | `#A78BFA` 薰衣草紫 | OLED 省电 |

### 4.2 ThemeColors 9 色槽

每个主题通过 `ThemeColors` 结构体提供 9 个语义色槽，同时提供 `ns*`（NSColor）和 `sw*`（SwiftUI Color）双套属性：

| 色槽 | 语义 | 用途 |
|---|---|---|
| background | 主背景 | 面板、窗口背景 |
| sidebarBackground | 侧边栏背景 | 主看板侧边栏 |
| accent | 强调色 | 按钮、活跃状态、悬浮球渐变 |
| textPrimary | 一级文字 | 标题、App 名称 |
| textSecondary | 二级文字 | 副标题、窗口标题 |
| textTertiary | 三级文字 | 辅助信息、时间戳 |
| rowHighlight | 行高亮 | hover/选中行背景（accent@8%浅色/@12%深色） |
| separator | 分隔线 | Tab 分隔、区域分隔 |
| favoriteStar | 关注星号 | 已关注=金色 `#F2C40F`，所有主题统一 |

### 4.3 各主题色值表

**浅色主题**

| 色槽 | defaultWhite | warmIvory | mintGreen | lightBlue |
|---|---|---|---|---|
| background | `#FFFFFF` | `#FBF8F4` | `#F0FDF4` | `#EFF6FF` |
| sidebarBg | `#F7F7F7` | `#F4F0EA` | `#E7F6EC` | `#E6EEF8` |
| accent | `#E53935` | `#D97706` | `#16A34A` | `#2563EB` |
| textPrimary | `#252525` | `#2E2924` | `#1A2E1F` | `#1A2438` |
| textSecondary | `#747474` | `#7A7066` | `#4D7057` | `#4D6180` |
| textTertiary | `#A0A0A0` | `#A6998F` | `#7A9985` | `#7A8CA6` |
| rowHighlight | accent@8% | accent@8% | accent@8% | accent@8% |
| separator | `#E5E5E5` | `#E0D9CC` | `#CCE6D6` | `#D1DEF0` |

**深色主题**

| 色槽 | classicDark | deepOcean | inkGreen | pureBlack |
|---|---|---|---|---|
| background | `#1C1C1E` | `#0F1B2D` | `#0D1F17` | `#000000` |
| sidebarBg | `#131313` | `#0B1525` | `#091811` | `#0C0C0C` |
| accent | `#529CCA` | `#60A5FA` | `#4ADE80` | `#A78BFA` |
| textPrimary | `#E6E6E6` | `#E0EBF5` | `#E0F2E6` | `#EBEBF2` |
| textSecondary | `#999999` | `#8094AD` | `#809E8A` | `#9494A1` |
| textTertiary | `#6B6B6B` | `#596B85` | `#597566` | `#666670` |
| rowHighlight | accent@12% | accent@12% | accent@12% | accent@12% |
| separator | `#383838` | `#24334D` | `#1F3829` | `#29292E` |

### 4.4 主题刷新链路

```
PreferencesView → @Published → AppDelegate.applyPreferences()
  → NSApp.appearance 更新（浅色/深色）
  → ballView.updateColorStyle()（悬浮球渐变从 accent 派生）
  → quickPanelWindow.applyTheme()（背景+毛玻璃+叠加层）
  → panelView.forceReload()（全量重建 UI）
  → post themeChanged 通知（FloatingBall 等监听者响应）
```

### 4.5 悬浮球颜色派生

悬浮球渐变色由 `AppTheme.ballGradientColors` 从 accent 自动派生：
- `light` = accent.blended(withFraction: 0.3, of: .white)
- `medium` = accent
- `dark` = accent.blended(withFraction: 0.4, of: .black)

---

## 5. 交互原则

### 5.1 非侵入

悬浮球常驻但不抢焦点（nonactivating NSPanel），面板 hover 弹出 / 离开收起，钉住才持久。

### 5.2 三层递进

悬浮球（零信息，纯入口）→ 快捷面板（紧凑列表，操作为主）→ 主看板（完整配置），信息密度逐层递增。

### 5.3 不打断工作流

弹窗失焦自动关闭（`didResignActiveNotification` → `abortModal`），PendingAction 保留上下文，回来后一键继续。

### 5.4 一致性

同一主题下 AppKit + SwiftUI 颜色统一，通过 ThemeColors ns*/sw* 双套桥接。

---

## 6. 动画规范

### 6.1 Design Token（Constants.Design.Anim）

| Token | 时长 | 用途 |
|---|---|---|
| micro | 0.1s | hover 色变、步骤切换文案渐变 |
| fast | 0.15s | 悬浮球 hover 缩放反馈 |
| normal | 0.25s | 面板展开/收起、折叠/展开 |

### 6.2 面板动画

| 动画 | 时长 | 曲线 | 说明 |
|---|---|---|---|
| 弹出 | 250ms | ease-out | 从悬浮球方向缩放+滑出+淡入 |
| 收起 | 120ms | ease-in | 淡出 |
| hover 延迟 | 150ms | — | 悬浮球 hover 到面板弹出的等待时间 |
| 离开延迟 | 500ms | — | 鼠标离开到面板收起的等待时间 |

### 6.3 悬浮球动画

| 动画 | 参数 | 说明 |
|---|---|---|
| hover 缩放 | 1.06x, fast (0.15s) | 鼠标悬浮时微缩放 |
| 贴边吸附 | normal (0.25s), ease-out | 拖拽结束后吸附到最近边缘 |
| 钉住发光环 | 脉冲动画，持续 | 红色发光边框环 |
| accent 光晕 | 常驻 | 从 accent 色派生的阴影光晕 |

---

## 7. 间距规范

### 7.1 间距 Token（Constants.Design.Spacing）

| Token | 数值 | 用途 |
|---|---|---|
| xs | 4pt | 图标与文字间距、紧凑元素间隔 |
| sm | 8pt | 行内元素间距、按钮内边距 |
| md | 12pt | 区域间距、卡片内边距 |
| lg | 16pt | 模块间距 |
| xl | 24pt | 大区域分隔 |

### 7.2 圆角 Token（Constants.Design.Corner）

| Token | 数值 | 用途 |
|---|---|---|
| sm | 4pt | 图标、小元素 |
| md | 6pt | 行、按钮 |
| lg | 10pt | 卡片、弹窗内组件 |
| xl | 14pt | 面板、窗口 |

### 7.3 面板尺寸规格

| 属性 | 值 |
|---|---|
| 默认宽度 | 280px |
| 宽度范围 | 180-500px |
| 默认高度 | 400px |
| 最小高度 | 200px |
| 最大高度 | 屏幕 60% |
| App 行高 | 28px |
| 窗口行高 | 24px |
| 窗口缩进 | 28px |
| 顶部栏高度 | 32px |
| 计时器栏高度 | 46px |
| 面板圆角 | 14px |

---

## 8. 修改时必须遵守的规则

1. **配色**：新增 UI 元素必须使用 ThemeColors 取色，禁止硬编码颜色值，确保 8 主题视觉一致
2. **动画**：参照 `Constants.Design.Anim`（micro/fast/normal），节奏统一，禁止花哨过渡
3. **间距**：参照 `Constants.Design.Spacing`（xs/sm/md/lg/xl），避免随意数值
4. **图标一致**：悬浮球视觉修改必须同步 `FloatingBallView.createBrandLogoImage` 和 `scripts/gen-icon.swift`
5. **弹窗规范**：新增弹窗默认添加失焦自动关闭（`didResignActiveNotification` → `abortModal`）
6. **克制原则**：不加装饰性阴影、不加多余分割线、不加无意义动画，每个元素都应能回答"为什么需要它"
