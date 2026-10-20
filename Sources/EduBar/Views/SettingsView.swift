import EduBarCore
import SwiftUI

/// Contenu de la fenêtre « EduBar » : barre latérale des sections, la section choisie à droite.
struct SettingsView: View {
    let model: AppModel
    /// Seulement la section choisie, sans barre latérale ni titre (captures du README).
    var panelOnly = false

    var body: some View {
        // Changement de langue à chaud : lire `language` abonne la vue, l'identité neuve reconstruit tout.
        layout.id(model.language)
    }

    @ViewBuilder
    private var layout: some View {
        if panelOnly {
            VStack(alignment: .leading, spacing: 12) { content(model.panel) }
                .padding(14)
                .frame(width: 340)
        } else {
            HStack(spacing: 0) {
                List(selection: Binding(get: { model.panel }, set: { if let p = $0 { model.panel = p } })) {
                    ForEach(SettingsPanel.allCases) { p in
                        Label(p.title, systemImage: p.symbol).tag(p)
                    }
                }
                .listStyle(.sidebar)
                .frame(width: 200)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(model.panel.title).font(.title2.weight(.semibold))
                        content(model.panel)
                    }
                    .padding(24)
                    .frame(maxWidth: 560, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(minWidth: 620, minHeight: 440)
        }
    }

    @ViewBuilder
    private func content(_ panel: SettingsPanel) -> some View {
        switch panel {
        case .calendar: calendarEditor
        case .account: accountEditor
        case .notifications: notificationsEditor
        case .alternance: alternanceEditor
        case .shortcuts: shortcutsEditor
        case .friend: friendEditor
        case .weather: WeatherEditor(model: model)
        case .templates: templatesEditor
        case .app: appEditor
        }
    }

    // MARK: - Calendrier

    private var calendarEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Source", selection: binding(\.calendarSource)) {
                ForEach(CalendarSource.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if model.calendarSource == .myges {
                caption(L10n.tr(
                    "L'emploi du temps vient de ton compte myGES (section Compte myGES). Rafraîchi toutes les 15 min, 8 semaines à l'avance.",
                    "Your schedule comes from your myGES account (myGES account section). Refreshed every 15 min, 8 weeks ahead."
                ))
                if !model.hasCredentials {
                    Button(L10n.tr("Configurer le compte", "Set up the account")) { model.panel = .account }
                }
                schoolEventsEditor
            } else {
                icalEditor
            }
        }
    }

