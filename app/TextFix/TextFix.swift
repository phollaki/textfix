import AppKit
import ApplicationServices

enum Mode {
    case rephrase, grammar, translate, shorter, prompt, tldr, replies, explain, custom, redact

    var title: String {
        switch self {
        case .rephrase: return "Rephrase"
        case .grammar: return "Fix grammar"
        case .translate: return "Translate"
        case .shorter: return "Make it shorter"
        case .prompt: return "Prompt from my text"
        case .tldr: return "TL;DR"
        case .replies: return "Reply ideas"
        case .explain: return "Explain"
        case .custom: return "Your instruction"
        case .redact: return "Hide sensitive data"
        }
    }

    var loadingTitle: String {
        switch self {
        case .rephrase: return "Rephrasing…"
        case .grammar: return "Fixing grammar…"
        case .translate: return "Translating…"
        case .shorter: return "Shortening…"
        case .prompt: return "Writing prompt…"
        case .tldr: return "Summarizing…"
        case .replies: return "Writing replies…"
        case .explain: return "Explaining…"
        case .custom: return "Working…"
        case .redact: return "Hiding data…"
        }
    }

    var replacesText: Bool {
        switch self {
        case .prompt, .tldr, .replies, .explain: return false
        default: return true
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
    @MainActor private lazy var palette = Palette()
    @MainActor private lazy var results = ResultPanel()
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
    func run(_ hotKey: HotKey) {
        guard !busy else { return }
        guard AXIsProcessTrusted(), let model = settings?.model, model.ready || hotKey == .redact else {
            settings?.show()
            return
        }
        busy = true
        let mode = hotKey.mode
        if let mode { showLoading(mode) }
        let app = NSWorkspace.shared.frontmostApplication

        DispatchQueue.global(qos: .userInitiated).async {
            self.waitForModifierRelease()
            let saved = self.savePasteboard()
            guard let text = self.copySelection() else {
                NSSound.beep()
                Task { @MainActor in self.finish(nil) }
                return
            }
            Task { @MainActor in
                if let mode {
                    self.send(text, model.request(for: mode), app: app, saved: saved)
                    return
                }
                self.palette.show(language: model.language) { choice in
                    guard let choice else {
                        self.restore(saved)
                        self.finish(nil)
                        return
                    }
                    app?.activate()
                    self.showLoading(choice.mode)
                    self.send(text, model.request(for: choice.mode, instruction: choice.instruction), app: app, saved: saved)
                }
            }
        }
    }

    @MainActor
    private func showLoading(_ mode: Mode) {
        statusItem.button?.title = "…"
        loading.show(mode.loadingTitle)
    }

    @MainActor
    private func finish(_ error: String?) {
        busy = false
        loading.hide()
        statusItem.button?.title = "✎"
        if let error { show(error) }
    }

    @MainActor
    private func send(_ text: String, _ request: RewriteRequest?, app: NSRunningApplication?, saved: [NSPasteboardItem]) {
        guard let request else {
            restore(saved)
            finish(nil)
            return
        }
        nonisolated(unsafe) let saved = saved
        DispatchQueue.global(qos: .userInitiated).async {
            let error = self.process(text, request, app: app, saved: saved)
            Task { @MainActor in self.finish(error) }
        }
    }

    private func copySelection() -> String? {
        let count = pasteboard.changeCount
        press(key: 8)
        guard waitForCopy(after: count) else { return nil }
        return pasteboard.string(forType: .string)
    }

    private func process(_ text: String, _ request: RewriteRequest, app: NSRunningApplication?, saved: [NSPasteboardItem]) -> String? {
        switch AI.rewrite(text, request) {
        case .failure(let error):
            restore(saved)
            return error.message
        case .success(let output) where !request.mode.replacesText:
            restore(saved)
            Task { @MainActor in self.results.show(output, mode: request.mode) }
            return nil
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
