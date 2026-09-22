import Foundation

/// Suite de cours enchaînés sans pause.
public struct Block: Equatable, Sendable {
    public var first: Course
    public var last: Course

    public var start: Date { first.start }
    public var end: Date { last.end }
}

extension Schedule {
    /// Les suites de cours du jour, dans l'ordre.
    public func blocks(on day: Date, calendar: Calendar) -> [Block] {
        var blocks: [Block] = []
        for c in courses(on: day, calendar: calendar) {
            if let b = blocks.last, c.start <= b.last.end {
                if c.end >= b.last.end { blocks[blocks.count - 1].last = c }
            } else {
                blocks.append(Block(first: c, last: c))
            }
        }
        return blocks
    }
}
