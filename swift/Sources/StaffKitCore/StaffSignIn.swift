import AudienceCore
import Foundation
#if canImport(Security)
import Security
#endif

/// One sign-in for Focus, Velvet and Backstage on a device.
///
/// The three staff apps share a keychain access group (their `group.com.audiencekit.shared` app group), so a manager
/// who signs in to one is signed in to all three, and choosing an audience in one chooses it everywhere. Next and
/// Production builds keep separate items, as their keychain services always have.
public enum StaffKeychain {
    /// The access group every staff app's entitlements already carry.
    public static let accessGroup = "group.com.audiencekit.shared"

    /// The shared item's service for an environment: the test and production installs never read each other's session.
    public static func service(for environment: AudienceKitEnvironment) -> String {
        switch environment {
        case .staging: "com.audiencekit.staff.next"
        default: "com.audiencekit.staff.production" // production and unknown; `default` also covers cases a newer SDK adds
        }
    }

    #if canImport(Security)
    /// Where the chosen audience is kept beside the shared credential, so a sibling app can open on the same audience.
    public static func audienceStore(for environment: AudienceKitEnvironment) -> KeychainAudienceStore {
        KeychainAudienceStore(service: service(for: environment), account: "audience", accessGroup: accessGroup)
    }
    #endif

    /// The environment whose sign-ins `environment`'s API also takes, if any: next takes production's (the API's
    /// `TRUSTED_API_ORIGIN`), so a switch to Next keeps the production session and chosen audience.
    public static func trusted(by environment: AudienceKitEnvironment) -> AudienceKitEnvironment? {
        environment == .staging ? .production : nil
    }

    /// Whether a session belongs to a venue device (a redeemed device code) rather than a signed-in manager.
    public static func isVenueDevice(_ credential: Credential) -> Bool {
        credential.venueDeviceId != nil
    }
}

/// Somewhere to remember the audience the staff apps chose, beside the credential.
public protocol AudienceStore: Sendable {
    func load() throws -> ManagedAudience?
    func save(_ audience: ManagedAudience) throws
    func delete() throws
}

/// Remembers the audience in memory only, for tests and previews.
public final class InMemoryAudienceStore: AudienceStore, @unchecked Sendable {
    private let lock = NSLock()
    private var audience: ManagedAudience?

    public init(audience: ManagedAudience? = nil) {
        self.audience = audience
    }

    public func load() throws -> ManagedAudience? { lock.withLock { audience } }
    public func save(_ audience: ManagedAudience) throws { lock.withLock { self.audience = audience } }
    public func delete() throws { lock.withLock { audience = nil } }
}

#if canImport(Security)
/// Remembers the chosen audience as a JSON keychain item, readable by every app in the access group.
public struct KeychainAudienceStore: AudienceStore {
    public let service: String
    public let account: String
    public let accessGroup: String?
    /// The data protection keychain on the Mac (`KeychainCredentialStore.dataProtection`), so a rebuild keeps it.
    public let dataProtection: Bool

    public init(service: String, account: String = "audience", accessGroup: String? = nil, dataProtection: Bool = false) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
        self.dataProtection = dataProtection
    }

    public func load() throws -> ManagedAudience? {
        guard let data = try item.load() else { return nil }
        return try? JSONDecoder().decode(ManagedAudience.self, from: data)
    }

    public func save(_ audience: ManagedAudience) throws {
        try item.save(JSONEncoder().encode(audience))
    }

    public func delete() throws {
        try item.delete()
    }

    private var item: KeychainItem {
        KeychainItem(service: service, account: account, accessGroup: accessGroup, dataProtection: dataProtection)
    }
}

/// One generic-password keychain item, readable after first unlock like the SDK's credential item.
struct KeychainItem {
    let service: String
    let account: String
    let accessGroup: String?
    var dataProtection = false

    func load() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw KeychainError(status: status)
        }
    }

    func save(_ data: Data) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainError(status: status) }
        let addStatus = SecItemAdd(baseQuery.merging(attributes) { current, _ in current } as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        if dataProtection { query[kSecUseDataProtectionKeychain as String] = true }
        return query
    }
}
#endif

