import Foundation

#if canImport(os)
import os
#endif

/// Keeps the last GraphQL operations the SDK ran, in memory, so an app's "Check the app" screen (``AppCheck``) can show
/// what failed and why. On Apple platforms each one is also written to the unified log (category `graphql` under the
/// app's subsystem), so Console.app shows failures from a device.
///
/// It's a ``GraphQLMonitor``: hand it to ``AudienceSession/init(configuration:credentialStore:session:monitor:deviceAttestor:)``.
/// An app that already has monitoring (New Relic, say) passes it as `forwardingTo`, and every event goes on to it too.
///
/// Built for the DNC demo app, where queries over the complexity budget failed quietly behind `try?` and screens
/// came up empty; Hack Different's empty catalog was the same kind of failure.
public final class GraphQLOperationLog: GraphQLMonitor, @unchecked Sendable {
    /// One finished HTTP operation.
    public struct Entry: Identifiable, Sendable, Hashable {
        public let id: UUID
        public let date: Date
        public let name: String
        public let milliseconds: Int?
        public let error: String?

        public init(id: UUID = UUID(), date: Date = Date(), name: String, milliseconds: Int?, error: String?) {
            self.id = id
            self.date = date
            self.name = name
            self.milliseconds = milliseconds
            self.error = error
        }

        public var failed: Bool { error != nil }
    }

    public let capacity: Int
    private let forward: (any GraphQLMonitor)?
    private let lock = NSLock()
    private var stored: [Entry] = []
    #if canImport(os)
    private let logger: Logger?
    #endif

    /// - Parameters:
    ///   - subsystem: The unified log subsystem, usually the bundle ID; nil writes nothing to the unified log.
    ///   - capacity: How many operations to keep (the oldest go first).
    ///   - forward: Monitoring every event is passed on to.
    public init(subsystem: String? = nil, capacity: Int = 100, forwardingTo forward: (any GraphQLMonitor)? = nil) {
        self.capacity = max(1, capacity)
        self.forward = forward
        #if canImport(os)
        logger = subsystem.map { Logger(subsystem: $0, category: "graphql") }
        #endif
    }

    /// Everything kept, oldest first.
    public var entries: [Entry] { lock.withLock { stored } }

    /// The most recent failures, newest first.
    public func failures(limit: Int = 10) -> [Entry] {
        Array(entries.filter(\.failed).suffix(limit).reversed())
    }

    public func clear() {
        lock.withLock { stored.removeAll() }
    }

    public func record(_ event: GraphQLOperationEvent) {
        forward?.record(event)
        guard event.kind == .completed else { return }
        let name = event.name ?? event.type
        let milliseconds = event.duration.map(Self.milliseconds)
        #if canImport(os)
        if let error = event.error {
            logger?.error("\(name, privacy: .public) failed: \(error, privacy: .public)")
        } else {
            logger?.debug("\(name, privacy: .public) ok in \(milliseconds ?? -1) ms")
        }
        #endif
        let entry = Entry(name: name, milliseconds: milliseconds, error: event.error)
        lock.withLock {
            stored.append(entry)
            if stored.count > capacity { stored.removeFirst(stored.count - capacity) }
        }
    }

    public func record(_ event: CableSocketEvent) {
        forward?.record(event)
    }

    static func milliseconds(_ duration: Duration) -> Int {
        Int(duration.components.seconds * 1_000 + duration.components.attoseconds / 1_000_000_000_000_000)
    }
}
