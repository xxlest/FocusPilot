# AI Tab 任务看板实施规划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在快捷面板 AI Tab 项目文件夹下嵌入任务看板，以 `todo.md` 为唯一数据源，支持状态流转、复制到 AI 执行、删除条目。

**Architecture:** 新增 `TodoService` 单例负责 todo.md 解析和写回。UI 层在 `QuickPanelRowBuilder` 新增三种行构建方法。通过 mtime 纳入 `buildStructuralKey()` 实现外部修改感知。

**Tech Stack:** Swift 5, AppKit, NSStackView, FileManager, NSPasteboard

**设计文档:** `docs/superpowers/specs/2026-03-30-todo-kanban-design.md`

---

## 文件结构

| 文件 | 操作 | 职责 |
|------|------|------|
| `FocusPilot/Services/TodoService.swift` | 新建 | TodoStatus / TodoItem / TodoFile 模型 + 解析 / 写回 / 剪贴板 / 打开编辑器 |
| `FocusPilot/Helpers/Constants.swift` | 修改 | 新增 `Panel.todoIndent` 常量 |
| `FocusPilot/QuickPanel/QuickPanelView.swift` | 修改 | 折叠状态变量、buildStructuralKey mtime、buildAITabContent 集成 |
| `FocusPilot/QuickPanel/QuickPanelRowBuilder.swift` | 修改 | createTodoFoldRow / createTodoItemRow / createDoneSummaryRow |

---

### Task 1: TodoService — 数据模型 + 解析器

**Files:**
- Create: `FocusPilot/Services/TodoService.swift`

- [ ] **Step 1: 创建 TodoService.swift，定义数据模型和解析器**

```swift
import AppKit

// MARK: - 数据模型

enum TodoStatus: String {
    case todo
    case inProgress
    case done

    var dotColor: NSColor {
        switch self {
        case .todo: return .systemYellow
        case .inProgress: return .systemGreen
        case .done: return .systemGray
        }
    }

    var next: TodoStatus {
        switch self {
        case .todo: return .inProgress
        case .inProgress: return .done
        case .done: return .todo
        }
    }

    /// 匹配 ## 标题文字 → status
    static func from(sectionTitle: String) -> TodoStatus? {
        switch sectionTitle.trimmingCharacters(in: .whitespaces) {
        case "Todo": return .todo
        case "In Progress": return .inProgress
        case "Done": return .done
        default: return nil
        }
    }

    var sectionTitle: String {
        switch self {
        case .todo: return "## Todo"
        case .inProgress: return "## In Progress"
        case .done: return "## Done"
        }
    }
}

struct TodoItem {
    let title: String
    let content: String?        // 缩进块文字，nil 表示无内容
    let status: TodoStatus
    let sectionIndex: Int       // 同 section 内出现顺序
    let fingerprint: String     // title + "\n" + (content ?? "")

    /// 写入 todo.md 时的完整文本块（标题行 + 内容行）
    var rawLines: [String] {
        let checkbox = status == .done ? "- [x] " : "- [ ] "
        var lines = [checkbox + title]
        if let content = content {
            for line in content.components(separatedBy: "\n") {
                lines.append("  " + line)
            }
        }
        return lines
    }
}

struct TodoFile {
    let items: [TodoItem]
    let path: String

    var todoItems: [TodoItem] { items.filter { $0.status == .todo } }
    var inProgressItems: [TodoItem] { items.filter { $0.status == .inProgress } }
    var doneItems: [TodoItem] { items.filter { $0.status == .done } }
    var activeItems: [TodoItem] { items.filter { $0.status != .done } }

    var doneCount: Int { doneItems.count }
    var activeCount: Int { activeItems.count }
    var totalCount: Int { items.count }

    /// 进度摘要文字："2/5"（activeCount 已完成 / totalCount）
    var progressSummary: String { "\(doneCount)/\(totalCount)" }
}

// MARK: - TodoService

class TodoService {
    static let shared = TodoService()
    private init() {}

    /// 解析指定目录的 todo.md，每次都重新读取文件
    func parse(cwd: String) -> TodoFile? {
        let path = (cwd as NSString).appendingPathComponent("todo.md")
        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        let lines = text.components(separatedBy: "\n")
        var items: [TodoItem] = []
        var currentStatus: TodoStatus? = nil
        var sectionCounters: [TodoStatus: Int] = [.todo: 0, .inProgress: 0, .done: 0]

        var i = 0
        while i < lines.count {
            let line = lines[i]

            // 检测 ## 标题行
            if line.hasPrefix("## ") {
                let title = String(line.dropFirst(3))
                if let status = TodoStatus.from(sectionTitle: title) {
                    currentStatus = status
                }
                i += 1
                continue
            }

            // 检测任务标题行：- [ ] 或 - [x]
            guard let status = currentStatus,
                  (line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ")) else {
                i += 1
                continue
            }

            let isChecked = line.hasPrefix("- [x] ")
            let title = String(line.dropFirst(6))

            // 收集紧接的缩进内容行
            var contentLines: [String] = []
            var j = i + 1
            while j < lines.count {
                let nextLine = lines[j]
                // 缩进行：以 2+ 空格开头，且不为空
                if nextLine.hasPrefix("  ") && !nextLine.trimmingCharacters(in: .whitespaces).isEmpty {
                    // 去掉前导 2 空格
                    contentLines.append(String(nextLine.dropFirst(2)))
                    j += 1
                } else if nextLine.trimmingCharacters(in: .whitespaces).isEmpty {
                    // 空行：检查下一行是否还是缩进内容
                    if j + 1 < lines.count && lines[j + 1].hasPrefix("  ") {
                        j += 1
                    } else {
                        break
                    }
                } else {
                    break
                }
            }

            let content = contentLines.isEmpty ? nil : contentLines.joined(separator: "\n")
            let fingerprint = title + "\n" + (content ?? "")
            let idx = sectionCounters[status, default: 0]
            sectionCounters[status] = idx + 1

            items.append(TodoItem(
                title: title,
                content: content,
                status: status,
                sectionIndex: idx,
                fingerprint: fingerprint
            ))

            i = j
        }

        return TodoFile(items: items, path: path)
    }

    /// 获取 todo.md 的 mtime（用于 structural key），文件不存在返回 0
    func mtime(cwd: String) -> TimeInterval {
        let path = (cwd as NSString).appendingPathComponent("todo.md")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let date = attrs[.modificationDate] as? Date else {
            return 0
        }
        return date.timeIntervalSince1970
    }
}
```

