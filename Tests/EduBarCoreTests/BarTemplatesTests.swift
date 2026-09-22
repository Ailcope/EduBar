import Foundation
import Testing
@testable import EduBarCore

struct BarTemplatesTests {
    func bar(_ time: String, _ t: BarTemplates, schedule: Schedule = day) -> String {
        let now = at(time)
        let status = schedule.status(at: now, calendar: cal)
        return Display.barText(
            status: status, alert: RoomChange.alert(for: status, at: now), now: now, calendar: cal, templates: t
        )
    }

    @Test func defaultsKeepCurrentTexts() {
        let d = BarTemplates.defaults
        #expect(bar("2026-09-22 10:00", d) == "📚 Pause dans 1 h 15")
        #expect(bar("2026-09-22 12:00", d) == "🍽️ Déjeuner dans 1 h")
        #expect(bar("2026-09-22 13:10", d) == "📚 Cours dans 50 min · 501")
        #expect(bar("2026-09-22 12:50", d) == "⚠️ Salle 501 · fin dans 10 min")
    }

    @Test func customTemplatesReplaceTextsAndEmojis() {
        var t = BarTemplates.defaults
        t.beforeBreak = "🎧 Break : {temps}"
        t.beforeLunch = "🥪 Miam dans {temps}"
        t.onLunch = "🏃 Retour en {salle} dans {temps}"
        t.roomChange = "🚨 Go {salle} ({temps})"
        t.dayOver = "💤 {jour}"
        #expect(bar("2026-09-22 10:00", t) == "🎧 Break : 1 h 15")
        #expect(bar("2026-09-22 12:00", t) == "🥪 Miam dans 1 h")
        #expect(bar("2026-09-22 13:10", t) == "🏃 Retour en 501 dans 50 min")
        #expect(bar("2026-09-22 12:50", t) == "🚨 Go 501 (10 min)")
        #expect(bar("2026-09-22 18:00", t) == "💤 Demain 9h45")
    }

    @Test func emptyFieldFallsBackToDefault() {
        var t = BarTemplates.defaults
        t.beforeBreak = "   "
        #expect(bar("2026-09-22 10:00", t) == "📚 Pause dans 1 h 15")
    }

    @Test func unknownRoomDropsItsSeparator() {
        #expect(BarTemplates.render("☕ Cours dans {temps} · {salle}", temps: "8 min", salle: nil) == "☕ Cours dans 8 min")
        #expect(BarTemplates.render("{salle} - cours dans {temps}", temps: "8 min", salle: nil) == "cours dans 8 min")
        #expect(BarTemplates.render("Cours ({salle}) dans {temps}", temps: "8 min", salle: nil) == "Cours () dans 8 min")
        #expect(BarTemplates.render("Cours · {salle}", temps: "8 min", salle: "506") == "Cours · 506")
    }

    @Test func noNextClassMeansIconOnly() {
        var t = BarTemplates.defaults
        t.dayOver = "💤 {jour}"
        #expect(bar("2026-09-26 10:00", t) == "")
    }

    @Test func decodesPartialJSONWithDefaults() throws {
        let t = try JSONDecoder().decode(BarTemplates.self, from: Data(#"{"beforeBreak":"X {temps}"}"#.utf8))
        #expect(t.beforeBreak == "X {temps}")
        #expect(t.onBreak == BarTemplates.defaults.onBreak)
    }
}
