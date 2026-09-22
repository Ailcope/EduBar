import AppKit
import SwiftUI

@main
struct EduBarApp: App {
    // Pas de @State (macro indisponible sans Xcode avec le SDK macOS 27) : l'App n'est créée qu'une fois.
    private let model = AppModel()

    init() {
        Snapshot.runIfRequested()
        // Utile hors bundle (`swift run`) ; dans le .app, LSUIElement fait déjà le travail.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            Group {
                if model.showingSettings {
                    SettingsView(model: model)
                } else {
                    DayView(model: model, openSettings: model.openSettings)
                }
            }
            .fitsMenuWindow()
            .onAppear { model.tick() }
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        Group {
            let text = model.barText
            if text.isEmpty {
                Image(systemName: "graduationcap")
            } else {
                Text(text)
            }
        }
        .task { model.start() }
    }
}