- [ ] **Step 2: 编译验证**

Run: `make build`
Expected: 编译成功，无错误

- [ ] **Step 3: Commit**

```bash
git add FocusPilot/Services/TodoService.swift
git commit -m "feat(todo): 新增 TodoService — 数据模型 + todo.md 解析器"
```

---

### Task 2: TodoService — 写回操作（状态流转 + 删除）

**Files:**
- Modify: `FocusPilot/Services/TodoService.swift`

- [ ] **Step 1: 在 TodoService 中添加条目匹配和写回方法**

在 `TodoService` 类的 `mtime()` 方法之后追加：

```swift
    // MARK: - 写回操作

    /// 在 file 中找到与 item 匹配的条目（fingerprint + status + sectionIndex）
    private func findMatchingItem(_ item: TodoItem, in file: TodoFile) -> TodoItem? {
        let candidates = file.items.filter { $0.status == item.status && $0.fingerprint == item.fingerprint }
        if candidates.count == 1 { return candidates[0] }
        // 多个同 fingerprint 的条目，用 sectionIndex 区分
        return candidates.first(where: { $0.sectionIndex == item.sectionIndex })
    }

    /// 循环切换任务状态，写回文件
    /// - Returns: 操作是否成功
    @discardableResult
    func cycleStatus(item: TodoItem, cwd: String) -> Bool {
        guard let file = parse(cwd: cwd),
              let matched = findMatchingItem(item, in: file) else {
            return false
        }

        let targetStatus = matched.status.next
        let newItem = TodoItem(
            title: matched.title,
            content: matched.content,
            status: targetStatus,
            sectionIndex: 0, // 追加到目标 section 末尾
            fingerprint: matched.fingerprint
        )

        return rewriteFile(file: file, removing: matched, inserting: newItem)
    }

    /// 从文件中删除任务条目
    @discardableResult
    func deleteItem(_ item: TodoItem, cwd: String) -> Bool {
        guard let file = parse(cwd: cwd),
              let matched = findMatchingItem(item, in: file) else {
            return false
        }

        return rewriteFile(file: file, removing: matched, inserting: nil)
    }

    /// 核心写回逻辑：从文件移除一条任务，可选地追加到新 section
    private func rewriteFile(file: TodoFile, removing: TodoItem, inserting: TodoItem?) -> Bool {
        guard let data = FileManager.default.contents(atPath: file.path),
              let text = String(data: data, encoding: .utf8) else {
            return false
        }

        var lines = text.components(separatedBy: "\n")

        // 1. 定位并移除原条目
        let removeResult = removeTodoLines(from: &lines, matching: removing)
        guard removeResult else { return false }

        // 2. 如果需要插入新条目，追加到目标 section 末尾
        if let newItem = inserting {
            let targetSection = newItem.status.sectionTitle
            insertTodoLines(into: &lines, item: newItem, targetSection: targetSection)
        }

        // 3. 写回文件
        let output = lines.joined(separator: "\n")
        do {
            try output.write(toFile: file.path, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    /// 从 lines 中移除匹配条目的标题行 + 缩进内容行
    private func removeTodoLines(from lines: inout [String], matching item: TodoItem) -> Bool {
        let checkbox = item.status == .done ? "- [x] " : "- [ ] "
        let targetLine = checkbox + item.title

        // 找到匹配的行（同 section 内第 sectionIndex 个匹配）
        var currentSection: TodoStatus? = nil
        var matchCount = 0

        for i in 0..<lines.count {
            let line = lines[i]
            if line.hasPrefix("## ") {
                let title = String(line.dropFirst(3))
                currentSection = TodoStatus.from(sectionTitle: title)
            }
            if currentSection == item.status && line == targetLine {
                if matchCount == item.sectionIndex {
                    // 找到目标行，计算要删除的范围
                    var endIdx = i + 1
                    while endIdx < lines.count {
                        let nextLine = lines[endIdx]
                        if nextLine.hasPrefix("  ") && !nextLine.trimmingCharacters(in: .whitespaces).isEmpty {
                            endIdx += 1
                        } else if nextLine.trimmingCharacters(in: .whitespaces).isEmpty {
                            // 空行：如果下一行还是缩进内容则继续，否则吃掉这个空行后停止
                            if endIdx + 1 < lines.count && lines[endIdx + 1].hasPrefix("  ") {
                                endIdx += 1
                            } else {
                                endIdx += 1 // 吃掉尾部空行
                                break
                            }
                        } else {
                            break
                        }
                    }
                    lines.removeSubrange(i..<endIdx)
                    return true
                }
                matchCount += 1
            }
        }
        return false
    }

    /// 将新条目追加到目标 section 末尾；section 不存在时在文件末尾创建
    private func insertTodoLines(into lines: inout [String], item: TodoItem, targetSection: String) {
        let newLines = item.rawLines

        // 查找目标 section 的末尾位置
        var sectionStart: Int? = nil
        for i in 0..<lines.count {
            if lines[i] == targetSection {
                sectionStart = i
                break
            }
        }

        if let start = sectionStart {
            // 找到 section 末尾（下一个 ## 或文件结尾）
            var insertAt = start + 1
            while insertAt < lines.count {
                if lines[insertAt].hasPrefix("## ") { break }
                insertAt += 1
            }
            // 回退过尾部空行
            while insertAt > start + 1 && lines[insertAt - 1].trimmingCharacters(in: .whitespaces).isEmpty {
                insertAt -= 1
            }
            // 插入新条目 + 空行分隔
            var toInsert = newLines
            toInsert.append("")
            lines.insert(contentsOf: toInsert, at: insertAt)
        } else {
            // section 不存在，在文件末尾追加
            if let last = lines.last, !last.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append("")
            }
            lines.append(targetSection)
            lines.append(contentsOf: newLines)
            lines.append("")
        }
    }

    // MARK: - 复制与打开

    /// 获取复制到 AI 执行的内容：有内容返回内容，无内容返回标题
    func copyContent(for item: TodoItem) -> String {
        return item.content ?? item.title
    }

    /// 复制内容到剪贴板
    func copyToPasteboard(item: TodoItem) {
        let text = copyContent(for: item)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// 在编辑器中打开 todo.md
    func openInEditor(cwd: String) {
        let path = (cwd as NSString).appendingPathComponent("todo.md")
        let fileURL = URL(fileURLWithPath: path)

        // 优先查找该项目下 hostKind == .ide 的 session 宿主窗口
        let ideSessions = CoderBridgeService.shared.sessions.filter {
            $0.cwdNormalized == cwd && $0.lifecycle == .active && $0.hostKind == .ide
        }

        if let ideSession = ideSessions.first {
            let (windowID, confidence) = CoderBridgeService.shared.resolveWindowForSession(ideSession)
            if let wid = windowID, confidence == .high {
                let allWindows = AppMonitor.shared.runningApps.flatMap { $0.windows }
                if let windowInfo = allWindows.first(where: { $0.id == wid }) {
                    WindowService.shared.activateWindow(windowInfo)
                    return
                }
            }
        }

        // 无 IDE 宿主窗口，用系统默认编辑器打开
        NSWorkspace.shared.open(fileURL)
    }
```

