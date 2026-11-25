import AudienceCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ManagedAudience: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let subdomain: String

    public init(id: String, name: String, subdomain: String) {
        self.id = id; self.name = name; self.subdomain = subdomain
    }

    /// The Velvet Demo sandbox, where each person's own demo venue is (``DemoVenue``).
    public var isDemo: Bool { subdomain == DemoVenue.audienceSubdomain }
}

public struct ManagementChoice: Decodable, Sendable {
    public let kind: String
    public let allowed: Bool
    public let audience: ManagedAudience?
    public let listing: [String]?
    /// Set on the sandbox the person's own demo venue is in.
    public let demo: Bool?
}

/// A demo venue of the person's own, to try Velvet with before any audience invites them (`/v1/admin/demo`): in the
/// Velvet Demo sandbox, with sample nights from tonight, which nothing in Hot Mess or a real audience sees.
public struct DemoVenue: Decodable, Sendable, Hashable {
    public static let audienceSubdomain = "velvet-demo"

    public struct Venue: Decodable, Sendable, Hashable {
        public let id: String
        public let name: String
        public let locale: String?
    }
    /// The sandbox; ``AudienceManagementSession/choose(_:)`` opens it like any audience.
    public let audience: ManagedAudience
    /// Their demo venue, nil until they start one.
    public let venue: Venue?
}

/// The API stopped serving this build's SDK (HTTP 426), so the app has to be updated before it can go on.
public struct UpdateRequirement: Sendable, Hashable {
    /// The oldest SDK version the API accepts; empty when it didn't say.
    public let minimumSDKVersion: String
    /// The API's message for the person, if it sent one.
    public let message: String?

    public init(minimumSDKVersion: String, message: String? = nil) {
        self.minimumSDKVersion = minimumSDKVersion
        self.message = message
    }
}

