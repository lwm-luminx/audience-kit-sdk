@testable import AudienceCore
import Foundation
import Testing
@testable import AudienceKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let flyersAudienceID = "00000000-0000-4000-8000-000000000002"

private func flyersClient(_ stub: Stub) -> AudienceKitClient {
    let endpoint = URL(string: GraphQLEndpoint.consumer.path(audienceID: flyersAudienceID), relativeTo: stub.baseURL)!
        .absoluteURL
    let store = InMemoryCredentialStore(credential: Credential(token: "session-token", userId: "u-1",
                                                               audienceId: flyersAudienceID, role: "member",
                                                               endpoint: endpoint))
    let configuration = AudienceKitConfiguration(baseURL: stub.baseURL, host: "hotmess.admin.audiencekit.com",
                                                 audienceID: flyersAudienceID, facebookAppID: "100000000000001",
                                                 environment: .production)
    return AudienceKitClient(configuration: configuration, credentialStore: store, session: stub.session)
}

private func scratchDefaults() -> UserDefaults {
    let name = "flyers-\(UUID().uuidString)"
    return UserDefaults(suiteName: name)!
}

private let flyersLayout = """
{"data":{"layout":{"id":"lay-9","refreshAfter":60,"cards":[
  {"id":"flyers:l-1","kind":"flyers","rank":1,"title":null,"locale":{"id":"l-1"},
   "disclosure":"Based on your city and the time, nothing else.","explainerLabel":"What's a digital flyer?",
   "explainerUrl":"https://audiencekit.com/digital-flyers/","flyers":[
     {"id":"f-1","headline":"Free food","body":null,"linkUrl":null,"linkLabel":null,"tags":["food"],"tone":"gentle",
      "category":"food","lines":["Just a flyer for Salt Lake City. No idea who you are. Here if you need it."],
      "resource":{"id":"r-1","title":"Pantry","sensitive":false}},
     {"id":"f-2","headline":"Drag bingo","body":"Friday","linkUrl":"https://x.example","linkLabel":"Go",
      "tags":["events"],"tone":"playful","category":"community","lines":["a","b","c"],"resource":null}
   ]}
]}}}
"""

private let directoryJSON = """
{"locale":{"id":"l-1","name":"Salt Lake City"},"generated_at":"2026-11-15T22:00:00Z",
 "resources":[
  {"id":"r-1","title":"Utah Food Bank Mobile Pantry","name":"Utah Food Bank Mobile Pantry","neutral_title":null,
   "sensitive":false,"description":"Drive-through","facets":["food","no-id-required","secular"],"address":"3150 S 900 W",
   "latitude":40.7,"longitude":-111.9,"phone":"8019782452","text_number":null,"url":"https://utahfoodbank.org",
   "hours":[],"sessions":[{"days":[4],"note":"Thursdays"}],"intake_note":"No ID needed.","source_url":null,
   "checked_at":null,"locale_id":"l-1","next_session":{"session":{"days":[4]},"starts_at":"2026-11-19T07:00:00Z",
   "ends_at":"2026-11-20T06:59:59Z"}},
  {"id":"r-2","title":"Support services","name":"YWCA DV","neutral_title":"Support services","sensitive":true,
   "description":null,"facets":["dv-stalking","lgbtq-affirming"],"address":null,"latitude":null,"longitude":null,
   "phone":"18017778888","text_number":null,"url":null,"hours":[],"sessions":[],"intake_note":null,
   "source_url":null,"checked_at":"2026-11-15","locale_id":"l-1","next_session":null}
 ],
 "facets":["food","shelter","dv-stalking"],
 "needs":[{"key":"food","label":"I need food","facets":["food"]},
          {"key":"safe","label":"I don't feel safe at home","facets":["dv-stalking"]}],
 "advocacy":["No one deserves violence."],"quick_exit":"Leave now"}
"""

@Suite struct FlyersTests {
    @Test func readsTheFlyersCardAndAsksForItOnlyWhenTheServerHasIt() async throws {
        let stub = Stub { _ in .json(status: 200, body: flyersLayout) }
        let layout = try await flyersClient(stub).layout(screen: .now, cardKinds: [CardKind.flyers])
        let card = try #require(layout.card(CardKind.flyers))
        #expect(card.localeID == "l-1")
        let flyers = try #require(card.flyers)
        #expect(flyers.disclosure == "Based on your city and the time, nothing else.")
        #expect(flyers.flyers.map(\.id) == ["f-1", "f-2"])
        #expect(flyers.flyers[0].isGentle && flyers.flyers[0].resource?.title == "Pantry")
        let query = try #require(stub.requests.first?.jsonBody()["query"] as? String)
        #expect(query.contains("... on FlyersCard"))

        let shape = SchemaShape(fields: ["PromoCard": ["staffApp"]])
        #expect(!Queries.layout(shape).contains("FlyersCard"))
        #expect(Queries.layout(SchemaShape(fields: ["FlyersCard": ["flyers"]])).contains("... on FlyersCard"))
    }

