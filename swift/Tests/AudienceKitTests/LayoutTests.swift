@testable import AudienceCore
import Foundation
import Testing
@testable import AudienceKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let layoutAudienceID = "00000000-0000-4000-8000-000000000001"

private func layoutClient(_ stub: Stub) -> AudienceKitClient {
    let endpoint = URL(string: GraphQLEndpoint.consumer.path(audienceID: layoutAudienceID), relativeTo: stub.baseURL)!
        .absoluteURL
    let store = InMemoryCredentialStore(credential: Credential(token: "session-token", userId: "u-1",
                                                               audienceId: layoutAudienceID, role: "member",
                                                               endpoint: endpoint))
    let configuration = AudienceKitConfiguration(baseURL: stub.baseURL, host: "hotmess.admin.audiencekit.com",
                                                 audienceID: layoutAudienceID, facebookAppID: "100000000000001",
                                                 environment: .production)
    return AudienceKitClient(configuration: configuration, credentialStore: store, session: stub.session)
}

private let promo = """
{"id":"pp-1","category":"health","label":"Promoted","sponsorName":"Clinic","headline":"Free testing",
 "body":null,"imageUrl":"https://cdn.example/a.png","imageAlt":"A clinic","linkUrl":"https://clinic.example",
 "linkLabel":"Book","venue":null,"event":null}
"""

private let layoutJSON = """
{"data":{"layout":{"id":"lay-1","refreshAfter":60,"cards":[
  {"id":"now.chat:v-1","kind":"now.chat","rank":2,"title":null,"event":{"id":"e-1"},"venue":{"id":"v-1"},"locale":null},
  {"id":"now.stage:e-1","kind":"now.stage","rank":1,"title":null,"stageEvent":{"id":"e-1"},"venue":{"id":"v-1"}},
  {"id":"promo.slot:1","kind":"promo.slot","rank":3,"title":null,"candidates":[\(promo),
    {"id":"pp-2","category":"charity","label":"Charity","sponsorName":"Trevor","headline":"Donate",
     "venue":null,"event":null},{"id":"pp-bad"}]},
  {"id":"venues.nearby","kind":"venues.nearby","rank":4,"title":"Near you","venues":[{"id":"v-2"},{"id":"v-3"}],
   "locale":{"id":"l-1"}},
  {"id":"web:1","kind":"web","rank":5,"title":null,"headline":"Pride weekend","body":"Schedule","imageUrl":null,
   "imageAlt":null,"linkUrl":"https://hotmess.social/pride","linkLabel":"See it"},
  {"id":"future:1","kind":"future.thing","rank":6,"title":null}
]}}}
"""