    private var schoolEventsEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.tr("Évènements de l'école", "School events")).font(.callout.weight(.semibold))
            if model.availableSchoolSeries.isEmpty {
                caption(L10n.tr("Aucun évènement de l'école sur la période chargée.", "No school events in the loaded period."))
            } else {
                caption(L10n.tr(
                    "Conférences, sport et animations publiés dans le planning myGES. Masqués par défaut.",
                    "Talks, sports and activities published in the myGES schedule. Hidden by default."
                ))
                ForEach(model.availableSchoolSeries, id: \.self) { name in
                    Toggle(name, isOn: Binding(
                        get: { model.acceptedSchoolSeries.contains(name) },
                        set: { model.setSchoolSeries(name, accepted: $0) }
                    ))
                }
            }
        }
    }

    private var icalEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("URL du calendrier iCal (Edusign)", "iCal calendar URL (Edusign)")).font(.callout.weight(.semibold))
            TextField("webcal://api.edusign.fr/student/account/ical?…", text: binding(\.feedDraft))
                .textFieldStyle(.roundedBorder)
                .onSubmit(model.saveDraft)
            caption(L10n.tr(
                "Pour l'obtenir : connecte-toi sur Edusign, ouvre la console du navigateur et lance le snippet du README. L'URL reste sur ce Mac, lisible par ta session seulement.",
                "To get it: sign in to Edusign, open the browser console and run the snippet from the README. The URL stays on this Mac, readable by your session only."
            ))
            HStack {
                Button(L10n.tr("Enregistrer", "Save"), action: model.saveDraft)
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
                Label(L10n.tr("Ajouter à Calendrier", "Add to Calendar"), systemImage: "calendar.badge.plus")
            }
            .disabled(model.feedURL == nil)
            .help(L10n.tr(
                "Abonne l'app Calendrier à ce flux : tes cours y apparaissent et restent à jour.",
                "Subscribes the Calendar app to this feed: your classes show up there and stay up to date."
            ))
        }
    }

    // MARK: - Compte myGES

    private var accountEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("Identifiants myGES", "myGES credentials")).font(.callout.weight(.semibold))
            TextField(L10n.tr("Identifiant (p.nom)", "Username (f.lastname)"), text: binding(\.loginDraft))
                .textFieldStyle(.roundedBorder)
                .textContentType(.username)
            SecureField(L10n.tr("Mot de passe", "Password"), text: binding(\.passwordDraft))
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await model.saveCredentials() } }
            caption(L10n.tr(
                "Les mêmes que sur myges.fr. Ils restent sur ce Mac, dans un fichier lisible par ta session seulement (0600), et ne servent qu'à obtenir un jeton auprès de myGES.",
                "The same as on myges.fr. They stay on this Mac, in a file readable by your session only (0600), and are only used to get a token from myGES."
            ))
            HStack {
                Button(L10n.tr("Se connecter", "Sign in")) { Task { await model.saveCredentials() } }
                    .disabled(model.accountSaving || model.loginDraft.isEmpty || model.passwordDraft.isEmpty)
                    .keyboardShortcut(.defaultAction)
                if model.accountSaving { ProgressView().controlSize(.small) }
                if let result = model.accountResult {
                    Label(result.message, systemImage: result.ok ? "checkmark.circle" : "xmark.circle")
                        .font(.caption)
                        .foregroundStyle(result.ok ? .green : .red)
                        .lineLimit(3)
                }
            }
            if model.hasCredentials {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("Connecté : \(model.mygesLogin)", "Signed in: \(model.mygesLogin)")).font(.callout.weight(.medium))
                    if let error = model.grades.lastError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange).lineLimit(3)
                    } else if let updated = model.grades.lastUpdated {
                        caption(L10n.tr(
                            "Notes rafraîchies à \(Display.time(updated, calendar: model.calendar))",
                            "Grades refreshed at \(Display.time(updated, calendar: model.calendar))"
                        ))
                    }
                }
                Button(L10n.tr("Oublier ce compte", "Forget this account"), role: .destructive, action: model.forgetCredentials)
            }
        }
    }

    // MARK: - Application

    private var appEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(L10n.tr("Langue", "Language"), selection: binding(\.language)) {
                ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
            }
            .help(L10n.tr(
                "Appliquée tout de suite, sans relancer l'app.",
                "Applied immediately, no need to relaunch the app."
            ))
            Toggle(L10n.tr("Lancer au démarrage", "Launch at login"), isOn: binding(\.launchAtLogin))
            Picker(L10n.tr("Ouvrir le menu au clavier", "Open the menu with the keyboard"), selection: binding(\.hotKey)) {
                ForEach(HotKeyChoice.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .help(L10n.tr(
                "Depuis n'importe quelle app. Change-le s'il gêne un raccourci d'une autre app.",
                "From any app. Change it if it gets in the way of another app's shortcut."
            ))

            Toggle(L10n.tr("Compter cette installation (anonyme)", "Count this installation (anonymous)"), isOn: binding(\.usageEnabled))
            caption(L10n.tr(
                "Un signal par jour vers edu.mathys.cc : un identifiant tiré au hasard et la version d'EduBar. Ni l'URL, ni le calendrier, ni l'IP ne sont gardés. Sert seulement à savoir combien de personnes utilisent EduBar.",
                "One signal per day to edu.mathys.cc: a random identifier and the EduBar version. Neither the URL, the calendar nor the IP is kept. Only used to know how many people use EduBar."
            ))

            Divider()
            HStack {
                Text("Version \(model.updates.current ?? "dev")").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.updates.checking || model.updates.installing { ProgressView().controlSize(.small) }
                if model.updates.available != nil {
                    Button(model.updates.canInstallInPlace ? L10n.tr("Mettre à jour", "Update") : L10n.tr("Télécharger", "Download"), action: model.updates.install)
                        .disabled(model.updates.installing)
                } else {
                    Button(L10n.tr("Rechercher les mises à jour", "Check for updates"), action: model.updates.checkNow)
                        .disabled(model.updates.checking)
                }
            }
            if let message = model.updates.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(action: model.copyDiagnostic) {
                    Label(L10n.tr("Copier le diagnostic", "Copy diagnostics"), systemImage: "doc.on.clipboard")
                }
                    .font(.caption)
                    .help(L10n.tr(
                        "Version, emplacement, quarantaine, dernier rafraîchissement… Jamais l'URL du calendrier.",
                        "Version, location, quarantine, last refresh… Never the calendar URL."
                    ))
                if model.diagnosticCopied {
                    Text(L10n.tr("Copié, colle-le dans ton message.", "Copied, paste it into your message.")).font(.caption).foregroundStyle(.green)
                }
            }
        }
    }

    // MARK: - Textes

    private static var fields: [(label: String, path: WritableKeyPath<BarTemplates, String>)] {
        [
            (L10n.tr("En cours, pause ensuite", "In class, break next"), \.beforeBreak),
            (L10n.tr("En cours, déjeuner ensuite", "In class, lunch next"), \.beforeLunch),
            (L10n.tr("Dernier cours de la journée", "Last class of the day"), \.lastClass),
            (L10n.tr("Dernier cours de la semaine", "Last class of the week"), \.lastOfWeek),
            (L10n.tr("En pause", "On break"), \.onBreak),
            (L10n.tr("Pendant le déjeuner", "During lunch"), \.onLunch),
            (L10n.tr("Avant le premier cours", "Before the first class"), \.beforeFirst),
            (L10n.tr("Changement de salle (15 min avant)", "Room change (15 min before)"), \.roomChange),
            (L10n.tr("Journée finie", "Day over"), \.dayOver),
            (L10n.tr("Examen demain ou tout à l'heure", "Exam tomorrow or soon"), \.examSoon),
            (L10n.tr("Journée en entreprise", "Day at the company"), \.company),
            (L10n.tr("Météo (prochain cours loin)", "Weather (next class far away)"), \.weather),
        ]
    }

    private var templatesEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr(
                "Émojis et textes libres. Variables : {temps}, {salle}, {jour}. Météo : {meteo}, {temp}, {ville}, {jour}. Un champ vide reprend le texte par défaut.",
                "Emojis and free text. Variables: {temps}, {salle}, {jour}. Weather: {meteo}, {temp}, {ville}, {jour}. An empty field uses the default text."
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(L10n.tr("Annoncer le week-end au dernier cours de la semaine", "Announce the weekend at the last class of the week"), isOn: binding(\.announceWeekend))
                .font(.caption)
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
            Button(L10n.tr("Rétablir les textes par défaut", "Restore default texts")) { model.templates = .defaults }
                .font(.caption)
                .disabled(model.templates.isDefault)
        }
        .font(.body.weight(.regular))
    }

    // MARK: - Notifications

    private static var kinds: [(label: String, event: String, kind: NotificationKind)] {
        [
            (L10n.tr("Fin de cours", "End of class"), L10n.tr("avant la fin", "before the end"), .classEnd),
            (L10n.tr("Début de cours", "Start of class"), L10n.tr("avant le début", "before the start"), .classStart),
            (L10n.tr("Changement de salle", "Room change"), L10n.tr("avant la fin du cours", "before the class ends"), .roomChange),
        ]
    }

    private var notificationsEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr(
                "Variables : {cours}, {heure}, {temps}, {salle}, {pause}. Un champ vide reprend le texte par défaut. Si rien n'arrive, autorise EduBar dans Réglages Système > Notifications.",
                "Variables: {cours}, {heure}, {temps}, {salle}, {pause}. An empty field uses the default text. If nothing shows up, allow EduBar in System Settings > Notifications."
            ))
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
                        Button(L10n.tr("Tester", "Test")) { model.testNotification(item.kind) }
                            .font(.caption)
                    }
                    if rule.enabled {
                        Stepper(
                            rule.minutes == 0 ? L10n.tr("Au moment même", "Right at the time") : "\(rule.minutes) min \(item.event)",
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
                    Toggle(L10n.tr("Changements d'emploi du temps", "Schedule changes"), isOn: binding(\.notifyScheduleChanges))
                        .font(.callout.weight(.medium))
                    Spacer()
                    Button(L10n.tr("Tester", "Test"), action: model.testScheduleChange)
                        .font(.caption)
                }
                Text(L10n.tr(
                    "Cours annulé, déplacé, ajouté ou changement de salle dans les deux semaines à venir.",
                    "Class cancelled, moved, added or room changed within the next two weeks."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Toggle(L10n.tr("Nouvelle note", "New grade"), isOn: binding(\.notifyNewGrades))
                        .font(.callout.weight(.medium))
                    Spacer()
                    Button(L10n.tr("Tester", "Test"), action: model.testNewGrade)
                        .font(.caption)
                }
                caption(L10n.tr(
                    "Dès qu'une note apparaît sur myGES (vérifié toutes les 15 min). Nécessite un compte myGES.",
                    "As soon as a grade appears on myGES (checked every 15 min). Requires a myGES account."
                ))
            }
            .disabled(!model.hasCredentials)
            Button(L10n.tr("Rétablir les notifications par défaut", "Restore default notifications")) { model.notifications = .defaults }
                .font(.caption)
                .disabled(model.notifications.isDefault)
        }
        .font(.body.weight(.regular))
    }

    // MARK: - Alternance

    private static var weekdays: [(label: String, day: Int)] {
        L10n.current == .fr
            ? [("L", 2), ("M", 3), ("M", 4), ("J", 5), ("V", 6)]
            : [("M", 2), ("T", 3), ("W", 4), ("T", 5), ("F", 6)]
    }

    private var alternanceEditor: some View {
        let a = model.alternance
        return VStack(alignment: .leading, spacing: 8) {
            Picker(L10n.tr("Rythme", "Schedule"), selection: Binding(
                get: { model.alternance.mode },
                set: { mode in
                    if mode == .weeks, model.alternance.schoolAnchor == nil {
                        model.alternance.schoolAnchor = model.calendar.dateInterval(of: .weekOfYear, for: Date())?.start
                    }
                    model.alternance.mode = mode
                }
            )) {
                Text(L10n.tr("Pas d'alternance", "No work-study")).tag(Alternance.Mode.off)
                Text(L10n.tr("Automatique", "Automatic")).tag(Alternance.Mode.auto)
                Text(L10n.tr("Jours fixes", "Fixed days")).tag(Alternance.Mode.weekdays)
                Text(L10n.tr("Semaines alternées", "Alternating weeks")).tag(Alternance.Mode.weeks)
            }
            .font(.callout)

            switch a.mode {
            case .off:
                caption(L10n.tr(
                    "Choisis ton rythme : les jours en entreprise, la barre affiche « 🏢 Entreprise · école Lun. 9h ».",
                    "Choose your schedule: on company days, the menu bar shows “🏢 Work · school Mon 9 AM”."
                ))
            case .auto:
                caption(L10n.tr(
                    "Un jour de semaine sans cours dans le calendrier compte comme un jour en entreprise.",
                    "A weekday with no class in the calendar counts as a company day."
                ))
            case .weekdays:
                HStack(spacing: 6) {
                    Text(L10n.tr("En entreprise :", "At the company:")).font(.caption)
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
                Stepper(L10n.tr("École : \(a.schoolWeeks) semaine\(a.schoolWeeks > 1 ? "s" : "")",
                                "School: \(a.schoolWeeks) week\(a.schoolWeeks > 1 ? "s" : "")"),
                        value: binding(\.alternance.schoolWeeks), in: 1...12)
                    .font(.caption)
                Stepper(L10n.tr("Entreprise : \(a.companyWeeks) semaine\(a.companyWeeks > 1 ? "s" : "")",
                                "Company: \(a.companyWeeks) week\(a.companyWeeks > 1 ? "s" : "")"),
                        value: binding(\.alternance.companyWeeks), in: 1...12)
                    .font(.caption)
                DatePicker(L10n.tr("Début d'une période d'école", "Start of a school period"), selection: Binding(
                    get: { model.alternance.schoolAnchor ?? Date() },
                    set: { model.alternance.schoolAnchor = $0 }
                ), displayedComponents: .date)
                .datePickerStyle(.field)
                .font(.caption)
            }
            if a.mode != .off {
                caption(L10n.tr(
                    "Un jour avec des cours reste toujours un jour d'école. Aujourd'hui : "
                        + (model.isCompanyDay(Date()) ? "entreprise." : "école ou repos."),
                    "A day with classes is always a school day. Today: "
                        + (model.isCompanyDay(Date()) ? "company." : "school or day off.")
                ))
            }
        }
        .font(.body.weight(.regular))
    }

    // MARK: - Raccourcis

    private var shortcutsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            caption(L10n.tr(
                "Lance un raccourci de l'app Raccourcis quand une suite de cours commence et quand elle finit (activer un mode Concentration, couper le son…).",
                "Runs a shortcut from the Shortcuts app when a run of classes starts and when it ends (turn on a Focus mode, mute the sound…)."
            ))
            shortcutPicker(L10n.tr("Début des cours", "Classes start"), \.shortcuts.atStart)
            shortcutPicker(L10n.tr("Fin des cours", "Classes end"), \.shortcuts.atEnd)
            if model.availableShortcuts.isEmpty {
                caption(L10n.tr(
                    "Aucun raccourci trouvé : crée-en un dans l'app Raccourcis.",
                    "No shortcut found: create one in the Shortcuts app."
                ))
            }
        }
        .font(.body.weight(.regular))
        .onAppear(perform: model.loadShortcuts)
    }

    private func shortcutPicker(_ label: String, _ path: ReferenceWritableKeyPath<AppModel, String>) -> some View {
        let current = model[keyPath: path]
        let names = model.availableShortcuts + (current.isEmpty || model.availableShortcuts.contains(current) ? [] : [current])
        return HStack {
            Picker(label, selection: binding(path)) {
                Text(L10n.tr("Aucun", "None")).tag("")
                ForEach(names, id: \.self) { Text($0).tag($0) }
            }
            .font(.callout)
            Button(L10n.tr("Tester", "Test")) { ShortcutRunner.run(current) }
                .font(.caption)
                .disabled(current.isEmpty)
        }
    }

    // MARK: - Pauses communes

    private var friendEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            caption(L10n.tr(
                "Colle l'URL Edusign d'un pote (il la récupère comme toi) : EduBar affiche vos pauses communes et l'heure à laquelle il finit. Jusqu'à 3 potes. Les URL restent sur ce Mac, rien n'est envoyé.",
                "Paste a friend's Edusign URL (they get it the same way you do): EduBar shows your shared breaks and when they finish. Up to 3 friends. URLs stay on this Mac, nothing is sent."
            ))
            Picker(L10n.tr("Pote", "Friend"), selection: Binding(get: { model.friendSlot }, set: model.selectFriend)) {
                ForEach(0..<FeedFile.friendSlots, id: \.self) { i in
                    Text(model.friendURLs[i] == nil ? L10n.tr("Pote \(i + 1)", "Friend \(i + 1)") : model.friendLabel(i)).tag(i)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            TextField(L10n.tr("Prénom", "First name"), text: Binding(
                get: { model.friendNames[model.friendSlot] },
                set: { model.friendNames[model.friendSlot] = $0 }
            ))
                .textFieldStyle(.roundedBorder)
                .font(.callout)
            TextField("webcal://…", text: binding(\.friendDraft))
                .textFieldStyle(.roundedBorder)
                .font(.callout)
                .onSubmit(model.saveFriend)
            HStack {
                Button(L10n.tr("Enregistrer", "Save"), action: model.saveFriend)
                    .font(.caption)
                if let result = model.friendResult {
                    Label(result.message, systemImage: result.ok ? "checkmark.circle" : "xmark.circle")
                        .font(.caption)
                        .foregroundStyle(result.ok ? .green : .red)
                        .lineLimit(2)
                }
            }
            caption(L10n.tr(
                "Champ vide puis Enregistrer : son calendrier est oublié.",
                "Empty field then Save: their calendar is forgotten."
            ))
        }
        .font(.body.weight(.regular))
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
