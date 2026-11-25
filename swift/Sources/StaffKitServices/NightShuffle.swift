import Foundation

/// One song of a night's playlist (`Event.playlist.tracks`, from Spotify's catalog through the API).
public struct PlaylistTrack: Codable, Sendable, Equatable, Hashable {
    public var uri: String
    public var title: String
    public var artist: String?
    public var durationMs: Int?

    public init(uri: String, title: String, artist: String? = nil, durationMs: Int? = nil) {
        self.uri = uri; self.title = title; self.artist = artist; self.durationMs = durationMs
    }
}

/// A song coming up, as the screens and apps show it (`Venue.music.nowPlaying.upNext`).
public struct UpNextSong: Codable, Sendable, Equatable, Hashable {
    public var title: String
    public var artist: String?

    public init(title: String, artist: String? = nil) { self.title = title; self.artist = artist }
}

/// Velvet Display's own shuffle of a night's playlist, instead of Spotify's: the order is known ahead, so the screens,
/// the Velvet app and Hot Mess can show what plays next. Each night gets its own order (seeded by the event and the
/// date), the same order again if the Mac restarts mid-night, and a different one next week.
public struct NightShuffle: Sendable, Equatable {
    public private(set) var order: [PlaylistTrack]
    /// The position in `order` of the song playing now.
    public private(set) var index = 0

    /// How many coming songs the screens and the API get.
    public static let upNextCount = 5

    public init(tracks: [PlaylistTrack], seed: String) {
        var seen = Set<String>()
        let unique = tracks.filter { seen.insert($0.uri).inserted }
        order = Self.shuffled(unique, seed: seed)
    }

    /// A night's seed: the event (or link) and the night's date, so a restart keeps the order and next week differs.
    public static func seed(for key: String, on date: Date, calendar: Calendar = .current) -> String {
        // The night runs past midnight: until 6am it's still the evening before.
        let night = calendar.date(byAdding: .hour, value: -6, to: date) ?? date
        let day = calendar.dateComponents([.year, .month, .day], from: night)
        return "\(key)|\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)"
    }

    public var current: PlaylistTrack? { order.indices.contains(index) ? order[index] : nil }

    /// The songs after the current one, wrapping round to the start of the order.
    public func upNext(_ count: Int = upNextCount) -> [PlaylistTrack] {
        guard order.count > 1 else { return [] }
        return (1...min(count, order.count - 1)).map { order[(index + $0) % order.count] }
    }

    /// Moves to the next song (round to the start after the last) and returns it.
    @discardableResult
    public mutating func advance() -> PlaylistTrack? {
        guard !order.isEmpty else { return nil }
        index = (index + 1) % order.count
        return current
    }

    /// Moves back a song.
    @discardableResult
    public mutating func back() -> PlaylistTrack? {
        guard !order.isEmpty else { return nil }
        index = (index - 1 + order.count) % order.count
        return current
    }

    /// Takes the order staff set in tonight's queue (`Venue.music.queue`): the songs after the current one play as
    /// `coming` lists them (their Spotify URIs), and the night's other songs not yet reached follow in their own order.
    /// Songs already played stay where they are, and a URI that isn't one of the night's is left out.
    public mutating func reorder(coming: [String]) {
        guard !order.isEmpty else { return }
        let played = Array(order[...index])
        let rest = order[(index + 1)...]
        let byURI = Dictionary(rest.map { ($0.uri, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        let moved = coming.compactMap { uri in seen.insert(uri).inserted ? byURI[uri] : nil }
        let others = rest.filter { !seen.contains($0.uri) }
        order = played + moved + others
    }

    /// Follows a song someone picked in Spotify itself, when it's one of the night's.
    public mutating func follow(uri: String) -> Bool {
        guard let found = order.firstIndex(where: { $0.uri == uri }) else { return false }
        index = found
        return true
    }

    /// Fisher-Yates with a SplitMix64 generator seeded from the text (FNV-1a), so the same seed gives the same order
    /// on every Mac and every run.
    static func shuffled(_ tracks: [PlaylistTrack], seed: String) -> [PlaylistTrack] {
        var state: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.utf8 { state = (state ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        func next() -> UInt64 {
            state &+= 0x9e37_79b9_7f4a_7c15
            var z = state
            z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
            z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
            return z ^ (z >> 31)
        }
        var result = tracks
        guard result.count > 1 else { return result }
        for i in stride(from: result.count - 1, to: 0, by: -1) {
            let j = Int(next() % UInt64(i + 1))
            result.swapAt(i, j)
        }
        return result
    }
}
