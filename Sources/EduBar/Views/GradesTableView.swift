import AppKit
import EduBarCore
import SwiftUI

/// Tableau de notes façon myGES : une ligne par matière de la période choisie.
/// Les notes apparues au dernier chargement sont en vert et en gras.
struct GradesTableView: View {
    let model: AppModel

    private static let numberWidth: CGFloat = 64
    private static let averageWidth: CGFloat = 88
    private static let teacherWidth: CGFloat = 200
    private static let subjectMinWidth: CGFloat = 260

    private static let mygesBlue = Color(red: 0x2E / 255, green: 0x7B / 255, blue: 0xB8 / 255)
    private static let headerDark = Color(red: 0x3A / 255, green: 0x40 / 255, blue: 0x48 / 255)
    /// Bleu foncé en clair, bleu clair en sombre : lisible dans les deux apparences.
    private static let subjectText = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.55, green: 0.76, blue: 0.95, alpha: 1)
            : NSColor(red: 0.12, green: 0.31, blue: 0.48, alpha: 1)
    })
    private static let freshFill = Color.green.opacity(0.25)

    private var book: GradeBook? { model.snapshotGrades ?? model.grades.book }

    var body: some View {
        VStack(spacing: 0) {
            if !model.hasCredentials {
                empty {
                    Text("Ajoute ton compte myGES dans les réglages pour voir tes notes.").font(.callout)
                    Button("Réglages") {
                        model.panel = .account
                        model.openSettings()
                    }
                }
            } else if let book, let period = model.currentPeriod, !book.subjects.isEmpty {
                topBar(book: book)
                Divider()
                table(book: book, period: period)
                Divider()
                footer(book: book, period: period)
            } else {
                empty {
                    Text("Aucune note pour l'instant.").font(.callout).foregroundStyle(.secondary)
                    if model.grades.isLoading { ProgressView().controlSize(.small) }
                    if let error = model.grades.lastError, model.snapshotGrades == nil {
                        Text(error).font(.caption).foregroundStyle(.orange)
                    }
                }
            }
        }
        .frame(minWidth: 760, minHeight: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func empty<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 8) { content() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sélecteur de période

    private func topBar(book: GradeBook) -> some View {
        let binding = Binding<GradeBook.Period?>(
            get: { model.selectedPeriod.flatMap { p in book.periods.contains(p) ? p : nil } },
            set: { model.selectedPeriod = $0 }
        )
        return HStack(spacing: 8) {
            Text("Afficher mes cours de :")
            Picker("Période", selection: binding) {
                Text("Automatique" + (model.currentPeriod.map { " (\($0.title))" } ?? "")).tag(GradeBook.Period?.none)
                Divider()
                ForEach(book.periods) { Text($0.title).tag(GradeBook.Period?.some($0)) }
            }
            .labelsHidden()
            .fixedSize()
            Spacer()
            if model.grades.isLoading { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Tableau

    private func table(book: GradeBook, period: GradeBook.Period) -> some View {
        let subjects = book.subjects(in: period)
        let ccCount = book.maxCCCount(in: period)
        let fresh = Set((model.snapshotNewGrades ?? model.grades.newGrades).map { "\($0.course)|\($0.label)" })
        return GeometryReader { geo in
            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .center, horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        headerCell("Matière", fill: Self.mygesBlue, alignment: .leading, subject: true)
                        headerCell("Intervenant", fill: Self.headerDark, alignment: .leading, width: Self.teacherWidth)
                        headerCell("Coef.", fill: Self.headerDark)
                        headerCell("ECTS", fill: Self.headerDark)
                        ForEach(0..<ccCount, id: \.self) { headerCell("CC\($0 + 1)", fill: Self.headerDark) }
                        headerCell("Exam", fill: Self.headerDark)
                        headerCell("Moyenne", fill: Self.headerDark, width: Self.averageWidth)
                        headerCell("Lettre", fill: Self.headerDark)
                    }
                    ForEach(Array(subjects.enumerated()), id: \.element.id) { index, s in
                        let fill = rowFill(index)
                        GridRow {
                            Text(title(s))
                                .fontWeight(.medium)
                                .foregroundStyle(Self.subjectText)
                                .lineLimit(2)
                                .cell(fill: fill, alignment: .leading, subject: true)
                            Text(s.teacher ?? "")
                                .lineLimit(1)
                                .cell(fill: fill, alignment: .leading, width: Self.teacherWidth)
                            Text(Self.coefText(s.coef)).cell(fill: fill)
                            Text(Self.coefText(s.ects)).cell(fill: fill)
                            ForEach(0..<ccCount, id: \.self) { i in
                                let value = i < s.grades.count ? s.grades[i] : nil
                                gradeCell(value, fresh: fresh.contains("\(s.course)|CC\(i + 1)"), fill: fill)
                            }
                            gradeCell(s.exam, fresh: fresh.contains("\(s.course)|Examen"), fill: fill)
                            Text(Self.format(s.average) ?? "")
                                .fontWeight(.bold)
                                .cell(fill: fresh.contains("\(s.course)|Moyenne") ? Self.freshFill : fill, width: Self.averageWidth)
                            // myGES met « F » tant qu'il n'y a pas de moyenne : on n'affiche la lettre qu'avec elle.
                            Text(s.average != nil ? (s.letterMark ?? "") : "").cell(fill: fill)
                        }
                    }
                }
                .font(.system(size: 13).monospacedDigit())
                .frame(minWidth: geo.size.width, alignment: .topLeading)
            }
        }
    }

    private func headerCell(
        _ text: String, fill: Color, alignment: Alignment = .center, width: CGFloat? = nil, subject: Bool = false
    ) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .cell(fill: fill, alignment: alignment, width: width, subject: subject)
    }

    private func gradeCell(_ value: Double?, fresh: Bool, fill: Color) -> some View {
        Text(Self.format(value) ?? "")
            .fontWeight(fresh ? .bold : .regular)
            .cell(fill: fresh ? Self.freshFill : fill)
    }

    private func rowFill(_ index: Int) -> Color {
        let colors = NSColor.alternatingContentBackgroundColors
        return Color(nsColor: colors[index % colors.count])
    }

    private func title(_ s: GradeBook.Subject) -> String {
        s.shortCourse.prefix(1).uppercased() + s.shortCourse.dropFirst()
    }

    // MARK: - Pied

    private func footer(book: GradeBook, period: GradeBook.Period) -> some View {
        let count = book.subjects(in: period).count
        return HStack(spacing: 14) {
            if let avg = book.weightedAverage(in: period) {
                Text("Moyenne pondérée du semestre : ").foregroundStyle(.secondary)
                    + Text(Self.format(avg) ?? "").fontWeight(.semibold)
            }
            Text("\(count) matière\(count > 1 ? "s" : "")").foregroundStyle(.secondary)
            Spacer()
            if let error = model.grades.lastError, model.snapshotGrades == nil {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).lineLimit(1)
            } else if let updated = model.snapshotGrades == nil ? model.grades.lastUpdated : model.now {
                Text("Mis à jour à \(Display.time(updated, calendar: model.calendar))").foregroundStyle(.secondary)
            }
            Button {
                Task { await model.refreshNow() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(model.grades.isLoading)
            .help("Rafraîchir")
            Button("Ouvrir myGES") {
                if let url = URL(string: "https://myges.fr/student/marks") { NSWorkspace.shared.open(url) }
            }
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Formats

    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f
    }()

    /// « 15,5 », virgule française, 2 décimales au plus ; nil si pas de valeur.
    private static func format(_ value: Double?) -> String? {
        value.flatMap { formatter.string(from: NSNumber(value: $0)) }
    }

    /// « 2.00 » comme sur myGES, « N.C » si non communiqué.
    private static func coefText(_ value: Double?) -> String {
        value.map { String(format: "%.2f", $0) } ?? "N.C"
    }
}

private extension View {
    /// Cellule du tableau : marge, fond de ligne, largeur de colonne.
    func cell(
        fill: Color, alignment: Alignment = .center, width: CGFloat? = nil, subject: Bool = false
    ) -> some View {
        self
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(
                minWidth: subject ? 260 : (width ?? 64), maxWidth: subject ? .infinity : (width ?? 64),
                minHeight: 32, alignment: alignment)
            .background(fill)
    }
}
