import AppKit
import Carbon

// 全局快捷键管理（支持悬浮球+面板快捷键和主看板快捷键）
class HotkeyManager {
    static let shared = HotkeyManager()

    /// 悬浮球快捷键触发时的回调
    var onToggle: (() -> Void)?
    /// 主看板快捷键触发时的回调
    var onKanbanToggle: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var kanbanHotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private static let hotkeyID: UInt32 = 1
    private static let kanbanHotkeyID: UInt32 = 2

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
                } else if hotKeyID.id == HotkeyManager.kanbanHotkeyID {
                    DispatchQueue.main.async {
                        HotkeyManager.shared.onKanbanToggle?()
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

    /// 注册主看板快捷键
    func registerKanban(config: HotkeyConfig? = nil) {
        // 先注销旧的
        if let ref = kanbanHotKeyRef {
            UnregisterEventHotKey(ref)
            kanbanHotKeyRef = nil
        }
        let hotkey = config ?? ConfigStore.shared.preferences.hotkeyKanban
        let id = EventHotKeyID(signature: OSType(0x50494E54), id: Self.kanbanHotkeyID)
        RegisterEventHotKey(hotkey.keyCode, hotkey.carbonModifiers, id, GetApplicationEventTarget(), 0, &kanbanHotKeyRef)
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = kanbanHotKeyRef {
            UnregisterEventHotKey(ref)
            kanbanHotKeyRef = nil
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

    /// 仅重新注册主看板快捷键
    func reregisterKanban(config: HotkeyConfig) {
        if let ref = kanbanHotKeyRef {
            UnregisterEventHotKey(ref)
            kanbanHotKeyRef = nil
        }
        let id = EventHotKeyID(signature: OSType(0x50494E54), id: Self.kanbanHotkeyID)
        RegisterEventHotKey(config.keyCode, config.carbonModifiers, id, GetApplicationEventTarget(), 0, &kanbanHotKeyRef)
    }
}
