import AppKit
import SwiftUI

struct PaletteChoice {
    let mode: Mode
    var instruction = ""
}

struct PaletteItem: Identifiable {
    let id: Int
    let group: String
    let title: String
    let hint: String
    let choice: PaletteChoice
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    init(content: some View) {
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hosting = NSHostingView(rootView: content)
        contentView = hosting
        setContentSize(hosting.fittingSize)
    }

    func showNearTop() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let area = screen?.visibleFrame {
            setFrameOrigin(NSPoint(x: area.midX - frame.width / 2, y: area.maxY - area.height * 0.18 - frame.height))
        }
        makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class PaletteState: ObservableObject {
    @Published var query = "" {
        didSet { selected = 0 }
    }
    @Published var selected = 0
    let language: String

    init(language: String) {
        self.language = language
    }

    var items: [PaletteItem] {
        let actions: [(String, Mode, String, String)] = [
            ("Rewrite", .rephrase, "Rephrase", "Sounds like a native speaker wrote it"),
            ("Rewrite", .grammar, "Fix grammar", "Fixes mistakes, keeps your words"),
            ("Rewrite", .translate, "Translate to \(language)", "Change the language in Settings"),
            ("Rewrite", .shorter, "Make it shorter", "Same message, fewer words"),
            ("Understand", .tldr, "TL;DR", "Short summary, your text stays"),
            ("Understand", .replies, "Reply ideas", "Three short answers to choose from"),
            ("Understand", .explain, "Explain", "What it means, in plain words"),
            ("Create", .prompt, "Prompt from my text", "Turns your notes into a clear AI prompt to copy"),
        ]
        let search = query.trimmingCharacters(in: .whitespaces)
        var items = actions
            .filter { search.isEmpty || $0.2.localizedCaseInsensitiveContains(search) || $0.3.localizedCaseInsensitiveContains(search) }
            .enumerated()
            .map { PaletteItem(id: $0.offset, group: $0.element.0, title: $0.element.2, hint: $0.element.3, choice: PaletteChoice(mode: $0.element.1)) }
        if !search.isEmpty {
            items.append(PaletteItem(id: items.count, group: "Your instruction", title: search, hint: "Apply this to the selected text", choice: PaletteChoice(mode: .custom, instruction: search)))
        }
        return items
    }

    func move(_ step: Int) {
        selected = min(max(selected + step, 0), max(items.count - 1, 0))
    }
}

struct PaletteView: View {
    @ObservedObject var state: PaletteState
    let pick: (PaletteChoice) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        let items = state.items
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Type an action or your own instruction…", text: $state.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .focused($focused)
            }
            .padding(16)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(items) { item in
                            if item.id == 0 || items[item.id - 1].group != item.group {
                                Text(item.group.uppercased())
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.top, 8)
                            }
                            row(item, selected: item.id == state.selected)
                                .id(item.id)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: state.selected) { _, selected in proxy.scrollTo(selected) }
            }
            .frame(height: 450)
            Divider()
            Text("↑↓ move   ↵ run   esc close")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .frame(width: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .onAppear { focused = true }
    }

    private func row(_ item: PaletteItem, selected: Bool) -> some View {
        Button { pick(item.choice) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                Text(item.hint).font(.caption).foregroundStyle(selected ? .white.opacity(0.85) : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(selected ? .white : .primary)
            .background(selected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

@MainActor
final class Palette: NSObject, NSWindowDelegate {
    private var panel: FloatingPanel?
    private var monitor: Any?
    private var completion: ((PaletteChoice?) -> Void)?

    func show(language: String, completion: @escaping (PaletteChoice?) -> Void) {
        self.completion = completion
        let state = PaletteState(language: language)
        let panel = FloatingPanel(content: PaletteView(state: state) { [weak self] in self?.close($0) })
        panel.delegate = self
        self.panel = panel
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 125: state.move(1)
            case 126: state.move(-1)
            case 36, 76:
                let items = state.items
                if items.indices.contains(state.selected) { close(items[state.selected].choice) }
            case 53: close(nil)
            default: return event
            }
            return nil
        }
        panel.showNearTop()
    }

    func windowDidResignKey(_ notification: Notification) {
        close(nil)
    }

    private func close(_ choice: PaletteChoice?) {
        guard let completion else { return }
        self.completion = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        panel?.orderOut(nil)
        panel = nil
        completion(choice)
    }
}

@MainActor
final class ResultPanel: NSObject, NSWindowDelegate {
    private var panel: FloatingPanel?
    private var monitor: Any?

    func show(_ text: String, mode: Mode) {
        close()
        let parts = mode == .replies ? Self.replies(in: text) : [text]
        let panel = FloatingPanel(content: ResultView(title: mode.title, parts: parts) { [weak self] copied in
            if let copied {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(copied, forType: .string)
            }
            self?.close()
        })
        panel.delegate = self
        self.panel = panel
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.close()
            return nil
        }
        panel.showNearTop()
    }

    nonisolated static func replies(in text: String) -> [String] {
        var parts = [""]
        for line in text.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                parts.append("")
            } else {
                parts[parts.count - 1] += line + "\n"
            }
        }
        let replies = parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return replies.isEmpty ? [text] : replies
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    private func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

struct ResultView: View {
    let title: String
    let parts: [String]
    let done: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button("Close") { done(nil) }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(parts.indices, id: \.self) { index in
                        VStack(alignment: .trailing, spacing: 8) {
                            Text(parts[index])
                                .font(.system(size: 14))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Button(parts.count > 1 ? "Copy this reply" : "Copy") { done(parts[index]) }
                        }
                        .padding(12)
                        .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .frame(maxHeight: 460)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
