import Foundation

/// The promoted-card categories the viewer turned off ("Cards you see"), kept on the device and synced privately
/// through their iCloud key-value store when iCloud is on (the app needs the
/// `com.apple.developer.ubiquity-kvstore-identifier` entitlement), else in `UserDefaults`. Never sent to the server,
/// logged, or counted: build a ``CardFilter`` from it and filter on the device.
public final class CardPreferences: @unchecked Sendable {
    /// The key both stores keep the hidden categories under.
    public static let key = "audiencekit.cards.hiddenCategories"

    private let defaults: UserDefaults
    private let lock = NSLock()
    #if canImport(Darwin)
    private let cloud: NSUbiquitousKeyValueStore?
    private var observer: (any NSObjectProtocol)?
    #endif

    /// Called on the main queue when the hidden set changes, here or on another of the viewer's devices.
    public var onChange: (@Sendable (Set<String>) -> Void)?

    /// `cloud: false` keeps them on this device only (tests, or an app without the entitlement).
    public init(defaults: UserDefaults = .standard, cloud: Bool = true) {
        self.defaults = defaults
        #if canImport(Darwin)
        self.cloud = cloud ? NSUbiquitousKeyValueStore.default : nil
        if let store = self.cloud {
            observer = NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store, queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                let hidden = self.hidden
                self.defaults.set(hidden.sorted(), forKey: Self.key)
                self.onChange?(hidden)
            }
            store.synchronize()
        }
        #endif
    }

    deinit {
        #if canImport(Darwin)
        if let observer { NotificationCenter.default.removeObserver(observer) }
        #endif
    }

    /// The categories turned off.
    public var hidden: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        #if canImport(Darwin)
        if let values = cloud?.array(forKey: Self.key) as? [String] { return Set(values) }
        #endif
        return Set(defaults.stringArray(forKey: Self.key) ?? [])
    }

    public func isHidden(_ category: String) -> Bool {
        hidden.contains(category)
    }

    /// Turns a category off or back on.
    public func setHidden(_ category: String, _ hide: Bool) {
        var hidden = self.hidden
        if hide { hidden.insert(category) } else { hidden.remove(category) }
        store(hidden)
    }

    /// Shows every category again.
    public func reset() {
        store([])
    }

    /// The filter for these preferences and the published categories.
    public func filter(categories: [CardCategory]?) -> CardFilter {
        CardFilter(hidden: hidden, categories: categories)
    }

    private func store(_ hidden: Set<String>) {
        let values = hidden.sorted()
        lock.lock()
        defaults.set(values, forKey: Self.key)
        #if canImport(Darwin)
        cloud?.set(values, forKey: Self.key)
        cloud?.synchronize()
        #endif
        lock.unlock()
        let onChange = onChange
        if Thread.isMainThread {
            onChange?(hidden)
        } else {
            DispatchQueue.main.async { onChange?(hidden) }
        }
    }
}
