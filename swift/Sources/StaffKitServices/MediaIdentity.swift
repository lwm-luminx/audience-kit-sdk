import Foundation

// What a sing-along screen is captioning, in the shape MusicBrainz uses (its CC0 dumps can seed it): lyrics belong to
// the work, timing belongs to the recording. A cover, a remaster, a live take and a film's version of a song are
// each their own recording of the same work, each with its own timing; a medley is one recording of several works,
// one after another; a mashup is several works at once. Spec: "Velvet Display: Sing-Along Captions & Media Identity".
//
// The unified media model in the API (media_songs with their variant media_items) is where these go once timings are
// shared between venues; until then Velvet Display keeps them on the Mac that made them, beside the timing files.

/// A song as written: what its lyrics belong to. Lyric text itself is never kept here (a licensed provider's Basic
/// plan forbids keeping it); `lyrics` says where to fetch it and which version the timing was made against.
public struct MediaWork: Codable, Sendable, Equatable, Hashable {
    /// ISWC, e.g. "T-070.000.000-1". Streaming services don't expose it; it comes from MusicBrainz or a publisher.
    public var iswc: String?
    public var musicbrainzWorkId: String?
    public var title: String
    /// The lyric source and version, e.g. "musixmatch:12345@2026-05-01" or "venue-lrc:<digest>".
    public var lyrics: String?

    public init(title: String, iswc: String? = nil, musicbrainzWorkId: String? = nil, lyrics: String? = nil) {
        self.title = title; self.iswc = iswc; self.musicbrainzWorkId = musicbrainzWorkId; self.lyrics = lyrics
    }
}

/// An album or single: its barcode and artwork, for the sing-along background.
public struct MediaRelease: Codable, Sendable, Equatable, Hashable {
    /// UPC or EAN; Spotify and Apple Music both expose it on albums.
    public var barcode: String?
    public var musicbrainzReleaseId: String?
    public var title: String?
    public var artworkUrl: String?

    public init(title: String? = nil, barcode: String? = nil, musicbrainzReleaseId: String? = nil, artworkUrl: String? = nil) {
        self.title = title; self.barcode = barcode; self.musicbrainzReleaseId = musicbrainzReleaseId
        self.artworkUrl = artworkUrl
    }
}

/// A specific performance: what timing belongs to.
public struct MediaRecording: Codable, Sendable, Equatable, Hashable {
    /// ISRC; Spotify and Apple Music both expose it on tracks.
    public var isrc: String?
    public var musicbrainzRecordingId: String?
    /// Chromaprint's compressed fingerprint (`fpcalc` output) of the first two minutes, for finding the recording
    /// again from any copy of the audio when it has no identifier.
    public var fingerprint: String?
    public var title: String
    public var artist: String?
    public var album: String?
    public var duration: TimeInterval?
    /// Spotify track IDs known to play this recording, so a song Spotify is playing finds its timing.
    public var spotifyTrackIds: [String]?
    public var release: MediaRelease?

    public init(title: String, artist: String? = nil, album: String? = nil, isrc: String? = nil,
                musicbrainzRecordingId: String? = nil, fingerprint: String? = nil, duration: TimeInterval? = nil,
                spotifyTrackIds: [String]? = nil, release: MediaRelease? = nil) {
        self.title = title; self.artist = artist; self.album = album; self.isrc = isrc
        self.musicbrainzRecordingId = musicbrainzRecordingId; self.fingerprint = fingerprint; self.duration = duration
        self.spotifyTrackIds = spotifyTrackIds; self.release = release
    }

    /// `other` with this recording's identifiers (MBID, ISRC, fingerprint, duration, release) wherever it has none:
    /// what identifying a song found, put onto another description of the same recording, such as a timing file's.
    public func merged(over other: MediaRecording) -> MediaRecording {
        var merged = other
        merged.musicbrainzRecordingId = merged.musicbrainzRecordingId ?? musicbrainzRecordingId
        merged.isrc = merged.isrc ?? isrc
        merged.fingerprint = merged.fingerprint ?? fingerprint
        merged.duration = merged.duration ?? duration
        merged.artist = merged.artist ?? artist
        merged.album = merged.album ?? album
        merged.release = merged.release ?? release
        if merged.title.isEmpty { merged.title = title }
        let ids = (merged.spotifyTrackIds ?? []) + (spotifyTrackIds ?? []).filter { !(merged.spotifyTrackIds ?? []).contains($0) }
        merged.spotifyTrackIds = ids.isEmpty ? nil : ids
        return merged
    }

    /// The recording's identity for a cache: its MusicBrainz ID, else its ISRC, else its fingerprint, else (the
    /// generic media module's fallback) its title, artist and album. Never a file hash: the same recording from
    /// another source or encoding must find the same timing.
    public var key: String {
        if let id = musicbrainzRecordingId?.trimmingCharacters(in: .whitespaces).lowercased(), !id.isEmpty { return "mbid:\(id)" }
        if let isrc = isrc?.filter({ $0.isLetter || $0.isNumber }).uppercased(), !isrc.isEmpty { return "isrc:\(isrc)" }
        if let fingerprint, !fingerprint.isEmpty { return "fp:" + SHA256Digest.hex(Array(fingerprint.utf8)).prefix(24) }
        let fallback = [title, artist ?? "", album ?? ""].map(LyricTimingDigest.normalized).joined(separator: "|")
        return "meta:" + SHA256Digest.hex(Array(fallback.utf8)).prefix(24)
    }
}

