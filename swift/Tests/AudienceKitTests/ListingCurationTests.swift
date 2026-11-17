import AudienceCore
import Foundation
import Testing

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(json.utf8))
}

@Test func deletingAVenueSendsItsID() throws {
    #expect(ListingCuration.deleteMutation.contains("deleteVenue(input: { id: $id }) { deletedId }"))
    #expect(ListingCuration.deleteVariables(id: "v-1") == ["id": .string("v-1")])
    #expect(try decode(ListingCuration.DeleteResponse.self, #"{"deleteVenue":{"deletedId":"v-1"}}"#).deletedID == "v-1")
    #expect(try decode(ListingCuration.DeleteResponse.self, #"{"deleteVenue":null}"#).deletedID == nil)
    #expect(ListingCuration.deletePersonMutation.contains("deletePerson(input: { id: $id }) { deletedId }"))
    #expect(try decode(ListingCuration.DeleteResponse.self, #"{"deletePerson":{"deletedId":"p-1"}}"#).deletedID == "p-1")
}

@Test func aMergeSendsTheFieldsToTakeInTheSchemasOrder() throws {
    #expect(ListingCuration.mergeMutation.contains("takeFromSource: $takeFromSource"))
    #expect(ListingCuration.mergeVariables(sourceID: "a", destinationID: "b", takeFromSource: [.website, .name])
        == ["sourceId": .string("a"), "destinationId": .string("b"),
            "takeFromSource": .array([.string("NAME"), .string("WEBSITE")])])
    #expect(ListingCuration.mergeVariables(sourceID: "a", destinationID: "b")["takeFromSource"] == .array([]))

    let response = try decode(ListingCuration.MergeResponse.self, """
        {"mergeVenue":{"deletedId":"a","venue":{"id":"b","name":"The Edge"},
         "moved":[{"kind":"events","count":3},{"kind":"taggings","count":2}]}}
        """)
    #expect(response.deletedID == "a")
    #expect(response.venue == .init(id: "b", name: "The Edge"))
    #expect(response.movedCount == 5)
    #expect(try decode(ListingCuration.MergeResponse.self, #"{"mergeVenue":null}"#).moved.isEmpty)
}

@Test func duplicatesDecodeWithTheirReasons() throws {
    let response = try decode(ListingCuration.DuplicatesResponse.self, """
        {"venues":{"duplicates":[{"distance":40,"reasons":["SAME_PLACE","SOMETHING_NEW"],
         "keep":{"id":"k","name":"The Edge"},"merge":{"id":"m","name":"Edge NYC"}}]}}
        """)
    let pair = try #require(response.duplicates.first)
    #expect(pair.id == "k:m")
    #expect(pair.reasons == [.samePlace, .unknown])
    #expect(pair.reasonLine == "Same Google place · Looks alike · 40 m apart")
    #expect(try decode(ListingCuration.DuplicatesResponse.self, #"{"venues":{"duplicates":null}}"#).duplicates.isEmpty)

    #expect(ListingCuration.dismissVariables(pair, note: "  ")
        == ["input": .object(["venueIds": .array([.string("k"), .string("m")])])])
    #expect(ListingCuration.dismissVariables(pair, note: " Two floors ")["input"]
        == .object(["venueIds": .array([.string("k"), .string("m")]), "note": .string("Two floors")]))
}

@Test func theCopyNamesTheVenues() {
    #expect(ListingCurationCopy.deleteTitle("The Edge") == "Delete The Edge?")
    #expect(ListingCurationCopy.deleteDetail("The Edge").hasPrefix("The Edge and all of its events will be deleted."))
    #expect(ListingCurationCopy.mergeTitle(from: "Edge NYC", into: "The Edge") == "Merge Edge NYC into The Edge?")
    #expect(ListingCurationCopy.merged(from: "A", into: "B") == "A is merged into B.")
    #expect(ListingCurationCopy.deleted("A") == "A is deleted.")
    #expect(VenueMergeField.offered.map(\.title) == ["Name", "Description", "Website", "Photo", "Location", "Locale"])
}
