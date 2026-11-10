@testable import AudienceCore
import Foundation
import Testing
@testable import AudienceKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// The shared member calls apps build on: locales, tribes, cover passes, removing a chat message, promo views and a
// chat room's live stream.

private let servicesAudienceID = "00000000-0000-4000-8000-000000000002"

/// A client whose requests `stub` answers, signed in unless `signedIn` is false.
private func servicesClient(_ stub: Stub, signedIn: Bool = true) -> AudienceKitClient {
    let endpoint = URL(string: GraphQLEndpoint.consumer.path(audienceID: servicesAudienceID), relativeTo: stub.baseURL)!
        .absoluteURL
    let credential = Credential(token: "session-token", userId: "u-1", audienceId: servicesAudienceID, role: "member",
                                endpoint: endpoint)
    let store = InMemoryCredentialStore(credential: signedIn ? credential : nil)
    let configuration = AudienceKitConfiguration(baseURL: stub.baseURL, host: "hotmess.admin.audiencekit.com",
                                                 audienceID: servicesAudienceID, facebookAppID: nil,
                                                 environment: .production)
    return AudienceKitClient(configuration: configuration, credentialStore: store, session: stub.session)
}

private extension RecordedRequest {
    var query: String { ((try? jsonBody())?["query"] as? String) ?? "" }
    var operationName: String? { (try? jsonBody())?["operationName"] as? String }
    var variables: [String: Any] { ((try? jsonBody())?["variables"] as? [String: Any]) ?? [:] }
}

private func operation(_ request: RecordedRequest) -> String { request.operationName ?? "" }

private let tagJSON = ##"{"id":"t-1","name":"Bears","color":"#8b5a2b","tribe":true}"##
private let tribesJSON = #"{"tribes":[{"isPrivate":true,"tag":\#(tagJSON)}]}"#

private let admissionJSON = #"""
{"id":"a-1","status":"PAID","night":"2026-10-09","amount":{"cents":1000,"currency":"usd"},
 "total":{"cents":1112,"currency":"usd"},"isRefundable":true,"passSecret":"c2VjcmV0","scanCount":0,
 "checkedInAt":null,"profile":{"id":"u-1","name":"Rick Mark","avatarUrl":null},
 "venue":{"id":"v-1","name":"The Stud","photoUrl":null},"event":null}
