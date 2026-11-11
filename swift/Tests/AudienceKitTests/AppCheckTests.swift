@testable import AudienceCore
import AudienceKitTesting
import Foundation
import Testing

private struct Page: Decodable, Sendable {
    struct Events: Decodable, Sendable { var nodes: [Node] }
    struct Node: Decodable, Sendable { var id: String }
    var events: Events
}

private let eventsQuery = "query Events($first: Int) { events(first: $first) { nodes { id } } }"

private func eventsPage(_ client: AudienceSession, first: Int) async throws -> [String] {
    try await client.graphQL(eventsQuery, variables: ["first": .int(first)], operationName: "Events",
                             as: Page.self).events.nodes.map(\.id)
}

private final class Forwarded: GraphQLMonitor, @unchecked Sendable {
    let lock = NSLock()
    var operations: [GraphQLOperationEvent] = []
    var sockets: [CableSocketEvent] = []
    func record(_ event: GraphQLOperationEvent) { lock.withLock { operations.append(event) } }
    func record(_ event: CableSocketEvent) { lock.withLock { sockets.append(event) } }
}

@Suite struct GraphQLStubTests {
    @Test func refusesAPageOverTheComplexityBudgetLikeTheAPI() async throws {
        let api = GraphQLStub(respond: GraphQLStub.withinComplexityBudget(perItem: 77) { _ in
            .data(#"{"events":{"nodes":[{"id":"e-1"}]}}"#)
        })
        #expect(try await eventsPage(api.client, first: 10) == ["e-1"])
        await #expect(throws: AudienceKitError.self) { try await eventsPage(api.client, first: 25) }
        #expect(api.requests.map { $0.int("first") } == [10, 25])
        #expect(api.requests.first?.operationName == "Events")
        #expect(api.requests.first?.query.contains("events(first: $first)") == true)
    }

    @Test func answersErrorsRawBodiesAndFailures() async throws {
        let errors = GraphQLStub { _ in .error(#"Not "authorized""#) }
        do {
            _ = try await eventsPage(errors.client, first: 1)
            Issue.record("expected an error")
        } catch {
            #expect(String(describing: error).contains("authorized"))
        }

        let raw = GraphQLStub { _ in .raw(status: 500, body: "{}") }
        await #expect(throws: (any Error).self) { try await eventsPage(raw.client, first: 1) }

        let offline = GraphQLStub { _ in .failure(URLError(.notConnectedToInternet)) }
        await #expect(throws: (any Error).self) { try await eventsPage(offline.client, first: 1) }
    }

    @Test func aSessionThatOutlivesItsStubIsTurnedAway() async throws {
        var api: GraphQLStub? = GraphQLStub { _ in .data(#"{"events":{"nodes":[]}}"#) }
        let client = try #require(api).client
        #expect(try await eventsPage(client, first: 1).isEmpty)
        api = nil
        await #expect(throws: (any Error).self) { try await eventsPage(client, first: 1) }
    }

    @Test func readsVariablesOfEitherNumberType() {
        let request = GraphQLStub.Request(operationName: nil, query: "", variables: ["a": 3, "b": 4.0, "c": "x"],
                                          headers: [:])
        #expect(request.int("a") == 3)
        #expect(request.int("b") == 4)
        #expect(request.int("c") == nil)
        #expect(request.string("c") == "x")
    }
}

@Suite struct GraphQLOperationLogTests {
    @Test func keepsFinishedOperationsAndTheirFailures() async throws {
        let forwarded = Forwarded()
        let log = GraphQLOperationLog(subsystem: "com.audiencekit.tests", capacity: 3, forwardingTo: forwarded)
        let api = GraphQLStub(respond: GraphQLStub.withinComplexityBudget(perItem: 77) { _ in
            .data(#"{"events":{"nodes":[]}}"#)
        })
        let client = api.client(monitor: log)
        _ = try await eventsPage(client, first: 5)
        _ = try? await eventsPage(client, first: 50)

        #expect(log.entries.map(\.name) == ["Events", "Events"])
        #expect(log.entries[0].failed == false)
        #expect(log.entries[0].milliseconds != nil)
        #expect(log.failures().count == 1)
        #expect(log.failures().first?.error?.contains("exceeds max complexity of 1000") == true)
        #expect(forwarded.operations.count == 2)
    }

    @Test func dropsTheOldestPastCapacityAndIgnoresCableProgress() {
        let log = GraphQLOperationLog(capacity: 2)
        for name in ["A", "B", "C"] {
            log.record(GraphQLOperationEvent(kind: .completed, name: name, type: "query", transport: .http,
                                             endpoint: .consumer, duration: .milliseconds(12)))
        }
        log.record(GraphQLOperationEvent(kind: .subscribed, name: "Chat", type: "subscription", transport: .cable,
                                         endpoint: .consumer))
        log.record(GraphQLOperationEvent(kind: .completed, name: nil, type: "mutation", transport: .http,
                                         endpoint: .consumer, error: "boom"))
        #expect(log.entries.map(\.name) == ["C", "mutation"])
        #expect(log.entries[0].milliseconds == 12)
        #expect(log.failures().map(\.name) == ["mutation"])
        log.clear()
        #expect(log.entries.isEmpty)
    }

    @Test func passesSocketEventsOn() {
        let forwarded = Forwarded()
        let log = GraphQLOperationLog(forwardingTo: forwarded)
        log.record(CableSocketEvent(kind: .connected, endpoint: .consumer, operations: 1))
        #expect(forwarded.sockets.count == 1)
        #expect(log.entries.isEmpty)
    }
}

@MainActor
@Suite struct AppCheckTests {
    @Test func recordsEachStepsOutcomeAndBuildsAReport() async {
        let check = AppCheck()
        var changes = 0
        check.onChange = { changes += 1 }
        let log = GraphQLOperationLog()
        log.record(GraphQLOperationEvent(kind: .completed, name: "Events", type: "query", transport: .http,
                                         endpoint: .consumer, error: "Query has complexity of 1928"))

        await check.run { check in
            let signedIn = await check.step("Signed in") { "As Pat." }
            #expect(signedIn == .ok)
            await check.step("Events") { nil }
            await check.step("Location") { throw AppCheck.Problem("Location is denied for this app.") }
            await check.step("Server") { throw AudienceKitError(code: "FORBIDDEN", message: "Not authorized") }
            check.skip("Representative page", because: "No one represents this place.")
        }

        #expect(check.steps.map(\.outcome) == [.ok, .empty, .failed, .failed, .skipped])
        #expect(check.steps[2].detail == "Location is denied for this app.")
        #expect(check.steps[3].detail.contains("Not authorized"))
        #expect(check.hasFailures)
        #expect(check.isRunning == false)
        #expect(changes >= 7)

        let report = check.report(title: "DNC demo 1.0, https://api.next.audiencekit.com", log: log)
        let lines = report.split(separator: "\n").map(String.init)
        #expect(lines.first == "DNC demo 1.0, https://api.next.audiencekit.com")
        #expect(lines[1].hasPrefix("OK Signed in ("))
        #expect(lines[2].hasPrefix("EMPTY Events"))
        #expect(lines[5] == "SKIP Representative page (0 ms): No one represents this place.")
        #expect(lines.suffix(2) == ["Failed requests:", "- Events: Query has complexity of 1928"])
    }

    @Test func aNewRunStartsClean() async {
        let check = AppCheck()
        await check.run { await $0.step("One") { "1" } }
        await check.run { await $0.step("Two") { "2" } }
        #expect(check.steps.map(\.name) == ["Two"])
        #expect(check.hasFailures == false)
        #expect(check.report(title: "App") == "App\nOK Two (\(check.steps[0].milliseconds) ms): 2")
    }

    @Test func describesAnErrorWithoutItsOwnSentence() async {
        struct Opaque: Error {}
        let check = AppCheck()
        await check.run { await $0.step("Odd") { throw Opaque() } }
        #expect(check.steps.first?.detail.contains("Opaque") == true)
    }
}