- [ ] **Step 2: 编译验证**

Run: `make build`
Expected: 编译成功

- [ ] **Step 3: Commit**

```bash
git add FocusPilot/Services/TodoService.swift
git commit -m "feat(todo): TodoService 写回操作 — 状态流转/删除/复制/打开编辑器"
```

---

### Task 3: Constants — 新增 todoIndent 常量

**Files:**
- Modify: `FocusPilot/Helpers/Constants.swift:28-29`

- [ ] **Step 1: 在 Panel 枚举中添加 todoIndent**

在 `Constants.swift` 的 `Panel` 枚举内，`windowIndent` 行之后追加：

```swift
        static let todoIndent: CGFloat = 44           // 任务条目缩进（比 windowIndent 多一级）
```

即在第 29 行 `static let windowIndent: CGFloat = 28` 之后插入。

- [ ] **Step 2: 编译验证**

Run: `make build`
Expected: 编译成功

- [ ] **Step 3: Commit**

```bash
git add FocusPilot/Helpers/Constants.swift
git commit -m "feat(todo): 新增 Constants.Panel.todoIndent (44px)"
```

---

### Task 4: QuickPanelView — 折叠状态 + structural key mtime

**Files:**
- Modify: `FocusPilot/QuickPanel/QuickPanelView.swift:29` (collapsedGroups 附近)
- Modify: `FocusPilot/QuickPanel/QuickPanelView.swift:1734-1741` (buildStructuralKey .ai case)

