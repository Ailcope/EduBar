import EduBarCore
import Foundation
import UserNotifications

/// Notification macOS de changement de salle, une seule fois par cours.
@MainActor
final class Notifier {
    private var notified: Set<String> = []

    /// `UNUserNotificationCenter` plante hors d'un bundle .app (ex. `swift run`).
    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notify(_ alert: RoomAlert, calendar: Calendar) {
        guard available, notified.insert(alert.from.id).inserted else { return }
        let content = UNMutableNotificationContent()
        content.title = "Changement de salle : \(Display.shortRoom(alert.room))"
        content.body = "Après ce cours, \(alert.to.shortTitle) à \(Display.time(alert.to.start, calendar: calendar)) en \(alert.room)."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "room-\(alert.from.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
