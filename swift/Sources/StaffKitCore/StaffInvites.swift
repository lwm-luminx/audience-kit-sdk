import AudienceCore
import Foundation

// Onboarding invites as the staff apps make them (audience_kit_api doc/ONBOARDING_INVITES.md): a QR code that the
// Velvet Clip (a venue) or the Backstage Clip (a performer) opens to sign someone in and give them access. Focus's
// curators and Velvet's venue managers both make them; the server decides who may invite whom and says so.

/// One onboarding invite, as the `onboardingInvites` query and the invite mutations answer it.
public struct StaffInvite: Decodable, Sendable, Identifiable, Hashable {
    public let id: String
    /// `velvet` or `backstage`.
    public let app: String
    /// `join` (an existing venue or performer) or `new_listing` (the invitee adds theirs). Nil from older servers.
    public let kind: String?
    /// owner, manager or staff (Velvet); owner or manager (Backstage).
    public let access: String
    /// pending, claimed, awaiting_approval, accepted, declined, expired or revoked.
    public let status: String
    /// What the QR code opens, and the code as people type it (K7QX-2M9P-H4TD), while it is pending or claimed.
    public let url: String?
    public let code: String?
    public let note: String?
    public let expiresAt: String
    public let createdAt: String
    public let createdByName: String?
    public let claimedByName: String?
    public let firstScannedAt: String?
    public let lastScannedAt: String?
    public let claimedAt: String?
    public let acceptedAt: String?
    /// The venue or performer: on a new-listing invite, nil until they add theirs or ask to own one.
    public let subjectId: String?
    public let subjectName: String?
    public let localeName: String?
    /// The venue whose manager made it in Velvet.
    public let venueName: String?
    public let listingName: String?
    public let awaitingApprovalAt: String?
    public let declinedAt: String?
    public let decidedByName: String?

    public var isOpen: Bool { status == "pending" || status == "claimed" }
    public var isNewListing: Bool { kind == "new_listing" }
    public var isAwaitingApproval: Bool { status == "awaiting_approval" }
    public var isVenue: Bool { app == "velvet" }
    public var appName: String { isVenue ? "Velvet" : "Backstage" }
    public var accessTitle: String {
        if isNewListing { return isVenue ? "New venue" : "New performer" }
        return StaffInviteAccess(rawValue: access)?.title(venue: isVenue) ?? access.capitalized
    }

    /// Where it's got to, for the QR screen and the invite list: "Waiting to be scanned", "Scanned", "Jamie A. signed
    /// in", "Jamie A. says The Wildrose is theirs", "Joined".
    public var progress: String {
        let who = claimedByName ?? "Someone"
        switch status {
        case "accepted":
            return isNewListing ? "\(who) added \(subjectName ?? listingName ?? "their listing")" : "\(claimedByName ?? "They") joined"
        case "awaiting_approval": return "\(who) says \(subjectName ?? "a listing") is theirs"
        case "declined": return "Declined"
        case "claimed": return "\(who) signed in"
        case "expired": return "Expired"
        case "revoked": return "Revoked"
        default: return firstScannedAt == nil ? "Waiting to be scanned" : "Scanned"
        }
    }
}

/// What an invite gives the person who accepts it.
public enum StaffInviteAccess: String, CaseIterable, Identifiable, Sendable {
    case staff, manager, owner
    public var id: String { rawValue }

    public func title(venue: Bool) -> String {
        switch self {
        case .staff: "Staff"
        case .manager: "Manager"
        case .owner: venue ? "Owner" : "The performer"
        }
    }

    public var title: String { title(venue: true) }

    public func summary(venue: Bool) -> String {
        guard venue else {
            return self == .owner
                ? "It’s them: they own their page, and decide who else manages it."
                : "Manages the performer’s page, appearances and posts in Backstage."
        }
        return switch self {
        case .staff: "Works the door, tonight’s lineup and the venue’s chat in Velvet."
        case .manager: "Manages the venue’s listing, events, door and team."
        case .owner: "Owns the venue: everything a manager does, and who else can work it."
        }
    }

    /// The choices for a venue (Velvet) or a performer (Backstage: the performer themself, or a manager).
    public static func choices(venue: Bool) -> [StaffInviteAccess] { venue ? [.staff, .manager, .owner] : [.owner, .manager] }
}

/// How long a new invite works, as the API takes it.
public enum StaffInviteExpiry: Int, CaseIterable, Identifiable, Sendable {
    case hour = 1, day = 24, threeDays = 72, week = 168
    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .hour: "1 hour"
        case .day: "1 day"
        case .threeDays: "3 days"
        case .week: "7 days"
        }
    }
}

/// What someone fills in for a new invite.
public struct StaffInviteDraft: Sendable, Hashable {
    public var access: StaffInviteAccess
    public var expiry: StaffInviteExpiry = .threeDays
    public var note = ""
    public var title = ""
    public var pronouns = ""
    public var phone = ""
    /// A new listing (no subject): `velvet` or `backstage`, and where it goes.
    public var app: String?
    public var localeID: String?
    /// Velvet: the venue whose manager is inviting a performer.
    public var venueID: String?

    public init(venue: Bool) { access = venue ? .staff : .manager }

