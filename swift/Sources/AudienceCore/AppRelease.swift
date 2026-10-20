import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if canImport(StoreKit)
import StoreKit
#endif

/// What `GET /v1/app_release?app=<bundle id>` returns (and `GET /v1/branding`'s `app_release`): where an app is
/// published, and each channel's newest and oldest supported build. Public, no sign-in. The update prompts
/// (``AudienceKit/AudienceUpdates``) read it.
///
/// Every field may be missing: an unknown link means no button for it, a missing channel means no prompts on it, a
/// missing ``Channel/latestBuild`` means no soft prompt and a missing ``Channel/minimumBuild`` means nothing blocks.
public struct AppRelease: Codable, Sendable, Hashable {
    /// One way the app reaches people: TestFlight or the App Store.
    public struct Channel: Codable, Sendable, Hashable {
        /// The newest build (`CFBundleVersion`) on the channel. Builds below it are offered an update.
        public var latestBuild: Int?
        /// The oldest build that still works. Builds below it have to update before they can use the app.
        public var minimumBuild: Int?
        /// The newest build's marketing version (`CFBundleShortVersionString`), e.g. "2.2".
        public var latestVersion: String?
        /// What's new in the newest build, one line each.
        public var notes: [String]

        public init(latestBuild: Int? = nil, minimumBuild: Int? = nil, latestVersion: String? = nil,
                    notes: [String] = [])
        {
            self.latestBuild = latestBuild
            self.minimumBuild = minimumBuild
            self.latestVersion = latestVersion
            self.notes = notes
        }

        enum CodingKeys: String, CodingKey {
            case latestBuild = "latest_build"
            case minimumBuild = "minimum_build"
            case latestVersion = "latest_version"
            case notes
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            latestBuild = container.lenientInt(forKey: .latestBuild)
            minimumBuild = container.lenientInt(forKey: .minimumBuild)
            latestVersion = container.lenientString(forKey: .latestVersion)
            notes = ((try? container.decodeIfPresent([String?].self, forKey: .notes)) ?? nil)?
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty } ?? []
        }
    }

    /// The app's bundle ID, e.g. `social.hotmess.HotMess`.
    public var identifier: String?
    /// `ios`.
    public var platform: String?
    /// The API environment the entry is for, e.g. `production`.
    public var environment: String?
    /// The App Store's numeric ID for the app, e.g. "1195758383": the `itms-beta://` and `itms-apps://` links use it.
    public var appStoreID: String?
    /// The App Store page, for when `itms-apps://` doesn't open.
    public var appStoreURL: URL?
    /// The public TestFlight invite (`https://testflight.apple.com/join/<code>`), for when `itms-beta://` doesn't open.
    public var testFlightURL: URL?
    /// The TestFlight channel: what `sandbox` installs are compared with.
    public var testFlight: Channel?
    /// The App Store channel: what `production` installs are compared with.
    public var appStore: Channel?

    public init(identifier: String? = nil, platform: String? = "ios", environment: String? = nil,
                appStoreID: String? = nil, appStoreURL: URL? = nil, testFlightURL: URL? = nil,
                testFlight: Channel? = nil, appStore: Channel? = nil)
    {
        self.identifier = identifier
        self.platform = platform
        self.environment = environment
        self.appStoreID = appStoreID
        self.appStoreURL = appStoreURL
        self.testFlightURL = testFlightURL
        self.testFlight = testFlight
        self.appStore = appStore
    }

    enum CodingKeys: String, CodingKey {
        case identifier, platform, environment
        case appStoreID = "app_store_id"
        case appStoreURL = "app_store_url"
        case testFlightURL = "testflight_url"
        case testFlight = "testflight"
        case appStore = "app_store"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identifier = container.lenientString(forKey: .identifier)
        platform = container.lenientString(forKey: .platform)
        environment = container.lenientString(forKey: .environment)
        appStoreID = container.lenientString(forKey: .appStoreID)
        appStoreURL = container.lenientString(forKey: .appStoreURL).flatMap(URL.init(string:))
        testFlightURL = container.lenientString(forKey: .testFlightURL).flatMap(URL.init(string:))
        testFlight = try container.decodeIfPresent(Channel.self, forKey: .testFlight)
        appStore = try container.decodeIfPresent(Channel.self, forKey: .appStore)
    }

    /// The channel an install from `source` updates on: TestFlight for a TestFlight install, the App Store for an App
    /// Store one, none otherwise.
    public func channel(for source: InstallSource) -> Channel? {
        switch source {
        case .testFlight: testFlight
        case .appStore: appStore
        case .development, .unknown: nil
        }
    }

    // MARK: Links

    /// `itms-beta://beta.itunes.apple.com/v1/app/<appStoreID>`: opens the app's page in the TestFlight app.
    public var testFlightAppURL: URL? {
        appStoreID.flatMap(Self.digits).flatMap { URL(string: "itms-beta://beta.itunes.apple.com/v1/app/\($0)") }
    }

    /// `itms-apps://apps.apple.com/app/id<appStoreID>`: opens the app's page in the App Store app.
    public var appStoreAppURL: URL? {
        appStoreID.flatMap(Self.digits).flatMap { URL(string: "itms-apps://apps.apple.com/app/id\($0)") }
    }

    /// Where "Update in TestFlight" goes, in the order to try: the TestFlight app, then the invite link.
    public var testFlightLinks: [URL] { [testFlightAppURL, testFlightURL].compactMap { $0 } }

    /// Where "Update on the App Store" and "Get it on the App Store" go, in the order to try: the App Store app, then
    /// the web page.
    public var appStoreLinks: [URL] {
        var links = [appStoreAppURL, appStoreURL].compactMap { $0 }
        if appStoreURL == nil, let id = appStoreID.flatMap(Self.digits),
           let web = URL(string: "https://apps.apple.com/app/id\(id)")
        {
            links.append(web)
        }
        return links
    }

    /// The ID's digits, from "1195758383" or "id1195758383".
    private static func digits(_ id: String) -> String? {
        let digits = id.filter(\.isNumber)
        return digits.isEmpty ? nil : digits
    }
}

