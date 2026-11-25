import Foundation
import AudienceCore

/// A message in a venue's chat room, or in a locale's: the API gives both the same fields.
public struct VenueChatMessage: Decodable, Sendable, Identifiable {
    public let id: String
    /// The message as text-only apps show it: the text, or a rich message in words.
    public let message: String
    /// What they wrote: the text, or a rich message's body or caption.
    public let body: String?
    public let avatarUrl: String?
    public let presence: String?
    /// When a special stops showing.
    public let endsAt: String?
    public let event: SharedChatEvent?
    public let name: String?
    public let sentAt: String
    public let userId: String
    public let role: String?
    /// TEXT, ANNOUNCEMENT, SPECIAL, EVENT, PHOTO, REQUEST or PROMPT; a kind added later decodes as itself and shows
    /// as text (`isRich` is false for it).
    public let kind: String
    public let title: String?
    public let photoUrl: String?
    /// Whether it's the announcement pinned under the room's title.
    public let pinned: Bool
    public let postedAsVenue: Bool
    /// Whether talent posted it as their listing (role HOST); `personId` is which. Only `TalentManagementClient`'s
    /// chat reads and the room's frames carry it; false elsewhere.
    public let postedAsPerson: Bool
    public let personId: String?
    /// Whether the server posted it on its own, like an "On now" announcement.
    public let automatic: Bool
    /// The sender's membership in the audience, for kicking or banning them. Only the audience's admins get it, and
    /// only when they ask (`AudienceChatClient`); nil otherwise.
    public let member: AudienceChatMember?
    /// The prompt a PROMPT message puts to the room: an event's chat prompt, posted as the audience.
    public let prompt: ChatPromptFrame?
    /// The prompt a TEXT message answers, if it does; the room labels it "Prompt".
    public let promptId: String?
    /// Whether it was posted as the room's audience (a prompt): shown with the audience's name and mark, no role tag.
    public let postedAsAudience: Bool

    public init(id: String, message: String, body: String? = nil, avatarUrl: String? = nil, presence: String? = nil,
                endsAt: String? = nil, event: SharedChatEvent? = nil, name: String? = nil, sentAt: String,
                userId: String, role: String? = nil, kind: String = "TEXT", title: String? = nil,
                photoUrl: String? = nil, pinned: Bool = false, postedAsVenue: Bool = false, automatic: Bool = false,
                member: AudienceChatMember? = nil, postedAsPerson: Bool = false, personId: String? = nil,
                prompt: ChatPromptFrame? = nil, promptId: String? = nil, postedAsAudience: Bool = false) {
        self.id = id; self.message = message; self.body = body; self.avatarUrl = avatarUrl; self.presence = presence
        self.endsAt = endsAt; self.event = event; self.name = name; self.sentAt = sentAt; self.userId = userId
        self.role = role; self.kind = kind; self.title = title; self.photoUrl = photoUrl; self.pinned = pinned
        self.postedAsVenue = postedAsVenue; self.automatic = automatic; self.member = member
        self.postedAsPerson = postedAsPerson; self.personId = personId
        self.prompt = prompt; self.promptId = promptId; self.postedAsAudience = postedAsAudience
    }

