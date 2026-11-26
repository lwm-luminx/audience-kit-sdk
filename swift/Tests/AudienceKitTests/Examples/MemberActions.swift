// What a signed-in member does in the app, in the order a night out goes: RSVP, add it to their calendar, show the
// cover pass at the door, and report something they saw in chat.
import AudienceKit
import Foundation

public enum MemberActions {
    /// Says they're going, and returns their answer as the API recorded it.
    public static func goingTo(_ client: AudienceKitClient, eventID: String) async throws -> RSVPState {
        try await client.setRSVP(.attending, forEvent: eventID)
    }

    /// Links that add every event they're going to (and every event at `venueID`) to their own calendar: open
    /// `webcalUrl` for Apple Calendar or Outlook, `googleUrl` for Google Calendar.
    public static func calendarLinks(_ client: AudienceKitClient, venueID: String? = nil) async throws -> CalendarLinks {
        if let venueID { return try await client.followVenueInCalendar(venueID: venueID).links }
        return try await client.createCalendarFeed().links
    }

    /// The door code and how many seconds it's good for.
    public struct DoorPass: Equatable, Sendable {
        public let code: String
        public let refreshInSeconds: Int
    }

    /// The code to show at the door for tonight's cover at a venue. It changes every 30 seconds, so draw it as a QR
    /// code (in a `TimelineView(.periodic(from: .now, by: 1))`) and draw it again when `refreshInSeconds` runs out.
    /// It's made on the phone, so it works with no signal.
    public static func doorPass(_ client: AudienceKitClient, venueID: String, at date: Date = Date()) async throws
        -> DoorPass?
    {
        guard let pass = try await client.venueCover(venueID: venueID)?.viewerAdmission, pass.status == .paid,
              let secret = pass.passSecret,
              let code = CoverPass.code(admissionID: pass.id, secret: secret, at: date)
        else { return nil }
        return DoorPass(code: code, refreshInSeconds: CoverPass.secondsRemaining(at: date))
    }

    /// Reports a chat message as harassment and blocks whoever sent it.
    public static func reportHarassment(_ client: AudienceKitClient, messageID: String) async throws -> ReportResult {
        try await client.reportContent(.message, id: messageID, reason: ReportCopy.reasons[1], block: true)
    }
}