@Suite struct LayoutTests {
    @Test func readsTheLayoutInRankOrder() async throws {
        let stub = Stub { _ in .json(status: 200, body: layoutJSON) }
        let layout = try await layoutClient(stub).layout(screen: .now, cardKinds: ["now.stage", "now.chat"],
                                                         position: Coordinate(latitude: 37.7, longitude: -122.4),
                                                         localeID: "l-1", appVersion: "2.3.0")

        #expect(layout.id == "lay-1" && !layout.isFallback && layout.refreshAfter == 60)
        #expect(layout.cards.map(\.kind) == ["now.stage", "now.chat", "promo.slot", "venues.nearby", "web",
                                             "future.thing"])
        let stage = layout.cards[0]
        #expect(stage.eventID == "e-1" && stage.venueID == "v-1")
        #expect(layout.card("venues.nearby")?.venueIDs == ["v-2", "v-3"])
        #expect(layout.card("venues.nearby")?.title == "Near you")
        #expect(layout.card("web")?.web?.headline == "Pride weekend")
        #expect(layout.card("now.chat")?.web == nil)
        // The candidate missing its fields is dropped, not the slot.
        #expect(layout.card("promo.slot")?.candidates.map(\.id) == ["pp-1", "pp-2"])
        #expect(layout.card("promo.slot")?.candidates.first?.content.linkLabel == "Book")

        let body = try #require(stub.requests.first).jsonBody()
        let variables = try #require(body["variables"] as? [String: Any])
        #expect(variables["screen"] as? String == "NOW")
        #expect(variables["localeId"] as? String == "l-1")
        let client = try #require(variables["client"] as? [String: Any])
        #expect(client["cardKinds"] as? [String] == ["now.stage", "now.chat"])
        #expect(client["appVersion"] as? String == "2.3.0")
    }

    @Test func layoutClientSkipsKindsTheAppDidNotList() async throws {
        let stub = Stub { _ in .json(status: 200, body: layoutJSON) }
        let client = LayoutClient(session: layoutClient(stub), screen: .now,
                                  cardKinds: ["now.stage", "now.chat", "promo.slot", "web"], fallback: ["now.stage"])
        let layout = await client.load()

        #expect(layout.cards.map(\.kind) == ["now.stage", "now.chat", "promo.slot", "web"])
    }

    @Test func layoutClientFallsBackOnAnError() async throws {
        let stub = Stub { _ in .json(status: 500, body: "{}") }
        let client = LayoutClient(session: layoutClient(stub), screen: .venues, cardKinds: ["venues.all"],
                                  fallback: ["venues.all", "venues.thinCity"])
        let layout = await client.load()

        #expect(layout.isFallback && layout.id == nil)
        #expect(layout.cards.map(\.kind) == ["venues.all", "venues.thinCity"])
        #expect(layout.cards.allSatisfy(\.isFallback))
    }

    @Test func registryDrawsKnownKindsOnly() {
        var registry = CardRegistry<String>()
        registry.register("now.stage") { _ in "stage" }
        registry.register("promo.slot") { $0.promo(.none).map(\.content.headline) }

        let layout = CardLayout(id: "l", cards: [
            LayoutCard(id: "a", kind: "now.stage", rank: 1),
            LayoutCard(id: "b", kind: "mystery", rank: 2),
            LayoutCard(id: "c", kind: "promo.slot", rank: 3),
        ])
        #expect(registry.kinds == ["now.stage", "promo.slot"])
        // An empty slot draws nothing.
        #expect(registry.render(layout).map { $0.rendered } == ["stage"])
    }

    @Test func filterHidesOnlyHideableCategories() {
        let content = CardContent(headline: "x")
        let card = LayoutCard(id: "s", kind: "promo.slot", rank: 1, candidates: [
            PromoCard(id: "1", category: "venue", label: "Promoted", sponsorName: "Bar", content: content),
            PromoCard(id: "2", category: "health", label: "Promoted", sponsorName: "Clinic", content: content),
        ])
        let categories = [CardCategory(key: "venue", label: "Venues", description: "", hideable: false),
                          CardCategory(key: "health", label: "Health", description: "", hideable: true)]

        #expect(card.promo(CardFilter(hidden: ["health"], categories: categories))?.id == "1")
        // Venues can't be turned off, even if they were before the audience said so.
        #expect(card.promo(CardFilter(hidden: ["venue"], categories: categories))?.id == "1")
        // Until the categories load, every hidden one is honoured.
        #expect(card.promo(CardFilter(hidden: ["venue"]))?.id == "2")
        #expect(card.promo(CardFilter(hidden: ["venue", "health"])) == nil)
    }

    @Test func recordsCardViews() async throws {
        let stub = Stub { _ in .json(status: 200, body: #"{"data":{"recordCardViews":{"recorded":2}}}"#) }
        let recorded = try await layoutClient(stub).recordCardViews(promoIDs: ["pp-1", "pp-2"], layoutID: "lay-1")

        #expect(recorded == 2)
        let body = try #require(stub.requests.first).jsonBody()
        let variables = try #require(body["variables"] as? [String: Any])
        #expect(variables["promoIds"] as? [String] == ["pp-1", "pp-2"] && variables["layoutId"] as? String == "lay-1")
    }

    @Test func preferencesKeepHiddenCategoriesOnTheDevice() throws {
        let defaults = try #require(UserDefaults(suiteName: "layout-tests-\(UUID().uuidString)"))
        let preferences = CardPreferences(defaults: defaults, cloud: false)

        preferences.setHidden("health", true)
        preferences.setHidden("charity", true)
        preferences.setHidden("charity", false)
        #expect(preferences.hidden == ["health"])
        #expect(CardPreferences(defaults: defaults, cloud: false).isHidden("health"))
        preferences.reset()
        #expect(preferences.hidden.isEmpty)
    }
}
