import AudienceCore
import Foundation

// Friend matching from contacts (the API's doc/CONTACT_FRIEND_MATCHING.md). Someone proves their number with a text
// code, their phone sends one hash per contact (``ContactHashing``; names and numbers never leave the phone), and
// people who have each other saved are suggested to each other. Friends happen only through a request both agree to.

/// Where the viewer stands with someone contact matching found.
public enum ContactMatchStatus: String, Codable, Sendable {
    /// Nobody has asked yet: offer "Add".
    case none = "NONE"
    /// The viewer asked; no answer yet (a quiet "Not now" also reads as this).
    case requested = "REQUESTED"
    /// They asked the viewer: offer "Accept" and "Not now".
    case incoming = "INCOMING"
    /// Already friends.
    case friends = "FRIENDS"
}

/// A friend request between two people contact matching found.
public struct FriendRequest: Codable, Sendable, Hashable, Identifiable {
    public enum Status: String, Codable, Sendable {
        case pending = "PENDING"
        case accepted = "ACCEPTED"
        /// The person asked chose "Not now". Only they see this; the sender sees ``pending``.
        case dismissed = "DISMISSED"
        /// The sender turned contact matching off before an answer.
        case withdrawn = "WITHDRAWN"
    }

    public let id: String
    public let status: Status
    /// Who asked.
    public let user: Profile
    /// Who was asked.
    public let friend: Profile
    public let createdAt: Date?

    public init(id: String, status: Status, user: Profile, friend: Profile, createdAt: Date? = nil) {
        self.id = id
        self.status = status
        self.user = user
        self.friend = friend
        self.createdAt = createdAt
    }
}

/// Someone on the app the viewer has saved in their contacts, who has the viewer's number saved too.
public struct ContactMatch: Codable, Sendable, Hashable, Identifiable {
    /// Who they are: "First L." until friends.
    public let user: Profile
    public let status: ContactMatchStatus
    /// The request between them while one is waiting for an answer, whichever of them sent it.
    public let request: FriendRequest?
    /// Which of the hashes just sent found them. Only on the answer to a check; ``ContactMatchNames`` remembers the
    /// saved name it stands for.
    public let contactHash: String?

    public var id: String { user.id }

    public init(user: Profile, status: ContactMatchStatus, request: FriendRequest? = nil, contactHash: String? = nil) {
        self.user = user
        self.status = status
        self.request = request
        self.contactHash = contactHash
    }
}

/// The viewer's friend matching from contacts: `me.contactMatching`.
public struct ContactMatching: Codable, Sendable, Hashable {
    /// Whether matching is on: they can find people and be found. Turns on with the first check after verifying.
    public let enabled: Bool
    /// Whether they proved their number by text.
    public let phoneVerified: Bool
    /// Their verified number in E.164. Only they ever see it.
    public let phoneNumber: String?
    /// The name friends match them on.
    public let firstName: String?
    public let lastName: String?
    /// When they may ask for another text code.
    public let codeResendAt: Date?
    public let lastCheckedAt: Date?
    /// When they may check their contacts again (once a day).
    public let nextCheckAt: Date?
    /// How many contacts their last check covered.
    public let contactsChecked: Int
    /// Whether a code can be texted right now. False until the platform has a text provider: hide the offer to turn
    /// matching on. Nil from an API older than the field, which is treated as available.
    public let textCodesAvailable: Bool?
    /// Everyone found both ways, with where they stand. Empty while matching is off.
    public let matches: [ContactMatch]
    /// Requests waiting on the viewer's answer, newest first.
    public let incomingRequests: [FriendRequest]

    public init(enabled: Bool = false, phoneVerified: Bool = false, phoneNumber: String? = nil,
                firstName: String? = nil, lastName: String? = nil, codeResendAt: Date? = nil,
                lastCheckedAt: Date? = nil, nextCheckAt: Date? = nil, contactsChecked: Int = 0,
                textCodesAvailable: Bool? = nil, matches: [ContactMatch] = [], incomingRequests: [FriendRequest] = [])
    {
        self.enabled = enabled
        self.phoneVerified = phoneVerified
        self.phoneNumber = phoneNumber
        self.firstName = firstName
        self.lastName = lastName
        self.codeResendAt = codeResendAt
        self.lastCheckedAt = lastCheckedAt
        self.nextCheckAt = nextCheckAt
        self.contactsChecked = contactsChecked
        self.textCodesAvailable = textCodesAvailable
        self.matches = matches
        self.incomingRequests = incomingRequests
    }

