import AppKit
import EduBarCore
import SwiftUI

/// Fenêtre Notes : en-tête avec tuiles de stats, tableau en pastilles colorées, graphique des moyennes
/// par matière, pied de page. Même principe que le userscript MyPrettyGradES (vert > 10, jaune = 10, rouge < 10).
struct GradesTableView: View {
    let model: AppModel

    private static let numberWidth: CGFloat = 58
    private static let averageWidth: CGFloat = 84
    private static let teacherWidth: CGFloat = 170
    private static let subjectMinWidth: CGFloat = 220

    private static let mygesBlue = Color(red: 0x2E / 255, green: 0x7B / 255, blue: 0xB8 / 255)
    private static let headerDark = Color(red: 0x3A / 255, green: 0x40 / 255, blue: 0x48 / 255)
    private static let good = Color(red: 0x2E / 255, green: 0xCC / 255, blue: 0x71 / 255)
    private static let neutral = Color(red: 0xF1 / 255, green: 0xC4 / 255, blue: 0x0F / 255)
    private static let bad = Color(red: 0xE7 / 255, green: 0x4C / 255, blue: 0x3C / 255)
    private static let inkDark = Color(red: 0.08, green: 0.1, blue: 0.12)

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
                header(book: book, period: period)
                content(book: book, period: period)
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
        .frame(minWidth: 820, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func empty<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 8) { content() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Couleurs

    private static func tone(_ value: Double) -> Color {
        switch MarkTone(value) {
        case .good: good
        case .neutral: neutral
        case .bad: bad
        }
    }

    /// Texte des chiffres colorés : le vert/jaune/rouge pleins sont trop clairs en texte sur fond clair.
    private static func toneText(_ value: Double) -> Color {
        switch MarkTone(value) {
        case .good: Color(nsColor: NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.18, green: 0.8, blue: 0.44, alpha: 1) : NSColor(red: 0.07, green: 0.5, blue: 0.24, alpha: 1)
        })
        case .neutral: Color(nsColor: NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.95, green: 0.77, blue: 0.06, alpha: 1) : NSColor(red: 0.62, green: 0.45, blue: 0, alpha: 1)
        })
        case .bad: Color(nsColor: NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 1, green: 0.42, blue: 0.36, alpha: 1) : NSColor(red: 0.75, green: 0.18, blue: 0.12, alpha: 1)
        })
        }
    }

    private func subjectColor(_ s: GradeBook.Subject) -> Color {
        let key = s.shortCourse.lowercased().trimmingCharacters(in: .whitespaces)
        var assigned = model.subjectColors
        if assigned[key] == nil { assigned = SubjectColors.assign([key], count: SubjectPalette.colors.count) }
        return SubjectPalette.color(key, in: assigned)
    }

    // MARK: - En-tête

    private func header(book: GradeBook, period: GradeBook.Period) -> some View {
        let stats = book.stats(in: period)
        let binding = Binding<GradeBook.Period?>(
            get: { model.selectedPeriod.flatMap { p in book.periods.contains(p) ? p : nil } },
            set: { model.selectedPeriod = $0 }
        )
        let switched = model.selectedPeriod == nil && model.automaticPeriodDiffers
        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Notes").font(.system(size: 26, weight: .bold))
                Picker("Période", selection: binding) {
                    Text("Automatique" + (model.currentPeriod.map { " (\($0.title))" } ?? "")).tag(GradeBook.Period?.none)
                    Divider()
                    ForEach(book.periods) { Text($0.title).tag(GradeBook.Period?.some($0)) }
                }
                .labelsHidden()
                .fixedSize()
                if switched {
                    Text("Le semestre en cours n'a pas encore de note : affichage de \(period.title).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: 230, alignment: .leading)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 10) {
                weightedTile(stats.weighted)
                tile("Moyenne simple", stats.simple.map(Self.format) ?? "·", color: stats.simple.map(Self.toneText))
                tile("Min · Max", "\(stats.min.map(Self.format) ?? "·") · \(stats.max.map(Self.format) ?? "·")")
                tile("Écart-type", stats.standardDeviation.map(Self.format) ?? "·")
                absenceTile(stats)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func weightedTile(_ value: Double?) -> some View {
        let accent = value.map(Self.tone) ?? Color.secondary
        return VStack(alignment: .leading, spacing: 2) {
            Text("Moyenne pondérée").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Text(value.map(Self.format) ?? "·")
                .font(.system(size: 34, weight: .bold).monospacedDigit())
                .foregroundStyle(value.map(Self.toneText) ?? Color.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(accent.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(accent.opacity(0.45), lineWidth: 1))
    }

    private func tile(_ label: String, _ value: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            Text(value)
                .font(.system(size: 20, weight: .semibold).monospacedDigit())
                .foregroundStyle(color ?? Color.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)))
    }

    private func absenceTile(_ stats: GradeBook.Stats) -> some View {
        let alert = stats.absences > 0 || stats.lates > 0
        return VStack(alignment: .leading, spacing: 4) {
            Text("Absences · retards").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            Text("\(stats.absences) abs · \(stats.lates) ret")
                .font(.system(size: 20, weight: .semibold).monospacedDigit())
                .foregroundStyle(alert ? Color.orange : Color.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(alert ? Color.orange.opacity(0.14) : Color.primary.opacity(0.06)))
    }

    // MARK: - Contenu

    /// Toute la fenêtre défile d'un bloc : le tableau s'affiche en entier, le graphique vient dessous.
    private func content(book: GradeBook, period: GradeBook.Period) -> some View {
        ScrollView(.vertical) {
            VStack(spacing: 14) {
                table(book: book, period: period, width: model.gradesTableWidth)
                chart(book: book, period: period)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
            // Largeur réellement disponible (barre de défilement classique déduite), pour que le
            // tableau remplisse la fenêtre sans déborder.
            .background(GeometryReader { geo in
                Color.clear.onChange(of: geo.size.width, initial: true) { _, width in
                    model.gradesTableWidth = max(0, width - 40)
                }
            })
        }
    }

    // MARK: - Tableau

    private func table(book: GradeBook, period: GradeBook.Period, width: CGFloat) -> some View {
        let subjects = book.subjects(in: period)
        let ccCount = book.maxCCCount(in: period)
        let fresh = Set((model.snapshotNewGrades ?? model.grades.newGrades).map { "\($0.course)|\($0.label)" })
        return Group {
            ScrollView(.horizontal) {
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
                        let fill = index % 2 == 0 ? Color.clear : Color.primary.opacity(0.045)
                        GridRow {
                            HStack(spacing: 8) {
                                Circle().fill(subjectColor(s)).frame(width: 9, height: 9)
                                Text(title(s)).fontWeight(.medium).lineLimit(2)
                            }
                            .cell(fill: fill, alignment: .leading, subject: true)
                            Text(s.teacher ?? "")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .cell(fill: fill, alignment: .leading, width: Self.teacherWidth)
                            Text(Self.coefText(s.coef)).foregroundStyle(.secondary).cell(fill: fill)
                            Text(Self.coefText(s.ects)).foregroundStyle(.secondary).cell(fill: fill)
                            ForEach(0..<ccCount, id: \.self) { i in
                                let value = i < s.grades.count ? s.grades[i] : nil
                                pill(value, fresh: fresh.contains("\(s.course)|CC\(i + 1)")).cell(fill: fill)
                            }
                            pill(s.exam, fresh: fresh.contains("\(s.course)|Examen")).cell(fill: fill)
                            pill(s.average, fresh: fresh.contains("\(s.course)|Moyenne"), wide: true)
                                .cell(fill: fill, width: Self.averageWidth)
                            letter(s.average != nil ? s.letterMark : nil).cell(fill: fill)
                        }
                    }
                }
                .font(.system(size: 13).monospacedDigit())
                .frame(minWidth: width, alignment: .topLeading)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
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

    /// Pastille pleine colorée selon la note ; vide sans note. Nouvelle note : liseré et halo accentués.
    @ViewBuilder
    private func pill(_ value: Double?, fresh: Bool, wide: Bool = false) -> some View {
        if let value {
            Text(Self.format(value))
                .font(.system(size: 13, weight: wide || fresh ? .bold : .semibold).monospacedDigit())
                .foregroundStyle(Self.inkDark)
                .frame(minWidth: wide ? 56 : 40)
                .padding(.horizontal, 8)
                .padding(.vertical, wide ? 5 : 3)
                .background(Capsule().fill(Self.tone(value)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(fresh ? 0.95 : 0), lineWidth: 2))
                .shadow(color: fresh ? Self.tone(value).opacity(0.9) : .clear, radius: 5)
        } else {
            Text("")
        }
    }

    @ViewBuilder
    private func letter(_ value: String?) -> some View {
        if let value, !value.isEmpty {
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.12)))
        } else {
            Text("")
        }
    }

    private func title(_ s: GradeBook.Subject) -> String {
        s.shortCourse.prefix(1).uppercased() + s.shortCourse.dropFirst()
    }

    // MARK: - Graphique

    private func chart(book: GradeBook, period: GradeBook.Period) -> some View {
        let items = book.subjects(in: period).compactMap { s in s.average.map { (s, $0) } }
        let weighted = book.weightedAverage(in: period)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Moyennes par matière").font(.system(size: 13, weight: .semibold))
            if items.isEmpty {
                Text("Aucune moyenne disponible").font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                barChart(items: items, weighted: weighted).frame(height: 140)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.045)))
    }

    private func barChart(items: [(GradeBook.Subject, Double)], weighted: Double?) -> some View {
        let labelHeight: CGFloat = 18
        let axisWidth: CGFloat = 26
        return GeometryReader { geo in
            barPlot(items: items, weighted: weighted, size: geo.size, labelHeight: labelHeight, axisWidth: axisWidth)
        }
    }

    private func barPlot(
        items: [(GradeBook.Subject, Double)], weighted: Double?, size: CGSize, labelHeight: CGFloat, axisWidth: CGFloat
    ) -> some View {
        return Group {
            let plotH = size.height - labelHeight
            let plotW = size.width - axisWidth
            let slot = plotW / CGFloat(max(items.count, 1))
            let barW = min(slot * 0.62, 56)
            let y: (Double) -> CGFloat = { v in plotH * (1 - CGFloat(min(max(v, 0), 20) / 20)) }
            ZStack(alignment: .topLeading) {
                ForEach([0.0, 10.0, 20.0], id: \.self) { v in
                    Path { p in
                        p.move(to: CGPoint(x: axisWidth, y: y(v)))
                        p.addLine(to: CGPoint(x: size.width, y: y(v)))
                    }
                    .stroke(Color.primary.opacity(v == 0 ? 0.3 : 0.1), lineWidth: 1)
                    Text("\(Int(v))")
                        .font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: axisWidth - 6, alignment: .trailing)
                        .position(x: (axisWidth - 6) / 2, y: min(max(y(v), 6), plotH - 4))
                }
                ForEach(Array(items.enumerated()), id: \.element.0.id) { i, item in
                    let cx = axisWidth + slot * (CGFloat(i) + 0.5)
                    let h = max(plotH - y(item.1), 2)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Self.tone(item.1))
                        .frame(width: barW, height: h)
                        .position(x: cx, y: plotH - h / 2)
                    Text(Self.format(item.1))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Self.inkDark)
                        .position(x: cx, y: plotH - h + 9)
                        .opacity(h > 22 ? 1 : 0)
                    Text(Self.shortLabel(title(item.0)))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 1)
                        .frame(width: slot, alignment: .center)
                        .clipped()
                        .position(x: cx, y: plotH + labelHeight / 2 + 2)
                }
                if let weighted {
                    Path { p in
                        p.move(to: CGPoint(x: axisWidth, y: y(weighted)))
                        p.addLine(to: CGPoint(x: size.width, y: y(weighted)))
                    }
                    .stroke(Color.primary.opacity(0.75), style: StrokeStyle(lineWidth: 1.4, dash: [5, 4]))
                    Text("moy. \(Self.format(weighted))")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color(nsColor: .windowBackgroundColor)))
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.35), lineWidth: 0.5))
                        .position(x: size.width - 34, y: max(y(weighted) - 9, 7))
                }
            }
        }
    }

    /// Nom court pour l'axe : 14 caractères puis « … ».
    private static func shortLabel(_ s: String) -> String {
        s.count > 14 ? String(s.prefix(14)) + "…" : s
    }

    // MARK: - Pied

    private func footer(book: GradeBook, period: GradeBook.Period) -> some View {
        let stats = book.stats(in: period)
        return HStack(spacing: 14) {
            Text("\(stats.subjectCount) matière\(stats.subjectCount > 1 ? "s" : "") · \(stats.gradedSubjectCount) notée\(stats.gradedSubjectCount > 1 ? "s" : "")")
                .foregroundStyle(.secondary)
            if model.grades.isLoading { ProgressView().controlSize(.small) }
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
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
    }

    // MARK: - Formats

    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f
    }()

    /// « 15,5 », virgule française, 2 décimales au plus.
    private static func format(_ value: Double) -> String {
        formatter.string(from: NSNumber(value: value)) ?? ""
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
            .padding(.vertical, 6)
            .frame(
                minWidth: subject ? 220 : (width ?? 58), maxWidth: subject ? .infinity : (width ?? 58),
                minHeight: 38, alignment: alignment)
            .background(fill)
    }
}