- [ ] **Step 1: 在 QuickPanelView 中添加折叠状态变量**

在 `QuickPanelView.swift` 第 29 行 `var collapsedGroups: Set<String> = []` 之后追加两行：

```swift
    var collapsedTodoGroups: Set<String> = []   // 任务区折叠状态（默认折叠）
    var collapsedDoneGroups: Set<String> = []   // Done 区折叠状态（默认折叠）
```

注意：默认为空集 = 默认折叠（逻辑是"不在展开集合中 → 折叠"，与 `collapsedGroups` 相反）。为保持语义清晰，改用正向命名：

```swift
    var expandedTodoGroups: Set<String> = []    // 任务区展开状态（默认折叠）
    var expandedDoneGroups: Set<String> = []    // Done 区展开状态（默认折叠）
```

- [ ] **Step 2: 修改 buildStructuralKey() 的 .ai case，纳入 todo.md mtime**

找到 `QuickPanelView.swift` 中 `buildStructuralKey()` 方法的 `.ai` case（约第 1734 行）：

```swift
        case .ai:
            // 直接用 sessions 构建 key，不调用 groupedSessions 避免重复计算
            let sessionKeys = CoderBridgeService.shared.sessions
                .map { "\($0.cwdNormalized):\($0.sessionID):\($0.status.rawValue):\($0.lifecycle.rawValue)" }
                .sorted()
                .joined(separator: "|")
            let collapsed = collapsedGroups.sorted().joined(separator: ",")
            parts.append("AI:\(sessionKeys):C:\(collapsed)")
```

替换为：

```swift
        case .ai:
            let sessionKeys = CoderBridgeService.shared.sessions
                .map { "\($0.cwdNormalized):\($0.sessionID):\($0.status.rawValue):\($0.lifecycle.rawValue)" }
                .sorted()
                .joined(separator: "|")
            let collapsed = collapsedGroups.sorted().joined(separator: ",")
            // todo.md mtime 纳入 key，外部修改时触发全量重建
            let cwds = Set(CoderBridgeService.shared.sessions.map { $0.cwdNormalized })
            let todoMtimes = cwds.sorted().map { "\($0):\(TodoService.shared.mtime(cwd: $0))" }.joined(separator: ",")
            parts.append("AI:\(sessionKeys):C:\(collapsed):T:\(todoMtimes)")
```

- [ ] **Step 3: 编译验证**

Run: `make build`
Expected: 编译成功

- [ ] **Step 4: Commit**

```bash
git add FocusPilot/QuickPanel/QuickPanelView.swift
git commit -m "feat(todo): 折叠状态变量 + buildStructuralKey 纳入 todo.md mtime"
```

---

### Task 5: QuickPanelRowBuilder — 任务折叠行 + 任务条目行 + Done 摘要行

**Files:**
- Modify: `FocusPilot/QuickPanel/QuickPanelRowBuilder.swift` (文件末尾追加)

- [ ] **Step 1: 在 QuickPanelRowBuilder.swift 末尾（extension QuickPanelView 内）追加三个行构建方法**

在文件末尾的 `}` 之前追加：

