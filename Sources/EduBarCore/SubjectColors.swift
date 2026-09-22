import Foundation

extension Course {
    /// Matière : titre sans « T1 - », sans tenir compte de la casse.
    public var subjectKey: String { shortTitle.lowercased().trimmingCharacters(in: .whitespaces) }
}

public enum SubjectColors {
    /// Une couleur par matière, parmi `count`. Chaque matière garde sa couleur préférée (empreinte stable
    /// de son nom) quand elle est libre ; sinon la suivante libre. Tant qu'il y a moins de matières que
    /// de couleurs, deux matières n'ont jamais la même.
    public static func assign(_ keys: some Sequence<String>, count: Int) -> [String: Int] {
        guard count > 0 else { return [:] }
        var result: [String: Int] = [:]
        var used = Set<Int>()
        for key in Set(keys).sorted() {
            var i = Int(fnv1a(key) % UInt64(count))
            if used.count < count {
                while used.contains(i) { i = (i + 1) % count }
            }
            used.insert(i)
            result[key] = i
        }
        return result
    }

    /// FNV-1a 64 bits : `hashValue` change à chaque lancement, pas celle-ci.
    static func fnv1a(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100_0000_01b3
        }
        return h
    }
}
