import Foundation
@testable import EduBarCore

let paris = TimeZone(identifier: "Europe/Paris")!

var cal: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = paris
    c.locale = Locale(identifier: "fr_FR")
    return c
}

/// "2026-09-22 09:45" en heure de Paris.
func at(_ s: String) -> Date {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = paris
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.date(from: s)!
}

func fixture(_ name: String) -> String {
    let url = Bundle.module.url(forResource: name, withExtension: "ics", subdirectory: "Fixtures")!
    return try! String(contentsOf: url, encoding: .utf8)
}

func course(_ id: String, _ start: String, _ end: String, room: String? = nil, title: String? = nil) -> Course {
    Course(id: id, title: title ?? "T1 - cours \(id)", start: at(start), end: at(end), room: room)
}

/// Jour type : mardi 22/09/2026 + mercredi 23/09.
let c0 = course("c0", "2026-09-22 09:45", "2026-09-22 11:15", room: "Quai 12 - 506")
let c1 = course("c1", "2026-09-22 11:30", "2026-09-22 13:00", room: "Quai 12 - 506")
let c2 = course("c2", "2026-09-22 14:00", "2026-09-22 15:30", room: "Quai 12 - 501")
let c3 = course("c3", "2026-09-22 15:30", "2026-09-22 17:00", room: "Quai 12 - 501")
let c4 = course("c4", "2026-09-23 09:45", "2026-09-23 11:15")
