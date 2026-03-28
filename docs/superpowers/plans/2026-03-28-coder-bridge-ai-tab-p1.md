# Coder-Bridge AI Tab P1 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 补齐 AI Tab 体验——支持会话改名、显示最近 query 摘要、手动绑定窗口、隐藏会话。

**Architecture:** 在 P0 基础上，新增 ConfigStore 中 sessionPreferences 的持久化，CoderBridgeService 中 transcript 文件读取能力，以及 QuickPanel 中改名对话框、双行 session 行、隐藏会话折叠区等 UI 增强。

**Tech Stack:** Swift 5, AppKit, JSONSerialization, FileManager

**Spec 文档:** `docs/superpowers/specs/2026-03-28-coder-bridge-ai-tab-design.md` P1 部分

**编译验证:** `make build`
**安装验证:** `make install`

**前置条件:** P0 已完成并安装

---

## 文件结构

| 文件 | 改动类型 | 职责 |
|------|---------|------|
| `FocusPilot/Services/ConfigStore.swift` | Modify | 新增 sessionPreferences 持久化 |
| `FocusPilot/Services/CoderBridgeService.swift` | Modify | 新增 transcript 读取、preference 关联、隐藏会话逻辑 |
| `FocusPilot/Models/CoderSession.swift` | Modify | CoderSessionPreference 新增 WindowHint 字段 |
| `FocusPilot/QuickPanel/QuickPanelRowBuilder.swift` | Modify | 双行 session 行（query 摘要）、displayName 优先 |
| `FocusPilot/QuickPanel/QuickPanelMenuHandler.swift` | Modify | 改名对话框、手动绑定窗口、隐藏会话 |
| `FocusPilot/QuickPanel/QuickPanelView.swift` | Modify | 隐藏会话折叠入口 |

---

### Task 1: ConfigStore 持久化 sessionPreferences

**Files:**
- Modify: `FocusPilot/Services/ConfigStore.swift`

- [ ] **Step 1: 在 ConfigStore 中新增 sessionPreferences 属性**

在 ConfigStore 的属性区域（`windowRenames` 附近）添加：

```swift
    var sessionPreferences: [String: CoderSessionPreference] = [:]  // key → preference
```

- [ ] **Step 2: 在 load() 中加载 sessionPreferences**

在 `load()` 方法的 `lastPanelTab` 加载之后添加：

```swift
        if let data = defaults.data(forKey: Constants.Keys.sessionPreferences),
           let prefs = try? decoder.decode([String: CoderSessionPreference].self, from: data) {
            sessionPreferences = prefs
        }
```

- [ ] **Step 3: 新增 saveSessionPreferences() 单字段保存方法**

在 `saveWindowRenames()` 方法之后添加：

```swift
    /// 仅保存 AI 会话偏好
    func saveSessionPreferences() {
        if let data = try? encoder.encode(sessionPreferences) {
            defaults.set(data, forKey: Constants.Keys.sessionPreferences)
        }
    }
```

- [ ] **Step 4: 新增便捷方法更新单个 preference**

```swift
    func updateSessionPreference(key: String, displayName: String) {
        if var pref = sessionPreferences[key] {
            pref.displayName = displayName
            sessionPreferences[key] = pref
        } else {
            sessionPreferences[key] = CoderSessionPreference(key: key, displayName: displayName)
        }
        saveSessionPreferences()
    }
```

- [ ] **Step 5: 编译验证**

Run: `make build`
Expected: 编译成功

- [ ] **Step 6: Commit**

```bash
git add FocusPilot/Services/ConfigStore.swift
git commit -m "feat(ConfigStore): 新增 sessionPreferences 持久化

- sessionPreferences 字典存储 AI 会话偏好
- load() 中加载、saveSessionPreferences() 单字段保存
- updateSessionPreference() 便捷更新方法"
```

---

### Task 2: CoderBridgeService 集成 Preference 和 Transcript 读取

**Files:**
- Modify: `FocusPilot/Services/CoderBridgeService.swift`

- [ ] **Step 1: 新增 displayName 获取方法**

在 `CoderBridgeService` 的 `// MARK: - Session Queries` 区域添加：

