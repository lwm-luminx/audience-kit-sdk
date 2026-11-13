@testable import AudienceCore
import Foundation
import Testing
@testable import AudienceKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let gitHubAudienceID = "00000000-0000-4000-8000-000000000072"

private func gitHubClient(_ stub: Stub) -> AudienceKitClient {
    let endpoint = URL(string: GraphQLEndpoint.consumer.path(audienceID: gitHubAudienceID),
                       relativeTo: stub.baseURL)!.absoluteURL
    let store = InMemoryCredentialStore(credential: Credential(token: "session-token", userId: "u-1",
                                                               audienceId: gitHubAudienceID, role: "member",
                                                               endpoint: endpoint))
    let configuration = AudienceKitConfiguration(baseURL: stub.baseURL, audienceID: gitHubAudienceID)
    return AudienceKitClient(configuration: configuration, credentialStore: store, session: stub.session)
}

private extension RecordedRequest {
    var query: String { ((try? jsonBody())?["query"] as? String) ?? "" }
    var operationName: String? { (try? jsonBody())?["operationName"] as? String }
    var variables: [String: Any] { ((try? jsonBody())?["variables"] as? [String: Any]) ?? [:] }
}

private let statusesJSON = #"[{"id":"a","name":"Todo","color":"GRAY","description":null},"#
    + #"{"id":"b","name":"In Progress","color":"YELLOW","description":"Someone is on it"}]"#
private let itemJSON = #"""
{"id":"PVTI_7","type":"ISSUE","title":"Port the site to Workers","number":7,
 "url":"https://github.com/hack-different/website/issues/7","state":"OPEN","repository":"hack-different/website",
 "status":"In Progress","updatedAt":"2026-11-12T10:00:00Z","assignees":[{"login":"octocat","avatarUrl":null,"url":null}],
 "labels":[{"name":"good first issue","color":"7057ff"}]}
"""#
private let draftJSON = #"""
{"id":"PVTI_9","type":"DRAFT_ISSUE","title":"Plan the meetup","number":null,"url":null,"state":null,
 "repository":null,"status":null,"updatedAt":null,"assignees":[],"labels":[]}
"""#

@Test func theCommunityDecodesItsOrganizationRepositoriesAndProjects() async throws {
    let body = #"""
    {"data":{"github":{"viewerLogin":"octocat",
      "organization":{"login":"hack-different","name":"Hack Different","description":null,
                      "url":"https://github.com/hack-different","avatarUrl":null,"websiteUrl":"https://hackdiffe.rent"},
      "repositories":[{"name":"website","nameWithOwner":"hack-different/website","description":"hackdiffe.rent",
                       "url":"https://github.com/hack-different/website","language":"JavaScript","stars":12,"forks":3,
                       "openIssues":4,"pushedAt":"2026-11-10T00:00:00Z","topics":["cloudflare-workers"]}],
      "projects":[{"number":1,"title":"Roadmap","shortDescription":null,"url":"https://github.com/orgs/hack-different/projects/1",
                   "itemCount":3,"updatedAt":"2026-11-12T10:00:00Z","statuses":
    """# + statusesJSON + "}]}}}"
    let stub = Stub { _ in .json(status: 200, body: body) }

    let community = try #require(try await gitHubClient(stub).gitHubCommunity(repositories: 10))

    #expect(community.organization?.displayName == "Hack Different")
    #expect(community.viewerLogin == "octocat")
    #expect(community.repositories.first?.stars == 12)
    #expect(community.repositories.first?.topics == ["cloudflare-workers"])
    #expect(community.projects.first?.statuses.map(\.name) == ["Todo", "In Progress"])
    #expect(community.projects.first?.items == nil)
    let request = try #require(stub.requests.last)
    #expect(request.operationName == "GitHubCommunity")
    #expect(request.variables["first"] as? Int == 10)
}

@Test func aProjectGroupsItsItemsByStatus() async throws {
    let project = #"{"number":1,"title":"Roadmap","shortDescription":null,"url":"u","itemCount":2,"updatedAt":null,"#
        + #""readme":"# Roadmap","statuses":"# + statusesJSON + #","items":["# + itemJSON + "," + draftJSON + "]}"
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"github":{"project":"# + project + "}}}") }

    let board = try #require(try await gitHubClient(stub).gitHubProject(number: 1))

    #expect(board.readme == "# Roadmap")
    #expect(board.columns.map(\.status) == ["Todo", "In Progress", GitHubCopy.noStatus])
    #expect(board.columns[1].items.first?.reference == "website#7")
    #expect(board.columns[2].items.first?.type == .draftIssue)
    #expect(board.columns[2].items.first?.reference == nil)
    #expect(stub.requests.last?.variables["number"] as? Int == 1)
}

@Test func myItemsAreThoseAssignedToMe() async throws {
    let stub = Stub { _ in .json(status: 200, body: #"{"data":{"github":{"myItems":["# + itemJSON + "]}}}") }

    let items = try await gitHubClient(stub).myGitHubItems()

    #expect(items.map(\.title) == ["Port the site to Workers"])
    #expect(items.first?.assignees.first?.login == "octocat")
    #expect(items.first?.isDone == false)
}

/// Introspection for an audience without a GitHub App: no `github` on the root.
private func withoutGitHub(_ request: RecordedRequest) -> StubResponse {
    let pattern = try! NSRegularExpression(pattern: #"(t\d+): __type\(name: "(\w+)"\)"#)
    let query = request.query
    let entries = pattern.matches(in: query, range: NSRange(query.startIndex..., in: query)).map { match in
        let alias = String(query[Range(match.range(at: 1), in: query)!])
        return #""\#(alias)":{"fields":[{"name":"id"},{"name":"name"}]}"#
    }
    return .json(status: 200, body: #"{"data":{"# + entries.joined(separator: ",") + "}}")
}

@Test func anAudienceWithoutAGitHubAppGetsNothing() async throws {
    let stub = Stub { request in
        if request.operationName == "SchemaFields" { return withoutGitHub(request) }
        if request.query.contains("github") {
            return .json(status: 200, body: #"""
            {"errors":[{"message":"Field 'github' doesn't exist on type 'Audience'","extensions":{"code":"undefinedField"}}]}
            """#)
        }
        return .json(status: 200, body: #"{"data":{"id":"00000000-0000-4000-8000-000000000072"}}"#)
    }
    let client = gitHubClient(stub)

    #expect(try await client.gitHubCommunity() == nil)
    #expect(try await client.gitHubProject(number: 1) == nil)
    #expect(try await client.myGitHubItems().isEmpty)
}
