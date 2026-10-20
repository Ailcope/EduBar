import Foundation
import Testing
@testable import EduBarCore

@Suite struct L10nTests {
    // MARK: - Résolution de la langue

    @Test func explicitChoiceWins() {
        #expect(AppLanguage.fr.resolved(preferred: ["en-US"]) == .fr)
        #expect(AppLanguage.en.resolved(preferred: ["fr-FR"]) == .en)
    }

    @Test func systemPicksFrenchWhenAnyPreferredLanguageIsFrench() {
        // Étudiants d'une école française au macOS en anglais : garder le français.
        #expect(AppLanguage.system.resolved(preferred: ["fr-FR", "en-US"]) == .fr)
        #expect(AppLanguage.system.resolved(preferred: ["fr"]) == .fr)
        #expect(AppLanguage.system.resolved(preferred: ["en-US", "fr-US"]) == .fr)
        #expect(AppLanguage.system.resolved(preferred: ["de-DE", "fr-FR"]) == .fr)
    }

    @Test func systemFallsBackToEnglishWithoutFrench() {
        #expect(AppLanguage.system.resolved(preferred: ["en-GB"]) == .en)
        #expect(AppLanguage.system.resolved(preferred: ["de-DE", "es-ES"]) == .en)
        #expect(AppLanguage.system.resolved(preferred: []) == .en)
    }

    @Test func rawValuesAreStable() {
        // Persistés dans UserDefaults (clé `appLanguage`).
        #expect(AppLanguage.allCases.map(\.rawValue) == ["system", "fr", "en"])
    }

    @Test func trPicksTheCurrentLanguage() {
        #expect(L10n.with(.fr) { L10n.tr("Bonjour", "Hello") } == "Bonjour")
        #expect(L10n.with(.en) { L10n.tr("Bonjour", "Hello") } == "Hello")
    }

    @Test func localeFollowsLanguage() {
        #expect(L10n.with(.fr) { L10n.locale.identifier } == "fr_FR")
        #expect(L10n.with(.en) { L10n.locale.identifier } == "en_US")
    }

    // MARK: - Dates et durées

    @Test func timeAndDayLabelInEnglish() {
        L10n.with(.en) {
            #expect(Display.time(at("2026-09-22 08:45"), calendar: cal) == "8:45 AM")
            #expect(Display.time(at("2026-09-22 14:00"), calendar: cal) == "2 PM")
            #expect(Display.time(at("2026-09-22 00:05"), calendar: cal) == "12:05 AM")
            #expect(Display.time(at("2026-09-22 12:00"), calendar: cal) == "12 PM")
            let now = at("2026-09-24 12:00") // jeudi
            #expect(Display.dayLabel(at("2026-09-24 14:00"), now: now, calendar: cal) == "2 PM")
            #expect(Display.dayLabel(at("2026-09-25 08:45"), now: now, calendar: cal) == "Tomorrow 8:45 AM")
            #expect(Display.dayLabel(at("2026-09-28 08:45"), now: now, calendar: cal) == "Mon 8:45 AM")
            #expect(Display.dayLabel(at("2026-10-05 08:45"), now: now, calendar: cal) == "Mon 10/05 8:45 AM")
        }
    }

    @Test func timeAndDayLabelInFrenchUnchanged() {
        L10n.with(.fr) {
            #expect(Display.time(at("2026-09-22 08:45"), calendar: cal) == "8h45")
            let now = at("2026-09-24 12:00")
            #expect(Display.dayLabel(at("2026-09-25 08:45"), now: now, calendar: cal) == "Demain 8h45")
            #expect(Display.dayLabel(at("2026-10-05 08:45"), now: now, calendar: cal) == "Lun. 05/10 8h45")
        }
    }

    @Test func reportFollowsLanguage() {
        let months = Report.monthly(
            [course("a", "2026-09-22 09:00", "2026-09-22 10:30", title: "Réseaux")],
            now: at("2026-10-01 10:00"), calendar: cal
        )
        let fr = L10n.with(.fr) { Report.table(months, calendar: cal) }
        let en = L10n.with(.en) { Report.table(months, calendar: cal) }
        #expect(fr.hasPrefix("Mois\tMatière\tHeures\nseptembre 2026\tRéseaux\t1,5"))
        #expect(en.hasPrefix("Month\tSubject\tHours\nSeptember 2026\tRéseaux\t1.5"))
    }

    // MARK: - Barre

    @Test func barTextInEnglish() {
        let schedule = Schedule(courses: [c0, c1, c2, c3, c4])
        let now = at("2026-09-22 11:20") // pause de 10 min
        let status = schedule.status(at: now, calendar: cal)
        let fr = L10n.with(.fr) { Display.barText(status: status, alert: nil, now: now, calendar: cal) }
        let en = L10n.with(.en) { Display.barText(status: status, alert: nil, now: now, calendar: cal) }
        #expect(fr == "☕ Cours dans 10 min · 506")
        #expect(en == "☕ Class in 10 min · 506")
    }

