# Coder-Bridge AI Tab V2 设计文档

## 概述

FocusPilot 快捷面板第三个 Tab「AI」，展示通过 coder-bridge 注册的 AI 编码工具会话。采用"目录分组 + Session 列表"结构，替代之前的平铺 session 列表。

### 核心原则

- **会话识别和窗口切换是两个独立问题**：`sessionID` 标识 Claude 会话（内容/状态），窗口切换依赖 `session → window` 绑定关系，二者不是同一概念
- **宁可不绑定，也不要绑错窗口**：自动 fallback 不能制造强绑定，只有用户手动绑定（`manualWindowID`）才有排他性
- **目录分组为一级结构**：同一个工作目录下的多个 Claude Code 实例自然归入同一组
- **session 列表纯运行时**：FocusPilot 重启后清空所有 session，等 coder-bridge 重新注册

---

## 1. 数据模型

### 1.1 CoderSession（运行时，不持久化）

```swift
struct CoderSession: Identifiable {
    let sessionID: String               // UUID，Claude 会话唯一标识，不是窗口 ID
    var tool: CoderTool                  // claude / codex / gemini
    var cwd: String                      // 工作目录（原始路径）
    var cwdNormalized: String            // 规范化路径（git repo root 优先，realpath 兜底）
    var hostApp: String                  // "cursor" / "terminal" / "iterm2" / ""
    var status: SessionStatus            // 业务态
    var lifecycle: SessionLifecycle      // 生命周期态
    var lastSeq: Int                     // 最后处理的 seq，防乱序
    var lastUpdate: Date
    var lastInteraction: Date?           // 用户点击此 session 的时间

    // 窗口绑定（运行时）
    var manualWindowID: CGWindowID?      // 用户手动绑定，优先级最高，失效时自动清空
    var resolvedWindowID: CGWindowID?    // 最近一次 fallback 解析结果（仅弱记录，不用于强占用仲裁）

    var id: String { sessionID }

    /// sessionID 前 8 位，UI 显示用
    var shortID: String {
        String(sessionID.prefix(8))
    }

    /// cwd 最后一级目录名
    var cwdBasename: String {
        let homePath = NSHomeDirectory()
        if cwd == homePath || cwd == homePath + "/" { return "~" }
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? "~" : name
    }

    /// 排序用时间：lastInteraction 优先，无则退回 lastUpdate
    var sortDate: Date {
        lastInteraction ?? lastUpdate
    }

    /// 排序档位：active 在前，ended 在后
    var sortTier: Int {
        lifecycle == .ended ? 2 : 1
    }

    /// 是否需要用户处理（用于 AI Tab 角标）
    var isActionable: Bool {
        switch (status, lifecycle) {
        case (.idle, .active),
             (.done, .active), (.done, .ended),
             (.error, .active), (.error, .ended):
            return true
        default:
            return false
        }
    }

    var statusText: String {
        let base: String
        switch status {
        case .registered: base = "已连接"
        case .working:    base = "执行中"
        case .idle:       base = "等待输入"
        case .done:       base = "已完成"
        case .error:      base = "出错"
        }
        return lifecycle == .ended ? "\(base) · 已结束" : base
    }

    func statusDotColor(theme: ThemeColors) -> NSColor {
        switch status {
        case .idle:       return theme.nsAccent
        case .done:       return .systemGreen
        case .error:      return .systemRed
        case .working:    return theme.nsAccent
        case .registered: return theme.nsAccent
        }
    }

    var statusDotHasGlow: Bool {
        switch status {
        case .idle, .done, .error: return true
        default: return false
        }
    }

    var rowAlpha: CGFloat {
        switch (status, lifecycle) {
        case (_, .active): return 1.0
        case (.done, .ended), (.error, .ended), (.working, .ended): return 0.7
        default: return 0.5
        }
    }
}
```

### 1.2 SessionGroup（运行时，由 CoderBridgeService 计算）

```swift
struct SessionGroup {
    let cwdNormalized: String    // 分组 key
    var displayName: String      // UI 显示名，默认 basename(cwdNormalized)
    var sessions: [CoderSession] // 该目录下的所有 session（已排序）
}
```