```swift
    // MARK: - Todo Kanban Rows

    /// 任务折叠行：📋 任务 2/5 ✎
    func createTodoFoldRow(todoFile: TodoFile, cwdNormalized: String, isExpanded: Bool) -> HoverableRowView {
        let theme = ConfigStore.shared.currentThemeColors
        let row = HoverableRowView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: Constants.Panel.appRowHeight).isActive = true

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = Constants.Design.Spacing.sm
        stack.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: Constants.Panel.windowIndent),
            stack.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -Constants.Design.Spacing.sm),
            stack.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])

        // 折叠箭头
        let chevronName = isExpanded ? "chevron.down" : "chevron.right"
        if let img = Self.cachedSymbol(name: chevronName, size: 9, weight: .medium) {
            let chevron = NSImageView(image: img)
            chevron.contentTintColor = theme.nsTextTertiary
            chevron.translatesAutoresizingMaskIntoConstraints = false
            chevron.widthAnchor.constraint(equalToConstant: 12).isActive = true
            chevron.heightAnchor.constraint(equalToConstant: 12).isActive = true
            stack.addArrangedSubview(chevron)
        }

        // 📋 图标
        if let img = Self.cachedSymbol(name: "checklist", size: 11, weight: .regular) {
            let icon = NSImageView(image: img)
            icon.contentTintColor = theme.nsTextSecondary
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.widthAnchor.constraint(equalToConstant: 14).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 14).isActive = true
            stack.addArrangedSubview(icon)
        }

        // "任务" 标签
        let label = createLabel("任务", size: 12, color: theme.nsTextSecondary)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(label)

        stack.addArrangedSubview(createSpacer())

        // 进度摘要 "2/5"
        let progress = createLabel(todoFile.progressSummary, size: 11, color: theme.nsTextTertiary)
        progress.setContentCompressionResistancePriority(.required, for: .horizontal)
        stack.addArrangedSubview(progress)

        // ✎ 打开编辑器按钮
        if let editImg = Self.cachedSymbol(name: "pencil", size: 10, weight: .regular) {
            let editBtn = NSImageView(image: editImg)
            editBtn.contentTintColor = theme.nsTextTertiary.withAlphaComponent(0.35)
            editBtn.translatesAutoresizingMaskIntoConstraints = false
            editBtn.widthAnchor.constraint(equalToConstant: 14).isActive = true
            editBtn.heightAnchor.constraint(equalToConstant: 14).isActive = true

            // 用点击手势处理 ✎ 按钮
            let editClickView = NSView()
            editClickView.translatesAutoresizingMaskIntoConstraints = false
            editClickView.addSubview(editBtn)
            NSLayoutConstraint.activate([
                editBtn.centerXAnchor.constraint(equalTo: editClickView.centerXAnchor),
                editBtn.centerYAnchor.constraint(equalTo: editClickView.centerYAnchor),
                editClickView.widthAnchor.constraint(equalToConstant: 20),
                editClickView.heightAnchor.constraint(equalToConstant: 20),
            ])
            stack.addArrangedSubview(editClickView)

            // ✎ 点击事件通过行的 contextMenuProvider 不合适，改用 clickHandler 内位置判断
            // 这里只做视觉展示，✎ 的点击在 row.clickHandler 中通过 hitTest 区域判断
        }

        // 折叠/展开点击
        let cwd = cwdNormalized
        row.clickHandler = { [weak self] in
            if self?.expandedTodoGroups.contains(cwd) == true {
                self?.expandedTodoGroups.remove(cwd)
            } else {
                self?.expandedTodoGroups.insert(cwd)
            }
            self?.forceReload()
        }

        return row
    }

    /// 任务条目行：● 标题 ▶ ✕
    func createTodoItemRow(item: TodoItem, cwdNormalized: String, isDone: Bool) -> HoverableRowView {
        let theme = ConfigStore.shared.currentThemeColors
        let row = HoverableRowView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: Constants.Panel.windowRowHeight).isActive = true

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = Constants.Design.Spacing.xs
        stack.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: Constants.Panel.todoIndent),
            stack.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -Constants.Design.Spacing.sm),
            stack.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])

        // 色点（可点击切换状态）
        let dot = NSView()
        dot.wantsLayer = true
        dot.translatesAutoresizingMaskIntoConstraints = false
        let dotSize: CGFloat = isDone ? 8 : 10
        dot.layer?.backgroundColor = item.status.dotColor.cgColor
        dot.layer?.cornerRadius = dotSize / 2
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: dotSize),
            dot.heightAnchor.constraint(equalToConstant: dotSize),
        ])
        stack.addArrangedSubview(dot)

        // 标题文字
        let titleLabel = createLabel(item.title, size: 12, color: isDone ? theme.nsTextTertiary : theme.nsTextPrimary)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if isDone {
            // 删除线
            let attrStr = NSMutableAttributedString(string: item.title)
            attrStr.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: attrStr.length))
            attrStr.addAttribute(.foregroundColor, value: theme.nsTextTertiary, range: NSRange(location: 0, length: attrStr.length))
            attrStr.addAttribute(.font, value: NSFont.systemFont(ofSize: 12), range: NSRange(location: 0, length: attrStr.length))
            titleLabel.attributedStringValue = attrStr
        }
        stack.addArrangedSubview(titleLabel)

        stack.addArrangedSubview(createSpacer())

        // ▶ 执行按钮（Done 条目不显示）
        if !isDone {
            if let playImg = Self.cachedSymbol(name: "play.fill", size: 9, weight: .regular) {
                let playBtn = NSImageView(image: playImg)
                playBtn.contentTintColor = theme.nsTextTertiary.withAlphaComponent(0.35)
                playBtn.translatesAutoresizingMaskIntoConstraints = false
                playBtn.widthAnchor.constraint(equalToConstant: 14).isActive = true
                playBtn.heightAnchor.constraint(equalToConstant: 14).isActive = true
                stack.addArrangedSubview(playBtn)
            }
        }

        // ✕ 删除按钮
        if let xImg = Self.cachedSymbol(name: "xmark", size: 9, weight: .regular) {
            let xBtn = NSImageView(image: xImg)
            xBtn.contentTintColor = theme.nsTextTertiary.withAlphaComponent(0.35)
            xBtn.translatesAutoresizingMaskIntoConstraints = false
            xBtn.widthAnchor.constraint(equalToConstant: 14).isActive = true
            xBtn.heightAnchor.constraint(equalToConstant: 14).isActive = true
            stack.addArrangedSubview(xBtn)
        }

        // Done 行半透明
        if isDone {
            row.alphaValue = 0.5
        }

        // 点击处理：根据点击位置分发到不同操作
        let capturedItem = item
        let capturedCwd = cwdNormalized
        row.clickHandler = { [weak self] in
            guard let self = self, let window = self.window else { return }
            let mouseInWindow = window.mouseLocationOutsideOfEventStream
            let mouseInRow = row.convert(mouseInWindow, from: nil)
            let stackFrame = stack.convert(stack.bounds, to: row)

            // 计算各按钮的大致 x 区域
            let rowWidth = row.bounds.width
            let trailingArea: CGFloat = isDone ? 20 : 40  // Done: 只有 ✕; 非 Done: ▶ + ✕

            if mouseInRow.x > rowWidth - trailingArea {
                if isDone || mouseInRow.x > rowWidth - 20 {
                    // ✕ 删除
                    TodoService.shared.deleteItem(capturedItem, cwd: capturedCwd)
                    self.forceReload()
                } else {
                    // ▶ 复制到 AI 执行
                    self.handleTodoCopyToAI(item: capturedItem, cwd: capturedCwd)
                }
            } else if mouseInRow.x < Constants.Panel.todoIndent + 16 {
                // 色点区域：切换状态
                TodoService.shared.cycleStatus(item: capturedItem, cwd: capturedCwd)
                self.forceReload()
            } else {
                // 标题区域：也切换状态（整行点击友好）
                TodoService.shared.cycleStatus(item: capturedItem, cwd: capturedCwd)
                self.forceReload()
            }
        }

        return row
    }

    /// Done 摘要行：▶ ✓ N 项已完成
    func createDoneSummaryRow(doneCount: Int, cwdNormalized: String, isExpanded: Bool) -> HoverableRowView {
        let theme = ConfigStore.shared.currentThemeColors
        let row = HoverableRowView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: Constants.Panel.windowRowHeight).isActive = true

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = Constants.Design.Spacing.xs
        stack.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: Constants.Panel.todoIndent),
            stack.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -Constants.Design.Spacing.sm),
            stack.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])

        // 折叠箭头
        let chevronName = isExpanded ? "chevron.down" : "chevron.right"
        if let img = Self.cachedSymbol(name: chevronName, size: 8, weight: .medium) {
            let chevron = NSImageView(image: img)
            chevron.contentTintColor = theme.nsTextTertiary
            chevron.translatesAutoresizingMaskIntoConstraints = false
            chevron.widthAnchor.constraint(equalToConstant: 10).isActive = true
            chevron.heightAnchor.constraint(equalToConstant: 10).isActive = true
            stack.addArrangedSubview(chevron)
        }

        // "✓ N 项已完成"
        let label = createLabel("✓ \(doneCount) 项已完成", size: 11, color: theme.nsTextTertiary)
        stack.addArrangedSubview(label)

        // 折叠/展开点击
        let cwd = cwdNormalized
        row.clickHandler = { [weak self] in
            if self?.expandedDoneGroups.contains(cwd) == true {
                self?.expandedDoneGroups.remove(cwd)
            } else {
                self?.expandedDoneGroups.insert(cwd)
            }
            self?.forceReload()
        }

        return row
    }

    /// 复制到 AI 执行 + 智能窗口切换
    private func handleTodoCopyToAI(item: TodoItem, cwd: String) {
        // 1. 复制到剪贴板
        TodoService.shared.copyToPasteboard(item: item)

        // 2. 查找该项目下 active 的 AI session
        let activeSessions = CoderBridgeService.shared.sessions.filter {
            $0.cwdNormalized == cwd && $0.lifecycle == .active
        }

        if activeSessions.count == 1 {
            // 单个 session：直接切换
            let session = activeSessions[0]
            let (windowID, confidence) = CoderBridgeService.shared.resolveWindowForSession(session)
            if let wid = windowID, confidence == .high {
                let allWindows = AppMonitor.shared.runningApps.flatMap { $0.windows }
                if let windowInfo = allWindows.first(where: { $0.id == wid }) {
                    WindowService.shared.activateWindow(windowInfo)
                    (self.window as? QuickPanelWindow)?.yieldLevel()
                }
            }
        } else if activeSessions.count > 1 {
            // 多个 session：弹出选择菜单
            let menu = NSMenu(title: "选择会话")
            for session in activeSessions {
                let displayName = session.tool.displayName + " · " + session.shortID
                let menuItem = NSMenuItem(title: displayName, action: #selector(handleTodoSessionSelected(_:)), keyEquivalent: "")
                menuItem.target = self
                menuItem.representedObject = ["session": session, "cwd": cwd] as [String: Any]
                menu.addItem(menuItem)
            }
            // 在鼠标位置弹出菜单
            if let event = NSApp.currentEvent {
                NSMenu.popUpContextMenu(menu, with: event, for: self)
            }
        }
        // 无 session：仅复制，不切换（已在步骤 1 完成）
    }

    @objc private func handleTodoSessionSelected(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: Any],
              let session = info["session"] as? CoderSession else { return }

        let (windowID, confidence) = CoderBridgeService.shared.resolveWindowForSession(session)
        if let wid = windowID, confidence == .high {
            let allWindows = AppMonitor.shared.runningApps.flatMap { $0.windows }
            if let windowInfo = allWindows.first(where: { $0.id == wid }) {
                WindowService.shared.activateWindow(windowInfo)
                (self.window as? QuickPanelWindow)?.yieldLevel()
            }
        }
    }
```

