import Foundation
import Testing
import AudienceKit
@testable import StaffKitCore
@testable import StaffKitServices

private func soapboxClient(_ stub: Stub) -> SoapboxClient {
    SoapboxClient(session: AudienceManagementSession(baseURL: stub.baseURL, credentialStore: InMemoryCredentialStore(credential: makeCredential(audienceID: "audience", on: stub.baseURL)), session: stub.session))
}
private func lastRequest(_ stub: Stub) throws -> (query: String, variables: [String: Any]) {
    let body = try #require(stub.requests.last).jsonBody()
    return (body["query"] as? String ?? "", body["variables"] as? [String: Any] ?? [:])
}

private let publication = #"{"id":"p1","name":"QSaltLake","masthead":null,"about":"Utah's LGBTQ news","websiteUrl":"https://qsaltlake.com","editorialEmail":null,"photoUrl":null,"trust":"PENDING","trustNote":null,"trusted":false,"acceptsOpEds":true,"opEdGuidelines":"600 words","linksOut":false,"onboarded":true,"feedUrl":null,"feedError":null,"locale":{"id":"l1","name":"Salt Lake City"},"person":{"id":"pe1","name":"QSaltLake"},"viewerCanManage":true,"viewerCanPublish":false}"#
private func article(id: String = "a1", status: String = "DRAFT", scheduled: Bool = false, kind: String = "ARTICLE",
                     extra: String = "") -> String {
    #"{"id":"\#(id)","slug":"pride","title":"Pride returns","summary":"A bigger route","byline":"QSaltLake","kind":"\#(kind)","status":"\#(status)","publishedAt":"2026-11-10T18:00:00Z","scheduled":\#(scheduled),"edited":false,"pinned":false,"teaser":false,"canonicalUrl":null,"disclosure":null,"heroPhotoUrl":null,"heroAltText":null,"visibility":"COMMUNITY","reviewNote":null,"submittedAt":null,"pushedAt":null,"updatedAt":"2026-11-10T17:00:00.123Z","viewerCanManage":true,"publication":{"id":"p1","name":"QSaltLake"}\#(extra)}"#
}

