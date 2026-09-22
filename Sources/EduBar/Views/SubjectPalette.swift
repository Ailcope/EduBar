import EduBarCore
import SwiftUI

/// Couleurs des matières. Pas d'orange : il signale les examens.
enum SubjectPalette {
    static let colors: [Color] = [
        .blue, .green, .purple, .pink, .yellow, .brown, .teal, Color(red: 0.55, green: 0.75, blue: 0.2), .indigo,
    ]

    static func color(_ key: String, in assigned: [String: Int]) -> Color {
        colors[(assigned[key] ?? 0) % colors.count]
    }
}
