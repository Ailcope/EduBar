import EduBarCore
import SwiftUI

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: model.closeSettings) { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                Text("Réglages").font(.headline)
            }
            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("URL du calendrier Edusign").font(.callout.weight(.semibold))
                TextField("webcal://api.edusign.fr/student/account/ical?…", text: binding(\.feedDraft))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(model.saveDraft)
                Text("Pour l'obtenir : connecte-toi sur Edusign, ouvre la console du navigateur et lance le snippet du README. L'URL reste sur ce Mac, lisible par ta session seulement.")
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
                Button(action: model.subscribeInCalendar) {
                    Label("Ajouter à Calendrier", systemImage: "calendar.badge.plus")
                }
                .disabled(model.feedURL == nil)
                .help("Abonne l'app Calendrier à ce flux : tes cours y apparaissent et restent à jour.")
            }

            Divider()
            Toggle("Lancer au démarrage", isOn: binding(\.launchAtLogin))

            Divider()
            group("Notifications", .notifications) { notificationsEditor }
            group("Alternance", .alternance) { alternanceEditor }
            group("Raccourcis", .shortcuts) { shortcutsEditor }
            group("Personnaliser les textes", .templates) { templatesEditor }

            Divider()
            HStack {
                Text("Version \(model.updates.current ?? "dev")").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.updates.checking || model.updates.installing { ProgressView().controlSize(.small) }
                if model.updates.available != nil {
                    Button(model.updates.canInstallInPlace ? "Mettre à jour" : "Télécharger", action: model.updates.install)
                        .disabled(model.updates.installing)
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
        // Menu refermé pendant les réglages : volets repliés à la réouverture.
        .onDisappear(perform: model.collapsePanels)
    }

    // Un seul volet ouvert à la fois : le popover n'a pas de défilement.
    private func group(_ title: String, _ panel: SettingsPanel, @ViewBuilder content: @escaping () -> some View) -> some View {
        DisclosureGroup(title, isExpanded: Binding(
            get: { model.panel == panel },
            set: { model.panel = $0 ? panel : (model.panel == panel ? nil : model.panel) }
        ), content: content)
        .font(.callout.weight(.semibold))
    }

    // MARK: - Textes

    private static let fields: [(label: String, path: WritableKeyPath<BarTemplates, String>)] = [
        ("En cours, pause ensuite", \.beforeBreak),
        ("En cours, déjeuner ensuite", \.beforeLunch),
        ("Dernier cours de la journée", \.lastClass),
        ("En pause", \.onBreak),
        ("Pendant le déjeuner", \.onLunch),
        ("Avant le premier cours", \.beforeFirst),
        ("Changement de salle (15 min avant)", \.roomChange),
        ("Journée finie", \.dayOver),
        ("Examen demain ou tout à l'heure", \.examSoon),
        ("Journée en entreprise", \.company),
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

    // MARK: - Notifications

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
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Toggle("Changements d'emploi du temps", isOn: binding(\.notifyScheduleChanges))
                        .font(.callout.weight(.medium))
                    Spacer()
                    Button("Tester", action: model.testScheduleChange)
                        .font(.caption)
                }
                Text("Cours annulé, déplacé, ajouté ou changement de salle dans les deux semaines à venir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Rétablir les notifications par défaut") { model.notifications = .defaults }
                .font(.caption)
                .disabled(model.notifications == .defaults)
        }
        .font(.body.weight(.regular))
        .padding(.top, 6)
    }

    // MARK: - Alternance

    private static let weekdays: [(label: String, day: Int)] = [("L", 2), ("M", 3), ("M", 4), ("J", 5), ("V", 6)]

    private var alternanceEditor: some View {
        let a = model.alternance
        return VStack(alignment: .leading, spacing: 8) {
            Picker("Rythme", selection: Binding(
                get: { model.alternance.mode },
                set: { mode in
                    if mode == .weeks, model.alternance.schoolAnchor == nil {
                        model.alternance.schoolAnchor = model.calendar.dateInterval(of: .weekOfYear, for: Date())?.start
                    }
                    model.alternance.mode = mode
                }
            )) {
                Text("Pas d'alternance").tag(Alternance.Mode.off)
                Text("Automatique").tag(Alternance.Mode.auto)
                Text("Jours fixes").tag(Alternance.Mode.weekdays)
                Text("Semaines alternées").tag(Alternance.Mode.weeks)
            }
            .font(.callout)

            switch a.mode {
            case .off:
                caption("Choisis ton rythme : les jours en entreprise, la barre affiche « 🏢 Entreprise · école Lun. 9h ».")
            case .auto:
                caption("Un jour de semaine sans cours dans le calendrier compte comme un jour en entreprise.")
            case .weekdays:
                HStack(spacing: 6) {
                    Text("En entreprise :").font(.caption)
                    ForEach(Self.weekdays, id: \.day) { d in
                        Toggle(d.label, isOn: Binding(
                            get: { model.alternance.companyWeekdays.contains(d.day) },
                            set: { on in
                                if on { model.alternance.companyWeekdays.insert(d.day) }
                                else { model.alternance.companyWeekdays.remove(d.day) }
                            }
                        ))
                        .toggleStyle(.button)
                        .controlSize(.small)
                    }
                }
            case .weeks:
                Stepper("École : \(a.schoolWeeks) semaine\(a.schoolWeeks > 1 ? "s" : "")",
                        value: binding(\.alternance.schoolWeeks), in: 1...12)
                    .font(.caption)
                Stepper("Entreprise : \(a.companyWeeks) semaine\(a.companyWeeks > 1 ? "s" : "")",
                        value: binding(\.alternance.companyWeeks), in: 1...12)
                    .font(.caption)
                DatePicker("Début d'une période d'école", selection: Binding(
                    get: { model.alternance.schoolAnchor ?? Date() },
                    set: { model.alternance.schoolAnchor = $0 }
                ), displayedComponents: .date)
                .datePickerStyle(.field)
                .font(.caption)
            }
            if a.mode != .off {
                caption("Un jour avec des cours reste toujours un jour d'école. Aujourd'hui : "
                    + (model.isCompanyDay(Date()) ? "entreprise." : "école ou repos."))
            }
        }
        .font(.body.weight(.regular))
        .padding(.top, 6)
    }

    // MARK: - Raccourcis

    private var shortcutsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            caption("Lance un raccourci de l'app Raccourcis quand une suite de cours commence et quand elle finit (activer un mode Concentration, couper le son…).")
            shortcutPicker("Début des cours", \.shortcuts.atStart)
            shortcutPicker("Fin des cours", \.shortcuts.atEnd)
            if model.availableShortcuts.isEmpty {
                caption("Aucun raccourci trouvé : crée-en un dans l'app Raccourcis.")
            }
        }
        .font(.body.weight(.regular))
        .padding(.top, 6)
        .onAppear(perform: model.loadShortcuts)
    }

    private func shortcutPicker(_ label: String, _ path: ReferenceWritableKeyPath<AppModel, String>) -> some View {
        let current = model[keyPath: path]
        let names = model.availableShortcuts + (current.isEmpty || model.availableShortcuts.contains(current) ? [] : [current])
        return HStack {
            Picker(label, selection: binding(path)) {
                Text("Aucun").tag("")
                ForEach(names, id: \.self) { Text($0).tag($0) }
            }
            .font(.callout)
            Button("Tester") { ShortcutRunner.run(current) }
                .font(.caption)
                .disabled(current.isEmpty)
        }
    }

    // MARK: - Aides

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func binding<T>(_ path: ReferenceWritableKeyPath<AppModel, T>) -> Binding<T> {
        Binding(get: { model[keyPath: path] }, set: { model[keyPath: path] = $0 })
    }
}