```swift
    /// 获取 session 的显示名（preference 优先，否则 cwdBasename）
    func displayName(for session: CoderSession) -> String {
        if let pref = ConfigStore.shared.sessionPreferences[session.preferenceKey],
           !pref.displayName.isEmpty {
            return pref.displayName
        }
        return session.cwdBasename
    }
```

- [ ] **Step 2: 新增 transcript 路径定位方法**

在 `// MARK: - Session Queries` 区域添加：

```swift
    /// 定位 session 对应的 transcript 文件路径
    /// Claude Code transcript 存储在 ~/.claude/projects/<sanitized-cwd>/<session-id>.jsonl
    func transcriptPath(for session: CoderSession) -> String? {
        let claudeProjectsDir = NSHomeDirectory() + "/.claude/projects"
        let fm = FileManager.default

        guard fm.fileExists(atPath: claudeProjectsDir) else { return nil }

        // sanitized-cwd：把 / 替换为 -，去掉开头的 -
        let sanitized = session.cwdNormalized
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        let projectDir = claudeProjectsDir + "/" + sanitized
        let jsonlPath = projectDir + "/" + session.sessionID + ".jsonl"

        if fm.fileExists(atPath: jsonlPath) {
            return jsonlPath
        }

        // 兜底：遍历 projects 目录找匹配的 sessionID
        if let dirs = try? fm.contentsOfDirectory(atPath: claudeProjectsDir) {
            for dir in dirs {
                let candidatePath = claudeProjectsDir + "/" + dir + "/" + session.sessionID + ".jsonl"
                if fm.fileExists(atPath: candidatePath) {
                    return candidatePath
                }
            }
        }

        return nil
    }
```

- [ ] **Step 3: 新增最近 query 摘要提取方法**

```swift
    /// 从 transcript 文件中提取最近一条用户 query 的摘要
    /// 返回截断到 maxLength 字符的摘要文本，找不到则返回 nil
    func latestQuerySummary(for session: CoderSession, maxLength: Int = 40) -> String? {
        guard let path = transcriptPath(for: session),
              let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        // 从后往前找最近的 user message
        let lines = content.components(separatedBy: "\n").reversed()
        for line in lines {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = json["type"] as? String,
                  type == "user",
                  let message = json["message"] as? [String: Any],
                  let role = message["role"] as? String,
                  role == "user" else {
                continue
            }

            // content 可能是 String 或 Array
            var text = ""
            if let contentStr = message["content"] as? String {
                text = contentStr
            } else if let contentArr = message["content"] as? [[String: Any]] {
                // 多段内容，取第一个 text 类型
                for block in contentArr {
                    if let blockType = block["type"] as? String, blockType == "text",
                       let blockText = block["text"] as? String {
                        text = blockText
                        break
                    }
                }
            }

            if text.isEmpty { continue }

            // 去掉换行，截断
            text = text.replacingOccurrences(of: "\n", with: " ")
                       .trimmingCharacters(in: .whitespaces)
            if text.count > maxLength {
                text = String(text.prefix(maxLength)) + "..."
            }
            return text
        }

        return nil
    }
```

- [ ] **Step 4: 新增隐藏/显示会话方法**

```swift
    func hideSession(_ sid: String) {
        guard let index = sessions.firstIndex(where: { $0.sessionID == sid }) else { return }
        sessions[index].isHidden = true
        postSessionChanged()
    }

    func unhideSession(_ sid: String) {
        guard let index = sessions.firstIndex(where: { $0.sessionID == sid }) else { return }
        sessions[index].isHidden = false
        postSessionChanged()
    }

    /// 获取隐藏的 session 列表
    var hiddenSessions: [CoderSession] {
        sessions.filter { $0.isHidden }
    }
```

- [ ] **Step 5: 编译验证**

Run: `make build`
Expected: 编译成功

- [ ] **Step 6: Commit**

```bash
git add FocusPilot/Services/CoderBridgeService.swift
git commit -m "feat(CoderBridgeService): 新增 displayName、transcript 读取、隐藏会话

- displayName() 优先读取 CoderSessionPreference
- transcriptPath() 定位 session 的 .jsonl 文件
- latestQuerySummary() 从 transcript 提取最近 query 摘要
- hideSession/unhideSession 管理隐藏状态"
```

