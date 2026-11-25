import AudienceCore
import Foundation

/// Which staff app an onboarding invite brings someone into: Velvet (a venue's team) or Backstage (a performer's page).
public enum OnboardingApp: String, Codable, Sendable, Hashable {
    case velvet, backstage

    /// The path prefix of its invite links: `https://audiencekit.com/v/<code>` or `/b/<code>`.
    public var pathPrefix: String { self == .velvet ? "v" : "b" }
    public var name: String { self == .velvet ? "Velvet" : "Backstage" }
}

/// An onboarding invite's link, as its QR code opens it: `https://audiencekit.com/v/K7QX2M9PH4TD` for Velvet,
/// `/b/…` for Backstage. The App Clips are invoked with it, and the apps open it as a universal link.
public struct OnboardingLink: Sendable, Hashable {
    public static let host = "audiencekit.com"

    public let app: OnboardingApp
    /// The code as the URL carries it: 12 characters, no dashes.
    public let code: String

    public init(app: OnboardingApp, code: String) {
        self.app = app
        self.code = code
    }

    /// The invite in `url`, or nil when it isn't an invite link (another page on audiencekit.com, or another site).
    /// The code is in the path (`/v/K7QX2M9PH4TD`, what the API issues) or in a `code` query item
    /// (`/v?code=K7QX2M9PH4TD`), as the App Store Connect experience URLs `https://audiencekit.com/v` and `/b` allow.
    public init?(url: URL) {
        guard let host = url.host?.lowercased(), host == Self.host || host == "www.\(Self.host)" else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard (1...2).contains(parts.count),
              let app = [OnboardingApp.velvet, .backstage].first(where: { $0.pathPrefix == parts[0] })
        else { return nil }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == "code" || $0.name == "c" })?.value
        guard let raw = parts.count == 2 ? parts[1] : query else { return nil }
        let code = Self.normalize(raw)
        guard code.count == 12 else { return nil }
        self.init(app: app, code: code)
    }

    public var url: URL { URL(string: "https://\(Self.host)/\(app.pathPrefix)/\(code)")! }
    /// The code as people read it: K7QX-2M9P-H4TD.
    public var displayCode: String {
        stride(from: 0, to: code.count, by: 4).map { offset in
            let start = code.index(code.startIndex, offsetBy: offset)
            return String(code[start..<code.index(start, offsetBy: min(4, code.count - offset))])
        }.joined(separator: "-")
    }

    /// Upper case without dashes or spaces, reading I and L as 1 and O as 0 (Crockford base32), as the API does.
    static func normalize(_ code: String) -> String {
        String(code.uppercased().filter { $0 != "-" && $0 != " " }.map { character -> Character in
            switch character {
            case "I", "L": "1"
            case "O": "0"
            default: character
            }
        })
    }
}

/// What an invite says before anyone signs in (`GET /v1/onboarding/:code`): who wants them, where, and as what.
public struct OnboardingPreview: Decodable, Sendable, Hashable {
    public struct Audience: Decodable, Sendable, Hashable {
        public let id: String
        public let name: String
        public let subdomain: String
    }

    public struct Subject: Decodable, Sendable, Hashable {
        /// `Venue` or `Person`.
        public let type: String
        public let id: String
        public let name: String?
        public let imageUrl: String?

        public init(type: String, id: String, name: String?, imageUrl: String?) {
            self.type = type; self.id = id; self.name = name; self.imageUrl = imageUrl
        }

        enum CodingKeys: String, CodingKey { case type, id, name, imageUrl = "image_url" }

        public var isVenue: Bool { type == "Venue" }
        public var imageURL: URL? { imageUrl.flatMap(URL.init(string:)) }
    }

    /// A new listing's locale, and the venue whose manager made a performer invite.
    public struct Place: Decodable, Sendable, Hashable {
        public let id: String
        public let name: String?
    }

