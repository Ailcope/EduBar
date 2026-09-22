import Foundation
import Testing
@testable import EduBarCore

@Suite struct NotificationRulesTests {
    let schedule = Schedule(courses: [c0, c1, c2, c3, c4])
    let rules = NotificationRules.defaults

    func due(_ now: String, _ rules: NotificationRules? = nil) -> [PendingNotification] {
        (rules ?? self.rules).due(schedule: schedule, at: at(now), calendar: cal)
    }

    @Test func classEndBeforeShortBreak() {
        let n = due("2026-09-22 11:10")
        #expect(n.count == 1)
        #expect(n[0].title == "Fin du cours dans 5 min")
        #expect(n[0].body == "cours c0 se termine à 11h15. Ensuite : pause de 15 min.")
    }

    @Test func classEndBeforeLunchAndRoomChange() {
        // c1 finit à 13h, déjeuner puis c2 en 501 : fin de cours + changement de salle (15 min avant).
        let n = due("2026-09-22 12:55")
        #expect(n.map(\.title).sorted() == ["Fin du cours dans 5 min", "⚠️ Changement de salle : 501"])
        #expect(n.contains { $0.body.hasSuffix("Ensuite : déjeuner.") })
        #expect(due("2026-09-22 12:46").map(\.title) == ["⚠️ Changement de salle : 501"])
    }

    @Test func lastClassEndsDay() {
        // c2 et c3 s'enchaînent : une seule fin de cours, à 17h.
        #expect(due("2026-09-22 15:26").isEmpty)
        let n = due("2026-09-22 16:55")
        #expect(n.map(\.body) == ["cours c3 se termine à 17h. Ensuite : fin de journée."])
    }

    @Test func classStartAfterBreakAndFirst() {
        let n = due("2026-09-22 13:55")
        #expect(n.map(\.title) == ["Cours dans 5 min · 501"])
        #expect(n[0].body == "cours c2 à 14h · 501")
        #expect(due("2026-09-22 09:40").map(\.title) == ["Cours dans 5 min · 506"])
        // Pas de salle : elle disparaît avec son séparateur.
        #expect(due("2026-09-23 09:40").map(\.title) == ["Cours dans 5 min"])
    }

    @Test func windowAndDisabled() {
        #expect(due("2026-09-22 11:09").isEmpty)
        #expect(due("2026-09-22 11:15").count == 1) // pendant la minute de l'événement
        #expect(due("2026-09-22 11:16").isEmpty)
        var r = rules
        r.classEnd.enabled = false
        #expect(due("2026-09-22 11:10", r).isEmpty)
        r.classEnd = NotificationRule(enabled: true, minutes: 0, title: "Fini", body: "")
        #expect(due("2026-09-22 11:14", r).isEmpty)
        let n = due("2026-09-22 11:15", r)
        #expect(n.map(\.title) == ["Fini"])
        #expect(n[0].body == "cours c0 se termine à 11h15. Ensuite : pause de 15 min.") // vide : défaut
    }

    @Test func idsAreStablePerEvent() {
        #expect(due("2026-09-22 11:10").map(\.id) == due("2026-09-22 11:14").map(\.id))
        #expect(due("2026-09-22 11:10").map(\.id) != due("2026-09-22 12:56").map(\.id))
    }

    @Test func decodesOldOrPartialSettings() throws {
        let json = #"{"classEnd":{"enabled":false,"minutes":10,"title":"x","body":"y"}}"#
        let r = try JSONDecoder().decode(NotificationRules.self, from: Data(json.utf8))
        #expect(r.classEnd == NotificationRule(enabled: false, minutes: 10, title: "x", body: "y"))
        #expect(r.classStart == NotificationRules.defaults.classStart)
        #expect(r.roomChange == NotificationRules.defaults.roomChange)
    }

    @Test func sampleFillsVariables() {
        let s = rules.sample(.roomChange)
        #expect(!s.title.contains("{") && !s.body.contains("{"))
    }
}
