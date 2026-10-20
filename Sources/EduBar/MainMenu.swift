import AppKit
import EduBarCore

/// Menu principal minimal. Sans lui, une app de barre des menus n'a aucun menu Édition :
/// Cmd+C, Cmd+V, Cmd+X et Cmd+A ne font rien dans les champs de la fenêtre de réglages.
/// Réinstallé quand la langue change (`AppDelegate`).
@MainActor
enum MainMenu {
    static func install() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: L10n.tr("Quitter EduBar", "Quit EduBar"),
            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: L10n.tr("Édition", "Edit"))
        edit.addItem(withTitle: L10n.tr("Annuler", "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: L10n.tr("Rétablir", "Redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(withTitle: L10n.tr("Couper", "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L10n.tr("Copier", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L10n.tr("Coller", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(
            withTitle: L10n.tr("Tout sélectionner", "Select All"),
            action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }
}
