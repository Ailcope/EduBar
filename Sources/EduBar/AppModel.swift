import AppKit
import EduBarCore
import Foundation
import Observation
import ServiceManagement

/// Sections de la fenêtre de réglages, dans l'ordre de la barre latérale.
enum SettingsPanel: CaseIterable, Identifiable {
    case calendar, notifications, alternance, shortcuts, friend, weather, templates, app

    var id: Self { self }

    var title: String {
        switch self {
        case .calendar: "Calendrier"
        case .notifications: "Notifications"
        case .alternance: "Alternance"
        case .shortcuts: "Raccourcis"
        case .friend: "Pauses communes"
        case .weather: "Météo"
        case .templates: "Textes de la barre"
        case .app: "Application"
        }
    }

    var symbol: String {
        switch self {
        case .calendar: "calendar"
        case .notifications: "bell"
        case .alternance: "building.2"
        case .shortcuts: "square.stack.3d.up"
        case .friend: "person.2"
        case .weather: "cloud.sun"
        case .templates: "textformat"
        case .app: "gearshape"
        }
    }
}

/// D'où viennent les cours du compte principal.
enum CalendarSource: String, Codable, CaseIterable, Identifiable {
    case ical, myges

    var id: Self { self }

    var title: String {
        switch self {
        case .ical: "Flux iCal (Edusign)"
        case .myges: "Compte myGES"
        }
    }
}

@MainActor @Observable
final class AppModel {
    private(set) var now = Date()
    private(set) var feedURL: URL?
    let store = CalendarStore()
    let grades = GradesStore()
    let updates = UpdateChecker()
    let calendar = Calendar.autoupdatingCurrent

    /// Notifications personnalisées dans les réglages.
    var notifications: NotificationRules { didSet { Self.persist(notifications, "notificationRules") } }
    /// Textes de la barre personnalisés dans les réglages.
    var templates: BarTemplates { didSet { Self.persist(templates, "barTemplates") } }
    var alternance: Alternance { didSet { Self.persist(alternance, "alternance") } }
    var shortcuts: ShortcutSettings { didSet { Self.persist(shortcuts, "shortcuts") } }
    /// Météo à la place du prochain cours quand il est loin.
    var weather: WeatherSettings {
        didSet {
            Self.persist(weather, "weather")
            if !weather.enabled || weather.place == nil { weatherStore.clear() }
            refreshWeatherIfWanted()
        }
    }
    let weatherStore = WeatherStore()
    var weatherDraft = ""
    /// La recherche de ville remplit le campus (alerte pluie) plutôt que la ville affichée.
    var weatherForCampus = false {
        didSet {
            weatherResults = []
            weatherMessage = nil
        }
    }
    private(set) var weatherResults: [WeatherPlace] = []
    private(set) var weatherSearching = false
    private(set) var weatherMessage: String?

    /// Pendant le dernier cours de la semaine, la barre annonce le week-end.
    var announceWeekend: Bool {
        didSet { UserDefaults.standard.set(announceWeekend, forKey: "announceWeekend") }
    }

    /// Prévenir quand un cours est annulé, déplacé, ajouté ou change de salle.
    var notifyScheduleChanges: Bool {
        didSet { UserDefaults.standard.set(notifyScheduleChanges, forKey: "notifyScheduleChanges") }
    }

    /// Source du calendrier principal (les calendriers des potes restent en iCal).
    var calendarSource: CalendarSource {
        didSet { UserDefaults.standard.set(calendarSource.rawValue, forKey: "calendarSource") }
    }

    /// Identifiants myGES, lus sur disque au démarrage. Le mot de passe ne sort jamais du modèle.
    private(set) var credentials: MyGESCredentials?
    var hasCredentials: Bool { credentials != nil }
    /// Login seul, pour l'affichage.
    var mygesLogin: String { credentials?.login ?? "" }
    /// Brouillons des réglages du compte myGES.
    var loginDraft = ""
    var passwordDraft = ""
    var accountResult: (ok: Bool, message: String)?
    var accountSaving = false

    /// Prévenir à chaque nouvelle note.
    var notifyNewGrades: Bool {
        didSet { UserDefaults.standard.set(notifyNewGrades, forKey: "notifyNewGrades") }
    }

    /// Une source de cours est configurée : l'URL pour iCal, les identifiants pour myGES.
    var hasSource: Bool {
        switch calendarSource {
        case .ical: feedURL != nil
        case .myges: credentials != nil
        }
    }

