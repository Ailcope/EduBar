import EduBarCore
import SwiftUI

/// Popover principal : une journée (par défaut aujourd'hui, ou le prochain jour de cours), flèches ← → pour les autres.
struct DayView: View {
    let model: AppModel
    let openSettings: () -> Void

    private var fr: Locale { Locale(identifier: "fr_FR") }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if UpdateInstaller.diskImageVolume != nil || UpdateInstaller.isTranslocated {
                banner(
                    UpdateInstaller.isTranslocated ? "macOS isole EduBar (quarantaine)" : "EduBar tourne depuis le .dmg",
                    icon: "externaldrive", button: "Installer", action: model.installInApplications
                )
                .help("Copie EduBar dans Applications, la relance de là et éjecte le .dmg. Nécessaire pour les mises à jour.")
                if let message = model.installMessage {
                    Text(message).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            } else if let update = model.updates.available {
                banner(
                    "EduBar \(update.version.description) disponible", icon: "arrow.down.circle",
                    button: model.updates.canInstallInPlace ? "Mettre à jour" : "Télécharger", action: model.updates.install
                )
                .disabled(model.updates.installing)
            }
            Divider()
            if !model.feedLoaded {
                emptyState(
                    "Chargement…",
                    detail: "Si macOS le demande, autorise EduBar à lire son ancien élément du Trousseau : c'est la dernière fois.",
                    button: nil
                )
            } else if model.feedURL == nil {
                emptyState(
                    "Aucun calendrier configuré",
                    detail: "Colle l'URL webcal de ton calendrier Edusign dans les réglages.",
                    button: "Configurer"
                )
            } else if model.schedule.courses.isEmpty {
                emptyState("Aucun cours", detail: "Le calendrier ne contient aucun cours.", button: nil)
            } else {
                dayNavigation
                let day = model.shownDay
                let courses = model.schedule.courses(on: day, calendar: model.calendar)
                if courses.isEmpty {
                    emptyDay(day)
                } else {
                    timeline(courses)
                }
                weekSummary(day)
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
        .onDisappear { model.dayOffset = 0 }
    }

    // MARK: - Morceaux

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(dayTitle(model.now).capitalized(with: fr))
                .font(.headline)
            if !model.barText.isEmpty {
                Text(model.barText)
                    .font(.subheadline)
                    .foregroundStyle(model.alert == nil ? Color.secondary : Color.orange)
            }
        }
    }

    private func banner(_ title: String, icon: String, button: String, action: @escaping () -> Void) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
            Spacer()
            Button(button, action: action)
                .controlSize(.small)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15)))
    }

    private var dayNavigation: some View {
        let day = model.shownDay
        let isToday = model.calendar.isDate(day, inSameDayAs: model.now)
        let title: String
        if isToday {
            title = "Aujourd'hui"
        } else if model.calendar.isDateInTomorrow(day) {
            title = "Demain · \(dayTitle(day))"
        } else {
            title = dayTitle(day).capitalized(with: fr)
        }
        return HStack(spacing: 6) {
            Button { model.step(-1) } label: { Image(systemName: "chevron.left") }
                .help("Jour précédent")
            Text(model.dayOffset == 0 && !isToday ? "Prochains cours · \(dayTitle(day))" : title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if model.dayOffset != 0 {
                Button("Revenir") { model.dayOffset = 0 }
                    .font(.caption)
            }
            Button { model.step(1) } label: { Image(systemName: "chevron.right") }
                .help("Jour suivant")
        }
        .buttonStyle(.borderless)
    }

    private func emptyDay(_ day: Date) -> some View {
        let text: (title: String, icon: String)
        if model.isCompanyDay(day) {
            text = ("Journée en entreprise", "building.2")
        } else if model.calendar.isDateInWeekend(day) {
            text = ("Week-end", "sun.max")
        } else {
            text = ("Pas de cours", "calendar")
        }
        return Label(text.title, systemImage: text.icon)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }

    private func weekSummary(_ day: Date) -> some View {
        let w = Stats.week(of: day, now: model.now, schedule: model.schedule, calendar: model.calendar)
        let thisWeek = model.calendar.isDate(day, equalTo: model.now, toGranularity: .weekOfYear)
        var text = "\(thisWeek ? "Cette semaine" : "Semaine") : \(Self.hours(w.total)) de cours"
        if w.done > 0, w.done < w.total { text += " · \(Self.hours(w.done)) faites" }
        return Button(action: { model.showingStats = true }) {
            HStack(spacing: 4) {
                Image(systemName: "chart.bar")
                Text(text)
            }
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .foregroundStyle(.secondary)
        .help("Heures par matière")
    }

    static func hours(_ t: TimeInterval) -> String { t <= 0 ? "0 h" : Display.duration(t) }

    private func timeline(_ courses: [Course]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(courses.enumerated()), id: \.element.id) { i, c in
                if i > 0, c.start > courses[i - 1].end {
                    breakRow(from: courses[i - 1].end, to: c.start)
                }
                courseRow(c, roomChanged: i > 0 && roomChanged(from: courses[i - 1], to: c))
            }
        }
    }

    private func courseRow(_ c: Course, roomChanged: Bool) -> some View {
        let isCurrent = c.start <= model.now && model.now < c.end
        let isPast = c.end <= model.now
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(Display.time(c.start, calendar: model.calendar))
                Text(Display.time(c.end, calendar: model.calendar)).foregroundStyle(.secondary)
            }
            .font(.caption.monospacedDigit())
            .frame(width: 40, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(c.displayTitle)
                        .font(.callout.weight(isCurrent || c.isExam ? .semibold : .regular))
                        .fixedSize(horizontal: false, vertical: true)
                    if c.isExam {
                        Text("Examen")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange))
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                    Text(c.room ?? "Salle non indiquée")
                    if roomChanged {
                        Text("· changement").foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCurrent ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.orange.opacity(c.isExam ? 0.6 : 0), lineWidth: 1)
        )
        .opacity(isPast ? 0.5 : 1)
    }

    private func breakRow(from: Date, to: Date) -> some View {
        let isNow = from <= model.now && model.now < to
        let lunch = Display.isLunch(from: from, to: to, calendar: model.calendar)
        return HStack(spacing: 6) {
            Image(systemName: lunch ? "fork.knife" : "cup.and.saucer")
            Text("\(lunch ? "Pause déjeuner" : "Pause") \(Display.duration(to.timeIntervalSince(from)))")
            if isNow { Text("· maintenant").fontWeight(.semibold) }
        }
        .font(.caption)
        .foregroundStyle(isNow ? Color.accentColor : Color.secondary)
        .padding(.leading, 50)
    }

    private func emptyState(_ title: String, detail: String, button: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.callout.weight(.semibold))
            Text(detail).font(.caption).foregroundStyle(.secondary)
            if let button { Button(button, action: openSettings) }
        }
    }

    private var footer: some View {
        HStack {
            Group {
                if let error = model.store.lastError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                } else if let updated = model.store.lastUpdated {
                    Text("Mis à jour à \(Display.time(updated, calendar: model.calendar))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            Spacer()
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(model.store.isLoading || model.feedURL == nil)
            .help("Rafraîchir")
            Button { model.showingStats = true } label: { Image(systemName: "chart.bar") }
                .disabled(model.schedule.courses.isEmpty)
                .help("Statistiques")
            Button(action: openSettings) { Image(systemName: "gearshape") }
                .help("Réglages")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .help("Quitter")
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Aides

    private func dayTitle(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(fr))
    }

    private func roomChanged(from a: Course, to b: Course) -> Bool {
        guard let rb = b.room else { return false }
        return a.room?.lowercased() != rb.lowercased()
    }
}
