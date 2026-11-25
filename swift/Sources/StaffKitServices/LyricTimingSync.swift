import AudienceCore
import StaffKitCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A song's lyric timing shared between venues (the API's `LyricTiming`): when each line is sung, with a digest of
/// each line's words. A Mac that timed a song sends the times and digests (`reportLyricTiming`), and another venue's
/// Mac joins them to the words it fetched itself (`joined(with:)`). A Mac without a Musixmatch key of its own, or whose
/// key fails, asks the API for the words with the timing instead (`syncedLines`).
///
/// The API keeps the words too, encrypted, so screens keep their lyrics when a Musixmatch key fails (Rick 2026-11-20):
/// what its own key fetched, and what a Mac reports with `keepWords` (a venue's own LRC file, or Musixmatch's words with
/// the venue's key). Basic Musixmatch plans forbid keeping lyrics: that needs a plan that allows it.
public struct SharedLyricTiming: Decodable, Sendable, Equatable {
    public struct Line: Codable, Sendable, Equatable {
        public var time: TimeInterval
        public var digest: String
        /// The line's syllables, by how many of its characters each covers (`SyllableTiming.Syllable`), when a Mac's
        /// aligner timed it that finely; nil for line timing only.
        public var syllables: [SyllableTiming.Syllable]?
        public init(time: TimeInterval, digest: String, syllables: [SyllableTiming.Syllable]? = nil) {
            self.time = time; self.digest = digest; self.syllables = syllables
        }
    }

    /// A line with its words, as the API passes them through (`LyricTiming.syncedLines`).
    public struct WordedLine: Codable, Sendable, Equatable {
        public var time: TimeInterval
        public var text: String
        public init(time: TimeInterval, text: String) { self.time = time; self.text = text }
    }

    public var spotifyTrackId: String
    public var title: String
    public var matchedLines: Int
    public var lines: [Line]
    /// The words in time from the API, only when asked for (`lyricTiming(…, words: true)`) and the API had them.
    public var syncedLines: [WordedLine]?

    public init(spotifyTrackId: String, title: String, matchedLines: Int, lines: [Line],
                syncedLines: [WordedLine]? = nil) {
        self.spotifyTrackId = spotifyTrackId; self.title = title; self.matchedLines = matchedLines; self.lines = lines
        self.syncedLines = syncedLines
    }

    /// The API's words in time as lyrics to show; nil without them.
    public var syncedLyrics: SyncedLyrics? {
        guard let syncedLines, !syncedLines.isEmpty else { return nil }
        return SyncedLyrics(lines: syncedLines.map { SyncedLyrics.Line(time: $0.time, text: $0.text) })
    }

    /// The timing of timed lyrics, for sharing: each worded line's time and digest (instrumental breaks are left out).
    public static func lines(of lyrics: SyncedLyrics) -> [Line] {
        lyrics.lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { Line(time: ($0.time * 100).rounded() / 100, digest: LyricTimingDigest.digest($0.text)) }
    }

    /// The timing of a syllable timing file (Velvet JSON) for sharing: each worded line's start, digest and syllables.
    /// Lines the aligner flagged as a mismatch (the audio sings something else there) are left out.
    public static func lines(of timing: SyllableTiming) -> [Line] {
        timing.lines.filter { !$0.digest.isEmpty && !$0.syllables.isEmpty && $0.flag != "mismatch" }
            .map { line in
                Line(time: rounded(line.start), digest: line.digest, syllables: line.syllables.map {
                    SyllableTiming.Syllable(length: $0.length, start: rounded($0.start), end: rounded($0.end),
                                            confidence: $0.confidence.map { ($0 * 100).rounded() / 100 })
                })
            }
    }

    static func rounded(_ time: TimeInterval) -> TimeInterval { (time * 100).rounded() / 100 }

    /// Lines timed syllable by syllable.
    public var syllableLines: Int { lines.filter { !($0.syllables ?? []).isEmpty }.count }

