import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// A song's lyrics in time syllable by syllable, ready to caption: each line with its syllables, each syllable with
/// when it's sung. The sing-along screen sweeps a highlight across the line being sung, one syllable at a time.
///
/// Comes from a timing file (`SyllableTiming`, Velvet JSON) joined to the words, from a venue's TTML file, or, when
/// neither exists, estimated from line timing (`estimated(from:)`) so every song with lyrics in time gets a sweep.
public struct SyllableLyrics: Sendable, Equatable {
    public struct Syllable: Sendable, Equatable {
        /// The syllable's characters, with the spaces and punctuation after it: a line's syllables join into the line.
        public var text: String
        public var start: TimeInterval
        public var end: TimeInterval
        /// How sure the aligner was, 0 to 1; nil when estimated or hand-made.
        public var confidence: Double?

        public init(text: String, start: TimeInterval, end: TimeInterval, confidence: Double? = nil) {
            self.text = text; self.start = start; self.end = max(start, end); self.confidence = confidence
        }
    }

    public struct Line: Sendable, Equatable {
        public var start: TimeInterval
        public var end: TimeInterval
        /// Empty for an instrumental break.
        public var syllables: [Syllable]
        /// Set when the aligner found the audio disagrees with these words here (a cover's changed line, a skipped
        /// verse, another lyric version).
        public var mismatch: Bool
        /// True when the syllable times were measured: from the aligner run on the audio, or word timing someone
        /// made (a venue's TTML). False when they're only spread over the line timing (`estimated(from:)`).
        public var timed: Bool

        public init(start: TimeInterval, end: TimeInterval, syllables: [Syllable], mismatch: Bool = false,
                    timed: Bool = true) {
            self.start = start; self.end = max(start, end); self.syllables = syllables; self.mismatch = mismatch
            self.timed = timed
        }

        public var text: String { syllables.map(\.text).joined() }

        /// Whether the screen sweeps this line syllable by syllable. Only measured timing earns a sweep; a line whose
        /// syllables are guesses, or that the aligner found the audio doesn't sing, is lit as a whole line instead.
        public var sweeps: Bool { timed && !mismatch && !syllables.isEmpty }
    }

    /// In time order.
    public var lines: [Line]
    /// True when the syllable times are spread over line timing rather than aligned to the audio.
    public var estimated: Bool

    public init(lines: [Line], estimated: Bool = false) {
        self.lines = lines.sorted { $0.start < $1.start }
        self.estimated = estimated
    }

