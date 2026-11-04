import AppKit
import Carbon

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var key: String

    var label: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + key
    }
}

extension Shortcut {
    init?(event: NSEvent) {
        var modifiers: UInt32 = 0
        let flags = event.modifierFlags
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        guard modifiers & UInt32(controlKey | optionKey | cmdKey) != 0,
              let key = event.charactersIgnoringModifiers?.uppercased(),
              !key.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: key)
    }
}

final class HotKeys {
    private var references: [Mode: EventHotKeyRef] = [:]

    static func shortcut(for mode: Mode) -> Shortcut {
        guard let data = UserDefaults.standard.data(forKey: key(mode)),
              let shortcut = try? JSONDecoder().decode(Shortcut.self, from: data)
        else { return mode.defaultShortcut }
        return shortcut
    }

    func registerAll() {
        for mode in Mode.allCases { register(mode, Self.shortcut(for: mode)) }
    }

    func unregisterAll() {
        references.values.forEach { UnregisterEventHotKey($0) }
        references = [:]
    }

    func change(_ mode: Mode, to shortcut: Shortcut) -> String? {
        if let other = Mode.allCases.first(where: { $0 != mode && Self.shortcut(for: $0) == shortcut }) {
            return "\(shortcut.label) is already used for \(other.title)."
        }
        guard register(mode, shortcut) else {
            register(mode, Self.shortcut(for: mode))
            return "\(shortcut.label) is used by another app. Please try a different shortcut."
        }
        UserDefaults.standard.set(try? JSONEncoder().encode(shortcut), forKey: Self.key(mode))
        return nil
    }

    @discardableResult
    private func register(_ mode: Mode, _ shortcut: Shortcut) -> Bool {
        if let old = references.removeValue(forKey: mode) { UnregisterEventHotKey(old) }
        var reference: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x5446_5854), id: mode.rawValue)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else { return false }
        references[mode] = reference
        return true
    }

    private static func key(_ mode: Mode) -> String { "shortcut.\(mode.argument)" }
}
