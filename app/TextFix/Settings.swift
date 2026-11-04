import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI

let languages = [
    "English", "German", "Hungarian", "French", "Spanish", "Italian", "Portuguese", "Dutch",
    "Polish", "Czech", "Slovak", "Romanian", "Croatian", "Swedish", "Danish", "Norwegian",
    "Finnish", "Greek", "Turkish", "Ukrainian", "Russian", "Japanese", "Korean", "Chinese (Simplified)",
]

@MainActor
final class SettingsModel: ObservableObject {
    private let hotKeys: HotKeys
    private var monitor: Any?

    @Published var trusted = AXIsProcessTrusted()
    @Published var shortcuts = Dictionary(uniqueKeysWithValues: Mode.allCases.map { ($0, HotKeys.shortcut(for: $0)) })
    @Published var recording: Mode?
    @Published var shortcutError: String?
    @Published var loginError: String?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var language = UserDefaults.standard.string(forKey: "language") ?? "English" {
        didSet { UserDefaults.standard.set(language, forKey: "language") }
    }
    @Published var provider = UserDefaults.standard.string(forKey: "provider").flatMap(Provider.init(rawValue:)) ?? .openAI {
        didSet {
            UserDefaults.standard.set(provider.rawValue, forKey: "provider")
            apiKey = Keychain.key(for: provider) ?? ""
            modelName = UserDefaults.standard.string(forKey: "model.\(provider.rawValue)") ?? provider.defaultModel
            loadModels()
        }
    }
    @Published var apiKey = "" {
        didSet {
            let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != apiKey {
                apiKey = trimmed
                return
            }
            if apiKey != Keychain.key(for: provider) ?? "" { Keychain.set(apiKey, for: provider) }
            testResult = nil
        }
    }
    @Published var modelName = "" {
        didSet {
            UserDefaults.standard.set(modelName, forKey: "model.\(provider.rawValue)")
            testResult = nil
        }
    }
    @Published var models: [String] = []
    @Published var testing = false
    @Published var testResult: (ok: Bool, message: String)?

    init(hotKeys: HotKeys) {
        self.hotKeys = hotKeys
        apiKey = Keychain.key(for: provider) ?? ""
        modelName = UserDefaults.standard.string(forKey: "model.\(provider.rawValue)") ?? provider.defaultModel
    }

    var ready: Bool { (!provider.needsKey || !apiKey.isEmpty) && !modelName.isEmpty }

    func request(for mode: Mode) -> RewriteRequest? {
        guard ready else { return nil }
        return RewriteRequest(mode: mode, language: language, provider: provider, model: modelName, key: apiKey)
    }

    func loadModels() {
        models = []
        guard !provider.needsKey || !apiKey.isEmpty else { return }
        let provider = provider, key = apiKey
        Task.detached {
            let result = AI.models(provider, key: key)
            await MainActor.run {
                guard provider == self.provider, case .success(let models) = result else { return }
                self.models = models
                if self.modelName.isEmpty, let first = models.first { self.modelName = first }
            }
        }
    }

    func test() {
        guard let request = request(for: .grammar) else {
            testResult = (false, provider.needsKey ? "Add your API key first." : "Choose a model first.")
            return
        }
        testing = true
        testResult = nil
        Task.detached {
            let result = AI.rewrite("this sentense have a mistake", request)
            await MainActor.run {
                self.testing = false
                switch result {
                case .success(let text): self.testResult = (true, "It works: \(text)")
                case .failure(let error): self.testResult = (false, error.message)
                }
            }
        }
        loadModels()
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func restart() {
        hotKeys.unregisterAll()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    func record(_ mode: Mode) {
        stopRecording()
        shortcutError = nil
        recording = mode
        hotKeys.unregisterAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event, for: mode)
            return nil
        }
    }

