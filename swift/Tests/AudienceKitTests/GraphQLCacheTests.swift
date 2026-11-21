@testable import AudienceCore
import Foundation
import Testing
@testable import AudienceKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let cacheAudienceID = "00000000-0000-4000-8000-000000000044"

private struct Greeting: Decodable, Sendable, Equatable { let hello: String }

private func cachingClient(_ stub: Stub, cache: any GraphQLCache = InMemoryGraphQLCache(),
                           policy: GraphQLCachePolicy = .networkFirst(), userID: String = "u-1")
    -> (AudienceKitClient, InMemoryCredentialStore) {
    let endpoint = URL(string: GraphQLEndpoint.consumer.path(audienceID: cacheAudienceID), relativeTo: stub.baseURL)!
        .absoluteURL
    let store = InMemoryCredentialStore(credential: Credential(token: "session-token", userId: userID,
                                                               audienceId: cacheAudienceID, role: "member",
                                                               endpoint: endpoint))
    let configuration = AudienceKitConfiguration(baseURL: stub.baseURL, audienceID: cacheAudienceID)
    return (AudienceKitClient(configuration: configuration, credentialStore: store, session: stub.session,
                              cache: cache, defaultCachePolicy: policy), store)
}

/// Answers "world" until `failing` is set, then fails the way `failure` says.
private final class Flaky: @unchecked Sendable {
    let lock = NSLock()
    var failure: StubResponse?
    var answer = "world"