    /// The shared syllables put to these lyrics, for the captions' sweep: each lyric line takes the syllables of the
    /// next shared line with the same digest timed within a second of it (a little ahead, as `joined(with:)`), cut
    /// from its words by length and moved to the lyric line's time; a line with none gets its syllables spread over
    /// the line timing (`SyllableLyrics.estimated`). Nil when no line found syllables.
    public func syllables(with lyrics: SyncedLyrics, duration: TimeInterval? = nil) -> SyllableLyrics? {
        guard syllableLines > 0 else { return nil }
        let spread = SyllableLyrics.estimated(from: lyrics, duration: duration)
        var cursor = 0
        var found = 0
        var placed: [SyllableLyrics.Line] = []
        for (index, lyric) in lyrics.lines.enumerated() {
            let estimated = spread.lines.indices.contains(index) ? spread.lines[index] : nil
            let text = lyric.text.trimmingCharacters(in: .whitespaces)
            let digest = text.isEmpty ? "" : LyricTimingDigest.digest(text)
            let match = digest.isEmpty ? nil : lines.indices.dropFirst(cursor).prefix(12).first {
                lines[$0].digest == digest && abs(lines[$0].time - lyric.time) <= 1
            }
            guard let match else {
                if let estimated { placed.append(estimated) }
                continue
            }
            cursor = match + 1
            let shift = lyric.time - lines[match].time
            let moved = (lines[match].syllables ?? []).map {
                SyllableTiming.Syllable(length: $0.length, start: $0.start + shift, end: $0.end + shift,
                                        confidence: $0.confidence)
            }
            if !moved.isEmpty, let cut = SyllableTiming.cut(text, into: moved) {
                placed.append(SyllableLyrics.Line(start: lyric.time, end: max(lyric.time, moved.last!.end), syllables: cut))
                found += 1
            } else if let estimated {
                placed.append(estimated)
            }
        }
        return found > 0 ? SyllableLyrics(lines: placed) : nil
    }

    /// The words from a licensed source (one lyric line per line of text) put in time: each timed line takes the next
    /// unused line of text with the same digest, in order. Nil when fewer than half the timed lines found their words,
    /// which means the text is a different version of the song.
    public func joined(with text: String) -> SyncedLyrics? {
        let words = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let digests = words.map(LyricTimingDigest.digest)
        var cursor = 0
        var placed: [SyncedLyrics.Line] = []
        for line in lines {
            // Look a little ahead of the last match, so one missing or extra line of text doesn't lose the rest.
            guard let found = digests.indices.dropFirst(cursor).prefix(12).first(where: { digests[$0] == line.digest })
            else { continue }
            placed.append(SyncedLyrics.Line(time: line.time, text: words[found]))
            cursor = found + 1
        }
        guard !placed.isEmpty, placed.count * 2 >= lines.count else { return nil }
        return SyncedLyrics(lines: placed)
    }
}

/// The digest of one lyric line that the API keeps instead of its words (`LyricTiming.line_hash`): the line in
/// Unicode compatibility decomposition with accents dropped, lower case, apostrophes removed, every other run of
/// anything but letters and digits made one space, trimmed; then the first 16 hex digits of its SHA-256. Keep it in
/// step with the API.
public enum LyricTimingDigest {
    public static func normalized(_ line: String) -> String {
        let scalars = line.decomposedStringWithCompatibilityMapping.unicodeScalars
            .filter { $0.properties.generalCategory != .nonspacingMark }
        let lower = String(String.UnicodeScalarView(scalars)).lowercased()
        var out = String.UnicodeScalarView()
        var gap = false
        for scalar in lower.unicodeScalars where scalar != "'" && scalar != "\u{2019}" {
            if isWordScalar(scalar) {
                if gap, !out.isEmpty { out.append(" ") }
                gap = false
                out.append(scalar)
            } else {
                gap = true
            }
        }
        return String(out)
    }

    public static func digest(_ line: String) -> String {
        SHA256Digest.hex(Array(normalized(line).utf8)).prefix(16).description
    }

    static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }
}

/// SHA-256 (FIPS 180-4), small and dependency-free so StaffKitServices builds on Linux too (no CryptoKit there).
enum SHA256Digest {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    static func hex(_ message: [UInt8]) -> String {
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        var data = message
        let bitLength = UInt64(message.count) * 8
        data.append(0x80)
        while data.count % 64 != 56 { data.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) { data.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift))) }
        func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
        var w = [UInt32](repeating: 0, count: 64)
        for chunk in stride(from: 0, to: data.count, by: 64) {
            for i in 0..<16 {
                let b = chunk + i * 4
                w[i] = UInt32(data[b]) << 24 | UInt32(data[b + 1]) << 16 | UInt32(data[b + 2]) << 8 | UInt32(data[b + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
            for i in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = s0 &+ maj
                hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
            }
            h[0] &+= a; h[1] &+= b; h[2] &+= c; h[3] &+= d; h[4] &+= e; h[5] &+= f; h[6] &+= g; h[7] &+= hh
        }
        return h.map { word in
            let hex = String(word, radix: 16)
            return String(repeating: "0", count: 8 - hex.count) + hex
        }.joined()
    }
}