/// How a recording performs a work, and where in it.
public struct RecordingWorkLink: Codable, Sendable, Equatable, Hashable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// The work's own first recording.
        case original
        /// Another artist's recording; shares the work's lyrics, keeps its own timing and lyric differences.
        case cover
        /// The same artist's alternate version (remaster, live, music-video cut).
        case variant
        /// One of several works sung one after another in the recording.
        case medley
        /// One of several works overlapping in the recording.
        case mashup
    }

    public var work: MediaWork
    public var kind: Kind
    /// Seconds into the recording where the work starts and ends; nil for the whole recording.
    public var start: TimeInterval?
    public var end: TimeInterval?

    public init(work: MediaWork, kind: Kind = .original, start: TimeInterval? = nil, end: TimeInterval? = nil) {
        self.work = work; self.kind = kind; self.start = start; self.end = end
    }

    func covers(_ position: TimeInterval) -> Bool {
        position >= (start ?? 0) && position < (end ?? .infinity)
    }
}

/// What a sing-along screen does with a recording at a moment.
public enum CaptionPlan: Sendable, Equatable {
    /// Caption it: the work being sung (nil when the recording has no links, which is captioned as itself).
    case captions(MediaWork?)
    /// Overlapping works (a mashup): name them, don't caption them. Overlapping vocals are too hard to caption cleanly.
    case attribution([MediaWork])
    /// Between a medley's works.
    case none
}

extension RecordingWorkLink {
    /// What to show at `position` in a recording linked to `links`: captions for a single work or the medley work
    /// being sung, attribution only where works overlap (or any is a mashup).
    public static func plan(for links: [RecordingWorkLink], at position: TimeInterval) -> CaptionPlan {
        guard !links.isEmpty else { return .captions(nil) }
        if links.contains(where: { $0.kind == .mashup }) || overlaps(links) { return .attribution(links.map(\.work)) }
        if links.count == 1 { return .captions(links[0].work) }
        return links.first { $0.covers(position) }.map { .captions($0.work) } ?? .none
    }

    /// Whether any two links' ranges overlap (a mashup, whatever it's called).
    public static func overlaps(_ links: [RecordingWorkLink]) -> Bool {
        let ranges = links.map { ($0.start ?? 0, $0.end ?? .infinity) }.sorted { $0.0 < $1.0 }
        return zip(ranges, ranges.dropFirst()).contains { $0.1 > $1.0 }
    }
}

// MARK: Film (phase two: designed for, not used yet)

/// A film or episode: IMDb ID, cross-referenced through Wikidata and TMDb (MusicBrainz has no video equivalent).
public struct MediaVideoWork: Codable, Sendable, Equatable, Hashable {
    public var imdbId: String
    public var wikidataId: String?
    public var tmdbId: String?
    public var title: String
    /// Chromaprint's raw full-length output as a timeline (about eight sub-fingerprints a second), not one blob.
    public var timeline: FingerprintTimeline?

    public init(imdbId: String, title: String, wikidataId: String? = nil, tmdbId: String? = nil,
                timeline: FingerprintTimeline? = nil) {
        self.imdbId = imdbId; self.title = title; self.wikidataId = wikidataId; self.tmdbId = tmdbId
        self.timeline = timeline
    }
}

/// Raw Chromaprint sub-fingerprints in time order, `rate` of them a second.
public struct FingerprintTimeline: Codable, Sendable, Equatable, Hashable {
    public var rate: Double
    public var values: [UInt32]

    public init(rate: Double = FingerprintTimeline.chromaprintRate, values: [UInt32]) {
        self.rate = rate; self.values = values
    }

    /// Chromaprint's default: 11025 Hz audio, a sub-fingerprint every 1365 samples (about 8.07 a second).
    public static let chromaprintRate = 11025.0 / 1365.0

    /// Where `slice` best matches in this timeline, in seconds, with its similarity (1 is identical bits); nil when
    /// nothing scores over `threshold`. This is how a soundtrack recording or a segment's anchor is found in any
    /// edition of a film: by its sound, not its offset.
    public func find(_ slice: [UInt32], threshold: Double = 0.65) -> (time: TimeInterval, similarity: Double)? {
        guard !slice.isEmpty, slice.count <= values.count else { return nil }
        var best: (Int, Double)?
        for offset in 0...(values.count - slice.count) {
            var differing = 0
            for index in slice.indices { differing += (values[offset + index] ^ slice[index]).nonzeroBitCount }
            let similarity = 1 - Double(differing) / Double(slice.count * 32)
            if similarity > (best?.1 ?? threshold) { best = (offset, similarity) }
        }
        return best.map { (Double($0.0) / rate, $0.1) }
    }
}

/// A song in a film: its offsets in one edition, and its own fingerprint slice, which is the source of truth (a cut
/// or PAL speed-up moves the offsets; the sound stays).
public struct MediaVideoSegment: Codable, Sendable, Equatable, Hashable {
    public var video: String
    public var start: TimeInterval
    public var end: TimeInterval
    public var anchor: [UInt32]
    public var work: MediaWork?
    /// The soundtrack recording this segment matches, by its recording key.
    public var soundtrackRecording: String?

    public init(video imdbId: String, start: TimeInterval, end: TimeInterval, anchor: [UInt32],
                work: MediaWork? = nil, soundtrackRecording: String? = nil) {
        self.video = imdbId; self.start = start; self.end = end; self.anchor = anchor; self.work = work
        self.soundtrackRecording = soundtrackRecording
    }
}
