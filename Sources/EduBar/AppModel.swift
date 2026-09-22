import AppKit
import EduBarCore
import Foundation
import Observation
import ServiceManagement

@MainActor @Observable
final class AppModel {
    private(set) var now = Date()
    private(set) var feedURL: URL?
    let store = CalendarStore()
    let updates = UpdateChecker()
    let calendar = Calendar.autoupdatingCurrent

    /// Notifications personnalisées dans les réglages.
    var notifications: NotificationRules {
        didSet {
            if let data = try? JSONEncoder().encode(notifications) {
                UserDefaults.standard.set(data, forKey: "notificationRules")
            }
        }
    }

    /// Textes de la barre personnalisés dans les réglages.
    var templates: BarTemplates {
        didSet {
            if let data = try? JSONEncoder().encode(templates) {
                UserDefaults.standard.set(data, forKey: "barTemplates")
            }
        }
    }

    // État de l'UI (pas de @State : c'est une macro que les Command Line Tools ne savent pas développer avec le SDK macOS 27).
    var showingSettings = false
    var feedDraft = ""
    var saveResult: (ok: Bool, message: String)?
    var saving = false
    var showingTemplates = false
    var showingNotifications = false

    @ObservationIgnored private let notifier = Notifier()
    @ObservationIgnored private var started = false

    /// Faux tant que l'URL n'est pas lue (la migration depuis le Trousseau peut attendre une autorisation).
    private(set) var feedLoaded = false

    /// `readKeychainNow` : lecture synchrone, pour le mode `--snapshot` seulement.
    init(readKeychainNow: Bool = false) {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "notificationRules"),
           let rules = try? JSONDecoder().decode(NotificationRules.self, from: data) {
            notifications = rules
        } else {
            // Réglage de la v0.2 : seulement l'alerte de changement de salle.
            var rules = NotificationRules.defaults
            rules.roomChange.enabled = defaults.object(forKey: "notifyRoomChanges") as? Bool ?? true
            notifications = rules
        }
        templates = UserDefaults.standard.data(forKey: "barTemplates")
            .flatMap { try? JSONDecoder().decode(BarTemplates.self, from: $0) } ?? .defaults
        if readKeychainNow {
            feedURL = Self.loadFeed().flatMap(FeedURL.normalize)
            feedLoaded = true
        }
    }

    // MARK: - État dérivé

    var schedule: Schedule { Schedule(courses: store.courses) }
    var status: Status { schedule.status(at: now, calendar: calendar) }
    var alert: RoomAlert? {
        RoomChange.alert(for: status, at: now, lead: TimeInterval(max(0, notifications.roomChange.minutes) * 60))
    }
    var barText: String {
        guard feedURL != nil else { return "" }
        return Display.barText(status: status, alert: alert, now: now, calendar: calendar, templates: templates)
    }

    // MARK: - Boucles

    func start() {
        guard !started else { return }
        started = true
        notifier.requestAuthorization()
        announceUpdateIfJustInstalled()

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
        // Rafraîchissement du flux toutes les 15 min ; mises à jour de l'app une fois par jour.
        Task {
            await updates.checkIfDue()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15 * 60))
                await store.refresh(from: feedURL)
                await updates.checkIfDue()
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.tick()
                Task { await self.store.refresh(from: self.feedURL) }
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
    }

    /// Après une mise à jour automatique, le premier lancement de la nouvelle version l'annonce.
    private func announceUpdateIfJustInstalled() {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: UpdateChecker.updatedFromKey) != nil else { return }
        defaults.removeObject(forKey: UpdateChecker.updatedFromKey)
        let version = updates.current ?? "?"
        notifier.send(PendingNotification(
            id: "updated-\(version)", title: "EduBar est à jour", body: "Version \(version) installée, tes réglages sont conservés."
        ))
    }

    /// Envoie tout de suite un exemple de la notification (réglages).
    func testNotification(_ kind: NotificationKind) {
        notifier.send(notifications.sample(kind))
    }

    func refresh() async {
        await store.refresh(from: feedURL)
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
            feedURL = url
            await refresh()
            return (true, "\(courses.count) cours trouvés.")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func openSettings() {
        feedDraft = feedURL?.absoluteString ?? ""
        saveResult = nil
        collapsePanels()
        showingSettings = true
    }

    /// Replie les volets avant de revenir à la journée : la fenêtre du menu garde sinon leur hauteur.
    func closeSettings() {
        collapsePanels()
        showingSettings = false
    }

    func collapsePanels() {
        showingTemplates = false
        showingNotifications = false
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
