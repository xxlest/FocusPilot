import AppKit
import Carbon

// 全局快捷键管理
class HotkeyManager {
    static let shared = HotkeyManager()

    // 快捷键动作
    enum HotkeyAction: Int, CaseIterable {
        case ballToggle = 6   // ⌘⇧B
    }

    /// 快捷键触发时的回调
    var onAction: ((HotkeyAction) -> Void)?

    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var eventHandler: EventHandlerRef?

    private init() {}

    // MARK: - 注册/注销

    func registerAll() {
        // 安装 Carbon 事件处理器
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)

            if let action = HotkeyAction(rawValue: Int(hotKeyID.id)) {
                DispatchQueue.main.async {
                    HotkeyManager.shared.onAction?(action)
                }
            }
            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, &eventHandler)

        // 注册各快捷键
        // ⌘⇧B (B=0x0B)
        registerHotKey(id: HotkeyAction.ballToggle.rawValue, keyCode: UInt32(kVK_ANSI_B),
                       modifiers: UInt32(cmdKey | shiftKey))
    }

    func unregisterAll() {
        for ref in hotKeyRefs {
            if let ref = ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotKeyRefs.removeAll()

        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    // MARK: - 内部

    private func registerHotKey(id: Int, keyCode: UInt32, modifiers: UInt32) {
        let hotKeyID = EventHotKeyID(signature: OSType(0x50494E54), id: UInt32(id)) // "PINT"
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status == noErr {
            hotKeyRefs.append(hotKeyRef)
        }
    }
}
