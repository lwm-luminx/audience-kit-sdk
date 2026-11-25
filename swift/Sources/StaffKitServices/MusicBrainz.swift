import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends a request and hands back the body and response; tests stand in a canned one.
public typealias HTTPTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

/// Spaces requests to one web service at least `interval` apart, across every client that shares it, the way
/// MusicBrainz asks (one a second per application) and AcoustID asks (three a second).
public actor RequestThrottle {
    public let interval: Duration
    private var next: ContinuousClock.Instant?

    public init(interval: Duration) { self.interval = interval }

    /// Waits for this request's turn.
    public func turn() async {
        let clock = ContinuousClock()
        let now = clock.now
        let at = max(next ?? now, now)
        next = at + interval
        if at > now { try? await Task.sleep(until: at, clock: clock) }
    }
}

/// What went wrong asking MusicBrainz or AcoustID.
public enum SongLookupError: LocalizedError, Sendable, Equatable {
    case http(Int)
    case service(String)

    public var errorDescription: String? {
        switch self {
        case .http(503): return "The service is busy (rate limited). Try again in a moment."
        case .http(let status): return "The service answered \(status)."
        case .service(let message): return message
        }
    }
}

/// MusicBrainz's web service (https://musicbrainz.org/doc/MusicBrainz_API): recordings by MBID, by ISRC, or by
/// title and artist, with their works (the songs as written, with ISWCs), ISRCs and releases. Its data is CC0.
///
/// Every request carries a User-Agent naming the app and a page about it (MusicBrainz asks for one so it can reach
/// whoever runs a misbehaving client; no person's email goes in it), and all clients share one throttle of a request a
/// second, which is MusicBrainz's limit per application. A venue running its own MusicBrainz mirror (the
/// musicbrainz-docker image) sets `baseURL` to it, which has no limit.
public struct MusicBrainzClient: Sendable {
    public static let defaultBaseURL = URL(string: "https://musicbrainz.org/ws/2/")!
    /// One for every client in the process: the limit is per application, not per client.
    public static let sharedThrottle = RequestThrottle(interval: .milliseconds(1100))

    public var baseURL: URL
    public var userAgent: String
    private let transport: HTTPTransport
    private let throttle: RequestThrottle?

    /// `userAgent` should be "App/version ( https://page-about-it )".
    public init(baseURL: URL = MusicBrainzClient.defaultBaseURL, userAgent: String,
                throttle: RequestThrottle? = MusicBrainzClient.sharedThrottle,
                transport: HTTPTransport? = nil) {
        self.baseURL = baseURL
        self.userAgent = userAgent
        // A local mirror has no limit.
        self.throttle = baseURL.host == "musicbrainz.org" ? throttle : nil
        self.transport = transport ?? { request in try await URLSession.shared.data(for: request) }
    }

    /// The User-Agent for an app: its name and version and AudienceKit's page, no personal contact.
    public static func userAgent(app: String, version: String) -> String {
        "\(app)/\(version) ( https://audiencekit.com )"
    }

    // MARK: Lookups

    /// A recording with its artist credit, ISRCs, releases and works; nil when MusicBrainz has no such recording.
    public func recording(id: String) async throws -> MusicBrainzRecording? {
        try await get("recording/\(id.lowercased())", ["inc": "artist-credits+isrcs+releases+work-rels"])
    }

    /// The recordings with this ISRC (usually one; a few when MusicBrainz has duplicates to merge).
    public func recordings(isrc: String) async throws -> [MusicBrainzRecording] {
        struct Reply: Decodable { let recordings: [MusicBrainzRecording]? }
        let code = isrc.filter { $0.isLetter || $0.isNumber }.uppercased()
        let reply: Reply? = try await get("isrc/\(code)", ["inc": "artist-credits+releases"])
        return reply?.recordings ?? []
    }

    /// Recordings matching a title and artist, best first, with MusicBrainz's score (0 to 100).
    public func searchRecordings(title: String, artist: String?, limit: Int = 5) async throws -> [MusicBrainzRecording] {
        struct Reply: Decodable { let recordings: [MusicBrainzRecording]? }
        var query = "recording:\(Self.quoted(title))"
        if let artist, !artist.isEmpty { query += " AND artist:\(Self.quoted(artist))" }
        let reply: Reply? = try await get("recording", ["query": query, "limit": String(limit)])
        return reply?.recordings ?? []
    }

