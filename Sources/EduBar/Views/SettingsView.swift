import EduBarCore
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
            Toggle("Lancer au démarrage", isOn: binding(\.launchAtLogin))

            Divider()
            // Un seul volet ouvert à la fois : le popover n'a pas de défilement.
            DisclosureGroup("Notifications", isExpanded: Binding(
                get: { model.showingNotifications },
                set: { model.showingNotifications = $0; if $0 { model.showingTemplates = false } }
            )) {
                notificationsEditor
            }
            .font(.callout.weight(.semibold))
            DisclosureGroup("Personnaliser les textes", isExpanded: Binding(
                get: { model.showingTemplates },
                set: { model.showingTemplates = $0; if $0 { model.showingNotifications = false } }
            )) {
                templatesEditor
            }
            .font(.callout.weight(.semibold))

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

    private static let fields: [(label: String, path: WritableKeyPath<BarTemplates, String>)] = [
        ("En cours, pause ensuite", \.beforeBreak),
        ("En cours, déjeuner ensuite", \.beforeLunch),
        ("Dernier cours de la journée", \.lastClass),
        ("En pause", \.onBreak),
        ("Pendant le déjeuner", \.onLunch),
        ("Avant le premier cours", \.beforeFirst),
        ("Changement de salle (15 min avant)", \.roomChange),
        ("Journée finie", \.dayOver),
    ]

    private var templatesEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Émojis et textes libres. Variables : {temps}, {salle}, {jour}. Un champ vide reprend le texte par défaut.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Self.fields, id: \.label) { field in
                VStack(alignment: .leading, spacing: 2) {
                    Text(field.label).font(.caption).foregroundStyle(.secondary)
                    TextField(
                        BarTemplates.defaults[keyPath: field.path],
                        text: binding((\AppModel.templates).appending(path: field.path))
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                }
            }
            Button("Rétablir les textes par défaut") { model.templates = .defaults }
                .font(.caption)
                .disabled(model.templates == .defaults)
        }
        .font(.body.weight(.regular))
        .padding(.top, 6)
    }

    private static let kinds: [(label: String, event: String, kind: NotificationKind)] = [
        ("Fin de cours", "avant la fin", .classEnd),
        ("Début de cours", "avant le début", .classStart),
        ("Changement de salle", "avant la fin du cours", .roomChange),
    ]

    private var notificationsEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Variables : {cours}, {heure}, {temps}, {salle}, {pause}. Un champ vide reprend le texte par défaut. Si rien n'arrive, autorise EduBar dans Réglages Système > Notifications.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Self.kinds, id: \.label) { item in
                let path = (\AppModel.notifications).appending(path: item.kind.path)
                let rule = model[keyPath: path]
                let fallback = NotificationRules.defaults[keyPath: item.kind.path]
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Toggle(item.label, isOn: binding(path.appending(path: \.enabled)))
                            .font(.callout.weight(.medium))
                        Spacer()
                        Button("Tester") { model.testNotification(item.kind) }
                            .font(.caption)
                    }
                    if rule.enabled {
                        Stepper(
                            rule.minutes == 0 ? "Au moment même" : "\(rule.minutes) min \(item.event)",
                            value: binding(path.appending(path: \.minutes)), in: 0...60
                        )
                        .font(.caption)
                        TextField(fallback.title, text: binding(path.appending(path: \.title)))
                            .textFieldStyle(.roundedBorder)
                            .font(.callout)
                        TextField(fallback.body, text: binding(path.appending(path: \.body)))
                            .textFieldStyle(.roundedBorder)
                            .font(.callout)
                    }
                }
            }
            Button("Rétablir les notifications par défaut") { model.notifications = .defaults }
                .font(.caption)
                .disabled(model.notifications == .defaults)
        }
        .font(.body.weight(.regular))
        .padding(.top, 6)
    }

    private func binding<T>(_ path: ReferenceWritableKeyPath<AppModel, T>) -> Binding<T> {
        Binding(get: { model[keyPath: path] }, set: { model[keyPath: path] = $0 })
    }
}