extension VenueManagementClient {
    /// Shares a song's lyric timing with every venue (`reportLyricTiming`): the times and digests, and with
    /// `keepWords` the words too, which the API keeps encrypted when they fit the kept timing, for screens whose key
    /// fails. Only a venue device whose code has the music permission may. `matchedLines` is how many lines were timed
    /// from the audio (all of them for a venue's own LRC file); a report that matched fewer than the kept one doesn't
    /// replace it, but its words still join it. An API from before kept words takes the report without them.
    @discardableResult
    public func reportLyricTiming(spotifyTrackID: String, title: String, artist: String?, duration: TimeInterval?,
                                  lyrics: SyncedLyrics, matchedLines: Int, source: String,
                                  lyricsSource: String? = nil, keepWords: Bool = false) async throws -> SharedLyricTiming {
        let words = lyrics.lines.map(\.text).joined(separator: "\n")
        if keepWords, !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let kept = try? await reportLyricTiming(spotifyTrackID: spotifyTrackID, title: title, artist: artist,
                                                   duration: duration, lyrics: lyrics, matchedLines: matchedLines,
                                                   source: source, lyricsSource: lyricsSource, words: words) {
            return kept
        }
        return try await reportLyricTiming(spotifyTrackID: spotifyTrackID, title: title, artist: artist,
                                           duration: duration, lyrics: lyrics, matchedLines: matchedLines,
                                           source: source, lyricsSource: lyricsSource, words: nil)
    }

    private func reportLyricTiming(spotifyTrackID: String, title: String, artist: String?, duration: TimeInterval?,
                                   lyrics: SyncedLyrics, matchedLines: Int, source: String,
                                   lyricsSource: String?, words: String?) async throws -> SharedLyricTiming {
        struct Payload: Decodable, Sendable { let lyricTiming: SharedLyricTiming }
        struct Response: Decodable, Sendable { let reportLyricTiming: Payload }
        let lines = SharedLyricTiming.lines(of: lyrics)
        var variables: [String: GraphQLValue] = [
            "id": .string(spotifyTrackID.replacingOccurrences(of: "spotify:track:", with: "")),
            "title": .string(title),
            "lines": .array(lines.map { .object(["time": .double($0.time), "digest": .string($0.digest)]) }),
            "matched": .int(min(matchedLines, lines.count)),
            "source": .string(source),
        ]
        if let artist { variables["artist"] = .string(artist) }
        if let duration { variables["duration"] = .int(Int((duration * 1000).rounded())) }
        if let lyricsSource { variables["lyricsSource"] = .string(lyricsSource) }
        if let words {
            variables["words"] = .string(words)
            return try await session.graphQL("""
                mutation VelvetLyricTimingWords($id: String!, $title: String!, $artist: String, $duration: Int, \
                $lines: [LyricTimingLineInput!]!, $matched: Int!, $source: String, $lyricsSource: String, \
                $words: String) {
                  reportLyricTiming(input: { spotifyTrackId: $id, title: $title, artist: $artist, \
                durationMs: $duration, lines: $lines, matchedLines: $matched, source: $source, \
                lyricsSource: $lyricsSource, words: $words }) { \
                lyricTiming { spotifyTrackId title matchedLines lines { time digest } } }
                }
                """, variables: variables, as: Response.self).reportLyricTiming.lyricTiming
        }
        return try await session.graphQL("""
            mutation VelvetLyricTiming($id: String!, $title: String!, $artist: String, $duration: Int, \
            $lines: [LyricTimingLineInput!]!, $matched: Int!, $source: String, $lyricsSource: String) {
              reportLyricTiming(input: { spotifyTrackId: $id, title: $title, artist: $artist, durationMs: $duration, \
            lines: $lines, matchedLines: $matched, source: $source, lyricsSource: $lyricsSource }) { \
            lyricTiming { spotifyTrackId title matchedLines lines { time digest } } }
            }
            """, variables: variables, as: Response.self).reportLyricTiming.lyricTiming
    }