    private enum CodingKeys: String, CodingKey {
        case id, message, body, avatarUrl, presence, endsAt, event, name, sentAt, userId, role, kind, title, photoUrl
        case pinned, postedAsVenue, automatic, member, postedAsPerson, person, prompt, promptId, postedAsAudience
    }
    private struct PersonReference: Decodable { let id: String }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        message = try c.decode(String.self, forKey: .message)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
        presence = try c.decodeIfPresent(String.self, forKey: .presence)
        endsAt = try c.decodeIfPresent(String.self, forKey: .endsAt)
        event = try c.decodeIfPresent(SharedChatEvent.self, forKey: .event)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        sentAt = try c.decode(String.self, forKey: .sentAt)
        userId = try c.decode(String.self, forKey: .userId)
        role = try c.decodeIfPresent(String.self, forKey: .role)
        kind = try c.decode(String.self, forKey: .kind)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        photoUrl = try c.decodeIfPresent(String.self, forKey: .photoUrl)
        pinned = try c.decode(Bool.self, forKey: .pinned)
        postedAsVenue = try c.decode(Bool.self, forKey: .postedAsVenue)
        automatic = try c.decodeIfPresent(Bool.self, forKey: .automatic) ?? false
        member = try c.decodeIfPresent(AudienceChatMember.self, forKey: .member)
        postedAsPerson = try c.decodeIfPresent(Bool.self, forKey: .postedAsPerson) ?? false
        personId = try c.decodeIfPresent(PersonReference.self, forKey: .person)?.id
        // Prompts came after the rest; messages and frames from before them decode without.
        prompt = try c.decodeIfPresent(ChatPromptFrame.self, forKey: .prompt)
        promptId = try c.decodeIfPresent(String.self, forKey: .promptId)
        postedAsAudience = try c.decodeIfPresent(Bool.self, forKey: .postedAsAudience) ?? (kind == "PROMPT")
    }

    /// Whether it answers a prompt: a text message sent with `promptId`.
    public var answersPrompt: Bool { promptId != nil && kind == "TEXT" }

    /// What an AI host's posts are titled after its name (audience_kit_api Moderation::Hosting::HOST_SUFFIX).
    static let hostSuffix = " (AI host)"

    /// Whether an AI host (Arbiter's Glam) posted it: an announcement as the venue, titled "<name> (AI host)", as the
    /// API's ChatPostedAs#hosted? tells (its sender kind BOT). Its `avatarUrl` is the host's picture.
    public var postedByHost: Bool {
        kind == "ANNOUNCEMENT" && postedAsVenue && (title?.hasSuffix(Self.hostSuffix) ?? false)
    }

    /// The host's name ("Glam") for a host's post, nil for any other.
    public var hostName: String? {
        guard postedByHost, let title else { return nil }
        return String(title.dropLast(Self.hostSuffix.count))
    }
}

/// The prompt a PROMPT message puts to the room (`ChatMessage.prompt`), with its place in the night's prompts.
public struct ChatPromptFrame: Decodable, Sendable, Hashable {
    /// The prompt's ID; answers carry it as `promptId`.
    public let id: String
    /// CONVERSATION or TRIVIA; a kind added later decodes as itself and shows as a conversation prompt.
    public let kind: String
    /// The question.
    public let text: String
    /// A trivia question's answer. Guests see it once they tap or at `revealAt`; staff always do.
    public let answer: String?
    /// When the answer shows for everyone.
    public let revealAt: String?
    /// PINNED for the rotation (under the room's title), CARD for one dropped into a quiet room.
    public let shownAs: String?
    /// Which prompt of the night it is, from 1.
    public let number: Int?
    /// How many the night will show, at most.
    public let total: Int?
    /// When the next one rotates in, if one will.
    public let nextAt: String?

    public init(id: String, kind: String = "CONVERSATION", text: String, answer: String? = nil, revealAt: String? = nil,
                shownAs: String? = "PINNED", number: Int? = nil, total: Int? = nil, nextAt: String? = nil) {
        self.id = id; self.kind = kind; self.text = text; self.answer = answer; self.revealAt = revealAt
        self.shownAs = shownAs; self.number = number; self.total = total; self.nextAt = nextAt
    }

    public var isTrivia: Bool { kind == "TRIVIA" }
    /// Dropped into a quiet room rather than pinned under the title.
    public var isCard: Bool { shownAs == "CARD" }
    /// "2 of 6", when the frame says where it falls in the night.
    public var place: String? {
        guard let number, number > 0, let total, total > 0 else { return nil }
        return "\(number) of \(max(number, total))"
    }
    /// The overline over it: "Tonight's prompt · 2 of 6", "Trivia · 3 of 6", or "Prompt" for a quiet-room card.
    public var overline: String {
        let place = place.map { " · \($0)" } ?? ""
        if isTrivia { return "Trivia" + place }
        return isCard ? "Prompt" : "Tonight's prompt" + place
    }
}

