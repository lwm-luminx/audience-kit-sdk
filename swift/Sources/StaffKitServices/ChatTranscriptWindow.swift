import Foundation

/// How long a room shows its guests a message, so a staff screen can mark where the guests' view ends. Staff are sent
/// older messages; guests stop seeing each one once it's older than the room's chat retention.
public struct ChatGuestWindow: Sendable, Hashable {
    /// How long a message stays up for guests.
    public let retention: TimeInterval

    public init(retention: TimeInterval) { self.retention = max(0, retention) }

    /// The window a room's `chatRetentionMinutes` gives.
    public init?(minutes: Int?) {
        guard let minutes, minutes > 0 else { return nil }
        self.init(retention: TimeInterval(minutes) * 60)
    }

    /// The window `ChatJoined.expiresBefore` (an ISO 8601 instant) gives, heard at `heardAt`. The cutoff moves with
    /// the clock, so it's kept as a length of time rather than as that instant.
    public init?(expiresBefore: String?, heardAt: Date = Date()) {
        guard let cutoff = parseInstant(expiresBefore), cutoff <= heardAt else { return nil }
        self.init(retention: heardAt.timeIntervalSince(cutoff))
    }

    /// Guests don't see a message sent before this.
    public func cutoff(at now: Date = Date()) -> Date { now.addingTimeInterval(-retention) }
}

/// What a staff chat screen draws of a room's transcript: the last two days, with anything older behind "Show more",
/// and where the guests' view of the room ends, so staff can tell what guests still see from the room's history.
public struct ChatTranscriptWindow: Sendable {
    /// Messages older than this wait behind "Show more" until someone asks for them.
    public static let recent: TimeInterval = 48 * 60 * 60

    /// The messages to draw, oldest first.
    public let shown: [VenueChatMessage]
    /// How many of the loaded messages are behind "Show more".
    public let hiddenCount: Int
    /// How many of `shown`, from the top, guests no longer see. The divider goes after them; zero draws none.
    public let expiredCount: Int

    /// Lays out `messages` (newest first, as the API pages them). `showingAll` is set once someone taps "Show more";
    /// `guests` is the room's window when it's known.
    public init(newestFirst messages: [VenueChatMessage], guests: ChatGuestWindow?, showingAll: Bool, now: Date = Date()) {
        let oldestFirst = Array(messages.reversed())
        let since = now.addingTimeInterval(-Self.recent)
        // A message whose time can't be read is drawn as a recent one.
        let shown = showingAll ? oldestFirst : oldestFirst.filter { (parseInstant($0.sentAt) ?? now) >= since }
        self.shown = shown
        hiddenCount = oldestFirst.count - shown.count
        if let cutoff = guests?.cutoff(at: now) {
            expiredCount = shown.prefix { (parseInstant($0.sentAt) ?? now) < cutoff }.count
        } else {
            expiredCount = 0
        }
    }

    /// Whether "Show more" has something to show: loaded messages behind it, or older pages still to read.
    public func canShowMore(hasOlderPages: Bool) -> Bool { hiddenCount > 0 || hasOlderPages }

    /// The message the divider sits above, or nil when it sits below every message (or isn't drawn).
    public var firstGuestVisibleID: String? {
        guard expiredCount > 0, expiredCount < shown.count else { return nil }
        return shown[expiredCount].id
    }

    /// Whether the divider goes after the last message: everything shown is history guests no longer see.
    public var dividerAtEnd: Bool { expiredCount > 0 && expiredCount == shown.count }
}
