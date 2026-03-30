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

    /// 进度摘要文字："2/5"（doneCount / totalCount）
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

            let title = String(line.dropFirst(6))

            // 收集紧接的缩进内容行
            var contentLines: [String] = []
            var j = i + 1
            while j < lines.count {
                let nextLine = lines[j]
                // 缩进行：以 2+ 空格开头，且不为空
                if nextLine.hasPrefix("  ") && !nextLine.trimmingCharacters(in: .whitespaces).isEmpty {
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
