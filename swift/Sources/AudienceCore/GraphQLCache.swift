import Foundation

// MARK: - Policy

/// How a GraphQL call uses the on-device cache (``AudienceSession/graphQL(_:variables:operationName:endpoint:as:decoder:cachePolicy:cacheKey:)``).
///
/// The cache keeps the last good response for each query, so a flaky connection or a failing API shows the last
/// thing the person saw instead of an error. Only queries are kept, never mutations (unless the caller names a
/// `cacheKey` for a mutation that reads, such as a position report that returns what's nearby).
public enum GraphQLCachePolicy: Sendable, Hashable {
    /// Always ask the API, and never read or write the cache. The default, so nothing changes for callers that
    /// don't opt in.
    case networkOnly
    /// Ask the API and keep a good answer. When the API can't answer (offline, timed out, a 5xx, a GraphQL error, a
    /// response the app can't decode), return the last good answer instead, if it is no older than `maxAge`. A
    /// refusal that a kept answer can't fix (signed out, forbidden, not found, update required) still throws.
    case networkFirst(maxAge: TimeInterval = GraphQLCachePolicy.defaultMaxAge)
    /// Ask the API and keep a good answer, but never answer from the cache: for a background refresh, which needs to
    /// know when the API failed (to back off) while screens keep showing the last good answer.
    case refresh
    /// Return a kept answer without asking when it is no older than `freshFor`; otherwise behave as
    /// ``networkFirst(maxAge:)``. For data that changes slowly and is read often.
    case cacheFirst(freshFor: TimeInterval, maxAge: TimeInterval = GraphQLCachePolicy.defaultMaxAge)

    /// A week: older answers are more confusing than an error.
    public static let defaultMaxAge: TimeInterval = 7 * 24 * 60 * 60

    var maxAge: TimeInterval? {
        switch self {
        case .networkOnly, .refresh: nil
        case let .networkFirst(maxAge): maxAge
        case let .cacheFirst(_, maxAge): maxAge
        }
    }
}

/// Where a ``GraphQLResult`` came from.
public enum GraphQLResultSource: String, Sendable, Hashable {
    /// The API answered just now.
    case network
    /// The cache answered: the API wasn't asked (``GraphQLCachePolicy/cacheFirst(freshFor:maxAge:)``), or it
    /// failed and this is the last good answer (``GraphQLResult/error`` says why).
    case cache
}

/// A GraphQL answer and where it came from.
public struct GraphQLResult<Value: Sendable>: Sendable {
    public typealias Source = GraphQLResultSource

    public let value: Value
    public let source: Source
    /// When the API sent this answer: now for ``Source/network``, earlier for ``Source/cache``.
    public let fetchedAt: Date
    /// When the cache answered because the API failed: the failure.
    public let error: AudienceKitError?

    public init(value: Value, source: Source, fetchedAt: Date, error: AudienceKitError? = nil) {
        self.value = value
        self.source = source
        self.fetchedAt = fetchedAt
        self.error = error
    }

    /// Whether this is an older answer the API couldn't refresh, so a screen can say "Showing what we had at 9:41".
    public var isStale: Bool { error != nil }

    public func map<T: Sendable>(_ transform: (Value) throws -> T) rethrows -> GraphQLResult<T> {
        GraphQLResult<T>(value: try transform(value), source: source, fetchedAt: fetchedAt, error: error)
    }
}

extension AudienceKitError {
    /// Whether a kept answer is a fair stand-in when a query fails this way: the API couldn't answer, rather than
    /// refused. Signed out, forbidden, not found, invalid input and update required are refusals.
    public var allowsCachedAnswer: Bool {
        // The SDK answers these by asking the schema and retrying with fewer fields, so they must reach it.
        if errors.contains(where: { $0.code == "undefinedField" || $0.code == "undefinedType" }) { return false }
        switch code {
        case Code.network, Code.internalError, Code.decoding, Code.graphQL, Code.rateLimited:
            return true
        case Code.http:
            return (status ?? 500) >= 500 || status == 408
        default:
            return false
        }
    }
}

// MARK: - Storage

/// One kept response: the whole successful GraphQL response body, decoded again on the way out.
public struct GraphQLCacheEntry: Codable, Sendable, Hashable {
    /// The full cache key (``GraphQLCacheKey``), kept so a hash collision in a file name is never served.
    public let key: String
    public let body: Data
    public let storedAt: Date

    public init(key: String, body: Data, storedAt: Date = Date()) {
        self.key = key
        self.body = body
        self.storedAt = storedAt
    }
}

