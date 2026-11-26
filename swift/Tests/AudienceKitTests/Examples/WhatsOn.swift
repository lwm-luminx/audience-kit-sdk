// The "What's on" screen: a locale's upcoming events grouped by night, the way a list or a widget shows them. The
// sections are plain values, so the same function feeds a SwiftUI List, a widget timeline or a watch complication:
//
//     List(nights) { night in
//         Section(night.title) { ForEach(night.rows) { row in Text(row.name) } }
//     }
import AudienceKit
import Foundation

public enum WhatsOn {
    /// One night's events, soonest first.
    public struct Night: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let rows: [Row]
    }

    /// What a row shows: the event, where, and when, in the locale's time zone.
    public struct Row: Identifiable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let place: String?
        public let time: String
        public let canceled: Bool
    }

    /// Groups `events` by the night they start on in `timeZone`; events with no start yet are left out.
    public static func nights(_ events: [Event], timeZone: TimeZone) -> [Night] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let title = DateFormatter()
        title.locale = Locale(identifier: "en_US_POSIX")
        title.timeZone = timeZone
        title.dateFormat = "EEEE, MMMM d"
        let time = DateFormatter()
        time.locale = Locale(identifier: "en_US_POSIX")
        time.timeZone = timeZone
        time.dateFormat = "h:mm a"

        let scheduled = events.compactMap { event in event.startAt.map { (event, $0) } }.sorted { $0.1 < $1.1 }
        var nights: [Night] = []
        for (event, start) in scheduled {
            let day = calendar.startOfDay(for: start)
            let row = Row(id: event.id, name: event.name ?? "Untitled", place: event.venueName,
                          time: time.string(from: start), canceled: event.isCanceled)
            let key = ISO8601DateFormatter().string(from: day)
            if let last = nights.last, last.id == key {
                nights[nights.count - 1] = Night(id: key, title: last.title, rows: last.rows + [row])
            } else {
                nights.append(Night(id: key, title: title.string(from: start), rows: [row]))
            }
        }
        return nights
    }

    /// The locale's upcoming events, by night.
    public static func load(_ client: AudienceKitClient, localeID: String,
                            timeZone: TimeZone = TimeZone(identifier: "America/Denver")!) async throws -> [Night] {
        nights(try await client.events(window: .upcoming, localeID: localeID), timeZone: timeZone)
    }
}
