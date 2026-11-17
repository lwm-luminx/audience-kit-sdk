import AudienceCore
import Foundation
import Testing

private let draftNode = """
    {"id":"lr-1","state":"DONE","kind":"PERSON","query":"spokane pride","found":true,"name":"Spokane Pride",
     "summary":"OutSpokane runs Spokane Pride.","description":null,"website":"https://outspokane.org","city":"Spokane",
     "address":null,"phone":null,"googlePlaceId":null,"personKind":"ORGANIZATION","homeVenueName":null,"homeVenue":null,
     "locale":{"id":"loc-1"},"links":[{"provider":"instagram","handle":"outspokane","url":"https://instagram.com/outspokane"}],
     "evidence":[{"url":"https://outspokane.org","title":"OutSpokane"}],"matches":[],"error":null}
    """

@Test func listingResearchDecodesADraft() throws {
    let response = try JSONDecoder().decode(ListingResearch.ReadResponse.self,
                                            from: Data((#"{"listingResearch":"# + draftNode + "}").utf8))
    let draft = try #require(response.research)
    #expect(draft.state.isFinished)
    #expect(draft.kind == .person)
    #expect(draft.personKind == "ORGANIZATION")
    #expect(draft.locale?.id == "loc-1")
    #expect(draft.link("instagram") == "https://instagram.com/outspokane")
    #expect(draft.link("tiktok") == "")
    #expect(draft.socialLinks == .array([.object(["provider": .string("instagram"), "handle": .string("outspokane")])]))
}

@Test func listingResearchSomeoneElsesIsNil() throws {
    let response = try JSONDecoder().decode(ListingResearch.ReadResponse.self, from: Data(#"{"listingResearch":null}"#.utf8))
    #expect(response.research == nil)
}

@Test func listingResearchStartsWithWhatTheyTyped() {
    #expect(ListingResearch.startVariables(kind: .venue, query: "  Nyne Spokane ", localeID: "loc-1")
        == ["input": .object(["kind": .string("VENUE"), "query": .string("Nyne Spokane"), "localeId": .string("loc-1")])])
    #expect(ListingResearch.startVariables(kind: .person, query: "Dugan", localeID: nil)
        == ["input": .object(["kind": .string("PERSON"), "query": .string("Dugan")])])
    #expect(ListingResearch.startMutation.contains("researchListing(input: $input)"))
    #expect(ListingResearch.query.contains(ListingResearch.listingResearchFields))
    #expect(!ListingResearchState.running.isFinished)
}