    public let app: OnboardingApp
    /// `join` (an existing venue or performer) or `new_listing` (they add theirs). Nil from older servers: `join`.
    public let kind: String?
    /// `owner`, `manager` or `staff` for Velvet; `owner` (the performer themself) or `manager` for Backstage.
    public let access: String
    /// `pending`, `claimed`, or `awaiting_approval` once they asked to own an existing listing.
    public let status: String
    public let expiresAt: Date
    public let note: String?
    /// Who invited them, as "First L.".
    public let invitedBy: String?
    public let audience: Audience
    /// The venue or performer. Nil on a new-listing invite until they add theirs or ask to own one.
    public let subject: Subject?
    public let locale: Place?
    public let venue: Place?
    /// What the curator filled in for them (`title`, `phone`, `pronouns`), once they've signed in and claimed it.
    public let prefill: [String: String]?

    enum CodingKeys: String, CodingKey {
        case app, kind, access, status, note, audience, subject, locale, venue, prefill
        case expiresAt = "expires_at", invitedBy = "invited_by"
    }

    public var isOwner: Bool { access == "owner" }
    public var isVenue: Bool { app == .velvet }
    public var isNewListing: Bool { kind == "new_listing" }
    public var isAwaitingApproval: Bool { status == "awaiting_approval" }

    /// "work the door at The Wildrose", for the welcome's "Rick M. invited you to …".
    public var invitation: String {
        if isNewListing {
            return isVenue ? "add your venue to \(audience.name)" : "set up your performer page on \(audience.name)"
        }
        let place = subject?.name ?? (isVenue ? "the venue" : "the lineup")
        switch (app, access) {
        case (.velvet, "owner"): return "set up \(place) as its owner"
        case (.velvet, "manager"): return "help manage \(place)"
        case (.velvet, _): return "join the team at \(place)"
        case (.backstage, "owner"): return "take over your page as \(place)"
        case (.backstage, _): return "manage \(place)’s page"
        }
    }

    /// What accepting gives them, for the details step.
    public var accessSummary: String {
        switch (app, access) {
        case (.velvet, "owner"): "Owner: you manage the venue, its listing and who else can work it."
        case (.velvet, "manager"): "Manager: the venue's listing, events, door and team."
        case (.velvet, _): "Staff: the door, tonight's lineup and the venue's chat."
        case (.backstage, "owner"): "Your performer page, your appearances and your posts, and who else manages them."
        case (.backstage, _): "The performer's page, appearances and posts."
        }
    }
}

/// What a new-listing invite's invitee might mean while they look for their listing
/// (`GET /v1/onboarding/:code/matches?q=`).
public struct OnboardingMatches: Decodable, Sendable, Hashable {
    /// A Google place, and the audience's venue there when it already lists it.
    public struct Place: Decodable, Sendable, Hashable, Identifiable {
        public let placeId: String
        public let name: String?
        public let address: String?
        public let venueId: String?
        public var id: String { placeId }

        public init(placeId: String, name: String?, address: String?, venueId: String?) {
            self.placeId = placeId; self.name = name; self.address = address; self.venueId = venueId
        }

        enum CodingKeys: String, CodingKey {
            case name, address
            case placeId = "place_id", venueId = "venue_id"
        }
    }

    /// One of the audience's venues or performers.
    public struct Listing: Decodable, Sendable, Hashable, Identifiable {
        public let id: String
        public let name: String?
        public let imageUrl: String?
        /// Someone owns it already: asking for it still goes to a curator.
        public let owned: Bool?

        enum CodingKeys: String, CodingKey { case id, name, owned, imageUrl = "image_url" }

        public var imageURL: URL? { imageUrl.flatMap(URL.init(string:)) }
    }

    public let places: [Place]?
    public let venues: [Listing]?
    public let people: [Listing]?

    public init(places: [Place]? = nil, venues: [Listing]? = nil, people: [Listing]? = nil) {
        self.places = places; self.venues = venues; self.people = people
    }

    public var isEmpty: Bool { (places ?? []).isEmpty && (venues ?? []).isEmpty && (people ?? []).isEmpty }
}

/// What a new-listing invite's invitee picked: an existing listing (an ownership request a curator approves), a
/// Google place (a new venue, or a request when the audience already lists it), or one they typed in.
public enum OnboardingListingChoice: Sendable, Hashable {
    case existing(id: String, name: String?)
    case place(OnboardingMatches.Place)
    case typed(name: String, address: String?)