    func respond() -> StubResponse {
        lock.withLock { failure ?? .json(status: 200, body: #"{"data":{"hello":"\#(answer)"}}"#) }
    }
}

@Test func aFailedQueryReturnsTheLastGoodAnswer() async throws {
    let flaky = Flaky()
    let stub = Stub { _ in flaky.respond() }
    let (client, _) = cachingClient(stub)

    let fresh = try await client.graphQLResult("query Hello { hello }", as: Greeting.self)
    #expect(fresh.value.hello == "world")
    #expect(fresh.source == .network)
    #expect(!fresh.isStale)

    for failure: StubResponse in [.failure(URLError(.notConnectedToInternet)),
                                  .json(status: 503, body: "{}"),
                                  .json(status: 200, body: #"{"data":null,"errors":[{"message":"boom"}]}"#),
                                  .json(status: 200, body: #"{"data":{"hello":7}}"#)] {
        flaky.lock.withLock { flaky.failure = failure }
        let kept = try await client.graphQLResult("query Hello { hello }", as: Greeting.self)
        #expect(kept.value.hello == "world")
        #expect(kept.source == .cache)
        #expect(kept.isStale)
        #expect(kept.fetchedAt == fresh.fetchedAt)
    }
}

@Test func refusalsStillThrow() async throws {
    let flaky = Flaky()
    let stub = Stub { _ in flaky.respond() }
    let (client, _) = cachingClient(stub)
    _ = try await client.graphQL("query Hello { hello }", as: Greeting.self)

    for failure: StubResponse in [.json(status: 403, body: "{}"), .json(status: 404, body: "{}"),
                                  .json(status: 200, body: #"{"data":null,"errors":[{"message":"no","extensions":{"code":"undefinedField"}}]}"#)] {
        flaky.lock.withLock { flaky.failure = failure }
        await #expect(throws: AudienceKitError.self) {
            _ = try await client.graphQL("query Hello { hello }", as: Greeting.self)
        }
    }
}

@Test func withoutACacheOrPolicyNothingIsKept() async throws {
    let flaky = Flaky()
    let stub = Stub { _ in flaky.respond() }
    let (client, _) = cachingClient(stub, policy: .networkOnly)
    _ = try await client.graphQL("query Hello { hello }", as: Greeting.self)
    flaky.lock.withLock { flaky.failure = .failure(URLError(.timedOut)) }

    await #expect(throws: AudienceKitError.self) {
        _ = try await client.graphQL("query Hello { hello }", as: Greeting.self)
    }
    // A per-call policy turns it on, but there's nothing kept from the networkOnly call.
    await #expect(throws: AudienceKitError.self) {
        _ = try await client.graphQL("query Hello { hello }", as: Greeting.self, cachePolicy: .networkFirst())
    }
}

@Test func variablesAreOrderIndependentAndKeysSeparateAnswers() async throws {
    let stub = Stub { request in
        let vars = (try? request.jsonBody())?["variables"] as? [String: Any]
        return .json(status: 200, body: #"{"data":{"hello":"\#(vars?["a"] as? String ?? "")"}}"#)
    }
    let (client, _) = cachingClient(stub)
    _ = try await client.graphQL("query Hello($a: String) { hello }", variables: ["a": .string("x"), "b": .int(1)],
                                 as: Greeting.self)
    _ = try await client.graphQL("query Hello($a: String) { hello }", variables: ["a": .string("y")], as: Greeting.self)

    let x = await client.cachedGraphQL("query Hello($a: String) { hello }",
                                       variables: ["b": .int(1), "a": .string("x")], as: Greeting.self)
    let y = await client.cachedGraphQL("query  Hello($a: String)\n{ hello }", variables: ["a": .string("y")],
                                       as: Greeting.self)
    #expect(x?.value.hello == "x")
    #expect(y?.value.hello == "y")
    #expect(x?.source == .cache)
}

@Test func mutationsAreKeptOnlyUnderACacheKey() async throws {
    let flaky = Flaky()
    let stub = Stub { _ in flaky.respond() }
    let (client, _) = cachingClient(stub)
    let doc = "mutation Report($p: Int) { hello }"
    _ = try await client.graphQL(doc, variables: ["p": .int(1)], as: Greeting.self)
    #expect(await client.cachedGraphQL(doc, variables: ["p": .int(1)], as: Greeting.self) == nil)

    _ = try await client.graphQL(doc, variables: ["p": .int(2)], as: Greeting.self, cacheKey: "now")
    flaky.lock.withLock { flaky.failure = .failure(URLError(.networkConnectionLost)) }
    // A different position, same key: the last answer stands in.
    let kept = try await client.graphQLResult(doc, variables: ["p": .int(3)], as: Greeting.self, cacheKey: "now")
    #expect(kept.value.hello == "world")
    #expect(kept.isStale)
}

@Test func cacheFirstSkipsTheNetworkWhileFresh() async throws {
    let flaky = Flaky()
    let stub = Stub { _ in flaky.respond() }
    let (client, _) = cachingClient(stub, policy: .cacheFirst(freshFor: 60))
    _ = try await client.graphQL("query Hello { hello }", as: Greeting.self)
    flaky.lock.withLock { flaky.answer = "again" }

    let kept = try await client.graphQLResult("query Hello { hello }", as: Greeting.self)
    #expect(kept.value.hello == "world")
    #expect(kept.source == .cache)
    #expect(!kept.isStale)
    #expect(stub.requests.count == 1)

    let fresh = try await client.graphQLResult("query Hello { hello }", as: Greeting.self, cachePolicy: .networkFirst())
    #expect(fresh.value.hello == "again")
}

@Test func answersOlderThanMaxAgeAreNotServed() async throws {
    let flaky = Flaky()
    let stub = Stub { _ in flaky.respond() }
    let cache = InMemoryGraphQLCache()
    let (client, _) = cachingClient(stub, cache: cache, policy: .networkFirst(maxAge: 0.05))
    _ = try await client.graphQL("query Hello { hello }", as: Greeting.self)
    try await Task.sleep(for: .milliseconds(120))
    flaky.lock.withLock { flaky.failure = .failure(URLError(.timedOut)) }

    await #expect(throws: AudienceKitError.self) {
        _ = try await client.graphQL("query Hello { hello }", as: Greeting.self)
    }
}

@Test func anotherPersonNeverSeesTheAnswerAndSignOutEmptiesTheCache() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"hello":"world"}}"#) }
    let cache = InMemoryGraphQLCache()
    let (first, _) = cachingClient(stub, cache: cache, userID: "u-1")
    _ = try await first.graphQL("query Hello { hello }", as: Greeting.self)
    #expect(cache.count == 1)

    let (second, _) = cachingClient(stub, cache: cache, userID: "u-2")
    #expect(await second.cachedGraphQL("query Hello { hello }", as: Greeting.self) == nil)

    try? await first.signOut()
    #expect(cache.count == 0)
}