    /// Whether to offer "Find friends from your contacts": not on yet, and a code could be texted.
    public var canOffer: Bool { !enabled && textCodesAvailable != false }

    /// Whether a check would be let through now (one a day).
    public func canCheck(now: Date = Date()) -> Bool {
        guard phoneVerified else { return false }
        return nextCheckAt.map { $0 <= now } ?? true
    }

    /// How many matches still show "Add".
    public var addable: [ContactMatch] { matches.filter { $0.status == .none } }
}

/// The answer to a check: the state after it and everyone found, each with the hash that found them.
public struct ContactCheckResult: Sendable, Hashable {
    public let contactMatching: ContactMatching
    public let matches: [ContactMatch]

    public init(contactMatching: ContactMatching, matches: [ContactMatch]) {
        self.contactMatching = contactMatching
        self.matches = matches
    }
}

/// The names the person saved their matches under, kept on the phone only and never sent, so a match can read
/// "In your contacts as Jordan Park". The API can't say: it never learns a name from anyone's contacts.
///
/// Kept in `UserDefaults` (never iCloud), per audience. ``removeAll()`` when matching is turned off or on sign-out.
public final class ContactMatchNames: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()

    public init(audienceID: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.key = "AudienceKit.contactMatchNames.\(audienceID)"
    }

    /// The name the person has `userID` saved under, when a check on this phone found them.
    public func name(for userID: String) -> String? {
        lock.withLock { all()[userID] }
    }

    /// Remembers the saved name of everyone a check just found, from the batch that was sent. Names for people who
    /// no longer match are dropped.
    public func record(_ matches: [ContactMatch], from batch: ContactHashBatch) {
        lock.withLock {
            var names = all().filter { entry in matches.contains { $0.user.id == entry.key } }
            for match in matches {
                if let hash = match.contactHash, let name = batch.names[hash] { names[match.user.id] = name }
            }
            defaults.set(names, forKey: key)
        }
    }

    public func removeAll() {
        lock.withLock { defaults.removeObject(forKey: key) }
    }

    private func all() -> [String: String] {
        (defaults.dictionary(forKey: key) as? [String: String]) ?? [:]
    }
}

/// The words the apps use for contact matching, so iOS and Android say the same thing (`ContactMatchingCopy` on
/// Android too). Never "upload", "sync" or "hash" in front of people: a hash is a "scrambled code".
public enum ContactMatchingCopy {
    public static let title = "Find friends from your contacts"
    public static let cardBody = "Friends who turn this on too will show up here. We never keep your contacts or text anyone in them."
    public static let findFriends = "Find friends"
    public static let notNow = "Not now"
    public static let checking = "Checking your contacts"
    public static let onlyCodesLeave = "Only scrambled codes leave your phone."
    public static let numberPrivate = "Your number is never shown on your profile, and nobody can search for you by it."
    public static let ratesMayApply = "Message and data rates may apply."
    public static let noFriendsYet = "No friends here yet"
    public static let noFriendsBody = "None of the people in your contacts have turned this on yet. When someone who has your number does, you'll both see each other."
    public static let notNowIsQuiet = "Not now hides it quietly. They aren't told."

    /// "4 friends are here" / "1 friend is here".
    public static func friendsHere(_ count: Int) -> String {
        count == 1 ? "1 friend is here" : "\(count) friends are here"
    }

    /// "Add 2 friends" / "Add 1 friend".
    public static func addFriends(_ count: Int) -> String {
        count == 1 ? "Add 1 friend" : "Add \(count) friends"
    }

    /// "In your contacts as Jordan Park".
    public static func savedAs(_ name: String) -> String { "In your contacts as \(name)" }

    /// "We checked 457 contacts and skipped 61 with only a first name."
    public static func checked(_ batch: ContactHashBatch) -> String {
        let checked = "We checked \(batch.contactCount) \(batch.contactCount == 1 ? "contact" : "contacts")"
        guard batch.skippedWithoutFullName > 0 else { return checked + "." }
        return checked + " and skipped \(batch.skippedWithoutFullName) with only a first name."
    }
}

