import EduBarCore
import SwiftUI

/// Popover principal : une journée (par défaut aujourd'hui, ou le prochain jour de cours), flèches ← → pour les autres.
struct DayView: View {
    let model: AppModel
    let openSettings: () -> Void

    private var fr: Locale { L10n.locale }

    /// Colonne des heures : « 9:45 AM » est plus large que « 9h45 ».
    private static var timeWidth: CGFloat { L10n.current == .fr ? 40 : 58 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if UpdateInstaller.diskImageVolume != nil || UpdateInstaller.isTranslocated {
                banner(
                    UpdateInstaller.isTranslocated
                        ? L10n.tr("macOS isole EduBar (quarantaine)", "macOS is isolating EduBar (quarantine)")
                        : L10n.tr("EduBar tourne depuis le .dmg", "EduBar is running from the .dmg"),
                    icon: "externaldrive", button: L10n.tr("Installer", "Install"), action: model.installInApplications
                )
                .help(L10n.tr(
                    "Copie EduBar dans Applications, la relance de là et éjecte le .dmg. Nécessaire pour les mises à jour.",
                    "Copies EduBar to Applications, relaunches it from there and ejects the .dmg. Required for updates."
                ))
                if let message = model.installMessage {
                    Text(message).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            } else if let update = model.updates.available {
                banner(
                    L10n.tr("EduBar \(update.version.description) disponible", "EduBar \(update.version.description) is available"),
                    icon: "arrow.down.circle",
                    button: model.updates.canInstallInPlace ? L10n.tr("Mettre à jour", "Update") : L10n.tr("Télécharger", "Download"),
                    action: model.updates.install
                )
                .disabled(model.updates.installing)
            }
            Divider()
            if !model.feedLoaded {
                emptyState(
                    L10n.tr("Chargement…", "Loading…"),
                    detail: L10n.tr(
                        "Si macOS le demande, autorise EduBar à lire son ancien élément du Trousseau : c'est la dernière fois.",
                        "If macOS asks, allow EduBar to read its old Keychain item: this is the last time."
                    ),
                    button: nil
                )
            } else if !model.hasSource {
                emptyState(
                    L10n.tr("Aucun calendrier configuré", "No calendar set up"),
                    detail: L10n.tr(
                        "Ajoute ton compte myGES ou l'URL de ton calendrier dans les réglages.",
                        "Add your myGES account or your calendar URL in Settings."
                    ),
                    button: L10n.tr("Configurer", "Set up")
                )
            } else if model.schedule.courses.isEmpty {
                emptyState(
                    L10n.tr("Aucun cours", "No classes"),
                    detail: L10n.tr("Le calendrier ne contient aucun cours.", "The calendar has no classes."),
                    button: nil
                )
            } else {
                if let weather = model.dayWeather {
                    WeatherCard(model: model, forecast: weather.forecast, city: weather.city)
                }
                dayNavigation
                let day = model.shownDay
                let courses = model.schedule.courses(on: day, calendar: model.calendar)
                if courses.isEmpty {
                    emptyDay(day)
                } else {
                    timeline(courses)
                }
                if !model.friends.isEmpty, !courses.isEmpty {
                    friendSummary(day)
                }
                notes(day)
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
            title = L10n.tr("Aujourd'hui", "Today")
        } else if model.calendar.isDateInTomorrow(day) {
            title = L10n.tr("Demain", "Tomorrow") + " · \(dayTitle(day))"
        } else {
            title = dayTitle(day).capitalized(with: fr)
        }
        return HStack(spacing: 6) {
            Button { model.step(-1) } label: { Image(systemName: "chevron.left") }
                .help(L10n.tr("Jour précédent", "Previous day"))
            Text(model.dayOffset == 0 && !isToday ? L10n.tr("Prochains cours", "Next classes") + " · \(dayTitle(day))" : title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if model.dayOffset != 0 {
                Button(L10n.tr("Revenir", "Back")) { model.dayOffset = 0 }
                    .font(.caption)
            }
            Button { model.step(1) } label: { Image(systemName: "chevron.right") }
                .help(L10n.tr("Jour suivant", "Next day"))
        }
        .buttonStyle(.borderless)
    }

    private func emptyDay(_ day: Date) -> some View {
        let text: (title: String, icon: String)
        if let holiday = Holidays.name(of: day, calendar: model.calendar) {
            text = (L10n.tr("Férié", "Holiday") + " · \(holiday)", "flag")
        } else if model.isCompanyDay(day) {
            text = (L10n.tr("Journée en entreprise", "Day at the company"), "building.2")
        } else if model.calendar.isDateInWeekend(day) {
            text = (L10n.tr("Week-end", "Weekend"), "sun.max")
        } else {
            text = (L10n.tr("Pas de cours", "No classes"), "calendar")
        }
        return Label(text.title, systemImage: text.icon)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }

    /// Pauses communes avec chaque pote et l'heure à laquelle il finit.
    private func friendSummary(_ day: Date) -> some View {
        let t = { (d: Date) in Display.time(d, calendar: model.calendar) }
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(model.friends.enumerated()), id: \.offset) { _, friend in
                let shared = Together.day(day, mine: model.schedule, friend: friend.schedule, calendar: model.calendar)
                let headline = shared.friendEnd.map {
                    $0 <= model.now
                        ? L10n.tr("\(friend.name) a fini à \(t($0))", "\(friend.name) finished at \(t($0))")
                        : L10n.tr("\(friend.name) finit à \(t($0))", "\(friend.name) finishes at \(t($0))")
                } ?? L10n.tr("\(friend.name) n'a pas cours", "\(friend.name) has no classes")
                VStack(alignment: .leading, spacing: 2) {
                    Label(headline, systemImage: "person.2")
                        .font(.caption.weight(.semibold))
                    if shared.friendEnd != nil {
                        Text(shared.breaks.isEmpty
                            ? L10n.tr("Pas de pause commune", "No shared break")
                            : L10n.tr("Pauses communes : ", "Shared breaks: ") + shared.breaks.map { "\(t($0.start))-\(t($0.end))" }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }

    /// Jours fériés qui expliquent un trou (semaine affichée, ou jours sautés pour arriver ici) et vacances.
    @ViewBuilder
    private func notes(_ day: Date) -> some View {
        let cal = model.calendar
        let week = cal.dateInterval(of: .weekOfYear, for: day)
        let weekStart = week?.start ?? cal.startOfDay(for: day)
        // Jour par défaut (prochain jour de cours) : aussi les fériés sautés depuis aujourd'hui.
        let from = model.dayOffset == 0 ? min(weekStart, cal.startOfDay(for: model.now)) : weekStart
        let to = max(from, week?.end ?? day)
        let holidays = Holidays.weekdays(in: DateInterval(start: from, end: to), calendar: cal)
            .filter { !cal.isDate($0.day, inSameDayAs: day) }
        let vacation = model.vacation.flatMap { v -> String? in
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: model.now), to: v.start).day ?? 0
            return days <= 60 ? Vacations.label(v, now: model.now, calendar: cal) : nil
        }
        if !holidays.isEmpty || vacation != nil {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(holidays, id: \.day) { h in
                    Label(L10n.tr("Férié", "Holiday") + " \(h.day.formatted(.dateTime.weekday(.abbreviated).day().month(.twoDigits).locale(fr))) · \(h.name)",
                          systemImage: "flag")
                }
                if let vacation { Label(vacation, systemImage: "beach.umbrella") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func weekSummary(_ day: Date) -> some View {
        let w = Stats.week(of: day, now: model.now, schedule: model.schedule, calendar: model.calendar)
        let thisWeek = model.calendar.isDate(day, equalTo: model.now, toGranularity: .weekOfYear)
        var text = L10n.tr(
            "\(thisWeek ? "Cette semaine" : "Semaine") : \(Self.hours(w.total)) de cours",
            "\(thisWeek ? "This week" : "Week"): \(Self.hours(w.total)) of classes"
        )
        if w.done > 0, w.done < w.total { text += " · " + L10n.tr("\(Self.hours(w.done)) faites", "\(Self.hours(w.done)) done") }
        return Button(action: { model.showingStats = true }) {
            HStack(spacing: 4) {
                Image(systemName: "chart.bar")
                Text(text)
            }
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .foregroundStyle(.secondary)
        .help(L10n.tr("Heures par matière", "Hours per subject"))
    }

    static func hours(_ t: TimeInterval) -> String { t <= 0 ? "0 h" : Display.duration(t) }

    private func timeline(_ courses: [Course]) -> some View {
        let colors = model.subjectColors
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(courses.enumerated()), id: \.element.id) { i, c in
                if i > 0, c.start > courses[i - 1].end {
                    breakRow(from: courses[i - 1].end, to: c.start)
                }
                courseRow(c, roomChanged: i > 0 && roomChanged(from: courses[i - 1], to: c), colors: colors)
            }
        }
    }

    private func courseRow(_ c: Course, roomChanged: Bool, colors: [String: Int]) -> some View {
        let isCurrent = c.start <= model.now && model.now < c.end
        let isPast = c.end <= model.now
        return HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(SubjectPalette.color(c.subjectKey, in: colors))
                .frame(width: 3)
            VStack(alignment: .trailing, spacing: 0) {
                Text(Display.time(c.start, calendar: model.calendar))
                Text(Display.time(c.end, calendar: model.calendar)).foregroundStyle(.secondary)
            }
            .font(.caption.monospacedDigit())
            .frame(width: Self.timeWidth, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(c.displayTitle)
                        .font(.callout.weight(isCurrent || c.isExam ? .semibold : .regular))
                        .fixedSize(horizontal: false, vertical: true)
                    if c.isExam {
                        Text(L10n.tr("Examen", "Exam"))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange))
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                    Text(c.room ?? L10n.tr("Salle non indiquée", "Room not set"))
                    if roomChanged {
                        Text("· " + L10n.tr("changement", "changed")).foregroundStyle(.orange)
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
            Text("\(lunch ? L10n.tr("Pause déjeuner", "Lunch break") : L10n.tr("Pause", "Break")) \(Display.duration(to.timeIntervalSince(from)))")
            if isNow { Text("· " + L10n.tr("maintenant", "now")).fontWeight(.semibold) }
        }
        .font(.caption)
        .foregroundStyle(isNow ? Color.accentColor : Color.secondary)
        .padding(.leading, Self.timeWidth + 23)
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
                if let stale = model.staleSince {
                    Label(L10n.tr("Pas mis à jour depuis \(stale)", "Not updated for \(stale)") + (model.store.lastError.map { " · \($0)" } ?? ""),
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .help(L10n.tr(
                            "Le planning affiché peut être périmé : la source ne répond plus ou renvoie une erreur.",
                            "The schedule shown may be out of date: the source is not responding or returns an error."
                        ))
                } else if let error = model.store.lastError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                } else if let updated = model.store.lastUpdated {
                    Text(L10n.tr("Mis à jour à \(Display.time(updated, calendar: model.calendar))", "Updated at \(Display.time(updated, calendar: model.calendar))"))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            Spacer()
            Button {
                Task { await model.refreshNow() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(model.store.isLoading || !model.hasSource)
            .help(L10n.tr("Rafraîchir", "Refresh"))
            Button(action: model.openWeek) { Image(systemName: "calendar") }
                .disabled(model.schedule.courses.isEmpty)
                .help(L10n.tr("Semaine", "Week"))
            Button(action: model.openGrades) { Image(systemName: "graduationcap") }
                .disabled(!model.hasCredentials)
                .help(L10n.tr("Notes", "Grades"))
            Button { model.showingStats = true } label: { Image(systemName: "chart.bar") }
                .disabled(model.schedule.courses.isEmpty)
                .help(L10n.tr("Statistiques", "Statistics"))
            Button(action: openSettings) { Image(systemName: "gearshape") }
                .help(L10n.tr("Réglages", "Settings"))
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .help(L10n.tr("Quitter", "Quit"))
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