- [ ] **Step 2: 编译验证**

Run: `make build`
Expected: 编译成功

- [ ] **Step 3: Commit**

```bash
git add FocusPilot/QuickPanel/QuickPanelRowBuilder.swift
git commit -m "feat(todo): 任务折叠行 + 任务条目行 + Done 摘要行构建"
```

---

### Task 6: QuickPanelView — buildAITabContent 集成

**Files:**
- Modify: `FocusPilot/QuickPanel/QuickPanelView.swift:1975-1982` (buildAITabContent 中 session 渲染区)

- [ ] **Step 1: 在 buildAITabContent() 中，group session 渲染之前插入任务区渲染**

找到 `buildAITabContent()` 中的以下代码块（约第 1975 行）：

```swift
            if !isCollapsed {
                for session in group.sessions {
                    let row = createSessionRow(session: session)
                    contentStack.addArrangedSubview(row)
                    // 行宽撑满 contentStack
                    row.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
                }
            }
```

替换为：

```swift
            if !isCollapsed {
                // === 任务区（todo.md 存在时渲染）===
                let cwdKey = group.cwdNormalized
                if let todoFile = TodoService.shared.parse(cwd: cwdKey) {
                    let isTodoExpanded = expandedTodoGroups.contains(cwdKey)

                    // 任务折叠行
                    let foldRow = createTodoFoldRow(todoFile: todoFile, cwdNormalized: cwdKey, isExpanded: isTodoExpanded)
                    contentStack.addArrangedSubview(foldRow)
                    foldRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

                    if isTodoExpanded {
                        // 活跃任务（Todo + In Progress）
                        for item in todoFile.activeItems {
                            let itemRow = createTodoItemRow(item: item, cwdNormalized: cwdKey, isDone: false)
                            contentStack.addArrangedSubview(itemRow)
                            itemRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
                        }

                        // Done 摘要行（有 done 任务时才显示）
                        if todoFile.doneCount > 0 {
                            let isDoneExpanded = expandedDoneGroups.contains(cwdKey)
                            let doneRow = createDoneSummaryRow(doneCount: todoFile.doneCount, cwdNormalized: cwdKey, isExpanded: isDoneExpanded)
                            contentStack.addArrangedSubview(doneRow)
                            doneRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

                            if isDoneExpanded {
                                for item in todoFile.doneItems {
                                    let itemRow = createTodoItemRow(item: item, cwdNormalized: cwdKey, isDone: true)
                                    contentStack.addArrangedSubview(itemRow)
                                    itemRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
                                }
                            }
                        }
                    }

                    // 分隔线（任务区和 session 区之间）
                    if !group.sessions.isEmpty {
                        let separator = NSView()
                        separator.wantsLayer = true
                        separator.layer?.backgroundColor = theme.nsSeparator.cgColor
                        separator.translatesAutoresizingMaskIntoConstraints = false
                        contentStack.addArrangedSubview(separator)
                        NSLayoutConstraint.activate([
                            separator.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -Constants.Panel.windowIndent * 2),
                            separator.heightAnchor.constraint(equalToConstant: 1),
                            separator.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor, constant: Constants.Panel.windowIndent),
                        ])
                    }
                }

                // === Session 行（已有逻辑）===
                for session in group.sessions {
                    let row = createSessionRow(session: session)
                    contentStack.addArrangedSubview(row)
                    row.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
                }
            }
```

