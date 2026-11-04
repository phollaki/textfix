import AppKit
import Carbon

enum HotKey: UInt32, CaseIterable {
    case rephrase = 1
    case grammar = 2
    case translate = 3
    case palette = 4

    var argument: String {
        switch self {
        case .rephrase: return "rephrase"
        case .grammar: return "grammar"
        case .translate: return "translate"
        case .palette: return "palette"
        }
    }

    var title: String {
        switch self {
        case .rephrase: return "Rephrase"
        case .grammar: return "Fix grammar"
        case .translate: return "Translate"
        case .palette: return "Quick actions"
        }
    }

    var mode: Mode? {
        switch self {
        case .rephrase: return .rephrase
        case .grammar: return .grammar
        case .translate: return .translate
        case .palette: return nil
        }
    }

    var defaultShortcut: Shortcut {
        let modifiers = UInt32(controlKey | optionKey)
        switch self {
        case .rephrase: return Shortcut(keyCode: UInt32(kVK_ANSI_R), modifiers: modifiers, key: "R")
        case .grammar: return Shortcut(keyCode: UInt32(kVK_ANSI_G), modifiers: modifiers, key: "G")
        case .translate: return Shortcut(keyCode: UInt32(kVK_ANSI_T), modifiers: modifiers, key: "T")
        case .palette: return Shortcut(keyCode: UInt32(kVK_Space), modifiers: modifiers, key: "Space")
        }
    }
}

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
        let key = event.keyCode == kVK_Space ? "Space" : event.charactersIgnoringModifiers?.uppercased()
        guard modifiers & UInt32(controlKey | optionKey | cmdKey) != 0,
              let key,
              !key.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: key)
    }
}

final class HotKeys {
    private var references: [HotKey: EventHotKeyRef] = [:]

    static func shortcut(for mode: HotKey) -> Shortcut {
        guard let data = UserDefaults.standard.data(forKey: key(mode)),
              let shortcut = try? JSONDecoder().decode(Shortcut.self, from: data)
        else { return mode.defaultShortcut }
        return shortcut
    }

    func registerAll() {
        for mode in HotKey.allCases { register(mode, Self.shortcut(for: mode)) }
    }

    func unregisterAll() {
        references.values.forEach { UnregisterEventHotKey($0) }
        references = [:]
    }

    func change(_ mode: HotKey, to shortcut: Shortcut) -> String? {
        if let other = HotKey.allCases.first(where: { $0 != mode && Self.shortcut(for: $0) == shortcut }) {
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
    private func register(_ mode: HotKey, _ shortcut: Shortcut) -> Bool {
        if let old = references.removeValue(forKey: mode) { UnregisterEventHotKey(old) }
        var reference: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x5446_5854), id: mode.rawValue)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else { return false }
        references[mode] = reference
        return true
    }

    private static func key(_ mode: HotKey) -> String { "shortcut.\(mode.argument)" }
}