---

### Task 3: 双行 Session 行 + displayName 优先

**Files:**
- Modify: `FocusPilot/QuickPanel/QuickPanelRowBuilder.swift`

- [ ] **Step 1: 修改 createSessionRow 使用 displayName 并添加 query 摘要行**

找到 `createSessionRow(session:)` 方法，做以下修改：

1. displayName 从 `session.cwdBasename` 改为 `CoderBridgeService.shared.displayName(for: session)`

找到这行：
```swift
        let nameLabel = createLabel(session.cwdBasename, size: 12, color: theme.nsTextPrimary)
```
替换为：
```swift
        let displayName = CoderBridgeService.shared.displayName(for: session)
        let nameLabel = createLabel(displayName, size: 12, color: theme.nsTextPrimary)
```

2. 在 `row.alphaValue = session.rowAlpha` 之前，添加 query 摘要第二行：

```swift
        // 6. query 摘要（第二行，10pt 灰色）
        if let summary = CoderBridgeService.shared.latestQuerySummary(for: session) {
            let summaryLabel = createLabel(summary, size: 10, color: theme.nsTextTertiary)
            summaryLabel.lineBreakMode = .byTruncatingTail
            summaryLabel.translatesAutoresizingMaskIntoConstraints = false

            // 把 stack 改成主内容行，再加一个垂直容器包裹两行
            let verticalStack = NSStackView()
            verticalStack.orientation = .vertical
            verticalStack.alignment = .leading
            verticalStack.spacing = 2
            verticalStack.translatesAutoresizingMaskIntoConstraints = false

            // 把 stack 从 row 中移除，放入 verticalStack
            stack.removeFromSuperview()
            verticalStack.addArrangedSubview(stack)
            verticalStack.addArrangedSubview(summaryLabel)

            row.addSubview(verticalStack)
            NSLayoutConstraint.activate([
                verticalStack.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                verticalStack.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                verticalStack.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            ])

            // 有摘要时行高增加
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        }
```

注意：这段代码需要在原来设置 `stack` 的约束之后、`row.alphaValue` 之前插入。如果有 query 摘要，会把原来的水平 stack 包裹进一个垂直 stack 中。需要先移除原来 stack 的约束，再重新用 verticalStack 布局。

具体实现时需要调整原来 stack 约束的设置方式：
- 原来直接在 stack 上设置 leading/trailing/centerY 约束
- 改为：先不设置约束，等判断是否有 query 后再决定直接约束 stack 还是包裹进 verticalStack

- [ ] **Step 2: 编译验证**

Run: `make build`
Expected: 编译成功

- [ ] **Step 3: Commit**

```bash
git add FocusPilot/QuickPanel/QuickPanelRowBuilder.swift
git commit -m "feat(QuickPanel): session 行显示 displayName + query 摘要

- displayName 优先读取 CoderSessionPreference
- 有 query 摘要时双行显示（主信息 + 10pt 灰色摘要）
- 行高从 32 增加到 44（有摘要时）"
```

---

### Task 4: 右键菜单增强——改名 + 手动绑定 + 隐藏

**Files:**
- Modify: `FocusPilot/QuickPanel/QuickPanelMenuHandler.swift`

- [ ] **Step 1: 扩展 createSessionContextMenu 添加完整菜单项**

替换现有的 `createSessionContextMenu` 方法：

