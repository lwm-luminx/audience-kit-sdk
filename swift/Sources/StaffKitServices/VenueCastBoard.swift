import Foundation
import StaffKitCore

/// What Velvet sends a Chromecast: the board the Velvet cast receiver (hotmess.social `/cast/velvet`) draws, kept up
/// to date from tonight's lineup and the room's chat feed. The receiver is a dumb renderer, so everything it shows is
/// decided here: chat as the room's guests see it, times already in the venue's zone, only https images. Velvet iOS
/// sends it over `urn:x-cast:com.audiencekit.velvet`; Velvet Android builds the same message (VelvetCast.kt).
public struct VenueCastBoard {
    public static let namespace = "urn:x-cast:com.audiencekit.velvet"

    /// The venue as the TV names it.
    public struct Venue: Sendable {
        public var id: String
        public var name: String?
        public var timeZone: TimeZone
        /// Its banner or photo, which fills the TV on a night with nothing on.
        public var photo: String?
        public init(id: String, name: String?, timeZone: TimeZone, photo: String? = nil) {
            self.id = id; self.name = name; self.timeZone = timeZone; self.photo = photo
        }
    }

    /// One set in the lineup, ready to show.
    public struct Entry: Sendable, Equatable {
        public enum State: String, Sendable { case upcoming, on, done }
        public var id: String
        public var name: String
        public var role: String
        /// "10:00 PM", "~11:00 PM" for a soft start, or "" when it goes in order.
        public var time: String
        public var state: State
        public var images: [String]
        public init(id: String, name: String, role: String, time: String, state: State, images: [String]) {
            self.id = id; self.name = name; self.role = role; self.time = time; self.state = state
            self.images = Array(images.filter(isWebURL).prefix(2))
        }
    }

    public var lineup: [Entry] = []
    /// The venue's TV slogan settings; the receiver shows no slides until they're read.
    public var slogans: VenueMarqueeSettings?
    /// Upcoming events' posters, which the receiver takes turns showing full screen with the slogans.
    public var posters: [MarqueeEventPoster] = []
    /// The venue's social profiles, for the follow-us slide after each round of posters (`MarqueeSocial`).
    public var social: [MarqueeSocialProfile] = []
    /// Whether the TV shows the room: only when the device may moderate it, and not once the room turns it away.
    public private(set) var chat: Bool
    private var messages: [VenueChatMessage] = []
    private var pinned: VenueChatMessage?
    /// When the room stops showing messages to guests; staff are sent older ones, which the TV leaves out.
    private var expiresBefore: String?
    /// How many messages fit a TV.
    public static let keep = 12

    public init(chat: Bool) { self.chat = chat }

    /// Follows the room, newest first as the feed sends it.
    public mutating func apply(_ event: VenueChatEvent) {
        switch event {
        case .history(let recent, let pinnedNow):
            messages = Array(recent.filter(\.onCastWall).prefix(Self.keep)); pinned = pinnedNow
        case .message(let message):
            guard message.onCastWall else { break }
            messages.removeAll { $0.id == message.id }
            messages = Array(([message] + messages).prefix(Self.keep))
        case .updated(let message):
            if let index = messages.firstIndex(where: { $0.id == message.id }) { messages[index] = message }
            if pinned?.id == message.id { pinned = message }
        case .removed(let id):
            messages.removeAll { $0.id == id }
            if pinned?.id == id { pinned = nil }
        case .cleared(let before, let expired):
            // An admin clearing takes the pin too; messages expiring leave it, as in Hot Mess.
            messages.removeAll { $0.sent(atOrBefore: before) }
            if !expired { pinned = nil }
        case .expiry(let before):
            expiresBefore = before
            messages.removeAll { !$0.showsToGuests(expiresBefore: before) }
        case .pinned(let announcement):
            pinned = announcement
        case .unpinned(let id):
            if pinned?.id == id { pinned = nil }
        case .left, .rejected:
            chat = false
        case .range, .offline:
            break
        }
    }