    /// Shares a syllable timing file (Velvet JSON) with every venue for a Spotify track that plays its recording:
    /// each line's start, digest and syllables by length, never the words (`reportLyricTiming`). `matchedLines` is
    /// the lines it timed from the audio, so a venue's hand-timed LRC (every line) keeps its line times and takes
    /// these syllables. Nil when the timing has no line to share.
    @discardableResult
    public func reportSyllableTiming(_ timing: SyllableTiming, spotifyTrackID: String,
                                     lyricsSource: String? = nil) async throws -> SharedLyricTiming? {
        let recording = timing.recording
        guard recording.musicbrainzRecordingId != nil || recording.fingerprint != nil else {
            return try await reportSyllableTiming(timing, spotifyTrackID: spotifyTrackID, lyricsSource: lyricsSource,
                                                  identity: false)
        }
        do {
            return try await reportSyllableTiming(timing, spotifyTrackID: spotifyTrackID, lyricsSource: lyricsSource,
                                                  identity: true)
        } catch {
            // An API from before MusicBrainz ids: share the timing without them.
            return try await reportSyllableTiming(timing, spotifyTrackID: spotifyTrackID, lyricsSource: lyricsSource,
                                                  identity: false)
        }
    }

    /// Shares a syllable timing file for the recording itself, by its MusicBrainz recording ID, when no Spotify track
    /// is known to play it (a venue's own copy bought from a store): any venue whose copy MusicBrainz knows as the same
    /// recording finds it (`lyricTiming(venueID:recording:)`). Nil without an MBID or a line to share.
    @discardableResult
    public func reportRecordingTiming(_ timing: SyllableTiming, lyricsSource: String? = nil) async throws
        -> SharedLyricTiming? {
        guard timing.recording.musicbrainzRecordingId != nil else { return nil }
        return try await reportSyllableTiming(timing, spotifyTrackID: nil, lyricsSource: lyricsSource, identity: true)
    }

    private func reportSyllableTiming(_ timing: SyllableTiming, spotifyTrackID: String?, lyricsSource: String?,
                                      identity: Bool) async throws -> SharedLyricTiming? {
        struct Payload: Decodable, Sendable { let lyricTiming: SharedLyricTiming }
        struct Response: Decodable, Sendable { let reportLyricTiming: Payload }
        let lines = SharedLyricTiming.lines(of: timing)
        guard !lines.isEmpty else { return nil }
        let recording = timing.recording
        var variables: [String: GraphQLValue] = [
            "title": .string(recording.title),
            "lines": .array(lines.map { line in
                .object(["time": .double(line.time), "digest": .string(line.digest),
                         "syllables": .array((line.syllables ?? []).map { syllable in
                             var fields: [String: GraphQLValue] = ["length": .int(syllable.length),
                                                                    "start": .double(syllable.start),
                                                                    "end": .double(syllable.end)]
                             if let confidence = syllable.confidence { fields["confidence"] = .double(confidence) }
                             return .object(fields)
                         })])
            }),
            "matched": .int(lines.count),
            "source": .string("velvet-aligner"),
        ]
        if let artist = recording.artist { variables["artist"] = .string(artist) }
        if let duration = recording.duration { variables["duration"] = .int(Int((duration * 1000).rounded())) }
        if let isrc = recording.isrc { variables["isrc"] = .string(isrc) }
        if let lyricsSource { variables["lyricsSource"] = .string(lyricsSource) }
        if let spotifyTrackID {
            variables["id"] = .string(spotifyTrackID.replacingOccurrences(of: "spotify:track:", with: ""))
        }
        if !identity {
            return try await session.graphQL("""
                mutation VelvetSyllableTiming($id: String!, $title: String!, $artist: String, $duration: Int, \
                $isrc: String, $lines: [LyricTimingLineInput!]!, $matched: Int!, $source: String, $lyricsSource: String) {
                  reportLyricTiming(input: { spotifyTrackId: $id, title: $title, artist: $artist, durationMs: $duration, \
                isrc: $isrc, lines: $lines, matchedLines: $matched, source: $source, lyricsSource: $lyricsSource }) { \
                lyricTiming { spotifyTrackId title matchedLines lines { time digest syllables { length start end confidence } } } }
                }
                """, variables: variables, as: Response.self).reportLyricTiming.lyricTiming
        }
        if let id = recording.musicbrainzRecordingId { variables["mbid"] = .string(id) }
        if let fingerprint = recording.fingerprint { variables["fingerprint"] = .string(fingerprint) }
        return try await session.graphQL("""
            mutation VelvetRecordingTiming($id: String, $mbid: String, $fingerprint: String, $title: String!, \
            $artist: String, $duration: Int, $isrc: String, $lines: [LyricTimingLineInput!]!, $matched: Int!, \
            $source: String, $lyricsSource: String) {
              reportLyricTiming(input: { spotifyTrackId: $id, musicbrainzRecordingId: $mbid, \
            fingerprint: $fingerprint, title: $title, artist: $artist, durationMs: $duration, isrc: $isrc, \
            lines: $lines, matchedLines: $matched, source: $source, lyricsSource: $lyricsSource }) { \
            lyricTiming { spotifyTrackId title matchedLines lines { time digest syllables { length start end confidence } } } }
            }
            """, variables: variables, as: Response.self).reportLyricTiming.lyricTiming
    }

