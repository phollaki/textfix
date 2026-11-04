import AppKit
import Carbon

let textFix = TextFix()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.delegate = textFix
MainActor.assumeIsolated { textFix.start() }

var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
    var id = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
    if let hotKey = HotKey(rawValue: id.id) { MainActor.assumeIsolated { textFix.run(hotKey) } }
    return noErr
}, 1, &eventType, nil, nil)

app.run()
