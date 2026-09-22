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
    let calendar = Calendar.autoupdatingCurrent

    var notifyRoomChanges: Bool {
        didSet { UserDefaults.standard.set(notifyRoomChanges, forKey: "notifyRoomChanges") }
    }

    // État de l'UI (pas de @State : c'est une macro que les Command Line Tools ne savent pas développer avec le SDK macOS 27).
    var showingSettings = false
    var feedDraft = ""
    var saveResult: (ok: Bool, message: String)?
    var saving = false

    @ObservationIgnored private let notifier = Notifier()
    @ObservationIgnored private var started = false

    init() {
        feedURL = Keychain.get("feedURL").flatMap(FeedURL.normalize)
        notifyRoomChanges = UserDefaults.standard.object(forKey: "notifyRoomChanges") as? Bool ?? true
    }

    // MARK: - État dérivé

    var schedule: Schedule { Schedule(courses: store.courses) }
    var status: Status { schedule.status(at: now, calendar: calendar) }
    var alert: RoomAlert? { RoomChange.alert(for: status, at: now) }
    var barText: String {
        guard feedURL != nil else { return "" }
        return Display.barText(status: status, alert: alert, now: now, calendar: calendar)
    }

    // MARK: - Boucles

    func start() {
        guard !started else { return }
        started = true
        notifier.requestAuthorization()

        Task { await store.refresh(from: feedURL) }
        // Horloge : toutes les 30 s, calée sur :00 et :30.
        Task {
            while !Task.isCancelled {
                let wait = 30 - Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 30)
                try? await Task.sleep(for: .seconds(wait))
                tick()
            }
        }
        // Rafraîchissement du flux toutes les 15 min.
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15 * 60))
                await store.refresh(from: feedURL)
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
        if notifyRoomChanges, let alert { notifier.notify(alert, calendar: calendar) }
    }

    func refresh() async {
        await store.refresh(from: feedURL)
        tick()
    }

    // MARK: - Réglages

    /// Teste l'URL puis l'enregistre. Renvoie un message à afficher.
    func save(feed raw: String) async -> (ok: Bool, message: String) {
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
            Keychain.set(url.absoluteString, for: "feedURL")
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
        showingSettings = true
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