public struct SharedChatEvent: Decodable, Sendable {
    public let id: String
    public let name: String?
    public let startAt: String?
    public let endAt: String?
    public let venueName: String
    public let bannerUrl: String?

    public init(id: String, name: String?, startAt: String?, endAt: String? = nil, venueName: String, bannerUrl: String? = nil) {
        self.id = id; self.name = name; self.startAt = startAt; self.endAt = endAt; self.venueName = venueName
        self.bannerUrl = bannerUrl
    }

    private enum CodingKeys: String, CodingKey { case id, name, startAt, endAt, venue, bannerUrl }

    // The venue's name comes from the event's venue mixin: `venue { name }`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        startAt = try container.decodeIfPresent(String.self, forKey: .startAt)
        endAt = try container.decodeIfPresent(String.self, forKey: .endAt)
        venueName = try container.decodeIfPresent(EventPlace.self, forKey: .venue)?.name ?? ""
        bannerUrl = try container.decodeIfPresent(String.self, forKey: .bannerUrl)
    }
}

/// An event's venue mixin as the staff apps read it: `venue { name }`, the venue's name or "To be announced", and in
/// Backstage the venue itself, `venue { name venue { id tickets { cover { timeZone } } } }`, for the event's lineup.
/// The mixin has no `id` of its own: the venue's ID and zone live on its `venue`, null while it's to be announced.
struct EventPlace: Decodable, Sendable {
    let name: String
    var id: String?
    var coverTimeZone: String?

    private enum CodingKeys: String, CodingKey { case name, venue }
    private struct Place: Decodable { let id: String; let tickets: Tickets? }
    private struct Tickets: Decodable { let cover: Cover? }
    private struct Cover: Decodable { let timeZone: String? }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        let place = try container.decodeIfPresent(Place.self, forKey: .venue)
        id = place?.id
        coverTimeZone = place?.tickets?.cover?.timeZone
    }
}

public struct VenueChatPage: Decodable, Sendable {
    public struct Edge: Decodable, Sendable { public let node: VenueChatMessage }
    public struct PageInfo: Decodable, Sendable { public let hasNextPage: Bool; public let endCursor: String? }
    public let edges: [Edge]
    public let pageInfo: PageInfo
}

public struct VenueEvent: Decodable, Sendable, Identifiable {
    public struct Person: Decodable, Sendable, Identifiable, Hashable {
        public let id: String
        public let name: String?
        public let avatarUrl: String?
        /// Their tipping mixin, where it's read (an event's hosts and lineup): `tipping { options }`.
        private let tipping: Tipping?
        public init(id: String, name: String?, avatarUrl: String? = nil) {
            self.id = id; self.name = name; self.avatarUrl = avatarUrl; tipping = nil
        }

        /// One way to tip them by link: Cash App, Venmo and the like, never the in-app payment.
        public struct TipLink: Decodable, Sendable, Hashable {
            /// The provider's name, e.g. "Cash App".
            public let name: String
            /// Their handle there, e.g. their $cashtag without the $.
            public let handle: String?
            public let url: String?
            let isInApp: Bool?
        }
        private struct Tipping: Decodable, Sendable, Hashable { let options: [TipLink] }