    /// The message `/cast/velvet` reads: `type: "tonight"`, the venue, tonight's event names, the lineup, the slogan
    /// setting when it's on, upcoming events' posters, and the room (oldest first) when the TV shows it.
    public func message(venue: Venue, events: [String], at now: Date = Date()) -> [String: Any] {
        var place: [String: Any] = ["id": venue.id, "name": venue.name ?? "Tonight", "timeZone": venue.timeZone.identifier]
        if let photo = venue.photo, isWebURL(photo) { place["photo"] = photo }
        var board: [String: Any] = [
            "type": "tonight",
            "venue": place,
            "events": events.filter { !$0.isEmpty },
            "lineup": lineup.map { entry in
                ["id": entry.id, "name": entry.name, "role": entry.role, "time": entry.time,
                 "state": entry.state.rawValue, "images": entry.images] as [String: Any]
            },
        ]
        if let join = venueShortLink(venue.id) { board["join"] = join }
        if let slogans, slogans.marqueeSlogans {
            var settings: [String: Any] = ["adult": slogans.adultVenue]
            if !slogans.hiddenSlogans.isEmpty { settings["hidden"] = slogans.hiddenSlogans }
            // The posters to rotate, already filtered: the venue's audience's and AudienceKit's, so the receiver never
            // falls back to its own (Hot Mess) set. Empty shows none.
            settings["slides"] = slogans.showing.compactMap { slide -> [String: Any]? in
                guard let url = slide.url else { return nil }
                return ["id": slide.id, "image": url.absoluteString, "adult": slide.adult]
            }
            board["slogans"] = settings
        }
        if !posters.isEmpty { board["posters"] = posters.map(\.castMessage) }
        if !social.isEmpty { board["social"] = MarqueeSocial.castProfiles(social) }
        if chat {
            // A special leaves the wall at its end time, as it leaves the room in Hot Mess.
            let showing = messages.filter { $0.showsToGuests(expiresBefore: expiresBefore, at: now) }
            var room: [String: Any] = ["messages": showing.reversed().map { row($0, venueName: venue.name) }]
            if let pinned, pinned.showsToGuests(expiresBefore: nil, at: now) { room["pinned"] = pinned.title ?? pinned.message }
            board["chat"] = room
        }
        return board
    }

    /// The message as JSON text, for the Cast channel.
    public func text(venue: Venue, events: [String], at now: Date = Date()) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: message(venue: venue, events: events, at: now),
                                                     options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// What's on and what's next, then a few finished sets only while there's room, as the web sign shows.
    public static func visible<Item>(_ lineup: [Item], max: Int = 8, isDone: (Item) -> Bool) -> [Item] {
        let done = lineup.filter(isDone)
        let live = lineup.filter { !isDone($0) }
        return Array((done.suffix(Swift.max(0, max - live.count)) + live).prefix(max))
    }

    private func row(_ message: VenueChatMessage, venueName: String?) -> [String: Any] {
        let sender = message.postedAsVenue ? (venueName ?? "The venue") : (message.name ?? "Guest")
        let text = message.kind == "PHOTO" ? (message.message.isEmpty ? "📷 Photo" : "📷 \(message.message)")
            : message.title.map { "\($0): \(message.message)" } ?? message.message
        var row: [String: Any] = ["sender": sender, "text": text, "venue": message.postedAsVenue]
        if let avatar = message.avatarUrl, isWebURL(avatar) { row["avatar"] = avatar }
        // A photo shows in its bubble, as guests see it in the room.
        if message.kind == "PHOTO", let photo = message.photoUrl, isWebURL(photo) { row["photo"] = photo }
        return row
    }
}

/// The venue's short link, https://hotmess.social/v/<code>: the top 47 bits of its UUID in base62 (audience_kit_api
/// VenueShortLink, hotmess.social src/lib/venueShortLink.ts), or nil for an ID that isn't a UUID.
public func venueShortLink(_ id: String) -> String? {
    let hex = id.replacingOccurrences(of: "-", with: "")
    guard hex.count == 32, hex.allSatisfy(\.isHexDigit), var value = UInt64(hex.prefix(12), radix: 16) else { return nil }
    value >>= 1
    let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
    var code = ""
    for _ in 0..<8 { code = String(alphabet[Int(value % 62)]) + code; value /= 62 }
    return "https://hotmess.social/v/\(code)"
}

private func isWebURL(_ value: String) -> Bool { value.hasPrefix("https://") }

private extension VenueChatMessage {
    /// What the wall shows: what people and the venue say, not the room's own automatic notices.
    var onCastWall: Bool { !automatic && (!message.isEmpty || kind == "PHOTO") }
}
