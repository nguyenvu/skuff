import AppKit
import Carbon.HIToolbox
import Foundation

nonisolated extension Notification.Name {
    static let skuffHotkey = Notification.Name("skuffHotkey")
    static let skuffTogglePanel = Notification.Name("skuffTogglePanel")
}

nonisolated private func skuffHotKeyHandler(
    _ next: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    if hotKeyID.id == HotkeyCenter.toggleID {
        NotificationCenter.default.post(name: .skuffTogglePanel, object: nil)
    } else {
        NotificationCenter.default.post(name: .skuffHotkey, object: nil, userInfo: ["index": Int(hotKeyID.id)])
    }
    return noErr
}

final class HotkeyCenter {
    static let shared = HotkeyCenter()
    nonisolated static let toggleID: UInt32 = 100
    static let defaultToggleKeyCode = 49
    static let defaultToggleModifiers = Int(optionKey)

    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private let signature = OSType(0x536B7566)

    private let keyCodes: [UInt32] = [
        UInt32(kVK_ANSI_1), UInt32(kVK_ANSI_2), UInt32(kVK_ANSI_3),
        UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5), UInt32(kVK_ANSI_6),
        UInt32(kVK_ANSI_7), UInt32(kVK_ANSI_8), UInt32(kVK_ANSI_9)
    ]

    func register(count: Int, toggle: (keyCode: UInt32, modifiers: UInt32)?) -> (failedTabs: [Int], toggleFailed: Bool) {
        installHandlerIfNeeded()
        unregisterKeys()
        let limit = min(count, keyCodes.count)
        var failed: [Int] = []
        for index in 0..<limit {
            if !install(keyCode: keyCodes[index], modifiers: UInt32(optionKey), id: UInt32(index)) {
                failed.append(index)
            }
        }
        var toggleFailed = false
        if let toggle {
            toggleFailed = !install(keyCode: toggle.keyCode, modifiers: toggle.modifiers, id: Self.toggleID)
        }
        return (failed, toggleFailed)
    }

    func unregisterKeys() {
        for ref in refs {
            UnregisterEventHotKey(ref)
        }
        refs.removeAll()
    }

    private func install(keyCode: UInt32, modifiers: UInt32, id: UInt32) -> Bool {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            refs.append(ref)
            return true
        }
        return false
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), skuffHotKeyHandler, 1, &spec, nil, &handler)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var mods = 0
        if flags.contains(.command) { mods |= Int(cmdKey) }
        if flags.contains(.shift) { mods |= Int(shiftKey) }
        if flags.contains(.option) { mods |= Int(optionKey) }
        if flags.contains(.control) { mods |= Int(controlKey) }
        return mods
    }

    static func display(keyCode: Int, carbonModifiers: Int) -> String {
        var parts: [String] = []
        if carbonModifiers & Int(controlKey) != 0 { parts.append("⌃") }
        if carbonModifiers & Int(optionKey) != 0 { parts.append("⌥") }
        if carbonModifiers & Int(shiftKey) != 0 { parts.append("⇧") }
        if carbonModifiers & Int(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyName(keyCode))
        return parts.joined()
    }

    static func keyName(_ keyCode: Int) -> String {
        switch keyCode {
        case Int(kVK_Space): "Space"
        case Int(kVK_Tab): "Tab"
        case Int(kVK_Return): "Return"
        case Int(kVK_Escape): "Esc"
        case Int(kVK_ANSI_Grave): "`"
        default:
            keyMap[keyCode] ?? "Key \(keyCode)"
        }
    }

    private static let keyMap: [Int: String] = {
        let pairs: [(Int, String)] = [
            (Int(kVK_ANSI_A), "A"), (Int(kVK_ANSI_B), "B"), (Int(kVK_ANSI_C), "C"),
            (Int(kVK_ANSI_D), "D"), (Int(kVK_ANSI_E), "E"), (Int(kVK_ANSI_F), "F"),
            (Int(kVK_ANSI_G), "G"), (Int(kVK_ANSI_H), "H"), (Int(kVK_ANSI_I), "I"),
            (Int(kVK_ANSI_J), "J"), (Int(kVK_ANSI_K), "K"), (Int(kVK_ANSI_L), "L"),
            (Int(kVK_ANSI_M), "M"), (Int(kVK_ANSI_N), "N"), (Int(kVK_ANSI_O), "O"),
            (Int(kVK_ANSI_P), "P"), (Int(kVK_ANSI_Q), "Q"), (Int(kVK_ANSI_R), "R"),
            (Int(kVK_ANSI_S), "S"), (Int(kVK_ANSI_T), "T"), (Int(kVK_ANSI_U), "U"),
            (Int(kVK_ANSI_V), "V"), (Int(kVK_ANSI_W), "W"), (Int(kVK_ANSI_X), "X"),
            (Int(kVK_ANSI_Y), "Y"), (Int(kVK_ANSI_Z), "Z"),
            (Int(kVK_ANSI_0), "0"), (Int(kVK_ANSI_1), "1"), (Int(kVK_ANSI_2), "2"),
            (Int(kVK_ANSI_3), "3"), (Int(kVK_ANSI_4), "4"), (Int(kVK_ANSI_5), "5"),
            (Int(kVK_ANSI_6), "6"), (Int(kVK_ANSI_7), "7"), (Int(kVK_ANSI_8), "8"),
            (Int(kVK_ANSI_9), "9")
        ]
        return Dictionary(uniqueKeysWithValues: pairs)
    }()
}