/// Where this copy of the app came from, by StoreKit 2's `AppTransaction`: TestFlight (`sandbox`), the App Store
/// (`production`) or Xcode (`xcode`). Anything StoreKit can't vouch for is ``unknown``, and gets no update prompts.
public enum InstallSource: String, Codable, Sendable, Hashable, CaseIterable {
    /// A TestFlight beta: StoreKit's `sandbox` environment. Updates come from TestFlight.
    case testFlight
    /// The App Store: StoreKit's `production` environment. Updates come from the App Store.
    case appStore
    /// Built and run from Xcode: StoreKit's `xcode` environment. Never prompted.
    case development
    /// `AppTransaction` threw, couldn't be verified, named an environment the SDK doesn't know, or StoreKit isn't
    /// available on this platform. Never prompted.
    case unknown

    /// The source for an `AppStore.Environment`'s raw value: `Sandbox`, `Production` or `Xcode` (any case).
    public init(environment: String) {
        switch environment.lowercased() {
        case "sandbox": self = .testFlight
        case "production": self = .appStore
        case "xcode": self = .development
        default: self = .unknown
        }
    }

    /// Whether this install can be offered updates: TestFlight and App Store installs.
    public var isUpdatable: Bool { self == .testFlight || self == .appStore }

    /// This install's source, read once from `AppTransaction.shared` and kept for the rest of the run. A transaction
    /// that throws or doesn't verify is ``unknown``; there is no receipt fallback.
    public static var current: InstallSource {
        get async { await currentTask.value }
    }

    private static let currentTask = Task<InstallSource, Never> { await InstallSourceReader.read() }
}

/// What a stored or fetched ``AppRelease`` says, kept between runs so the prompts work offline: the release, when it
/// was last fetched, and the newest build the person said "Not now" to on each channel.
public struct AppReleaseState: Codable, Sendable, Hashable {
    /// The release as last fetched, or `nil` before the first successful fetch (no prompts then).
    public var release: AppRelease?
    /// When the release was last fetched (or the API said it had none).
    public var lastChecked: Date?
    /// The `latestBuild` "Not now" was tapped for, by channel (`testFlight`, `appStore`).
    public var dismissedBuilds: [String: Int]

    public init(release: AppRelease? = nil, lastChecked: Date? = nil, dismissedBuilds: [String: Int] = [:]) {
        self.release = release
        self.lastChecked = lastChecked
        self.dismissedBuilds = dismissedBuilds
    }

