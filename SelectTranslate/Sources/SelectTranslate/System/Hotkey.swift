import AppKit
import Carbon.HIToolbox
import Observation

/// 一个全局快捷键组合，如 ⌥D
nonisolated struct KeyCombo: Codable, Hashable, Sendable {
    var keyCode: UInt32
    var modifierFlags: UInt

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifierFlags = modifiers.intersection([.command, .option, .control, .shift]).rawValue
    }

    static let defaultSelection = KeyCombo(keyCode: UInt32(kVK_ANSI_D), modifiers: .option)
    static let defaultInput = KeyCombo(keyCode: UInt32(kVK_ANSI_A), modifiers: .option)

    var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifierFlags) }

    var carbonModifiers: UInt32 {
        var result = 0
        if modifiers.contains(.command) { result |= cmdKey }
        if modifiers.contains(.option) { result |= optionKey }
        if modifiers.contains(.control) { result |= controlKey }
        if modifiers.contains(.shift) { result |= shiftKey }
        return UInt32(result)
    }

    var displayString: String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option) { symbols += "⌥" }
        if modifiers.contains(.shift) { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        return symbols + Self.keyName(for: Int(keyCode))
    }

    /// 只有 F 键可以不带修饰键，否则会影响正常打字
    static func isValid(keyCode: Int, modifiers: NSEvent.ModifierFlags) -> Bool {
        !modifiers.intersection([.command, .option, .control]).isEmpty || functionKeys[keyCode] != nil
    }

    static func keyName(for keyCode: Int) -> String {
        keyNames[keyCode] ?? functionKeys[keyCode] ?? "键\(keyCode)"
    }

    private static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    private static let keyNames: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
        kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
        kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
        kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
        kVK_ANSI_Z: "Z", kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8",
        kVK_ANSI_9: "9", kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[",
        kVK_ANSI_RightBracket: "]", kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";",
        kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/",
        kVK_ANSI_Grave: "`", kVK_Space: "空格", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑",
        kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    ]
}

/// 基于 Carbon RegisterEventHotKey 的全局快捷键（不需要任何权限）
@Observable
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    enum Action: UInt32, CaseIterable {
        case translateSelection = 1
        case inputTranslation = 2
    }

    /// 注册失败（通常是被其他 App 占用）的快捷键
    private(set) var conflicts: Set<Action> = []

    /// 录制新快捷键时暂停，避免按下旧组合直接触发翻译
    var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            for action in Action.allCases {
                if isPaused { unregisterRef(action) } else { registerRef(action) }
            }
        }
    }

    @ObservationIgnored private var combos: [Action: KeyCombo] = [:]
    @ObservationIgnored private var handlers: [Action: () -> Void] = [:]
    @ObservationIgnored private var refs: [Action: EventHotKeyRef] = [:]
    @ObservationIgnored private var handlerInstalled = false

    func register(_ combo: KeyCombo?, for action: Action, handler: @escaping () -> Void) {
        installHandlerIfNeeded()
        unregisterRef(action)
        handlers[action] = handler
        combos[action] = combo
        if !isPaused { registerRef(action) }
    }

    private func registerRef(_ action: Action) {
        conflicts.remove(action)
        guard let combo = combos[action] else { return }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: 0x5354_524E /* STRN */, id: action.rawValue)
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs[action] = ref
        } else {
            conflicts.insert(action)
        }
    }

    private func unregisterRef(_ action: Action) {
        if let ref = refs.removeValue(forKey: action) {
            UnregisterEventHotKey(ref)
        }
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard status == noErr else { return status }
            let rawID = hotKeyID.id
            // Carbon 事件在主线程分发
            MainActor.assumeIsolated {
                HotkeyCenter.shared.fire(rawID)
            }
            return noErr
        }, 1, &eventType, nil, nil)
    }

    private func fire(_ rawID: UInt32) {
        guard let action = Action(rawValue: rawID) else { return }
        handlers[action]?()
    }
}
