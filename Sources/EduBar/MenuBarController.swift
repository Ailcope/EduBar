import AppKit
import SwiftUI

/// Icône de la barre des menus et son popover. Remplace `MenuBarExtra`, qu'aucune API ne sait
/// ouvrir par programme : il en faut une pour le raccourci clavier global.
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    static private(set) var shared: MenuBarController?

    private let model: AppModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var anchorWindow: NSWindow?

    init(model: AppModel) {
        self.model = model
        super.init()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.autosaveName = "EduBar"
        Self.shared = self
        observeLabel()
        model.start()
    }

    func toggle() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            show()
        }
    }

    @objc private func clicked() { toggle() }

    private func show() {
        guard let anchor = anchorView() else { return }
        // Contenu neuf à chaque ouverture : `onAppear` repart, comme avec `MenuBarExtra`.
        let host = NSHostingController(rootView: MenuContent(model: model))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        NSApp.activate()
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    /// L'icône, ou, si un gestionnaire de barre des menus la cache, un point en haut à droite de l'écran.
    private func anchorView() -> NSView? {
        if let button = item.button, let window = button.window,
           NSScreen.screens.contains(where: { $0.frame.contains(window.frame) }) {
            anchorWindow?.orderOut(nil)
            return button
        }
        guard let screen = NSScreen.main else { return nil }
        let visible = screen.visibleFrame
        let window = anchorWindow ?? NSWindow(
            contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.level = .statusBar
        window.setFrame(NSRect(x: visible.maxX - 200, y: visible.maxY - 1, width: 1, height: 1), display: false)
        window.orderFront(nil)
        anchorWindow = window
        return window.contentView
    }

    func popoverDidClose(_ notification: Notification) {
        // Menu refermé : retour à la journée à la réouverture.
        model.dayOffset = 0
        model.showingStats = false
        model.showingWeek = false
        model.weekOffset = 0
        model.reportCopied = false
        model.collapsePanels()
        popover.contentViewController = nil
        anchorWindow?.orderOut(nil)
    }

    /// Titre de l'icône, redessiné dès que `barText` change.
    private func observeLabel() {
        let text = withObservationTracking { model.barText } onChange: { [weak self] in
            Task { @MainActor in self?.observeLabel() }
        }
        guard let button = item.button else { return }
        if text.isEmpty {
            button.title = ""
            button.image = NSImage(systemSymbolName: "graduationcap", accessibilityDescription: "EduBar")
        } else {
            button.image = nil
            button.title = text
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor private var controller: MenuBarController?

    @MainActor func applicationDidFinishLaunching(_ notification: Notification) {
        controller = MenuBarController(model: AppModel())
    }
}

/// Journée, statistiques ou réglages, selon l'état du modèle.
struct MenuContent: View {
    let model: AppModel

    var body: some View {
        Group {
            if model.showingSettings {
                SettingsView(model: model)
            } else if model.showingStats {
                StatsView(model: model)
            } else if model.showingWeek {
                WeekView(model: model)
            } else {
                DayView(model: model, openSettings: model.openSettings)
            }
        }
        .fixedSize()
        .onAppear { model.tick() }
    }
}
