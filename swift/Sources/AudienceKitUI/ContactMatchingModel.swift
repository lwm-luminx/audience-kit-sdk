#if canImport(SwiftUI) && canImport(Contacts)
import AudienceCore
import AudienceKit
import Foundation
import SwiftUI

/// The state behind the find-friends screens (``FindFriendsCard``, ``FindFriendsFlow``, ``FriendRequestCards``,
/// ``ContactMatchingSettings``): the person's contact matching as the API has it, and the calls that change it.
/// An app keeps one for the signed-in person and hands it to each view.
///
/// ```swift
/// @StateObject private var friends = ContactMatchingModel(client: client, audienceID: audienceID)
/// ```
@MainActor
public final class ContactMatchingModel: ObservableObject {
    /// The person's contact matching; nil until ``load()`` has answered, or when the audience doesn't have it.
    @Published public private(set) var state: ContactMatching?
    /// What the last check on this phone sent, for "We checked 457 contacts and skipped 61".
    @Published public private(set) var lastBatch: ContactHashBatch?
    /// Whether a call is in flight.
    @Published public private(set) var working = false
    /// Why the last call failed, in the API's words.
    @Published public var error: String?
    /// Whether the person refused the contacts prompt: only Settings can change it.
    @Published public private(set) var contactsDenied = false
    /// Whether "Not now" on the card is still in force (30 days).
    @Published public private(set) var cardHidden: Bool

    public let client: AudienceKitClient
    /// What each match is saved as, on this phone only.
    public let names: ContactMatchNames
    /// The phone's region, for numbers saved without a country code.
    public let region: String?

    private let defaults: UserDefaults
    private let hiddenKey: String
    private let requestAccess: @Sendable () async -> Bool
    private let readContacts: @Sendable () async throws -> [DeviceContact]

    /// How long "Not now" hides the card.
    public static let cardHiddenFor: TimeInterval = 30 * 24 * 60 * 60

    /// - Parameters:
    ///   - requestAccess, readContacts: how contacts are read; the phone's own contacts unless a test passes others.
    public init(client: AudienceKitClient, audienceID: String, defaults: UserDefaults = .standard,
                region: String? = ContactsReader.region,
                requestAccess: @escaping @Sendable () async -> Bool = { await ContactsReader.requestAccess() },
                readContacts: @escaping @Sendable () async throws -> [DeviceContact] = { try await ContactsReader.read() })
    {
        self.client = client
        self.names = ContactMatchNames(audienceID: audienceID, defaults: defaults)
        self.region = region
        self.defaults = defaults
        self.hiddenKey = "AudienceKit.contactMatching.cardHiddenUntil.\(audienceID)"
        self.requestAccess = requestAccess
        self.readContacts = readContacts
        self.cardHidden = defaults.double(forKey: hiddenKey) > Date().timeIntervalSince1970
    }

    /// Whether to show ``FindFriendsCard``: matching is off, a code can be texted, and the card isn't hidden.
    public var offersCard: Bool { state?.canOffer == true && !cardHidden }

    /// The requests waiting on the person's answer.
    public var incomingRequests: [FriendRequest] { state?.incomingRequests ?? [] }

    /// The name the person saved a match under, when a check on this phone found them.
    public func savedName(for userID: String) -> String? { names.name(for: userID) }

    /// Reads the person's contact matching. Quietly leaves ``state`` nil when the audience doesn't have it.
    public func load() async {
        if let loaded = try? await client.contactMatching() { state = loaded }
    }

    /// "Not now" on the card: hides it for ``cardHiddenFor``.
    public func hideCard() {
        defaults.set(Date().addingTimeInterval(Self.cardHiddenFor).timeIntervalSince1970, forKey: hiddenKey)
        cardHidden = true
    }

    /// Texts a code to `number` (as typed, in `region`'s format or with a "+") and saves the match name.
    @discardableResult
    public func start(number: String, region: String?, firstName: String, lastName: String) async -> Bool {
        guard let phone = ContactHashing.e164(number, region: region) else {
            error = "Enter your mobile number with its area code."
            return false
        }
        return await run { try await self.client.startContactPhoneVerification(phoneNumber: phone, firstName: firstName,
                                                                              lastName: lastName) }
    }

    /// Proves the number with the code from the text.
    @discardableResult
    public func verify(code: String) async -> Bool {
        await run { try await self.client.verifyContactPhone(code: code) }
    }

    /// Asks for contacts if needed, turns them into scrambled codes on the phone and checks them. False when the
    /// person refused contacts (``contactsDenied``) or the API refused the check (``error``).
    @discardableResult
    public func checkContacts() async -> Bool {
        guard await requestAccess() else {
            contactsDenied = true
            return false
        }
        contactsDenied = false
        working = true
        defer { working = false }
        do {
            let contacts = try await readContacts()
            let region = region
            let batch = await Task.detached(priority: .userInitiated) {
                ContactHashing.batch(contacts, region: region)
            }.value
            let result = try await client.checkContacts(batch, names: names)
            lastBatch = batch
            state = result.contactMatching
            error = nil
            return true
        } catch {
            self.error = Self.message(error)
            return false
        }
    }

    /// "Add": asks a match to be friends.
    @discardableResult
    public func add(_ match: ContactMatch) async -> Bool {
        await run { try await self.client.sendFriendRequest(userID: match.user.id) }
    }

    /// "Add N friends": asks everyone still showing "Add".
    public func addAll() async {
        for match in state?.addable ?? [] {
            guard await add(match) else { return }
        }
    }

    /// "Accept" or "Not now" on a request.
    @discardableResult
    public func respond(to request: FriendRequest, accept: Bool) async -> Bool {
        await run { try await self.client.respondToFriendRequest(id: request.id, accept: accept) }
    }

    /// Changes the name friends match the person on.
    @discardableResult
    public func setName(firstName: String, lastName: String) async -> Bool {
        await run { try await self.client.setContactMatchName(firstName: firstName, lastName: lastName) }
    }

    /// "Turn off and delete": the API deletes the number and every code; the phone forgets the saved names.
    @discardableResult
    public func turnOff() async -> Bool {
        let done = await run { try await self.client.disableContactMatching(names: self.names) }
        if done { lastBatch = nil }
        return done
    }

    private func run(_ call: @escaping () async throws -> ContactMatching) async -> Bool {
        working = true
        defer { working = false }
        do {
            state = try await call()
            error = nil
            return true
        } catch {
            self.error = Self.message(error)
            return false
        }
    }

    static func message(_ error: Error) -> String {
        if let error = error as? AudienceKitError { return error.message }
        if error is ContactMatchingUnavailable { return "Finding friends from contacts isn't available here yet." }
        return error.localizedDescription
    }
}
#endif