    /// Marks the shared timing of a Spotify track (else a MusicBrainz recording) as bad: Velvet Display's Bad Timing.
    /// AudienceKit drops its syllables and lets the next report replace it (`flagLyricTiming`); with `lines`, the
    /// line times were wrong too and the timing goes. True when a kept timing was cleared, false when none was kept.
    @discardableResult
    public func flagLyricTiming(venueID: String, spotifyTrackID: String?, musicbrainzRecordingID: String? = nil,
                                lines: Bool = false) async throws -> Bool {
        struct Payload: Decodable, Sendable { let cleared: Bool }
        struct Response: Decodable, Sendable { let flagLyricTiming: Payload }
        var variables: [String: GraphQLValue] = ["lines": .bool(lines)]
        if let id = spotifyTrackID?.replacingOccurrences(of: "spotify:track:", with: ""), !id.isEmpty {
            variables["id"] = .string(id)
        } else if let mbid = musicbrainzRecordingID {
            variables["mbid"] = .string(mbid)
        } else {
            return false
        }
        return try await session.graphQL("""
            mutation VelvetFlagLyricTiming($id: String, $mbid: String, $lines: Boolean) {
              flagLyricTiming(input: { spotifyTrackId: $id, musicbrainzRecordingId: $mbid, lines: $lines }) { cleared }
            }
            """, variables: variables, as: Response.self).flagLyricTiming.cleared
    }

    /// The shared lyric timing for a recording, whichever way a venue kept it: for one of its Spotify tracks, its
    /// MusicBrainz recording or its ISRC (`Venue.music.lyricTimings`). The one that timed the most lines from the
    /// audio wins. Nil when nobody has timed it; an API from before MusicBrainz ids is asked by Spotify track only.
    /// With `words`, also the words in time AudienceKit fetches for it (`syncedLines`), for a Mac without a key.
    public func lyricTiming(venueID: String, recording: MediaRecording,
                            words: Bool = false) async throws -> SharedLyricTiming? {
        struct Music: Decodable, Sendable { let lyricTimings: [SharedLyricTiming] }
        struct Venue: Decodable, Sendable { let music: Music? }
        struct Venues: Decodable, Sendable { let venue: Venue? }
        struct Response: Decodable, Sendable { let venues: Venues }
        let ids = (recording.spotifyTrackIds ?? []).map { $0.replacingOccurrences(of: "spotify:track:", with: "") }
        let mbids = recording.musicbrainzRecordingId.map { [$0] } ?? []
        let isrcs = recording.isrc.map { [$0] } ?? []
        let byTrack: () async throws -> SharedLyricTiming? = {
            guard let id = ids.first else { return nil }
            return try await self.lyricTiming(venueID: venueID, spotifyTrackID: id, words: words)
        }
        let synced = words ? " syncedLines { time text }" : ""
        guard !mbids.isEmpty || !isrcs.isEmpty else { return try await byTrack() }
        let found: [SharedLyricTiming]
        do {
            found = try await session.graphQL("""
                query VelvetRecordingTimings($venue: ID!, $ids: [String!], $mbids: [String!], $isrcs: [String!]) { \
                venues { venue(id: $venue) { music { \
                lyricTimings(spotifyTrackIds: $ids, musicbrainzRecordingIds: $mbids, isrcs: $isrcs) { \
                spotifyTrackId title matchedLines lines { time digest syllables { length start end confidence } }\(synced) \
                } } } } }
                """, variables: ["venue": .string(venueID), "ids": .array(ids.map { .string($0) }),
                                  "mbids": .array(mbids.map { .string($0) }), "isrcs": .array(isrcs.map { .string($0) })],
                as: Response.self).venues.venue?.music?.lyricTimings ?? []
        } catch {
            return try await byTrack()
        }
        return found.max { ($0.matchedLines, $0.syllableLines) < ($1.matchedLines, $1.syllableLines) }
    }