    /// Client réseau myGES ; il relit les identifiants à chaque connexion.
    @ObservationIgnored private let credentialBox = CredentialBox()
    @ObservationIgnored private lazy var client = MyGESClient { [credentialBox] in credentialBox.value }

    /// Signal anonyme quotidien vers edu.mathys.cc (activé par défaut).
    var usageEnabled: Bool {
        didSet { UserDefaults.standard.set(usageEnabled, forKey: UsageReporter.enabledKey) }
    }
    @ObservationIgnored private let usage = UsageReporter()

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
    var showingStats = false
    var showingWeek = false
    /// Vue des notes myGES ; à remettre à faux avec `showingWeek` et `showingStats` (fermeture du popover).
    var showingGrades = false
    /// Décalage en semaines de la vue semaine par rapport à celle du jour affiché.
    var weekOffset = 0
    var feedDraft = ""
    var saveResult: (ok: Bool, message: String)?
    var saving = false
    var panel: SettingsPanel = .calendar
    /// Ouvre la fenêtre de réglages ; posé par `MenuBarController`.
    @ObservationIgnored var presentSettings: () -> Void = {}
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
        weather = Self.load("weather") ?? .defaults
        notifyNewGrades = defaults.object(forKey: "notifyNewGrades") as? Bool ?? true
        calendarSource = defaults.string(forKey: "calendarSource").flatMap(CalendarSource.init)
            ?? (MyGESCredentialsFile.standard.read() != nil ? .myges
                : FeedFile.standard.read() != nil ? .ical : .myges)
        announceWeekend = defaults.object(forKey: "announceWeekend") as? Bool ?? true
        notifyScheduleChanges = defaults.object(forKey: "notifyScheduleChanges") as? Bool ?? true
        usageEnabled = defaults.object(forKey: UsageReporter.enabledKey) as? Bool ?? true
        hotKey = defaults.string(forKey: "hotKey").flatMap(HotKeyChoice.init) ?? .optionCommandE
        friendNames = (0..<FeedFile.friendSlots).map { defaults.string(forKey: Self.friendNameKey($0)) ?? "" }
        friendURLs = (0..<FeedFile.friendSlots).map { FeedFile.friend($0).read().flatMap(FeedURL.normalize) }
        if readKeychainNow {
            feedURL = Self.loadFeed().flatMap(FeedURL.normalize)
            credentials = MyGESCredentialsFile.read()
            credentialBox.value = credentials
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
        guard hasSource else { return "" }
        let text = Display.barText(
            status: status, alert: alert, now: now, calendar: calendar, templates: templates,
            companyToday: isCompanyDay(now), weather: shownWeather,
            weekend: announceWeekend && schedule.endsWeek(status, calendar: calendar, isCompanyDay: isCompanyDay)
        )
        // Planning peut-être périmé : visible sans ouvrir le menu.
        guard staleSince != nil else { return text }
        return text.isEmpty ? "⚠︎" : text + " ⚠︎"
    }

    /// « 26 h » : durée depuis le dernier chargement réussi du flux, s'il date de plus d'un jour.
    var staleSince: String? {
        guard hasSource, frozenNow == nil else { return nil }
        return Freshness.staleSince(store.lastUpdated, now: now)
    }

    /// Prochain cours assez loin pour que la barre affiche la météo.
    private var weatherApplies: Bool { Weather.applies(status, now: now, hours: weather.hours) }

    /// La ville dont la météo doit s'afficher maintenant : activée, ville choisie, prochain cours loin
    /// (ou carte toujours dans la journée).
    private var weatherPlaceWanted: WeatherPlace? {
        guard weather.enabled, let place = weather.place, hasSource,
              weather.alwaysInDay || weatherApplies else { return nil }
        return place
    }

    /// Météo de la barre, à la place du prochain cours ; nil si elle ne s'applique pas ou n'est pas chargée.
    var shownWeather: (forecast: Forecast, city: String)? {
        if let snapshotWeather { return snapshotWeather }
        return weatherApplies ? loadedWeather : nil
    }

    /// Carte météo de la journée : comme la barre, ou toujours si l'option est cochée.
    var dayWeather: (forecast: Forecast, city: String)? {
        if let snapshotWeather { return snapshotWeather }
        return weather.alwaysInDay || weatherApplies ? loadedWeather : nil
    }