extension Queries {
    static func contactMatchingFields(_ shape: SchemaShape, checking: Bool = false) -> String {
        let available = shape.has("ContactMatching", "textCodesAvailable") ? "textCodesAvailable" : ""
        return """
        enabled phoneVerified phoneNumber firstName lastName codeResendAt lastCheckedAt nextCheckAt contactsChecked
        \(available)
        matches { \(contactMatchFields(shape, checking: false)) }
        incomingRequests { \(friendRequestFields) }
        """
    }

    static func contactMatchFields(_ shape: SchemaShape, checking: Bool) -> String {
        let hash = checking && shape.has("ContactMatch", "contactHash") ? "contactHash" : ""
        return "status \(hash) user { id name avatarUrl } request { \(friendRequestFields) }"
    }

    static let friendRequestFields = "id status createdAt user { id name avatarUrl } friend { id name avatarUrl }"

    static func contactMatching(_ shape: SchemaShape) -> String {
        "query ContactMatching { me { contactMatching { \(contactMatchingFields(shape)) } } }"
    }

    static func startContactPhoneVerification(_ shape: SchemaShape) -> String {
        """
        mutation StartContactPhoneVerification($phoneNumber: String!, $firstName: String!, $lastName: String!) {
          startContactPhoneVerification(input: { phoneNumber: $phoneNumber, firstName: $firstName,
                                                 lastName: $lastName }) {
            contactMatching { \(contactMatchingFields(shape)) }
          }
        }
        """
    }

    static func verifyContactPhone(_ shape: SchemaShape) -> String {
        """
        mutation VerifyContactPhone($code: String!) {
          verifyContactPhone(input: { code: $code }) { contactMatching { \(contactMatchingFields(shape)) } }
        }
        """
    }

    static func checkContacts(_ shape: SchemaShape) -> String {
        """
        mutation CheckContacts($hashes: [String!]!, $contactCount: Int!) {
          checkContacts(input: { hashes: $hashes, contactCount: $contactCount }) {
            matches { \(contactMatchFields(shape, checking: true)) }
            contactMatching { \(contactMatchingFields(shape)) }
          }
        }
        """
    }

    static func setContactMatchName(_ shape: SchemaShape) -> String {
        """
        mutation SetContactMatchName($firstName: String!, $lastName: String!) {
          setContactMatchName(input: { firstName: $firstName, lastName: $lastName }) {
            contactMatching { \(contactMatchingFields(shape)) }
          }
        }
        """
    }

    static func disableContactMatching(_ shape: SchemaShape) -> String {
        """
        mutation DisableContactMatching {
          disableContactMatching(input: {}) { contactMatching { \(contactMatchingFields(shape)) } }
        }
        """
    }

    static func sendFriendRequest(_ shape: SchemaShape) -> String {
        """
        mutation SendFriendRequest($userId: ID!) {
          sendFriendRequest(input: { userId: $userId }) { contactMatching { \(contactMatchingFields(shape)) } }
        }
        """
    }

    static func respondToFriendRequest(_ shape: SchemaShape) -> String {
        """
        mutation RespondToFriendRequest($requestId: ID!, $accept: Boolean!) {
          respondToFriendRequest(input: { requestId: $requestId, accept: $accept }) {
            contactMatching { \(contactMatchingFields(shape)) }
          }
        }
        """
    }
}

struct ContactMatchingResponse: Decodable, Sendable {
    struct Me: Decodable, Sendable { var contactMatching: ContactMatching? }
    struct Payload: Decodable, Sendable {
        var contactMatching: ContactMatching?
        var matches: [ContactMatch]?
    }

    var me: Me?
    var startContactPhoneVerification: Payload?
    var verifyContactPhone: Payload?
    var checkContacts: Payload?
    var setContactMatchName: Payload?
    var disableContactMatching: Payload?
    var sendFriendRequest: Payload?
    var respondToFriendRequest: Payload?

    var payload: Payload? {
        startContactPhoneVerification ?? verifyContactPhone ?? checkContacts ?? setContactMatchName
            ?? disableContactMatching ?? sendFriendRequest ?? respondToFriendRequest
    }
}

/// The API answered a contact matching call without its state: the audience doesn't have matching.
public struct ContactMatchingUnavailable: Error, Sendable {}