@Test func myPublicationsDecodeWithTrustAndOpEds() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"soapbox":{"myPublications":[\#(publication)]}}}"#) }
    let publications = try await soapboxClient(stub).myPublications()
    let first = try #require(publications.first)
    #expect(first.name == "QSaltLake" && first.trust == .pending && !first.viewerCanPublish && first.acceptsOpEds)
    #expect(first.locale?.name == "Salt Lake City")
    let (query, _) = try lastRequest(stub)
    #expect(query.contains("myPublications { id name masthead"))
    #expect(try #require(stub.requests.last).path.hasSuffix("staffql"))
}

@Test func articlesSortOntoShelves() async throws {
    let body = [article(id: "d"), article(id: "r", status: "IN_REVIEW"), article(id: "s", status: "PUBLISHED", scheduled: true),
                article(id: "p", status: "PUBLISHED"), article(id: "o", status: "SUBMITTED", kind: "OP_ED"),
                article(id: "u", status: "UNPUBLISHED")].joined(separator: ",")
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"soapbox":{"publication":{"allArticles":{"nodes":[\#(body)]}}}}}"#) }
    let articles = try await soapboxClient(stub).articles(publicationID: "p1", statuses: [.draft, .published], first: 500)
    #expect(articles.map(\.shelf) == [.drafts, .inReview, .scheduled, .published, .opEds, .drafts])
    #expect(articles[4].isOpEd)
    #expect(articles[0].updatedAt.timeIntervalSince1970 > 0)
    let (query, variables) = try lastRequest(stub)
    #expect(query.contains("allArticles(statuses: $statuses, first: $first)"))
    #expect(variables["first"] as? Int == SoapboxClient.pageSize)
    #expect(variables["statuses"] as? [String] == ["DRAFT", "PUBLISHED"])
}

@Test func anArticleReadsItsBodyAndSubjects() async throws {
    let full = article(extra: ##","body":"# Hello","venues":[{"id":"v1","name":"Club Try-Angles"}],"events":[],"people":[],"locales":[{"id":"l1","name":"Salt Lake City"}]"##)
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"soapbox":{"article":\#(full)}}}"#) }
    let read = try #require(try await soapboxClient(stub).article(id: "a1"))
    #expect(read.body == "# Hello" && read.subjects(.venue).map(\.title) == ["Club Try-Angles"] && read.subjects(.event).isEmpty)
    #expect(try lastRequest(stub).variables["id"] as? String == "a1")
}

@Test func savingSendsOnlyWhatChanged() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"saveArticle":{"article":\#(article())}}}"#) }
    let client = soapboxClient(stub)
    _ = try await client.createArticle(publicationID: "p1", .init(title: "Pride returns", body: "Text",
                                                                  subjects: [.venue: ["v1"], .locale: []]))
    let created = try #require(try lastRequest(stub).variables["input"] as? [String: Any])
    #expect(created["publicationId"] as? String == "p1" && created["title"] as? String == "Pride returns")
    #expect(created["venueIds"] as? [String] == ["v1"] && created["localeIds"] as? [String] == [])
    #expect(created["summary"] == nil && created["eventIds"] == nil && created["id"] == nil)
    _ = try await client.updateArticle(id: "a1", .init(pinned: true, visibility: .public))
    let updated = try #require(try lastRequest(stub).variables["input"] as? [String: Any])
    #expect(updated["id"] as? String == "a1" && updated["pinned"] as? Bool == true && updated["visibility"] as? String == "PUBLIC")
    #expect(updated["title"] == nil && updated["publicationId"] == nil)
}

@Test func publishingSchedulesAndPushes() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"setArticleStatus":{"article":\#(article(status: "PUBLISHED", scheduled: true))}}}"#) }
    let at = Date(timeIntervalSince1970: 1_800_000_000)
    let moved = try await soapboxClient(stub).setStatus(of: "a1", to: .publish, note: "  ", publishAt: at,
                                                       push: SoapboxPush(localeIDs: ["l1"], purpose: .event))
    #expect(moved.shelf == .scheduled)
    let input = try #require(try lastRequest(stub).variables["input"] as? [String: Any])
    #expect(input["action"] as? String == "PUBLISH" && input["note"] == nil)
    #expect((input["publishAt"] as? String)?.hasPrefix("2027-01-15T08:00:00") == true)
    #expect(input["pushLocaleIds"] as? [String] == ["l1"] && input["pushPurpose"] as? String == "EVENT")
}

@Test func aPushAskingForMoneyIsRefusedBeforeItsSent() async throws {
    let stub = Stub { _ in .json(status: 200, body: "{}") }
    let asking = SoapboxArticle(id: "a1", title: "Chip in $5 before midnight", publication: .init(id: "p1", name: "Q"))
    await #expect(throws: AudienceKitError.self) {
        try await soapboxClient(stub).setStatus(of: "a1", to: .publish, push: SoapboxPush(localeIDs: ["l1"], purpose: .volunteer),
                                                article: asking)
    }
    #expect(stub.requests.isEmpty)
    #expect(SoapboxPushRules.refusal(title: "Donate to the campaign", summary: nil) != nil)
    #expect(SoapboxPushRules.refusal(title: "Canvass with us", summary: "Volunteers meet at 10") == nil)
    #expect(SoapboxPushRules.refusal(title: "Rally Saturday", summary: "via ActBlue") != nil)
}

@Test func declineSendsTheNoteAndOtherActionsNoPush() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"setArticleStatus":{"article":\#(article(status: "DECLINED", kind: "OP_ED"))}}}"#) }
    _ = try await soapboxClient(stub).setStatus(of: "a1", to: .declineOpEd, note: " Too long ",
                                               push: SoapboxPush(localeIDs: ["l1"], purpose: .event))
    let input = try #require(try lastRequest(stub).variables["input"] as? [String: Any])
    #expect(input["action"] as? String == "DECLINE_OP_ED" && input["note"] as? String == "Too long")
    #expect(input["pushLocaleIds"] == nil && input["publishAt"] == nil)
}

@Test func publicationsSaveAndTrust() async throws {
    let stub = Stub { request in
        let query = (try? request.jsonBody()["query"] as? String) ?? ""
        let field = query.contains("setPublicationTrust") ? "setPublicationTrust" : "savePublication"
        return .json(status: 200, body: #"{"data":{"\#(field)":{"publication":\#(publication)}}}"#)
    }
    let client = soapboxClient(stub)
    _ = try await client.startPublication(personID: "pe1")
    #expect(try #require(try lastRequest(stub).variables["input"] as? [String: Any])["personId"] as? String == "pe1")
    _ = try await client.updatePublication(id: "p1", .init(about: "News", acceptsOpEds: false, localeID: ""))
    let input = try #require(try lastRequest(stub).variables["input"] as? [String: Any])
    #expect(input["id"] as? String == "p1" && input["about"] as? String == "News" && input["acceptsOpEds"] as? Bool == false)
    #expect(input.keys.contains("localeId") && input["localeId"] is NSNull && input["masthead"] == nil)
    _ = try await client.setTrust(of: "p1", to: .trusted, note: "Known paper")
    let trust = try #require(try lastRequest(stub).variables["input"] as? [String: Any])
    #expect(trust["trust"] as? String == "TRUSTED" && trust["note"] as? String == "Known paper")
}

@Test func theViewerSaysAdminAndTheirPeople() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"me":{"consoleRole":"ADMIN","listings":{"people":[{"id":"pe1","name":"QSaltLake"}]}}}}"#) }
    let viewer = try await soapboxClient(stub).viewer()
    #expect(viewer.isAdmin && viewer.people.map(\.id) == ["pe1"])
}

@Test func peopleAndLocalesAreFilteredByName() async throws {
    let stub = Stub { request in
        let query = (try? request.jsonBody()["query"] as? String) ?? ""
        if query.contains("locales") { return .json(status: 200, body: #"{"data":{"locales":[{"id":"l1","name":"Salt Lake City"},{"id":"l2","name":"Utah"}]}}"#) }
        return .json(status: 200, body: #"{"data":{"venues":{"list":{"nodes":[{"id":"v1","name":"Club Try-Angles"}]}}}}"#)
    }
    let client = soapboxClient(stub)
    #expect(try await client.subjects(.locale, matching: "salt").map(\.id) == ["l1"])
    #expect(try await client.subjects(.locale, matching: " ").count == 2)
    #expect(try await client.subjects(.venue, matching: "try").map(\.id) == ["v1"])
    #expect(try lastRequest(stub).variables["search"] as? String == "try")
}

@Test func guidesAndUnknownValuesStillDecode() async throws {
    // The API added GUIDE (a standing guide such as a Pride guide); a build without it failed the whole review queue.
    let body = [article(id: "g", status: "IN_REVIEW", kind: "GUIDE"), article(id: "n", status: "SOMETHING_NEW", kind: "SOMETHING_NEW")]
        .joined(separator: ",")
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"soapbox":{"publication":{"allArticles":{"nodes":[\#(body)]}}}}}"#) }
    let articles = try await soapboxClient(stub).articles(publicationID: "p1", statuses: nil, first: 500)
    #expect(articles.map(\.kind) == [.guide, .article])
    #expect(articles.map(\.status) == [.inReview, .draft])
    #expect(!articles[0].isOpEd)
}