    /// The line being sung at `position`: the last that has started, or nil before the first.
    public func index(at position: TimeInterval) -> Int? {
        var low = 0, high = lines.count - 1, found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].start <= position { found = mid; low = mid + 1 } else { high = mid - 1 }
        }
        return found
    }

    /// How much of a syllable is sung at `position`, 0 to 1.
    public static func fill(_ syllable: Syllable, at position: TimeInterval) -> Double {
        guard position > syllable.start else { return 0 }
        guard syllable.end > syllable.start else { return 1 }
        return min(1, (position - syllable.start) / (syllable.end - syllable.start))
    }

    /// These syllables inside `lyrics`' own line timing (Musixmatch's): each line keeps the start of the lyric line
    /// with its words and ends where the next starts, and its syllables are kept inside that, so the aligner only
    /// places syllables and never moves a line (Rick, 2026-11-21: "it seems that we override the line timing").
    /// A line whose words aren't found keeps its own times.
    public func anchored(to lyrics: SyncedLyrics) -> SyllableLyrics {
        let digests = lyrics.lines.map { line -> String in
            let text = line.text.trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? "" : LyricTimingDigest.digest(text)
        }
        var cursor = 0
        let placed = lines.map { line -> Line in
            let text = line.text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return line }
            let digest = LyricTimingDigest.digest(text)
            guard let found = digests.indices.dropFirst(cursor).prefix(12).first(where: { digests[$0] == digest })
            else { return line }
            cursor = found + 1
            let start = lyrics.lines[found].time
            let end = lyrics.lines.indices.contains(found + 1) ? max(start, lyrics.lines[found + 1].time) : max(start, line.end)
            func inside(_ time: TimeInterval) -> TimeInterval { min(max(time, start), end) }
            let syllables = line.syllables.map {
                Syllable(text: $0.text, start: inside($0.start), end: inside($0.end), confidence: $0.confidence)
            }
            return Line(start: start, end: end, syllables: syllables, mismatch: line.mismatch, timed: line.timed)
        }
        return SyllableLyrics(lines: placed)
    }

    /// Syllable timing spread over line timing: each line's syllables (`Syllabifier`) share the time until the next
    /// line, longer syllables longer, finishing a little early and never stretching over a long instrumental gap. A
    /// first draft of the sweep for songs no one has run the aligner on.
    public static func estimated(from lyrics: SyncedLyrics, duration: TimeInterval? = nil) -> SyllableLyrics {
        var lines: [Line] = []
        for (index, line) in lyrics.lines.enumerated() {
            let next = index + 1 < lyrics.lines.count ? lyrics.lines[index + 1].time : (duration ?? line.time + 5)
            let pieces = Syllabifier.syllables(line.text.trimmingCharacters(in: .whitespaces))
            guard !pieces.isEmpty, line.text.contains(where: { $0.isLetter || $0.isNumber }) else {
                lines.append(Line(start: line.time, end: next, syllables: [], timed: false))
                continue
            }
            let available = max(0.3, next - line.time - 0.1)
            let span = min(available, Double(pieces.count) * 0.55 + 0.4)
            let weights = pieces.map { Double($0.filter { $0.isLetter || $0.isNumber }.count) + 1 }
            let total = weights.reduce(0, +)
            var at = line.time
            var syllables: [Syllable] = []
            for (piece, weight) in zip(pieces, weights) {
                let length = span * weight / total
                syllables.append(Syllable(text: piece, start: at, end: at + length))
                at += length
            }
            lines.append(Line(start: line.time, end: at, syllables: syllables, timed: false))
        }
        return SyllableLyrics(lines: lines, estimated: true)
    }

    /// The lines with an instrumental break (an empty line, shown as a musical note) wherever the music plays at
    /// least `minimum` seconds with nothing sung: before the first line, between lines, and after the last when
    /// `duration` is known. A break starts a second after the last syllable, so the line before can finish.
    public func withBreaks(minimum: TimeInterval = 8, duration: TimeInterval? = nil) -> SyllableLyrics {
        var out: [Line] = []
        var sungUntil: TimeInterval = 0
        var previousIsBreak = false
        func gap(until next: TimeInterval) {
            guard !previousIsBreak, next - sungUntil >= minimum else { return }
            let start = out.isEmpty && sungUntil == 0 ? 0 : sungUntil + 1
            out.append(Line(start: start, end: next, syllables: []))
        }
        for line in lines {
            if !line.syllables.isEmpty { gap(until: line.start) }
            out.append(line)
            previousIsBreak = line.syllables.isEmpty
            if !line.syllables.isEmpty { sungUntil = max(line.start, line.syllables.map(\.end).max() ?? line.end) }
        }
        if let duration, !lines.isEmpty { gap(until: duration) }
        return SyllableLyrics(lines: out, estimated: estimated)
    }

    /// The lines as plain timed lyrics (each line at its start).
    public var syncedLyrics: SyncedLyrics {
        SyncedLyrics(lines: lines.map { SyncedLyrics.Line(time: $0.start, text: $0.text) })
    }
}

/// A syllable timing file, Velvet JSON (`velvet-syllables/1`): one per recording, cached on the Mac that made it
/// (tools/velvet-align writes them). It holds times and each line's digest (`LyricTimingDigest`), never the words: the
/// licensed source's terms (Musixmatch Basic) forbid keeping lyrics anywhere else, so the words are joined back at
/// show time from wherever the screen got them (`joined(with:)`). A syllable is a run of the line's characters,
/// counted in Unicode scalars of the NFC form of the line with its ends trimmed.
public struct SyllableTiming: Codable, Sendable, Equatable {
    public static let currentFormat = "velvet-syllables/1"

    public struct Syllable: Codable, Sendable, Equatable {
        /// How many of the line's characters (NFC Unicode scalars) this syllable covers, spaces after it included.
        public var length: Int
        public var start: TimeInterval
        public var end: TimeInterval
        public var confidence: Double?

