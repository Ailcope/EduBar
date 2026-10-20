import AppKit
import EduBarCore
import Observation
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
    private let settingsWindow: SettingsWindow
    private let gradesWindow: GradesWindow

    init(model: AppModel) {
        self.model = model
        settingsWindow = SettingsWindow(model: model)
        gradesWindow = GradesWindow(model: model)
        super.init()
        model.presentSettings = { [weak self] in
            self?.popover.performClose(nil)
            self?.settingsWindow.show()
        }
        model.presentGrades = { [weak self] in
            self?.popover.performClose(nil)
            self?.gradesWindow.show()
        }
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.autosaveName = "EduBar"
        Self.shared = self
        observeLabel()
        observeLanguage()
        model.start()
        #if DEBUG
        // Vérif visuelle : `EDUBAR_SETTINGS=1 .build/debug/EduBar` ouvre la fenêtre au lancement.
        if ProcessInfo.processInfo.environment["EDUBAR_SETTINGS"] != nil { model.openSettings() }
        // Idem pour la fenêtre Notes : `EDUBAR_GRADES=1`.
        if ProcessInfo.processInfo.environment["EDUBAR_GRADES"] != nil { model.openGrades() }
        // Langue forcée au lancement : `EDUBAR_LANG=en`. Puis, 6 s plus tard, bascule à chaud : `EDUBAR_LANG_SWITCH=fr`.
        if let next = ProcessInfo.processInfo.environment["EDUBAR_LANG_SWITCH"].flatMap(AppLanguage.init) {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(6))
                self.model.language = next
            }
        }
        #endif
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
        popover.contentViewController = nil
        anchorWindow?.orderOut(nil)
    }

    /// Changement de langue à chaud : menu principal et titres de fenêtres. Le contenu des fenêtres et du
    /// popover se reconstruit seul (`.id(model.language)` sur leur racine), la barre via `observeLabel`.
    private func observeLanguage() {
        withObservationTracking { _ = model.language } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                MainMenu.install()
                self.gradesWindow.retitle()
                self.observeLanguage()
            }
        }
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
        MainMenu.install()
        controller = MenuBarController(model: AppModel())
    }
}

/// Journée, semaine ou statistiques, selon l'état du modèle. Les réglages ont leur fenêtre.
struct MenuContent: View {
    let model: AppModel

    var body: some View {
        Group {
            if model.showingStats {
                StatsView(model: model)
            } else if model.showingWeek {
                WeekView(model: model)
            } else {
                DayView(model: model, openSettings: model.openSettings)
            }
        }
        .id(model.language)
        .fixedSize()
        .onAppear { model.tick() }
    }
}
