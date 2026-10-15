import AppKit
import SwiftUI

/// La fenêtre « EduBar » (réglages) : une `NSWindow` standard, redimensionnable, une seule instance.
/// Ouverte, l'app passe au premier plan avec une icône au Dock et une place dans Cmd-Tab ;
/// fermée, elle redevient une app de barre des menus.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let startSize = NSSize(width: 820, height: 560)
    static let minSize = NSSize(width: 620, height: 440)
    static let autosaveName = "FenetreReglagesEduBar"

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
        w.title = "EduBar"
        w.isReleasedWhenClosed = false
        w.tabbingMode = .disallowed
        w.contentMinSize = Self.minSize
        let host = NSHostingController(rootView: SettingsView(model: model))
        // La fenêtre décide de sa taille, pas le contenu SwiftUI.
        host.sizingOptions = []
        w.contentViewController = host
        w.setContentSize(Self.startSize)
        w.center()
        // Reprend la position mémorisée s'il y en a une, et la mémorise ensuite.
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
