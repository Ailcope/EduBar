import EduBarCore
import SwiftUI

/// Popover principal : la journée (ou le prochain jour de cours).
struct DayView: View {
    let model: AppModel
    let openSettings: () -> Void

    private var fr: Locale { Locale(identifier: "fr_FR") }

    /// Jour affiché : aujourd'hui s'il reste des cours, sinon le prochain jour de cours.
    private var shown: (date: Date, courses: [Course], isToday: Bool)? {
        let today = model.schedule.courses(on: model.now, calendar: model.calendar)
        if today.contains(where: { $0.end > model.now }) { return (model.now, today, true) }
        guard let next = model.schedule.courses.first(where: { $0.start > model.now }) else {
            return today.isEmpty ? nil : (model.now, today, true)
        }
        return (next.start, model.schedule.courses(on: next.start, calendar: model.calendar), false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let update = model.updates.available {
                HStack {
                    Label("EduBar \(update.version.description) disponible", systemImage: "arrow.down.circle")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button("Télécharger", action: model.updates.install)
                        .controlSize(.small)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15)))
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
            } else if let shown {
                if !shown.isToday {
                    Text("Prochains cours · \(dayTitle(shown.date))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                timeline(shown.courses)
            } else {
                emptyState("Aucun cours à venir", detail: "Le calendrier ne contient plus de cours.", button: nil)
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
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
                Text(c.shortTitle.prefix(1).uppercased() + c.shortTitle.dropFirst())
                    .font(.callout.weight(isCurrent ? .semibold : .regular))
                    .fixedSize(horizontal: false, vertical: true)
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
