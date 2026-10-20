import AudienceCore
import Foundation

#if canImport(Combine)
import Combine
#endif
#if canImport(UIKit) && !os(watchOS)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Update prompts for TestFlight and App Store installs, driven by the API's release config
/// (``AudienceSession/appRelease(app:)``) and StoreKit 2's install environment (``InstallSource``).
///
/// Configure one at launch with ``configure(session:appName:testFlightURL:appStoreURL:minimumInterval:store:)``, then
/// either apply AudienceKitUI's `.audienceUpdatePrompts()` at the root of the app (or `AudienceUpdatePromptPresenter`
/// in UIKit), or draw your own UI from ``prompt``, ``prompts`` or ``onPrompt``.
///
/// - Development (`xcode`) and unknown installs never see anything, and the config isn't fetched for them.
/// - The config is fetched when the app comes to the foreground (``checkOnForeground()``), at most once per
///   ``minimumInterval``; ``checkNow()`` ("Check for updates") skips the wait. It is kept between runs, so the prompts
///   work offline, and with none stored (first launch offline) nothing shows.
/// - A build below its channel's oldest working build gets the blocking prompt on every foreground, from the stored
///   config. A soft prompt shows only after a fetch, once per build: "Not now" (``dismiss()``) skips that build.
@MainActor
public final class AudienceUpdates {
    /// The instance ``configure(session:appName:testFlightURL:appStoreURL:minimumInterval:store:)`` made, which the
    /// SwiftUI modifier and UIKit presenter use when not handed one.
    public private(set) static var shared: AudienceUpdates?

    /// The bundle ID the config is fetched for.
    public let app: String
    /// The app's name in the prompts' copy, e.g. "Hot Mess".
    public let appName: String
    /// This build's `CFBundleVersion` as a number; `nil` (no prompts) when it isn't a whole number.
    public let currentBuild: Int?
    /// This build's `CFBundleShortVersionString`.
    public let currentVersion: String
    /// How long to wait between fetches on foreground.
    public let minimumInterval: TimeInterval

    /// Where this install came from, once StoreKit has said (`nil` before the first check).
    public private(set) var installSource: InstallSource? {
        willSet { willChange() }
    }

    /// What to show now: the blocking screen, a soft sheet, the TestFlight-missing sheet, or nothing.
    public private(set) var prompt: UpdatePrompt? {
        willSet { willChange() }
        didSet { if prompt != oldValue { announce(prompt) } }
    }

    /// Whether a fetch is under way.
    public private(set) var isChecking = false {
        willSet { willChange() }
    }

    /// The stored config, when it was last fetched, and the builds the person said "Not now" to.
    public private(set) var state: AppReleaseState {
        willSet { willChange() }
    }

    /// Called on the main actor whenever ``prompt`` changes: the custom-UI hook for apps that draw their own prompts
    /// (AudienceKitUI's `UpdateBanner`, `UpdateSheet` and `UpdateScreen` are there to draw them with).
    public var onPrompt: (@MainActor (UpdatePrompt?) -> Void)?

    private let store: any AppReleaseStore
    private let fetch: @Sendable () async throws -> AppRelease?
    private let readInstallSource: @Sendable () async -> InstallSource
    private let testFlightInstalled: @MainActor (AppRelease) -> Bool
    private let openLink: @MainActor (URL) async -> Bool
    private let now: @Sendable () -> Date
    private let fallbackTestFlightURL: URL?
    private let fallbackAppStoreURL: URL?
    private var subscribers: [UUID: AsyncStream<UpdatePrompt?>.Continuation] = [:]

    /// Update prompts for this app, fetching its config through `session`.
    ///
    /// - Parameters:
    ///   - session: the API to fetch `GET /v1/app_release` from (its configured base URL).
    ///   - app: the bundle ID; this app's by default.
    ///   - appName: the name the copy uses; the bundle's display name by default.
    ///   - bundle: where the build and version are read from.
    ///   - testFlightURL: the TestFlight invite to fall back to when the config has none.
    ///   - appStoreURL: the App Store page to fall back to when the config has none.
    ///   - minimumInterval: how long to wait between fetches on foreground; a day by default.
    ///   - store: where the config and dismissals are kept; `UserDefaults` by default.
    public convenience init(session: AudienceSession, app: String? = nil, appName: String? = nil,
                            bundle: Bundle = .main, testFlightURL: URL? = nil, appStoreURL: URL? = nil,
                            minimumInterval: TimeInterval = UpdateRules.defaultInterval,
                            store: (any AppReleaseStore)? = nil)
    {
        let app = app ?? bundle.bundleIdentifier ?? ""
        let name = appName
            ?? bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "This app"
        self.init(app: app, appName: name,
                  currentBuild: UpdateRules.buildNumber(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String),
                  currentVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                  testFlightURL: testFlightURL, appStoreURL: appStoreURL, minimumInterval: minimumInterval,
                  store: store ?? UserDefaultsAppReleaseStore(key: "AudienceKit.appRelease.\(app)"),
                  fetch: { [session] in try await session.appRelease(app: app) })
    }

