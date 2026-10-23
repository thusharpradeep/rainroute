import Foundation

enum SegmentRanges {
    /// Formats 1-based segment numbers, compressing runs of consecutive values.
    /// Example: `[2, 5, 6, 7, 9]` becomes `"2, 5–7, 9"`.
    static func format(_ indices: [Int]) -> String {
        let sorted = Array(Set(indices.filter { $0 > 0 })).sorted()
        guard let first = sorted.first else { return "" }

        var parts: [String] = []
        var runStart = first
        var runEnd = first

        for index in sorted.dropFirst() {
            if index == runEnd + 1 {
                runEnd = index
            } else {
                parts.append(part(from: runStart, to: runEnd))
                runStart = index
                runEnd = index
            }
        }
        parts.append(part(from: runStart, to: runEnd))
        return parts.joined(separator: ", ")
    }

    private static func part(from start: Int, to end: Int) -> String {
        start == end ? "\(start)" : "\(start)–\(end)"
    }
}