    /// Whether accepting asks a curator first.
    public var isRequest: Bool {
        switch self {
        case .existing: true
        case .place(let place): place.venueId != nil
        case .typed: false
        }
    }

    public var name: String? {
        switch self {
        case .existing(_, let name): name
        case .place(let place): place.name
        case .typed(let name, _): name
        }
    }

    /// The accept call's body.
    public var body: [String: Any] {
        switch self {
        case .existing(let id, _):
            return ["match_id": id]
        case .place(let place):
            if let venueId = place.venueId { return ["match_id": venueId] }
            return ["listing": ["google_place_id": place.placeId, "name": place.name ?? ""]]
        case .typed(let name, let address):
            var listing = ["name": name]
            if let address, !address.isEmpty { listing["address"] = address }
            return ["listing": listing]
        }
    }
}

/// What accepting an invite answers (`POST /v1/onboarding/:code/accept`): the session is now in the invite's audience.
public struct OnboardingAcceptance: Sendable, Hashable {
    public let audience: ManagedAudience
    public let subject: OnboardingPreview.Subject
    /// The person's role in the audience: `listing`, or `admin` for an audience admin.
    public let role: String

    public init(audience: ManagedAudience, subject: OnboardingPreview.Subject, role: String) {
        self.audience = audience; self.subject = subject; self.role = role
    }
}

/// Where an App Clip leaves its session for its app (Velvet or Backstage) to pick up after it's installed.
///
/// A clip can't write to the staff apps' shared keychain group, so each clip shares one app group with its own app
/// (`group.com.audiencekit.Velvet.clip`) and keeps the session there as a keychain item, or as a file in that group's
/// container when the keychain refuses the item (``HandoffCredentialStore``). On launch the
/// app moves it into ``StaffCredentialStore`` and deletes it, with the audience it was accepted in and the venue or
/// performer to open.
public enum OnboardingHandoff {
    /// The app group a clip shares with its app, for a staff app's bundle ID (`com.audiencekit.Velvet.next`).
    public static func accessGroup(appBundleID: String) -> String { "group.\(appBundleID).clip" }

    /// What the app opens once it has the session: the accepted venue or performer, in its audience.
    public struct Destination: Codable, Sendable, Hashable {
        public let audience: ManagedAudience
        public let subjectID: String
        public let subjectType: String

        public init(audience: ManagedAudience, subjectID: String, subjectType: String) {
            self.audience = audience; self.subjectID = subjectID; self.subjectType = subjectType
        }
    }

    #if canImport(Security)
    /// The clip's credential, readable by the clip and its app only (``HandoffCredentialStore``).
    public static func credentialStore(environment: AudienceKitEnvironment, appBundleID: String) -> HandoffCredentialStore {
        let service = StaffKeychain.service(for: environment) + ".clip"
        let group = accessGroup(appBundleID: appBundleID)
        return HandoffCredentialStore(keychain: KeychainCredentialStore(service: service, accessGroup: group),
                                      file: HandoffFile(group: group, name: "\(service).session-credential"))
    }

    static func destinationSlot(environment: AudienceKitEnvironment, appBundleID: String) -> HandoffSlot {
        HandoffSlot(service: StaffKeychain.service(for: environment) + ".clip", account: "destination",
                    accessGroup: accessGroup(appBundleID: appBundleID))
    }

    /// Called by the clip once the invite is accepted.
    public static func save(_ destination: Destination, environment: AudienceKitEnvironment, appBundleID: String) {
        guard let data = try? JSONEncoder().encode(destination) else { return }
        destinationSlot(environment: environment, appBundleID: appBundleID).save(data)
    }