/// Where ``AudienceSession`` keeps the last good answer to each query. Pass one as the session's `cache` to turn
/// caching on; ``FileGraphQLCache`` keeps answers across launches.
///
/// Everything in it is the signed-in person's own data. The session empties it on sign-out and account deletion,
/// and keys every entry by audience and person, so one person never sees another's answers.
public protocol GraphQLCache: Sendable {
    func entry(for key: String) -> GraphQLCacheEntry?
    func store(_ entry: GraphQLCacheEntry)
    /// Forgets entries older than `date`.
    func removeEntries(storedBefore date: Date)
    func removeAll()
}

/// Builds the key an answer is kept under: the API instance, audience, person, endpoint and either the caller's
/// `cacheKey` or the document and its variables (with sorted keys, so the same variables always match).
public enum GraphQLCacheKey {
    public static func make(apiBase: URL, audienceID: String?, userID: String?, endpointPath: String,
                            query: String, variables: [String: GraphQLValue]?, cacheKey: String?) -> String {
        let operation: String
        if let cacheKey {
            operation = "key:" + cacheKey
        } else {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let vars = variables.flatMap { try? encoder.encode($0) }.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let normalized = query.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            operation = "doc:" + normalized + "|vars:" + vars
        }
        return [apiBase.absoluteString, audienceID ?? "-", userID ?? "-", endpointPath, operation]
            .joined(separator: "|")
    }

    /// A file-name-safe digest of `key`: two FNV-1a 64-bit hashes with different seeds, as hex.
    static func digest(_ key: String) -> String {
        func fnv(_ seed: UInt64) -> UInt64 {
            var hash = seed
            for byte in key.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x100_0000_01B3
            }
            return hash
        }
        return String(format: "%016llx%016llx", fnv(0xCBF2_9CE4_8422_2325), fnv(0x84222325_CBF29CE4))
    }
}

/// Keeps answers in memory: for tests, previews, and apps that only want fallback within one launch.
public final class InMemoryGraphQLCache: GraphQLCache, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: GraphQLCacheEntry] = [:]

    public init() {}

    public func entry(for key: String) -> GraphQLCacheEntry? {
        lock.withLock { entries[key] }
    }

    public func store(_ entry: GraphQLCacheEntry) {
        lock.withLock { entries[entry.key] = entry }
    }

    public func removeEntries(storedBefore date: Date) {
        lock.withLock { entries = entries.filter { $0.value.storedAt >= date } }
    }

    public func removeAll() {
        lock.withLock { entries.removeAll() }
    }

    public var count: Int { lock.withLock { entries.count } }
}

/// Keeps answers as files in the app's Caches directory, so they outlive the launch. The system may empty Caches when
/// the device runs low on space, and it isn't backed up, which suits data that the API can always send again. On iOS
/// the files are readable after the first unlock, so a background refresh can use them while the phone is locked.
public final class FileGraphQLCache: GraphQLCache, @unchecked Sendable {
    public let directory: URL
    private let lock = NSLock()
    private let fileManager = FileManager.default

    /// - Parameter directory: where to keep the files; by default `Caches/AudienceKit/GraphQL`.
    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AudienceKit", isDirectory: true)
            .appendingPathComponent("GraphQL", isDirectory: true)
    }

    public func entry(for key: String) -> GraphQLCacheEntry? {
        lock.withLock {
            guard let data = try? Data(contentsOf: url(for: key)),
                  let entry = try? Self.decoder.decode(GraphQLCacheEntry.self, from: data),
                  entry.key == key
            else { return nil }
            return entry
        }
    }

    public func store(_ entry: GraphQLCacheEntry) {
        lock.withLock {
            guard let data = try? Self.encoder.encode(entry) else { return }
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            #if os(iOS)
            try? data.write(to: url(for: entry.key), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try? data.write(to: url(for: entry.key), options: [.atomic])
            #endif
        }
    }

    public func removeEntries(storedBefore date: Date) {
        lock.withLock {
            let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for file in files {
                guard let data = try? Data(contentsOf: file),
                      let entry = try? Self.decoder.decode(GraphQLCacheEntry.self, from: data)
                else {
                    try? fileManager.removeItem(at: file)
                    continue
                }
                if entry.storedAt < date { try? fileManager.removeItem(at: file) }
            }
        }
    }

    public func removeAll() {
        lock.withLock { _ = try? fileManager.removeItem(at: directory) }
    }

    private func url(for key: String) -> URL {
        directory.appendingPathComponent(GraphQLCacheKey.digest(key) + ".json")
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