    @Test func keepsDismissalsOnThePhone() throws {
        let defaults = scratchDefaults()
        let dismissals = FlyerDismissals(defaults: defaults)
        let food = DigitalFlyer(id: "f-1", headline: "Food", category: "food")
        let bingo = DigitalFlyer(id: "f-2", headline: "Bingo", category: "community")
        let other = DigitalFlyer(id: "f-3", headline: "Karaoke", category: "community")
        let card = FlyersCardContent(disclosure: "d", explainerLabel: "e", explainerUrl: "u", flyers: [food, bingo, other])

        dismissals.dismiss(bingo)
        #expect(card.visible(dismissals).map(\.id) == ["f-1", "f-3"])
        dismissals.setHidden(category: "food", true)
        #expect(card.visible(dismissals).map(\.id) == ["f-3"])
        #expect(FlyerDismissals(defaults: defaults).hiddenCategories == ["food"])
        dismissals.setHidden(category: "food", false)
        dismissals.reset()
        #expect(card.visible(dismissals).count == 3)

        for index in 0 ..< (FlyerDismissals.limit + 5) {
            dismissals.dismiss(DigitalFlyer(id: "x-\(index)", headline: "x"))
        }
        #expect(dismissals.dismissedFlyers.count == FlyerDismissals.limit)
        #expect(!dismissals.dismissedFlyers.contains("x-0"))
    }

    @Test func neverShowsTheSameLineTwiceInARow() {
        let flyer = DigitalFlyer(id: "f", headline: "h", lines: ["a", "b", "c"])
        let picker = FlyerLinePicker(defaults: scratchDefaults())
        var last: String?
        for _ in 0 ..< 200 {
            let line = picker.line(for: flyer)
            #expect(line != nil && line != last)
            last = line
        }
        var generator = SystemRandomNumberGenerator()
        #expect(FlyerLinePicker.pick(from: ["only"], last: "only", using: &generator) == "only")
        #expect(FlyerLinePicker.pick(from: [], last: nil, using: &generator) == nil)
    }

    @Test func fetchesTheDirectoryWithoutTheSessionTokenAndFiltersOnThePhone() async throws {
        let stub = Stub { _ in .json(status: 200, body: directoryJSON) }
        let directory = try await flyersClient(stub).communityDirectory(localeID: "l-1")

        let request = try #require(stub.requests.first)
        #expect(request.url.path == "/v1/audience/\(flyersAudienceID)/community_resources")
        #expect(request.url.query == "locale_id=l-1")
        #expect(request.header("Authorization") == nil)

        #expect(directory.locale.name == "Salt Lake City")
        #expect(directory.resources(for: directory.needs[0]).map(\.id) == ["r-1"])
        let safe = directory.resources(for: directory.needs[1])
        #expect(safe.map(\.title) == ["Support services"] && safe[0].sensitive)
        #expect(directory.resources(withAnyOf: [], alsoRequiring: ["no-id-required"]).map(\.id) == ["r-1"])
        #expect(directory.resources[0].sessions.first?.note == "Thursdays")
        #expect(directory.resources[0].nextSession?.startsAt == "2026-11-19T07:00:00Z")
        #expect(directory.quickExit == "Leave now")
        #expect(stub.requests.count == 1)
    }

    @Test func readsTheFlyerCopy() async throws {
        let json = """
        {"data":{"flyerCopy":{"disclosure":"d","explainerLabel":"e","explainerUrl":"u","quickExit":"Leave now",
         "advocacy":["You deserve better."],"categories":[{"key":"food","label":"Food"}],
         "needs":[{"key":"food","label":"I need food","facets":["food"]}]}}}
        """
        let stub = Stub { _ in .json(status: 200, body: json) }
        let copy = try await flyersClient(stub).flyerCopy()
        #expect(copy.categories.map(\.key) == ["food"] && copy.needs.first?.facets == ["food"])
        #expect(copy.advocacy == ["You deserve better."])
    }
}