        /// Where to tip them directly, by link (Rick, 2026-11-23: "allow the tip functions and links to show
        /// directly"), links only: a screen can't take an in-app payment.
        public var tipLinks: [TipLink] {
            (tipping?.options ?? []).filter { $0.isInApp != true && !($0.url ?? "").isEmpty }
        }
    }
    public struct Series: Decodable, Sendable { public let id: String; public let name: String }
    /// RSVPs so far, from its rsvp mixin: `rsvp { counts { going interested } }`. Going includes ticket holders.
    /// Its staff only (admins, its listing's managers, its venue's devices); nil for everyone else.
    public struct RSVPCounts: Decodable, Sendable { public let going: Int; public let interested: Int }
    public let karaoke: StaffKaraokeNight?
    public let tags: [StaffEventTag]?
    public let id: String
    public let name: String?
    public let description: String?
    public let startAt: String?
    public let endAt: String?
    public let isCanceled: Bool
    private let venue: EventPlace?
    /// Its tickets mixin: `tickets { url cover { cents } }`.
    private let tickets: Tickets?
    public let bannerUrl: String?
    /// Its people mixin: `people { lineup { nodes } }`.
    private let lineup: Lineup?
    public let eventSeries: Series?
    public let seriesOverride: Bool
    /// Its cover mixin, inside its tickets.
    public var cover: Cover? { tickets?.cover }
    public let isFeatured: Bool?
    public let occurrenceOn: String?
    /// Its ping mixin: `ping { count }`.
    private let ping: VenueWorkspace.PingCount?
    /// Its rsvp mixin: `rsvp { counts { going interested } }`.
    private let rsvp: RSVP?

    public struct Cover: Decodable, Sendable {
        /// Cents instead of the venue's usual cover: 0 for free, nil for the venue's. On a sliding scale, the
        /// suggested amount.
        public let cents: Int?
        /// Its own sliding scale's least and most, in cents; nil for a fixed cover.
        public let minCents: Int?
        public let maxCents: Int?

        public init(cents: Int?, minCents: Int? = nil, maxCents: Int? = nil) {
            self.cents = cents; self.minCents = minCents; self.maxCents = maxCents
        }
    }
    private struct Tickets: Decodable, Sendable { let url: String?; let cover: Cover? }
    private struct Lineup: Decodable, Sendable {
        let lineup: GraphQLNodes<Person>
        let hosts: GraphQLNodes<Person>?
        let jockeys: GraphQLNodes<Person>?
        let jockeyLabel: String?
    }
    private struct RSVP: Decodable, Sendable { let counts: RSVPCounts? }
    private enum CodingKeys: String, CodingKey {
        case karaoke, tags, id, name, description, startAt, endAt, isCanceled, venue, tickets, bannerUrl, eventSeries, seriesOverride
        case isFeatured, occurrenceOn, ping, rsvp
        case lineup = "people"
    }
    /// Where to buy tickets.
    public var ticketUrl: String? { tickets?.url }
    /// Who is hosting or playing it.
    public var people: [Person] { lineup?.lineup.nodes ?? [] }
    /// The people hosting it (its hosts, not its lineup).
    public var hosts: [Person] { lineup?.hosts?.nodes ?? [] }
    /// Who runs its music or screens: its KJ, DJ or VJ (``jockeyLabel`` says which). On its lineup, not its hosts.
    public var jockeys: [Person] { lineup?.jockeys?.nodes ?? [] }
    /// What its jockeys are billed as, by its kind of night: "KJ" (karaoke), "VJ" (video or visuals) or "DJ".
    public var jockeyLabel: String { lineup?.jockeyLabel ?? "DJ" }
    /// Someone as billed on it: a jockey as "KJ Dalton", anyone else by name.
    public func billedName(_ person: Person) -> String? {
        guard let name = person.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        return jockeys.contains { $0.id == person.id } ? "\(jockeyLabel) \(name)" : name
    }
    /// Who's on the bill up front, for the board: "Hosted by Mama Alma · KJ Dalton". A night whose only one is its KJ,
    /// DJ or VJ is hosted by them: "Hosted by KJ Dalton" (Rick, 2026-11-23: "if the only linked person is a KJ they are
    /// a defacto host"). Nil with neither.
    public var billing: String? {
        let jockeyIDs = Set(jockeys.map(\.id))
        let hostNames = hosts.filter { !jockeyIDs.contains($0.id) }.compactMap { billedName($0) }
        let jockeyNames = jockeys.compactMap { billedName($0) }
        if hostNames.isEmpty, !jockeyNames.isEmpty { return "Hosted by \(jockeyNames.formatted(.list(type: .and)))" }
        let parts = [hostNames.isEmpty ? nil : "Hosted by \(hostNames.formatted(.list(type: .and)))"] + jockeyNames
        let line = parts.compactMap { $0 }.joined(separator: " · ")
        return line.isEmpty ? nil : line
    }

