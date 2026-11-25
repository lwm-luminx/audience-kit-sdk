import Foundation
import AudienceCore
import StaffKitCore

// The venue's games on its screens (audience_kit_api doc/SHOW_CONTROL.md, Rick 2026-11-21): bingo, where a host
// draws each number from Velvet or Backstage and reads it out while the screens keep the board, and group trivia's
// rounds shown big (the round, the question, its choices, then the answer). The API draws the numbers, so every
// host's phone and every screen agree.

/// One number called in a bingo game.
public struct BingoCall: Decodable, Sendable, Hashable {
    public let number: Int
    /// B, I, N, G or O in 75-ball; nil in 90-ball.
    public let letter: String?
    /// How the host reads it out: "B-12", or "12" in 90-ball.
    public let label: String

    public init(number: Int, letter: String? = nil, label: String? = nil) {
        self.number = number; self.letter = letter; self.label = label ?? letter.map { "\($0)-\(number)" } ?? "\(number)"
    }
}

/// A game of bingo at a venue: the numbers called, in order.
public struct StaffBingoGame: Decodable, Sendable, Hashable, Identifiable {
    /// SEVENTY_FIVE (B-I-N-G-O, 1 to 75) or NINETY (1 to 90).
    public static let seventyFive = "SEVENTY_FIVE"
    public static let ninety = "NINETY"

    public let id: String
    public let style: String
    /// What wins this game, as the host named it: "Four corners".
    public let pattern: String?
    public let running: Bool
    public let highest: Int
    public let remaining: Int
    public let calls: [BingoCall]
    public let lastCall: BingoCall?
    public let startedAt: String?
    public let endedAt: String?

    public init(id: String, style: String = StaffBingoGame.seventyFive, pattern: String? = nil, running: Bool = true,
                calls: [BingoCall] = [], startedAt: String? = nil, endedAt: String? = nil) {
        self.id = id; self.style = style; self.pattern = pattern; self.running = running; self.calls = calls
        self.highest = style == Self.ninety ? 90 : 75; self.remaining = highest - calls.count
        self.lastCall = calls.last; self.startedAt = startedAt; self.endedAt = endedAt
    }

    public var isSeventyFive: Bool { style != Self.ninety }
    public var called: Set<Int> { Set(calls.map(\.number)) }
    /// The calls before the latest, newest first.
    public func previous(_ count: Int) -> [BingoCall] { Array(calls.dropLast().suffix(count).reversed()) }

    /// The board's rows: B to O with 15 numbers each in 75-ball, nine rows of ten (1-10 ... 81-90) in 90-ball.
    public var rows: [(label: String?, numbers: [Int])] {
        if isSeventyFive {
            return ["B", "I", "N", "G", "O"].enumerated().map { index, letter in
                (letter, Array((index * 15 + 1)...(index * 15 + 15)))
            }
        }
        return (0..<9).map { row in (nil, Array((row * 10 + 1)...(row * 10 + 10))) }
    }
}

/// A trivia round as the screens show it: `StaffTriviaRound` with its format and where it sits in its set's rounds.
public struct MarqueeTriviaRound: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    public let statement: String
    public let choices: [StaffTriviaRound.Choice]
    public let voting: Bool
    public let closesAt: String?
    public let answer: String?
    public let roomCall: String?
    public let reveal: String?
    public let revealsAtEnd: Bool
    public let revealedAt: String?
    /// MYTH_OR_LEGEND, MULTIPLE_CHOICE or FILL_BLANK.
    public let format: String?
    /// "Round 1: Divas"; nil when the set has no rounds.
    public let roundTitle: String?
    public let questionNumber: Int?
    public let roundSize: Int?

    public init(id: String, statement: String, choices: [StaffTriviaRound.Choice] = [], voting: Bool = true,
                closesAt: String? = nil, answer: String? = nil, roomCall: String? = nil, reveal: String? = nil,
                revealsAtEnd: Bool = false, revealedAt: String? = nil, format: String? = nil, roundTitle: String? = nil,
                questionNumber: Int? = nil, roundSize: Int? = nil) {
        self.id = id; self.statement = statement; self.choices = choices; self.voting = voting; self.closesAt = closesAt
        self.answer = answer; self.roomCall = roomCall; self.reveal = reveal; self.revealsAtEnd = revealsAtEnd
        self.revealedAt = revealedAt; self.format = format; self.roundTitle = roundTitle
        self.questionNumber = questionNumber; self.roundSize = roundSize
    }

    public var isRevealed: Bool { answer != nil }
    public var isFillBlank: Bool { format == "FILL_BLANK" || choices.isEmpty }
    public var totalVotes: Int { choices.reduce(0) { $0 + $1.count } }
    public var closes: Date? { closesAt.flatMap { try? Date($0, strategy: .iso8601) } }
    /// "Question 2 of 5", or nil with no rounds.
    public var progress: String? {
        guard let questionNumber else { return nil }
        return roundSize.map { "Question \(questionNumber) of \($0)" } ?? "Question \(questionNumber)"
    }
    /// A, B, C ... for the choice at `index`.
    public static func letter(_ index: Int) -> String { String(UnicodeScalar(UInt8(65 + index % 26))) }
}

