import AppKit
import EduBarCore
import Foundation
import UserNotifications

/// Notifications macOS, une seule fois par événement.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private var notified: Set<String> = []

    /// `UNUserNotificationCenter` plante hors d'un bundle .app (ex. `swift run`).
    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    func requestAuthorization() {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func send(_ n: PendingNotification) {
        guard available, notified.insert(n.id).inserted else { return }
        let content = UNMutableNotificationContent()
        content.title = n.title
        content.body = n.body
        content.sound = .default
        if let url = n.url { content.userInfo = ["url": url.absoluteString] }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: n.id, content: content, trigger: nil))
    }

    /// Affiche aussi la bannière quand l'app est au premier plan (popover ouvert, bouton « Tester »).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Clic sur une notification qui porte une page (notes de version) : on l'ouvre.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let raw = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: raw), url.scheme == "https"
        else { return }
        await MainActor.run { _ = NSWorkspace.shared.open(url) }
    }
}
