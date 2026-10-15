import EduBarCore
import SwiftUI

/// Notes myGES par matière : moyenne, contrôles continus, examen. Les notes apparues au dernier chargement sont en vert.
struct GradesView: View {
    let model: AppModel

    private var book: GradeBook? { model.snapshotGrades ?? model.grades.book }

    var body: some View {
        let subjects = (book?.subjects ?? []).sorted {
            $0.shortCourse.localizedCaseInsensitiveCompare($1.shortCourse) == .orderedAscending
        }
        let fresh = Set((model.snapshotNewGrades ?? model.grades.newGrades).map { "\($0.course)|\($0.label)" })
        let colors = colors(for: subjects)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Button { model.showingGrades = false } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Notes").font(.headline)
                    subtitle(count: subjects.count)
                }
            }
            Divider()

            if !model.hasCredentials {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ajoute ton compte myGES dans les réglages pour voir tes notes.")
                        .font(.callout)
                    Button("Réglages") {
                        model.panel = .account
                        model.openSettings()
                    }
                }
            } else if subjects.isEmpty {
                Text("Aucune note pour l'instant.").font(.callout).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(subjects) { card($0, fresh: fresh, colors: colors) }
                    }
                }
                .frame(maxHeight: 420)
            }
        }
        .padding(14)
        .frame(width: 340)
        // Menu refermé : retour à la journée à la réouverture.
        .onDisappear { model.showingGrades = false }
    }

    @ViewBuilder
    private func subtitle(count: Int) -> some View {
        if let error = model.grades.lastError, model.snapshotGrades == nil {
            Text(error).font(.caption).foregroundStyle(.orange).lineLimit(2)
        } else {
            let updated = model.snapshotGrades == nil ? model.grades.lastUpdated : model.now
            Text("\(count) matière\(count > 1 ? "s" : "")" + (updated.map { " · mis à jour à \(Display.time($0, calendar: model.calendar))" } ?? ""))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Couleur de la matière : celle de l'emploi du temps si elle y figure, sinon une couleur stable.
    private func colors(for subjects: [GradeBook.Subject]) -> [String: Int] {
        var assigned = SubjectColors.assign(subjects.map(key), count: SubjectPalette.colors.count)
        for (k, v) in model.subjectColors where assigned[k] != nil { assigned[k] = v }
        return assigned
    }

    private func key(_ s: GradeBook.Subject) -> String { s.shortCourse.lowercased().trimmingCharacters(in: .whitespaces) }

    private func card(_ s: GradeBook.Subject, fresh: Set<String>, colors: [String: Int]) -> some View {
        let color = SubjectPalette.color(key(s), in: colors)
        let title = s.shortCourse.prefix(1).uppercased() + s.shortCourse.dropFirst()
        let headline = s.average ?? s.ccAverage
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout.weight(.semibold)).lineLimit(2)
                    if let teacher = s.teacher {
                        Text(teacher).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Text(Self.format(headline) ?? "·").font(.title3.weight(.bold)).monospacedDigit()
            }
            if !s.grades.isEmpty || s.exam != nil {
                HStack(spacing: 4) {
                    ForEach(Array(s.grades.enumerated()), id: \.offset) { i, g in
                        chip("CC\(i + 1) \(Self.format(g) ?? "")", highlighted: fresh.contains("\(s.course)|CC\(i + 1)"))
                    }
                    if let exam = s.exam {
                        chip("Exam \(Self.format(exam) ?? "")", highlighted: fresh.contains("\(s.course)|Examen"))
                    }
                }
            }
            if let detail = detail(s) {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    private func chip(_ text: String, highlighted: Bool) -> some View {
        Text(text)
            .font(.caption.monospacedDigit())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(highlighted ? Color.green.opacity(0.28) : Color.primary.opacity(0.08)))
    }

    private func detail(_ s: GradeBook.Subject) -> String? {
        var parts: [String] = []
        if let coef = s.coef { parts.append("coef \(Self.format(coef) ?? "")") }
        if let ects = s.ects { parts.append("\(Self.format(ects) ?? "") ECTS") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f
    }()

    /// « 14,5 », virgule française ; nil si pas de valeur.
    private static func format(_ value: Double?) -> String? {
        value.flatMap { formatter.string(from: NSNumber(value: $0)) }
    }
}