/// The song a venue's room is singing along to (Venue.liveActivity.song): its lines with their words and times, and
/// either when it started (the lyrics follow the clock) or the line it's held on (a demo, with nothing playing).
public struct LiveSong: Decodable, Sendable, Hashable {
    public struct Line: Decodable, Sendable, Hashable {
        public let time: Double
        public let text: String
        public init(time: Double, text: String) { self.time = time; self.text = text }
    }
    struct Timing: Decodable, Sendable, Hashable { let syncedLines: [Line]? }

    public let title: String?
    public let artist: String?
    /// The line the screens hold on, from 0; nil follows the clock from `startedAt`.
    public let line: Int?
    public let startedAt: String?
    /// Where the venue's player says the song is (Velvet Display reading Spotify): seconds in at `positionAt`, and
    /// whether it's playing. When set, the lyrics run from it rather than `startedAt`, so a pause or seek holds them.
    public let position: Double?
    public let positionAt: String?
    public let playing: Bool?
    let timing: Timing?

    public init(title: String?, artist: String? = nil, line: Int? = nil, startedAt: String? = nil, lines: [Line]? = nil,
                position: Double? = nil, positionAt: String? = nil, playing: Bool? = nil) {
        self.title = title; self.artist = artist; self.line = line; self.startedAt = startedAt
        self.position = position; self.positionAt = positionAt; self.playing = playing
        self.timing = Timing(syncedLines: lines)
    }

    /// Its lines with their words; nil when nobody has timed it or there are no words for it.
    public var lines: [Line]? { timing?.syncedLines.flatMap { $0.isEmpty ? nil : $0 } }
    public var lyrics: SyncedLyrics? {
        lines.map { SyncedLyrics(lines: $0.map { SyncedLyrics.Line(time: $0.time, text: $0.text) }) }
    }

    /// Where the song is at `now`: held partway into its held line (so the line shows half sung), else where the
    /// venue's player last said it was, else running on from when it started. Nil when none is known.
    public func clock(at now: Date = Date()) -> PlaybackClock? {
        if let line, let lines, lines.indices.contains(line) {
            let start = lines[line].time
            let end = lines.indices.contains(line + 1) ? lines[line + 1].time : start + 4
            return PlaybackClock(trackID: title, position: start + (end - start) * 0.55, readAt: now, playing: false)
        }
        if let position, let at = positionAt.flatMap({ try? Date($0, strategy: .iso8601) }) {
            return PlaybackClock(trackID: title, position: position, readAt: at, playing: playing ?? true)
        }
        guard let started = startedAt.flatMap({ try? Date($0, strategy: .iso8601) }) else { return nil }
        return PlaybackClock(trackID: title, position: max(0, now.timeIntervalSince(started)), readAt: now, playing: true)
    }
}

/// What the lineup on now has set for the screens (Venue.liveActivity): BINGO, TRIVIA, SING_ALONG or PROMPTS, and
/// the song while the room sings along.
public struct VenueLiveActivity: Decodable, Sendable, Hashable {
    public static let bingo = "BINGO", trivia = "TRIVIA", singAlong = "SING_ALONG"
    public let kind: String
    public let song: LiveSong?

    public init(kind: String, song: LiveSong? = nil) { self.kind = kind; self.song = song }
}

