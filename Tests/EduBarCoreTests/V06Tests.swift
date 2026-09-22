import Foundation
import Testing
@testable import EduBarCore

@Suite struct FreshnessTests {
    @Test func recentIsFine() {
        #expect(Freshness.staleSince(at("2026-09-22 08:00"), now: at("2026-09-22 20:00")) == nil)
        #expect(Freshness.staleSince(nil, now: at("2026-09-22 20:00")) == nil)
    }

    @Test func staleInHoursThenDays() {
        #expect(Freshness.staleSince(at("2026-09-21 08:00"), now: at("2026-09-22 10:00")) == "26 h")
        #expect(Freshness.staleSince(at("2026-09-19 08:00"), now: at("2026-09-22 10:00")) == "3 jours")
    }

    @Test func emptyFeedIsSuspiciousOnlyWithUpcomingCourses() {
        let now = at("2026-09-22 10:00")
        #expect(Freshness.suspiciousEmpty(fresh: [], previous: [c2], now: now))
        #expect(!Freshness.suspiciousEmpty(fresh: [], previous: [], now: now))
        #expect(!Freshness.suspiciousEmpty(fresh: [c2], previous: [c2], now: now))
        // Plus rien à venir (fin d'année) : un flux vide est plausible.
        #expect(!Freshness.suspiciousEmpty(fresh: [], previous: [c0], now: at("2026-09-22 12:00")))
    }
}

@Suite struct ReportTests {
    let courses = [
        course("a", "2026-09-22 09:00", "2026-09-22 10:30", title: "T1 - réseaux"),
        course("b", "2026-09-23 09:00", "2026-09-23 10:00", title: "T1 - Réseaux"),
        course("c", "2026-09-23 14:00", "2026-09-23 16:00", title: "T1 - anglais"),
        course("d", "2026-10-01 09:00", "2026-10-01 12:00", title: "T1 - réseaux"),
    ]

    @Test func groupsDoneHoursByMonthAndSubject() {
        let months = Report.monthly(courses, now: at("2026-10-01 10:00"), calendar: cal)
        #expect(months.count == 2)
        #expect(months[0].subjects.map(\.title) == ["Réseaux", "Anglais"])
        let expected: [TimeInterval] = [9000, 7200]
        #expect(months[0].subjects.map(\.hours) == expected)
        // Cours en cours : seulement la partie faite.
        #expect(months[1].total == 3600)
    }

    @Test func futureCoursesAreLeftOut() {
        #expect(Report.monthly(courses, now: at("2026-09-01 08:00"), calendar: cal).isEmpty)
    }

    @Test func tablePastesIntoSpreadsheets() {
        let months = Report.monthly(courses, now: at("2026-09-30 00:00"), calendar: cal)
        #expect(Report.table(months, calendar: cal) == """
        Mois\tMatière\tHeures
        septembre 2026\tRéseaux\t2,5
        septembre 2026\tAnglais\t2
        septembre 2026\tTotal\t4,5
        """)
    }
}

@Suite struct WeekGridTests {
    @Test func weekdaysOnlyUnlessWeekendHasCourses() {
        let grid = WeekGrid(week: at("2026-09-23 12:00"), schedule: Schedule(courses: [c0]), calendar: cal)
        #expect(grid.days.count == 5)
        #expect(grid.days.first == at("2026-09-21 00:00"))
        let saturday = course("s", "2026-09-26 09:00", "2026-09-26 12:00")
        #expect(WeekGrid(week: at("2026-09-23 12:00"), schedule: Schedule(courses: [c0, saturday]), calendar: cal).days.count == 6)
    }

    @Test func hourRangeCoversTheWeek() {
        let grid = WeekGrid(week: at("2026-09-22 12:00"), schedule: Schedule(courses: [c0, c3]), calendar: cal)
        #expect(grid.firstHour == 8)
        #expect(grid.lastHour == 18)
        let late = course("l", "2026-09-22 07:30", "2026-09-22 19:15")
        let wide = WeekGrid(week: at("2026-09-22 12:00"), schedule: Schedule(courses: [late]), calendar: cal)
        #expect(wide.firstHour == 7)
        #expect(wide.lastHour == 20)
        #expect(wide.position(at("2026-09-22 07:00"), calendar: cal) == 0)
        #expect(wide.position(at("2026-09-22 20:00"), calendar: cal) == 1)
    }
}

@Suite struct FriendSlotTests {
    @Test func firstSlotKeepsTheOldFile() {
        #expect(FeedFile.friend(0).url.lastPathComponent == "friend-url")
        #expect(FeedFile.friend(2).url.lastPathComponent == "friend-url-3")
    }
}
