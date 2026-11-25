import Foundation
import Testing
import AudienceCore
@testable import StaffKitCore
@testable import StaffKitServices

private func chooserClient(_ stub: Stub) -> SoapboxClient {
    SoapboxClient(session: AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session))
}

@Test func thePublisherChooserListsPublicationsWithTheirPlaces() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"soapbox":{"myPublications":[{"id":"p1","name":"QSaltLake","masthead":null,"trust":"TRUSTED","person":{"id":"x1","name":"QSaltLake"},"locale":{"id":"l1","name":"Salt Lake City","ancestors":[{"id":"l0","name":"Utah"}],"location":{"point":"POINT (-111.891 40.7608)"}}},{"id":"p2","name":"Bayside Bulletin","masthead":null,"trust":"PENDING","person":null,"locale":null}]}}}"#) }
    let directory = try await chooserClient(stub).publisherDirectory()
    #expect(directory.entries.map(\.id) == ["p2", "p1"])
    #expect(directory.entry("p1")?.place == "Salt Lake City, Utah")
    let body = try #require(stub.requests.last).jsonBody()
    #expect((body["query"] as? String)?.contains("query SoapboxPublisherChooser") == true)
    #expect(try #require(stub.requests.last).path.hasSuffix("staffql"))
}

@Test func nearbyAsksWhichLocalesThePositionIsIn() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"locales":[{"id":"l0"},{"id":"l1"}]}}"#) }
    let ids = try await chooserClient(stub).localesContaining(Coordinate(latitude: 40.76, longitude: -111.89))
    #expect(ids == ["l0", "l1"])
    let body = try #require(stub.requests.last).jsonBody()
    let here = (body["variables"] as? [String: Any])?["here"] as? [String: Any]
    #expect(here?["latitude"] as? Double == 40.76)
}