        public init(length: Int, start: TimeInterval, end: TimeInterval, confidence: Double? = nil) {
            self.length = length; self.start = start; self.end = end; self.confidence = confidence
        }
    }

    public struct Line: Codable, Sendable, Equatable {
        public var digest: String
        public var start: TimeInterval
        public var end: TimeInterval
        public var syllables: [Syllable]
        /// "mismatch" where alignment confidence was low (the audio sings something else here), "drift" where the
        /// aligned start disagreed with the line timing it was checked against.
        public var flag: String?

        public init(digest: String, start: TimeInterval, end: TimeInterval, syllables: [Syllable], flag: String? = nil) {
            self.digest = digest; self.start = start; self.end = end; self.syllables = syllables; self.flag = flag
        }
    }

    public var format: String
    public var recording: MediaRecording
    /// The works the recording sings (one for a song; several with ranges for a medley). Empty: the recording is
    /// captioned as itself.
    public var works: [RecordingWorkLink]
    /// Which lyrics the timing was made against (`lyricVersion(of:)`): different words re-run the aligner.
    public var lyricVersion: String
    /// The aligner and its models, e.g. "velvet-align/0.1 htdemucs wav2vec2-large-960h": a better model re-runs it.
    public var model: String
    public var createdAt: String?
    public var lines: [Line]

    public init(recording: MediaRecording, works: [RecordingWorkLink] = [], lyricVersion: String, model: String,
                createdAt: String? = nil, lines: [Line]) {
        self.format = Self.currentFormat; self.recording = recording; self.works = works
        self.lyricVersion = lyricVersion; self.model = model; self.createdAt = createdAt; self.lines = lines
    }

    /// The cache key: the recording's identity (`MediaRecording.key`) with the lyric and model versions.
    public var cacheKey: String { "\(recording.key)|\(lyricVersion)|\(model)" }

    /// The file this timing is cached as.
    public var fileName: String { String(SHA256Digest.hex(Array(cacheKey.utf8)).prefix(24)) + ".json" }

    /// A version for a set of lyric lines: the first 16 hex digits of the SHA-256 of their digests, one a line.
    public static func lyricVersion(of lines: [String]) -> String {
        let digests = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .map(LyricTimingDigest.digest).joined(separator: "\n")
        return String(SHA256Digest.hex(Array(digests.utf8)).prefix(16))
    }

    static func scalars(_ text: String) -> [Unicode.Scalar] {
        Array(text.trimmingCharacters(in: .whitespaces).precomposedStringWithCanonicalMapping.unicodeScalars)
    }

    /// The timing put to the words from wherever the screen got them: each timed line takes the next unused line of
    /// words with the same digest, a little ahead of the last, and is cut into syllables by length. Nil when fewer
    /// than half the timed lines found their words (another version of the song).
    public func joined(with words: [String]) -> SyllableLyrics? {
        let texts = words.map { $0.trimmingCharacters(in: .whitespaces) }
        let digests = texts.map { $0.isEmpty ? "" : LyricTimingDigest.digest($0) }
        var cursor = 0
        var placed: [SyllableLyrics.Line] = []
        var worded = 0
        for line in lines {
            if line.syllables.isEmpty {
                placed.append(SyllableLyrics.Line(start: line.start, end: line.end, syllables: []))
                continue
            }
            guard let found = digests.indices.dropFirst(cursor).prefix(12).first(where: { digests[$0] == line.digest }),
                  let cut = Self.cut(texts[found], into: line.syllables) else { continue }
            placed.append(SyllableLyrics.Line(start: line.start, end: line.end, syllables: cut, mismatch: line.flag == "mismatch"))
            cursor = found + 1
            worded += 1
        }
        let timed = lines.filter { !$0.syllables.isEmpty }.count
        guard worded > 0, worded * 2 >= timed else { return nil }
        return SyllableLyrics(lines: placed)
    }

    public func joined(with lyrics: SyncedLyrics) -> SyllableLyrics? { joined(with: lyrics.lines.map(\.text)) }

    static func cut(_ text: String, into syllables: [Syllable]) -> [SyllableLyrics.Syllable]? {
        let all = scalars(text)
        guard syllables.reduce(0, { $0 + $1.length }) == all.count else { return nil }
        var at = 0
        return syllables.map { syllable in
            var view = String.UnicodeScalarView()
            view.append(contentsOf: all[at..<(at + syllable.length)])
            at += syllable.length
            return SyllableLyrics.Syllable(text: String(view), start: syllable.start, end: syllable.end,
                                           confidence: syllable.confidence)
        }
    }

