import AppKit
import ObjectiveC

// 关联对象 Key（星号关注按钮存储 bundleID 和 displayName）
var bundleIDKey: UInt8 = 0
var displayNameKey: UInt8 = 0
var renameTextFieldKey: UInt8 = 0

// MARK: - 菜单与事件处理（extension QuickPanelView）
// 从 QuickPanelView 主文件提取的菜单、关注操作、App 启动等事件处理逻辑

extension QuickPanelView {

    // MARK: - 重命名 Key 工具方法

    static func renameKey(bundleID: String, windowID: CGWindowID) -> String {
        return "\(bundleID)::\(windowID)"
    }

    // MARK: - 窗口右键菜单

    func createWindowContextMenu(bundleID: String, windowInfo: WindowInfo) -> NSMenu {
        let menu = NSMenu()

        // 关闭窗口
        let closeItem = NSMenuItem(title: "关闭窗口", action: #selector(handleCloseWindow(_:)), keyEquivalent: "")
        closeItem.target = self
        closeItem.representedObject = windowInfo
        menu.addItem(closeItem)

        menu.addItem(NSMenuItem.separator())

        let renameItem = NSMenuItem(title: "重命名窗口", action: #selector(handleRenameWindow(_:)), keyEquivalent: "")
        renameItem.target = self
        renameItem.representedObject = (bundleID, windowInfo)
        menu.addItem(renameItem)

        let key = Self.renameKey(bundleID: bundleID, windowID: windowInfo.id)
        if ConfigStore.shared.windowRenames[key] != nil {
            let clearItem = NSMenuItem(title: "清除自定义名称", action: #selector(handleClearRename(_:)), keyEquivalent: "")
            clearItem.target = self
            clearItem.representedObject = key
            menu.addItem(clearItem)
        }

        return menu
    }

    @objc func handleCloseWindow(_ sender: NSMenuItem) {
        guard let windowInfo = sender.representedObject as? WindowInfo else { return }
        WindowService.shared.closeWindow(windowInfo)
        // 短暂延迟后刷新列表（等待窗口关闭生效）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.forceReload()
        }
    }

    @objc func handleRenameWindow(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? (String, WindowInfo) else { return }
        let bundleID = info.0
        let windowInfo = info.1
        let key = Self.renameKey(bundleID: bundleID, windowID: windowInfo.id)
        let currentName = ConfigStore.shared.windowRenames[key] ?? windowInfo.title

        // P3-#7：拆分为弹窗展示和保存两步
        guard let newName = showRenameDialog(currentName: currentName, originalTitle: windowInfo.title) else {
            return
        }
        applyRename(key: key, newName: newName, originalTitle: windowInfo.title)
    }

    /// 展示重命名弹窗，返回用户输入的新名称（nil 表示取消）
    private func showRenameDialog(currentName: String, originalTitle: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "重命名窗口"
        alert.informativeText = "原始标题：\(originalTitle)"
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        textField.stringValue = currentName
        textField.isEditable = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        prepareAlert(alert)
        let response = alert.runModal()
        restoreAfterAlert()
        guard response == .alertFirstButtonReturn else { return nil }
        return textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 应用重命名结果
    private func applyRename(key: String, newName: String, originalTitle: String) {
        if !newName.isEmpty && newName != originalTitle {
            ConfigStore.shared.windowRenames[key] = newName
            ConfigStore.shared.saveWindowRenames()
            forceReload()
        } else if newName == originalTitle || newName.isEmpty {
            ConfigStore.shared.windowRenames.removeValue(forKey: key)
            ConfigStore.shared.saveWindowRenames()
            forceReload()
        }
    }

    @objc func handleClearRename(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        ConfigStore.shared.windowRenames.removeValue(forKey: key)
        ConfigStore.shared.saveWindowRenames()
        forceReload()
    }

    // MARK: - 关注右键菜单

    func createFavoriteContextMenu(bundleID: String, isRunning: Bool) -> NSMenu {
        let menu = NSMenu()

        // 置顶操作（已经在第一位时不显示）
        let configs = ConfigStore.shared.appConfigs
        if configs.first?.bundleID != bundleID {
            let pinItem = NSMenuItem(title: "置顶", action: #selector(handlePinToTop(_:)), keyEquivalent: "")
            pinItem.target = self
            pinItem.representedObject = bundleID
            menu.addItem(pinItem)
        }

        // 关闭应用（仅运行中时显示）
        if isRunning {
            menu.addItem(NSMenuItem.separator())
            let terminateItem = NSMenuItem(title: "关闭应用", action: #selector(handleTerminateApp(_:)), keyEquivalent: "")
            terminateItem.target = self
            terminateItem.representedObject = bundleID
            menu.addItem(terminateItem)
        }

        menu.addItem(NSMenuItem.separator())

        // 取消关注
        let removeItem = NSMenuItem(title: "取消关注", action: #selector(handleRemoveFavorite(_:)), keyEquivalent: "")
        removeItem.target = self
        removeItem.representedObject = bundleID
        menu.addItem(removeItem)

        return menu
    }

    // MARK: - 活跃 App 右键菜单

    func createRunningAppContextMenu(bundleID: String) -> NSMenu {
        let menu = NSMenu()

        let terminateItem = NSMenuItem(title: "关闭应用", action: #selector(handleTerminateApp(_:)), keyEquivalent: "")
        terminateItem.target = self
        terminateItem.representedObject = bundleID
        menu.addItem(terminateItem)

        return menu
    }

    @objc func handleTerminateApp(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        let runningApps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleID }
        for app in runningApps {
            app.terminate()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.forceReload()
        }
    }

    @objc func handlePinToTop(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        var order = ConfigStore.shared.appConfigs.map { $0.bundleID }
        guard let idx = order.firstIndex(of: bundleID), idx > 0 else { return }
        order.remove(at: idx)
        order.insert(bundleID, at: 0)
        ConfigStore.shared.reorderApps(order)
        forceReload()
    }

    @objc func handleRemoveFavorite(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        // removeApp 内部会发送 appStatusChanged 通知，自动触发 reloadData
        ConfigStore.shared.removeApp(bundleID)
    }

    // MARK: - 星号关注切换

    /// 星号关注按钮点击：切换关注/取消关注
    /// P1-#4：不再显式调用 forceReload，依赖 addApp/removeApp 内部的通知机制
    @objc func handleToggleFavorite(_ sender: NSButton) {
        guard let bundleID = objc_getAssociatedObject(sender, &bundleIDKey) as? String else { return }
        let name = objc_getAssociatedObject(sender, &displayNameKey) as? String ?? ""

        if ConfigStore.shared.isFavorite(bundleID) {
            ConfigStore.shared.removeApp(bundleID)
        } else {
            ConfigStore.shared.addApp(bundleID, displayName: name)
        }
        // addApp/removeApp 内部发送 appStatusChanged 通知，自动触发 reloadData
        // buildStructuralKey 中的 fav 标记确保结构变化被检测到
    }

    // MARK: - App 启动

    /// 启动未运行的 App
    func launchApp(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            WindowService.shared.debugLog("QuickPanel: 找不到 App URL bundleID=\(bundleID)")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        // 面板临时让位，让启动的 App 窗口显示在前面
        (self.window as? QuickPanelWindow)?.yieldLevel()
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
            if let error = error {
                WindowService.shared.debugLog("QuickPanel: 启动 App 失败 bundleID=\(bundleID) error=\(error)")
            } else {
                WindowService.shared.debugLog("QuickPanel: App 已启动 bundleID=\(bundleID) pid=\(app?.processIdentifier ?? -1)")
            }
        }
    }

    // MARK: - 其他事件

    @objc func openMainKanban() {
        NotificationCenter.default.post(name: Constants.Notifications.ballOpenMainKanban, object: nil)
    }

    @objc func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    // MARK: - AI Session 右键菜单

    func createSessionContextMenu(session: CoderSession) -> NSMenu? {
        let menu = NSMenu()

        // 绑定到当前窗口
        let bindItem = NSMenuItem(title: "绑定到当前窗口", action: #selector(handleBindToCurrentWindow(_:)), keyEquivalent: "")
        bindItem.target = self
        bindItem.representedObject = session.sessionID
        menu.addItem(bindItem)

        // 解除绑定（仅在有绑定时显示）
        if session.manualWindowID != nil || session.autoWindowID != nil {
            let unbindItem = NSMenuItem(title: "解除绑定", action: #selector(handleUnbindSession(_:)), keyEquivalent: "")
            unbindItem.target = self
            unbindItem.representedObject = session.sessionID
            menu.addItem(unbindItem)
        }

        // 置顶（如果不是组内第一个）
        let groups = CoderBridgeService.shared.groupedSessions
        let isFirstInGroup = groups.first(where: { $0.sessions.contains(where: { $0.sessionID == session.sessionID }) })?.sessions.first?.sessionID == session.sessionID
        if !isFirstInGroup {
            let pinItem = NSMenuItem(title: "置顶", action: #selector(handlePinSession(_:)), keyEquivalent: "")
            pinItem.target = self
            pinItem.representedObject = session.sessionID
            menu.addItem(pinItem)
        }

        menu.addItem(NSMenuItem.separator())

        // 重命名
        let renameItem = NSMenuItem(title: "重命名", action: #selector(handleRenameSession(_:)), keyEquivalent: "")
        renameItem.target = self
        renameItem.representedObject = session.sessionID
        menu.addItem(renameItem)

        // 重置名称（仅有自定义名时显示）
        let hasCustomName = ConfigStore.shared.sessionPreferences[session.sessionID]?.displayName != nil
        if hasCustomName {
            let resetItem = NSMenuItem(title: "重置名称", action: #selector(handleResetSessionName(_:)), keyEquivalent: "")
            resetItem.target = self
            resetItem.representedObject = session.sessionID
            menu.addItem(resetItem)
        }

        menu.addItem(NSMenuItem.separator())

        // 复制 Session ID
        let copyItem = NSMenuItem(title: "复制 Session ID", action: #selector(handleCopySessionID(_:)), keyEquivalent: "")
        copyItem.target = self
        copyItem.representedObject = session.sessionID
        menu.addItem(copyItem)

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

    @objc func handleBindToCurrentWindow(_ sender: NSMenuItem) {
        guard let sid = sender.representedObject as? String else { return }
        guard let session = CoderBridgeService.shared.sessions.first(where: { $0.sessionID == sid }) else { return }

        let myPID = ProcessInfo.processInfo.processIdentifier
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return }

        // 找第一个非 FocusPilot 的普通窗口
        var targetWindowID: CGWindowID?
        var targetTitle = ""
        var targetPID: pid_t = 0
        for windowInfo in windowList {
            guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID != myPID,
                  let layer = windowInfo[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let wid = windowInfo[kCGWindowNumber as String] as? CGWindowID else { continue }
            targetWindowID = wid
            targetTitle = windowInfo[kCGWindowName as String] as? String ?? ""
            targetPID = ownerPID
            break
        }

        guard let wid = targetWindowID else { return }

        let frontApp = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == targetPID })
        let frontBundleID = frontApp?.bundleIdentifier ?? ""
        let appName = frontApp?.localizedName ?? "未知应用"
        let displayTitle = targetTitle.isEmpty ? appName : "\(appName) — \(targetTitle)"

        let alert = NSAlert()

        // hostApp 校验
        if !session.hostApp.isEmpty,
           let expectedBundleID = HostAppMapping.bundleID(for: session.hostApp),
           frontBundleID != expectedBundleID {
            let expectedName = HostAppMapping.displayName(for: session.hostApp)
            alert.messageText = "窗口不匹配"
            alert.informativeText = "此会话的宿主应用是「\(expectedName)」，当前窗口属于「\(appName)」。\n请先切换到「\(expectedName)」的窗口再绑定。"
            alert.addButton(withTitle: "确定")
            prepareAlert(alert)
            alert.runModal()
            restoreAfterAlert()
            return
        }

        alert.messageText = "绑定到当前窗口"

        if !CoderBridgeService.shared.allowsSharedBinding(for: session),
           let occupierSid = CoderBridgeService.shared.sessionOccupyingWindow(wid, excludingSid: sid) {
            // 独占类：替换确认逻辑
            let occupierSession = CoderBridgeService.shared.sessions.first(where: { $0.sessionID == occupierSid })
            let occupierName = occupierSession?.shortID ?? "其他会话"
            alert.informativeText = "「\(displayTitle)」当前已被会话 \(occupierName) 绑定。\n确定替换绑定？（旧绑定将被清除）"
        } else {
            // 白名单 app 或无冲突：直接确认绑定
            alert.informativeText = "确定将此会话绑定到「\(displayTitle)」？"
        }

        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        prepareAlert(alert)
        if alert.runModal() == .alertFirstButtonReturn {
            CoderBridgeService.shared.bindSessionToWindow(sid: sid, windowID: wid)
            forceReload()
        }
        restoreAfterAlert()
    }

    @objc func handleUnbindSession(_ sender: NSMenuItem) {
        guard let sid = sender.representedObject as? String else { return }
        CoderBridgeService.shared.clearManualWindowID(sid: sid)
        CoderBridgeService.shared.clearAutoWindowID(sid: sid)
        forceReload()
    }

    @objc func handleCopySessionID(_ sender: NSMenuItem) {
        guard let sid = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sid, forType: .string)
    }

    @objc func handleRemoveSession(_ sender: NSMenuItem) {
        guard let sid = sender.representedObject as? String else { return }
        CoderBridgeService.shared.removeSession(sid)
    }

    @objc func handleRemoveAllEndedSessions() {
        CoderBridgeService.shared.removeEndedSessions()
    }

    // MARK: - 置顶

    @objc func handlePinGroup(_ sender: NSMenuItem) {
        guard let cwdNormalized = sender.representedObject as? String else { return }
        CoderBridgeService.shared.pinGroup(cwdNormalized)
        forceReload()
    }

    @objc func handleCreateTodoFile(_ sender: NSMenuItem) {
        guard let cwd = sender.representedObject as? String else { return }
        let path = (cwd as NSString).appendingPathComponent("todo.md")
        let content = "## Todo\n- [ ] 在这里添加你的第一个任务\n  任务描述写在缩进行（可选）\n\n## In Progress\n\n## Done\n"
        FileManager.default.createFile(atPath: path, contents: content.data(using: .utf8))
        expandedTodoGroups.insert(cwd)
        forceReload()
    }

    @objc func handlePinSession(_ sender: NSMenuItem) {
        guard let sid = sender.representedObject as? String else { return }
        CoderBridgeService.shared.pinSession(sid)
        forceReload()
    }

    // MARK: - 重命名 / 重置名称

    @objc func handleRenameSession(_ sender: NSMenuItem) {
        guard let sid = sender.representedObject as? String,
              let session = CoderBridgeService.shared.sessions.first(where: { $0.sessionID == sid }) else { return }

        let key = session.sessionID
        let currentName = ConfigStore.shared.sessionPreferences[key]?.displayName ?? ""

        let alert = NSAlert()
        alert.messageText = "重命名会话"
        alert.informativeText = "\(session.tool.displayName) · \(session.shortID)"
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        let containerWidth: CGFloat = 260

        // 输入框
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: containerWidth, height: 24))
        textField.stringValue = currentName
        textField.placeholderString = session.tool.displayName
        textField.isEditable = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel

        // 读取任务列表（使用 cwdNormalized 与面板一致）
        let todoFile = TodoService.shared.parse(cwd: session.cwdNormalized)
        let activeItems = todoFile?.activeItems ?? []

        if activeItems.isEmpty {
            // 无任务：纯输入框
            alert.accessoryView = textField
            alert.window.initialFirstResponder = textField
        } else {
            // 有任务：输入框 + 分隔线 + 标签 + 任务列表
            let rowHeight: CGFloat = 22
            let maxVisibleRows = min(activeItems.count, 5)
            let listHeight = CGFloat(maxVisibleRows) * rowHeight
            let labelHeight: CGFloat = 16
            let sepHeight: CGFloat = 12
            let totalHeight = 24 + sepHeight + labelHeight + 4 + listHeight

            let container = NSView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: totalHeight))

            // 输入框（顶部）
            textField.frame = NSRect(x: 0, y: totalHeight - 24, width: containerWidth, height: 24)
            container.addSubview(textField)

            // 分隔线
            let sepY = totalHeight - 24 - sepHeight
            let sep = NSView(frame: NSRect(x: 0, y: sepY + sepHeight / 2 - 0.5, width: containerWidth, height: 1))
            sep.wantsLayer = true
            sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
            container.addSubview(sep)

            // 标签
            let label = NSTextField(labelWithString: "从任务选择")
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            label.frame = NSRect(x: 0, y: sepY - labelHeight, width: containerWidth, height: labelHeight)
            container.addSubview(label)

            // 任务按钮列表
            let listView = NSView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: CGFloat(activeItems.count) * rowHeight))
            for (i, item) in activeItems.enumerated() {
                let y = CGFloat(activeItems.count - 1 - i) * rowHeight
                let btn = NSButton(frame: NSRect(x: 0, y: y, width: containerWidth, height: rowHeight))
                btn.title = item.title
                btn.bezelStyle = .inline
                btn.isBordered = false
                btn.alignment = .left
                btn.font = .systemFont(ofSize: 12)
                btn.contentTintColor = .labelColor
                btn.target = self
                btn.action = #selector(handleTodoItemClicked(_:))
                // 关联 textField 以便点击时填充
                objc_setAssociatedObject(btn, &renameTextFieldKey, textField, .OBJC_ASSOCIATION_ASSIGN)
                listView.addSubview(btn)
            }

            if activeItems.count > maxVisibleRows {
                let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: listHeight))
                scrollView.documentView = listView
                scrollView.hasVerticalScroller = true
                scrollView.drawsBackground = false
                container.addSubview(scrollView)
            } else {
                listView.frame = NSRect(x: 0, y: 0, width: containerWidth, height: listHeight)
                container.addSubview(listView)
            }

            alert.accessoryView = container
            alert.window.initialFirstResponder = textField
        }

        prepareAlert(alert)
        let response = alert.runModal()
        restoreAfterAlert()

        guard response == .alertFirstButtonReturn else { return }
        let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if newName.isEmpty {
            ConfigStore.shared.removeSessionPreference(key: key)
        } else {
            ConfigStore.shared.updateSessionPreference(key: key, displayName: newName)
        }
        forceReload()
    }

    /// 任务项点击 → 填充到重命名输入框
    @objc func handleTodoItemClicked(_ sender: NSButton) {
        guard let textField = objc_getAssociatedObject(sender, &renameTextFieldKey) as? NSTextField else { return }
        textField.stringValue = sender.title
        textField.selectText(nil)
    }

    @objc func handleResetSessionName(_ sender: NSMenuItem) {
        guard let sid = sender.representedObject as? String,
              let session = CoderBridgeService.shared.sessions.first(where: { $0.sessionID == sid }) else { return }
        ConfigStore.shared.removeSessionPreference(key: session.sessionID)
        forceReload()
    }
}
