@testable import AudienceCore
import Foundation
import Testing
@testable import AudienceKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let showAudienceID = "00000000-0000-4000-8000-000000000001"

private func showClient(_ stub: Stub) -> AudienceKitClient {
    let endpoint = URL(string: GraphQLEndpoint.consumer.path(audienceID: showAudienceID), relativeTo: stub.baseURL)!
        .absoluteURL
    let store = InMemoryCredentialStore(credential: Credential(token: "session-token", userId: "u-1",
                                                               audienceId: showAudienceID, role: "member",
                                                               endpoint: endpoint))
    let configuration = AudienceKitConfiguration(baseURL: stub.baseURL, host: "hotmess.admin.audiencekit.com",
                                                 audienceID: showAudienceID, facebookAppID: "100000000000001",
                                                 environment: .production)
    return AudienceKitClient(configuration: configuration, credentialStore: store, session: stub.session)
}

private let round = """
{"id":"t-1","statement":"RuPaul once fronted a punk band.","choices":[{"label":"Myth","count":1},{"label":"Legend","count":3}],
 "myChoice":"Legend","voting":true,"closesAt":"2026-10-22T05:01:30Z","answer":null,"roomCall":null,"reveal":null,
 "revealsAtEnd":true,"revealedAt":null,"message":{"id":"m-9"}}
"""

private let showJSON = """
{"data":{"venues":{"venue":{"id":"v-1",
  "people":{"runningOrder":{"nodes":[
    {"id":"pre","entryKind":"SEGMENT","activity":"TRIVIA","curtainCallMinutes":null,"estimatedMinutes":null,
     "projectedStartsAt":"2026-10-22T05:00:00Z","projectedEndsAt":null,"lateMinutes":null,"scenes":[]},
    {"id":"set","entryKind":"ACT","activity":null,"curtainCallMinutes":5,"estimatedMinutes":20,
     "projectedStartsAt":"2026-10-22T05:37:00Z","projectedEndsAt":"2026-10-22T05:57:00Z","lateMinutes":7,
     "scenes":[{"id":"sc-1","title":"Opener","lengthSeconds":180,"performer":{"id":"p-1","name":"Contessa","avatarUrl":null}},
               {"id":"sc-2","title":"Lip sync","lengthSeconds":null,"performer":null}]},
    {"id":"new","entryKind":"SOMETHING_NEW","activity":"KARAOKE_BATTLE","scenes":null}
  ]},
  "curtainReadiness":{"act":{"id":"set"},"verdict":"PENDING","counts":[{"area":"VENUE","ready":1,"total":1},
    {"area":"TALENT","ready":0,"total":2}]}},
  "trivia":{"current":\(round)}
}}}}
"""

@Suite struct ShowControlTests {
    @Test func readsTheShowWithScenesTimesReadinessAndTrivia() async throws {
        let stub = Stub { _ in .json(status: 200, body: showJSON) }
        let show = try #require(try await showClient(stub).show(venueID: "v-1"))

        #expect(show.entries.map(\.kind) == [.segment, .act, .unknown])
        #expect(show.entries.first?.runsTrivia == true)
        #expect(show.entries.last?.activity == .unknown && show.entries.last?.scenes == [])
        let set = try #require(show.entries.first { $0.id == "set" })
        #expect(set.curtainCallMinutes == 5 && set.estimatedMinutes == 20 && set.lateMinutes == 7)
        #expect(set.scenes.map(\.title) == ["Opener", "Lip sync"] && set.scenes.first?.performer?.name == "Contessa")
        #expect(set.projectedStartsAt == ISO8601DateFormatter().date(from: "2026-10-22T05:37:00Z"))
        #expect(show.curtain == CurtainReadiness(actID: "set", verdict: .pending,
                                                  counts: [ReadinessCount(area: .venue, ready: 1, total: 1),
                                                           ReadinessCount(area: .talent, ready: 0, total: 2)]))
        let trivia = try #require(show.trivia)
        #expect(trivia.question == "Myth or Legend?" && trivia.totalVotes == 4 && trivia.messageID == "m-9")
        #expect(trivia.revealsAtEnd && !trivia.isRevealed && trivia.myChoice == "Legend")
        #expect(trivia.share(of: trivia.choices[1]) == 0.75)
    }

    @Test func votesInATriviaRound() async throws {
        let stub = Stub { _ in .json(status: 200, body: #"{"data":{"voteTrivia":{"round":\#(round)}}}"#) }
        let voted = try await showClient(stub).voteTrivia(roundID: "t-1", choice: "Legend")

        let body = try #require(stub.requests.first).jsonBody()
        #expect(body["variables"] as? [String: String] == ["roundId": "t-1", "choice": "Legend"])
        #expect((body["query"] as? String)?.contains("voteTrivia(input:") == true)
        #expect(voted.myChoice == "Legend")
    }
}
