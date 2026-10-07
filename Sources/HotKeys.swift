import AppKit
import Carbon.HIToolbox

enum HotKeyAction: UInt32, CaseIterable {
    case previousSpace = 1
    case nextSpace = 2
    case clearNotifications = 3

    var title: String {
        switch self {
        case .previousSpace: "Previous Space"
        case .nextSpace: "Next Space"
        case .clearNotifications: "Clear Notifications"
        }
    }

    var defaultsKey: String { "shortcut.\(rawValue)" }

    var defaultShortcut: KeyboardShortcut {
        let remoteModifiers = UInt32(controlKey | optionKey | cmdKey)
        switch self {
        case .previousSpace:
            return KeyboardShortcut(keyCode: UInt32(kVK_LeftArrow), modifiers: remoteModifiers)
        case .nextSpace:
            return KeyboardShortcut(keyCode: UInt32(kVK_RightArrow), modifiers: remoteModifiers)
        case .clearNotifications:
            return KeyboardShortcut(
                keyCode: UInt32(kVK_ANSI_N),
                modifiers: UInt32(controlKey | optionKey | cmdKey)
            )
        }
    }
}

struct KeyboardShortcut: Hashable {
    let keyCode: UInt32
    let modifiers: UInt32

    var displayName: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        result += Self.keyName(for: keyCode)
        return result
    }

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbonModifiers: UInt32 = 0
        if flags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if flags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }

        // Requiring Command or Control avoids accidental character capture and
        // satisfies the global-hotkey restrictions used by recent macOS versions.
        guard carbonModifiers & UInt32(controlKey | cmdKey) != 0 else { return nil }
        keyCode = UInt32(event.keyCode)
        modifiers = carbonModifiers
    }

    private static func keyName(for keyCode: UInt32) -> String {
        let specialKeys: [UInt32: String] = [
            UInt32(kVK_LeftArrow): "←",
            UInt32(kVK_RightArrow): "→",
            UInt32(kVK_UpArrow): "↑",
            UInt32(kVK_DownArrow): "↓",
            UInt32(kVK_Space): "Space",
            UInt32(kVK_Return): "Return",
            UInt32(kVK_Tab): "Tab",
            UInt32(kVK_Escape): "Esc",
            UInt32(kVK_Delete): "Delete",
        ]
        if let name = specialKeys[keyCode] { return name }

        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        guard let rawData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "Key \(keyCode)"
        }
        let data = Unmanaged<CFData>.fromOpaque(rawData).takeUnretainedValue()
        guard let layout = CFDataGetBytePtr(data) else { return "Key \(keyCode)" }

        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(
            UnsafePointer<UCKeyboardLayout>(OpaquePointer(layout)),
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )
        guard status == noErr, length > 0 else { return "Key \(keyCode)" }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }
}

enum ShortcutStore {
    static var defaults: [HotKeyAction: KeyboardShortcut] {
        Dictionary(uniqueKeysWithValues: HotKeyAction.allCases.map { ($0, $0.defaultShortcut) })
    }

    static func load() -> [HotKeyAction: KeyboardShortcut] {
        Dictionary(uniqueKeysWithValues: HotKeyAction.allCases.map { action in
            guard let value = UserDefaults.standard.dictionary(forKey: action.defaultsKey),
                  let keyCode = value["keyCode"] as? NSNumber,
                  let modifiers = value["modifiers"] as? NSNumber else {
                return (action, action.defaultShortcut)
            }
            return (
                action,
                KeyboardShortcut(
                    keyCode: keyCode.uint32Value,
                    modifiers: modifiers.uint32Value
                )
            )
        })
    }

    static func save(_ shortcuts: [HotKeyAction: KeyboardShortcut]) {
        for action in HotKeyAction.allCases {
            guard let shortcut = shortcuts[action] else { continue }
            UserDefaults.standard.set(
                ["keyCode": shortcut.keyCode, "modifiers": shortcut.modifiers],
                forKey: action.defaultsKey
            )
        }
    }

    static func removeSavedValues() {
        for action in HotKeyAction.allCases {
            UserDefaults.standard.removeObject(forKey: action.defaultsKey)
        }
    }
}

final class HotKeyManager {
    private static let signature: OSType = 0x4D4B4559 // "MKEY"
    private var eventHandler: EventHandlerRef?
    private var registeredHotKeys: [EventHotKeyRef] = []
    private let actionHandler: (HotKeyAction) -> Void
    private(set) var shortcuts = ShortcutStore.load()

    init(actionHandler: @escaping (HotKeyAction) -> Void) {
        self.actionHandler = actionHandler
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            var identifier = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &identifier
            )
            guard status == noErr,
                  identifier.signature == HotKeyManager.signature,
                  let action = HotKeyAction(rawValue: identifier.id) else {
                return OSStatus(eventNotHandledErr)
            }
            DispatchQueue.main.async { manager.actionHandler(action) }
            return noErr
        }
        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        _ = register(shortcuts)
    }

    deinit {
        unregisterAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    func update(action: HotKeyAction, shortcut: KeyboardShortcut) -> Bool {
        var candidate = shortcuts
        candidate[action] = shortcut
        guard Set(candidate.values).count == candidate.count else { return false }

        let previous = shortcuts
        unregisterAll()
        if register(candidate) {
            shortcuts = candidate
            ShortcutStore.save(candidate)
            return true
        }
        unregisterAll()
        _ = register(previous)
        return false
    }

    func resetToDefaults() -> Bool {
        let defaults = ShortcutStore.defaults
        let previous = shortcuts
        unregisterAll()
        if register(defaults) {
            shortcuts = defaults
            ShortcutStore.removeSavedValues()
            return true
        }
        _ = register(previous)
        return false
    }

    private func register(_ shortcuts: [HotKeyAction: KeyboardShortcut]) -> Bool {
        for action in HotKeyAction.allCases {
            guard let shortcut = shortcuts[action] else { return false }
            var reference: EventHotKeyRef?
            let identifier = EventHotKeyID(signature: Self.signature, id: action.rawValue)
            let status = RegisterEventHotKey(
                shortcut.keyCode,
                shortcut.modifiers,
                identifier,
                GetApplicationEventTarget(),
                0,
                &reference
            )
            guard status == noErr, let reference else {
                unregisterAll()
                return false
            }
            registeredHotKeys.append(reference)
        }
        return true
    }

    private func unregisterAll() {
        registeredHotKeys.forEach { UnregisterEventHotKey($0) }
        registeredHotKeys.removeAll()
    }
}
