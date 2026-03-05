import AppKit
import ObjectiveC

// 关联对象 Key（星号收藏按钮存储 bundleID 和 displayName）
var bundleIDKey: UInt8 = 0
var displayNameKey: UInt8 = 0

// MARK: - 菜单与事件处理（extension QuickPanelView）
// 从 QuickPanelView 主文件提取的菜单、收藏操作、App 启动等事件处理逻辑

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

    // MARK: - 收藏右键菜单

    func createFavoriteContextMenu(bundleID: String) -> NSMenu {
        let menu = NSMenu()

        // 置顶操作（已经在第一位时不显示）
        let configs = ConfigStore.shared.appConfigs
        if configs.first?.bundleID != bundleID {
            let pinItem = NSMenuItem(title: "置顶", action: #selector(handlePinToTop(_:)), keyEquivalent: "")
            pinItem.target = self
            pinItem.representedObject = bundleID
            menu.addItem(pinItem)
        }

        // 取消收藏
        let removeItem = NSMenuItem(title: "取消收藏", action: #selector(handleRemoveFavorite(_:)), keyEquivalent: "")
        removeItem.target = self
        removeItem.representedObject = bundleID
        menu.addItem(removeItem)

        return menu
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

    // MARK: - 星号收藏切换

    /// 星号收藏按钮点击：切换收藏/取消收藏
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
}
