import Foundation
import Testing
import AudienceCore
import AudienceKit
import StaffKitServices
import StaffKitCore

@Test func venueControlClearsSessionOverridesInSeriesAndEvents() async throws {
    var draft = StaffKaraokeDraft(enabled: true, ownSessionCode: "654321")
    #expect(draft.seriesFields["karaokeSessionCode"] == .string("654321"))
    draft.venueControlled = true
    #expect(draft.seriesFields["karaokeSessionCode"] == .null)
    let event = #"{"id":"event","name":"Karaoke","isCanceled":false,"seriesOverride":false,"karaoke":{"providerName":"KaraFun","sessionCode":"123456","ownSessionCode":null,"joinUrl":"https://www.karafun.com/123456/"}}"#
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"setEventKaraoke":{"event":\#(event)}}}"#) }
    let session = AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session)
    let saved = try await VenueManagementClient(session: session).setKaraoke(eventID: "event", draft: draft)
    #expect(saved.karaoke?.ownSessionCode == nil)
    #expect(saved.karaoke?.joinUrl == "https://www.karafun.com/123456/")
    let body = try #require(stub.requests.last).jsonBody()
    let variables = try #require(body["variables"] as? [String: Any])
    #expect(variables["code"] as? String == "")
    #expect(variables["karaoke"] as? Bool == true)
}

@Test func seriesTagsAndKaraokeAreSavedTogetherWithoutReplacingItsOwner() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{}}"#) }
    let session = AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session)
    var fields = StaffKaraokeDraft(enabled: true).seriesFields
    fields["tagIds"] = .array([.string("sing-along")])
    try await VenueManagementClient(session: session).saveSeries(id: "series", venueID: "venue", fields: fields)
    let body = try #require(stub.requests.last).jsonBody()
    let input = try #require((body["variables"] as? [String: Any])?["input"] as? [String: Any])
    let series = try #require(input["eventSeries"] as? [String: Any])
    #expect(series["karaoke"] as? Bool == true)
    #expect(series["karaokeSessionCode"] is NSNull)
    #expect(series["tagIds"] as? [String] == ["sing-along"])
    #expect(series["ownerVenueId"] == nil)
}

@Test func disablingKaraokeDropsAStaleSession() {
    var draft = StaffKaraokeDraft(enabled: true, ownSessionCode: "123456")
    draft.enabled = false
    #expect(draft.effectiveCode == nil)
    #expect(draft.seriesFields["karaoke"] == .bool(false))
    #expect(draft.seriesFields["karaokeSessionCode"] == .null)
}

private func karaokeEvent(_ karaoke: String, hosts: [String] = []) throws -> VenueEvent {
    let people = hosts.enumerated().map { #"{"id":"p\#($0.offset)","name":"\#($0.element)"}"# }.joined(separator: ",")
    let json = #"{"id":"e1","isCanceled":false,"seriesOverride":false,"karaoke":\#(karaoke),"people":{"lineup":{"nodes":[]},"hosts":{"nodes":[\#(people)]}}}"#
    return try JSONDecoder().decode(VenueEvent.self, from: Data(json.utf8))
}

@Test func aKaraFunNightWithoutACodeSendsSingersToItsHost() throws {
    let night = try karaokeEvent(#"{"providerName":"KaraFun","sessionCode":null,"joinUrl":null}"#, hosts: ["Dalton"])
    #expect(night.karaokeSignUp == "Speak to the host Dalton to sign up")
    let nobody = try karaokeEvent(#"{"providerName":"KaraFun","sessionCode":""}"#)
    #expect(nobody.karaokeSignUp == "Speak to the host to sign up")
}

@Test func aKaraFunNightWithASessionSaysWhereToJoin() throws {
    let night = try karaokeEvent(#"{"providerName":"KaraFun","sessionCode":"123456","joinUrl":"https://kfun.cc/123456"}"#,
                                 hosts: ["Dalton"])
    #expect(night.karaokeSignUp == "Sign up to sing at kfun.cc/123456")
}

@Test func aSingAlongNightHasNoSignUp() throws {
    #expect(try karaokeEvent(#"{"providerName":"Sing-along","sessionCode":null}"#).karaokeSignUp == nil)
}

@Test func hostsTipLinksSkipInAppTips() throws {
    let json = #"{"id":"e1","isCanceled":false,"seriesOverride":false,"people":{"lineup":{"nodes":[]},"hosts":{"nodes":[{"id":"p1","name":"Dalton","tipping":{"options":[{"name":"Cash App","handle":"dalton","url":"https://cash.app/$dalton","isInApp":false},{"name":"In the app","handle":null,"url":null,"isInApp":true}]}}]}}}"#
    let event = try JSONDecoder().decode(VenueEvent.self, from: Data(json.utf8))
    #expect(event.hosts.first?.tipLinks.map(\.name) == ["Cash App"])
}

@Test func aKaraFunNightWithAKJSendsSingersToTheKJ() throws {
    let json = #"{"id":"e1","isCanceled":false,"seriesOverride":false,"karaoke":{"providerName":"KaraFun","sessionCode":null},"people":{"lineup":{"nodes":[]},"hosts":{"nodes":[{"id":"p1","name":"Mama Alma"}]},"jockeys":{"nodes":[{"id":"p2","name":"Dalton"}]},"jockeyLabel":"KJ"}}"#
    let night = try JSONDecoder().decode(VenueEvent.self, from: Data(json.utf8))
    #expect(night.karaokeSignUp == "Speak to KJ Dalton to sign up")
    #expect(night.billing == "Hosted by Mama Alma · KJ Dalton")
    #expect(night.billedName(night.jockeys[0]) == "KJ Dalton")
    #expect(night.billedName(night.hosts[0]) == "Mama Alma")
}

@Test func aLoneKJHostsTheNight() throws {
    let json = #"{"id":"e1","isCanceled":false,"seriesOverride":false,"karaoke":{"providerName":"KaraFun","sessionCode":null},"people":{"lineup":{"nodes":[]},"hosts":{"nodes":[]},"jockeys":{"nodes":[{"id":"p2","name":"Dalton"}]},"jockeyLabel":"KJ"}}"#
    let night = try JSONDecoder().decode(VenueEvent.self, from: Data(json.utf8))
    #expect(night.billing == "Hosted by KJ Dalton")
    #expect(night.karaokeSignUp == "Speak to KJ Dalton to sign up")
}

@Test func anOlderAPIsEventHasNoJockeys() throws {
    let night = try karaokeEvent(#"{"providerName":"KaraFun","sessionCode":null}"#, hosts: ["Dalton"])
    #expect(night.jockeys.isEmpty && night.jockeyLabel == "DJ")
    #expect(night.billing == "Hosted by Dalton")
}
