@testable import AudienceCore
import Foundation
import Testing
@testable import AudienceKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let soapboxAudienceID = "00000000-0000-4000-8000-000000000071"

private func soapboxClient(_ stub: Stub) -> AudienceKitClient {
    let endpoint = URL(string: GraphQLEndpoint.consumer.path(audienceID: soapboxAudienceID),
                       relativeTo: stub.baseURL)!.absoluteURL
    let store = InMemoryCredentialStore(credential: Credential(token: "session-token", userId: "u-1",
                                                               audienceId: soapboxAudienceID, role: "member",
                                                               endpoint: endpoint))
    let configuration = AudienceKitConfiguration(baseURL: stub.baseURL, audienceID: soapboxAudienceID)
    return AudienceKitClient(configuration: configuration, credentialStore: store, session: stub.session)
}

private extension RecordedRequest {
    var query: String { ((try? jsonBody())?["query"] as? String) ?? "" }
    var operationName: String? { (try? jsonBody())?["operationName"] as? String }
    var variables: [String: Any] { ((try? jsonBody())?["variables"] as? [String: Any]) ?? [:] }
}

private let publicationJSON = #"{"id":"pub-1","name":"QSaltLake","photoUrl":null,"trusted":true,"acceptsOpEds":true}"#
private let articleFieldsJSON = #"""
"id":"a-1","slug":"pride-2027","title":"Pride 2027","summary":"What's on","byline":"QSaltLake","kind":"ARTICLE",
"publishedAt":"2027-06-01T16:00:00Z","edited":false,"pinned":true,"teaser":false,"canonicalUrl":null,
"disclosure":"QSaltLake sponsors the festival.","heroPhotoUrl":null,"heroAltText":null,
"""# + #""publication":"# + publicationJSON
private let articleJSON = "{" + articleFieldsJSON + "}"

/// Introspection for an audience without the Soapbox module: no `soapbox`, no `articles` anywhere.
private func withoutSoapbox(_ request: RecordedRequest) -> StubResponse {
    let pattern = try! NSRegularExpression(pattern: #"(t\d+): __type\(name: "(\w+)"\)"#)
    let query = request.query
    let entries = pattern.matches(in: query, range: NSRange(query.startIndex..., in: query)).map { match in
        let alias = String(query[Range(match.range(at: 1), in: query)!])
        return #""\#(alias)":{"fields":[{"name":"id"},{"name":"name"}]}"#
    }
    return .json(status: 200, body: #"{"data":{"# + entries.joined(separator: ",") + "}}")
}

@Test func aLocalesNewsDecodes() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"soapbox":{"articles":{"nodes":["# + articleJSON + "]}}}}") }

    let articles = try await soapboxClient(stub).articles(localeID: "l-1", first: 10)

    let article = try #require(articles.first)
    #expect(article.title == "Pride 2027")
    #expect(article.publication.name == "QSaltLake")
    #expect(article.pinned)
    #expect(!article.isOpEd)
    #expect(article.publishedAt == ISO8601DateFormatter().date(from: "2027-06-01T16:00:00Z"))
    #expect(article.body == nil)
    let request = try #require(stub.requests.first)
    #expect(request.operationName == "Articles")
    #expect(request.variables["localeId"] as? String == "l-1")
    #expect(request.variables["first"] as? Int == 10)
    #expect(request.variables["publicationId"] == nil)
}

@Test func anArticleReadsItsBodyAndSubjects() async throws {
    let json = "{" + articleFieldsJSON
        + #","body":"# Pride","venues":[{"id":"v-1","name":"Club Try-Angles"}],"events":[],"people":[],"locales":[]}"#
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"soapbox":{"article":"# + json + "}}}") }

    let article = try await soapboxClient(stub).article(id: "a-1")

    #expect(article?.body == "# Pride")
    #expect(article?.venues == [ArticleSubject(id: "v-1", name: "Club Try-Angles")])
    #expect(stub.requests.first?.query.contains("body") == true)
}

@Test func articlesAboutEachKindOfListingReadTheirMixin() async throws {
    let list = #"{"articles":{"list":{"nodes":["# + articleJSON + "]}}}"
    let stub = Stub { request in
        let query = request.query
        let data = if query.contains("venues {") {
            #"{"venues":{"venue":"# + list + "}}"
        } else if query.contains("events {") {
            #"{"events":{"event":"# + list + "}}"
        } else if query.contains("people {") {
            #"{"people":{"person":"# + list + "}}"
        } else {
            #"{"locale":"# + list + "}"
        }
        return .json(status: 200, body: #"{"data":"# + data + "}")
    }
    let client = soapboxClient(stub)

    for topic in [ArticleTopic.venue("v-1"), .event("e-1"), .person("p-1"), .locale("l-1")] {
        #expect(try await client.articles(about: topic, first: 3).map(\.id) == ["a-1"])
    }
    #expect(stub.requests.map(\.operationName) == Array(repeating: "ArticlesAbout", count: 4))
    #expect(stub.requests[2].variables["id"] as? String == "p-1")
}

@Test func anAudienceWithoutSoapboxGetsNothing() async throws {
    let stub = Stub { request in
        if request.operationName == "SchemaFields" { return withoutSoapbox(request) }
        if request.query.contains("soapbox") || request.query.contains("articles") {
            return .json(status: 200, body: #"""
            {"errors":[{"message":"Field 'soapbox' doesn't exist on type 'Audience'","extensions":{"code":"undefinedField"}}]}
            """#)
        }
        return .json(status: 200, body: #"{"data":{"id":"00000000-0000-4000-8000-000000000071"}}"#)
    }
    let client = soapboxClient(stub)

    #expect(try await client.articles().isEmpty)
    #expect(try await client.article(id: "a-1") == nil)
    #expect(try await client.publications().isEmpty)
    #expect(try await client.publication(id: "pub-1") == nil)
    #expect(try await client.myOpEds().isEmpty)
    #expect(try await client.articles(about: .venue("v-1")).isEmpty)
    #expect(stub.requests.map(\.operationName) == [
        "Articles", "SchemaFields", "Articles", "Article", "Publications", "Publication", "MyOpEds", "ArticlesAbout",
    ])
    #expect(stub.requests.last?.query == "query ArticlesAbout { id }")
}

@Test func publicationsAndMyOpEdsDecode() async throws {
    let stub = Stub { request in
        switch request.operationName {
        case "Publications":
            return .json(status: 200, body: #"""
            {"data":{"soapbox":{"publications":[{"id":"pub-1","name":"QSaltLake","masthead":"QSaltLake","trusted":true,
             "acceptsOpEds":true,"opEdGuidelines":"800 words.","locale":{"id":"l-1","name":"Salt Lake City"},
             "person":{"id":"p-9","name":"QSaltLake"}}]}}}
            """#)
        case "Publication":
            return .json(status: 200, body: #"{"data":{"soapbox":{"publication":null}}}"#)
        default:
            return .json(status: 200, body: #"""
            {"data":{"soapbox":{"myOpEds":[{"id":"a-2","slug":"fund-the-center","title":"Fund the center",
             "byline":"Sam R.","kind":"OP_ED","edited":false,"pinned":false,"teaser":false,"status":"DECLINED",
             "reviewNote":"Ran a similar piece","submittedAt":"2027-05-01T00:00:00Z","publication":
            """# + publicationJSON + "}]}}}")
        }
    }
    let client = soapboxClient(stub)

    let publication = try #require(try await client.publications().first)
    #expect(publication.opEdGuidelines == "800 words.")
    #expect(publication.locale?.name == "Salt Lake City")
    #expect(try await client.publication(id: "pub-2") == nil)
    let opEd = try #require(try await client.myOpEds().first)
    #expect(opEd.isOpEd)
    #expect(opEd.status == .declined)
    #expect(opEd.reviewNote == "Ran a similar piece")
    #expect(SoapboxCopy.status(.declined) == "Not running")
}

@Test func submittingAnOpEdSendsItsFields() async throws {
    let stub = Stub { _ in
        .json(status: 200, body: #"""
        {"data":{"submitOpEd":{"article":{"id":"a-3","slug":"fund-the-center","title":"Fund the center","byline":"Sam R.",
         "kind":"OP_ED","edited":false,"pinned":false,"teaser":false,"status":"SUBMITTED","publication":
        """# + publicationJSON + "}}}}")
    }

    let article = try await soapboxClient(stub).submitOpEd(publicationID: "pub-1", title: "Fund the center",
                                                           body: "It matters.")

    #expect(article.status == .submitted)
    let request = try #require(stub.requests.first)
    #expect(request.operationName == "SubmitOpEd")
    #expect(request.variables["body"] as? String == "It matters.")
    #expect(request.variables["byline"] is NSNull)
}

@Test func aRefusedOpEdThrows() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"submitOpEd":{"article":null}}}"#) }

    await #expect(throws: OpEdNotSubmitted.self) {
        try await soapboxClient(stub).submitOpEd(publicationID: "pub-1", title: "T", body: "B", byline: "Me")
    }
    #expect(stub.requests.first?.variables["byline"] as? String == "Me")
}

@Test func theSoapboxCopyCoversEveryStatus() {
    for status in ArticleStatus.allCases { #expect(!SoapboxCopy.status(status).isEmpty) }
    #expect(SoapboxCopy.writeOpEd == "Write an op-ed")
}
