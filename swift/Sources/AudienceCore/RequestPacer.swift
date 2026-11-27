import Foundation

/// Keeps one session from flooding the API (a request storm), whatever the app's timers and retries do.
///
/// - **Pacing.** A token bucket: up to `burst` requests at once, refilling at `perSecond`. A request beyond that
///   waits its turn instead of going out at once.
/// - **Backing off.** When the API answers 429 (rate limited), or 503 (unavailable) with a `Retry-After`, every
///   request this session makes is held back until the answer's `Retry-After` has passed, or, without one, for 1, 2, 4… seconds up to a minute
///   after each one in a row (with jitter, so many devices don't come back together). A held-back request fails at
///   once with ``AudienceKitError/Code/rateLimited`` and never reaches the network, so a cached answer stands in
///   where there is one (``GraphQLCache``). The first answer that doesn't ask for one ends the backoff.
///
/// ``AudienceSession`` keeps one and sends every HTTP request through it.
public struct RequestPacer: Sendable {
    /// The most requests that may go out at once.
    public var burst: Double
    /// How many requests a second the bucket refills by.
    public var perSecond: Double
    /// The longest a backoff lasts, whatever `Retry-After` says.
    public var maximumBackoff: TimeInterval

    private var tokens: Double
    private var refilledAt: Date?
    private var pausedUntil: Date?
    private var strikes = 0

    public init(burst: Double = 20, perSecond: Double = 8, maximumBackoff: TimeInterval = 120) {
        self.burst = max(1, burst)
        self.perSecond = max(0.1, perSecond)
        self.maximumBackoff = maximumBackoff
        tokens = self.burst
    }

    /// What to do with a request now: send it, wait first, or fail it because the API asked this session to wait.
    public enum Admission: Equatable, Sendable {
        case send
        case wait(TimeInterval)
        case paused(retryAfter: TimeInterval)
    }

    /// Whether a request may go out at `now`. `.send` takes a token; `.wait` means ask again after that long.
    public mutating func admit(now: Date = Date()) -> Admission {
        if let pausedUntil, pausedUntil > now {
            return .paused(retryAfter: pausedUntil.timeIntervalSince(now))
        }
        pausedUntil = nil
        refill(now: now)
        if tokens >= 1 {
            tokens -= 1
            return .send
        }
        return .wait((1 - tokens) / perSecond)
    }

    /// Learns from a response: 429, or 503 with a `Retry-After`, starts (or lengthens) a backoff; anything else ends it.
    public mutating func observe(status: Int, retryAfter: String?, now: Date = Date(), jitter: Double = .random(in: 0 ... 0.25)) {
        guard status == 429 || (status == 503 && Self.seconds(retryAfter, now: now) != nil) else {
            strikes = 0
            return
        }
        strikes += 1
        let fallback = pow(2, Double(min(strikes - 1, 6)))
        let delay = min(Self.seconds(retryAfter, now: now) ?? fallback, maximumBackoff)
        let until = now.addingTimeInterval(delay * (1 + jitter))
        pausedUntil = max(pausedUntil ?? until, until)
    }

    /// When the API asked this session to wait until, if it still is.
    public func pausedUntil(now: Date = Date()) -> Date? {
        guard let pausedUntil, pausedUntil > now else { return nil }
        return pausedUntil
    }

    private mutating func refill(now: Date) {
        if let refilledAt {
            tokens = min(burst, tokens + max(0, now.timeIntervalSince(refilledAt)) * perSecond)
        }
        refilledAt = now
    }

    /// A `Retry-After` value in seconds: delta-seconds, or an HTTP date.
    static func seconds(_ value: String?, now: Date) -> TimeInterval? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if let seconds = Double(value) { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: value) else { return nil }
        return max(0, date.timeIntervalSince(now))
    }
}