```swift
    func createSessionContextMenu(session: CoderSession) -> NSMenu? {
        let menu = NSMenu()

        // 改名
        let renameItem = NSMenuItem(title: "改名...", action: #selector(handleRenameSession(_:)), keyEquivalent: "")
        renameItem.target = self
        renameItem.representedObject = session
        menu.addItem(renameItem)

        // 手动绑定窗口 → 子菜单
        if !session.hostApp.isEmpty,
           let bundleID = HostAppMapping.bundleID(for: session.hostApp),
           let runningApp = AppMonitor.shared.runningApps.first(where: { $0.bundleID == bundleID }),
           !runningApp.windows.isEmpty {
            let bindItem = NSMenuItem(title: "绑定到窗口", action: nil, keyEquivalent: "")
            let bindSubmenu = NSMenu()
            for windowInfo in runningApp.windows {
                let windowItem = NSMenuItem(title: windowInfo.title.isEmpty ? "(无标题)" : windowInfo.title, action: #selector(handleBindToWindow(_:)), keyEquivalent: "")
                windowItem.target = self
                windowItem.representedObject = ["session": session, "windowInfo": windowInfo] as [String: Any]
                bindSubmenu.addItem(windowItem)
            }
            bindItem.submenu = bindSubmenu
            menu.addItem(bindItem)
        }

        menu.addItem(NSMenuItem.separator())

        // 隐藏此会话
        let hideItem = NSMenuItem(title: "隐藏此会话", action: #selector(handleHideSession(_:)), keyEquivalent: "")
        hideItem.target = self
        hideItem.representedObject = session.sessionID
        menu.addItem(hideItem)

        if session.lifecycle == .ended {
            menu.addItem(NSMenuItem.separator())

            let removeItem = NSMenuItem(title: "移除此会话", action: #selector(handleRemoveSession(_:)), keyEquivalent: "")
            removeItem.target = self
            removeItem.representedObject = session.sessionID
            menu.addItem(removeItem)

            let removeAllItem = NSMenuItem(title: "移除所有已结束会话", action: #selector(handleRemoveAllEndedSessions), keyEquivalent: "")
            removeAllItem.target = self
            menu.addItem(removeAllItem)
        }

        return menu
    }
```

- [ ] **Step 2: 新增改名 handler**

```swift
    @objc func handleRenameSession(_ sender: NSMenuItem) {
        guard let session = sender.representedObject as? CoderSession else { return }

        let alert = NSAlert()
        alert.messageText = "重命名 AI 会话"
        alert.informativeText = "为 \(session.cwdBasename) 会话设置自定义名称"
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.stringValue = CoderBridgeService.shared.displayName(for: session)
        input.placeholderString = session.cwdBasename
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let newName = input.stringValue.trimmingCharacters(in: .whitespaces)
            if !newName.isEmpty {
                ConfigStore.shared.updateSessionPreference(key: session.preferenceKey, displayName: newName)
                forceReload()
            }
        }
    }
```

- [ ] **Step 3: 新增手动绑定 handler**

```swift
    @objc func handleBindToWindow(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: Any],
              let session = info["session"] as? CoderSession,
              let windowInfo = info["windowInfo"] as? WindowInfo else { return }

        // 更新 session 的 candidateWindowID
        if let index = CoderBridgeService.shared.sessions.firstIndex(where: { $0.sessionID == session.sessionID }) {
            CoderBridgeService.shared.sessions[index].initialCandidateWindowID = windowInfo.id
            CoderBridgeService.shared.sessions[index].candidateWindowID = windowInfo.id
            CoderBridgeService.shared.sessions[index].matchConfidence = .high
        }
        forceReload()
    }
```

- [ ] **Step 4: 新增隐藏 handler**

```swift
    @objc func handleHideSession(_ sender: NSMenuItem) {
        guard let sid = sender.representedObject as? String else { return }
        CoderBridgeService.shared.hideSession(sid)
    }
```

- [ ] **Step 5: 编译验证**

Run: `make build`
Expected: 编译成功。注意 `CoderBridgeService.shared.sessions` 是 `private(set)`，`handleBindToWindow` 需要直接修改它。如果编译报错，需要在 CoderBridgeService 中新增一个 `updateSessionWindow(sid:windowID:)` 公开方法来替代直接访问。

- [ ] **Step 6: Commit**

```bash
git add FocusPilot/QuickPanel/QuickPanelMenuHandler.swift
git commit -m "feat(QuickPanel): 右键菜单增强——改名、绑定窗口、隐藏会话

- 改名通过 NSAlert + NSTextField 输入
- 绑定到窗口子菜单列出同宿主 App 的窗口
- 隐藏此会话 + 已结束会话移除"
```

---

### Task 5: 隐藏会话折叠入口

**Files:**
- Modify: `FocusPilot/QuickPanel/QuickPanelView.swift`

- [ ] **Step 1: 在 buildAITabContent 末尾添加隐藏会话折叠区**

找到 `buildAITabContent()` 方法，在 `for session in sessions` 循环之后、方法结束之前添加：

