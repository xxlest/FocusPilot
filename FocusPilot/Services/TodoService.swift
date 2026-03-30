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

    // MARK: - 写回操作

    /// 在 file 中找到与 item 匹配的条目（fingerprint + status + sectionIndex）
    private func findMatchingItem(_ item: TodoItem, in file: TodoFile) -> TodoItem? {
        let candidates = file.items.filter { $0.status == item.status && $0.fingerprint == item.fingerprint }
        if candidates.count == 1 { return candidates[0] }
        return candidates.first(where: { $0.sectionIndex == item.sectionIndex })
    }

    /// 循环切换任务状态，写回文件
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
            sectionIndex: 0,
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

        let removeResult = removeTodoLines(from: &lines, matching: removing)
        guard removeResult else { return false }

        if let newItem = inserting {
            let targetSection = newItem.status.sectionTitle
            insertTodoLines(into: &lines, item: newItem, targetSection: targetSection)
        }

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
                    var endIdx = i + 1
                    while endIdx < lines.count {
                        let nextLine = lines[endIdx]
                        if nextLine.hasPrefix("  ") && !nextLine.trimmingCharacters(in: .whitespaces).isEmpty {
                            endIdx += 1
                        } else if nextLine.trimmingCharacters(in: .whitespaces).isEmpty {
                            if endIdx + 1 < lines.count && lines[endIdx + 1].hasPrefix("  ") {
                                endIdx += 1
                            } else {
                                endIdx += 1
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

        var sectionStart: Int? = nil
        for i in 0..<lines.count {
            if lines[i] == targetSection {
                sectionStart = i
                break
            }
        }

        if let start = sectionStart {
            var insertAt = start + 1
            while insertAt < lines.count {
                if lines[insertAt].hasPrefix("## ") { break }
                insertAt += 1
            }
            while insertAt > start + 1 && lines[insertAt - 1].trimmingCharacters(in: .whitespaces).isEmpty {
                insertAt -= 1
            }
            var toInsert = newLines
            toInsert.append("")
            lines.insert(contentsOf: toInsert, at: insertAt)
        } else {
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
}