"""#

@Suite struct Locales {
    @Test func localesDecodeWithTheirPlaces() async throws {
        let stub = Stub { _ in
            .json(status: 200, body: #"""
            {"data":{"locales":[{"id":"l-1","name":"San Francisco","label":"SF","cityNames":["San Francisco","Oakland"],
              "bannerUrl":null,"profile":{"places":{"placeId":"ChIJIQBpAG2ahYAR_6128GcTUEo"}}}]}}
            """#)
        }

        let locales = try await servicesClient(stub).locales()

        let first = try #require(locales.first)
        #expect(first.label == "SF")
        #expect(first.cityNames == ["San Francisco", "Oakland"])
        #expect(first.googlePlaceId == "ChIJIQBpAG2ahYAR_6128GcTUEo")
        #expect(try #require(stub.requests.first).operationName == "Locales")
    }

    @Test func anAudienceWithoutListingsGetsLocalesWithoutPlaces() async throws {
        let stub = Stub { request in
            switch operation(request) {
            case "SchemaFields":
                return .json(status: 200, body: #"{"data":{"t0":{"fields":[{"name":"id"},{"name":"name"},{"name":"label"},{"name":"cityNames"},{"name":"bannerUrl"}]}}}"#)
            case "Locales" where request.query.contains("profile"):
                return .json(status: 200, body: #"""
                {"errors":[{"message":"Field 'profile' doesn't exist on type 'Locale'","extensions":{"code":"undefinedField"}}]}
                """#)
            default:
                return .json(status: 200, body: #"{"data":{"locales":[{"id":"l-1","name":"Reno","label":null,"cityNames":null,"bannerUrl":null}]}}"#)
            }
        }

        let locales = try await servicesClient(stub).locales()

        #expect(locales.map(\.name) == ["Reno"])
        #expect(locales.first?.googlePlaceId == nil)
        #expect(stub.requests.map(operation) == ["Locales", "SchemaFields", "Locales"])
        #expect(!(stub.requests.last?.query.contains("profile") ?? true))
    }

    @Test func noLocalesIsAnEmptyList() async throws {
        let stub = Stub { _ in .json(status: 200, body: #"{"data":{"locales":null}}"#) }

        #expect(try await servicesClient(stub).locales().isEmpty)
    }
}

@Suite struct TribeCalls {
    @Test func tribesListWhatsAvailableAndTheUsersOwn() async throws {
        let stub = Stub { _ in
            .json(status: 200, body: #"""
            {"data":{"id":"aud","tribes":[\#(tagJSON),{"id":"t-2","name":"Twinks","color":null,"tribe":true}],
              "me":{"self":{"id":"u-1",\#(tribesJSON.dropFirst().dropLast())}}}}
            """#)
        }

        let tribes = try await servicesClient(stub).tribes()

        #expect(tribes.available.map(\.name) == ["Bears", "Twinks"])
        #expect(tribes.available.first?.tribe == true)
        #expect(tribes.mine == [TribeIdentification(tag: Tag(id: "t-1", name: "Bears", color: "#8b5a2b", tribe: true),
                                                     isPrivate: true)])
    }

    @Test func noTribesAndNoProfileAreEmpty() async throws {
        let stub = Stub { _ in .json(status: 200, body: #"{"data":{"id":"aud","tribes":null,"me":null}}"#) }

        let tribes = try await servicesClient(stub).tribes()

        #expect(tribes.available.isEmpty)
        #expect(tribes.mine.isEmpty)
    }

    @Test func identifyingAndLeavingNameTheTag() async throws {
        let stub = Stub { request in
            operation(request) == "IdentifyWithTribe"
                ? .json(status: 200, body: #"{"data":{"identifyWithTribe":\#(tribesJSON)}}"#)
                : .json(status: 200, body: #"{"data":{"leaveTribe":{"tribes":[]}}}"#)
        }
        let client = servicesClient(stub)

        let joined = try await client.identifyWithTribe("t-1", isPrivate: false)
        #expect(joined.map(\.tag.id) == ["t-1"])
        let identify = try #require(stub.requests.first)
        #expect(identify.variables["tagId"] as? String == "t-1")
        #expect(identify.variables["isPrivate"] as? Bool == false)

        #expect(try await client.leaveTribe("t-1").isEmpty)
        let leave = try #require(stub.requests.last)
        #expect(leave.operationName == "LeaveTribe")
        #expect(leave.variables["tagId"] as? String == "t-1")
    }

    @Test func identifyingIsPrivateUnlessSaidOtherwise() async throws {
        let stub = Stub { _ in .json(status: 200, body: #"{"data":{"identifyWithTribe":\#(tribesJSON)}}"#) }

        try await servicesClient(stub).identifyWithTribe("t-1")

        #expect(try #require(stub.requests.first).variables["isPrivate"] as? Bool == true)
    }
}

@Suite struct CoverPasses {
    @Test func admissionsListTheUsersPasses() async throws {
        let stub = Stub { _ in
            .json(status: 200, body: #"{"data":{"me":{"cover":{"admissions":{"nodes":[\#(admissionJSON)]}}}}}"#)
        }

        let admissions = try await servicesClient(stub).admissions()

        let pass = try #require(admissions.first)
        #expect(pass.status == .paid)
        #expect(pass.isRefundable)
        #expect(pass.venue.name == "The Stud")
        #expect(pass.checkedInAt == nil)
    }

    @Test func noProfileHasNoPasses() async throws {
        let stub = Stub { _ in .json(status: 200, body: #"{"data":{"me":null}}"#) }

        #expect(try await servicesClient(stub).admissions().isEmpty)
    }

    @Test func refundingNamesThePassAndReturnsItRefunded() async throws {
        let refunded = admissionJSON.replacingOccurrences(of: "\"PAID\"", with: "\"REFUNDED\"")
            .replacingOccurrences(of: "\"isRefundable\":true", with: "\"isRefundable\":false")
        let stub = Stub { _ in .json(status: 200, body: #"{"data":{"refundAdmission":{"admission":\#(refunded)}}}"#) }

        let admission = try await servicesClient(stub).refundAdmission(admissionID: "a-1")

        #expect(admission.status == .refunded)
        #expect(!admission.isRefundable)
        let request = try #require(stub.requests.first)
        #expect(request.operationName == "RefundAdmission")
        #expect(request.variables["admissionId"] as? String == "a-1")
    }

    @Test func aRefusedRefundThrows() async throws {
        let stub = Stub { _ in
            .json(status: 200, body: #"{"errors":[{"message":"Already checked in","extensions":{"code":"FORBIDDEN"}}]}"#)
        }

        await #expect(throws: AudienceKitError.self) { try await servicesClient(stub).refundAdmission(admissionID: "a-1") }
    }
}

@Suite struct ChatCalls {
    @Test func removeChatMessageNamesTheMessage() async throws {
        let stub = Stub { _ in .json(status: 200, body: #"{"data":{"removeMyChatMessage":{"deletedId":"m-1"}}}"#) }

        try await servicesClient(stub).removeChatMessage(id: "m-1")

        let request = try #require(stub.requests.first)
        #expect(request.operationName == "RemoveMyChatMessage")
        #expect(request.variables["messageId"] as? String == "m-1")
    }

    @Test func removingSomeoneElsesMessageThrows() async throws {
        let stub = Stub { _ in
            .json(status: 200, body: #"{"errors":[{"message":"Not yours","extensions":{"code":"FORBIDDEN"}}]}"#)
        }

        await #expect(throws: AudienceKitError.self) { try await servicesClient(stub).removeChatMessage(id: "m-1") }
    }

    @Test func sendingToAVenueRepliesToAPrompt() async throws {
        let stub = Stub { _ in
            .json(status: 200, body: #"""
            {"data":{"sendMyChatMessage":{"message":{"id":"m-9","body":"me!","message":"me!","kind":"REQUEST","pinned":false}}}}
            """#)
        }

        let message = try await servicesClient(stub).sendChatMessage("me!", in: .venue(id: "v-1"), promptID: "p-1")

        #expect(message.kind == "REQUEST")
        let request = try #require(stub.requests.first)
        let input = try #require(request.variables["input"] as? [String: Any])
        #expect(input["venueId"] as? String == "v-1")
        #expect(input["promptId"] as? String == "p-1")
        #expect(input["localeId"] == nil)
    }
}

@Suite struct GraphQLEnvelopes {
    private func events(_ body: String) async throws -> [Event] {
        try await servicesClient(Stub { _ in .json(status: 200, body: body) }).events()
    }

    @Test func noDataOrNotJSONThrowsRatherThanReturningNothing() async throws {
        await #expect(throws: AudienceKitError.self) { try await events(#"{"data":null}"#) }
        await #expect(throws: AudienceKitError.self) { try await events("<html>Bad gateway</html>") }
    }

    @Test func anErrorWithoutExtensionsKeepsItsMessage() async throws {
        do {
            _ = try await events(#"{"errors":[{"message":"Boom"}]}"#)
            Issue.record("didn't throw")
        } catch let error as AudienceKitError {
            #expect(error.message.contains("Boom") || error.errors.contains { $0.message == "Boom" })
        }
    }

    @Test func anEmptyErrorsListIsNotAnError() async throws {
        #expect(try await events(#"{"data":{"events":{"list":{"nodes":[]}}},"errors":[]}"#).isEmpty)
    }
}

// MARK: - Promo views

private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String: Any]] = []
    var all: [[String: Any]] { lock.withLock { recorded } }
    func add(_ variables: [String: Any]) { lock.withLock { recorded.append(variables) } }
}

@Suite struct PromoViews {
    private func recorder(signedIn: Bool = true) -> (PromoViewRecorder, Calls) {
        let calls = Calls()
        let stub = Stub { request in
            calls.add(request.variables)
            return .json(status: 200, body: #"{"data":{"recordCardViews":{"recorded":1}}}"#)
        }
        return (PromoViewRecorder(session: servicesClient(stub, signedIn: signedIn), minimumOnScreen: .milliseconds(20)),
                calls)
    }

    @Test func aPromoOnScreenLongEnoughIsReportedOncePerLayout() async throws {
        let (recorder, calls) = recorder()

        await recorder.appeared("p-1", layoutID: "lay-1")
        await recorder.appeared("p-2", layoutID: "lay-1")
        try await eventually { calls.all.count == 1 }
        let ids = try #require(calls.all.first?["promoIds"] as? [String])
        #expect(Set(ids) == ["p-1", "p-2"])
        #expect(calls.all.first?["layoutId"] as? String == "lay-1")

        // Seen again in the same layout: not reported again.
        await recorder.disappeared("p-1")
        await recorder.appeared("p-1", layoutID: "lay-1")
        try await Task.sleep(for: .milliseconds(700))
        #expect(calls.all.count == 1)
    }

    @Test func aPromoScrolledPastQuicklyIsNotReported() async throws {
        let (recorder, calls) = recorder()

        await recorder.appeared("p-1", layoutID: "lay-1")
        await recorder.disappeared("p-1")
        try await Task.sleep(for: .milliseconds(700))

        #expect(calls.all.isEmpty)
    }

    @Test func signedOutViewsAreNotReported() async throws {
        let (recorder, calls) = recorder(signedIn: false)

        await recorder.appeared("p-1", layoutID: nil)
        try await Task.sleep(for: .milliseconds(700))

        #expect(calls.all.isEmpty)
    }

    @Test func onePromoInTwoLayoutsIsReportedInEach() async throws {
        let (recorder, calls) = recorder()

        await recorder.appeared("p-1", layoutID: "home")
        // Wait for the home view to be reported rather than a fixed time: a loaded simulator can take longer than
        // any sleep to run the on-screen timer, and then disappearing cancels it.
        try await eventually { calls.all.count == 1 }
        await recorder.disappeared("p-1")
        await recorder.appeared("p-1", layoutID: "venue")
        try await eventually { calls.all.count == 2 }

        #expect(Set(calls.all.compactMap { $0["layoutId"] as? String }) == ["home", "venue"])
    }

    @Test func viewsAreSentTenAtATime() async throws {
        let (recorder, calls) = recorder()

        for index in 0 ..< 12 { await recorder.appeared("p-\(index)", layoutID: nil) }
        try await eventually { calls.all.count == 2 }

        let sizes = calls.all.compactMap { ($0["promoIds"] as? [String])?.count }.sorted()
        #expect(sizes == [2, 10])
        #expect(calls.all.allSatisfy { $0["layoutId"] == nil })
    }
}

// MARK: - A chat room's stream

private let cableConfiguration = AudienceKitConfiguration(baseURL: URL(string: "https://api.test")!)

private func cableJSON(_ object: [String: Any]) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
}

nonisolated(unsafe) private let line: [String: Any] = ["id": "m-1", "body": "hi", "message": "hi", "name": "Ada L.", "userId": "u-2",
                                   "kind": "TEXT", "pinned": false]

@Suite struct ChatStream {
    /// A chat room's stream on a welcomed, confirmed socket, its socket and its identifier.
    /// The cable comes back too: the caller keeps it alive while it reads the stream.
    private func joined(_ room: ChatRoom, watch: Bool = false) async throws
        -> (AsyncStream<ChatRoomUpdate>.Iterator, FakeSocket, String, AudienceCable) {
        let sockets = Sockets()
        let cable = AudienceCable(configuration: cableConfiguration, credential: {
            Credential(token: "session-jwt", userId: "u-1", audienceId: "aud", role: "member",
                       endpoint: URL(string: "https://api.test/v1/audience/aud/graphql")!)
        }, openSocket: { sockets.open($0) })
        var updates = await cable.chat(room, watch: watch, audienceID: "aud").makeAsyncIterator()
        try await eventually { !sockets.all.isEmpty }
        let socket = try #require(sockets.all.first)
        socket.push(#"{"type":"welcome"}"#)
        try await eventually { socket.commands("subscribe").count == 1 }
        let identifier = try #require(socket.commands("subscribe").first?["identifier"] as? String)
        socket.push(cableJSON(["type": "confirm_subscription", "identifier": identifier]))
        guard case .subscribed? = await updates.next() else {
            Issue.record("not subscribed")
            return (updates, socket, identifier, cable)
        }
        return (updates, socket, identifier, cable)
    }

    private func result(_ socket: FakeSocket, _ identifier: String, _ result: [String: Any], more: Bool = true) {
        socket.push(cableJSON(["identifier": identifier, "message": ["result": result, "more": more]]))
    }

    @Test func runsTheRoomsOperationAndStreamsItsEvents() async throws {
        var (updates, socket, identifier, cable) = try await joined(.venue(id: "v-1"))

        let command = try #require(socket.commands("message").first?["data"] as? String)
        let execute = try #require(JSONSerialization.jsonObject(with: Data(command.utf8)) as? [String: Any])
        #expect(execute["operationName"] as? String == "ChatRoom")
        #expect((execute["variables"] as? [String: Any])?["id"] as? String == "v-1")
        #expect((execute["query"] as? String)?.contains("room: venueChat(venueId: $id)") == true)

        result(socket, identifier, ["data": ["room": ["__typename": "ChatJoined", "outOfRange": true,
                                                      "roster": ["people": []], "history": [["message": line]],
                                                      "pinnedMessage": NSNull()]]])
        guard case let .event(.joined(_, history, pinned, outOfRange))? = await updates.next() else {
            Issue.record("not joined")
            return
        }
        #expect(history.map(\.id) == ["m-1"])
        #expect(pinned == nil)
        #expect(outOfRange)

        result(socket, identifier, ["data": ["room": ["__typename": "ChatMessageRemoved", "messageId": "m-1"]]])
        guard case let .event(.removed(messageID))? = await updates.next() else {
            Issue.record("not removed")
            return
        }
        #expect(messageID == "m-1")
        withExtendedLifetime(cable) {}
    }

    @Test func oneBadMessageDoesNotLoseTheJoin() async throws {
        var (updates, socket, identifier, cable) = try await joined(.venue(id: "v-1"))

        var badDate = line
        badDate["id"] = "m-2"
        badDate["sentAt"] = "yesterday"
        var noID = line
        noID.removeValue(forKey: "id")
        result(socket, identifier, ["data": ["room": ["__typename": "ChatJoined", "outOfRange": false,
                                                      "roster": ["people": [["userId": "u-2", "name": "Ada L.", "friend": false], ["name": "?", "friend": false]]],
                                                      "history": [["message": line], ["message": badDate], ["message": noID]],
                                                      "pinnedMessage": NSNull()]]])
        guard case let .event(.joined(people, history, _, _))? = await updates.next() else {
            Issue.record("the join was lost")
            return
        }
        #expect(history.map(\.id) == ["m-1"])
        #expect(people.map(\.userId) == ["u-2"])
        withExtendedLifetime(cable) {}
    }

    @Test func watchingALocaleAsksToWatch() async throws {
        let (_, socket, _, _) = try await joined(.locale(id: "l-1"), watch: true)

        let command = try #require(socket.commands("message").first?["data"] as? String)
        #expect(command.contains("localeChat(localeId: $id, watch: true)"))
    }

    @Test func aRefusedRoomSaysWhyAndEnds() async throws {
        var (updates, socket, identifier, cable) = try await joined(.venue(id: "v-1"))

        result(socket, identifier, ["data": NSNull(), "errors": [["message": "You're not at this venue"]]])

        guard case let .refused(errors)? = await updates.next() else {
            Issue.record("not refused")
            return
        }
        #expect(errors.first?.message == "You're not at this venue")
        #expect(await updates.next() == nil)
        withExtendedLifetime(cable) {}
    }

    @Test func aRejectedChannelIsRefusedWithoutErrors() async throws {
        let sockets = Sockets()
        let cable = AudienceCable(configuration: cableConfiguration, credential: {
            Credential(token: "session-jwt", userId: "u-1", audienceId: "aud", role: "member",
                       endpoint: URL(string: "https://api.test/v1/audience/aud/graphql")!)
        }, openSocket: { sockets.open($0) })
        var updates = await cable.chat(.venue(id: "v-1"), audienceID: "aud").makeAsyncIterator()
        try await eventually { !sockets.all.isEmpty }
        let socket = try #require(sockets.all.first)
        socket.push(#"{"type":"welcome"}"#)
        try await eventually { socket.commands("subscribe").count == 1 }
        let identifier = try #require(socket.commands("subscribe").first?["identifier"] as? String)
        socket.push(cableJSON(["type": "reject_subscription", "identifier": identifier]))

        guard case let .refused(errors)? = await updates.next() else {
            Issue.record("not refused")
            return
        }
        #expect(errors.isEmpty)
        #expect(await updates.next() == nil)
    }

    @Test func aDroppedSocketSaysItReconnects() async throws {
        var (updates, socket, _, cable) = try await joined(.venue(id: "v-1"))

        socket.push(#"{"type":"disconnect","reason":"server_restart","reconnect":true}"#)

        guard case let .disconnected(reason, reconnects)? = await updates.next() else {
            Issue.record("not disconnected")
            return
        }
        #expect(reason == "server_restart")
        #expect(reconnects)
        withExtendedLifetime(cable) {}
    }

    @Test func anEmptyResultIsSkipped() async throws {
        var (updates, socket, identifier, cable) = try await joined(.venue(id: "v-1"))

        result(socket, identifier, ["data": ["room": NSNull()]])
        result(socket, identifier, ["data": ["room": ["__typename": "ChatRangeChanged", "outOfRange": false]]])

        guard case .event(.rangeChanged(outOfRange: false))? = await updates.next() else {
            Issue.record("the empty result wasn't skipped")
            return
        }
        withExtendedLifetime(cable) {}
    }
}
