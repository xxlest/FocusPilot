import AppKit
import ObjectiveC

// 关联对象 Key（星号关注按钮存储 bundleID 和 displayName）
var bundleIDKey: UInt8 = 0
var displayNameKey: UInt8 = 0

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

        let response = alert.runModal()
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

        // 改名
        let renameItem = NSMenuItem(title: "改名...", action: #selector(handleRenameSession(_:)), keyEquivalent: "")
        renameItem.target = self
        renameItem.representedObject = [
            "sessionID": session.sessionID,
            "cwdBasename": session.cwdBasename,
            "preferenceKey": session.preferenceKey,
            "displayName": CoderBridgeService.shared.displayName(for: session)
        ] as [String: String]
        menu.addItem(renameItem)

        // 手动绑定窗口 → 子菜单
        if !session.hostApp.isEmpty,
           let bundleID = HostAppMapping.bundleID(for: session.hostApp),
           let runningApp = AppMonitor.shared.runningApps.first(where: { $0.bundleID == bundleID }),
           !runningApp.windows.isEmpty {
            let bindItem = NSMenuItem(title: "绑定到窗口", action: nil, keyEquivalent: "")
            let bindSubmenu = NSMenu()
            for windowInfo in runningApp.windows {
                let title = windowInfo.title.isEmpty ? "(无标题)" : windowInfo.title
                let windowItem = NSMenuItem(title: title, action: #selector(handleBindToWindow(_:)), keyEquivalent: "")
                windowItem.target = self
                windowItem.representedObject = ["sid": session.sessionID, "wid": windowInfo.id] as [String: Any]
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

    @objc func handleRenameSession(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: String],
              let _ = info["sessionID"],
              let cwdBasename = info["cwdBasename"],
              let preferenceKey = info["preferenceKey"],
              let currentDisplayName = info["displayName"] else { return }

        let alert = NSAlert()
        alert.messageText = "重命名 AI 会话"
        alert.informativeText = "为 \(cwdBasename) 会话设置自定义名称"
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.stringValue = currentDisplayName
        input.placeholderString = cwdBasename
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let newName = input.stringValue.trimmingCharacters(in: .whitespaces)
            if !newName.isEmpty {
                ConfigStore.shared.updateSessionPreference(key: preferenceKey, displayName: newName)
                forceReload()
            }
        }
    }

    @objc func handleBindToWindow(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: Any],
              let sid = info["sid"] as? String,
              let wid = info["wid"] as? CGWindowID else { return }
        CoderBridgeService.shared.bindSessionToWindow(sid: sid, windowID: wid)
        forceReload()
    }

    @objc func handleHideSession(_ sender: NSMenuItem) {
        guard let sid = sender.representedObject as? String else { return }
        CoderBridgeService.shared.hideSession(sid)
    }

    @objc func handleRemoveSession(_ sender: NSMenuItem) {
        guard let sid = sender.representedObject as? String else { return }
        CoderBridgeService.shared.removeSession(sid)
    }

    @objc func handleRemoveAllEndedSessions() {
        CoderBridgeService.shared.removeEndedSessions()
    }
}
