@testable import AudienceCore
import Foundation
import Testing
@testable import AudienceKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let contactAudienceID = "00000000-0000-4000-8000-000000000074"

private func contactClient(_ stub: Stub) -> AudienceKitClient {
    let endpoint = URL(string: GraphQLEndpoint.consumer.path(audienceID: contactAudienceID),
                       relativeTo: stub.baseURL)!.absoluteURL
    let store = InMemoryCredentialStore(credential: Credential(token: "session-token", userId: "u-1",
                                                               audienceId: contactAudienceID, role: "member",
                                                               endpoint: endpoint))
    let configuration = AudienceKitConfiguration(baseURL: stub.baseURL, audienceID: contactAudienceID)
    return AudienceKitClient(configuration: configuration, credentialStore: store, session: stub.session)
}

private extension RecordedRequest {
    var query: String { ((try? jsonBody())?["query"] as? String) ?? "" }
    var operationName: String? { (try? jsonBody())?["operationName"] as? String }
    var variables: [String: Any] { ((try? jsonBody())?["variables"] as? [String: Any]) ?? [:] }
}

private let jordanHash = "568bb17dbe82b2d378c7867777b9e84d8d128b7950fb137fc4e38f4ea808e33c"

private func stateJSON(enabled: Bool = false, verified: Bool = false, matches: String = "[]",
                       requests: String = "[]", available: String = "true") -> String
{
    """
    {"enabled":\(enabled),"phoneVerified":\(verified),"phoneNumber":\(verified ? "\"+12065550142\"" : "null"),\
    "firstName":"Danny","lastName":"Ortiz","codeResendAt":"2026-11-16T07:00:30Z","lastCheckedAt":null,\
    "nextCheckAt":"2026-11-16T07:00:00Z","contactsChecked":0,"textCodesAvailable":\(available),\
    "matches":\(matches),"incomingRequests":\(requests)}
    """
}

// MARK: - Hashing (the API's doc/CONTACT_FRIEND_MATCHING.md fixes these vectors; ContactHashingTest.kt has the same)

@Test func namesNormalizeAsTheAPIDoes() {
    #expect(ContactHashing.normalizeName(" José-Luis ") == "joseluis")
    #expect(ContactHashing.normalizeName("O'Brien") == "obrien")
    #expect(ContactHashing.normalizeName("ÅSA Öberg 2") == "asaoberg2")
    #expect(ContactHashing.normalizeName("ﬁona") == "fiona")
    #expect(ContactHashing.normalizeName("李") == "")
}

@Test func aContactHashesToTheDocumentedVector() {
    #expect(ContactHashing.hash(firstName: "José-Luis", lastName: "O'Brien", e164: "+12065550142")
        == "5e55a1b55a29bb89dcb5e2694e558276db8bed11535dc6c0d96db558acc35339")
    #expect(ContactHashing.hash(firstName: "Jordan", lastName: "Park", e164: "+12065550177") == jordanHash)
}

@Test func numbersBecomeE164WithThePhonesRegion() {
    #expect(ContactHashing.e164("(206) 555-0142", region: "US") == "+12065550142")
    #expect(ContactHashing.e164("1-206-555-0142", region: "us") == "+12065550142")
    #expect(ContactHashing.e164("+1 206 555 0142", region: "GB") == "+12065550142")
    #expect(ContactHashing.e164("206.555.0142 x12", region: "CA") == "+12065550142")
    #expect(ContactHashing.e164("011 44 20 7946 0958", region: "US") == "+442079460958")
    #expect(ContactHashing.e164("020 7946 0958", region: "GB") == "+442079460958")
    #expect(ContactHashing.e164("00 1 206 555 0142", region: "GB") == "+12065550142")
    #expect(ContactHashing.e164("0412 345 678", region: "AU") == "+61412345678")
    #expect(ContactHashing.e164("0011 44 20 7946 0958", region: "AU") == "+442079460958")
    #expect(ContactHashing.e164("55 1234 5678", region: "MX") == "+525512345678")
    #expect(ContactHashing.e164("044 55 1234 5678", region: "MX") == "+525512345678")
    #expect(ContactHashing.e164("01 55 1234 5678", region: "MX") == "+525512345678")
    #expect(ContactHashing.e164("06 1234 5678", region: "IT") == "+390612345678")
    #expect(ContactHashing.e164("8 (912) 345-67-89", region: "RU") == "+79123456789")
    #expect(ContactHashing.e164("06 30 123 4567", region: "HU") == "+36301234567")
    #expect(ContactHashing.e164("8 612 34567", region: "LT") == "+37061234567")
    #expect(ContactHashing.e164("8 029 123-45-67", region: "BY") == "+375291234567")
    #expect(ContactHashing.e164("٠٤١٢٣٤٥٦٧٨", region: "AU") == "+61412345678")
}