extension AudienceSession {
    private static var contactTypes: [String] { ["ContactMatching", "ContactMatch"] }

    private func contactMutation(_ operationName: String, variables: [String: GraphQLValue]? = nil,
                                 document: (SchemaShape) -> String) async throws -> ContactMatchingResponse.Payload
    {
        let response = try await graphQL(types: Self.contactTypes, variables: variables,
                                         operationName: operationName, as: ContactMatchingResponse.self,
                                         document: document)
        guard let payload = response.payload, payload.contactMatching != nil else {
            throw ContactMatchingUnavailable()
        }
        return payload
    }

    /// The signed-in person's contact matching: whether it's on, their number and match name, their matches and the
    /// requests waiting on them.
    public func contactMatching() async throws -> ContactMatching {
        let response = try await graphQL(types: Self.contactTypes, operationName: "ContactMatching",
                                         as: ContactMatchingResponse.self, document: Queries.contactMatching)
        guard let state = response.me?.contactMatching else { throw ContactMatchingUnavailable() }
        return state
    }

    /// Saves the name friends match the person on and texts a six-digit code to `phoneNumber` (E.164, from
    /// ``ContactHashing/e164(_:region:)``). Up to five codes a day, 30 seconds apart.
    @discardableResult
    public func startContactPhoneVerification(phoneNumber: String, firstName: String,
                                              lastName: String) async throws -> ContactMatching
    {
        let variables: [String: GraphQLValue] = [
            "phoneNumber": .string(phoneNumber), "firstName": .string(firstName), "lastName": .string(lastName),
        ]
        return try await contactMutation("StartContactPhoneVerification", variables: variables,
                                         document: Queries.startContactPhoneVerification).contactMatching!
    }

    /// Proves the number with the code from the text. Matching is still off until the first check.
    @discardableResult
    public func verifyContactPhone(code: String) async throws -> ContactMatching {
        try await contactMutation("VerifyContactPhone", variables: ["code": .string(code)],
                                  document: Queries.verifyContactPhone).contactMatching!
    }

    /// Sends a batch of contact hashes (``ContactHashing/batch(_:region:limit:)``), which turns matching on and
    /// replaces the last check. Once a day. Pass `names` to remember, on the phone, what each match is saved as.
    public func checkContacts(_ batch: ContactHashBatch, names: ContactMatchNames? = nil) async throws -> ContactCheckResult {
        let variables: [String: GraphQLValue] = [
            "hashes": .array(batch.hashes.map { .string($0) }), "contactCount": .int(batch.contactCount),
        ]
        let payload = try await contactMutation("CheckContacts", variables: variables,
                                                document: Queries.checkContacts)
        let matches = payload.matches ?? []
        names?.record(matches, from: batch)
        return ContactCheckResult(contactMatching: payload.contactMatching!, matches: matches)
    }

    /// Changes the name friends match the person on.
    @discardableResult
    public func setContactMatchName(firstName: String, lastName: String) async throws -> ContactMatching {
        try await contactMutation("SetContactMatchName",
                                  variables: ["firstName": .string(firstName), "lastName": .string(lastName)],
                                  document: Queries.setContactMatchName).contactMatching!
    }

    /// Turns matching off: the API deletes their number, match name and every code, and withdraws requests nobody
    /// answered. Friends already made stay. Pass `names` to forget the saved names on the phone too.
    @discardableResult
    public func disableContactMatching(names: ContactMatchNames? = nil) async throws -> ContactMatching {
        let state = try await contactMutation("DisableContactMatching",
                                              document: Queries.disableContactMatching).contactMatching!
        names?.removeAll()
        return state
    }

    /// Asks a match to be friends. If they had already asked, their request is accepted.
    @discardableResult
    public func sendFriendRequest(userID: String) async throws -> ContactMatching {
        try await contactMutation("SendFriendRequest", variables: ["userId": .string(userID)],
                                  document: Queries.sendFriendRequest).contactMatching!
    }

    /// Answers a request: accept it, or "Not now", which hides it without telling the sender.
    @discardableResult
    public func respondToFriendRequest(id: String, accept: Bool) async throws -> ContactMatching {
        try await contactMutation("RespondToFriendRequest",
                                  variables: ["requestId": .string(id), "accept": .bool(accept)],
                                  document: Queries.respondToFriendRequest).contactMatching!
    }
}
