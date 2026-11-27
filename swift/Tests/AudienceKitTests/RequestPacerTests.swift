@testable import AudienceCore
import Foundation
import Testing
@testable import AudienceKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite struct RequestPacing {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func sendsABurstThenMakesTheRestWaitTheirTurn() {
        var pacer = RequestPacer(burst: 3, perSecond: 2)
        #expect((0 ..< 3).map { _ in pacer.admit(now: start) } == [.send, .send, .send])
        #expect(pacer.admit(now: start) == .wait(0.5))
        #expect(pacer.admit(now: start.addingTimeInterval(0.5)) == .send)
    }

    @Test func holdsEveryRequestForRetryAfterOnA429() {
        var pacer = RequestPacer()
        pacer.observe(status: 429, retryAfter: "30", now: start, jitter: 0)
        #expect(pacer.admit(now: start.addingTimeInterval(10)) == .paused(retryAfter: 20))
        #expect(pacer.pausedUntil(now: start) == start.addingTimeInterval(30))
        #expect(pacer.admit(now: start.addingTimeInterval(30)) == .send)
    }

    @Test func backsOffExponentiallyWithoutRetryAfterAndStopsAtTheMaximum() {
        var pacer = RequestPacer(maximumBackoff: 10)
        var waits: [Date?] = []
        for _ in 0 ..< 6 {
            pacer.observe(status: 429, retryAfter: nil, now: start, jitter: 0)
            waits.append(pacer.pausedUntil(now: start))
        }
        #expect(waits.map { $0?.timeIntervalSince(start) } == [1, 2, 4, 8, 10, 10])
    }

    @Test func a503WaitsOnlyWhenItSaysHowLong() {
        var pacer = RequestPacer()
        pacer.observe(status: 503, retryAfter: nil, now: start, jitter: 0)
        #expect(pacer.pausedUntil(now: start) == nil)
        pacer.observe(status: 503, retryAfter: "5", now: start, jitter: 0)
        #expect(pacer.pausedUntil(now: start) == start.addingTimeInterval(5))
    }

    @Test func anyOtherAnswerEndsTheStreak() {
        var pacer = RequestPacer()
        pacer.observe(status: 429, retryAfter: nil, now: start, jitter: 0)
        pacer.observe(status: 429, retryAfter: nil, now: start, jitter: 0)
        pacer.observe(status: 200, retryAfter: nil, now: start.addingTimeInterval(5), jitter: 0)
        pacer.observe(status: 429, retryAfter: nil, now: start.addingTimeInterval(5), jitter: 0)
        #expect(pacer.pausedUntil(now: start.addingTimeInterval(5)) == start.addingTimeInterval(6))
    }

    @Test func readsRetryAfterAsSecondsOrAnHTTPDate() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        #expect(RequestPacer.seconds(formatter.string(from: start.addingTimeInterval(45)), now: start) == 45)
        #expect(RequestPacer.seconds("12", now: start) == 12)
        #expect(RequestPacer.seconds("soon", now: start) == nil)
    }

    @Test func aSessionStopsCallingTheAPIAfterA429UntilRetryAfter() async throws {
        let stub = Stub { _ in .json(status: 429, body: #"{"error":"RATE_LIMITED","message":"Slow down"}"#) }
        let configuration = AudienceKitConfiguration(baseURL: stub.baseURL, host: "hotmess.admin.audiencekit.com")
        let client = AudienceKitClient(configuration: configuration, session: stub.session)
        let request = APIRequest(path: "/v1/status", authenticated: false)

        for _ in 0 ..< 5 {
            await #expect(throws: AudienceKitError.self) { try await client.data(for: request) }
        }

        #expect(stub.requests.count == 1)
        let paused = try #require(await client.pausedUntil())
        #expect(paused > Date())
    }
}
