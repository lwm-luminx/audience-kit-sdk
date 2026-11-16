// The find-friends views and their model, hosted in a window. macOS only (Linux has no SwiftUI or Contacts). The
// model reads the contacts the test gives it, never the Mac's own.
#if canImport(SwiftUI) && canImport(AppKit) && canImport(Contacts)
import AudienceCore
import AudienceKit
import AudienceKitTesting
import AudienceKitUI
import Foundation
import SwiftUI
import Testing

private let jordanHash = "568bb17dbe82b2d378c7867777b9e84d8d128b7950fb137fc4e38f4ea808e33c"

private func state(enabled: Bool = false, verified: Bool = false, matches: String = "[]", requests: String = "[]",
                   available: Bool = true) -> String
{
    """
    {"enabled":\(enabled),"phoneVerified":\(verified),"phoneNumber":\(verified ? "\"+12065550142\"" : "null"),\
    "firstName":"Danny","lastName":"Ortiz","codeResendAt":"2026-11-16T07:00:30Z",\
    "lastCheckedAt":\(enabled ? "\"2026-11-16T06:00:00Z\"" : "null"),"nextCheckAt":"2026-11-17T06:00:00Z",\
    "contactsChecked":\(enabled ? 1 : 0),"textCodesAvailable":\(available),"matches":\(matches),\
    "incomingRequests":\(requests)}
    """
}

private let request_ = #"{"id":"r-1","status":"PENDING","createdAt":"2026-11-16T06:00:00Z","user":{"id":"u-2","name":"Jordan P.","avatarUrl":null},"friend":{"id":"u-test","name":"Danny Ortiz","avatarUrl":null}}"#

private func match(_ status: String, hash: Bool = false) -> String {
    #"[{"status":"\#(status)",\#(hash ? "\"contactHash\":\"\(jordanHash)\"," : "")"user":{"id":"u-2","name":"Jordan P.","avatarUrl":null},"request":null}]"#
}

@MainActor
private func model(_ stub: GraphQLStub, contacts: [DeviceContact] = [], allowed: Bool = true) -> ContactMatchingModel {
    let defaults = UserDefaults(suiteName: "find-friends-\(UUID().uuidString)")!
    return ContactMatchingModel(client: stub.client, audienceID: "a-1", defaults: defaults, region: "US",
                                requestAccess: { allowed }, readContacts: { contacts })
}

@MainActor
private func draws<Content: View>(_ content: Content) async -> Bool {
    let host = ViewHost(content)
    await host.settle()
    defer { host.close() }
    return host.drewSomething
}

