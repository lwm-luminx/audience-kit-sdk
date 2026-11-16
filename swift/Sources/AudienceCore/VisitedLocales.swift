import Foundation

/// A locale the person has been in, as remembered on this phone.
public struct VisitedLocale: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public var name: String
    public var lastVisitedAt: Date

    public init(id: String, name: String, lastVisitedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.lastVisitedAt = lastVisitedAt
    }
}

/// The locales the person has been in lately, kept on the phone only and never sent, so a background refresh knows
/// which cities' data to keep fresh in the ``GraphQLCache`` (Rick, 2026-11-15: "Users may track locales they were in
/// as a way locally to prompt what to sync").
///
/// Kept in `UserDefaults` (never iCloud), per audience. Forget it on sign-out with ``removeAll()``.
public final class VisitedLocales: @unchecked Sendable {
    /// How many locales to remember; the oldest visit goes first.
    public let limit: Int
    /// How long a visit counts; older ones are dropped.
    public let window: TimeInterval
    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()

    /// - Parameters:
    ///   - audienceID: one list per audience.
    ///   - limit: how many locales to keep (5 by default).
    ///   - window: how long a visit counts (30 days by default).
    public init(audienceID: String, defaults: UserDefaults = .standard, limit: Int = 5,
                window: TimeInterval = 30 * 24 * 60 * 60) {
        self.defaults = defaults
        self.key = "AudienceKit.visitedLocales.\(audienceID)"
        self.limit = limit
        self.window = window
    }

    /// Notes that the person is in `id` now (or at `date`).
    public func record(id: String, name: String, at date: Date = Date()) {
        lock.withLock {
            var all = load().filter { $0.id != id }
            all.insert(VisitedLocale(id: id, name: name, lastVisitedAt: date), at: 0)
            save(prune(all, now: date))
        }
    }

    /// The locales visited within ``window``, most recent first.
    public func recent(now: Date = Date()) -> [VisitedLocale] {
        lock.withLock { prune(load(), now: now) }
    }

    public func removeAll() {
        lock.withLock { defaults.removeObject(forKey: key) }
    }

    private func prune(_ locales: [VisitedLocale], now: Date) -> [VisitedLocale] {
        Array(locales.filter { now.timeIntervalSince($0.lastVisitedAt) <= window }
            .sorted { $0.lastVisitedAt > $1.lastVisitedAt }
            .prefix(limit))
    }

    private func load() -> [VisitedLocale] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([VisitedLocale].self, from: data)) ?? []
    }

    private func save(_ locales: [VisitedLocale]) {
        guard let data = try? JSONEncoder().encode(locales) else { return }
        defaults.set(data, forKey: key)
    }
}

/// Spaces out background refreshes: after a failure it waits longer each time (doubling from `base` up to `cap`),
/// and a success resets it, so a failing API is never asked in a tight loop while the cache keeps serving the last
/// good answer.
public struct RefreshBackoff: Sendable, Hashable, Codable {
    public var base: TimeInterval
    public var cap: TimeInterval
    public private(set) var failures: Int = 0
    public private(set) var lastAttemptAt: Date?

    public init(base: TimeInterval = 15 * 60, cap: TimeInterval = 6 * 60 * 60) {
        self.base = base
        self.cap = cap
    }

    /// How long to wait after the last attempt: `base` after a success, doubling with each failure up to `cap`.
    public var interval: TimeInterval {
        min(cap, base * pow(2, Double(min(failures, 16))))
    }

    /// Whether a refresh is due at `now`.
    public func isDue(now: Date = Date()) -> Bool {
        guard let lastAttemptAt else { return true }
        return now.timeIntervalSince(lastAttemptAt) >= interval
    }

    /// When the next refresh is due.
    public func nextDate(now: Date = Date()) -> Date {
        (lastAttemptAt ?? now).addingTimeInterval(lastAttemptAt == nil ? 0 : interval)
    }

    public mutating func succeeded(at date: Date = Date()) {
        failures = 0
        lastAttemptAt = date
    }

    public mutating func failed(at date: Date = Date()) {
        failures += 1
        lastAttemptAt = date
    }
}
