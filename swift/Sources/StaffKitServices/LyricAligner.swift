import Foundation

/// Times a song's lyric lines from a transcript of the song: words heard with when they were heard (speech
/// recognition on an audio file the venue owns), matched in order to the lines. Each line takes the time of the first
/// stretch of heard words that matches its opening words; a line nothing matched gets a time between its neighbours,
/// spread by how long they are. The result is `SyncedLyrics`, and `lrcText` writes it as an LRC file for the
/// lyrics folder.
///
/// Recognizers hear sung words badly, so this is a first draft for someone to check, not a finished file.
public enum LyricAligner {
    public struct Word: Sendable, Equatable {
        public var text: String
        public var time: TimeInterval
        public init(text: String, time: TimeInterval) { self.text = text; self.time = time }
    }

    /// How many of a line's opening words are compared, and how far ahead of the last match a line is looked for.
    static let openingWords = 4
    static let lookahead = 60

    public static func align(lyrics: String, words heard: [Word], duration: TimeInterval? = nil) -> SyncedLyrics {
        let lines = lyrics.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !($0.hasPrefix("[") && $0.hasSuffix("]")) }
        let heard = heard.map { (word: normalized($0.text), time: $0.time) }.filter { !$0.word.isEmpty }
        var times: [TimeInterval?] = []
        var cursor = 0
        for line in lines {
            let words = line.split(whereSeparator: \.isWhitespace).map { normalized(String($0)) }.filter { !$0.isEmpty }
            let opening = Array(words.prefix(openingWords))
            var best: (index: Int, score: Int)?
            if !opening.isEmpty {
                for start in cursor..<min(heard.count, cursor + lookahead) {
                    var score = 0
                    for (offset, word) in opening.enumerated() where start + offset < heard.count {
                        if similar(heard[start + offset].word, word) { score += 1 }
                    }
                    // The first word must match, plus half the opening (a one-word line: just that word).
                    guard similar(heard[start].word, opening[0]), score * 2 >= opening.count else { continue }
                    if best == nil || score > best!.score { best = (start, score) }
                    if score == opening.count { break }
                }
            }
            if let best {
                times.append(heard[best.index].time)
                cursor = best.index + max(1, words.count / 2)
            } else {
                times.append(nil)
            }
        }
        return SyncedLyrics(lines: zip(fill(times, weights: lines.map(\.count), end: duration ?? heard.last.map { $0.time + 3 }), lines)
            .map { SyncedLyrics.Line(time: $0, text: $1) })
    }

    /// Times for the lines nothing matched, between the matched ones around them, by each line's length; never going
    /// backwards.
    static func fill(_ times: [TimeInterval?], weights: [Int], end: TimeInterval?) -> [TimeInterval] {
        var result = times
        var index = 0
        while index < result.count {
            guard result[index] == nil else { index += 1; continue }
            var next = index
            while next < result.count && result[next] == nil { next += 1 }
            let before = index > 0 ? result[index - 1]! : 0
            let after = next < result.count ? result[next]! : max(end ?? before, before) + (end == nil ? Double(next - index) * 3 : 0)
            let span = max(0, after - before)
            // The previous line's length counts too: it takes time to sing before the gap's first line comes.
            let previous = index > 0 ? weights[index - 1] : 0
            let gap = Array(weights[index..<next])
            let total = Double(max(1, previous + gap.reduce(0, +)))
            var elapsed = Double(previous)
            for offset in 0..<(next - index) {
                result[index + offset] = before + span * elapsed / total
                elapsed += Double(gap[offset])
            }
            index = next
        }
        var last: TimeInterval = 0
        return result.map { time in
            last = max(last, time ?? last)
            return last
        }
    }

    static func normalized(_ word: String) -> String {
        String(word.lowercased().folding(options: .diacriticInsensitive, locale: nil).unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// The same word, or close: one edit apart for words of four letters or more, or one a prefix of the other.
    static func similar(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        guard min(a.count, b.count) >= 3 else { return false }
        if a.hasPrefix(b) || b.hasPrefix(a) { return true }
        return min(a.count, b.count) >= 4 && distance(a, b) <= 1
    }

    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var row = Array(0...b.count)
        for i in 1...max(1, a.count) where !a.isEmpty {
            var previous = row[0]
            row[0] = i
            for j in stride(from: 1, through: b.count, by: 1) {
                let current = row[j]
                row[j] = a[i - 1] == b[j - 1] ? previous : 1 + min(previous, row[j], row[j - 1])
                previous = current
            }
        }
        return a.isEmpty ? b.count : row[b.count]
    }
}

extension SyncedLyrics {
    /// The lines as an LRC file (`[mm:ss.xx]line`), with the title and artist tags when given.
    public func lrcText(title: String? = nil, artist: String? = nil) -> String {
        var out: [String] = []
        if let artist, !artist.isEmpty { out.append("[ar:\(artist)]") }
        if let title, !title.isEmpty { out.append("[ti:\(title)]") }
        for line in lines {
            let hundredths = Int((max(0, line.time) * 100).rounded())
            out.append(String(format: "[%02d:%02d.%02d]", hundredths / 6000, hundredths / 100 % 60, hundredths % 100) + line.text)
        }
        return out.joined(separator: "\n") + "\n"
    }
}
