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
        let colors = model.subjectColors
        let months = Report.monthly(schedule.courses, now: now, calendar: model.calendar)
        let thisMonth = months.last { model.calendar.isDate($0.month, equalTo: now, toGranularity: .month) }

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
                row("Ce mois-ci", "\(DayView.hours(thisMonth?.total ?? 0)) faites")
                HStack {
                    Button(action: model.copyReport) { Label("Copier le relevé d'heures", systemImage: "tablecells") }
                        .buttonStyle(.borderless)
                        .disabled(months.isEmpty)
                        .help("Heures faites par mois et par matière, à coller dans Excel ou Numbers (entreprise, OPCO).")
                    if model.reportCopied { Text("Copié, colle-le dans un tableur.").foregroundStyle(.green) }
                }
                .font(.caption)
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
                            Circle().fill(SubjectPalette.color(s.key, in: colors)).frame(width: 7, height: 7)
                            Text(s.title).lineLimit(1)
                            if s.exams > 0 {
                                Text(s.exams > 1 ? "\(s.exams) examens" : "examen").foregroundStyle(.orange)
                            }
                            Spacer()
                            Text("\(DayView.hours(s.done)) / \(DayView.hours(s.total))")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        bar(s.total > 0 ? s.done / s.total : 0, color: SubjectPalette.color(s.key, in: colors))
                    }
                }
                if subjects.count > Self.maxSubjects {
                    Text("+ \(subjects.count - Self.maxSubjects) autres matières")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Faites / prévues. Les jours passés sont gardés sur ce Mac, même quand Edusign les retire.")
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

    /// Barre de progression à la couleur de la matière (`ProgressView` ignore `tint` en petite taille).
    private func bar(_ fraction: Double, color: Color) -> some View {
        Capsule()
            .fill(Color.primary.opacity(0.08))
            .overlay(alignment: .leading) {
                GeometryReader { g in
                    Capsule().fill(color).frame(width: max(fraction > 0 ? 4 : 0, g.size.width * min(1, fraction)))
                }
            }
            .frame(height: 4)
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