    /// Lucene phrase quoting for MusicBrainz's search.
    static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    func request(_ path: String, _ query: [String: String]) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            + [URLQueryItem(name: "fmt", value: "json")]
        var request = URLRequest(url: components.url!)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        return request
    }

    /// GETs and decodes; nil for a 404. A 503 (over the limit) is tried once more after two seconds.
    private func get<T: Decodable>(_ path: String, _ query: [String: String]) async throws -> T? {
        let request = request(path, query)
        for attempt in 0..<2 {
            await throttle?.turn()
            let (data, response) = try await transport(request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            switch status {
            case 200..<300: return try JSONDecoder().decode(T.self, from: data)
            case 404: return nil
            case 503 where attempt == 0: try await Task.sleep(for: .seconds(2))
            default: throw SongLookupError.http(status)
            }
        }
        throw SongLookupError.http(503)
    }
}

/// A MusicBrainz recording as its web service returns it, the fields a sing-along needs.
public struct MusicBrainzRecording: Decodable, Sendable, Equatable {
    public struct Credit: Decodable, Sendable, Equatable {
        public struct Artist: Decodable, Sendable, Equatable { public let id: String; public let name: String }
        public let name: String
        public let joinphrase: String?
        public let artist: Artist?
    }

    public struct Release: Decodable, Sendable, Equatable {
        public let id: String
        public let title: String?
        public let date: String?
        public let barcode: String?
        public let status: String?
    }

    public struct Relation: Decodable, Sendable, Equatable {
        public struct Work: Decodable, Sendable, Equatable {
            public let id: String
            public let title: String
            public let iswcs: [String]?
        }
        public let type: String?
        public let attributes: [String]?
        public let work: Work?
        public let begin: String?
        public let end: String?
    }

    public let id: String
    public let title: String
    /// Milliseconds.
    public let length: Int?
    /// Search results only: how well it matched, 0 to 100.
    public let score: Int?
    public let isrcs: [String]?
    public let credits: [Credit]?
    public let releases: [Release]?
    public let relations: [Relation]?

    enum CodingKeys: String, CodingKey {
        case id, title, length, score, isrcs, releases, relations
        case credits = "artist-credit"
    }

    /// The artist credit as MusicBrainz writes it: "Idina Menzel & Kristin Chenoweth".
    public var artist: String? {
        guard let credits, !credits.isEmpty else { return nil }
        return credits.map { $0.name + ($0.joinphrase ?? "") }.joined().trimmingCharacters(in: .whitespaces)
    }

    public var duration: TimeInterval? { length.map { Double($0) / 1000 } }

    /// The release to show: an official one, the earliest dated.
    public var release: Release? {
        let official = releases?.filter { $0.status == nil || $0.status == "Official" } ?? []
        return (official.isEmpty ? releases ?? [] : official)
            .min { ($0.date?.isEmpty == false ? $0.date! : "9999") < ($1.date?.isEmpty == false ? $1.date! : "9999") }
    }

    /// The works it performs, as caption links: MusicBrainz's medley and cover attributes become those kinds, live a
    /// variant (tools/velvet-align's `works_from_rows` does the same from a local mirror).
    public var works: [RecordingWorkLink] {
        var seen = Set<String>()
        return (relations ?? []).compactMap { relation -> RecordingWorkLink? in
            guard let work = relation.work, seen.insert(work.id).inserted else { return nil }
            let attributes = Set((relation.attributes ?? []).map { $0.lowercased() })
            let kind: RecordingWorkLink.Kind = attributes.contains("medley") ? .medley
                : attributes.contains("cover") ? .cover : attributes.contains("live") ? .variant : .original
            return RecordingWorkLink(work: MediaWork(title: work.title, iswc: work.iswcs?.first,
                                                     musicbrainzWorkId: work.id), kind: kind)
        }
    }