/// What a venue's screens in the Games mode show: tonight's bingo game and trivia round, and what the lineup on now
/// has set (Rick, 2026-11-21: "activity type is bingo, trivia, sing-along or whatever the event has set").
public struct VenueGames: Sendable, Hashable {
    public let bingo: StaffBingoGame?
    public let trivia: MarqueeTriviaRound?
    /// What the lineup on now has set; nil when it sets nothing (or the API doesn't say).
    public let activity: VenueLiveActivity?
    /// Whether the API said what's set (Venue.liveActivity). An API without it leaves the screen to pick, as before.
    public let followsActivity: Bool

    public init(bingo: StaffBingoGame? = nil, trivia: MarqueeTriviaRound? = nil, activity: VenueLiveActivity? = nil,
                followsActivity: Bool = false) {
        self.bingo = bingo; self.trivia = trivia; self.activity = activity; self.followsActivity = followsActivity
    }

    public enum Showing: Hashable, Sendable {
        case bingo(StaffBingoGame), trivia(MarqueeTriviaRound), singAlong(LiveSong), nothing
    }

    /// What goes up: whatever the lineup on now has set (its game, its round, its song), nothing when it sets none.
    /// From an API that doesn't say, a running bingo game first, then tonight's trivia round, then the last board.
    public var showing: Showing {
        if followsActivity {
            switch activity?.kind {
            case VenueLiveActivity.bingo: return bingo.map(Showing.bingo) ?? .nothing
            case VenueLiveActivity.trivia: return trivia.map(Showing.trivia) ?? .nothing
            case VenueLiveActivity.singAlong: return activity?.song.map(Showing.singAlong) ?? .nothing
            default: return .nothing
            }
        }
        if let bingo, bingo.running { return .bingo(bingo) }
        if let trivia { return .trivia(trivia) }
        if let bingo { return .bingo(bingo) }
        return .nothing
    }
}

extension VenueManagementClient {
    static let bingoGameFields = "id style pattern running highest remaining startedAt endedAt calls { number letter label } lastCall { number letter label }"
    static let marqueeTriviaFields = "id statement choices { label count } voting closesAt answer roomCall reveal revealsAtEnd revealedAt format roundTitle questionNumber roundSize"

    static let liveSongFields = "title artist line startedAt timing { syncedLines { time text } }"
    /// With where the venue's player is in the song; an API from before it refuses these, so it's asked again without.
    static let liveSongPositionFields = "title artist line startedAt position positionAt playing timing { syncedLines { time text } }"

    /// The venue's bingo game, trivia round and live activity tonight, for its screens. Asks for each apart, so an API
    /// without one (production before liveActivity ships, say) still gives the others.
    public func venueGames(venueID: String) async throws -> VenueGames {
        if let kind = SyntheticActivity.requested, let games = SyntheticActivity.games(kind) { return games }
        async let bingo = try? currentBingoGame(venueID: venueID)
        async let trivia = try? marqueeTrivia(venueID: venueID)
        // Not try?: it would flatten "the API said none" (nil) into "the API couldn't say".
        async let live: VenueLiveActivity?? = {
            do { return .some(try await liveActivity(venueID: venueID)) } catch { return .none }
        }()
        let activity = await live
        return VenueGames(bingo: await bingo ?? nil, trivia: await trivia ?? nil, activity: activity ?? nil,
                          followsActivity: activity != nil)
    }

    /// What the lineup on now has set for the screens; nil while it sets nothing.
    public func liveActivity(venueID: String) async throws -> VenueLiveActivity? {
        struct Venue: Decodable, Sendable { let liveActivity: VenueLiveActivity? }
        struct Venues: Decodable, Sendable { let venue: Venue? }
        struct Response: Decodable, Sendable { let venues: Venues }
        if let response = try? await session.graphQL("""
            query StaffLiveActivityAt($id: ID!) { venues { venue(id: $id) { liveActivity { kind song { \(Self.liveSongPositionFields) } } } } }
            """, variables: ["id": .string(venueID)], as: Response.self) {
            return response.venues.venue?.liveActivity
        }
        let response = try await session.graphQL("""
            query StaffLiveActivity($id: ID!) { venues { venue(id: $id) { liveActivity { kind song { \(Self.liveSongFields) } } } } }
            """, variables: ["id": .string(venueID)], as: Response.self)
        return response.venues.venue?.liveActivity
    }