    /// An invite to add a new venue or performer page, which the invitee owns.
    public static func newListing(app: String, localeID: String? = nil, venueID: String? = nil) -> StaffInviteDraft {
        var draft = StaffInviteDraft(venue: app == "velvet")
        draft.access = .owner
        draft.app = app
        draft.localeID = localeID
        draft.venueID = venueID
        return draft
    }

    /// The mutation input: blanks are left out.
    public func input(subjectID: String?) -> [String: GraphQLValue] {
        var input: [String: GraphQLValue] = [
            "access": .string(access.rawValue), "expiresInHours": .int(expiry.rawValue)
        ]
        if let subjectID { input["subjectId"] = .string(subjectID) }
        for (key, value) in [("note", note), ("title", title), ("pronouns", pronouns), ("phone", phone),
                             ("app", app ?? ""), ("localeId", localeID ?? ""), ("venueId", venueID ?? "")] {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { input[key] = .string(trimmed) }
        }
        return input
    }
}

/// Which invites a list shows.
public enum StaffInviteScope: Sendable, Hashable {
    /// A venue's or performer's.
    case subject(String)
    /// The ones a venue's managers made in Velvet (performers).
    case venue(String)
    /// The invites to add a new listing, and the ownership requests, that a curator can see.
    case curated
}

/// Onboarding invites. The server checks who may invite whom on every call.
public struct StaffInvitesClient: Sendable {
    public let session: AudienceManagementSession

    public init(session: AudienceManagementSession) { self.session = session }

    public static let inviteFields = """
    id app kind access status url code note expiresAt createdAt createdByName claimedByName firstScannedAt lastScannedAt \
    claimedAt acceptedAt subjectId subjectName localeName venueName listingName awaitingApprovalAt declinedAt decidedByName
    """
    public static let invitesQuery = """
    query StaffInvites($subjectId: ID, $venueId: ID, $includeEnded: Boolean) {
      onboardingInvites(subjectId: $subjectId, venueId: $venueId, includeEnded: $includeEnded) { \(inviteFields) }
    }
    """
    static func mutation(_ name: String, _ input: String) -> String {
        "mutation Staff\(name)($input: \(input)!) { \(name.prefix(1).lowercased() + name.dropFirst())(input: $input) { invite { \(inviteFields) } } }"
    }
    public static let createMutation = mutation("CreateOnboardingInvite", "OnboardingInviteCreateInput")
    public static let renewMutation = mutation("RenewOnboardingInvite", "OnboardingInviteRenewInput")
    public static let revokeMutation = mutation("RevokeOnboardingInvite", "OnboardingInviteRevokeInput")
    public static let approveMutation = mutation("ApproveOnboardingInvite", "OnboardingInviteApproveInput")
    public static let declineMutation = mutation("DeclineOnboardingInvite", "OnboardingInviteDeclineInput")

    private struct Payload: Decodable, Sendable { let invite: StaffInvite }

    /// Newest first; ended ones (accepted, declined, expired, revoked) only when asked for.
    public func invites(_ scope: StaffInviteScope, includeEnded: Bool = false) async throws -> [StaffInvite] {
        var variables: [String: GraphQLValue] = ["includeEnded": .bool(includeEnded)]
        switch scope {
        case .subject(let id): variables["subjectId"] = .string(id)
        case .venue(let id): variables["venueId"] = .string(id)
        case .curated: break
        }
        return try await session.graphQL(Self.invitesQuery, variables: variables,
                                         as: [String: [StaffInvite]].self)["onboardingInvites"] ?? []
    }

    public func invites(subjectID: String, includeEnded: Bool = false) async throws -> [StaffInvite] {
        try await invites(.subject(subjectID), includeEnded: includeEnded)
    }

    public func create(_ draft: StaffInviteDraft, subjectID: String?) async throws -> StaffInvite {
        try await invite(Self.createMutation, "createOnboardingInvite", draft.input(subjectID: subjectID))
    }

    /// A new code and expiry; the old code stops working.
    public func renew(_ inviteID: String, expiry: StaffInviteExpiry = .threeDays) async throws -> StaffInvite {
        try await invite(Self.renewMutation, "renewOnboardingInvite",
                         ["id": .string(inviteID), "expiresInHours": .int(expiry.rawValue)])
    }

    /// The code stops working; access already granted stays.
    public func revoke(_ inviteID: String) async throws -> StaffInvite {
        try await invite(Self.revokeMutation, "revokeOnboardingInvite", ["id": .string(inviteID)])
    }

    /// Curators: the person who said a listing is theirs gets it.
    public func approve(_ inviteID: String) async throws -> StaffInvite {
        try await invite(Self.approveMutation, "approveOnboardingInvite", ["id": .string(inviteID)])
    }

    public func decline(_ inviteID: String) async throws -> StaffInvite {
        try await invite(Self.declineMutation, "declineOnboardingInvite", ["id": .string(inviteID)])
    }

    private func invite(_ mutation: String, _ field: String, _ input: [String: GraphQLValue]) async throws -> StaffInvite {
        let result = try await session.graphQL(mutation, variables: ["input": .object(input)], as: [String: Payload].self)
        guard let invite = result[field]?.invite else { throw AudienceKitError.decoding("The invite was missing") }
        return invite
    }
}