```swift
        // 隐藏的会话折叠入口
        let hiddenSessions = CoderBridgeService.shared.hiddenSessions
        if !hiddenSessions.isEmpty {
            let separator = NSView()
            separator.wantsLayer = true
            separator.layer?.backgroundColor = ConfigStore.shared.currentThemeColors.nsTextTertiary.withAlphaComponent(0.15).cgColor
            separator.translatesAutoresizingMaskIntoConstraints = false
            separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
            contentStack.addArrangedSubview(separator)

            let hiddenRow = HoverableRowView()
            hiddenRow.translatesAutoresizingMaskIntoConstraints = false
            hiddenRow.heightAnchor.constraint(equalToConstant: 28).isActive = true

            let hiddenLabel = createLabel("隐藏的会话 (\(hiddenSessions.count))", size: 11, color: ConfigStore.shared.currentThemeColors.nsTextTertiary)
            hiddenLabel.translatesAutoresizingMaskIntoConstraints = false
            hiddenRow.addSubview(hiddenLabel)
            NSLayoutConstraint.activate([
                hiddenLabel.leadingAnchor.constraint(equalTo: hiddenRow.leadingAnchor, constant: Constants.Design.Spacing.sm),
                hiddenLabel.centerYAnchor.constraint(equalTo: hiddenRow.centerYAnchor),
            ])

            hiddenRow.clickHandler = { [weak self] in
                // 点击展开：取消所有隐藏
                for session in hiddenSessions {
                    CoderBridgeService.shared.unhideSession(session.sessionID)
                }
            }

            contentStack.addArrangedSubview(hiddenRow)
        }
```

- [ ] **Step 2: 编译验证**

Run: `make build`
Expected: 编译成功

- [ ] **Step 3: Commit**

```bash
git add FocusPilot/QuickPanel/QuickPanelView.swift
git commit -m "feat(QuickPanel): 隐藏会话折叠入口

- AI Tab 底部显示'隐藏的会话 (N)'
- 点击展开恢复所有隐藏会话"
```

---

### Task 6: 端到端验证

**Files:** 无新增

- [ ] **Step 1: 编译安装**

Run: `make install`
Expected: 编译成功，FocusPilot 启动

- [ ] **Step 2: 验证改名功能**

1. 在 AI Tab 中找到一条 session
2. 右键 → "改名..."
3. 输入新名称，确定
4. 确认 session 行显示新名称
5. 重启 FocusPilot，新开一个同项目的 Claude Code 会话，确认名称继承

- [ ] **Step 3: 验证 query 摘要**

1. 在一个已有对话的 Claude Code 会话对应的 session 行上
2. 确认第二行显示了最近 query 的摘要文本（10pt 灰色）

- [ ] **Step 4: 验证隐藏功能**

1. 右键一条 session → "隐藏此会话"
2. 确认该行消失，底部出现"隐藏的会话 (1)"
3. 点击"隐藏的会话 (1)"
4. 确认该行恢复

- [ ] **Step 5: 验证手动绑定**

1. 右键一条 session → "绑定到窗口" → 选择一个窗口
2. 点击该 session 行
3. 确认切换到了选择的窗口

- [ ] **Step 6: Commit（如有修复）**

```bash
git add -A
git commit -m "fix(coder-bridge): P1 端到端集成修复"
```

---

### Task 7: 更新项目文档

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: 在 CLAUDE.md 的关键设计决策中补充 P1 内容**

在 coder-bridge 相关的设计决策之后添加：

```
- **AI 会话偏好持久化**：CoderSessionPreference 按 tool+cwdNormalized+hostApp 索引，存储 displayName；新 session 自动继承同 key 的偏好
- **Transcript 读取**：从 ~/.claude/projects/<sanitized-cwd>/<session-id>.jsonl 提取用户消息（type=="user" + message.role=="user"），用于 query 摘要
- **双行 Session 行**：第一行主信息（工具图标+displayName+宿主图标+状态），第二行最近 query 摘要（10pt nsTextTertiary）
```

- [ ] **Step 2: Commit + Push**

```bash
git add CLAUDE.md
git commit -m "docs: 更新 CLAUDE.md P1 设计决策"
git push
```
