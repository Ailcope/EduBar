import AppKit
import EduBarCore
import Foundation
import Observation
import ServiceManagement

/// Volets des réglages (un seul ouvert à la fois : le popover n'a pas de défilement).
enum SettingsPanel {
    case notifications, alternance, shortcuts, friend, templates
}

@MainActor @Observable
final class AppModel {
    private(set) var now = Date()
    private(set) var feedURL: URL?
    let store = CalendarStore()
    let updates = UpdateChecker()
    let calendar = Calendar.autoupdatingCurrent

    /// Notifications personnalisées dans les réglages.
    var notifications: NotificationRules { didSet { Self.persist(notifications, "notificationRules") } }
    /// Textes de la barre personnalisés dans les réglages.
    var templates: BarTemplates { didSet { Self.persist(templates, "barTemplates") } }
    var alternance: Alternance { didSet { Self.persist(alternance, "alternance") } }
    var shortcuts: ShortcutSettings { didSet { Self.persist(shortcuts, "shortcuts") } }
    /// Prévenir quand un cours est annulé, déplacé, ajouté ou change de salle.
    var notifyScheduleChanges: Bool {
        didSet { UserDefaults.standard.set(notifyScheduleChanges, forKey: "notifyScheduleChanges") }
    }

    /// Raccourci global qui ouvre le menu.
    var hotKey: HotKeyChoice {
        didSet {
            UserDefaults.standard.set(hotKey.rawValue, forKey: "hotKey")
            if frozenNow == nil { GlobalHotKey.register(hotKey) }
        }
    }

    /// Calendriers de potes (3 au plus), pour les pauses communes. Lus comme le tien, rien n'est envoyé.
    private(set) var friendURLs: [URL?]
    let friendStores = (0..<FeedFile.friendSlots).map {
        CalendarStore(cacheName: $0 == 0 ? "friend.ics" : "friend-\($0 + 1).ics")
    }
    var friendNames: [String] {
        didSet {
            for (i, name) in friendNames.enumerated() { UserDefaults.standard.set(name, forKey: Self.friendNameKey(i)) }
        }
    }
    /// Pote affiché dans les réglages.
    private(set) var friendSlot = 0
    var friendDraft = ""
    var reportCopied = false
    var friendResult: (ok: Bool, message: String)?
    var diagnosticCopied = false

    // État de l'UI (pas de @State : c'est une macro que les Command Line Tools ne savent pas développer avec le SDK macOS 27).
    var showingSettings = false
    var showingStats = false
    var showingWeek = false
    /// Décalage en semaines de la vue semaine par rapport à celle du jour affiché.
    var weekOffset = 0
    var feedDraft = ""
    var saveResult: (ok: Bool, message: String)?
    var saving = false
    var panel: SettingsPanel?
    /// Décalage en jours du jour affiché par rapport au jour par défaut (flèches ← →).
    var dayOffset = 0
    /// Raccourcis de l'app Raccourcis, lus à l'ouverture du volet.
    private(set) var availableShortcuts: [String] = []
    private(set) var installMessage: String?

    @ObservationIgnored private let notifier = Notifier()
    @ObservationIgnored private var started = false
    @ObservationIgnored private var ranShortcuts: Set<String> = []

    /// Faux tant que l'URL n'est pas lue (la migration depuis le Trousseau peut attendre une autorisation).
    private(set) var feedLoaded = false