@Test func theFileCacheKeepsAnswersAcrossInstances() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let old = Date(timeIntervalSinceNow: -100)
    FileGraphQLCache(directory: directory).store(GraphQLCacheEntry(key: "a", body: Data("1".utf8)))
    FileGraphQLCache(directory: directory).store(GraphQLCacheEntry(key: "b", body: Data("2".utf8), storedAt: old))

    let cache = FileGraphQLCache(directory: directory)
    #expect(cache.entry(for: "a")?.body == Data("1".utf8))
    #expect(cache.entry(for: "c") == nil)
    cache.removeEntries(storedBefore: Date(timeIntervalSinceNow: -10))
    #expect(cache.entry(for: "b") == nil)
    #expect(cache.entry(for: "a") != nil)
    cache.removeAll()
    #expect(cache.entry(for: "a") == nil)
}

@Test func visitedLocalesKeepTheRecentFewOnThePhone() throws {
    let defaults = try #require(UserDefaults(suiteName: "visited-\(UUID().uuidString)"))
    let visited = VisitedLocales(audienceID: "aud", defaults: defaults, limit: 2, window: 1000)
    let now = Date()
    visited.record(id: "sf", name: "San Francisco", at: now.addingTimeInterval(-2000))
    visited.record(id: "den", name: "Denver", at: now.addingTimeInterval(-30))
    visited.record(id: "la", name: "Los Angeles", at: now.addingTimeInterval(-20))
    visited.record(id: "den", name: "Denver", at: now.addingTimeInterval(-10))

    #expect(visited.recent(now: now).map(\.id) == ["den", "la"])
    #expect(VisitedLocales(audienceID: "other", defaults: defaults).recent().isEmpty)
    visited.removeAll()
    #expect(visited.recent(now: now).isEmpty)
}

@Test func backoffDoublesAfterFailuresAndResetsOnSuccess() {
    var backoff = RefreshBackoff(base: 10, cap: 35)
    let start = Date(timeIntervalSince1970: 1000)
    #expect(backoff.isDue(now: start))
    backoff.failed(at: start)
    #expect(backoff.interval == 20)
    #expect(!backoff.isDue(now: start.addingTimeInterval(19)))
    #expect(backoff.isDue(now: start.addingTimeInterval(20)))
    backoff.failed(at: start)
    #expect(backoff.interval == 35)
    #expect(backoff.nextDate(now: start) == start.addingTimeInterval(35))
    backoff.succeeded(at: start)
    #expect(backoff.interval == 10)
}

@Test func refreshKeepsTheAnswerButNeverServesIt() async throws {
    let flaky = Flaky()
    let stub = Stub { _ in flaky.respond() }
    let (client, _) = cachingClient(stub)
    flaky.lock.withLock { flaky.answer = "refreshed" }
    _ = try await client.graphQL("query Hello { hello }", as: Greeting.self, cachePolicy: .refresh)
    flaky.lock.withLock { flaky.failure = .failure(URLError(.timedOut)) }

    await #expect(throws: AudienceKitError.self) {
        _ = try await client.graphQL("query Hello { hello }", as: Greeting.self, cachePolicy: .refresh)
    }
    let kept = try await client.graphQL("query Hello { hello }", as: Greeting.self)
    #expect(kept.hello == "refreshed")
}

@Test func cachedVenuesReadsTheLastListWithoutTheNetwork() async throws {
    let body = #"{"data":{"venues":{"list":{"nodes":[{"id":"v-1","name":"Purr","hidden":false,"order":1,"photoUrl":null,"bannerUrl":null,"locale":{"id":"l-1","name":"San Francisco","label":"SF","cityNames":null,"bannerUrl":null},"location":null,"tags":[]}]}}}}"#
    let stub = Stub { _ in .json(status: 200, body: body) }
    let cache = InMemoryGraphQLCache()
    let (client, _) = cachingClient(stub, cache: cache)
    #expect(await client.cachedVenues() == nil)

    _ = try await client.venues()

    // A relaunch: a new session that hasn't learned the audience's schema shape still finds the list.
    let offline = Stub { _ in .failure(URLError(.notConnectedToInternet)) }
    let (relaunched, _) = cachingClient(offline, cache: cache)
    let kept = try #require(await relaunched.cachedVenues())
    #expect(kept.map(\.id) == ["v-1"])
    #expect(offline.requests.isEmpty)
    #expect(await relaunched.cachedVenues(maxAge: -1) == nil)
}