    /// Called by the app on launch: when its clip left a session and the app isn't signed in, the session becomes the
    /// staff apps' shared one and the audience the chosen one. Returns where to go. Either way the clip's items are
    /// deleted, so this happens once.
    public static func adopt(into credentials: any CredentialStore, audienceStore: any AudienceStore,
                             environment: AudienceKitEnvironment, appBundleID: String) -> Destination? {
        let clipStore = credentialStore(environment: environment, appBundleID: appBundleID)
        let slot = destinationSlot(environment: environment, appBundleID: appBundleID)
        guard let credential = try? clipStore.load() else { return nil }
        let destination = slot.load().flatMap { try? JSONDecoder().decode(Destination.self, from: $0) }
        defer {
            try? clipStore.delete()
            slot.delete()
        }
        if (try? credentials.load()) == nil {
            try? credentials.save(credential)
            if let destination { try? audienceStore.save(destination.audience) }
        }
        return destination
    }

    /// ``adopt(into:audienceStore:environment:appBundleID:)`` for a staff app's own stores: the shared sign-in
    /// (``StaffCredentialStore``) and chosen audience (``StaffKeychain/audienceStore(for:)``).
    public static func adoptIntoStaffApp(environment: AudienceKitEnvironment, appService: String,
                                         appBundleID: String = Bundle.main.bundleIdentifier ?? "") -> Destination? {
        adopt(into: StaffCredentialStore(environment: environment, appService: appService),
              audienceStore: StaffKeychain.audienceStore(for: environment), environment: environment,
              appBundleID: appBundleID)
    }
    #endif
}

#if canImport(Security)
/// A file in the app group container the clip shares with its app: where a handoff item goes when the keychain refuses
/// it (an access group missing from the clip's provisioning profile fails with errSecMissingEntitlement, -34018). It is
/// still the app group, so the app reads it the same way; there's no file only when the group itself isn't provisioned.
public struct HandoffFile: Sendable {
    let group: String
    let name: String

    /// `<container>/Library/Application Support/<name>`.
    var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(name)
    }

    func load() -> Data? {
        guard let url else { return nil }
        return try? Data(contentsOf: url)
    }

    @discardableResult
    func save(_ data: Data) -> Bool {
        guard let url else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: url, options: .atomic)
            #endif
            return true
        } catch {
            return false
        }
    }

    func delete() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

/// One item the clip leaves for its app in their shared app group: a keychain item, or a ``HandoffFile`` when the
/// keychain refuses it. Saving never throws: the clip's flow must not stop because the handoff couldn't be written
/// (the Backstage clip stopped right after Sign in with Apple on 2026-11-08).
public struct HandoffSlot: Sendable {
    let service: String
    let account: String
    let accessGroup: String

    var keychain: KeychainItem { KeychainItem(service: service, account: account, accessGroup: accessGroup) }
    var file: HandoffFile { HandoffFile(group: accessGroup, name: "\(service).\(account)") }

    func load() -> Data? { (try? keychain.load()) ?? file.load() }

    /// Whether the data was kept anywhere the app can read it.
    @discardableResult
    func save(_ data: Data) -> Bool {
        if (try? keychain.save(data)) != nil {
            file.delete()
            return true
        }
        return file.save(data)
    }

    func delete() {
        try? keychain.delete()
        file.delete()
    }
}

/// The clip's session: in memory for the clip's own flow, and in the app group for the app, as the keychain item the
/// clip always wrote or, when the keychain refuses it, a ``HandoffFile``. Saving never throws, so a keychain refusal
/// can't fail the sign-in it follows.
public final class HandoffCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var credential: Credential?
    let keychain: KeychainCredentialStore
    let file: HandoffFile

    init(keychain: KeychainCredentialStore, file: HandoffFile) {
        self.keychain = keychain
        self.file = file
    }

    public func load() throws -> Credential? {
        if let credential = lock.withLock({ credential }) { return credential }
        if let credential = try? keychain.load() { return credential }
        return file.load().flatMap { try? JSONDecoder().decode(Credential.self, from: $0) }
    }

    public func save(_ credential: Credential) throws {
        lock.withLock { self.credential = credential }
        if (try? keychain.save(credential)) != nil {
            file.delete()
        } else if let data = try? JSONEncoder().encode(credential) {
            file.save(data)
        }
    }

    public func delete() throws {
        lock.withLock { credential = nil }
        try? keychain.delete()
        file.delete()
    }
}
#endif