    /// The recording in the media identity model, keeping what `known` already says (from the file's tags).
    public func merged(into known: MediaRecording) -> MediaRecording {
        var recording = known
        recording.musicbrainzRecordingId = id
        if recording.title.isEmpty { recording.title = title }
        recording.artist = recording.artist ?? artist
        recording.duration = recording.duration ?? duration
        recording.isrc = recording.isrc ?? isrcs?.first
        if let release {
            var media = recording.release ?? MediaRelease()
            media.musicbrainzReleaseId = media.musicbrainzReleaseId ?? release.id
            media.title = media.title ?? release.title
            media.barcode = media.barcode ?? release.barcode.flatMap { $0.isEmpty ? nil : $0 }
            media.artworkUrl = media.artworkUrl ?? "https://coverartarchive.org/release/\(release.id)/front-500"
            recording.release = media
            recording.album = recording.album ?? release.title
        }
        return recording
    }
}

/// AcoustID's lookup (https://acoustid.org/webservice): a Chromaprint fingerprint and duration to the MusicBrainz
/// recordings whose audio matches. Its key is the application's, registered at acoustid.org; it is free only for
/// non-commercial use, so a venue only turns this on with a key it has the right to use. Three requests a second.
public struct AcoustIDClient: Sendable {
    public static let sharedThrottle = RequestThrottle(interval: .milliseconds(350))
    public static let endpoint = URL(string: "https://api.acoustid.org/v2/lookup")!

    public struct Match: Decodable, Sendable, Equatable {
        public struct Recording: Decodable, Sendable, Equatable {
            public struct Artist: Decodable, Sendable, Equatable { public let id: String?; public let name: String }
            public let id: String
            public let title: String?
            public let duration: Double?
            public let artists: [Artist]?
        }
        /// AcoustID's own id for the fingerprint cluster.
        public let id: String
        /// How well the fingerprint matched, 0 to 1.
        public let score: Double
        public let recordings: [Recording]?
    }

    public var key: String
    private let transport: HTTPTransport
    private let throttle: RequestThrottle

    public init(key: String, throttle: RequestThrottle = AcoustIDClient.sharedThrottle, transport: HTTPTransport? = nil) {
        self.key = key
        self.throttle = throttle
        self.transport = transport ?? { request in try await URLSession.shared.data(for: request) }
    }