    /// Update prompts with every outside dependency handed in: for tests, previews and apps with their own transport.
    ///
    /// - Parameters:
    ///   - fetch: fetches the config; `nil` when the API has none for the app.
    ///   - installSource: where this install came from; ``InstallSource/current`` by default.
    ///   - testFlightInstalled: whether the TestFlight app can be opened; `canOpenURL("itms-beta://…")` by default.
    ///   - openURL: opens a link and says whether it did; `UIApplication.open` by default.
    ///   - now: the clock.
    public init(app: String, appName: String, currentBuild: Int?, currentVersion: String,
                testFlightURL: URL? = nil, appStoreURL: URL? = nil,
                minimumInterval: TimeInterval = UpdateRules.defaultInterval,
                store: any AppReleaseStore = InMemoryAppReleaseStore(),
                fetch: @escaping @Sendable () async throws -> AppRelease?,
                installSource: @escaping @Sendable () async -> InstallSource = { await InstallSource.current },
                testFlightInstalled: (@MainActor (AppRelease) -> Bool)? = nil,
                openURL: (@MainActor (URL) async -> Bool)? = nil,
                now: @escaping @Sendable () -> Date = { Date() })
    {
        self.app = app
        self.appName = appName
        self.currentBuild = currentBuild
        self.currentVersion = currentVersion
        self.minimumInterval = minimumInterval
        self.store = store
        self.fetch = fetch
        readInstallSource = installSource
        self.testFlightInstalled = testFlightInstalled ?? SystemLinks.canOpenTestFlight
        openLink = openURL ?? SystemLinks.open
        self.now = now
        fallbackTestFlightURL = testFlightURL
        fallbackAppStoreURL = appStoreURL
        state = store.load()
    }

    /// Makes the app's update prompts and keeps them as ``shared``. Call once at launch.
    @discardableResult
    public static func configure(session: AudienceSession, appName: String? = nil, testFlightURL: URL? = nil,
                                 appStoreURL: URL? = nil, minimumInterval: TimeInterval = UpdateRules.defaultInterval,
                                 store: (any AppReleaseStore)? = nil) -> AudienceUpdates
    {
        let updates = AudienceUpdates(session: session, appName: appName, testFlightURL: testFlightURL,
                                      appStoreURL: appStoreURL, minimumInterval: minimumInterval, store: store)
        shared = updates
        return updates
    }

    /// Makes `updates` the ``shared`` instance, e.g. one built with injected dependencies.
    public static func configure(_ updates: AudienceUpdates) {
        shared = updates
    }

    // MARK: - State

    /// The stored config, with the fallback links filled in.
    public var release: AppRelease? {
        guard var filled = state.release else { return nil }
        if filled.testFlightURL == nil { filled.testFlightURL = fallbackTestFlightURL }
        if filled.appStoreURL == nil { filled.appStoreURL = fallbackAppStoreURL }
        return filled
    }

    /// When the config was last fetched.
    public var lastChecked: Date? { state.lastChecked }

    /// What the About rows say: an update waiting (dismissed or not), up to date, or nothing to say.
    public var status: UpdateStatus {
        guard let installSource else { return .unknown }
        return UpdateRules.status(source: installSource, release: release, currentBuild: currentBuild,
                                  currentVersion: currentVersion)
    }

    /// The update waiting for this install, if any, whether or not it was dismissed: for an inline banner.
    public var availableUpdate: UpdateOffer? {
        if case let .available(offer) = status { return offer }
        return nil
    }

    /// The update waiting for this install that the person hasn't said "Not now" to: what an inline `UpdateBanner`
    /// shows. Closing the banner is ``dismiss()``.
    public var pendingUpdate: UpdateOffer? {
        guard let offer = availableUpdate, let latest = offer.latestBuild else { return nil }
        if let dismissed = state.dismissedBuilds[offer.channel.rawValue], dismissed >= latest { return nil }
        return offer
    }

