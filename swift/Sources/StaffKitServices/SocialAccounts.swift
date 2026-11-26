import Foundation
import AudienceCore
import StaffKitCore

/// One of a listing's social accounts on a network AudienceKit can post to (Facebook, Instagram, Bluesky): a social
/// link on the listing, with whether a token that may post as it is connected. Talent and venue managers link their
/// Facebook Page, and the Instagram professional account linked to that Page, from the apps (see the API's
/// doc/SOCIAL_PUBLISHING.md); the tokens never come back.
public struct LinkedSocialAccount: Decodable, Sendable, Identifiable, Hashable {
    public let id: String
    /// facebook, instagram or bluesky.
    public let provider: String
    /// The username or Bluesky handle, without the @.
    public let handle: String
    /// The display name, as it was when connected.
    public let name: String?
    public let profileUrl: String?
    /// Whether it can be posted as.
    public let connected: Bool
    public let connectedAt: String?
    public let connectedByName: String?
    /// The network's reason the last post failed, such as a revoked token.
    public let lastError: String?

    public init(id: String, provider: String, handle: String, name: String? = nil, profileUrl: String? = nil,
                connected: Bool, connectedAt: String? = nil, connectedByName: String? = nil, lastError: String? = nil) {
        self.id = id
        self.provider = provider
        self.handle = handle
        self.name = name
        self.profileUrl = profileUrl
        self.connected = connected
        self.connectedAt = connectedAt
        self.connectedByName = connectedByName
        self.lastError = lastError
    }

    /// "@handle", or the name when there's no handle (a Facebook Page without a username shows its ID as handle).
    public var displayName: String {
        if provider == "facebook", let name, !name.isEmpty, handle.allSatisfy(\.isNumber) { return name }
        return handle.isEmpty ? (name ?? provider) : "@" + handle
    }
}

/// The networks a listing links for posting, and what each one's linked state is.
public struct LinkedSocialAccounts: Sendable, Hashable {
    public let accounts: [LinkedSocialAccount]
    public init(_ accounts: [LinkedSocialAccount]) { self.accounts = accounts }

    /// The connected account on a network, else the first one listed there.
    public func account(_ provider: String) -> LinkedSocialAccount? {
        let on = accounts.filter { $0.provider == provider }
        return on.first(where: \.connected) ?? on.first
    }
    public var facebook: LinkedSocialAccount? { account("facebook") }
    public var instagram: LinkedSocialAccount? { account("instagram") }
    public func isLinked(_ provider: String) -> Bool { account(provider)?.connected == true }

    /// After linking Facebook: why Instagram didn't come with it, when it didn't. Instagram connects only as the
    /// professional (Business or Creator) account linked to the Facebook Page, with the Page's token.
    public var instagramHint: String? {
        guard isLinked("facebook"), !isLinked("instagram") else { return nil }
        return "Instagram links through your Facebook Page. Switch your Instagram to a professional account, link it to your Page in Instagram or Meta Business Suite, then link Facebook again."
    }
}

/// Links and unlinks a listing's Facebook Page and Instagram account for posting as them, for Backstage (a person)
/// and Velvet (a venue). Linking signs in to Facebook with the platform's publishing Login for Business configuration
/// (``ManagementPlatform/facebookPublishLoginConfigurationID``) and hands the code to the API, which exchanges it with
/// the app's secret and keeps the Page token (`connectSocialFacebook`).
public struct SocialAccountsClient: Sendable {
    public enum Owner: Sendable, Hashable {
        case person(id: String)
        case venue(id: String)
        var id: String {
            switch self {
            case let .person(id), let .venue(id): id
            }
        }
    }

    public let session: AudienceManagementSession
    public init(session: AudienceManagementSession) { self.session = session }

    /// The listing's Facebook, Instagram and Bluesky accounts, linked or not. Empty for someone who doesn't manage it.
    public func accounts(of owner: Owner) async throws -> LinkedSocialAccounts {
        switch owner {
        case let .person(id):
            struct Person: Decodable, Sendable { let socialAccounts: [LinkedSocialAccount] }
            struct People: Decodable, Sendable { let person: Person? }
            struct Response: Decodable, Sendable { let people: People }
            let response = try await session.graphQL("""
                query StaffPersonSocialAccounts($id: ID!) {
                  people { person(id: $id) { socialAccounts { id provider handle name profileUrl connected connectedAt connectedByName lastError } } }
                }
                """, variables: ["id": .string(id)], as: Response.self)
            return LinkedSocialAccounts(response.people.person?.socialAccounts ?? [])
        case let .venue(id):
            struct Venue: Decodable, Sendable { let socialAccounts: [LinkedSocialAccount] }
            struct Venues: Decodable, Sendable { let venue: Venue? }
            struct Response: Decodable, Sendable { let venues: Venues }
            let response = try await session.graphQL("""
                query StaffVenueSocialAccounts($id: ID!) {
                  venues { venue(id: $id) { socialAccounts { id provider handle name profileUrl connected connectedAt connectedByName lastError } } }
                }
                """, variables: ["id": .string(id)], as: Response.self)
            return LinkedSocialAccounts(response.venues.venue?.socialAccounts ?? [])
        }
    }

    /// Links the listing's Facebook Page (its own Page by default, or `pageID`), and the Instagram account linked to
    /// it, with the code from signing in with the publishing configuration. The person must be able to create content
    /// on the Page. Returns its accounts after.
    public func linkFacebook(_ owner: Owner, code: String, redirectURI: String, facebookAppID: String,
                             pageID: String? = nil) async throws -> LinkedSocialAccounts {
        struct Payload: Decodable, Sendable { let accounts: [LinkedSocialAccount] }
        struct Response: Decodable, Sendable { let connectSocialFacebook: Payload? }
        var input: [String: GraphQLValue] = [
            "ownerId": .string(owner.id), "facebookCode": .string(code), "redirectUri": .string(redirectURI),
            "facebookAppId": .string(facebookAppID),
        ]
        if let pageID, !pageID.isEmpty { input["pageId"] = .string(pageID) }
        let response = try await session.graphQL("""
            mutation StaffConnectSocialFacebook($input: SocialFacebookConnectInput!) {
              connectSocialFacebook(input: $input) { accounts { id provider handle name profileUrl connected connectedAt connectedByName lastError } }
            }
            """, variables: ["input": .object(input)], as: Response.self)
        guard let payload = response.connectSocialFacebook else { throw AudienceKitError.decoding("The accounts were missing") }
        return LinkedSocialAccounts(payload.accounts)
    }

    /// Stops posting as one of the listing's accounts and forgets its token. The account stays on the listing's
    /// profile. Unlinking a Facebook Page doesn't unlink its Instagram account, which has its own row.
    public func unlink(_ account: LinkedSocialAccount, of owner: Owner) async throws -> LinkedSocialAccounts {
        struct Payload: Decodable, Sendable { let accounts: [LinkedSocialAccount] }
        struct Response: Decodable, Sendable { let disconnectSocialAccount: Payload? }
        let response = try await session.graphQL("""
            mutation StaffDisconnectSocialAccount($input: SocialAccountDisconnectInput!) {
              disconnectSocialAccount(input: $input) { accounts { id provider handle name profileUrl connected connectedAt connectedByName lastError } }
            }
            """, variables: ["input": .object(["ownerId": .string(owner.id), "id": .string(account.id)])], as: Response.self)
        guard let payload = response.disconnectSocialAccount else { throw AudienceKitError.decoding("The accounts were missing") }
        return LinkedSocialAccounts(payload.accounts)
    }
}
