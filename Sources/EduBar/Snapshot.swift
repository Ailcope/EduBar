import AppKit
import SwiftUI

/// `EduBar --snapshot <dossier> [--at "yyyy-MM-dd HH:mm"]` : rend le popover et les réglages en PNG
/// (à partir du cache) puis quitte. Sert aux captures du README et à vérifier le rendu.
@MainActor
enum Snapshot {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let model = AppModel(readKeychainNow: true)
        if let j = args.firstIndex(of: "--at"), j + 1 < args.count {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd HH:mm"
            model.frozenNow = f.date(from: args[j + 1])
        }
        model.tick()

        let bar = Text(model.barText.isEmpty ? "(icône seule)" : model.barText).padding(6)
        write(bar, to: dir.appendingPathComponent("bar.png"))
        write(DayView(model: model, openSettings: {}), to: dir.appendingPathComponent("day.png"))
        model.openSettings()
        // Jamais la vraie URL (jetons d'accès) dans une capture.
        model.feedDraft = "webcal://api.edusign.fr/student/account/ical?…"
        model.panel = .templates
        write(SettingsView(model: model), to: dir.appendingPathComponent("settings.png"))
        model.panel = .notifications
        write(SettingsView(model: model), to: dir.appendingPathComponent("notifications.png"))
        model.panel = .alternance
        write(SettingsView(model: model), to: dir.appendingPathComponent("alternance.png"))
        let alternance = model.alternance
        model.alternance.mode = .weekdays
        write(SettingsView(model: model), to: dir.appendingPathComponent("alternance-days.png"))
        model.alternance.mode = .weeks
        model.alternance.schoolAnchor = model.alternance.schoolAnchor ?? model.now
        write(SettingsView(model: model), to: dir.appendingPathComponent("alternance-weeks.png"))
        model.alternance = alternance
        model.panel = .shortcuts
        write(SettingsView(model: model), to: dir.appendingPathComponent("shortcuts.png"))
        model.panel = nil
        write(SettingsView(model: model), to: dir.appendingPathComponent("settings-closed.png"))
        write(StatsView(model: model), to: dir.appendingPathComponent("stats.png"))
        model.step(1)
        write(DayView(model: model, openSettings: {}), to: dir.appendingPathComponent("day-next.png"))
        print("bar: \(model.barText)")
        exit(0)
    }

    private static func write(_ view: some View, to url: URL) {
        // Vue AppKit hors écran plutôt qu'ImageRenderer, qui ne dessine pas les contrôles (boutons, champs).
        for (appearance, suffix) in [(NSAppearance.Name.aqua, ""), (.darkAqua, "-dark")] {
            let host = NSHostingView(rootView: view
                .fixedSize()
                .background(appearance == .darkAqua ? Color(white: 0.16) : Color(white: 0.96)))
            host.appearance = NSAppearance(named: appearance)
            let size = host.fittingSize
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false
            )
            window.appearance = host.appearance
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { continue }
            let name = url.deletingPathExtension().lastPathComponent + suffix + ".png"
            try? png.write(to: url.deletingLastPathComponent().appendingPathComponent(name))
        }
    }
}