    @Test func defaultTemplatesExistInBothLanguages() {
        let fr = BarTemplates.defaults(for: .fr), en = BarTemplates.defaults(for: .en)
        #expect(fr != en)
        #expect(L10n.with(.en) { BarTemplates.defaults } == en)
    }

    @Test func storedDefaultsFollowTheLanguageButCustomTextStays() {
        var stored = BarTemplates.defaults(for: .fr)
        stored.onBreak = "Pause café {temps}"
        let en = stored.localized(to: .en)
        #expect(en.beforeBreak == BarTemplates.defaults(for: .en).beforeBreak)
        #expect(en.onBreak == "Pause café {temps}")
        #expect(en.localized(to: .fr).beforeBreak == BarTemplates.defaults(for: .fr).beforeBreak)
        #expect(!stored.isDefault)
        #expect(BarTemplates.defaults(for: .fr).isDefault && BarTemplates.defaults(for: .en).isDefault)
    }

    // MARK: - Notifications

    @Test func notificationRulesInEnglish() {
        let schedule = Schedule(courses: [c0, c1, c2, c3, c4])
        let n = L10n.with(.en) {
            NotificationRules.defaults.due(schedule: schedule, at: at("2026-09-22 11:10"), calendar: cal)
        }
        #expect(n.count == 1)
        #expect(n[0].title == "Class ends in 5 min")
        #expect(n[0].body == "Cours c0 ends at 11:15 AM. Next: a break of 15 min.")
    }

    @Test func roomChangeAndLunchInEnglish() {
        let schedule = Schedule(courses: [c0, c1, c2, c3, c4])
        let n = L10n.with(.en) {
            NotificationRules.defaults.due(schedule: schedule, at: at("2026-09-22 12:55"), calendar: cal)
        }
        #expect(n.map(\.title).sorted() == ["Class ends in 5 min", "⚠️ Room change: 501"])
        #expect(n.contains { $0.body.hasSuffix("Next: lunch.") })
    }

    @Test func storedNotificationDefaultsFollowTheLanguage() {
        var rules = NotificationRules.defaults(for: .fr)
        rules.classStart.title = "Go en cours {salle}"
        rules.classEnd.minutes = 10
        let en = rules.localized(to: .en)
        #expect(en.classEnd.title == "Class ends in {temps}")
        #expect(en.classEnd.minutes == 10)
        #expect(en.classStart.title == "Go en cours {salle}")
        #expect(L10n.with(.en) { en.isDefault } == false)
        #expect(L10n.with(.en) { NotificationRules.defaults(for: .fr).isDefault })
    }

    @Test func scheduleChangesInEnglish() {
        let old = [c0, c2]
        let new = [c0]
        let now = at("2026-09-20 12:00")
        let changes = ScheduleDiff.changes(from: old, to: new, now: now)
        let n = L10n.with(.en) { ScheduleDiff.notifications(changes, now: now, calendar: cal) }
        #expect(n.count == 1)
        #expect(n[0].title == "❌ Class cancelled · Tue 2 PM")
        #expect(n[0].body == "Cours c2 (2 PM-3:30 PM) is no longer on the schedule.")
    }

    @Test func gradeNotificationsInEnglish() {
        let grade = NewGrade(course: "T1 - Sécurité", label: "Examen", value: 15.5)
        let n = L10n.with(.en) { GradeDiff.notifications([grade]) }
        #expect(n[0].title == "New grade: Sécurité")
        #expect(n[0].body == "Exam: 15.5/20")
        let fr = L10n.with(.fr) { GradeDiff.notifications([grade]) }
        #expect(fr[0].title == "Nouvelle note : Sécurité")
        #expect(fr[0].body == "Examen : 15.5/20")
        // L'identifiant ne dépend pas de la langue : pas de doublon de notification après un changement.
        #expect(n[0].id == fr[0].id)
    }

    // MARK: - Météo, jours fériés

    @Test func weatherLabelsInEnglish() {
        #expect(L10n.with(.fr) { Weather.condition(61, isDay: true).label } == "Pluie")
        #expect(L10n.with(.en) { Weather.condition(61, isDay: true).label } == "Rain")
        #expect(L10n.with(.en) { Weather.weekday("2026-10-03") } == "Sat")
    }

    @Test func holidaysInEnglish() {
        #expect(L10n.with(.fr) { Holidays.name(of: at("2026-12-25 12:00"), calendar: cal) } == "Noël")
        #expect(L10n.with(.en) { Holidays.name(of: at("2026-12-25 12:00"), calendar: cal) } == "Christmas Day")
        #expect(L10n.with(.en) { Holidays.name(of: at("2026-04-06 12:00"), calendar: cal) } == "Easter Monday")
    }
}