@MainActor
struct FindFriendsViewTests {
    @Test("The card shows while matching is off, and Not now hides it")
    func card() async {
        let stub = GraphQLStub { _ in .data(#"{"me":{"contactMatching":\#(state())}}"#) }
        let friends = model(stub)
        #expect(!friends.offersCard)
        await friends.load()
        #expect(friends.offersCard)
        #expect(await draws(FindFriendsCard(model: friends) {}))

        friends.hideCard()
        #expect(!friends.offersCard && friends.cardHidden)
    }

    @Test("The card stays away while codes can't be texted")
    func cardWithoutTexting() async {
        let stub = GraphQLStub { _ in .data(#"{"me":{"contactMatching":\#(state(available: false))}}"#) }
        let friends = model(stub)
        await friends.load()
        #expect(!friends.offersCard)
    }

    @Test("The flow verifies a number, checks contacts and shows who it found")
    func flow() async {
        let stub = GraphQLStub { request in
            switch request.operationName {
            case "StartContactPhoneVerification":
                return .data(#"{"startContactPhoneVerification":{"contactMatching":\#(state())}}"#)
            case "VerifyContactPhone":
                return .data(#"{"verifyContactPhone":{"contactMatching":\#(state(verified: true))}}"#)
            case "CheckContacts":
                return .data(#"{"checkContacts":{"matches":\#(match("NONE", hash: true)),"contactMatching":\#(state(enabled: true, verified: true, matches: match("NONE")))}}"#)
            case "SendFriendRequest":
                return .data(#"{"sendFriendRequest":{"contactMatching":\#(state(enabled: true, verified: true, matches: match("REQUESTED")))}}"#)
            default:
                return .data(#"{"me":{"contactMatching":\#(state())}}"#)
            }
        }
        let friends = model(stub, contacts: [DeviceContact(firstName: "Jordan", lastName: "Park",
                                                           phoneNumbers: ["206-555-0177"]),
                                             DeviceContact(firstName: "Mom", lastName: "", phoneNumbers: ["2065550100"])])
        await friends.load()
        #expect(await draws(FindFriendsFlow(model: friends, appName: "Hot Mess", firstName: "Danny",
                                            lastName: "Ortiz") {}))

        #expect(await friends.start(number: "555", region: "US", firstName: "Danny", lastName: "Ortiz") == false)
        #expect(friends.error != nil)
        #expect(await friends.start(number: "(206) 555-0142", region: "US", firstName: "Danny", lastName: "Ortiz"))
        #expect(stub.requests.last?.string("phoneNumber") == "+12065550142")
        #expect(await friends.verify(code: "424242"))
        #expect(friends.state?.phoneVerified == true)

        #expect(await friends.checkContacts())
        #expect(friends.lastBatch?.contactCount == 1)
        #expect(friends.lastBatch?.skippedWithoutFullName == 1)
        #expect(friends.savedName(for: "u-2") == "Jordan Park")
        #expect((stub.requests.last?.variables["hashes"] as? [String]) == [jordanHash])
        #expect(await draws(ContactMatchesView(model: friends, appName: "Hot Mess") {}))
        #expect(await draws(FindFriendsFlow(model: friends, appName: "Hot Mess") {}))

        await friends.addAll()
        #expect(friends.state?.matches.first?.status == .requested)
        #expect(friends.error == nil)
    }

    @Test("Refused contacts says so and sends nothing")
    func refusedContacts() async {
        let stub = GraphQLStub { _ in .data(#"{"me":{"contactMatching":\#(state(verified: true))}}"#) }
        let friends = model(stub, allowed: false)
        await friends.load()

        #expect(await friends.checkContacts() == false)
        #expect(friends.contactsDenied)
        #expect(stub.requests.allSatisfy { $0.operationName == "ContactMatching" })
        #expect(await draws(FindFriendsFlow(model: friends, appName: "Hot Mess") {}))
    }

    @Test("Requests show as cards and Not now answers quietly")
    func requests() async {
        let stub = GraphQLStub { request in
            if request.operationName == "RespondToFriendRequest" {
                #expect(request.variables["accept"] as? Bool == false)
                return .data(#"{"respondToFriendRequest":{"contactMatching":\#(state(enabled: true, verified: true))}}"#)
            }
            return .data(#"{"me":{"contactMatching":\#(state(enabled: true, verified: true, requests: "[\(request_)]"))}}"#)
        }
        let friends = model(stub)
        await friends.load()
        #expect(friends.incomingRequests.count == 1)
        #expect(await draws(FriendRequestCards(model: friends)))

        #expect(await friends.respond(to: friends.incomingRequests[0], accept: false))
        #expect(friends.incomingRequests.isEmpty)
    }

    @Test("Settings show the number and name, and turning off forgets the saved names")
    func settings() async {
        let stub = GraphQLStub { request in
            switch request.operationName {
            case "DisableContactMatching":
                return .data(#"{"disableContactMatching":{"contactMatching":\#(state())}}"#)
            case "SetContactMatchName":
                return .data(#"{"setContactMatchName":{"contactMatching":\#(state(enabled: true, verified: true))}}"#)
            default:
                return .data(#"{"me":{"contactMatching":\#(state(enabled: true, verified: true))}}"#)
            }
        }
        let friends = model(stub)
        await friends.load()
        #expect(await draws(ContactMatchingSettings(model: friends, appName: "Hot Mess") {}.frame(height: 500)))

        #expect(await friends.setName(firstName: "Daniel", lastName: "Ortiz"))
        #expect(await friends.turnOff())
        #expect(friends.state?.enabled == false)
        #expect(friends.lastBatch == nil)
        #expect(await draws(ContactMatchingSettings(model: friends, appName: "Hot Mess") {}.frame(height: 300)))
    }

    @Test("A refused call keeps the API's words")
    func errors() async {
        let stub = GraphQLStub { _ in .error("That code isn't right. Check the text and try again.") }
        let friends = model(stub)

        #expect(await friends.verify(code: "000000") == false)
        #expect(friends.error == "That code isn't right. Check the text and try again.")
    }
}
#endif