    /// Matches for a compressed fingerprint (`Chromaprint.compressed`) of a recording `duration` seconds long, best
    /// first.
    public func lookup(fingerprint: String, duration: TimeInterval) async throws -> [Match] {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "client", value: key), URLQueryItem(name: "format", value: "json"),
                           URLQueryItem(name: "meta", value: "recordings"),
                           URLQueryItem(name: "duration", value: String(Int(duration.rounded()))),
                           URLQueryItem(name: "fingerprint", value: fingerprint)]
        request.httpBody = Data((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        request.timeoutInterval = 20
        await throttle.turn()
        let (data, response) = try await transport(request)
        struct Reply: Decodable {
            struct Problem: Decodable { let message: String? }
            let status: String
            let results: [Match]?
            let error: Problem?
        }
        let reply: Reply
        do {
            reply = try JSONDecoder().decode(Reply.self, from: data)
        } catch {
            throw SongLookupError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard reply.status == "ok" else { throw SongLookupError.service(reply.error?.message ?? "AcoustID said no.") }
        return (reply.results ?? []).sorted { $0.score > $1.score }
    }
}

/// Who a song is: the recording, the works it performs, and how that was found.
public struct SongIdentification: Codable, Sendable, Equatable {
    public enum Method: String, Codable, Sendable {
        /// The file's own MusicBrainz recording ID tag (MusicBrainz Picard writes it).
        case musicbrainzTag
        /// The file's or Spotify's ISRC, looked up in MusicBrainz.
        case isrc
        /// The audio's Chromaprint fingerprint, matched by AcoustID.
        case fingerprint
        /// Title, artist and length searched in MusicBrainz.
        case search
        /// Nothing matched: only what the file says.
        case none
    }

    public var recording: MediaRecording
    public var works: [RecordingWorkLink]
    public var method: Method
    public var acoustidId: String?
    /// How sure: AcoustID's score or MusicBrainz's search score, 0 to 1; 1 for an identifier.
    public var confidence: Double?
    public var identifiedAt: Date

    public init(recording: MediaRecording, works: [RecordingWorkLink] = [], method: Method,
                acoustidId: String? = nil, confidence: Double? = nil, identifiedAt: Date = Date()) {
        self.recording = recording; self.works = works; self.method = method; self.acoustidId = acoustidId
        self.confidence = confidence; self.identifiedAt = identifiedAt
    }

    public var musicbrainzURL: URL? {
        recording.musicbrainzRecordingId.flatMap { URL(string: "https://musicbrainz.org/recording/\($0)") }
    }
}

/// Identifies a recording from what is known about it, most certain first: its MusicBrainz ID, its ISRC, its audio
/// fingerprint (when an AcoustID key is set), then a MusicBrainz search on title, artist and length.
public struct SongIdentifier: Sendable {
    public var musicBrainz: MusicBrainzClient
    public var acoustID: AcoustIDClient?
    /// The least AcoustID score to take a match on.
    public var minimumScore = 0.5
    /// The least MusicBrainz search score (0 to 100) to take, and how far the length may be off.
    public var minimumSearchScore = 90
    public var lengthTolerance: TimeInterval = 10

    public init(musicBrainz: MusicBrainzClient, acoustID: AcoustIDClient? = nil) {
        self.musicBrainz = musicBrainz; self.acoustID = acoustID
    }

    public func identify(_ known: MediaRecording) async throws -> SongIdentification {
        if let id = known.musicbrainzRecordingId, !id.isEmpty, let found = try await musicBrainz.recording(id: id) {
            return SongIdentification(recording: found.merged(into: known), works: found.works,
                                      method: .musicbrainzTag, confidence: 1)
        }
        if let isrc = known.isrc, !isrc.isEmpty,
           let best = closest(try await musicBrainz.recordings(isrc: isrc), to: known.duration),
           let found = try await musicBrainz.recording(id: best.id) {
            return SongIdentification(recording: found.merged(into: known), works: found.works, method: .isrc,
                                      confidence: 1)
        }
        if let acoustID, let fingerprint = known.fingerprint, let duration = known.duration,
           let match = try await acoustID.lookup(fingerprint: fingerprint, duration: duration)
               .first(where: { $0.score >= minimumScore && !($0.recordings ?? []).isEmpty }),
           let pick = pick(match.recordings ?? [], for: known),
           let found = try await musicBrainz.recording(id: pick.id) {
            return SongIdentification(recording: found.merged(into: known), works: found.works, method: .fingerprint,
                                      acoustidId: match.id, confidence: match.score)
        }
        if !known.title.isEmpty {
            let results = try await musicBrainz.searchRecordings(title: known.title, artist: known.artist)
            if let best = results.first(where: { result in
                (result.score ?? 0) >= minimumSearchScore
                    && Self.close(result.duration, known.duration, within: lengthTolerance)
            }), let found = try await musicBrainz.recording(id: best.id) {
                return SongIdentification(recording: found.merged(into: known), works: found.works, method: .search,
                                          confidence: Double(best.score ?? 0) / 100)
            }
        }
        return SongIdentification(recording: known, method: .none)
    }

    /// Of several recordings (an ISRC MusicBrainz hasn't deduplicated), the one nearest the file's length.
    func closest(_ recordings: [MusicBrainzRecording], to duration: TimeInterval?) -> MusicBrainzRecording? {
        guard let duration else { return recordings.first }
        return recordings.min { abs(($0.duration ?? .infinity) - duration) < abs(($1.duration ?? .infinity) - duration) }
    }

    /// Of an AcoustID match's recordings (the same audio is often on several), the one whose title is the file's,
    /// else the first.
    func pick(_ recordings: [AcoustIDClient.Match.Recording], for known: MediaRecording) -> AcoustIDClient.Match.Recording? {
        let title = LyricTimingDigest.normalized(known.title)
        return recordings.first { !title.isEmpty && LyricTimingDigest.normalized($0.title ?? "") == title }
            ?? recordings.first
    }

    static func close(_ a: TimeInterval?, _ b: TimeInterval?, within tolerance: TimeInterval) -> Bool {
        guard let a, let b else { return true }
        return abs(a - b) <= tolerance
    }
}