    private var loadedWeather: (forecast: Forecast, city: String)? {
        guard let place = weatherPlaceWanted, let forecast = weatherStore.forecast(for: place),
              Weather.isFresh(forecast, now: now, settings: weather) else { return nil }
        return (forecast, place.name)
    }

    /// Météo factice du mode `--snapshot`.
    @ObservationIgnored var snapshotWeather: (forecast: Forecast, city: String)?

    private func refreshWeatherIfWanted(force: Bool = false) {
        guard frozenNow == nil, let place = weatherPlaceWanted else { return }
        let settings = weather
        Task { await weatherStore.refreshIfDue(place, settings: settings, force: force) }
    }

    @ObservationIgnored private var rainChecked: Date?
    @ObservationIgnored private var rainAttempt: Date?

    /// Avant la fin du dernier cours du jour : regarde une fois le risque de pluie et prévient s'il le faut.
    /// Après un échec réseau, nouvel essai 5 min plus tard.
    private func checkRain() {
        guard let end = Weather.rainCheckDue(schedule: schedule, now: now, calendar: calendar, settings: weather),
              let place = weather.rainPlace, rainChecked != end else { return }
        if let rainAttempt, now.timeIntervalSince(rainAttempt) < 5 * 60 { return }
        rainAttempt = now
        let settings = weather
        Task {
            guard let hours = try? await WeatherStore.rain(place) else { return }
            rainChecked = end
            if let n = Weather.rainAlert(end: end, hours: hours, settings: settings, calendar: calendar) { notifier.send(n) }
        }
    }

    func testRainAlert() {
        notifier.send(Weather.rainSample(settings: weather, calendar: calendar))
    }

    /// Bouton ↻ du menu : le calendrier, et la météo même hors délai.
    func refreshNow() async {
        refreshWeatherIfWanted(force: true)
        await refresh()
    }

    func searchWeather() {
        let query = weatherDraft
        guard !weatherSearching, Weather.searchURL(query) != nil else { return }
        weatherSearching = true
        weatherMessage = nil
        Task {
            do {
                weatherResults = try await WeatherStore.search(query)
                weatherMessage = weatherResults.isEmpty ? "Aucune ville trouvée." : nil
            } catch {
                weatherResults = []
                weatherMessage = error.localizedDescription
            }
            weatherSearching = false
        }
    }

