@testable import AudienceCore
import Foundation
import Testing
@testable import AudienceKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let rollUpAudienceID = "00000000-0000-4000-8000-000000000728"

private func rollUpClient(_ stub: Stub) -> AudienceKitClient {
    let endpoint = URL(string: GraphQLEndpoint.consumer.path(audienceID: rollUpAudienceID),
                       relativeTo: stub.baseURL)!.absoluteURL
    let store = InMemoryCredentialStore(credential: Credential(token: "session-token", userId: "u-1",
                                                               audienceId: rollUpAudienceID, role: "member",
                                                               endpoint: endpoint))
    let configuration = AudienceKitConfiguration(baseURL: stub.baseURL, audienceID: rollUpAudienceID)
    return AudienceKitClient(configuration: configuration, credentialStore: store, session: stub.session)
}

private extension RecordedRequest {
    var query: String { ((try? jsonBody())?["query"] as? String) ?? "" }
    var variables: [String: Any] { ((try? jsonBody())?["variables"] as? [String: Any]) ?? [:] }
}

private let rollUpJSON = #"""
{"data":{"node":{"rollUp":[
 {"id":"link-1","status":"LINKED","origin":"FUZZY","score":0.9,
  "event":{"id":"e-1","name":"Dirty Pop","startAt":"2025-12-18T04:00:00Z"},
  "item":{"__typename":"Track","id":"t-1","title":"DIRTY POP 12/17/25 LIVE AT THE DALLAS EAGLE",
   "providerUrl":"https://officialdirtypop.podomatic.com/episodes/1","streamUrl":"https://cdn.example/1.mp3",
   "artworkUrl":null,"releasedAt":"2025-12-18T10:02:11Z"}},
 {"id":"link-2","status":"LINKED","origin":"MANUAL","score":null,"event":null,
  "item":{"__typename":"MediaTitle","id":"m-1","filmTitle":"Paris Is Burning","year":1990,
   "filmImdbUrl":"https://www.imdb.com/title/tt0100332/"}},
 {"id":"link-3","status":"LINKED","origin":"MANUAL","score":null,"event":null,
  "item":{"__typename":"Hologram","id":"h-1"}}
]}}}
"""#

@Test func rollUpDecodesEachKindOfItemFlat() async throws {
    let stub = Stub { _ in .json(status: 200, body: rollUpJSON) }

    let items = try await rollUpClient(stub).rollUp(id: "venue-1", kinds: [.track, .mediaTitle])

    #expect(items.map(\.id) == ["link-1", "link-2", "link-3"])
    let episode = try #require(items.first)
    #expect(episode.kind == .track)
    #expect(episode.itemID == "t-1")
    #expect(episode.streamUrl == "https://cdn.example/1.mp3")
    #expect(episode.url == "https://officialdirtypop.podomatic.com/episodes/1")
    #expect(episode.event?.name == "Dirty Pop")
    #expect(episode.subtitle == "Dirty Pop")
    #expect(episode.isMatched)
    #expect(episode.score == 0.9)
    #expect(episode.publishedAt == ISO8601.date(from: "2025-12-18T10:02:11Z"))

    let film = items[1]
    #expect(film.kind == .mediaTitle)
    #expect(film.subtitle == "1990")
    #expect(film.url == "https://www.imdb.com/title/tt0100332/")
    #expect(!film.isMatched)
    #expect(items[2].kind == nil)

    let request = try #require(stub.requests.first)
    #expect(request.query.contains("... on Venue { rollUp("))
    #expect(request.query.contains("... on MediaTitle { id filmTitle: title year filmImdbUrl: imdbUrl }"))
    #expect(request.variables["id"] as? String == "venue-1")
    #expect(request.variables["kinds"] as? [String] == ["TRACK", "MEDIA_TITLE"])
    #expect(request.variables["limit"] as? Int == 50)
    #expect(request.variables["statuses"] == nil)
}

@Test func rollUpLeavesOutTypesTheSchemaHasNot() {
    let shape = SchemaShape(fields: ["Venue": ["rollUp"], "Event": ["rollUp"], "Track": ["streamUrl"],
                                     "Person": ["avatarUrl"]])
    let document = Queries.rollUp(shape)
    #expect(document.contains("... on Venue {"))
    #expect(document.contains("... on Event {"))
    #expect(!document.contains("... on Locale {"))
    #expect(!document.contains("MediaTitle"))
    #expect(!document.contains("Article"))
    #expect(Queries.rollUp(SchemaShape(fields: ["Venue": ["name"]])) == "query RollUp { id }")
}

@Test func rollUpFromAnAPIWithoutItIsEmpty() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"node":null}}"#) }

    let items = try await rollUpClient(stub).rollUp(id: "venue-1", statuses: [.linked, .suggested])

    #expect(items.isEmpty)
    #expect(stub.requests.first?.variables["statuses"] as? [String] == ["LINKED", "SUGGESTED"])
}