    /// The timing of syllable lyrics, without their words: for caching a venue's own TTML, or tests.
    public init(lyrics: SyllableLyrics, recording: MediaRecording, works: [RecordingWorkLink] = [], model: String) {
        let lines = lyrics.lines.map { line -> Line in
            Line(digest: line.syllables.isEmpty ? "" : LyricTimingDigest.digest(line.text), start: line.start,
                 end: line.end,
                 syllables: line.syllables.enumerated().map { index, syllable in
                     // The first syllable can't carry the line's leading spaces, which are trimmed.
                     let text = index == 0 ? syllable.text.drop(while: \.isWhitespace).description : syllable.text
                     let trimmed = index == line.syllables.count - 1
                         ? String(text.reversed().drop(while: \.isWhitespace).reversed()) : text
                     return Syllable(length: trimmed.precomposedStringWithCanonicalMapping.unicodeScalars.count,
                                     start: syllable.start, end: syllable.end, confidence: syllable.confidence)
                 }, flag: line.mismatch ? "mismatch" : nil)
        }
        self.init(recording: recording, works: works, lyricVersion: Self.lyricVersion(of: lyrics.lines.map(\.text)),
                  model: model, lines: lines)
    }
}

// MARK: TTML

/// Syllable lyrics as TTML, the timed-text format Apple Music's lyrics use: a `<p>` a line, a `<span>` a syllable
/// (word timing, `itunes:timing="Word"`), the spaces between words as text between spans. Velvet JSON is the cache;
/// TTML is for the venue's own files and for handing to other players. A TTML file holds the words, so it's written
/// only where the words are the venue's to keep.
public enum SyllableTTML {
    public static func document(_ lyrics: SyllableLyrics, title: String? = nil, artist: String? = nil,
                                language: String = "en") -> String {
        var out = #"<?xml version="1.0" encoding="UTF-8"?>"# + "\n"
        out += #"<tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata" "#
        out += #"xmlns:itunes="http://music.apple.com/lyric-ttml-internal" itunes:timing="Word" xml:lang="\#(escape(language))">"#
        out += "\n<head><metadata>"
        if let title { out += "<ttm:title>\(escape(title))</ttm:title>" }
        if let artist { out += "<ttm:agent type=\"person\"><ttm:name>\(escape(artist))</ttm:name></ttm:agent>" }
        out += "</metadata></head>\n"
        let end = lyrics.lines.last?.end ?? 0
        out += "<body dur=\"\(clock(end))\">\n<div begin=\"\(clock(lyrics.lines.first?.start ?? 0))\" end=\"\(clock(end))\">\n"
        for line in lyrics.lines where !line.syllables.isEmpty {
            out += "<p begin=\"\(clock(line.start))\" end=\"\(clock(line.end))\">"
            for syllable in line.syllables {
                let word = String(syllable.text.reversed().drop(while: \.isWhitespace).reversed())
                let gap = syllable.text.dropFirst(word.count)
                out += "<span begin=\"\(clock(syllable.start))\" end=\"\(clock(syllable.end))\">\(escape(word))</span>"
                if !gap.isEmpty { out += " " }
            }
            out += "</p>\n"
        }
        out += "</div>\n</body>\n</tt>\n"
        return out
    }

    /// Syllable lyrics from TTML: word- or syllable-timed spans in each `<p>`, or a line-timed `<p>` with no spans,
    /// whose syllables are then spread over its time. Nil when it has no timed lines.
    public static func lyrics(_ ttml: String) -> SyllableLyrics? {
        guard let data = ttml.data(using: .utf8) else { return nil }
        let reader = TTMLReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        _ = parser.parse()
        guard !reader.lines.isEmpty else { return nil }
        return SyllableLyrics(lines: reader.lines, estimated: reader.estimated)
    }

