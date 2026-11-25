import Foundation

/// One turn in a karaoke host app's queue, as Velvet Display reads it off the Mac (Rick, 2026-11-23: read KaraFun's
/// queue on the same box and upload it to the screens). KaraFun has no API for its queue, so Velvet reads the queue
/// panel's text: Apple's text recognition on the window it already records, else Accessibility.
public struct KaraokeQueueTurn: Codable, Sendable, Equatable {
    public var singer: String?
    public var title: String
    public var artist: String?

    public init(singer: String? = nil, title: String, artist: String? = nil) {
        self.singer = singer; self.title = title; self.artist = artist
    }
}

/// Turns the text read off a karaoke app's window into its queue. Pure, so it runs (and is tested) without a Mac.
public enum KaraokeQueueText {
    /// One line of recognized text, with its box in the window as fractions of the window's size, measured from the
    /// top left (Vision measures from the bottom left; the reader flips it).
    public struct Line: Sendable, Equatable {
        public var text: String
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(text: String, x: Double, y: Double, width: Double, height: Double) {
            self.text = text; self.x = x; self.y = y; self.width = width; self.height = height
        }

        var maxX: Double { x + width }
        var maxY: Double { y + height }
        var midY: Double { y + height / 2 }
    }

    /// The most turns a reading keeps, matching what the API keeps.
    public static let limit = 50

    /// Words a queue panel's heading uses.
    static let headings = ["queue", "up next", "next up", "playlist", "waiting list", "singers"]

    /// Whether this line is the queue panel's heading ("Queue", "Up next", "Queue (4)").
    public static func isHeading(_ text: String) -> Bool {
        let words = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[\(\[]?\d+[\)\]]?"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return headings.contains(words)
    }

    /// Text that isn't part of a turn: durations ("3:42"), bare numbers or positions ("2", "#3"), and buttons.
    static func isNoise(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 2 { return true }
        if trimmed.range(of: #"^#?\d+[\.\)]?$"#, options: .regularExpression) != nil { return true }
        if trimmed.range(of: #"^-?\d{1,2}:\d{2}(:\d{2})?$"#, options: .regularExpression) != nil { return true }
        let buttons = ["clear", "clear all", "shuffle", "edit", "remove", "add", "add singer", "see all", "more", "x"]
        return buttons.contains(trimmed.lowercased())
    }

    /// Strips a leading position ("1.", "2)", "#3 ") and a trailing duration from a line.
    static func cleaned(_ text: String) -> String {
        text.replacingOccurrences(of: #"^\s*#?\d{1,2}[\.\)]?\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+-?\d{1,2}:\d{2}\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A singer named on a line of its own ("by Dalton", "Singer: Dalton", "🎤 Dalton").
    static func singerName(_ text: String) -> String? {
        let patterns = [#"^(?:sung by|by|singer:?|for)\s+(.+)$"#, #"^🎤\s*(.+)$"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { continue }
            let name = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        }
        return nil
    }

    /// The queue in the window's text, or nil when there's no queue panel heading to read under (the panel's hidden
    /// or scrolled away). An empty array is a queue panel with nobody in it.
    ///
    /// Reads the column under the heading: the lines below it that start within the panel's left and right edges,
    /// down to the window's bottom or the next heading. Lines close together vertically make one turn; within a turn
    /// the first line is the song, the next one down the artist, and a line set off to the right of the song (or one
    /// saying "by …") the singer.
    public static func parse(lines: [Line]) -> [KaraokeQueueTurn]? {
        guard let heading = lines.filter({ isHeading($0.text) }).min(by: { $0.y < $1.y }) else { return nil }
        // The panel's column: from the heading's left edge to the window's right edge, or to the left of a wider
        // column's start when the heading sits in the middle (KaraFun puts its queue in a side panel).
        let left = heading.x - 0.02
        let below = lines
            .filter { $0 != heading && $0.y > heading.maxY - 0.002 && $0.x >= left && !isHeading($0.text) }
            .filter { !isNoise($0.text) }
            .sorted { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }
        guard !below.isEmpty else { return [] }

        // Lines on the same baseline (within half a line) go together; rows of baselines close together make a turn.
        var baselines: [[Line]] = []
        for line in below {
            if let last = baselines.last?.first, abs(last.midY - line.midY) < max(last.height, line.height) * 0.5 {
                baselines[baselines.count - 1].append(line)
            } else {
                baselines.append([line])
            }
        }
        let typicalHeight = median(below.map(\.height))
        var turns: [[[Line]]] = []
        var previousBottom: Double?
        for baseline in baselines {
            let top = baseline.map(\.y).min() ?? 0
            let bottom = baseline.map(\.maxY).max() ?? 0
            // A gap bigger than about half a line starts the next turn; titles and artists sit tighter than that.
            if let previousBottom, top - previousBottom < typicalHeight * 0.45, let last = turns.indices.last,
               turns[last].count < 3 {
                turns[last].append(baseline)
            } else {
                turns.append([baseline])
            }
            previousBottom = bottom
        }
        return Array(turns.compactMap(turn).prefix(limit))
    }

    /// One turn from its baselines of text, top first.
    static func turn(_ baselines: [[Line]]) -> KaraokeQueueTurn? {
        var singer: String?
        var texts: [String] = []
        for (index, baseline) in baselines.enumerated() {
            let ordered = baseline.sorted { $0.x < $1.x }
            for (column, line) in ordered.enumerated() {
                let text = cleaned(line.text)
                guard !text.isEmpty, !isNoise(text) else { continue }
                if let name = singerName(text) {
                    singer = singer ?? name
                } else if column > 0 && index == 0 && singer == nil {
                    // Set off to the right of the song on its first line: who's singing it.
                    singer = text
                } else {
                    texts.append(text)
                }
            }
        }
        guard let first = texts.first else { return nil }
        // "Title - Artist" on one line.
        if texts.count == 1, let dash = first.range(of: " - ") ?? first.range(of: " – ") {
            let title = first[..<dash.lowerBound].trimmingCharacters(in: .whitespaces)
            let artist = first[dash.upperBound...].trimmingCharacters(in: .whitespaces)
            if !title.isEmpty { return KaraokeQueueTurn(singer: singer, title: title, artist: artist.isEmpty ? nil : artist) }
        }
        return KaraokeQueueTurn(singer: singer, title: first, artist: texts.dropFirst().first)
    }

    /// The queue from rows of text read some other way (Accessibility: one row's static texts, in reading order):
    /// first the song, then the artist, with a "by …" text or a third text taken as the singer.
    public static func turns(rows: [[String]]) -> [KaraokeQueueTurn] {
        let parsed: [KaraokeQueueTurn] = rows.compactMap { row in
            var singer: String?
            var texts: [String] = []
            for raw in row {
                let text = cleaned(raw)
                guard !text.isEmpty, !isNoise(text), !isHeading(text) else { continue }
                if let name = singerName(text) { singer = singer ?? name } else { texts.append(text) }
            }
            guard let title = texts.first else { return nil }
            if singer == nil, texts.count >= 3 { singer = texts[2] }
            return KaraokeQueueTurn(singer: singer, title: title, artist: texts.dropFirst().first)
        }
        return Array(parsed.prefix(limit))
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0.02 }
        return sorted[sorted.count / 2]
    }
}