    /// Tonight's bingo game at the venue: the one running, else the last ended; nil before the first.
    public func currentBingoGame(venueID: String) async throws -> StaffBingoGame? {
        struct Bingo: Decodable, Sendable { let current: StaffBingoGame? }
        struct Venue: Decodable, Sendable { let bingo: Bingo? }
        struct Venues: Decodable, Sendable { let venue: Venue? }
        struct Response: Decodable, Sendable { let venues: Venues }
        let response = try await session.graphQL("""
            query StaffBingoCurrent($id: ID!) { venues { venue(id: $id) { bingo { current { \(Self.bingoGameFields) } } } } }
            """, variables: ["id": .string(venueID)], as: Response.self)
        return response.venues.venue?.bingo?.current
    }

    /// Tonight's trivia round with its format and round, for the screens.
    public func marqueeTrivia(venueID: String) async throws -> MarqueeTriviaRound? {
        struct Trivia: Decodable, Sendable { let current: MarqueeTriviaRound? }
        struct Venue: Decodable, Sendable { let trivia: Trivia? }
        struct Venues: Decodable, Sendable { let venue: Venue? }
        struct Response: Decodable, Sendable { let venues: Venues }
        let response = try await session.graphQL("""
            query StaffMarqueeTrivia($id: ID!) { venues { venue(id: $id) { trivia { current { \(Self.marqueeTriviaFields) } } } } }
            """, variables: ["id": .string(venueID)], as: Response.self)
        return response.venues.venue?.trivia?.current
    }

    /// Starts a game of bingo at the venue (ending any still running); its screens show the board.
    @discardableResult
    public func startBingoGame(venueID: String, style: String = StaffBingoGame.seventyFive,
                               pattern: String? = nil) async throws -> StaffBingoGame {
        struct Payload: Decodable, Sendable { let game: StaffBingoGame }
        struct Response: Decodable, Sendable { let startBingoGame: Payload }
        let response = try await session.graphQL("""
            mutation StaffBingoStart($venueId: ID!, $style: BingoStyle, $pattern: String) {
              startBingoGame(input: { venueId: $venueId, style: $style, pattern: $pattern }) { game { \(Self.bingoGameFields) } }
            }
            """, variables: ["venueId": .string(venueID), "style": .string(style),
                             "pattern": pattern.flatMap { $0.isEmpty ? nil : GraphQLValue.string($0) } ?? .null],
            as: Response.self)
        return response.startBingoGame.game
    }

    /// Draws the next number, at random from those not called yet, for the host to read out.
    @discardableResult
    public func drawBingoNumber(gameID: String) async throws -> StaffBingoGame {
        struct Payload: Decodable, Sendable { let game: StaffBingoGame }
        struct Response: Decodable, Sendable { let drawBingoNumber: Payload }
        let response = try await session.graphQL("""
            mutation StaffBingoDraw($id: ID!) { drawBingoNumber(input: { id: $id }) { game { \(Self.bingoGameFields) } } }
            """, variables: ["id": .string(gameID)], as: Response.self)
        return response.drawBingoNumber.game
    }

    /// Takes back the last number called.
    @discardableResult
    public func undoBingoCall(gameID: String) async throws -> StaffBingoGame {
        struct Payload: Decodable, Sendable { let game: StaffBingoGame }
        struct Response: Decodable, Sendable { let undoBingoCall: Payload }
        let response = try await session.graphQL("""
            mutation StaffBingoUndo($id: ID!) { undoBingoCall(input: { id: $id }) { game { \(Self.bingoGameFields) } } }
            """, variables: ["id": .string(gameID)], as: Response.self)
        return response.undoBingoCall.game
    }

    /// Ends the game; the screens keep its board until the next starts.
    @discardableResult
    public func endBingoGame(gameID: String) async throws -> StaffBingoGame {
        struct Payload: Decodable, Sendable { let game: StaffBingoGame }
        struct Response: Decodable, Sendable { let endBingoGame: Payload }
        let response = try await session.graphQL("""
            mutation StaffBingoEnd($id: ID!) { endBingoGame(input: { id: $id }) { game { \(Self.bingoGameFields) } } }
            """, variables: ["id": .string(gameID)], as: Response.self)
        return response.endBingoGame.game
    }
}