@Test func numbersThatCantBeReadAreSkipped() {
    #expect(ContactHashing.e164("555-0142", region: "US") == nil)
    #expect(ContactHashing.e164("(106) 555-0142", region: "US") == nil)
    #expect(ContactHashing.e164("(206) 155-0142", region: "US") == nil)
    #expect(ContactHashing.e164("206 555 0142", region: nil) == nil)
    #expect(ContactHashing.e164("206 555 0142", region: "ZZ") == nil)
    #expect(ContactHashing.e164("+0 123 456 789", region: "US") == nil)
    #expect(ContactHashing.e164("+44 12", region: "US") == nil)
    #expect(ContactHashing.e164("", region: "US") == nil)
    #expect(ContactHashing.callingCode(region: "gb") == "44")
    #expect(ContactHashing.callingCode(region: nil) == nil)
}

@Test func aBatchSkipsContactsWithoutAFullNameOrNumber() {
    let contacts = [
        DeviceContact(firstName: "Jordan", lastName: "Park", phoneNumbers: ["(206) 555-0177", "+1 206 555 0177"]),
        DeviceContact(firstName: "Mom", lastName: "", phoneNumbers: ["206-555-0100"]),
        DeviceContact(firstName: "Sam", lastName: "Lee", phoneNumbers: ["12"]),
        DeviceContact(firstName: "Rick", lastName: "Mark", phoneNumbers: ["206-555-0111", "020 7946 0958"]),
    ]

    let batch = ContactHashing.batch(contacts, region: "US")

    #expect(batch.contactCount == 2)
    #expect(batch.skippedWithoutFullName == 1)
    #expect(batch.skippedWithoutNumber == 1)
    #expect(batch.hashes.count == 2)
    #expect(Set(batch.hashes) == Set(batch.names.keys))
    #expect(batch.names[jordanHash] == "Jordan Park")
    #expect(ContactMatchingCopy.checked(batch) == "We checked 2 contacts and skipped 1 with only a first name.")
}

@Test func aBatchStopsAtTheLimit() {
    let contacts = (0 ..< 5).map {
        DeviceContact(firstName: "A\($0)", lastName: "B", phoneNumbers: ["20655501\(40 + $0)", "20655502\(40 + $0)"])
    }

    let batch = ContactHashing.batch(contacts, region: "US", limit: 5)

    #expect(batch.hashes.count == 4)
    #expect(batch.contactCount == 2)
    #expect(batch.skippedOverLimit == 3)
    #expect(ContactMatchingCopy.checked(batch) == "We checked 2 contacts.")
}

// MARK: - API calls