    /// TTML time expressions: "HH:MM:SS.mmm", "MM:SS.mmm", "SS.mmm", "12.5s", "1500ms", "2m", "1h".
    public static func seconds(_ text: String) -> TimeInterval? {
        let value = text.trimmingCharacters(in: .whitespaces)
        for (suffix, scale) in [("ms", 0.001), ("s", 1.0), ("m", 60.0), ("h", 3600.0)] where value.hasSuffix(suffix) {
            if let number = Double(value.dropLast(suffix.count)) { return number * scale }
        }
        let parts = value.split(separator: ":", omittingEmptySubsequences: false).map { Double($0) }
        guard !parts.isEmpty, parts.count <= 3, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.reduce(0) { $0 * 60 + $1! }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let milliseconds = Int((max(0, seconds) * 1000).rounded())
        return String(format: "%02d:%02d:%02d.%03d", milliseconds / 3_600_000, milliseconds / 60_000 % 60,
                      milliseconds / 1000 % 60, milliseconds % 1000)
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// Reads TTML's `<p>` lines and their timed `<span>`s. Text between spans (the spaces between words) goes on the
/// syllable before it.
private final class TTMLReader: NSObject, XMLParserDelegate {
    var lines: [SyllableLyrics.Line] = []
    var estimated = false
    private var paragraph: (start: TimeInterval, end: TimeInterval)?
    private var syllables: [SyllableLyrics.Syllable] = []
    private var loose = ""
    private var spans: [(start: TimeInterval, end: TimeInterval)?] = []
    private var spanText = ""

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        let local = name.split(separator: ":").last.map(String.init) ?? name
        let begin = attributes["begin"].flatMap(SyllableTTML.seconds)
        let end = attributes["end"].flatMap(SyllableTTML.seconds)
            ?? attributes["dur"].flatMap(SyllableTTML.seconds).flatMap { dur in begin.map { $0 + dur } }
        if local == "p" {
            paragraph = begin.map { ($0, end ?? $0) }
            syllables = []; loose = ""; spans = []
        } else if local == "span", paragraph != nil {
            spans.append(begin.map { ($0, end ?? $0) })
            if begin != nil { spanText = "" }
        } else if local == "br", paragraph != nil {
            append(" ")
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard paragraph != nil else { return }
        append(string.replacingOccurrences(of: "\n", with: " "))
    }

    private func append(_ text: String) {
        if spans.contains(where: { $0 != nil }) {
            spanText += text
        } else if let last = syllables.indices.last {
            syllables[last].text += text
        } else {
            loose += text
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let local = name.split(separator: ":").last.map(String.init) ?? name
        if local == "span", paragraph != nil, let timing = spans.popLast() {
            // Only the innermost timed span makes a syllable; an outer one (a background vocal's group) just holds them.
            if let timing, !spanText.isEmpty {
                if spanText.allSatisfy(\.isWhitespace), let last = syllables.indices.last {
                    // Spaces inside an outer span, between its syllables: they belong to the one before.
                    syllables[last].text += " "
                } else {
                    syllables.append(SyllableLyrics.Syllable(text: collapse(spanText), start: timing.start, end: timing.end))
                }
                spanText = ""
            }
        } else if local == "p", let line = paragraph {
            paragraph = nil
            if syllables.isEmpty {
                // A line-timed paragraph: spread its syllables over its time.
                let text = collapse(loose).trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { return }
                let synced = SyncedLyrics(lines: [SyncedLyrics.Line(time: line.start, text: text)])
                if var spread = SyllableLyrics.estimated(from: synced, duration: line.end).lines.first {
                    spread.end = line.end
                    lines.append(spread)
                    estimated = true
                }
            } else {
                if !loose.isEmpty { syllables[0].text = String(collapse(loose).drop(while: \.isWhitespace)) + syllables[0].text }
                syllables[0].text = String(syllables[0].text.drop(while: \.isWhitespace))
                let last = syllables.count - 1
                syllables[last].text = String(syllables[last].text.reversed().drop(while: \.isWhitespace).reversed())
                lines.append(SyllableLyrics.Line(start: line.start, end: max(line.end, syllables.map(\.end).max() ?? 0),
                                                 syllables: syllables))
            }
        }
    }

    /// Every run of white space as one space, kept where it was.
    private func collapse(_ text: String) -> String {
        var out = ""
        for character in text {
            if character.isWhitespace {
                if out.last != " " { out.append(" ") }
            } else {
                out.append(character)
            }
        }
        return out
    }
}
