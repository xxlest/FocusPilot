import AppKit
import Carbon

// 全局快捷键管理（支持悬浮球+面板快捷键和主看板快捷键）
class HotkeyManager {
    static let shared = HotkeyManager()

    /// 悬浮球快捷键触发时的回调
    var onToggle: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private static let hotkeyID: UInt32 = 1

    private init() {}

    // MARK: - 注册/注销

    /// 注册悬浮球快捷键（首次调用时同时安装事件处理器）
    func register(config: HotkeyConfig? = nil) {
        // 安装 Carbon 事件处理器（仅安装一次，两个快捷键共用）
        if eventHandler == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

            let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)

                if hotKeyID.id == HotkeyManager.hotkeyID {
                    DispatchQueue.main.async {
                        HotkeyManager.shared.onToggle?()
                    }
                }
                return noErr
            }

            InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, &eventHandler)
        }

        // 使用传入配置或从 ConfigStore 读取
        let hotkey = config ?? ConfigStore.shared.preferences.hotkeyToggle
        let id = EventHotKeyID(signature: OSType(0x50494E54), id: Self.hotkeyID)
        RegisterEventHotKey(hotkey.keyCode, hotkey.carbonModifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    /// 仅重新注册悬浮球快捷键
    func reregister(config: HotkeyConfig) {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        let id = EventHotKeyID(signature: OSType(0x50494E54), id: Self.hotkeyID)
        RegisterEventHotKey(config.keyCode, config.carbonModifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

}