    private func handle(_ event: NSEvent, for mode: Mode) {
        if event.keyCode == 53 {
            stopRecording()
            return
        }
        guard let shortcut = Shortcut(event: event) else {
            shortcutError = "Use at least one of Control, Option or Command, plus a key."
            return
        }
        shortcutError = hotKeys.change(mode, to: shortcut)
        shortcuts[mode] = HotKeys.shortcut(for: mode)
        stopRecording()
    }

    func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording != nil { hotKeys.registerAll() }
        recording = nil
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TextFix").font(.title2.bold())
                        Text("Select text in any app and press a shortcut.").foregroundStyle(.secondary)
                    }
                }
            }

            Section("Permission") {
                if model.trusted {
                    Label("TextFix has Accessibility access.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("TextFix needs Accessibility access to copy and paste your selected text.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("1. Open the settings and turn on TextFix.\n2. Restart TextFix.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Open Accessibility Settings") { model.openAccessibilitySettings() }
                            .buttonStyle(.borderedProminent)
                        Button("Restart TextFix") { model.restart() }
                    }
                }
            }

            Section("AI provider") {
                Picker("Provider", selection: $model.provider) {
                    ForEach(Provider.allCases) { Text($0.title).tag($0) }
                }
                if model.provider.needsKey {
                    SecureField("API key", text: $model.apiKey, prompt: Text("Paste your key"))
                    if let url = model.provider.keyURL {
                        Link("Get an API key from \(model.provider.title)", destination: url).font(.caption)
                    }
                } else {
                    Text("Runs on your Mac with Ollama. No key needed. Install it from ollama.com and download a model.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("Model") {
                    HStack {
                        TextField("Model", text: $model.modelName).labelsHidden()
                        Menu("Choose") {
                            ForEach(model.models, id: \.self) { name in
                                Button(name) { model.modelName = name }
                            }
                        }
                        .fixedSize()
                        .disabled(model.models.isEmpty)
                    }
                }
                HStack {
                    Button("Test") { model.test() }.disabled(model.testing)
                    if model.testing { ProgressView().controlSize(.small) }
                    if let result = model.testResult {
                        Text(result.message)
                            .foregroundStyle(result.ok ? .green : .red)
                            .lineLimit(3)
                            .textSelection(.enabled)
                    }
                }
                Text("Your key stays in the macOS Keychain. TextFix sends the selected text only to the provider you choose.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Shortcuts") {
                ForEach(Mode.allCases, id: \.self) { mode in
                    LabeledContent(mode.title) {
                        Button(model.recording == mode ? "Press a shortcut…" : model.shortcuts[mode]?.label ?? "") {
                            model.recording == mode ? model.stopRecording() : model.record(mode)
                        }
                        .frame(minWidth: 140)
                    }
                }
                if let error = model.shortcutError {
                    Text(error).foregroundStyle(.red)
                }
                Picker("Translate to", selection: $model.language) {
                    ForEach(languages, id: \.self) { Text($0) }
                }
            }

            Section {
                Toggle("Open TextFix at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                if let error = model.loginError {
                    Text(error).foregroundStyle(.red)
                }
                HStack(spacing: 16) {
                    Link("Website", destination: URL(string: "https://textfix.puteanihollakos.com")!)
                    Link("Source code", destination: URL(string: "https://github.com/phollaki/textfix")!)
                    Link("Report a problem", destination: URL(string: "https://github.com/phollaki/textfix/issues")!)
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 440, idealWidth: 480, minHeight: 360, idealHeight: 620)
        .onAppear { model.loadModels() }
        .onReceive(timer) { _ in model.trusted = AXIsProcessTrusted() }
        .onDisappear { model.stopRecording() }
    }
}

@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    let model: SettingsModel
    private var window: NSWindow?

    init(model: SettingsModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "TextFix"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.setContentSize(NSSize(width: 480, height: min(620, (NSScreen.main?.visibleFrame.height ?? 700) - 80)))
            window.center()
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.stopRecording()
        NSApp.setActivationPolicy(.accessory)
    }
}