- [ ] **Step 2: 编译验证**

Run: `make build`
Expected: 编译成功

- [ ] **Step 3: Commit**

```bash
git add FocusPilot/QuickPanel/QuickPanelView.swift
git commit -m "feat(todo): buildAITabContent 集成任务区渲染"
```

---

### Task 7: 端到端测试 — make install + 手动验证

**Files:** 无新修改

- [ ] **Step 1: 安装到本地**

Run: `make install`
Expected: 编译、签名、安装、启动成功

- [ ] **Step 2: 创建测试用 todo.md**

在某个有 AI session 的项目目录下创建 `todo.md`：

```markdown
## Todo
- [ ] 实现用户登录模块
  需要支持 OAuth2 和本地账号两种方式，
  登录状态持久化到 Keychain

- [ ] 添加快捷键配置

## In Progress
- [ ] 重构 WindowService 刷新逻辑
  拆分两阶段刷新为独立方法

## Done
- [x] 修复面板闪烁 bug
- [x] 设计数据模型
```

- [ ] **Step 3: 手动验证功能清单**

打开 FocusPilot 快捷面板 → AI Tab，逐项验证：

1. **任务折叠行显示**：项目文件夹展开后，session 列表上方出现 `▶ 📋 任务 2/5 ✎`
2. **折叠/展开**：点击任务折叠行 → 展开显示任务列表 + Done 摘要
3. **色点颜色**：Todo 黄色、In Progress 绿色、Done 灰色
4. **Done 折叠区**：显示 `✓ 2 项已完成`，点击展开，Done 条目有删除线 + 半透明
5. **状态流转**：点击色点 → Todo→In Progress→Done 循环，检查 todo.md 文件内容正确写回
6. **复制到 AI 执行**：点击 ▶ → 检查剪贴板内容是否为任务内容（非标题）→ 窗口切换
7. **删除**：点击 ✕ → 条目从面板和 todo.md 中移除
8. **✎ 打开编辑器**：点击 ✎ → 跳转到编辑器窗口
9. **外部修改感知**：在编辑器中添加一条任务 → 1~3s 后面板自动刷新显示
10. **无 todo.md**：项目没有 todo.md 时不显示任务折叠行
11. **分隔线**：任务区和 session 区之间有分隔线

- [ ] **Step 4: 修复发现的问题（如有）**

如果步骤 3 发现问题，定位并修复后重新 `make install` 验证。

- [ ] **Step 5: 最终 Commit**

```bash
git add -A
git commit -m "feat(todo): AI Tab 任务看板 — V4.2 功能完成"
```

---

### Task 8: 文档更新

**Files:**
- Modify: `docs/PRD.md`
- Modify: `docs/Architecture.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: 更新 PRD.md**

在 PRD 中添加 V4.2 任务看板功能描述。

- [ ] **Step 2: 更新 Architecture.md**

在架构文档中添加 TodoService 和任务区 UI 描述。

- [ ] **Step 3: 更新 CLAUDE.md**

在 CLAUDE.md 的文件结构中添加 `TodoService.swift`，在关键设计决策中添加任务看板相关条目，在配置迁移中添加 V4.2 条目。

- [ ] **Step 4: Commit**

```bash
git add docs/PRD.md docs/Architecture.md CLAUDE.md
git commit -m "docs: 更新 PRD/Architecture/CLAUDE.md — V4.2 任务看板"
```