    /// `readKeychainNow` : lecture synchrone, pour le mode `--snapshot` seulement.
    init(readKeychainNow: Bool = false) {
        let defaults = UserDefaults.standard
        if let rules: NotificationRules = Self.load("notificationRules") {
            notifications = rules
        } else {
            // Réglage de la v0.2 : seulement l'alerte de changement de salle.
            var rules = NotificationRules.defaults
            rules.roomChange.enabled = defaults.object(forKey: "notifyRoomChanges") as? Bool ?? true
            notifications = rules
        }
        templates = Self.load("barTemplates") ?? .defaults
        alternance = Self.load("alternance") ?? .defaults
        shortcuts = Self.load("shortcuts") ?? .defaults
        notifyScheduleChanges = defaults.object(forKey: "notifyScheduleChanges") as? Bool ?? true
        hotKey = defaults.string(forKey: "hotKey").flatMap(HotKeyChoice.init) ?? .optionCommandE
        friendNames = (0..<FeedFile.friendSlots).map { defaults.string(forKey: Self.friendNameKey($0)) ?? "" }
        friendURLs = (0..<FeedFile.friendSlots).map { FeedFile.friend($0).read().flatMap(FeedURL.normalize) }
        if readKeychainNow {
            feedURL = Self.loadFeed().flatMap(FeedURL.normalize)
            feedLoaded = true
        }
    }

    /// `friendName` (celui de la v0.5), puis `friendName2`, `friendName3`.
    private static func friendNameKey(_ slot: Int) -> String { slot == 0 ? "friendName" : "friendName\(slot + 1)" }