**同名目录消歧**：如果不同 `cwdNormalized` 的 `basename` 相同，补父级路径片段区分。例如两个 `app` 目录分别显示为 `app (frontend)` 和 `app (backend)`。

### 1.3 CoderSessionPreference（持久化，本轮不扩展）

```swift
struct CoderSessionPreference: Codable {
    let key: String
    var displayName: String
    var isPinned: Bool
}
```

本轮不动此结构，不扩展新用途。后续若需要项目级显示偏好再继续使用。

### 1.4 关键设计决策

- `sessionID` 是 Claude 会话身份，不是 macOS 窗口 ID
- `manualWindowID` 是用户确认的强绑定，有排他性（用于 occupiedWindowIDs）
- `resolvedWindowID` 仅记录最近一次 fallback 结果，**不用于强占用仲裁**，只用于调试和弱提示
- `isActionable` 和 `actionableCount` 保留，驱动 AI Tab 角标
- `isHidden` 已删除，不再支持隐藏会话

---

## 2. 状态机

（保持不变，参见 V1 文档 2.1-2.3 节）

状态流：
```
SessionStart → registered
UserPromptSubmit → working
Stop → done
Notification(idle_prompt) → idle
SessionEnd → lifecycle=ended
```

清理：ended 后 2 分钟自动移除，或用户右键手动移除。

---

## 3. IPC 协议

（保持不变，参见 V1 文档 3.1-3.4 节）

---

## 4. 窗口关联与匹配

### 4.1 核心语义

- 点击 session 行 = 尝试激活该 session 关联的窗口
- 点击的是 session（Claude 会话），不是窗口标题
- `sessionID` 保证内容/状态显示正确（通过 transcript 文件）
- 窗口切换依赖 `session → window` 绑定关系

### 4.2 绑定优先级

```
1. manualWindowID（用户手动绑定，优先级最高）
   - 失效时自动清空，降级到 fallback
2. fallback 匹配（自动，每次点击时执行）
   - 排除已被其他 session 的 manualWindowID 占用的窗口
   - cwd basename 匹配窗口标题 → .high（仅当唯一命中且未占用时）
   - 同宿主 App 只有一个未占用窗口 → .low
   - 多个未占用窗口无法区分 → .none
   - 全部候选已被占用 → .none
3. .none → 只激活宿主 App，提示用户手动绑定
```

### 4.3 占用检测规则

```swift
/// 只统计 active session 的 manualWindowID（手动绑定 = 强占用）
/// resolvedWindowID 不参与占用仲裁（自动猜测 ≠ 强占用）
var occupiedWindowIDs: Set<CGWindowID> {
    Set(sessions.compactMap { s in
        guard s.lifecycle == .active else { return nil }
        return s.manualWindowID
    })
}
```

### 4.4 手动绑定

- 右键 → "绑定到当前窗口"
- 获取当前前台窗口 + 确认对话框
- 冲突检测：如果目标窗口已被其他 session 的 `manualWindowID` 占用，提示并替换
- 绑定为 session 级临时状态，不持久化

---

## 5. AI Tab UI 设计

### 5.1 Tab 栏

```
┌─ 运行中 ─┬─ 关注 ─┬─ AI ─┐
│          │        │  (3) │   ← 角标 = actionableCount
└──────────┴────────┴──────┘
```

### 5.2 整体结构：目录分组 + Session 列表

```
┌─ AI Tab ────────────────────────────────────────┐
│ ▼ FocusPilot                                    │  ← 一级：目录组
│   ● Claude · a1b2c3d4 · Cursor · 执行中         │  ← 二级：session 行
│     "帮我修复编译错误..."                        │     第二行：query 摘要
│   ● Claude · e5f6g7h8 · iTerm2 · 等待输入       │
│     "分析窗口绑定逻辑"                           │
│                                                  │
│ ▼ MyBackend                                      │
│   ● Claude · 91ab44ef · Terminal · 已完成        │
│     "添加用户认证接口"                            │
└──────────────────────────────────────────────────┘
```

### 5.3 目录组行

```
┌─ HoverableRowView (高度 24px) ──────────────────┐
│ ▼ FocusPilot                              (2)   │
│ ↑       ↑                                  ↑    │
│ 折叠  目录名                          session 数 │
└──────────────────────────────────────────────────┘
```