    /// What the screens say about singing at a KaraFun karaoke night: where to join its session when it has one,
    /// else which host to ask, by name (Rick, 2026-11-22: "for karafun
    /// events without a code the screens show 'speak to the host Dalton to sign up'"). Nil for any other event, a
    /// sing-along night included.
    public var karaokeSignUp: String? {
        guard let karaoke, karaoke.providerName?.lowercased().contains("karafun") == true else { return nil }
        if let join = karaoke.joinUrl?.trimmingCharacters(in: .whitespaces), !join.isEmpty {
            let shown = join.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
            return "Sign up to sing at \(shown)"
        }
        if let code = karaoke.sessionCode?.trimmingCharacters(in: .whitespaces), !code.isEmpty {
            return "Sign up to sing in KaraFun with code \(code)"
        }
        // No code to scan, so nobody can queue from their phone: send them to the KJ when it has one, else the host
        // (Rick, 2026-11-23: "we dont want to say 'search karafun'").
        let kjs = jockeys.compactMap { billedName($0) }
        if !kjs.isEmpty { return "Speak to \(kjs.formatted(.list(type: .or))) to sign up" }
        let names = hosts.compactMap { $0.name?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let host = switch names.count {
        case 0: "the host"
        case 1: "the host \(names[0])"
        default: "the hosts \(names.dropLast().joined(separator: ", ")) or \(names.last!)"
        }
        return "Speak to \(host) to sign up"
    }
    /// Cents instead of the venue's usual cover: 0 for free, nil for the venue's.
    public var coverCents: Int? { cover?.cents }
    /// Its own sliding scale's least and most, in cents; nil for a fixed cover (or the venue's).
    public var coverMinCents: Int? { cover?.minCents }
    public var coverMaxCents: Int? { cover?.maxCents }
    /// Its venue's name, or "To be announced".
    public var venueName: String { venue?.name ?? "" }
    /// People who pinged to come tonight; managers of its listing only.
    public var pingCount: Int? { ping?.count }
    /// RSVPs so far; its staff only.
    public var rsvpCounts: RSVPCounts? { rsvp?.counts }
}

public struct VenueSeries: Decodable, Sendable, Identifiable {
    public let karaoke: Bool?
    public let karaokeSessionCode: String?
    public let tags: [StaffEventTag]?
    public let id: String
    public let name: String
    public let description: String?
    public let rrule: String
    public let recurrenceText: String?
    public let startsOn: String
    public let startTime: String
    public let timeZone: String
    public let durationMinutes: Int?
    /// Its tickets mixin: `tickets { url }`.
    private let tickets: TicketsLink?
    public let skippedDates: [String]
    public let upcomingStarts: [String]
    public let events: [VenueEvent]
    public let bannerUrl: String?
    /// Its people mixin: `people { hosts { nodes } }`.
    private let people: People?
    public let generatedThrough: String?

    private struct People: Decodable, Sendable {
        let hosts: GraphQLNodes<VenueEvent.Person>
        let jockeys: GraphQLNodes<VenueEvent.Person>?
        let jockeyLabel: String?
    }
    /// Its default hosts.
    public var hosts: [VenueEvent.Person]? { people?.hosts.nodes }
    /// Its default jockeys: KJ, DJ or VJ (``jockeyLabel``), on each occurrence.
    public var jockeys: [VenueEvent.Person]? { people?.jockeys?.nodes }
    /// What its jockeys are billed as: KJ on a karaoke series, VJ for video or visuals, else DJ.
    public var jockeyLabel: String { people?.jockeyLabel ?? "DJ" }
    /// Where to buy tickets, copied to each occurrence.
    public var ticketUrl: String? { tickets?.url }
}

/// An event's or series' tickets mixin, read for its link: `tickets { url }`.
struct TicketsLink: Decodable, Sendable { let url: String? }

/// Someone banned from a venue: they can't see it, its events or its chat, or buy cover there.
public struct VenueChatBan: Decodable, Sendable, Identifiable {
    public let id: String
    /// Who is banned.
    public let user: Profile
    public let createdAt: String
    /// When a moderation provider's temporary ban runs out. Nil for a ban that lasts until someone unbans them.
    public let expiresAt: String?
}

extension VenueManagementClient {
    /// A person's tip links, for the screens.
    static let tipFields = "tipping { options { name handle url isInApp } }"

