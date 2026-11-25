import Foundation
import AudienceCore
import StaffKitCore

/// The signed-in person's private calendar subscription in the audience (API doc/CALENDAR_SYNC.md): their shifts,
/// their talent's lineup slots and events, and the events they're going to, as a feed their calendar app keeps up
/// with. Venue devices have none: their user is whoever issued the code.
public struct CalendarFeed: Decodable, Sendable, Equatable {
    /// The https feed, to copy.
    public let url: String
    /// The same as webcal://, which Calendar opens as a subscription.
    public let webcalUrl: String
    /// Google Calendar's page that adds it.
    public let googleUrl: String
}

/// Makes and reads the calendar subscription link (`createCalendarFeed`, `me { calendarFeed }`).
public struct CalendarSyncClient: Sendable {
    let session: AudienceManagementSession

    public init(session: AudienceManagementSession) { self.session = session }

    /// The link, or nil before they made one.
    public func feed() async throws -> CalendarFeed? {
        struct Response: Decodable, Sendable { struct Me: Decodable, Sendable { let calendarFeed: CalendarFeed? }; let me: Me? }
        return try await session.graphQL("query StaffCalendarFeed { me { calendarFeed { url webcalUrl googleUrl } } }",
                                         as: Response.self).me?.calendarFeed
    }

    /// The link, made on first ask; `reset` replaces it, so the old link stops working.
    public func create(reset: Bool = false) async throws -> CalendarFeed {
        struct Response: Decodable, Sendable {
            struct Payload: Decodable, Sendable { let calendarFeed: CalendarFeed }
            let createCalendarFeed: Payload
        }
        return try await session.graphQL("""
            mutation StaffCreateCalendarFeed($reset: Boolean) {
                createCalendarFeed(input: { reset: $reset }) { calendarFeed { url webcalUrl googleUrl } }
            }
            """, variables: ["reset": .bool(reset)], as: Response.self).createCalendarFeed.calendarFeed
    }
}

/// What "Add to Calendar" puts in the calendar for one event or slot: a copy, which later changes don't follow (the
/// subscription does).
public struct CalendarEntry: Sendable, Equatable, Identifiable {
    /// How long an event with no end runs, as the API's calendar feed does.
    public static let defaultLength: TimeInterval = 3 * 60 * 60

    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let location: String?
    public let notes: String?

    public init(id: String, title: String, start: Date, end: Date?, location: String? = nil, notes: String? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end.flatMap { $0 > start ? $0 : nil } ?? start.addingTimeInterval(Self.defaultLength)
        self.location = location.flatMap { $0.isEmpty ? nil : $0 }
        self.notes = notes
    }

    /// A talent event, or nil when it has no start time.
    public init?(event: TalentEvent) {
        guard let start = event.startAt.flatMap(Self.instant) else { return nil }
        self.init(id: event.id, title: event.name ?? "Event", start: start, end: event.endAt.flatMap(Self.instant),
                  location: event.venueName, notes: event.description)
    }

    static func instant(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