- 点击折叠/展开该组
- 显示该组下的 session 数量
- 同名目录时补父级路径：`app (frontend/app)`

### 5.4 Session 行

```
┌─ HoverableRowView (高度 44px) ──────────────────┐
│ ● Claude · a1b2c3d4    Cursor     执行中        │  ← 第一行
│   "帮我修复编译错误..."                          │  ← 第二行：query 摘要
└──────────────────────────────────────────────────┘
```

**第一行组成**：
- 状态圆点（6px，颜色按 status）
- 工具名（"Claude" / "Codex" / "Gemini"）
- `·` 分隔符
- shortSessionID（前 8 位）
- 弹性间距
- hostApp 显示名（"Cursor" / "iTerm2" / "Terminal"）
- 状态文字（"执行中" / "等待输入" / ...）

**第二行**：
- 最近 query 摘要（从 transcript 提取）
- 没有 query 时显示 `等待输入...`
- 10pt，nsTextTertiary

**缩进**：session 行相对目录组行缩进 `Constants.Panel.windowIndent`（28px），和现有窗口行缩进一致。

### 5.5 排序

**组内排序**：
- active 在前，ended 在后
- 同档内按 `sortDate`（lastInteraction > lastUpdate）倒排

**组间排序**：
- 按组内最新 session 的 sortDate 倒排（最近活跃的项目组在上面）

### 5.6 右键菜单

```
绑定到当前窗口         ← session 级临时绑定 + 冲突确认
复制 Session ID
────
移除此会话             ← 仅 ended 时显示
移除所有已结束会话      ← 仅 ended 时显示
```

### 5.7 空状态

```
┌─────────────────────────────────┐
│                                 │
│    还没有 AI 编码会话           │
│    启动一个 AI 编码工具后       │
│    会自动显示在这里             │
│                                 │
└─────────────────────────────────┘
```

---

## 6. 与 V1 的差异总结

| 项目 | V1 | V2 |
|------|----|----|
| 一级结构 | 平铺 session 列表 | 按 cwdNormalized 分组 |
| session 行主标题 | cwdBasename（项目名） | Claude · shortID |
| 第二级信息 | Topic（用户编辑/自动） | 无（已删除 Topic） |
| 第三级信息 | Query 摘要 | Query 摘要（提升为第二行） |
| 隐藏会话 | 支持 | 已删除 |
| isActionable | 保留 | 保留 |
| 窗口占用检测 | 仅 manualWindowID | 仅 manualWindowID（明确 resolvedWindowID 不参与） |
| 自动初始绑定 | 已取消 | 已取消 |

---

## 7. 修改清单

| # | 改动 | 文件 | 说明 |
|---|------|------|------|
| 1 | CoderSession 清理 | CoderSession.swift | 删 topic/isHidden/initialCandidateWindowID/candidateWindowID/matchConfidence；加 resolvedWindowID/shortID |
| 2 | 新增 SessionGroup | CoderSession.swift | 分组结构体 |
| 3 | CoderBridgeService 分组逻辑 | CoderBridgeService.swift | 新增 groupedSessions 计算属性 + 同名消歧 |
| 4 | resolveWindowForSession 修正 | CoderBridgeService.swift | 排除 manualWindowID 占用 + 存 resolvedWindowID（弱记录）+ basename 唯一未占用时才 .high |
| 5 | buildAITabContent 改为分组 | QuickPanelView.swift | 目录组行 + session 列表 + 折叠 |
| 6 | createSessionRow 重写 | QuickPanelRowBuilder.swift | shortID + hostApp + status + query 摘要 |
| 7 | 右键菜单重写 | QuickPanelMenuHandler.swift | 绑定当前窗口 + 复制 Session ID + 移除 |
| 8 | 删除残留代码 | 多文件 | topic/isHidden/hideSession/unhideSession/editTopic/displayName 相关 |

---

## 8. 分期

### 本轮（V2 重构）

上述修改清单 #1-#8，一次性完成。

### P2（后续）

- Query 历史面板（右键 → 查看 Query 历史）
- Gemini / Codex adapter
- 宿主特定的强映射/强校验（P3）
