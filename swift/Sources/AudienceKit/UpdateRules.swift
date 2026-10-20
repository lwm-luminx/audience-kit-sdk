import AudienceCore
import Foundation

/// The two places an install updates from.
public enum UpdateChannel: String, Codable, Sendable, Hashable, CaseIterable {
    /// TestFlight: installs whose StoreKit environment is `sandbox`. Prompts name builds ("Build 420215").
    case testFlight
    /// The App Store: installs whose StoreKit environment is `production`. Prompts name versions ("2.2").
    case appStore

    /// The channel an install from `source` updates on; `nil` for development and unknown installs.
    public init?(_ source: InstallSource) {
        switch source {
        case .testFlight: self = .testFlight
        case .appStore: self = .appStore
        case .development, .unknown: return nil
        }
    }
}

/// A newer (or required) build for this install, on its channel: what the prompts and the About rows show.
public struct UpdateOffer: Sendable, Hashable {
    /// Where the install updates from.
    public var channel: UpdateChannel
    /// This build's `CFBundleVersion`.
    public var currentBuild: Int
    /// This build's `CFBundleShortVersionString`.
    public var currentVersion: String
    /// The channel's newest build, when the config names one.
    public var latestBuild: Int?
    /// The newest build's marketing version, when the config names one.
    public var latestVersion: String?
    /// The oldest build that still works on the channel, when the config names one.
    public var minimumBuild: Int?
    /// What's new, one line each; empty hides the "What's new" well.
    public var notes: [String]
    /// The whole config, for its links.
    public var release: AppRelease

    public init(channel: UpdateChannel, currentBuild: Int, currentVersion: String, release: AppRelease) {
        let config = channel == .testFlight ? release.testFlight : release.appStore
        self.channel = channel
        self.currentBuild = currentBuild
        self.currentVersion = currentVersion
        latestBuild = config?.latestBuild
        latestVersion = config?.latestVersion
        minimumBuild = config?.minimumBuild
        notes = config?.notes ?? []
        self.release = release
    }

    /// Where the update button goes, in the order to try: TestFlight's links on TestFlight, the App Store's on the App
    /// Store.
    public var updateLinks: [URL] { channel == .testFlight ? release.testFlightLinks : release.appStoreLinks }

    /// Where "Get it on the App Store" goes, in the order to try.
    public var appStoreLinks: [URL] { release.appStoreLinks }

    /// Whether this build is older than the channel's newest.
    public var isUpdateAvailable: Bool { latestBuild.map { currentBuild < $0 } ?? false }

    /// Whether this build is older than the oldest that still works.
    public var isBelowMinimum: Bool { minimumBuild.map { currentBuild < $0 } ?? false }

    /// The newest build as people see it: "Build 420215" on TestFlight, "Version 2.2" on the App Store (or its build
    /// when the config names no version).
    public var latestLabel: String? {
        switch channel {
        case .testFlight:
            return latestBuild.map(UpdateText.build)
        case .appStore:
            if let latestVersion, !latestVersion.isEmpty { return UpdateText.version(latestVersion) }
            return latestBuild.map(UpdateText.build)
        }
    }

    /// The oldest build that works, as people see it: "Build 420180" (TestFlight only names builds).
    public var minimumLabel: String? { minimumBuild.map(UpdateText.build) }

    /// This build as people see it: "Build 420212" on TestFlight, "Version 2.1" on the App Store.
    public var currentLabel: String {
        channel == .testFlight ? UpdateText.build(currentBuild) : UpdateText.version(currentVersion)
    }
}

/// What to show this install, at most one at a time; the blocking screen wins over everything.
public enum UpdatePrompt: Sendable, Hashable, Identifiable {
    /// A newer build is out: a sheet the person can put off with "Not now".
    case soft(UpdateOffer)
    /// This build is older than the oldest that works: a full screen with no way out but updating.
    case blocking(UpdateOffer)
    /// A TestFlight install, a newer build is out, but the TestFlight app isn't installed, so it can't arrive: a sheet
    /// sending the person to the App Store.
    case noTestFlight(UpdateOffer)

    public var offer: UpdateOffer {
        switch self {
        case let .soft(offer), let .blocking(offer), let .noTestFlight(offer): offer
        }
    }

    public var isBlocking: Bool {
        if case .blocking = self { return true }
        return false
    }

    /// Stable for a prompt, channel and build, so a sheet isn't presented again for the same thing.
    public var id: String {
        let kind = switch self {
        case .soft: "soft"
        case .blocking: "blocking"
        case .noTestFlight: "noTestFlight"
        }
        return "\(kind).\(offer.channel.rawValue).\(offer.latestBuild ?? 0).\(offer.minimumBuild ?? 0)"
    }
}

