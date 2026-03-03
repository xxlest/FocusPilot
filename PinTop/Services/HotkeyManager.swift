import AppKit
import Carbon

// 全局快捷键管理（支持动态注册）
class HotkeyManager {
    static let shared = HotkeyManager()

    // 快捷键动作
    enum HotkeyAction: Int, CaseIterable {
        case ballToggle = 1   // 悬浮球显隐
        case panelToggle = 2  // 快捷面板显隐
    }

    /// 快捷键触发时的回调
    var onAction: ((HotkeyAction) -> Void)?

    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var eventHandler: EventHandlerRef?

    private init() {}

    // MARK: - 注册/注销

    /// 使用指定配置注册快捷键（避免从 ConfigStore 读取，防止 @Published willSet 时序问题）
    func registerAll(ballToggle: HotkeyConfig? = nil, panelToggle: HotkeyConfig? = nil) {
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

        // 使用传入配置，或从 ConfigStore 读取（首次注册时）
        let prefs = ConfigStore.shared.preferences
        let ball = ballToggle ?? prefs.hotkeyBallToggle
        let panel = panelToggle ?? prefs.hotkeyPanelToggle

        // 注册悬浮球显隐快捷键
        registerHotKey(id: HotkeyAction.ballToggle.rawValue,
                       keyCode: ball.keyCode,
                       modifiers: ball.carbonModifiers)

        // 注册快捷面板显隐快捷键
        registerHotKey(id: HotkeyAction.panelToggle.rawValue,
                       keyCode: panel.keyCode,
                       modifiers: panel.carbonModifiers)
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

    /// 使用指定配置重新注册所有快捷键
    func reregisterAll(ballToggle: HotkeyConfig, panelToggle: HotkeyConfig) {
        unregisterAll()
        registerAll(ballToggle: ballToggle, panelToggle: panelToggle)
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
