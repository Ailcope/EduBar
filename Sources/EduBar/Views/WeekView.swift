import EduBarCore
import SwiftUI

/// Semaine en grille : un jour par colonne, un bloc par cours à la couleur de sa matière.
/// Un clic sur un jour ouvre cette journée.
struct WeekView: View {
    let model: AppModel

    private static let hourHeight: CGFloat = 24
    private static let axisWidth: CGFloat = 24
    private var fr: Locale { Locale(identifier: "fr_FR") }

    var body: some View {
        let cal = model.calendar
        let week = model.shownWeek
        let grid = WeekGrid(week: week, schedule: model.schedule, calendar: cal)
        let height = CGFloat(grid.lastHour - grid.firstHour) * Self.hourHeight
        let colors = model.subjectColors
        let hours = Stats.week(of: week, now: model.now, schedule: model.schedule, calendar: cal)

        return VStack(alignment: .leading, spacing: 10) {
            header(week)
            Divider()
            HStack(spacing: 2) {
                Color.clear.frame(width: Self.axisWidth, height: 1)
                ForEach(grid.days, id: \.self) { day in
                    let today = cal.isDate(day, inSameDayAs: model.now)
                    Button { model.showDay(day) } label: {
                        Text(day.formatted(.dateTime.weekday(.abbreviated).day().locale(fr)).capitalized(with: fr))
                            .font(.caption.weight(today ? .bold : .regular))
                            .foregroundStyle(today ? Color.accentColor : Color.secondary)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderless)
                    .help("Voir la journée")
                }
            }
            HStack(alignment: .top, spacing: 2) {
                axis(grid, height: height)
                ForEach(grid.days, id: \.self) { day in
                    column(day, grid: grid, height: height, colors: colors)
                }
            }
            Text(hours.total > 0
                ? "\(DayView.hours(hours.total)) de cours" + (hours.done > 0 && hours.done < hours.total ? " · \(DayView.hours(hours.done)) faites" : "")
                : "Aucun cours cette semaine")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 420)
    }

    private func header(_ week: Date) -> some View {
        let start = model.calendar.dateInterval(of: .weekOfYear, for: week)?.start ?? week
        let current = model.calendar.isDate(start, equalTo: model.now, toGranularity: .weekOfYear)
        return HStack(spacing: 6) {
            Button { model.showingWeek = false } label: { Image(systemName: "chevron.left") }
                .help("Retour à la journée")
            Text(current ? "Cette semaine" : "Semaine du \(start.formatted(.dateTime.day().month(.abbreviated).locale(fr)))")
                .font(.headline)
            Spacer()
            if model.weekOffset != 0 {
                Button("Revenir") { model.weekOffset = 0 }.font(.caption)
            }
            Button { model.weekOffset = max(-13, model.weekOffset - 1) } label: { Image(systemName: "arrow.left") }
                .help("Semaine précédente")
            Button { model.weekOffset = min(13, model.weekOffset + 1) } label: { Image(systemName: "arrow.right") }
                .help("Semaine suivante")
        }
        .buttonStyle(.borderless)
    }

    private func axis(_ grid: WeekGrid, height: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            ForEach(grid.firstHour..<grid.lastHour, id: \.self) { h in
                Text("\(h)h")
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .offset(y: CGFloat(h - grid.firstHour) * Self.hourHeight - 5)
            }
        }
        .frame(width: Self.axisWidth, height: height, alignment: .topTrailing)
    }

    private func column(_ day: Date, grid: WeekGrid, height: CGFloat, colors: [String: Int]) -> some View {
        let cal = model.calendar
        let courses = model.schedule.courses(on: day, calendar: cal)
        let y = { (d: Date) in CGFloat(grid.position(d, calendar: cal)) * height }
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.04))
            ForEach(1..<(grid.lastHour - grid.firstHour), id: \.self) { h in
                Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.5)
                    .offset(y: CGFloat(h) * Self.hourHeight)
            }
            if courses.isEmpty, let note = emptyNote(day) {
                Label(note.text, systemImage: note.icon)
                    .labelStyle(.iconOnly)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(note.text)
                    .offset(y: 8)
            }
            ForEach(courses) { c in
                block(c, colors: colors)
                    .frame(height: max(12, y(c.end) - y(c.start)))
                    .offset(y: y(c.start))
            }
            if cal.isDate(day, inSameDayAs: model.now), model.now > courses.first?.start ?? .distantFuture {
                Rectangle().fill(Color.red).frame(height: 1).offset(y: y(model.now))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .top)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { model.showDay(day) }
    }

    private func block(_ c: Course, colors: [String: Int]) -> some View {
        let color = SubjectPalette.color(c.subjectKey, in: colors)
        let current = c.start <= model.now && model.now < c.end
        let t = { (d: Date) in Display.time(d, calendar: model.calendar) }
        return Text(c.displayTitle)
            .font(.system(size: 9, weight: current || c.isExam ? .semibold : .regular))
            .lineLimit(3)
            .minimumScaleFactor(0.8)
            .padding(.leading, 4)
            .padding(.trailing, 1)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 3).fill(color.opacity(current ? 0.45 : 0.28)))
            .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 2) }
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.orange, lineWidth: c.isExam ? 1 : 0))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .opacity(c.end <= model.now ? 0.55 : 1)
            .help([c.displayTitle, "\(t(c.start))-\(t(c.end))", c.room].compactMap { $0 }.joined(separator: " · "))
    }

    private func emptyNote(_ day: Date) -> (text: String, icon: String)? {
        if let holiday = Holidays.name(of: day, calendar: model.calendar) { return ("Férié · \(holiday)", "flag") }
        if model.isCompanyDay(day) { return ("En entreprise", "building.2") }
        return nil
    }
}