@Test func readingContactMatching() async throws {
    let request = #"{"id":"r-1","status":"PENDING","createdAt":"2026-11-16T06:00:00Z","user":{"id":"u-2","name":"Jordan P.","avatarUrl":null},"friend":{"id":"u-1","name":"Danny Ortiz","avatarUrl":null}}"#
    let matches = #"[{"status":"INCOMING","user":{"id":"u-2","name":"Jordan P.","avatarUrl":"/a.jpg"},"request":\#(request)}]"#
    let stub = Stub { _ in
        .json(status: 200, body: #"{"data":{"me":{"contactMatching":\#(stateJSON(enabled: true, verified: true, matches: matches, requests: "[\(request)]"))}}}"#)
    }

    let state = try await contactClient(stub).contactMatching()

    #expect(state.enabled && state.phoneVerified)
    #expect(state.phoneNumber == "+12065550142")
    #expect(state.matches.first?.status == .incoming)
    #expect(state.matches.first?.id == "u-2")
    #expect(state.matches.first?.contactHash == nil)
    #expect(state.incomingRequests.first?.user.name == "Jordan P.")
    #expect(state.incomingRequests.first?.status == .pending)
    #expect(state.addable.isEmpty)
    #expect(!state.canOffer)
    #expect(state.canCheck(now: ISO8601DateFormatter().date(from: "2026-11-16T08:00:00Z")!))
    #expect(!state.canCheck(now: ISO8601DateFormatter().date(from: "2026-11-16T06:00:00Z")!))
    let sent = try #require(stub.requests.first)
    #expect(sent.operationName == "ContactMatching")
    #expect(sent.query.contains("textCodesAvailable"))
    #expect(!sent.query.contains("contactHash"))
}

@Test func theOfferHidesWhenCodesCantBeTexted() {
    #expect(ContactMatching().canOffer)
    #expect(ContactMatching(textCodesAvailable: true).canOffer)
    #expect(!ContactMatching(textCodesAvailable: false).canOffer)
    #expect(!ContactMatching(enabled: true).canOffer)
    #expect(!ContactMatching().canCheck())
    #expect(ContactMatching(phoneVerified: true).canCheck())
}

@Test func anOlderAPIIsAskedWithoutTheNewFields() async throws {
    let stub = Stub { request in
        let query = ((try? request.jsonBody())?["query"] as? String) ?? ""
        if query.contains("__type") || query.contains("__schema") {
            return .json(status: 200, body: #"{"data":{"t0":{"fields":[{"name":"status"}]},"t1":{"fields":[{"name":"enabled"}]}}}"#)
        }
        if query.contains("textCodesAvailable") {
            return .json(status: 200, body: #"{"errors":[{"message":"Field 'textCodesAvailable' doesn't exist on type 'ContactMatching'","extensions":{"code":"undefinedField"}}]}"#)
        }
        return .json(status: 200, body: #"{"data":{"me":{"contactMatching":{"enabled":false,"phoneVerified":false,"contactsChecked":0,"matches":[],"incomingRequests":[]}}}}"#)
    }

    let state = try await contactClient(stub).contactMatching()

    #expect(state.textCodesAvailable == nil)
    #expect(state.canOffer)
    #expect(stub.requests.last?.query.contains("textCodesAvailable") == false)
}

@Test func verifyingANumber() async throws {
    let stub = Stub { request in
        let name = ((try? request.jsonBody())?["operationName"] as? String) ?? ""
        let key = name == "VerifyContactPhone" ? "verifyContactPhone" : "startContactPhoneVerification"
        return .json(status: 200, body: #"{"data":{"\#(key)":{"contactMatching":\#(stateJSON(verified: name == "VerifyContactPhone"))}}}"#)
    }
    let client = contactClient(stub)

    let started = try await client.startContactPhoneVerification(phoneNumber: "+12065550142", firstName: "Danny",
                                                                 lastName: "Ortiz")
    let verified = try await client.verifyContactPhone(code: "424242")

    #expect(!started.phoneVerified)
    #expect(started.codeResendAt == ISO8601DateFormatter().date(from: "2026-11-16T07:00:30Z"))
    #expect(verified.phoneVerified)
    #expect(stub.requests[0].variables["phoneNumber"] as? String == "+12065550142")
    #expect(stub.requests[0].variables["firstName"] as? String == "Danny")
    #expect(stub.requests[1].variables["code"] as? String == "424242")
}

@Test func checkingContactsRemembersWhatMatchesAreSavedAs() async throws {
    let matches = #"[{"status":"NONE","contactHash":"\#(jordanHash)","user":{"id":"u-2","name":"Jordan P.","avatarUrl":null},"request":null}]"#
    let stub = Stub { _ in
        .json(status: 200, body: #"{"data":{"checkContacts":{"matches":\#(matches),"contactMatching":\#(stateJSON(enabled: true, verified: true, matches: matches))}}}"#)
    }
    let defaults = UserDefaults(suiteName: "contact-names-\(UUID().uuidString)")!
    let names = ContactMatchNames(audienceID: contactAudienceID, defaults: defaults)
    let batch = ContactHashing.batch([DeviceContact(firstName: "Jordan", lastName: "Park",
                                                    phoneNumbers: ["206-555-0177"])], region: "US")

    let result = try await contactClient(stub).checkContacts(batch, names: names)

    #expect(result.matches.map(\.user.id) == ["u-2"])
    #expect(result.contactMatching.addable.count == 1)
    #expect(names.name(for: "u-2") == "Jordan Park")
    #expect(ContactMatchingCopy.savedAs(names.name(for: "u-2")!) == "In your contacts as Jordan Park")
    let sent = try #require(stub.requests.first)
    #expect(sent.operationName == "CheckContacts")
    #expect(sent.variables["hashes"] as? [String] == [jordanHash])
    #expect(sent.variables["contactCount"] as? Int == 1)
    #expect(sent.query.contains("contactHash"))

    names.record([], from: batch)
    #expect(names.name(for: "u-2") == nil)
}

@Test func requestsNamesAndTurningOff() async throws {
    let stub = Stub { request in
        let name = ((try? request.jsonBody())?["operationName"] as? String) ?? ""
        let key = name.prefix(1).lowercased() + name.dropFirst()
        return .json(status: 200, body: #"{"data":{"\#(key)":{"contactMatching":\#(stateJSON(enabled: name != "DisableContactMatching", verified: true))}}}"#)
    }
    let defaults = UserDefaults(suiteName: "contact-names-\(UUID().uuidString)")!
    let names = ContactMatchNames(audienceID: contactAudienceID, defaults: defaults)
    names.record([ContactMatch(user: Profile(id: "u-2", name: "Jordan P."), status: .none, contactHash: "h")],
                 from: ContactHashBatch(hashes: ["h"], contactCount: 1, names: ["h": "Jordan Park"]))
    let client = contactClient(stub)

    try await client.sendFriendRequest(userID: "u-2")
    try await client.respondToFriendRequest(id: "r-1", accept: false)
    try await client.setContactMatchName(firstName: "Daniel", lastName: "Ortiz")
    #expect(names.name(for: "u-2") == "Jordan Park")
    let off = try await client.disableContactMatching(names: names)

    #expect(!off.enabled)
    #expect(names.name(for: "u-2") == nil)
    #expect(stub.requests.map(\.operationName) == ["SendFriendRequest", "RespondToFriendRequest",
                                                   "SetContactMatchName", "DisableContactMatching"])
    #expect(stub.requests[0].variables["userId"] as? String == "u-2")
    #expect(stub.requests[1].variables["requestId"] as? String == "r-1")
    #expect(stub.requests[1].variables["accept"] as? Bool == false)
    #expect(stub.requests[2].variables["firstName"] as? String == "Daniel")
}

@Test func anAudienceWithoutMatchingThrows() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"me":null}}"#) }

    await #expect(throws: ContactMatchingUnavailable.self) { try await contactClient(stub).contactMatching() }
}

@Test func theCopyCountsFriends() {
    #expect(ContactMatchingCopy.friendsHere(1) == "1 friend is here")
    #expect(ContactMatchingCopy.friendsHere(4) == "4 friends are here")
    #expect(ContactMatchingCopy.addFriends(1) == "Add 1 friend")
    #expect(ContactMatchingCopy.addFriends(2) == "Add 2 friends")
}
