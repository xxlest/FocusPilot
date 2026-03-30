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
    let content: String?   // 缩进块文字，nil 表示无内容
}

/// 任务看板：三个有序 section
struct TodoBoard {
    var todo: [TodoItem]
    var inProgress: [TodoItem]
    var done: [TodoItem]
    let path: String

    var activeItems: [TodoItem] { todo + inProgress }
    var doneCount: Int { done.count }
    var totalCount: Int { todo.count + inProgress.count + done.count }
    var progressSummary: String { "\(doneCount)/\(totalCount)" }

    func item(section: TodoStatus, index: Int) -> TodoItem? {
        let arr = items(for: section)
        guard index >= 0 && index < arr.count else { return nil }
        return arr[index]
    }

    func items(for section: TodoStatus) -> [TodoItem] {
        switch section {
        case .todo: return todo
        case .inProgress: return inProgress
        case .done: return done
        }
    }

    mutating func remove(section: TodoStatus, index: Int) {
        switch section {
        case .todo: todo.remove(at: index)
        case .inProgress: inProgress.remove(at: index)
        case .done: done.remove(at: index)
        }
    }

    mutating func append(_ item: TodoItem, to section: TodoStatus) {
        switch section {
        case .todo: todo.append(item)
        case .inProgress: inProgress.append(item)
        case .done: done.append(item)
        }
    }

    func serialize() -> String {
        var lines: [String] = []

        lines.append(TodoStatus.todo.sectionTitle)
        for item in todo { lines.append(contentsOf: serializeItem(item, checked: false)) }

        lines.append("")
        lines.append(TodoStatus.inProgress.sectionTitle)
        for item in inProgress { lines.append(contentsOf: serializeItem(item, checked: false)) }

        lines.append("")
        lines.append(TodoStatus.done.sectionTitle)
        for item in done { lines.append(contentsOf: serializeItem(item, checked: true)) }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    private func serializeItem(_ item: TodoItem, checked: Bool) -> [String] {
        let checkbox = checked ? "- [x] " : "- [ ] "
        var result = [checkbox + item.title]
        if let content = item.content {
            for line in content.components(separatedBy: "\n") {
                result.append("  " + line)
            }
        }
        return result
    }
}

// MARK: - TodoService

class TodoService {
    static let shared = TodoService()
    private init() {}

    /// 解析 todo.md → TodoBoard
    func parse(cwd: String) -> TodoBoard? {
        let path = (cwd as NSString).appendingPathComponent("todo.md")
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        var todo: [TodoItem] = []
        var inProgress: [TodoItem] = []
        var done: [TodoItem] = []
        var currentStatus: TodoStatus? = nil

        let lines = text.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]

            if line.hasPrefix("## ") {
                let title = String(line.dropFirst(3))
                if let status = TodoStatus.from(sectionTitle: title) {
                    currentStatus = status
                }
                i += 1
                continue
            }

            guard let status = currentStatus,
                  (line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ")) else {
                i += 1
                continue
            }

            let title = String(line.dropFirst(6))

            // 收集缩进内容行
            var contentLines: [String] = []
            var j = i + 1
            while j < lines.count {
                let nextLine = lines[j]
                if nextLine.hasPrefix("  ") && !nextLine.trimmingCharacters(in: .whitespaces).isEmpty {
                    contentLines.append(String(nextLine.dropFirst(2)))
                    j += 1
                } else if nextLine.trimmingCharacters(in: .whitespaces).isEmpty {
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
            let item = TodoItem(title: title, content: content)

            switch status {
            case .todo: todo.append(item)
            case .inProgress: inProgress.append(item)
            case .done: done.append(item)
            }

            i = j
        }

        return TodoBoard(todo: todo, inProgress: inProgress, done: done, path: path)
    }

    /// todo.md 的 mtime（用于 structural key）
    func mtime(cwd: String) -> TimeInterval {
        let path = (cwd as NSString).appendingPathComponent("todo.md")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let date = attrs[.modificationDate] as? Date else {
            return 0
        }
        return date.timeIntervalSince1970
    }

    // MARK: - 写回操作（全部基于 section + index）

    /// 循环切换状态：从 section[index] 移到 next section 末尾
    @discardableResult
    func cycleStatus(section: TodoStatus, index: Int, cwd: String) -> Bool {
        guard var board = parse(cwd: cwd),
              let item = board.item(section: section, index: index) else {
            return false
        }
        board.remove(section: section, index: index)
        board.append(item, to: section.next)
        return writeBoard(board)
    }

    /// 删除条目
    @discardableResult
    func deleteItem(section: TodoStatus, index: Int, cwd: String) -> Bool {
        guard var board = parse(cwd: cwd),
              board.item(section: section, index: index) != nil else {
            return false
        }
        board.remove(section: section, index: index)
        return writeBoard(board)
    }

    /// 复制内容到剪贴板
    func copyToPasteboard(item: TodoItem) {
        let text = item.content ?? item.title
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// 在编辑器中打开 todo.md
    func openInEditor(cwd: String) {
        let path = (cwd as NSString).appendingPathComponent("todo.md")
        let fileURL = URL(fileURLWithPath: path)

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
        NSWorkspace.shared.open(fileURL)
    }

    // MARK: - Private

    private func writeBoard(_ board: TodoBoard) -> Bool {
        do {
            try board.serialize().write(toFile: board.path, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }
}
