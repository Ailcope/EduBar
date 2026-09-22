import Foundation
import Testing
@testable import EduBarCore

struct DisplayTests {
    @Test func durationRoundsUpToTheMinute() {
        #expect(Display.duration(22 * 60 + 10) == "23 min")
        #expect(Display.duration(5) == "1 min")
        #expect(Display.duration(0) == "0 min")
        #expect(Display.duration(-30) == "0 min")
        #expect(Display.duration(60 * 60) == "1 h")
        #expect(Display.duration(65 * 60) == "1 h 05")
        #expect(Display.duration(150 * 60) == "2 h 30")
    }

    @Test func time() {
        #expect(Display.time(at("2026-09-22 08:45"), calendar: cal) == "8h45")
        #expect(Display.time(at("2026-09-22 14:00"), calendar: cal) == "14h")
    }

    @Test func shortRoom() {
        #expect(Display.shortRoom("Quai 12 - 501") == "501")
        #expect(Display.shortRoom("Amphi") == "Amphi")
    }

    @Test func dayLabel() {
        let now = at("2026-09-24 12:00") // jeudi
        #expect(Display.dayLabel(at("2026-09-24 14:00"), now: now, calendar: cal) == "14h")
        #expect(Display.dayLabel(at("2026-09-25 08:45"), now: now, calendar: cal) == "Demain 8h45")
        #expect(Display.dayLabel(at("2026-09-28 08:45"), now: now, calendar: cal) == "Lun. 8h45")
        #expect(Display.dayLabel(at("2026-10-05 08:45"), now: now, calendar: cal) == "Lun. 05/10 8h45")
    }

    func bar(_ schedule: Schedule, _ time: String) -> String {
        let now = at(time)
        let status = schedule.status(at: now, calendar: cal)
        return Display.barText(status: status, alert: RoomChange.alert(for: status, at: now), now: now, calendar: cal)
    }

    @Test func barTexts() {
        #expect(bar(day, "2026-09-22 12:50") == "⚠️ Salle 501 · fin dans 10 min")
        #expect(bar(day, "2026-09-22 10:00") == "📚 Pause dans 1 h 15")
        #expect(bar(day, "2026-09-22 14:30") == "📚 Fin dans 2 h 30")
        #expect(bar(day, "2026-09-22 11:20") == "☕ Cours dans 10 min · 506")
        #expect(bar(day, "2026-09-22 08:00") == "Cours dans 1 h 45 · 506")
        #expect(bar(day, "2026-09-22 18:00") == "Demain 9h45")
        #expect(bar(day, "2026-09-21 10:00") == "Demain 9h45")
        #expect(bar(day, "2026-09-26 10:00") == "")
    }

    @Test func lunchIsAnHourLongBreakAroundNoon() {
        #expect(Display.isLunch(from: at("2026-09-22 13:00"), to: at("2026-09-22 14:00"), calendar: cal))
        #expect(Display.isLunch(from: at("2026-09-22 12:00"), to: at("2026-09-22 13:30"), calendar: cal))
        #expect(!Display.isLunch(from: at("2026-09-22 11:15"), to: at("2026-09-22 11:30"), calendar: cal))
        #expect(!Display.isLunch(from: at("2026-09-22 12:30"), to: at("2026-09-22 13:15"), calendar: cal))
        #expect(!Display.isLunch(from: at("2026-09-22 16:00"), to: at("2026-09-22 17:00"), calendar: cal))
    }

    @Test func lunchBarTexts() {
        // c1 finit à 13h, c2 commence à 14h : pause déjeuner.
        #expect(bar(day, "2026-09-22 12:00") == "🍽️ Déjeuner dans 1 h")
        #expect(bar(day, "2026-09-22 13:10") == "📚 Cours dans 50 min · 501")
    }

    @Test func breakWithoutRoomOmitsIt() {
        let a = course("a", "2026-09-22 09:00", "2026-09-22 10:00")
        let b = course("b", "2026-09-22 10:15", "2026-09-22 11:00")
        #expect(bar(Schedule(courses: [a, b]), "2026-09-22 10:05") == "☕ Cours dans 10 min")
    }
}