/// Keeps a manager's credential where every staff app can read it, and a venue device's where only this app can.
///
/// A device code is bound to one device and one venue's permissions, so a door iPad's Velvet session must never unlock
/// Focus or Backstage: those credentials stay in the app's own store. Everything else goes to the shared store. A
/// manager's credential saved by an older build in the app's own store is moved to the shared one the first time it
/// is read.
public struct StaffCredentialStore: CredentialStore {
    /// Read by every staff app in the access group.
    public let shared: any CredentialStore
    /// Read by this app only: venue device sessions, and manager sessions from before sign-in was shared.
    public let app: any CredentialStore
    /// The shared item of the environment this one's API also takes (``StaffKeychain/trusted(by:)``): production's,
    /// on Next. Read when this environment has no session of its own, and never written.
    public let trusted: (any CredentialStore)?

    public init(shared: any CredentialStore, app: any CredentialStore, trusted: (any CredentialStore)? = nil) {
        self.shared = shared
        self.app = app
        self.trusted = trusted
    }

    #if canImport(Security)
    /// The shared item for `environment` beside this app's own item, `appService` being the service the app used before.
    public init(environment: AudienceKitEnvironment, appService: String) {
        self.init(shared: KeychainCredentialStore(service: StaffKeychain.service(for: environment),
                                                  accessGroup: StaffKeychain.accessGroup),
                  app: KeychainCredentialStore(service: appService),
                  trusted: StaffKeychain.trusted(by: environment).map {
                      KeychainCredentialStore(service: StaffKeychain.service(for: $0), accessGroup: StaffKeychain.accessGroup)
                  })
    }
    #endif

    public func load() throws -> Credential? {
        if let own = try ownCredential() { return own }
        return try trusted?.load()
    }

    private func ownCredential() throws -> Credential? {
        if let credential = try app.load() {
            if StaffKeychain.isVenueDevice(credential) { return credential }
            // A manager signed in before sign-in was shared: move the session where the other apps can see it,
            // unless one of them has signed in since.
            if let current = try shared.load() {
                try app.delete()
                return current
            }
            try shared.save(credential)
            try app.delete()
            return credential
        }
        return try shared.load()
    }

    public func save(_ credential: Credential) throws {
        if StaffKeychain.isVenueDevice(credential) {
            try app.save(credential)
        } else {
            try shared.save(credential)
            try app.delete()
        }
    }

    /// Ends whichever session this app is using: a device's own, or the manager's shared one, or the trusted
    /// environment's when it was using that one (signing out on Next of a production session ends it there too: they
    /// share the session).
    public func delete() throws {
        if let credential = try app.load(), StaffKeychain.isVenueDevice(credential) {
            try app.delete()
        } else {
            let borrowed = try ownCredential() == nil
            try app.delete()
            try shared.delete()
            if borrowed { try trusted?.delete() }
        }
    }
}

/// The chosen audience, falling back to the trusted environment's (production's, on Next) until one is chosen here.
public struct StaffAudienceStore: AudienceStore {
    public let own: any AudienceStore
    public let trusted: (any AudienceStore)?

    public init(own: any AudienceStore, trusted: (any AudienceStore)? = nil) {
        self.own = own
        self.trusted = trusted
    }

    public func load() throws -> ManagedAudience? {
        try own.load() ?? trusted?.load()
    }

    public func save(_ audience: ManagedAudience) throws { try own.save(audience) }

    public func delete() throws { try own.delete() }
}

#if canImport(Security)
extension AudienceManagementSession {
    /// The session a staff app uses: one sign-in and one chosen audience shared with its siblings through the keychain
    /// group (``StaffCredentialStore``, ``StaffKeychain/audienceStore(for:)``), `appService` being the app's own item.
    ///
    /// UI tests (the App Store screenshots) launch the app with two variables people can't set on a device:
    /// `AK_UI_TEST_SIGNED_OUT=1` forgets the stored session and audience first, and `AK_UI_TEST_API_URL` points the app
    /// at another API, e.g. a local server holding the demo audience.
    public static func staff(environment: AudienceKitEnvironment, appService: String,
                             processEnvironment: [String: String] = ProcessInfo.processInfo.environment)
        -> AudienceManagementSession
    {
        let credentials = StaffCredentialStore(environment: environment, appService: appService)
        let audience = StaffAudienceStore(own: StaffKeychain.audienceStore(for: environment),
                                          trusted: StaffKeychain.trusted(by: environment).map(StaffKeychain.audienceStore(for:)))
        if processEnvironment["AK_UI_TEST_SIGNED_OUT"] == "1" {
            try? credentials.app.delete()
            try? credentials.shared.delete()
            try? audience.own.delete()
        }
        return AudienceManagementSession(baseURL: processEnvironment["AK_UI_TEST_API_URL"].flatMap(URL.init(string:)),
                                         environment: environment, credentialStore: credentials, audienceStore: audience)
    }
}
#endif
