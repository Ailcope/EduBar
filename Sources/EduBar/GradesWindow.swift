import AppKit
import SwiftUI

/// La fenêtre « Notes » : tableau de notes façon myGES, une seule instance.
/// Même principe que `SettingsWindow` : au premier plan avec une icône au Dock tant qu'elle est ouverte.
@MainActor
final class GradesWindow: NSObject, NSWindowDelegate {
    static let startSize = NSSize(width: 1100, height: 600)
    static let minSize = NSSize(width: 760, height: 400)
    static let autosaveName = "FenetreNotesEduBar"

    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    /// Ouvre la fenêtre, ou la ramène devant si elle l'est déjà.
    func show() {
        let w = window ?? make()
        window = w
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        if w.isMiniaturized { w.deminiaturize(nil) }
        w.makeKeyAndOrderFront(nil)
    }

    private func make() -> NSWindow {
        let w = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.startSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        w.title = "Notes"
        w.isReleasedWhenClosed = false
        w.tabbingMode = .disallowed
        w.contentMinSize = Self.minSize
        let host = NSHostingController(rootView: GradesTableView(model: model))
        // La fenêtre décide de sa taille, pas le contenu SwiftUI.
        host.sizingOptions = []
        w.contentViewController = host
        w.setContentSize(Self.startSize)
        w.center()
        w.setFrameAutosaveName(Self.autosaveName)
        w.delegate = self
        return w
    }

    func windowWillClose(_ notification: Notification) {
        // Plus aucune autre fenêtre : retour à l'app de barre des menus (ni Dock, ni Cmd-Tab).
        let closing = notification.object as? NSWindow
        if !NSApp.windows.contains(where: { $0.isVisible && $0 !== closing && $0.styleMask.contains(.titled) }) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