/// Shared management session for Focus, Velvet, and Backstage. The API remains the authority on access.
///
/// The session keeps the ``Credential`` the API issues (the token JSON every sign-in and `POST /v1/admin/choices`
/// answer with) in a ``CredentialStore``; nothing decodes the JWT. Failures are ``AudienceKitError`` values, told
/// apart by their ``AudienceKitError/code``.
public actor AudienceManagementSession {
    private nonisolated let configuration: AudienceKitConfiguration
    /// The API this session talks to.
    public nonisolated var baseURL: URL { configuration.baseURL }
    private let credentialStore: any CredentialStore
    /// Where the chosen audience is remembered beside the credential; nil to forget it between launches.
    private let audienceStore: (any AudienceStore)?
    private let session: URLSession
    private var client: AudienceSession
    private var liveCable: AudienceCable?

    /// Yields whenever a call finds this SDK too old (``AudienceKitError/Code/updateRequired``), wherever the call
    /// was made, so the app can block on an update screen. Iterate it from one place.
    public nonisolated let updatesRequired: AsyncStream<UpdateRequirement>
    private nonisolated let updateContinuation: AsyncStream<UpdateRequirement>.Continuation

    /// Yields once each time the API refuses the session (HTTP 401 on a signed-in call, or the cable closed as
    /// `unauthorized`), wherever the call was made: an expired or revoked token, or one issued for another endpoint.
    /// The credential and chosen audience are already forgotten; the app goes back to sign-in, saying to sign in
    /// again. A 403 (no staff role) or a network failure isn't a session ending. Iterate it from one place.
    public nonisolated let sessionsEnded: AsyncStream<Void>
    private nonisolated let sessionEndContinuation: AsyncStream<Void>.Continuation
    /// The last token reported on ``sessionsEnded``, so the calls and sockets it refused report it once.
    private var endedToken: String?

    /// Signs in to the environment's ``ManagementPlatform``; tests can point `baseURL` elsewhere.
    ///
    /// Give the staff apps a ``StaffCredentialStore`` and ``StaffKeychain/audienceStore(for:)`` so one sign-in, and
    /// one chosen audience, serves Focus, Velvet and Backstage together.
    public init(baseURL: URL? = nil, environment: AudienceKitEnvironment = .production,
                credentialStore: any CredentialStore = InMemoryCredentialStore(),
                audienceStore: (any AudienceStore)? = nil, session: URLSession = .shared) {
        let platform = ManagementPlatform.for(environment)
        let configuration = AudienceKitConfiguration(baseURL: baseURL ?? platform.baseURL, host: platform.host,
                                                       facebookAppID: platform.facebookAppID, environment: environment,
                                                       trustedCredentialOrigins: platform.trustedCredentialOrigins)
        self.configuration = configuration
        self.credentialStore = credentialStore
        self.audienceStore = audienceStore
        self.session = session
        client = AudienceSession(configuration: configuration, credentialStore: credentialStore, session: session)
        (updatesRequired, updateContinuation) = AsyncStream<UpdateRequirement>.makeStream(bufferingPolicy: .bufferingNewest(1))
        (sessionsEnded, sessionEndContinuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    deinit {
        updateContinuation.finish()
        sessionEndContinuation.finish()
    }

    /// The stored credential, if any.
    private var storedCredential: Credential? { try? credentialStore.load() }

    /// Runs a call, reporting an ``AudienceKitError/Code/updateRequired`` failure on ``updatesRequired`` before
    /// rethrowing it, and a refused session on ``sessionsEnded``.
    ///
    /// The SDK forgets the credential when the API answers a signed-in call with 401, so a 401 that leaves no
    /// credential behind is the session ending; a refused sign-in or review code (401 on a call made without the
    /// token) leaves it. `reportsSessionEnd` is false for signing out, where a session that's already gone is what
    /// was asked for.
    private func observing<T: Sendable>(reportsSessionEnd: Bool = true, _ call: () async throws -> T) async throws -> T {
        let token = storedCredential?.token
        do { return try await call() }
        catch let error as AudienceKitError {
            switch error.code {
            case AudienceKitError.Code.updateRequired:
                updateContinuation.yield(UpdateRequirement(minimumSDKVersion: error.minimumSDKVersion ?? "",
                                                           message: error.message))
            case AudienceKitError.Code.unauthenticated:
                if reportsSessionEnd, let token, storedCredential == nil { await sessionEnded(token: token) }
            default:
                break
            }
            throw error
        }
    }

    /// The API refused `token` on a connection the SDK doesn't make itself: the ``cable()`` closed as `unauthorized`,
    /// or an SSE stream answered 401. Forgets the session and reports it on ``sessionsEnded``, unless the store no
    /// longer holds `token` (it already ended, or someone signed in again since).
    public func sessionRejected(token: String?) async {
        guard let token, storedCredential?.token == token else { return }
        await client.sessionRejected(token: token)
        await sessionEnded(token: token)
    }

    /// Forgets what's left of a refused session (the chosen audience, the cable) and tells the app, once per token.
    private func sessionEnded(token: String) async {
        guard endedToken != token else { return }
        endedToken = token
        try? audienceStore?.delete()
        await liveCable?.disconnect()
        sessionEndContinuation.yield()
    }

    /// Asks `/v1/status` for the oldest SDK the API accepts (`api.sdk.ios.minimumVersion`) and reports on
    /// ``updatesRequired`` when this one is older, so a signed-out app can ask for the update before anything fails.
    /// Nil when this SDK is fine or the check failed.
    @discardableResult
    public func checkForRequiredUpdate() async -> UpdateRequirement? {
        struct Status: Decodable {
            struct API: Decodable {
                struct SDK: Decodable {
                    struct Platform: Decodable { let minimumVersion: String? }
                    let ios: Platform?
                }
                let version: String?
                let sdk: SDK?
            }
            let api: API?
        }
        do {
            let data = try await observing { try await client.data(for: APIRequest(path: "/v1/status", authenticated: false)) }
            guard let minimum = try JSONDecoder().decode(Status.self, from: data).api?.sdk?.ios?.minimumVersion,
                  AudienceKitSDK.isOlder(than: minimum) else { return nil }
            let requirement = UpdateRequirement(minimumSDKVersion: minimum)
            updateContinuation.yield(requirement)
            return requirement
        } catch let error as AudienceKitError where error.code == AudienceKitError.Code.updateRequired {
            return UpdateRequirement(minimumSDKVersion: error.minimumSDKVersion ?? "", message: error.message)
        } catch { return nil }
    }

    public var isSignedIn: Bool { get async { await client.isSignedIn } }

    /// The cable this session's GraphQL subscriptions ride on (the door, chat rooms): one socket to the API, opened by
    /// the first subscription and signed with whatever credential the store holds when it opens.
    public func cable() -> AudienceCable {
        if let liveCable { return liveCable }
        let store = credentialStore
        let cable = AudienceCable(configuration: configuration, endpoint: .staff,
                                  url: AudienceCable.url(for: configuration.baseURL), session: session,
                                  credential: { try? store.load() },
                                  unauthorized: { [weak self] token in
                                      guard let self else { return }
                                      Task { await self.sessionRejected(token: token) }
                                  })
        liveCable = cable
        return cable
    }

    /// The audience the session's operations run in: the one chosen, restored or bound to the device, else the one
    /// its credential was signed in on.
    public var operatingAudienceID: String? {
        if let boundAudienceID { return boundAudienceID }
        return storedCredential?.audienceId
    }

    /// Runs a GraphQL subscription over the ``cable()`` in the session's audience. Without an audience there's
    /// nothing to follow, and the stream says ``AudienceCable/Event/rejected`` and ends.
    public func subscribe(_ query: String, variables: [String: GraphQLValue] = [:],
                          operationName: String? = nil) async -> AsyncStream<AudienceCable.Event> {
        guard let audienceID = operatingAudienceID else {
            return AsyncStream { $0.yield(.rejected); $0.finish() }
        }
        return await cable().subscribe(query: query, variables: variables, operationName: operationName,
                                       audienceID: audienceID)
    }

    public func signIn(accessToken: String, device: DeviceDescription) async throws {
        try await observing {
            try await retryingLostConnection { try await client.signIn(facebookAccessToken: accessToken, device: device) }
        }
    }

    /// Signs in with a session the API already issued (a sign-in's `token` answer, or its bare JWT read into a
    /// ``Credential``), for tools like `arbiterctl sign-in` that hand a running app a token instead of going through a
    /// sign-in sheet. The credential is stored as if this device had signed in; the caller checks it works (by fetching
    /// ``choices(everyAudience:)``, say) and signs out again when it doesn't.
    public func signIn(credential: Credential) async throws {
        try await observing { try await client.adopt(credential: credential) }
    }

    public func signIn(code: String, redirectURI: String, device: DeviceDescription) async throws {
        try await observing {
            try await retryingLostConnection {
                try await client.signIn(facebookCode: code, redirectURI: redirectURI, device: device)
            }
        }
    }

    /// Signs in with Apple (`POST /v1/token/apple`) on the platform, like a Facebook sign-in: the API checks the identity
    /// token and, when Apple's verified email is the one on an account that signed in with Facebook, signs in to that
    /// account, so ``choices()`` lists its audiences. Otherwise the account is new and has none until someone invites it
    /// or it connects Facebook (``connectFacebook(code:redirectURI:device:)``).
    public func signIn(appleIdentityToken: String, firstName: String? = nil, lastName: String? = nil,
                       device: DeviceDescription) async throws {
        try await observing {
            _ = try await client.signIn(appleIdentityToken: appleIdentityToken, firstName: firstName, lastName: lastName,
                                        device: device)
        }
    }

    /// Signs in with Apple through a browser (`POST /v1/token/apple` with `nonce`), for builds that can't carry the
    /// Sign in with Apple entitlement: a Developer ID Mac app (Apple grants it only to App Store and development
    /// builds). The identity token is for a Services ID and came back through the browser, so the API accepts it only
    /// with `nonce`, the value whose SHA-256 the sign-in gave Apple, which never left the app. `redirectURI` is the
    /// return URL the sign-in named, which Apple needs again to exchange `authorizationCode` (kept to revoke the
    /// person's tokens if they delete their account). The account is found as for the native sign-in.
    public func signIn(appleIdentityToken: String, nonce: String, authorizationCode: String? = nil,
                       redirectURI: String? = nil, firstName: String? = nil, lastName: String? = nil,
                       device: DeviceDescription) async throws {
        struct Body: Encodable {
            let identity_token: String
            let nonce: String
            let authorization_code: String?
            let redirect_uri: String?
            let first_name: String?
            let last_name: String?
            let host: String?
            let device: DeviceDescription
        }
        let body = try JSONEncoder().encode(Body(
            identity_token: appleIdentityToken, nonce: nonce, authorization_code: authorizationCode,
            redirect_uri: redirectURI, first_name: firstName, last_name: lastName, host: configuration.host,
            device: device))
        try await observing {
            let data = try await client.data(for: APIRequest(method: "POST", path: "/v1/token/apple", body: body,
                                                             authenticated: false))
            let credential = try JSONDecoder.audienceKit.decode(Credential.self, from: data)
            try await client.adopt(credential: credential)
        }
    }

    /// Connects Facebook to the signed-in account (one that signed in with Apple), with the code from
    /// ``FacebookSignIn``, so the Pages that Facebook account manages decide its audiences. When the Facebook profile
    /// already has an account, that account takes over the Apple sign-in and the session switches to it.
    public func connectFacebook(code: String, redirectURI: String, device: DeviceDescription) async throws {
        try await observing {
            try await retryingLostConnection {
                try await client.connectFacebook(code: code, redirectURI: redirectURI, device: device)
            }
        }
    }

    /// Signs in with Instagram (`POST /v1/token/instagram`) on the platform, with the ticket and verifier from
    /// ``InstagramSignIn``, for Instagram Business and Creator accounts. Instagram shares no email, so a new Instagram
    /// account is a new account; either way, the listings that name that Instagram account and that nobody manages yet
    /// become its own, so ``choices()`` lists their audiences.
    public func signIn(instagramTicket ticket: String, verifier: String, device: DeviceDescription) async throws {
        try await instagram(ticket: ticket, verifier: verifier, device: device, connect: false)
    }

    /// Connects Instagram to the signed-in account, which then claims the listings that name that Instagram account
    /// and that nobody manages yet. When the Instagram account already has an account, the two become one and the
    /// session can switch to it, as with ``connectFacebook(code:redirectURI:device:)``.
    public func connectInstagram(ticket: String, verifier: String, device: DeviceDescription) async throws {
        try await instagram(ticket: ticket, verifier: verifier, device: device, connect: true)
    }

    private func instagram(ticket: String, verifier: String, device: DeviceDescription, connect: Bool) async throws {
        struct Body: Encodable {
            let ticket: String; let verifier: String; let host: String?; let device: DeviceDescription; let connect: Bool
        }
        let body = try JSONEncoder().encode(Body(ticket: ticket, verifier: verifier, host: configuration.host,
                                                 device: device, connect: connect))
        let data = try await observing(reportsSessionEnd: !connect) {
            try await client.data(for: APIRequest(method: "POST", path: "/v1/token/instagram", body: body,
                                                  authenticated: connect))
        }
        try await client.adopt(credential: Self.credential(from: data))
    }

    /// Sign-in follows a switch back from Facebook, when iOS may have dropped the connection the request reuses. That
    /// fails before the request leaves, so the token or one-time code is still unused and one retry is safe.
    private func retryingLostConnection(_ signIn: () async throws -> SignInResult) async throws {
        do {
            _ = try await signIn()
        } catch let error as AudienceKitError where error.code == AudienceKitError.Code.network
            && error.underlying?.code == .networkConnectionLost {
            _ = try await signIn()
        }
    }

    /// Signs App Review in with the demo audience's fixed code (`POST /v1/admin/review_login`), as that audience's
    /// staff. The session is a platform session like a Facebook sign-in's, so ``choices()`` and ``choose(_:)`` follow.
    /// Sends the install's signed AppTransaction (`app_transaction`), so the API refuses the code in a copy from the
    /// App Store (403, reason `store_install`).
    public func signIn(reviewCode: String, device: DeviceDescription, appTransaction: String? = nil) async throws {
        struct Body: Encodable {
            let code: String
            let device: DeviceDescription
            let appTransaction: String?
            enum CodingKeys: String, CodingKey {
                case code, device
                case appTransaction = "app_transaction"
            }
        }
        let signed: String?
        if let appTransaction { signed = appTransaction } else { signed = await ReviewInstall.signedAppTransaction() }
        let body = try JSONEncoder().encode(Body(code: reviewCode, device: device, appTransaction: signed))
        let data: Data
        do {
            data = try await observing {
                try await client.data(for: APIRequest(method: "POST", path: "/v1/admin/review_login", body: body,
                                                      authenticated: false))
            }
        } catch let error as AudienceKitError where error.code == AudienceKitError.Code.unauthenticated {
            throw AudienceKitError.signInFailed(message: "That App Review code isn’t valid or has expired.")
        }
        try await client.adopt(credential: Self.credential(from: data))
    }

    /// Whether the apps should offer the App Review code: never in a copy installed from the App Store, and otherwise
    /// only while App Review is on for the demo audience. App Review runs the build in StoreKit's sandbox, like
    /// TestFlight, so reviewers still get it. A slow or failed first request (a cold server, a flaky network) is tried
    /// twice more before it counts as off, since a missing link leaves App Review no way to sign in.
    ///
    /// - Parameter installSource: where this copy came from; StoreKit's `AppTransaction` (``InstallSource/current``)
    ///   by default.
    public func reviewCodeAvailable(installSource: InstallSource? = nil) async -> Bool {
        let source: InstallSource
        if let installSource { source = installSource } else { source = await InstallSource.current }
        guard source != .appStore else { return false }
        struct Status: Decodable { let enabled: Bool }
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(attempt)) }
            do {
                let data = try await observing {
                    try await client.data(for: APIRequest(path: "/v1/admin/review_login", authenticated: false))
                }
                return try JSONDecoder().decode(Status.self, from: data).enabled
            } catch { continue }
        }
        return false
    }

    /// Their demo venue, if they have started one (`GET /v1/admin/demo`); nil when this API has no demo venues.
    public func demoVenue() async -> DemoVenue? {
        guard let data = try? await observing({ try await client.data(for: APIRequest(path: "/v1/admin/demo")) })
        else { return nil }
        return try? Self.decode(DemoVenue.self, from: data)
    }

    /// Makes their demo venue with sample nights the first time, or opens the one they have; `reset` puts fresh sample
    /// nights on it from tonight (`POST /v1/admin/demo`). Then ``choose(_:)`` the returned audience to work it.
    public func startDemoVenue(reset: Bool = false) async throws -> DemoVenue {
        struct Body: Encodable { let reset: Bool }
        let body = try JSONEncoder().encode(Body(reset: reset))
        let data = try await observing {
            try await client.data(for: APIRequest(method: "POST", path: "/v1/admin/demo", body: body))
        }
        return try Self.decode(DemoVenue.self, from: data)
    }

    /// Deletes their demo venue and their access to it (`DELETE /v1/admin/demo`). The app goes back to ``choices()``.
    public func removeDemoVenue() async throws {
        _ = try await observing { try await client.data(for: APIRequest(method: "DELETE", path: "/v1/admin/demo")) }
        if let saved = try? audienceStore?.load(), saved.isDemo { try? audienceStore?.delete() }
    }

    public func venueDevicesAvailable() async -> Bool {
        struct Status: Decodable { let enabled: Bool }
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(attempt)) }
            do {
                let data = try await observing {
                    try await client.data(for: APIRequest(path: "/v1/venue-devices/status", authenticated: false))
                }
                return try JSONDecoder().decode(Status.self, from: data).enabled
            } catch { continue }
        }
        return false
    }

    public var isVenueDevice: Bool {
        guard let credential = storedCredential else { return false }
        return StaffKeychain.isVenueDevice(credential)
    }

    /// Redeems a venue device code (`POST /v1/venue-devices/redeem`): the answer is the device's token JSON plus
    /// `venue_device`, and the credential (a venue device's, by its `venueDeviceId`) becomes this app's session.
    public func redeemVenueCode(_ code: String, identifier: String) async throws -> VenueDeviceSession {
        struct Body: Encodable { let code: String; let identifier: String }
        struct Response: Decodable { let venue_device: VenueDeviceSession }
        let body = try JSONEncoder().encode(Body(code: code, identifier: identifier))
        let data = try await observing {
            try await client.data(for: APIRequest(method: "POST", path: "/v1/venue-devices/redeem", body: body,
                                                  authenticated: false))
        }
        let access = try Self.decode(Response.self, from: data).venue_device
        try await client.adopt(credential: Self.credential(from: data))
        bindDevice(access)
        return access
    }

    /// Starts pairing this screen with a venue by QR code (VenuePairing). `platform` says what's asking, e.g. "tvos".
    public func startVenuePairing(identifier: String, platform: String) async throws -> VenuePairing {
        struct Body: Encodable { let identifier: String; let platform: String }
        let body = try JSONEncoder().encode(Body(identifier: identifier, platform: platform))
        let data = try await observing {
            try await client.data(for: APIRequest(method: "POST", path: "/v1/venue-devices/pairings", body: body,
                                                  authenticated: false))
        }
        return try Self.decode(VenuePairing.self, from: data)
    }

    /// Whether a venue manager has approved the pairing yet: nil while it waits; once approved, signs this device in
    /// like `redeemVenueCode` and returns its access. Throws once the pairing has expired or was already picked up.
    public func claimVenuePairing(_ pairing: VenuePairing) async throws -> VenueDeviceSession? {
        struct Body: Encodable { let poll_token: String }
        struct Response: Decodable { let venue_device: VenueDeviceSession? }
        let body = try JSONEncoder().encode(Body(poll_token: pairing.pollToken))
        let data = try await observing {
            try await client.data(for: APIRequest(method: "POST", path: "/v1/venue-devices/pairings/claim", body: body,
                                                  authenticated: false))
        }
        guard let access = try Self.decode(Response.self, from: data).venue_device else { return nil }
        try await client.adopt(credential: Self.credential(from: data))
        bindDevice(access)
        return access
    }

    public func venueDeviceSession() async throws -> VenueDeviceSession {
        let data = try await observing { try await client.data(for: APIRequest(path: "/v1/venue-devices/session")) }
        let access = try Self.decode(VenueDeviceSession.self, from: data)
        bindDevice(access)
        return access
    }

    private func bindDevice(_ access: VenueDeviceSession) {
        var selected = configuration
        selected.audienceID = access.audience.id
        client = AudienceSession(configuration: selected, credentialStore: credentialStore, session: session)
    }

    /// With `everyAudience`, a super admin also gets every other audience (`?every_audience=true`), for Arbiter, which
    /// works for any audience they run; an API from before it ignores the parameter.
    public func choices(everyAudience: Bool = false) async throws -> [ManagementChoice] {
        struct Response: Decodable { let choices: [ManagementChoice] }
        let query = everyAudience ? [URLQueryItem(name: "every_audience", value: "true")] : []
        let data = try await observing {
            try await client.data(for: APIRequest(path: "/v1/admin/choices", queryItems: query))
        }
        return try Self.decode(Response.self, from: data).choices
            .filter { $0.allowed && $0.audience != nil }
    }

    /// Choosing an audience invalidates the previous server session (`POST /v1/admin/choices`): the credential it
    /// answers with replaces the stored one before any further request.
    public func choose(_ audience: ManagedAudience) async throws {
        _ = try await observing { try await client.switchAudience(to: audience.id) }
        try audienceStore?.save(audience)
        bind(to: audience.id)
    }

    /// Opens `audience` beside this session instead of switching it (`POST /v1/admin/choices` with `alongside`): this
    /// session stays on its audience, and the one returned is bound to `audience`, its credential kept in
    /// `credentialStore` and the audience in `audienceStore`, so ``restoreAudience()`` brings it back next launch.
    /// Both belong to one sign-in on the server: signing out of either ends both. Arbiter works for several audiences
    /// at once this way.
    public func openAlongside(_ audience: ManagedAudience, credentialStore: any CredentialStore,
                              audienceStore: any AudienceStore) async throws -> AudienceManagementSession {
        struct Body: Encodable { let audience_id: String; let alongside = true }
        let body = try JSONEncoder().encode(Body(audience_id: audience.id))
        let data = try await observing {
            try await client.data(for: APIRequest(method: "POST", path: "/v1/admin/choices", body: body))
        }
        let opened = AudienceManagementSession(baseURL: configuration.baseURL, environment: configuration.environment,
                                               credentialStore: credentialStore, audienceStore: audienceStore,
                                               session: session)
        try await opened.adopt(Self.credential(from: data), for: audience)
        return opened
    }

    private func adopt(_ credential: Credential, for audience: ManagedAudience) async throws {
        try await client.adopt(credential: credential)
        try audienceStore?.save(audience)
        bind(to: audience.id)
    }

    /// The audience this device's staff apps last chose, when its session is still the one that chose it, bound to
    /// this client. Nil for a venue device, for a fresh sign-in, and when another app has since switched audience and
    /// the remembered one no longer matches the credential; the caller then shows its audience picker.
    public func restoreAudience() async -> ManagedAudience? {
        guard let audienceStore, let credential = storedCredential, !StaffKeychain.isVenueDevice(credential),
              let audience = try? audienceStore.load() else { return nil }
        bind(to: audience.id)
        return audience
    }

    /// The audience the client is bound to, when one has been chosen or restored.
    public var boundAudienceID: String? { client.configuration.audienceID }

    private func bind(to audienceID: String?) {
        var selected = configuration
        selected.audienceID = audienceID
        client = AudienceSession(configuration: selected, credentialStore: credentialStore, session: session)
    }

    /// Opens the person's own venues and talent listings (signed up in Velvet or Backstage, outside any audience):
    /// they live in a hidden shared tenant (`me { ownListingsAudienceId }` on `/v1/staffql`), whose staffql serves
    /// every tool and the live door and chat to the same platform sign-in. The session is bound to it without it
    /// ever becoming the chosen audience: nothing is remembered, and ``closeOwnListings()`` goes back. Answers its
    /// ID, or nil when they have no listing of their own yet.
    @discardableResult
    public func openOwnListings() async throws -> String? {
        struct Response: Decodable { struct Me: Decodable { let ownListingsAudienceId: String? }; let me: Me? }
        let result = try await ownListingsGraphQL("# endpoint: audienceless\nquery OwnListingsAudience { me { ownListingsAudienceId } }",
                                                as: Response.self)
        guard let audienceID = result.me?.ownListingsAudienceId else { return nil }
        bind(to: audienceID)
        return audienceID
    }

    /// Leaves the person's own listings for the platform sign-in with no audience chosen (their audiences and own
    /// listings). Does nothing when an audience was chosen rather than opened through ``openOwnListings()``.
    public func closeOwnListings() {
        guard canUseOwnListings, boundAudienceID != nil else { return }
        bind(to: nil)
    }

    public func graphQL<Response: Decodable & Sendable>(_ query: String,
                  variables: [String: GraphQLValue]? = nil, as type: Response.Type) async throws -> Response {
        // Staff tools read and change the audience through its staff view (staffql), where their roles apply. A venue
        // or listing of one's own is in the hidden shared tenant: ``openOwnListings()`` binds the session to it first.
        guard !(canUseOwnListings && boundAudienceID == nil) else {
            throw AudienceKitError.missingConfiguration("choose an audience or open your own listings first")
        }
        return try await observing { try await client.graphQL(query, variables: variables, endpoint: .staff, as: type) }
    }

    /// Whether ``ownListingsGraphQL(_:variables:as:)`` can run: signed in on the platform with no audience chosen,
    /// the credential `/v1/staffql` takes. Choosing an audience swaps it for one bound to that audience.
    public var canUseOwnListings: Bool {
        guard let credential = storedCredential, !StaffKeychain.isVenueDevice(credential) else { return false }
        return credential.audienceId == nil
    }

    /// Runs an operation on the audience-less staff endpoint (``GraphQLEndpoint/audiencelessStaff``): a listing of one's
    /// own, in no audience or any number of them. Throws without calling the API when an audience is chosen, since
    /// that credential would be refused there and a refusal ends the session.
    public func ownListingsGraphQL<Response: Decodable & Sendable>(_ query: String,
                                   variables: [String: GraphQLValue]? = nil,
                                   as type: Response.Type) async throws -> Response {
        guard canUseOwnListings else {
            throw AudienceKitError.missingConfiguration("listings of your own need the platform sign-in, before choosing an audience")
        }
        return try await observing {
            try await client.graphQL(query, variables: variables, endpoint: .audiencelessStaff, as: type)
        }
    }

    /// Deletes the signed-in person's AudienceKit account and everything recorded about them (the `deleteAccount`
    /// mutation; it can't be undone), then forgets the local credential. Needs a chosen audience.
    public func deleteAccount() async throws {
        struct Response: Decodable { struct Payload: Decodable { let deleted: Bool }; let deleteAccount: Payload? }
        let result = try await graphQL("mutation { deleteAccount(input: { confirm: true }) { deleted } }",
                                       as: Response.self)
        guard result.deleteAccount?.deleted == true else { throw AudienceKitError.signInFailed(message: "The account wasn’t deleted.") }
        try? audienceStore?.delete()
        // The account is gone, so its token is already dead: forget it, whether or not the revoke call gets through.
        try? await client.signOut()
        try credentialStore.delete()
        await liveCable?.disconnect()
    }

    /// Forgets the local credential and the chosen audience, then revokes the server session (`DELETE /v1/token`).
    /// The device is signed out even when the revoke fails; that failure is thrown so the app can say the session
    /// may still be alive elsewhere.
    public func signOut() async throws {
        try? audienceStore?.delete()
        await liveCable?.disconnect()
        try await observing(reportsSessionEnd: false) { try await client.signOut() }
    }

    /// The credential in a token JSON response, as the SDK reads it.
    private static func credential(from data: Data) throws -> Credential {
        try decode(Credential.self, from: data)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder.audienceKit.decode(type, from: data) }
        catch { throw AudienceKitError.decoding(String(describing: error)) }
    }
}

