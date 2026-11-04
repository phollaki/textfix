import AppKit
import ApplicationServices
import Carbon

enum Mode: UInt32, CaseIterable {
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

    var title: String {
        switch self {
        case .rephrase: return "Rephrase"
        case .grammar: return "Fix grammar"
        case .translate: return "Translate"
        }
    }

    var loadingTitle: String {
        switch self {
        case .rephrase: return "Rephrasing…"
        case .grammar: return "Fixing grammar…"
        case .translate: return "Translating…"
        }
    }

    var defaultShortcut: Shortcut {
        let modifiers = UInt32(controlKey | optionKey)
        switch self {
        case .rephrase: return Shortcut(keyCode: UInt32(kVK_ANSI_R), modifiers: modifiers, key: "R")
        case .grammar: return Shortcut(keyCode: UInt32(kVK_ANSI_G), modifiers: modifiers, key: "G")
        case .translate: return Shortcut(keyCode: UInt32(kVK_ANSI_T), modifiers: modifiers, key: "T")
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

final class TextFix: NSObject, NSApplicationDelegate, @unchecked Sendable {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let pasteboard = NSPasteboard.general
    private let loading = LoadingPanel()
    private let hotKeys = HotKeys()
    private var settings: SettingsWindow?
    private var busy = false

    @MainActor
    func start() {
        let model = SettingsModel(hotKeys: hotKeys)
        settings = SettingsWindow(model: model)

        statusItem.button?.title = "✎"
        let menu = NSMenu()
        let item = menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        item.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit TextFix", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        hotKeys.registerAll()
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) || !model.ready { settings?.show() }
    }

    @MainActor @objc private func openSettings() {
        settings?.show()
    }

    @MainActor
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings?.show()
        return false
    }

    @MainActor
    func run(_ mode: Mode) {
        guard !busy else { return }
        guard AXIsProcessTrusted() else {
            settings?.show()
            return
        }
        guard let request = settings?.model.request(for: mode) else {
            settings?.show()
            return
        }
        busy = true
        statusItem.button?.title = "…"
        loading.show(mode.loadingTitle)
        let app = NSWorkspace.shared.frontmostApplication

        DispatchQueue.global(qos: .userInitiated).async {
            self.waitForModifierRelease()
            let saved = self.savePasteboard()
            let error = self.process(request, app: app, saved: saved)
            Task { @MainActor in
                self.busy = false
                self.loading.hide()
                self.statusItem.button?.title = "✎"
                if let error { self.show(error) }
            }
        }
    }

    private func process(_ request: RewriteRequest, app: NSRunningApplication?, saved: [NSPasteboardItem]) -> String? {
        let count = pasteboard.changeCount
        press(key: 8)
        guard waitForCopy(after: count), let text = pasteboard.string(forType: .string) else {
            NSSound.beep()
            return nil
        }

        switch AI.rewrite(text, request) {
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
            if flags.intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand]).isEmpty { return }
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
