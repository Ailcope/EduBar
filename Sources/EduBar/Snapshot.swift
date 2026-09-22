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
        model.showingTemplates = true
        write(SettingsView(model: model), to: dir.appendingPathComponent("settings.png"))
        print("bar: \(model.barText)")
        exit(0)
    }

    private static func write(_ view: some View, to url: URL) {
        for (scheme, suffix) in [(ColorScheme.light, ""), (.dark, "-dark")] {
            let r = ImageRenderer(content: view
                .environment(\.colorScheme, scheme)
                .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.96)))
            r.scale = 2
            guard let img = r.nsImage, let tiff = img.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else { continue }
            let name = url.deletingPathExtension().lastPathComponent + suffix + ".png"
            try? png.write(to: url.deletingLastPathComponent().appendingPathComponent(name))
        }
    }
}