    /// Range la ville trouvée dans l'emplacement en cours de recherche : ville affichée ou campus.
    func pickWeatherPlace(_ place: WeatherPlace) {
        weatherResults = []
        weatherDraft = ""
        weatherMessage = nil
        if weatherForCampus { weather.campus = place } else { weather.place = place }
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
            let (raw, creds) = await Task.detached { (Self.loadFeed(), MyGESCredentialsFile.read()) }.value
            feedURL = raw.flatMap(FeedURL.normalize)
            setCredentials(creds)
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
        // Signal d'utilisation : ~2 min après le lancement, puis vérifié toutes les heures (un seul succès par jour).
        Task {
            try? await Task.sleep(for: .seconds(120))
            while !Task.isCancelled {
                if frozenNow == nil { await usage.sendIfDue(enabled: usageEnabled, calendar: calendar) }
                try? await Task.sleep(for: .seconds(60 * 60))
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
        refreshWeatherIfWanted()
        checkRain()
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
        switch calendarSource {
        case .ical:
            await store.refresh(from: feedURL)
        case .myges:
            if credentials != nil {
                let client = client, calendar = calendar
                await store.refresh(using: {
                    let range = KordisAPI.agendaRange(now: Date(), calendar: calendar)
                    return try await client.agenda(from: range.from, to: range.to)
                })
            }
        }
        if frozenNow == nil {
            for (i, friend) in friendStores.enumerated() { await friend.refresh(from: friendURLs[i]) }
        }
        if announceChanges, notifyScheduleChanges, frozenNow == nil, store.lastUpdated != stamp {
            let changes = ScheduleDiff.changes(from: before, to: store.courses, now: Date())
            for n in ScheduleDiff.notifications(changes, now: Date(), calendar: calendar) { notifier.send(n) }
        }
        if credentials != nil, frozenNow == nil {
            let client = client
            let fresh = await grades.refresh(using: { try await client.gradesCurrentYear() })
            if announceChanges, notifyNewGrades {
                for n in GradeDiff.notifications(fresh) { notifier.send(n) }
            }
        }
        tick()
    }

    /// Notification d'exemple pour les réglages.
    func testNewGrade() {
        notifier.send(PendingNotification(
            id: "grade-test-\(Date().timeIntervalSince1970)", title: "Nouvelle note : Sécurité des réseaux",
            body: "CC2 : 15,5/20"
        ))
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
            if calendarSource == .ical { store.clear() }
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
            // Venir de myGES : les cours en cache sont ceux d'une autre source.
            let switched = calendarSource != .ical
            if switched { store.clear() }
            calendarSource = .ical
            await refresh(announceChanges: !changed && !switched)
            return (true, "\(courses.count) cours trouvés.")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    /// Met à jour les identifiants en mémoire et pour le client réseau.
    private func setCredentials(_ creds: MyGESCredentials?) {
        credentials = creds
        credentialBox.value = creds
    }

    /// Teste les identifiants du brouillon, puis les enregistre et charge cours et notes.
    func saveCredentials() async {
        let creds = MyGESCredentials(
            login: loginDraft.trimmingCharacters(in: .whitespacesAndNewlines), password: passwordDraft
        )
        guard !creds.login.isEmpty, !creds.password.isEmpty else {
            accountResult = (false, "Renseigne l'identifiant et le mot de passe.")
            return
        }
        accountSaving = true
        accountResult = nil
        defer { accountSaving = false }
        do {
            _ = try await client.authenticate(creds)
            try MyGESCredentialsFile.write(creds)
            let changed = creds.login != credentials?.login || calendarSource != .myges
            setCredentials(creds)
            calendarSource = .myges
            passwordDraft = ""
            if changed {
                store.clear()
                grades.clear()
            }
            await refresh(announceChanges: false)
            let rated = grades.book?.subjects.filter { !$0.grades.isEmpty || $0.exam != nil }.count ?? 0
            if let error = store.lastError ?? grades.lastError {
                accountResult = (true, "Connecté, mais le chargement a échoué : \(error)")
            } else {
                accountResult = (true, "Connecté : \(store.courses.count) cours sur 8 semaines, \(rated) matières notées.")
            }
        } catch {
            accountResult = (false, error.localizedDescription)
        }
    }

    /// Supprime les identifiants et les notes ; les cours myGES aussi si c'était la source.
    func forgetCredentials() {
        MyGESCredentialsFile.remove()
        setCredentials(nil)
        grades.clear()
        loginDraft = ""
        passwordDraft = ""
        accountResult = (true, "Compte myGES oublié.")
        if calendarSource == .myges { store.clear() }
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
            ("Source", calendarSource == .myges ? "myGES" : "iCal"),
            ("Calendrier", !hasSource ? "non configuré" : "configuré"),
            ("Notes", grades.lastError.map { "erreur : \($0)" } ?? "\(grades.book?.subjects.count ?? 0) matières"),
            ("Cours", "\(store.courses.count)"),
            ("Dernière mise à jour", store.lastUpdated.map { $0.formatted(.iso8601) } ?? "jamais"),
            ("Erreur", store.lastError ?? "aucune"),
            ("Potes", friendCounts.isEmpty ? "aucun" : friendCounts),
            ("Alternance", alternance.mode.rawValue),
            ("Météo", !weather.enabled ? "désactivée" : weather.place == nil ? "sans ville"
                : weatherStore.lastError.map { "erreur : \($0)" } ?? "activée"),
            ("Raccourci", hotKey.label),
            ("Comptage", "\(usageEnabled ? "activé" : "désactivé"), dernier signal \(usage.lastDay ?? "jamais")"),
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
        showingGrades = false
    }

    func openSettings() {
        feedDraft = feedURL?.absoluteString ?? ""
        loginDraft = credentials?.login ?? ""
        passwordDraft = ""
        accountResult = nil
        friendDraft = friendURLs[friendSlot]?.absoluteString ?? ""
        saveResult = nil
        friendResult = nil
        weatherDraft = ""
        weatherResults = []
        weatherMessage = nil
        diagnosticCopied = false
        // Sans calendrier, rien d'autre ne sert : on ouvre directement sur l'URL.
        if !hasSource { panel = .calendar }
        presentSettings()
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

/// Identifiants lisibles depuis le client réseau (hors du fil principal).
final class CredentialBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: MyGESCredentials?
    var value: MyGESCredentials? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
