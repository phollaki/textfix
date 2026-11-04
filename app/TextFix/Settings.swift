import AppKit
import ApplicationServices
import ServiceManagement
import StoreKit
import SwiftUI

let languages = [
    "English", "German", "Hungarian", "French", "Spanish", "Italian", "Portuguese", "Dutch",
    "Polish", "Czech", "Slovak", "Romanian", "Croatian", "Swedish", "Danish", "Norwegian",
    "Finnish", "Greek", "Turkish", "Ukrainian", "Russian", "Japanese", "Korean", "Chinese (Simplified)",
]

@MainActor
final class SettingsModel: ObservableObject {
    let store: Store
    private let hotKeys: HotKeys
    private var monitor: Any?

    @Published var trusted = AXIsProcessTrusted()
    @Published var shortcuts = Dictionary(uniqueKeysWithValues: Mode.allCases.map { ($0, HotKeys.shortcut(for: $0)) })
    @Published var recording: Mode?
    @Published var shortcutError: String?
    @Published var usage: Usage?
    @Published var storeError: String?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var language = UserDefaults.standard.string(forKey: "language") ?? "English" {
        didSet { UserDefaults.standard.set(language, forKey: "language") }
    }

    init(store: Store, hotKeys: HotKeys) {
        self.store = store
        self.hotKeys = hotKeys
        store.onChange = { [weak self] in self?.refreshUsage() }
    }

    func refreshUsage() {
        Task { if let usage = await API.usage(transaction: store.transaction) { self.usage = usage } }
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
        } catch {
            storeError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func buy(_ product: Product) {
        Task { storeError = await store.buy(product) }
    }

    func restore() {
        Task { storeError = await store.restore() }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var store: Store
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

            Section("Plan") {
                if let usage = model.usage {
                    LabeledContent(usage.plan == "pro" ? "TextFix Pro" : "Free") {
                        Text("\(usage.used) of \(usage.limit.formatted()) rewrites this month")
                    }
                    ProgressView(value: Double(min(usage.used, usage.limit)), total: Double(usage.limit))
                }
                if store.transaction == nil {
                    ForEach(store.products, id: \.id) { product in
                        Button("\(product.displayName): \(product.displayPrice) \(period(product))") { model.buy(product) }
                    }
                    Text("Pro gives you 2,000 rewrites a month. The subscription renews automatically until you cancel it in your App Store settings.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Link("Manage subscription", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                }
                Button("Restore purchases") { model.restore() }
                if let error = model.storeError {
                    Text(error).foregroundStyle(.red)
                }
            }

            Section {
                Toggle("Open TextFix at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                HStack(spacing: 16) {
                    Link("Privacy", destination: API.website.appendingPathComponent("privacy.html"))
                    Link("Terms", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    Link("Support", destination: API.website.appendingPathComponent("support.html"))
                }
                .font(.caption)
                Text("Your ID: \(API.installId)")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 440, idealWidth: 480, minHeight: 360, idealHeight: 620)
        .onReceive(timer) { _ in model.trusted = AXIsProcessTrusted() }
        .onDisappear { model.stopRecording() }
    }

    private func period(_ product: Product) -> String {
        product.subscription?.subscriptionPeriod.unit == .year ? "a year" : "a month"
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
            window.contentView = NSHostingView(rootView: SettingsView(model: model, store: model.store))
            window.setContentSize(NSSize(width: 480, height: min(620, (NSScreen.main?.visibleFrame.height ?? 700) - 80)))
            window.center()
            self.window = window
        }
        model.refreshUsage()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.stopRecording()
        NSApp.setActivationPolicy(.accessory)
    }
}