/// What the About rows say about updates.
public enum UpdateStatus: Sendable, Hashable {
    /// Nothing to say: a development or unknown install, no config yet, or the channel isn't configured.
    case unknown
    /// This is the channel's newest build (or newer).
    case upToDate
    /// A newer build is out, whether or not the person said "Not now" to it.
    case available(UpdateOffer)
}

/// The update decisions, with no I/O: which prompt an install gets, and when to check again.
public enum UpdateRules {
    /// Checked at most once a day.
    public static let defaultInterval: TimeInterval = 24 * 60 * 60

    /// The `CFBundleVersion` as a number, e.g. 420212; `nil` for anything that isn't a whole number (such as "1.2.3"),
    /// which turns the prompts off.
    public static func buildNumber(_ value: String?) -> Int? {
        value.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// The offer for this install on its channel, when the install has a channel and the config covers it.
    public static func offer(source: InstallSource, release: AppRelease?, currentBuild: Int?,
                             currentVersion: String) -> UpdateOffer?
    {
        guard let channel = UpdateChannel(source), let release, let currentBuild,
              release.channel(for: source) != nil
        else { return nil }
        return UpdateOffer(channel: channel, currentBuild: currentBuild, currentVersion: currentVersion,
                           release: release)
    }

    /// The prompt this install gets, if any:
    ///
    /// - development and unknown installs, no config, or no config for the install's channel: none;
    /// - below the channel's `minimumBuild`: ``UpdatePrompt/blocking(_:)``;
    /// - below its `latestBuild`, unless that build was dismissed: ``UpdatePrompt/soft(_:)``, or
    ///   ``UpdatePrompt/noTestFlight(_:)`` for a TestFlight install that can't open `itms-beta://`.
    ///
    /// - Parameters:
    ///   - dismissedBuild: the `latestBuild` the person said "Not now" to on this channel.
    ///   - canOpenTestFlight: whether the TestFlight app is installed (`canOpenURL("itms-beta://…")`).
    public static func prompt(source: InstallSource, release: AppRelease?, currentBuild: Int?,
                              currentVersion: String, dismissedBuild: Int?, canOpenTestFlight: Bool) -> UpdatePrompt?
    {
        guard let offer = offer(source: source, release: release, currentBuild: currentBuild,
                                currentVersion: currentVersion)
        else { return nil }

        if offer.isBelowMinimum { return .blocking(offer) }
        guard offer.isUpdateAvailable, let latest = offer.latestBuild else { return nil }
        if let dismissedBuild, dismissedBuild >= latest { return nil }
        if offer.channel == .testFlight, !canOpenTestFlight { return .noTestFlight(offer) }
        return .soft(offer)
    }

    /// What the About rows say: an available update (dismissed or not), up to date, or nothing.
    public static func status(source: InstallSource, release: AppRelease?, currentBuild: Int?,
                              currentVersion: String) -> UpdateStatus
    {
        guard let offer = offer(source: source, release: release, currentBuild: currentBuild,
                                currentVersion: currentVersion),
              offer.latestBuild != nil
        else { return .unknown }
        return offer.isUpdateAvailable ? .available(offer) : .upToDate
    }

    /// Whether it's time to fetch the config again: never fetched, or `interval` has passed since. A clock that went
    /// backwards counts as due.
    public static func shouldCheck(lastChecked: Date?, now: Date, interval: TimeInterval = defaultInterval) -> Bool {
        guard let lastChecked else { return true }
        let elapsed = now.timeIntervalSince(lastChecked)
        return elapsed < 0 || elapsed >= interval
    }
}

/// The words the prompts use for builds and versions.
public enum UpdateText {
    /// "Build 420215": a build is never named without the word.
    public static func build(_ build: Int) -> String {
        "Build \(build)"
    }

    /// "Version 2.2".
    public static func version(_ version: String) -> String {
        "Version \(version)"
    }

    /// The About row's "Installed from": "TestFlight beta" or "App Store"; `nil` (hide the row) for development and
    /// unknown installs.
    public static func installedFrom(_ source: InstallSource?) -> String? {
        switch source {
        case .testFlight: "TestFlight beta"
        case .appStore: "App Store"
        case .development, .unknown, nil: nil
        }
    }

    /// The About row's label for the update status: "Beta updates" on TestFlight, "Updates" otherwise.
    public static func updatesRowTitle(_ source: InstallSource?) -> String {
        source == .testFlight ? "Beta updates" : "Updates"
    }

    /// The About row's value: "Build 420215 ready", "Version 2.2 ready" or "Up to date"; `nil` with nothing to say.
    public static func status(_ status: UpdateStatus) -> String? {
        switch status {
        case let .available(offer): offer.latestLabel.map { "\($0) ready" }
        case .upToDate: "Up to date"
        case .unknown: nil
        }
    }
}