    enum CodingKeys: String, CodingKey {
        case release, lastChecked, dismissedBuilds
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        release = try? container.decodeIfPresent(AppRelease.self, forKey: .release)
        lastChecked = try? container.decodeIfPresent(Date.self, forKey: .lastChecked)
        dismissedBuilds = (try? container.decodeIfPresent([String: Int].self, forKey: .dismissedBuilds)) ?? [:]
    }
}

/// Keeps an ``AppReleaseState`` between runs.
public protocol AppReleaseStore: Sendable {
    func load() -> AppReleaseState
    func save(_ state: AppReleaseState)
}

/// Keeps the ``AppReleaseState`` in `UserDefaults`, as JSON under one key.
public final class UserDefaultsAppReleaseStore: AppReleaseStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()

    /// - Parameters:
    ///   - defaults: `.standard` unless the app shares an app group.
    ///   - key: the defaults key; one per app.
    public init(defaults: UserDefaults = .standard, key: String = "AudienceKit.appRelease") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> AppReleaseState {
        lock.withLock {
            guard let data = defaults.data(forKey: key),
                  let state = try? Self.decoder.decode(AppReleaseState.self, from: data)
            else { return AppReleaseState() }
            return state
        }
    }

    public func save(_ state: AppReleaseState) {
        lock.withLock {
            guard let data = try? Self.encoder.encode(state) else { return }
            defaults.set(data, forKey: key)
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Keeps the ``AppReleaseState`` in memory: for tests and previews.
public final class InMemoryAppReleaseStore: AppReleaseStore, @unchecked Sendable {
    private let lock = NSLock()
    private var state: AppReleaseState

    public init(_ state: AppReleaseState = AppReleaseState()) {
        self.state = state
    }

    public func load() -> AppReleaseState { lock.withLock { state } }
    public func save(_ state: AppReleaseState) { lock.withLock { self.state = state } }
}

extension AudienceSession {
    /// The app's release config, `GET /v1/app_release?app=<bundle id>`: its links and each channel's builds. No
    /// sign-in needed. `nil` when the API doesn't know the app (404).
    ///
    /// - Parameter app: the bundle ID; this app's by default.
    public func appRelease(app: String? = Bundle.main.bundleIdentifier) async throws -> AppRelease? {
        guard let app, !app.isEmpty else {
            throw AudienceKitError.missingConfiguration("the app release needs a bundle ID")
        }
        let request = APIRequest(path: "/v1/app_release", queryItems: [URLQueryItem(name: "app", value: app)],
                                 authenticated: false)
        do {
            let data = try await data(for: request)
            do {
                return try JSONDecoder().decode(AppRelease.self, from: data)
            } catch {
                throw AudienceKitError.decoding(String(describing: error))
            }
        } catch let error as AudienceKitError where error.status == 404 {
            return nil
        }
    }
}

// MARK: - StoreKit

#if canImport(StoreKit)
enum InstallSourceReader {
    static func read() async -> InstallSource {
        do {
            // Only a transaction StoreKit verified counts; an unverified one is no evidence of where the app came from.
            guard case let .verified(transaction) = try await AppTransaction.shared else { return .unknown }
            switch transaction.environment {
            case .sandbox: return .testFlight
            case .production: return .appStore
            case .xcode: return .development
            default: return .unknown
            }
        } catch {
            return .unknown
        }
    }
}
#else
enum InstallSourceReader {
    static func read() async -> InstallSource { .unknown }
}
#endif

// MARK: - Lenient decoding

extension KeyedDecodingContainer {
    /// A string, or a number written as one; `nil` for null, missing or anything else.
    func lenientString(forKey key: Key) -> String? {
        if let string = try? decodeIfPresent(String.self, forKey: key) { return string }
        if let number = try? decodeIfPresent(Int.self, forKey: key) { return String(number) }
        if let number = try? decodeIfPresent(Double.self, forKey: key) { return String(number) }
        return nil
    }

    /// An integer, or a string of one; `nil` for null, missing or anything else.
    func lenientInt(forKey key: Key) -> Int? {
        if let number = try? decodeIfPresent(Int.self, forKey: key) { return number }
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            return Int(string.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }
}