    private static func persist(_ value: some Encodable, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    // MARK: - État dérivé

    var schedule: Schedule { Schedule(courses: snapshotCourses ?? store.courses) }
    var status: Status { schedule.status(at: now, calendar: calendar) }
    var alert: RoomAlert? {
        RoomChange.alert(for: status, at: now, lead: TimeInterval(max(0, notifications.roomChange.minutes) * 60))
    }
    var barText: String {
        guard feedURL != nil else { return "" }
        let text = Display.barText(
            status: status, alert: alert, now: now, calendar: calendar, templates: templates,
            companyToday: isCompanyDay(now)
        )
        // Planning peut-être périmé : visible sans ouvrir le menu.
        guard staleSince != nil else { return text }
        return text.isEmpty ? "⚠︎" : text + " ⚠︎"
    }

    /// « 26 h » : durée depuis le dernier chargement réussi du flux, s'il date de plus d'un jour.
    var staleSince: String? {
        guard feedURL != nil, frozenNow == nil else { return nil }
        return Freshness.staleSince(store.lastUpdated, now: now)
    }

    func isCompanyDay(_ day: Date) -> Bool {
        alternance.isCompanyDay(day, schedule: schedule, calendar: calendar)
    }

    /// Prochaines vacances. En alternance « automatique », une semaine sans cours est une semaine en
    /// entreprise : impossible de distinguer des vacances, rien n'est affiché.
    var vacation: Vacation? {
        guard alternance.mode != .auto else { return nil }
        return Vacations.next(from: now, schedule: schedule, calendar: calendar, isCompanyDay: isCompanyDay)
    }

    /// Indice de couleur par matière (voir `SubjectPalette`).
    var subjectColors: [String: Int] {
        SubjectColors.assign(schedule.courses.map(\.subjectKey), count: SubjectPalette.colors.count)
    }

    /// Potes configurés, dans l'ordre des réglages.
    var friends: [(name: String, schedule: Schedule)] {
        if let snapshotFriends { return snapshotFriends }
        return friendURLs.indices.compactMap { i in
            friendURLs[i] == nil ? nil : (friendLabel(i), Schedule(courses: friendStores[i].courses))
        }
    }

    /// Potes factices du mode `--snapshot` (jamais un vrai calendrier dans une capture).
    @ObservationIgnored var snapshotFriends: [(name: String, schedule: Schedule)]?

    /// Cours anonymisés du mode `--snapshot --demo` (captures du README).
    @ObservationIgnored var snapshotCourses: [Course]?

    func friendLabel(_ slot: Int) -> String {
        let name = friendNames[slot].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Pote \(slot + 1)" : name
    }

    /// Jour affiché par défaut : aujourd'hui s'il reste des cours, sinon le prochain jour de cours.
    var baseDay: Date {
        let today = schedule.courses(on: now, calendar: calendar)
        if today.contains(where: { $0.end > now }) { return now }
        guard let next = schedule.courses.first(where: { $0.start > now }) else { return now }
        return next.start
    }

    var shownDay: Date { calendar.date(byAdding: .day, value: dayOffset, to: baseDay) ?? baseDay }

    /// Jour suivant ou précédent, en sautant les week-ends sans cours.
    func step(_ delta: Int) {
        var offset = dayOffset
        repeat {
            offset += delta
            let day = calendar.date(byAdding: .day, value: offset, to: baseDay) ?? baseDay
            if !calendar.isDateInWeekend(day) || !schedule.courses(on: day, calendar: calendar).isEmpty { break }
        } while abs(offset) < 90
        dayOffset = max(-90, min(90, offset))
    }

    // MARK: - Boucles

    func start() {
        guard !started else { return }
        started = true
        notifier.requestAuthorization()
        announceUpdateIfJustInstalled()
        GlobalHotKey.register(hotKey)
        updates.onFound = { [weak self] r in
            self?.notifier.send(PendingNotification(
                id: "available-\(r.version)", title: "EduBar \(r.version) disponible",
                body: "Clique pour la télécharger, ou ouvre le menu d'EduBar.", url: r.dmg ?? r.page
            ))
        }

        // Hors du fil principal : une demande d'accès au Trousseau (migration) ne doit pas figer la barre.
        Task {
            let raw = await Task.detached { Self.loadFeed() }.value
            feedURL = raw.flatMap(FeedURL.normalize)
            feedLoaded = true
            await refresh()
        }
        // Horloge : toutes les 30 s, calée sur :00 et :30.
        Task {
            while !Task.isCancelled {
                let wait = 30 - Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 30)
                try? await Task.sleep(for: .seconds(wait))
                tick()
            }
        }
        // Rafraîchissement du flux toutes les 15 min ; mises à jour de l'app toutes les 6 h.
        Task {
            await updates.checkIfDue()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15 * 60))
                await refresh()
                await updates.checkIfDue()
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.tick()
                Task { await self.refresh() }
            }
        }
        tick()
    }

    /// Heure figée (mode `--snapshot`).
    @ObservationIgnored var frozenNow: Date?

    func tick() {
        now = frozenNow ?? Date()
        guard frozenNow == nil else { return }
        for n in notifications.due(schedule: schedule, at: now, calendar: calendar) { notifier.send(n) }
        for run in shortcuts.due(schedule: schedule, at: now, calendar: calendar)
        where ranShortcuts.insert(run.id).inserted {
            ShortcutRunner.run(run.name)
        }
    }

    /// Après une mise à jour automatique, le premier lancement de la nouvelle version l'annonce.
    /// Un clic sur la notification ouvre les notes de version.
    private func announceUpdateIfJustInstalled() {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: UpdateChecker.updatedFromKey) != nil else { return }
        defaults.removeObject(forKey: UpdateChecker.updatedFromKey)
        let version = updates.current ?? "?"
        notifier.send(PendingNotification(
            id: "updated-\(version)", title: "EduBar est à jour",
            body: "Version \(version) installée, tes réglages sont conservés. Clique pour voir les nouveautés.",
            url: URL(string: "https://github.com/Ailcope/EduBar/releases/tag/v\(version)")
        ))
    }

    /// Envoie tout de suite un exemple de la notification (réglages).
    func testNotification(_ kind: NotificationKind) {
        notifier.send(notifications.sample(kind))
    }

    func testScheduleChange() {
        let start = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
            .addingTimeInterval(14 * 3600)
        let sample = Course(
            id: "test-\(Date().timeIntervalSince1970)", title: "Langage C avancé",
            start: start, end: start.addingTimeInterval(90 * 60), room: "501"
        )
        for n in ScheduleDiff.notifications([.cancelled(sample)], now: Date(), calendar: calendar) {
            notifier.send(PendingNotification(id: n.id, title: n.title, body: n.body))
        }
    }

    /// Recharge le flux. `announceChanges` : prévenir des cours annulés, déplacés, ajoutés.
    func refresh(announceChanges: Bool = true) async {
        let before = store.courses
        let stamp = store.lastUpdated
        await store.refresh(from: feedURL)
        if frozenNow == nil {
            for (i, friend) in friendStores.enumerated() { await friend.refresh(from: friendURLs[i]) }
        }
        if announceChanges, notifyScheduleChanges, frozenNow == nil, store.lastUpdated != stamp {
            let changes = ScheduleDiff.changes(from: before, to: store.courses, now: Date())
            for n in ScheduleDiff.notifications(changes, now: Date(), calendar: calendar) { notifier.send(n) }
        }
        tick()
    }

    // MARK: - Réglages

    /// L'URL enregistrée. Jusqu'à la v0.3.2 elle était dans le Trousseau : on l'y reprend une fois
    /// et on la déplace dans le fichier, qui survit aux mises à jour sans redemander d'accès.
    nonisolated static func loadFeed() -> String? {
        let file = FeedFile.standard
        if let value = file.read() { return value }
        guard let old = Keychain.get("feedURL") else { return nil }
        if (try? file.write(old)) != nil { Keychain.set(nil, for: "feedURL") }
        return old
    }

    /// Teste l'URL puis l'enregistre. Renvoie un message à afficher.
    func save(feed raw: String) async -> (ok: Bool, message: String) {
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            FeedFile.standard.remove()
            Keychain.set(nil, for: "feedURL")
            feedURL = nil
            store.clear()
            return (true, "URL supprimée.")
        }
        guard let url = FeedURL.normalize(raw) else {
            return (false, "URL invalide : elle doit commencer par webcal:// ou https://.")
        }
        do {
            let (_, courses) = try await CalendarStore.fetch(url)
            try FeedFile.standard.write(url.absoluteString)
            // Autre calendrier : ses différences avec l'ancien ne sont pas des changements.
            let changed = url != feedURL
            // Ni son cache ni ses journées archivées ne se mélangent au nouveau.
            if changed { store.clear() }
            feedURL = url
            await refresh(announceChanges: !changed)
            return (true, "\(courses.count) cours trouvés.")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    /// Pote affiché dans les réglages : son URL remplace le champ.
    func selectFriend(_ slot: Int) {
        friendSlot = slot
        friendDraft = friendURLs[slot]?.absoluteString ?? ""
        friendResult = nil
    }

    /// Calendrier du pote affiché : même vérification que le tien, fichier à part (0600). Champ vide : supprimé.
    func saveFriend() {
        let raw = friendDraft, slot = friendSlot
        let file = FeedFile.friend(slot), store = friendStores[slot]
        friendResult = nil
        Task {
            if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                file.remove()
                friendURLs[slot] = nil
                store.clear()
                friendResult = (true, "Calendrier retiré.")
                return
            }
            guard let url = FeedURL.normalize(raw) else {
                friendResult = (false, "URL invalide : elle doit commencer par webcal:// ou https://.")
                return
            }
            do {
                let (_, courses) = try await CalendarStore.fetch(url)
                try file.write(url.absoluteString)
                if url != friendURLs[slot] { store.clear() }
                friendURLs[slot] = url
                await store.refresh(from: url)
                friendResult = (true, "\(courses.count) cours trouvés.")
            } catch {
                friendResult = (false, error.localizedDescription)
            }
        }
    }

    /// Infos utiles pour déboguer, copiées dans le presse-papiers. Jamais d'URL ni de jeton.
    func copyDiagnostic() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnosticText(), forType: .string)
        diagnosticCopied = true
    }

    func diagnosticText() -> String {
        let friendCounts = friendURLs.indices.filter { friendURLs[$0] != nil }
            .map { "\(friendStores[$0].courses.count) cours" }.joined(separator: ", ")
        let app = Bundle.main.bundleURL
        let quarantine = getxattr(app.path, "com.apple.quarantine", nil, 0, 0, 0) >= 0
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return Diagnostic.render([
            ("Version", updates.current ?? "dev"),
            ("macOS", "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"),
            ("Emplacement", UpdateInstaller.isTranslocated ? "isolée par macOS (App Translocation)"
                : app.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")),
            ("Depuis le .dmg", UpdateInstaller.diskImageVolume == nil ? "non" : "oui"),
            ("Quarantaine", quarantine ? "oui" : "non"),
            ("Mise à jour sur place", UpdateInstaller.canReplaceSelf ? "possible" : "impossible"),
            ("Calendrier", feedURL == nil ? "non configuré" : "configuré"),
            ("Cours", "\(store.courses.count)"),
            ("Dernière mise à jour", store.lastUpdated.map { $0.formatted(.iso8601) } ?? "jamais"),
            ("Erreur", store.lastError ?? "aucune"),
            ("Potes", friendCounts.isEmpty ? "aucun" : friendCounts),
            ("Alternance", alternance.mode.rawValue),
            ("Raccourci", hotKey.label),
            ("Mise à jour dispo", updates.available?.version.description ?? "non"),
        ])
    }

    /// Abonne l'app Calendrier au flux (elle le tient à jour elle-même).
    func subscribeInCalendar() {
        guard let url = feedURL, var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        c.scheme = "webcal"
        guard let webcal = c.url else { return }
        let app = URL(fileURLWithPath: "/System/Applications/Calendar.app")
        NSWorkspace.shared.open([webcal], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    func loadShortcuts() {
        Task {
            availableShortcuts = await Task.detached { ShortcutRunner.list() }.value
        }
    }

    /// Lancée depuis l'image disque : se copie dans Applications, s'y relance et éjecte l'image.
    func installInApplications() {
        installMessage = nil
        do {
            let installed = try UpdateInstaller.copyToApplications()
            UpdateInstaller.relaunch(at: installed, ejecting: UpdateInstaller.diskImageVolume)
        } catch {
            installMessage = "Installation impossible : \(error.localizedDescription) Glisse EduBar dans Applications."
        }
    }

    /// Relevé d'heures faites par mois et par matière, collable dans un tableur.
    func copyReport() {
        let months = Report.monthly(schedule.courses, now: now, calendar: calendar)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Report.table(months, calendar: calendar), forType: .string)
        reportCopied = true
    }

    /// Semaine du jour affiché.
    func openWeek() {
        weekOffset = 0
        showingWeek = true
    }

    var shownWeek: Date { calendar.date(byAdding: .weekOfYear, value: weekOffset, to: shownDay) ?? shownDay }

    /// Clic sur un jour de la vue semaine : retour à la journée, sur ce jour-là.
    func showDay(_ day: Date) {
        let base = calendar.startOfDay(for: baseDay)
        dayOffset = calendar.dateComponents([.day], from: base, to: calendar.startOfDay(for: day)).day ?? 0
        showingWeek = false
    }

    func openSettings() {
        feedDraft = feedURL?.absoluteString ?? ""
        friendDraft = friendURLs[friendSlot]?.absoluteString ?? ""
        saveResult = nil
        friendResult = nil
        diagnosticCopied = false
        panel = nil
        showingStats = false
        showingSettings = true
    }

    /// Replie les volets avant de revenir à la journée : la fenêtre du menu garde sinon leur hauteur.
    func closeSettings() {
        panel = nil
        showingSettings = false
    }

    func collapsePanels() {
        panel = nil
    }

    func saveDraft() {
        saving = true
        saveResult = nil
        Task {
            saveResult = await save(feed: feedDraft)
            saving = false
        }
    }

    private(set) var launchAtLoginRevision = 0

    var launchAtLogin: Bool {
        get { _ = launchAtLoginRevision; return SMAppService.mainApp.status == .enabled }
        set {
            defer { launchAtLoginRevision += 1 }
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("EduBar: lancement au démarrage impossible: \(error.localizedDescription)")
            }
        }
    }
}