// MARK: - Onboarding invites (the Velvet and Backstage App Clips)

extension AudienceManagementSession {
    /// What an invite says, without signing in (`GET /v1/onboarding/:code`). An unknown, used or ended code throws
    /// the API's one message for all of them ("This invite has ended. …").
    public func onboardingPreview(_ link: OnboardingLink) async throws -> OnboardingPreview {
        let data = try await observing {
            try await client.data(for: APIRequest(path: "/v1/onboarding/\(link.code)", authenticated: false))
        }
        return try Self.decode(OnboardingPreview.self, from: data)
    }

    /// Binds the invite to the signed-in person (`POST /v1/onboarding/:code/claim`), so nobody else can use it, and
    /// answers with what the curator filled in for them.
    public func claimOnboarding(_ link: OnboardingLink) async throws -> OnboardingPreview {
        let data = try await observing {
            try await client.data(for: APIRequest(method: "POST", path: "/v1/onboarding/\(link.code)/claim"))
        }
        return try Self.decode(OnboardingPreview.self, from: data)
    }

    /// Accepts the invite (`POST /v1/onboarding/:code/accept`): the API grants the access and swaps the session for
    /// one in the invite's audience, which becomes this session's chosen audience, as ``choose(_:)`` does.
    public func acceptOnboarding(_ link: OnboardingLink) async throws -> OnboardingAcceptance {
        switch try await acceptOnboarding(link, choice: nil) {
        case .joined(let acceptance): return acceptance
        case .requested: throw AudienceKitError.decoding("The invite is waiting for a curator")
        }
    }