    /// Every change to ``prompt``, starting with the current one: the custom-UI hook as a stream. Each access is a new
    /// subscription.
    public var prompts: AsyncStream<UpdatePrompt?> {
        let (stream, continuation) = AsyncStream<UpdatePrompt?>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.subscribers[id] = nil }
        }
        continuation.yield(prompt)
        return stream
    }

    // MARK: - Checking

    /// The app came to the foreground: fetches the config when ``minimumInterval`` has passed since the last fetch,
    /// then decides the prompt. A build below the oldest that works is blocked from the stored config even when no
    /// fetch is due.
    public func checkOnForeground() async {
        await check(force: false)
    }

    /// "Check for updates": fetches the config now, whatever the interval, then decides the prompt.
    public func checkNow() async {
        await check(force: true)
    }

    private func check(force: Bool) async {
        let source: InstallSource
        if let installSource {
            source = installSource
        } else {
            source = await readInstallSource()
            installSource = source
        }
        guard source.isUpdatable else {
            prompt = nil
            return
        }

        var fetched = false
        if (force || UpdateRules.shouldCheck(lastChecked: state.lastChecked, now: now(), interval: minimumInterval)),
           !isChecking
        {
            isChecking = true
            defer { isChecking = false }
            do {
                let release = try await fetch()
                var next = state
                next.release = release
                next.lastChecked = now()
                state = next
                store.save(next)
                fetched = true
            } catch {
                // Offline or refused: keep the stored config, and try again on the next foreground.
            }
        }

        decide(source: source, fetched: fetched)
    }

    /// Feeds in a config the app got another way, such as ``Branding/appRelease`` from `branding(app:)`, as if it had
    /// just been fetched.
    public func adopt(_ release: AppRelease?) {
        var next = state
        next.release = release
        next.lastChecked = now()
        state = next
        store.save(next)
        if let installSource { decide(source: installSource, fetched: true) }
    }

    private func decide(source: InstallSource, fetched: Bool) {
        let channel = UpdateChannel(source)
        let release = self.release
        var canOpenTestFlight = false
        if source == .testFlight, let release { canOpenTestFlight = testFlightInstalled(release) }
        var dismissedBuild: Int?
        if let channel { dismissedBuild = state.dismissedBuilds[channel.rawValue] }
        let decided = UpdateRules.prompt(
            source: source, release: release, currentBuild: currentBuild, currentVersion: currentVersion,
            dismissedBuild: dismissedBuild, canOpenTestFlight: canOpenTestFlight
        )
        // Blocking (and nothing) always apply; a soft prompt only after a fetch, so it shows at most once per interval.
        if fetched || decided == nil || decided?.isBlocking == true || prompt?.id == decided?.id {
            prompt = decided
        } else if prompt?.isBlocking == true {
            prompt = nil
        }
    }

    // MARK: - Acting

    /// "Not now" (or swiping the sheet away, or hiding the banner): forgets the soft prompt and skips its build until
    /// a newer one. Does nothing to the blocking screen.
    public func dismiss() {
        guard let offer = prompt?.offer ?? availableUpdate, prompt?.isBlocking != true,
              let latest = offer.latestBuild
        else { return }
        var next = state
        next.dismissedBuilds[offer.channel.rawValue] = latest
        state = next
        store.save(next)
        prompt = nil
    }

    /// Opens the update on the install's channel: TestFlight (`itms-beta://`, then the invite link) or the App Store
    /// (`itms-apps://`, then the web page). Returns whether a link opened.
    @discardableResult
    public func openUpdate() async -> Bool {
        guard let source = installSource, let channel = UpdateChannel(source), let release else { return false }
        return await open(channel == .testFlight ? release.testFlightLinks : release.appStoreLinks)
    }

    /// Opens the app on the App Store: `itms-apps://`, then the web page. Returns whether a link opened.
    @discardableResult
    public func openAppStore() async -> Bool {
        await open(release?.appStoreLinks ?? [])
    }

    /// Opens the first of `links` that opens.
    @discardableResult
    public func open(_ links: [URL]) async -> Bool {
        for link in links {
            if await openLink(link) { return true }
        }
        return false
    }

    // MARK: - Private

    private func announce(_ prompt: UpdatePrompt?) {
        onPrompt?(prompt)
        for continuation in subscribers.values {
            continuation.yield(prompt)
        }
    }

    private func willChange() {
        #if canImport(Combine)
        objectWillChange.send()
        #endif
    }
}

#if canImport(Combine)
extension AudienceUpdates: ObservableObject {}
#endif

/// The plan's name for setting up the update prompts: ``AudienceUpdates/configure(session:appName:testFlightURL:appStoreURL:minimumInterval:store:)``.
/// The build endpoint is the session's API.
@MainActor
@discardableResult
public func configureBetaUpdates(session: AudienceSession, appName: String? = nil, testFlightURL: URL? = nil,
                                 appStoreURL: URL? = nil,
                                 minimumInterval: TimeInterval = UpdateRules.defaultInterval) -> AudienceUpdates
{
    AudienceUpdates.configure(session: session, appName: appName, testFlightURL: testFlightURL,
                              appStoreURL: appStoreURL, minimumInterval: minimumInterval)
}

/// Opening links and asking whether TestFlight is there, on the platform at hand.
@MainActor
enum SystemLinks {
    /// Whether `itms-beta://` opens: the TestFlight app is installed. The app must list `itms-beta` in
    /// `LSApplicationQueriesSchemes`, or this is always false.
    static func canOpenTestFlight(_ release: AppRelease) -> Bool {
        guard let url = release.testFlightAppURL ?? URL(string: "itms-beta://") else { return false }
        #if canImport(UIKit) && !os(watchOS)
        return UIApplication.shared.canOpenURL(url)
        #elseif canImport(AppKit)
        return NSWorkspace.shared.urlForApplication(toOpen: url) != nil
        #else
        return false
        #endif
    }

    static func open(_ url: URL) async -> Bool {
        #if canImport(UIKit) && !os(watchOS)
        return await UIApplication.shared.open(url)
        #elseif canImport(AppKit)
        return NSWorkspace.shared.open(url)
        #else
        return false
        #endif
    }
}
