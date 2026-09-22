import EduBarCore
import SwiftUI

/// Heures de cours : la semaine, les examens à venir, le détail par matière.
struct StatsView: View {
    let model: AppModel

    private static let maxSubjects = 14

    var body: some View {
        let schedule = model.schedule
        let now = model.now
        let week = Stats.week(of: now, now: now, schedule: schedule, calendar: model.calendar)
        let nextWeekDay = model.calendar.date(byAdding: .weekOfYear, value: 1, to: now) ?? now
        let nextWeek = Stats.week(of: nextWeekDay, now: now, schedule: schedule, calendar: model.calendar)
        let exams = schedule.courses.filter { $0.isExam && $0.end > now }.prefix(3)
        let subjects = Stats.bySubject(schedule.courses, now: now)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { model.showingStats = false } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                Text("Statistiques").font(.headline)
            }
            Divider()

            VStack(alignment: .leading, spacing: 4) {
                row("Cette semaine", "\(DayView.hours(week.total)) · \(DayView.hours(week.done)) faites")
                row("Semaine prochaine", DayView.hours(nextWeek.total))
            }

            if !exams.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Prochains examens").font(.callout.weight(.semibold))
                    ForEach(Array(exams), id: \.id) { e in
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: "pencil.and.list.clipboard").foregroundStyle(.orange)
                            Text(e.displayTitle).lineLimit(1)
                            Spacer()
                            Text(Display.dayLabel(e.start, now: now, calendar: model.calendar))
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
            }

            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Par matière").font(.callout.weight(.semibold))
                ForEach(subjects.prefix(Self.maxSubjects), id: \.title) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(s.title).lineLimit(1)
                            Spacer()
                            Text("\(DayView.hours(s.done)) / \(DayView.hours(s.total))")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        ProgressView(value: s.total > 0 ? s.done / s.total : 0)
                            .controlSize(.small)
                            .tint(s.exams > 0 ? .orange : .accentColor)
                    }
                }
                if subjects.count > Self.maxSubjects {
                    Text("+ \(subjects.count - Self.maxSubjects) autres matières")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Faites / prévues, d'après les cours présents dans ton calendrier Edusign.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 340)
        // Menu refermé : retour à la journée à la réouverture.
        .onDisappear { model.showingStats = false }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}
