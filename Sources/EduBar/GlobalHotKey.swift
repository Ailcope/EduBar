import AppKit
import Carbon.HIToolbox

/// Combinaisons proposées pour ouvrir le menu d'EduBar depuis n'importe quelle app.
enum HotKeyChoice: String, CaseIterable {
    case optionCommandE, controlOptionE, controlOptionCommandE, off

    var label: String {
        switch self {
        case .optionCommandE: "⌥⌘E"
        case .controlOptionE: "⌃⌥E"
        case .controlOptionCommandE: "⌃⌥⌘E"
        case .off: "Aucun"
        }
    }

    fileprivate var modifiers: UInt32? {
        switch self {
        case .optionCommandE: UInt32(optionKey | cmdKey)
        case .controlOptionE: UInt32(controlKey | optionKey)
        case .controlOptionCommandE: UInt32(controlKey | optionKey | cmdKey)
        case .off: nil
        }
    }
}

/// Raccourci global via Carbon : pas besoin de l'autorisation Accessibilité.
@MainActor
enum GlobalHotKey {
    private static var hotKey: EventHotKeyRef?
    private static var handler: EventHandlerRef?

    static func register(_ choice: HotKeyChoice) {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        guard let modifiers = choice.modifiers else { return }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                MainActor.assumeIsolated { GlobalHotKey.toggleMenu() }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x4544_4241), id: 1) // « EDBA »
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_E), modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr { NSLog("EduBar: raccourci \(choice.label) indisponible (\(status))") }
    }

    /// Ouvre ou referme le menu, comme un clic sur l'icône.
    static func toggleMenu() {
        MenuBarController.shared?.toggle()
    }
}
