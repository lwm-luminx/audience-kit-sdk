import Foundation

/// The words for the one-time note a reader acknowledges before their first Soapbox story: a publisher's ads are the
/// publisher's own relationship, kept so it can keep paying writers; the app takes no cut, and its own sponsored spots
/// are separate. The same words on iOS and Android (`PublisherAdsCopy` there).
public enum PublisherAdsCopy {
    public static let title = "Publishers run their own ads"

    /// The note, naming the app ("Hot Mess").
    public static func body(appName: String) -> String {
        """
        Stories here come from independent publishers. Each publisher chooses the ads in its stories and answers for \
        them: that ad relationship is the publisher's own, and it's there so they can keep paying writers and making \
        the work you read.

        \(appName) takes no cut, just as it takes none from performers' tips. \(appName)'s own sponsored spots are \
        separate and always marked Promoted, and \(appName) never shares your data with a publisher's advertisers.
        """
    }

    public static let accept = "I understand"
    public static let decline = "Not now"
}

/// Which signed-in people on this device have acknowledged ``PublisherAdsCopy``, so the note shows once per person
/// before their first Soapbox story and not again. Kept by user ID on the device and synced privately through their
/// iCloud key-value store when iCloud is on (the same store as ``CardPreferences``), else in `UserDefaults`. Never
/// sent to the server.
public final class PublisherAdsAcknowledgement: @unchecked Sendable {
    /// The key both stores keep the acknowledged user IDs under.
    public static let key = "audiencekit.soapbox.publisherAdsAcknowledged"

    private let defaults: UserDefaults
    private let lock = NSLock()
    #if canImport(Darwin)
    private let cloud: NSUbiquitousKeyValueStore?
    #endif

    /// `cloud: false` keeps it on this device only (tests, or an app without the entitlement).
    public init(defaults: UserDefaults = .standard, cloud: Bool = true) {
        self.defaults = defaults
        #if canImport(Darwin)
        self.cloud = cloud ? NSUbiquitousKeyValueStore.default : nil
        self.cloud?.synchronize()
        #endif
    }

    /// Whether `userID` has acknowledged it. Nobody signed in (`nil`) never has, so a guest sees the note each time.
    public func isAcknowledged(by userID: String?) -> Bool {
        guard let userID = Self.normalized(userID) else { return false }
        return acknowledged.contains(userID)
    }

    /// Records that `userID` acknowledged it. Does nothing for `nil`.
    public func acknowledge(userID: String?) {
        guard let userID = Self.normalized(userID) else { return }
        lock.lock()
        defer { lock.unlock() }
        let values = (read().union([userID])).sorted()
        defaults.set(values, forKey: Self.key)
        #if canImport(Darwin)
        cloud?.set(values, forKey: Self.key)
        cloud?.synchronize()
        #endif
    }

    /// Forgets every acknowledgement (sign out of everything, tests).
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: Self.key)
        #if canImport(Darwin)
        cloud?.removeObject(forKey: Self.key)
        cloud?.synchronize()
        #endif
    }

    private var acknowledged: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return read()
    }

    private func read() -> Set<String> {
        var values = Set(defaults.stringArray(forKey: Self.key) ?? [])
        #if canImport(Darwin)
        if let synced = cloud?.array(forKey: Self.key) as? [String] { values.formUnion(synced) }
        #endif
        return values
    }

    private static func normalized(_ userID: String?) -> String? {
        guard let id = userID?.trimmingCharacters(in: .whitespaces).lowercased(), !id.isEmpty else { return nil }
        return id
    }
}
