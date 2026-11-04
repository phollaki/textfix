import AppKit
import ApplicationServices
import Carbon

enum Mode: UInt32 {
    case rephrase = 1
    case grammar = 2
    case translate = 3

    var argument: String {
        switch self {
        case .rephrase: return "rephrase"
        case .grammar: return "grammar"
        case .translate: return "translate"
        }
    }

    var loadingTitle: String {
        switch self {
        case .rephrase: return "Rephrasing…"
        case .grammar: return "Fixing grammar…"
        case .translate: return "Translating…"
        }
    }
}

final class LoadingPanel {
    private let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 190, height: 44),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: true
    )
    private let label = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator(frame: NSRect(x: 16, y: 14, width: 16, height: 16))

    init() {
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let background = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 190, height: 44))
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true

        spinner.style = .spinning
        spinner.controlSize = .small
        label.frame = NSRect(x: 42, y: 13, width: 140, height: 18)
        label.font = .systemFont(ofSize: 13, weight: .medium)

        background.addSubview(spinner)
        background.addSubview(label)
        panel.contentView = background
    }

    func show(_ text: String) {
        label.stringValue = text
        spinner.startAnimation(nil)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let area = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: area.midX - 95, y: area.maxY - 60))
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        spinner.stopAnimation(nil)
        panel.orderOut(nil)
    }
}

final class TextFix: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let pasteboard = NSPasteboard.general
    private let script = NSHomeDirectory() + "/.local/bin/textfix"
    private let loading = LoadingPanel()
    private var busy = false

    func start() {
        statusItem.button?.title = "✎"
        let menu = NSMenu()
        menu.addItem(withTitle: "Rephrase: Control+Option+R", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Fix grammar: Control+Option+G", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Translate to English: Control+Option+T", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit TextFix", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusItem.menu = menu

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func run(_ mode: Mode) {
        guard !busy else { return }
        guard AXIsProcessTrusted() else {
            show("TextFix needs Accessibility access. Turn it on in System Settings > Privacy & Security > Accessibility.")
            return
        }
        busy = true
        statusItem.button?.title = "…"
        loading.show(mode.loadingTitle)
        let app = NSWorkspace.shared.frontmostApplication

        DispatchQueue.global(qos: .userInitiated).async {
            self.waitForModifierRelease()
            let saved = self.savePasteboard()
            let error = self.process(mode, app: app, saved: saved)
            DispatchQueue.main.async {
                self.busy = false
                self.loading.hide()
                self.statusItem.button?.title = "✎"
                if let error { self.show(error) }
            }
        }
    }

    private func process(_ mode: Mode, app: NSRunningApplication?, saved: [NSPasteboardItem]) -> String? {
        let count = pasteboard.changeCount
        press(key: 8)
        guard waitForCopy(after: count), let text = pasteboard.string(forType: .string) else {
            NSSound.beep()
            return nil
        }

        let result = rewrite(text, mode)
        switch result {
        case .failure(let error):
            restore(saved)
            return error.message
        case .success(let output):
            pasteboard.clearContents()
            pasteboard.setString(output, forType: .string)
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app?.processIdentifier else {
                return "You switched apps, so TextFix did not paste. The new text is in your clipboard."
            }
            press(key: 9)
            Thread.sleep(forTimeInterval: 1)
            restore(saved)
            return nil
        }
    }

    private func rewrite(_ text: String, _ mode: Mode) -> Result<String, ScriptError> {
        let task = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        task.executableURL = URL(fileURLWithPath: script)
        task.arguments = [mode.argument]
        task.standardInput = input
        task.standardOutput = output
        task.standardError = errors

        do {
            try task.run()
        } catch {
            return .failure(ScriptError(message: "Could not start \(script)"))
        }

        try? input.fileHandleForWriting.write(contentsOf: Data(text.utf8))
        try? input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard task.terminationStatus == 0, let result = String(data: data, encoding: .utf8) else {
            let message = String(data: errorData, encoding: .utf8) ?? ""
            return .failure(ScriptError(message: message.isEmpty ? "TextFix failed" : message))
        }
        return .success(result)
    }

    private func press(key: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    private func waitForCopy(after count: Int) -> Bool {
        for _ in 0..<50 {
            if pasteboard.changeCount != count { return true }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return false
    }

    private func waitForModifierRelease() {
        for _ in 0..<100 {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if !flags.contains(.maskControl) && !flags.contains(.maskAlternate) { return }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    private func savePasteboard() -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    private func restore(_ items: [NSPasteboardItem]) {
        pasteboard.clearContents()
        pasteboard.writeObjects(items)
    }

    private func show(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "TextFix"
        alert.informativeText = message
        alert.runModal()
    }
}

struct ScriptError: Error {
    let message: String
}

let textFix = TextFix()

func register(key: Int, mode: Mode) {
    var reference: EventHotKeyRef?
    let id = EventHotKeyID(signature: OSType(0x5446_5854), id: mode.rawValue)
    RegisterEventHotKey(UInt32(key), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &reference)
}

signal(SIGPIPE, SIG_IGN)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
textFix.start()

var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
    var id = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
    if let mode = Mode(rawValue: id.id) { textFix.run(mode) }
    return noErr
}, 1, &eventType, nil, nil)

register(key: kVK_ANSI_R, mode: .rephrase)
register(key: kVK_ANSI_G, mode: .grammar)
register(key: kVK_ANSI_T, mode: .translate)
app.run()
