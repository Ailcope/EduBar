import SwiftUI

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { model.showingSettings = false } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                Text("Réglages").font(.headline)
            }
            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("URL du calendrier Edusign").font(.callout.weight(.semibold))
                TextField("webcal://api.edusign.fr/student/account/ical?…", text: binding(\.feedDraft))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(model.saveDraft)
                Text("Pour l'obtenir : connecte-toi sur Edusign, ouvre la console du navigateur et lance le snippet du README. L'URL reste sur ce Mac (Trousseau).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Enregistrer", action: model.saveDraft)
                        .disabled(model.saving)
                        .keyboardShortcut(.defaultAction)
                    if model.saving { ProgressView().controlSize(.small) }
                    if let result = model.saveResult {
                        Label(result.message, systemImage: result.ok ? "checkmark.circle" : "xmark.circle")
                            .font(.caption)
                            .foregroundStyle(result.ok ? .green : .red)
                            .lineLimit(2)
                    }
                }
            }

            Divider()
            Toggle("Prévenir 15 min avant un changement de salle", isOn: binding(\.notifyRoomChanges))
            Toggle("Lancer au démarrage", isOn: binding(\.launchAtLogin))

            Divider()
            HStack {
                Text("Version \(model.updates.current ?? "dev")").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.updates.checking { ProgressView().controlSize(.small) }
                if model.updates.available != nil {
                    Button("Télécharger", action: model.updates.install)
                } else {
                    Button("Rechercher les mises à jour", action: model.updates.checkNow)
                        .disabled(model.updates.checking)
                }
            }
            if let message = model.updates.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private func binding<T>(_ path: ReferenceWritableKeyPath<AppModel, T>) -> Binding<T> {
        Binding(get: { model[keyPath: path] }, set: { model[keyPath: path] = $0 })
    }
}