    /// Accepts the invite, with what a new-listing invite's invitee picked. Answers ``OnboardingOutcome/joined(_:)``
    /// (access granted, session swapped) or, when they asked to own an existing listing,
    /// ``OnboardingOutcome/requested(_:)`` (202: a curator approves it first, and the session stays as it was).
    public func acceptOnboarding(_ link: OnboardingLink, choice: OnboardingListingChoice?) async throws -> OnboardingOutcome {
        struct Response: Decodable {
            struct Tenant: Decodable { let audience: ManagedAudience }
            let tenant: Tenant
            let role: String
            let subject: OnboardingPreview.Subject
        }
        struct Status: Decodable { let status: String? }
        let body = try choice.map { try JSONSerialization.data(withJSONObject: $0.body) }
        let data = try await observing {
            try await client.data(for: APIRequest(method: "POST", path: "/v1/onboarding/\(link.code)/accept", body: body))
        }
        if (try? Self.decode(Status.self, from: data))?.status == "awaiting_approval" {
            return .requested(try Self.decode(OnboardingPreview.self, from: data))
        }
        let response = try Self.decode(Response.self, from: data)
        try await client.adopt(credential: Self.credential(from: data))
        try audienceStore?.save(response.tenant.audience)
        bind(to: response.tenant.audience.id)
        return .joined(OnboardingAcceptance(audience: response.tenant.audience, subject: response.subject,
                                            role: response.role))
    }

    /// What a new-listing invite's invitee might mean (`GET /v1/onboarding/:code/matches?q=`): Google places and the
    /// audience's venues (Velvet), or its performers (Backstage). Needs the invite claimed first.
    public func onboardingMatches(_ link: OnboardingLink, query: String) async throws -> OnboardingMatches {
        let data = try await observing {
            try await client.data(for: APIRequest(path: "/v1/onboarding/\(link.code)/matches",
                                                  queryItems: [URLQueryItem(name: "q", value: query)]))
        }
        return try Self.decode(OnboardingMatches.self, from: data)
    }
}

/// How accepting an invite ended.
public enum OnboardingOutcome: Sendable, Hashable {
    /// They have the access, and the session is in the invite's audience.
    case joined(OnboardingAcceptance)
    /// They asked to own an existing listing: a curator approves or declines it, and nothing is granted yet.
    case requested(OnboardingPreview)
}
