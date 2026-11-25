import Foundation
import AudienceCore
import StaffKitCore

/// What Backstage needs to share an event or a performer to Instagram and Facebook: the signed link, the words for
/// the poster and caption, and the pictures to draw it from (the API's PosterArt and the performers' approved
/// cut-outs). The poster is drawn on the phone, like the console's Headliner poster; nothing redraws a face.
public struct SharePack: Sendable {
    /// One of its READY posters or backgrounds (PosterArt), newest first.
    public struct Art: Decodable, Sendable, Identifiable {
        public let id: String
        public let kind: String
        public let status: String
        public let orientation: String
        public let url: String?
        public let artistName: String?
        public var commissioned: Bool { kind == "COMMISSIONED" }
    }
    /// A performer on it, in billing order, with their approved cut-out when they have one.
    public struct Performer: Decodable, Sendable, Identifiable {
        public let id: String
        public let name: String?
        public let posterCutoutUrl: String?

        public init(id: String, name: String?, posterCutoutUrl: String?) {
            self.id = id
            self.name = name
            self.posterCutoutUrl = posterCutoutUrl
        }
    }

    /// The signed link (30 days): it opens the event or performer in the app, or on the web without it.
    public let link: URL?
    public let title: String
    /// "Fri, Oct 30 · 9 PM", in the venue's zone.
    public let when: String
    public let place: String
    public let performers: [Performer]
    public let art: [Art]
    /// The event photo or performer banner: shared as it is when there's nothing to make a poster from.
    public let bannerUrl: String?

    public init(link: URL?, title: String, when: String, place: String, performers: [Performer], art: [Art], bannerUrl: String?) {
        self.link = link
        self.title = title
        self.when = when
        self.place = place
        self.performers = performers
        self.art = art
        self.bannerUrl = bannerUrl
    }

    /// "with Anya · Darcy", or "" with nobody billed.
    public var billing: String {
        let names = performers.compactMap(\.name).filter { !$0.isEmpty }
        return names.isEmpty ? "" : "with " + names.joined(separator: " · ")
    }

    /// The newest artist's poster: it takes over from the drawn one, as in the console.
    public var artistPoster: Art? { art.first { $0.commissioned && $0.url != nil } }

    /// The newest background for a poster of `orientation` (PORTRAIT, LANDSCAPE or SQUARE), else any background.
    public func background(for orientation: String) -> Art? {
        let backgrounds = art.filter { !$0.commissioned && $0.url != nil }
        return backgrounds.first { $0.orientation == orientation } ?? backgrounds.first
    }

    /// The caption to post with it: what, when, where, and the link (Facebook and the share sheet keep it; Instagram
    /// takes the link from a story's link sticker).
    public func caption(includeLink: Bool = true) -> String {
        var lines = [title]
        let detail = [when, place].filter { !$0.isEmpty }.joined(separator: " · ")
        if !detail.isEmpty { lines.append(detail) }
        if !billing.isEmpty { lines.append(billing) }
        if includeLink, let link { lines.append(link.absoluteString) }
        return lines.joined(separator: "\n")
    }
}

extension TalentManagementClient {
    static let shareArtFields = "posterArt { id kind status orientation url artistName }"

    /// The event, its art and lineup's cut-outs, and a signed link to it.
    static let eventShareQuery = """
        query BackstageEventShare($id: ID!, $path: String!) {
          shareLink(path: $path, lifetime: MONTH) { url }
          events { event(id: $id) {
            id name startAt bannerUrl venue { name venue { id tickets { cover { timeZone } } } }
            people { lineup { nodes { id name posterCutoutUrl } } }
            \(shareArtFields)
          } }
        }
        """

    /// The performer (or troupe, with its members), their art and cut-out, and a signed link to their page.
    static let personShareQuery = """
        query BackstagePersonShare($id: ID!, $path: String!) {
          shareLink(path: $path, lifetime: MONTH) { url }
          people { person(id: $id) {
            id name posterCutoutUrl bannerUrl
            members { id name posterCutoutUrl }
            \(shareArtFields)
          } }
        }
        """

    public func eventShare(id: String) async throws -> SharePack? {
        struct Response: Decodable, Sendable {
            struct Link: Decodable, Sendable { let url: String }
            struct Event: Decodable, Sendable {
                struct People: Decodable, Sendable { let lineup: GraphQLNodes<SharePack.Performer> }
                let name: String?
                let startAt: String?
                let bannerUrl: String?
                let venue: EventPlace?
                let people: People?
                let posterArt: [SharePack.Art]
            }
            struct Events: Decodable, Sendable { let event: Event? }
            let shareLink: Link?
            let events: Events
        }
        let response = try await session.graphQL(Self.eventShareQuery, variables: ["id": .string(id), "path": .string("/events/\(id)")],
                                                as: Response.self)
        guard let event = response.events.event else { return nil }
        let zone = event.venue?.coverTimeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        return SharePack(link: response.shareLink.flatMap { URL(string: $0.url) }, title: event.name ?? "Tonight",
                         when: Self.posterDate(event.startAt, zone: zone), place: event.venue?.name ?? "",
                         performers: event.people?.lineup.nodes ?? [], art: Self.ready(event.posterArt), bannerUrl: event.bannerUrl)
    }

    public func personShare(id: String) async throws -> SharePack? {
        struct Response: Decodable, Sendable {
            struct Link: Decodable, Sendable { let url: String }
            struct Person: Decodable, Sendable {
                let id: String
                let name: String?
                let posterCutoutUrl: String?
                let bannerUrl: String?
                let members: [SharePack.Performer]
                let posterArt: [SharePack.Art]
            }
            struct People: Decodable, Sendable { let person: Person? }
            let shareLink: Link?
            let people: People
        }
        let response = try await session.graphQL(Self.personShareQuery, variables: ["id": .string(id), "path": .string("/people/\(id)")],
                                                as: Response.self)
        guard let person = response.people.person else { return nil }
        // A troupe stands as its members; a performer as themselves.
        let performers = person.members.isEmpty
            ? [SharePack.Performer(id: person.id, name: person.name, posterCutoutUrl: person.posterCutoutUrl)]
            : person.members
        return SharePack(link: response.shareLink.flatMap { URL(string: $0.url) }, title: person.name ?? "", when: "", place: "",
                         performers: performers, art: Self.ready(person.posterArt), bannerUrl: person.bannerUrl)
    }

    private static func ready(_ art: [SharePack.Art]) -> [SharePack.Art] { art.filter { $0.status == "READY" } }

    /// "Fri, Oct 30 · 9 PM" (or "9:30 PM") in `zone`.
    static func posterDate(_ iso: String?, zone: TimeZone) -> String {
        guard let date = parseInstant(iso) else { return "" }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = zone
        day.dateFormat = "EEE, MMM d"
        let time = DateFormatter()
        time.locale = day.locale
        time.timeZone = zone
        time.dateFormat = venueCalendar(zone).component(.minute, from: date) == 0 ? "h a" : "h:mm a"
        return "\(day.string(from: date)) · \(time.string(from: date))"
    }
}