    /// The shared lyric timing for a Spotify track (`Venue.music.lyricTimings`), nil when no venue has timed it, with
    /// each line's syllables when a venue's aligner timed them. With `words`, also the words in time that AudienceKit
    /// fetches for it right then (`syncedLines`), for a Mac without a Musixmatch key of its own. An API from before
    /// shared syllables is asked again without them.
    public func lyricTiming(venueID: String, spotifyTrackID: String,
                            words: Bool = false) async throws -> SharedLyricTiming? {
        do {
            return try await lyricTiming(venueID: venueID, spotifyTrackID: spotifyTrackID, words: words, syllables: true)
        } catch {
            return try await lyricTiming(venueID: venueID, spotifyTrackID: spotifyTrackID, words: words, syllables: false)
        }
    }

    private func lyricTiming(venueID: String, spotifyTrackID: String, words: Bool,
                             syllables: Bool) async throws -> SharedLyricTiming? {
        struct Music: Decodable, Sendable { let lyricTimings: [SharedLyricTiming] }
        struct Venue: Decodable, Sendable { let music: Music? }
        struct Venues: Decodable, Sendable { let venue: Venue? }
        struct Response: Decodable, Sendable { let venues: Venues }
        let id = spotifyTrackID.replacingOccurrences(of: "spotify:track:", with: "")
        let synced = words ? " syncedLines { time text }" : ""
        let line = syllables ? "time digest syllables { length start end confidence }" : "time digest"
        return try await session.graphQL("""
            query VelvetLyricTimings($venue: ID!, $ids: [String!]!) { venues { venue(id: $venue) { music { \
            lyricTimings(spotifyTrackIds: $ids) { spotifyTrackId title matchedLines lines { \(line) }\(synced) } } } } }
            """, variables: ["venue": .string(venueID), "ids": .array([.string(id)])],
            as: Response.self).venues.venue?.music?.lyricTimings.first
    }
}

/// A song's words as AudienceKit fetched them with its own Musixmatch key (`Venue.music.lyrics`), so a venue's Mac
/// needs no key of its own: synced (LRC) when the platform's plan has them, else plain words, kept by the API so each
/// song is fetched once and survives the key failing.
public struct ProxiedLyrics: Decodable, Sendable, Equatable {
    /// One lyric line per line.
    public var words: String
    /// The words in time, as LRC, when the source had them synced.
    public var lrc: String?
    public var source: String

    public init(words: String, lrc: String?, source: String) {
        self.words = words
        self.lrc = lrc
        self.source = source
    }

    /// The synced lyrics to show, when the source had them in time.
    public var synced: SyncedLyrics? { lrc.flatMap(SyncedLyrics.lrc) }
}

extension VenueManagementClient {
    /// The song's words through AudienceKit's Musixmatch key (`Venue.music.lyrics`): only this venue's devices with
    /// the music permission. Nil when the source has no words for it.
    public func proxiedLyrics(venueID: String, title: String, artist: String?, spotifyTrackID: String? = nil,
                              musicbrainzRecordingID: String? = nil, isrc: String? = nil,
                              duration: TimeInterval? = nil) async throws -> ProxiedLyrics? {
        struct Music: Decodable, Sendable { let lyrics: ProxiedLyrics? }
        struct Venue: Decodable, Sendable { let music: Music? }
        struct Venues: Decodable, Sendable { let venue: Venue? }
        struct Response: Decodable, Sendable { let venues: Venues }
        var variables: [String: GraphQLValue] = ["venue": .string(venueID), "title": .string(title)]
        if let artist, !artist.isEmpty { variables["artist"] = .string(artist) }
        if let spotifyTrackID {
            variables["id"] = .string(spotifyTrackID.replacingOccurrences(of: "spotify:track:", with: ""))
        }
        if let musicbrainzRecordingID { variables["mbid"] = .string(musicbrainzRecordingID) }
        if let isrc { variables["isrc"] = .string(isrc) }
        if let duration { variables["duration"] = .int(Int((duration * 1000).rounded())) }
        return try await session.graphQL("""
            query VelvetLyrics($venue: ID!, $title: String!, $artist: String, $id: String, $mbid: String, \
            $isrc: String, $duration: Int) { venues { venue(id: $venue) { music { \
            lyrics(title: $title, artist: $artist, spotifyTrackId: $id, musicbrainzRecordingId: $mbid, isrc: $isrc, \
            durationMs: $duration) { words lrc source } } } } }
            """, variables: variables, as: Response.self).venues.venue?.music?.lyrics
    }
}