    static let eventFields = """
        id name description startAt endAt isCanceled tags { id name color }
        karaoke { providerName sessionCode ownSessionCode joinUrl } venue { name } tickets { url cover { cents minCents maxCents } } bannerUrl
        people { lineup { nodes { id name avatarUrl \(tipFields) } } hosts { nodes { id name avatarUrl \(tipFields) } } jockeys { nodes { id name avatarUrl \(tipFields) } } jockeyLabel } eventSeries { id name } seriesOverride isFeatured occurrenceOn ping { count }
        rsvp { counts { going interested } }
        """
    static let seriesFields = """
        id name description karaoke karaokeSessionCode tags { id name color } rrule recurrenceText startsOn startTime timeZone durationMinutes tickets { url }
        skippedDates upcomingStarts(count: 8) bannerUrl generatedThrough people { hosts { nodes { id name avatarUrl } } jockeys { nodes { id name avatarUrl } } jockeyLabel } events { \(eventFields) }
        """
    public func event(id: String) async throws -> VenueEvent? {
        struct Response: Decodable, Sendable {
            struct Events: Decodable, Sendable { let event: VenueEvent? }
            let events: Events
        }
        return try await session.graphQL("query VelvetEvent($id: ID!) { events { event(id: $id) { \(Self.eventFields) } } }",
                                       variables: ["id": .string(id)], as: Response.self).events.event
    }
    /// Creates an event at the venue, or changes one. Send only the fields that changed: any change to an
    /// occurrence sets it apart from its series.
    public func saveEvent(id: String?, venueID: String, fields: [String: GraphQLValue]) async throws -> VenueEvent {
        struct Payload: Decodable, Sendable { let event: VenueEvent }
        struct Response: Decodable, Sendable { let createEvent: Payload?; let updateEvent: Payload? }
        var input: [String: GraphQLValue] = ["event": .object(fields)]
        if let id { input["id"] = .string(id) }
        else {
            var creating = fields
            creating["venueId"] = .string(venueID)
            input["event"] = .object(creating)
        }
        let action = id == nil ? "createEvent" : "updateEvent"
        let type = id == nil ? "EventCreateInput" : "EventUpdateInput"
        let response = try await session.graphQL("mutation VelvetEventSave($input: \(type)!) { \(action)(input: $input) { event { \(Self.eventFields) } } }",
                                                 variables: ["input": .object(input)], as: Response.self)
        guard let event = (response.createEvent ?? response.updateEvent)?.event else { throw AudienceKitError.decoding("The saved event was missing") }
        return event
    }
    /// Deletes an event with its RSVPs. Deleting an occurrence skips its date.
    public func deleteEvent(id: String) async throws {
        try await operation("deleteEvent", inputType: "EventDeleteInput", input: ["id": .string(id)], selection: "deletedId")
    }
    /// Deletes a series and its upcoming occurrences, except ones edited on their own or with RSVPs.
    public func deleteSeries(id: String) async throws {
        try await operation("deleteEventSeries", inputType: "EventSeriesDeleteInput", input: ["id": .string(id)], selection: "deletedId")
    }
    /// The audience's people, for choosing hosts.
    public func people() async throws -> [VenueEvent.Person] {
        struct Response: Decodable, Sendable {
            struct People: Decodable, Sendable { let list: GraphQLNodes<VenueEvent.Person> }
            let people: People
        }
        return try await session.graphQL("query VelvetPeople { people { list { nodes { id name avatarUrl } } } }",
                                         as: Response.self).people.list.nodes
    }
    public func series(venueID: String) async throws -> [VenueSeries] {
        struct Response: Decodable, Sendable {
            struct Events: Decodable, Sendable { let series: GraphQLNodes<VenueSeries> }
            let events: Events?
        }
        return try await session.graphQL("""
            query VelvetSeries($id: ID!) { events { series(ownerId: $id) { nodes { \(Self.seriesFields) } } } }
            """, variables: ["id": .string(venueID)], as: Response.self).events?.series.nodes ?? []
    }
    public func saveSeries(id: String?, venueID: String, fields: [String: GraphQLValue]) async throws {
        var input: [String: GraphQLValue] = ["eventSeries": .object(fields)]
        if let id { input["id"] = .string(id) }
        else {
            var creating = fields
            creating["ownerVenueId"] = .string(venueID)
            creating["venueId"] = .string(venueID)
            input["eventSeries"] = .object(creating)
        }
        let action = id == nil ? "createEventSeries" : "updateEventSeries"
        let type = id == nil ? "EventSeriesCreateInput" : "EventSeriesUpdateInput"
        try await operation(action, inputType: type, input: input, selection: "eventSeries { id }")
    }
    static let messageFields = """
        id message body name avatarUrl presence endsAt sentAt userId role kind title photoUrl pinned postedAsVenue automatic
        event { id name startAt endAt venue { name } bannerUrl }
        postedAsAudience promptId prompt { \(chatPromptFrameFields) }
        """
    /// A PROMPT message's prompt, as the room shows it.
    static let chatPromptFrameFields = "id kind text answer revealAt shownAs number total nextAt"
    public func chat(venueID: String, after: String? = nil) async throws -> VenueChatPage {
        struct Response: Decodable, Sendable {
            struct Chat: Decodable, Sendable { let venueMessages: VenueChatPage }
            let chat: Chat
        }
        return try await session.graphQL("""
            query VelvetChat($id: ID!, $after: String) {
              chat {
                venueMessages(venueId: $id, first: 50, after: $after) {
                  edges { node { \(Self.messageFields) } }
                  pageInfo { hasNextPage endCursor }
                }
              }
            }
            """, variables: ["id": .string(venueID), "after": after.map(GraphQLValue.string) ?? .null],
            as: Response.self).chat.venueMessages
    }
    /// The announcement pinned under the venue's chat room title, however old; nil when none is.
    public func pinnedMessage(venueID: String) async throws -> VenueChatMessage? {
        struct Response: Decodable, Sendable {
            struct Chat: Decodable, Sendable { let pinnedMessage: VenueChatMessage? }
            struct Venue: Decodable, Sendable { let chat: Chat }
            struct Venues: Decodable, Sendable { let venue: Venue? }
            let venues: Venues
        }
        return try await session.graphQL("query VelvetPinnedMessage($id: ID!) { venues { venue(id: $id) { chat { pinnedMessage { \(Self.messageFields) } } } } }",
                                       variables: ["id": .string(venueID)], as: Response.self).venues.venue?.chat.pinnedMessage
    }
    /// Posts to the venue's chat as the venue, and returns the message as the room shows it. A special's `endsAt`
    /// must be after now and within 24 hours.
    @discardableResult
    public func send(venueID: String, message: String, announcement: String? = nil,
                     kind: String = "TEXT", title: String? = nil, photo: String? = nil,
                     eventID: String? = nil, endsAt: String? = nil, pinned: Bool = false) async throws -> VenueChatMessage? {
        struct Response: Decodable, Sendable {
            struct Payload: Decodable, Sendable { let venueMessage: VenueChatMessage? }
            let sendChatMessage: Payload?
        }
        var input: [String: GraphQLValue] = ["venueId": .string(venueID), "message": .string(message),
                                            "asVenue": .bool(true), "kind": .string(announcement == nil ? kind : "ANNOUNCEMENT"),
                                            "pinned": .bool(pinned)]
        if let title = announcement ?? title { input["title"] = .string(title) }
        if let photo { input["photo"] = .string(photo) }
        if let eventID { input["eventId"] = .string(eventID) }
        if let endsAt { input["endsAt"] = .string(endsAt) }
        return try await session.graphQL("""
            mutation VelvetSendMessage($input: ChatMessageSendInput!) { sendChatMessage(input: $input) { venueMessage { \(Self.messageFields) } } }
            """, variables: ["input": .object(input)], as: Response.self).sendChatMessage?.venueMessage
    }
    /// Edits an announcement or special: its title, its body, or when a special ends. Only what's given changes.
    /// An `endsAt` of now or earlier ends the special at once.
    @discardableResult
    public func updateMessage(id: String, title: String? = nil, message: String? = nil, endsAt: Date? = nil) async throws -> VenueChatMessage? {
        struct Response: Decodable, Sendable {
            struct Payload: Decodable, Sendable { let venueMessage: VenueChatMessage? }
            let updateChatMessage: Payload?
        }
        var input: [String: GraphQLValue] = ["id": .string(id)]
        if let title { input["title"] = .string(title) }
        if let message { input["message"] = .string(message) }
        if let endsAt { input["endsAt"] = .string(ISO8601DateFormatter().string(from: endsAt)) }
        return try await session.graphQL("""
            mutation VelvetUpdateMessage($input: ChatMessageUpdateInput!) { updateChatMessage(input: $input) { venueMessage { \(Self.messageFields) } } }
            """, variables: ["input": .object(input)], as: Response.self).updateChatMessage?.venueMessage
    }
    /// Ends a special now: guests stop seeing it.
    @discardableResult
    public func endSpecial(id: String) async throws -> VenueChatMessage? {
        try await updateMessage(id: id, endsAt: Date())
    }
    public func removeMessage(id: String) async throws {
        try await operation("removeChatMessage", inputType: "ChatMessageRemoveInput", input: ["id": .string(id)], selection: "deletedId")
    }
    public func pinMessage(id: String, pinned: Bool) async throws {
        try await operation("pinChatMessage", inputType: "ChatMessagePinInput",
                            input: ["id": .string(id), "pinned": .bool(pinned)], selection: "venueMessage { id }")
    }
    public func clearChat(venueID: String) async throws {
        try await operation("clearChatRoom", inputType: "ChatRoomClearInput", input: ["venueId": .string(venueID)], selection: "removedCount")
    }
    public func moderateChat(venueID: String, userID: String, action: String) async throws {
        try await operation("moderateVenueChat", inputType: "VenueChatModerateInput",
                            input: ["venueId": .string(venueID), "userId": .string(userID), "action": .string(action)], selection: "userId")
    }
    /// Bans `userID` from the venue: they stop seeing it, its events and its chat, and can't buy cover there.
    public func banFromVenue(venueID: String, userID: String) async throws {
        try await moderateChat(venueID: venueID, userID: userID, action: "BAN")
    }
    public func unbanFromVenue(venueID: String, userID: String) async throws {
        try await moderateChat(venueID: venueID, userID: userID, action: "UNBAN")
    }
    /// The people banned from the venue, newest first.
    public func chatBans(venueID: String) async throws -> [VenueChatBan] {
        struct Response: Decodable, Sendable {
            struct Chat: Decodable, Sendable { let venueBans: GraphQLNodes<VenueChatBan> }
            let chat: Chat
        }
        return try await session.graphQL("query VelvetChatBans($id: ID!) { chat { venueBans(venueId: $id) { nodes { id user { id name avatarUrl } createdAt expiresAt } } } }",
                                       variables: ["id": .string(venueID)], as: Response.self).chat.venueBans.nodes
    }
    private func operation(_ name: String, inputType: String, input: [String: GraphQLValue], selection: String) async throws {
        _ = try await session.graphQL("mutation VelvetOperation($input: \(inputType)!) { \(name)(input: $input) { \(selection) } }",
                                   variables: ["input": .object(input)], as: GraphQLValue.self)
    }
}
