import AudienceCore
import Foundation

// GitHub: the community's GitHub organization, its public repositories and its public GitHub Projects with each item's
// Status, read by the audience's own GitHub App (the API's `github` mixin, doc/GITHUB.md). Audiences without a GitHub
// App don't have the mixin, so every helper here returns nothing for them.

/// The community's GitHub organization.
public struct GitHubOrganization: Codable, Sendable, Hashable {
    public let login: String
    public let name: String?
    public let description: String?
    public let url: String
    public let avatarUrl: String?
    public let websiteUrl: String?

    public init(login: String, name: String? = nil, description: String? = nil, url: String, avatarUrl: String? = nil,
                websiteUrl: String? = nil)
    {
        self.login = login
        self.name = name
        self.description = description
        self.url = url
        self.avatarUrl = avatarUrl
        self.websiteUrl = websiteUrl
    }

    /// Its display name, else its login.
    public var displayName: String { name ?? login }
}

/// One of the organization's public repositories.
public struct GitHubRepository: Codable, Sendable, Hashable, Identifiable {
    public var id: String { nameWithOwner }
    public let name: String
    public let nameWithOwner: String
    public let description: String?
    public let url: String
    public let language: String?
    public let stars: Int
    public let forks: Int
    public let openIssues: Int
    public let pushedAt: Date?
    public let topics: [String]

    public init(name: String, nameWithOwner: String, description: String? = nil, url: String, language: String? = nil,
                stars: Int = 0, forks: Int = 0, openIssues: Int = 0, pushedAt: Date? = nil, topics: [String] = [])
    {
        self.name = name
        self.nameWithOwner = nameWithOwner
        self.description = description
        self.url = url
        self.language = language
        self.stars = stars
        self.forks = forks
        self.openIssues = openIssues
        self.pushedAt = pushedAt
        self.topics = topics
    }
}

/// A GitHub account, as an item's assignee.
public struct GitHubPerson: Codable, Sendable, Hashable, Identifiable {
    public var id: String { login }
    public let login: String
    public let avatarUrl: String?
    public let url: String?

    public init(login: String, avatarUrl: String? = nil, url: String? = nil) {
        self.login = login
        self.avatarUrl = avatarUrl
        self.url = url
    }
}

/// A label on an issue or pull request; `color` is six hex digits without `#`.
public struct GitHubLabel: Codable, Sendable, Hashable {
    public let name: String
    public let color: String?

    public init(name: String, color: String? = nil) {
        self.name = name
        self.color = color
    }
}

/// One of a project's Status columns (Todo, In Progress, Done), in the project's order.
public struct GitHubStatus: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    /// GitHub's name for its color: GRAY, BLUE, GREEN, YELLOW, ORANGE, RED, PINK or PURPLE.
    public let color: String?
    public let description: String?

    public init(id: String, name: String, color: String? = nil, description: String? = nil) {
        self.id = id
        self.name = name
        self.color = color
        self.description = description
    }
}

/// What a project item is.
public enum GitHubItemType: String, Codable, Sendable, CaseIterable {
    case issue = "ISSUE"
    case pullRequest = "PULL_REQUEST"
    /// A draft on the project itself: no repository, number or link.
    case draftIssue = "DRAFT_ISSUE"
}

/// An item on a project: an issue, pull request or draft, with its Status.
public struct GitHubProjectItem: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let type: GitHubItemType
    public let title: String
    public let number: Int?
    public let url: String?
    /// OPEN, CLOSED or MERGED as GitHub says; nil for drafts.
    public let state: String?
    /// owner/name; nil for drafts.
    public let repository: String?
    /// The name of its Status column (``GitHubProject/statuses``), nil when unset.
    public let status: String?
    public let assignees: [GitHubPerson]
    public let labels: [GitHubLabel]
    public let updatedAt: Date?

    public init(id: String, type: GitHubItemType = .issue, title: String, number: Int? = nil, url: String? = nil,
                state: String? = nil, repository: String? = nil, status: String? = nil,
                assignees: [GitHubPerson] = [], labels: [GitHubLabel] = [], updatedAt: Date? = nil)
    {
        self.id = id
        self.type = type
        self.title = title
        self.number = number
        self.url = url
        self.state = state
        self.repository = repository
        self.status = status
        self.assignees = assignees
        self.labels = labels
        self.updatedAt = updatedAt
    }

    /// "website#7" for issues and pull requests; nil for drafts.
    public var reference: String? {
        guard let repository, let number else { return nil }
        return "\(repository.split(separator: "/").last.map(String.init) ?? repository)#\(number)"
    }

    /// Whether it's closed or merged.
    public var isDone: Bool { state == "CLOSED" || state == "MERGED" }
}

/// One of the organization's public GitHub Projects. Lists leave out ``items`` and ``readme``;
/// ``AudienceSession/gitHubProject(number:)`` reads them.
public struct GitHubProject: Codable, Sendable, Hashable, Identifiable {
    public var id: Int { number }
    public let number: Int
    public let title: String
    public let shortDescription: String?
    public let readme: String?
    public let url: String
    public let itemCount: Int
    public let updatedAt: Date?
    public let statuses: [GitHubStatus]
    public let items: [GitHubProjectItem]?

    public init(number: Int, title: String, shortDescription: String? = nil, readme: String? = nil, url: String,
                itemCount: Int = 0, updatedAt: Date? = nil, statuses: [GitHubStatus] = [],
                items: [GitHubProjectItem]? = nil)
    {
        self.number = number
        self.title = title
        self.shortDescription = shortDescription
        self.readme = readme
        self.url = url
        self.itemCount = itemCount
        self.updatedAt = updatedAt
        self.statuses = statuses
        self.items = items
    }

    /// Its items as a board: one column per Status in the project's order, then "No status" when any item has none.
    public var columns: [(status: String, items: [GitHubProjectItem])] {
        let items = items ?? []
        var columns = statuses.map { status in (status: status.name, items: items.filter { $0.status == status.name }) }
        let known = Set(statuses.map(\.name))
        let unsorted = items.filter { $0.status.map { !known.contains($0) } ?? true }
        if !unsorted.isEmpty { columns.append((status: GitHubCopy.noStatus, items: unsorted)) }
        return columns
    }
}

extension Queries {
    /// The type the GitHub documents depend on: the root's `github`.
    static let gitHubTypes = ["Audience"]

    static let gitHubItemFields = """
    id type title number url state repository status updatedAt assignees { login avatarUrl url } \
    labels { name color }
    """
    static let gitHubProjectFields = """
    number title shortDescription url itemCount updatedAt statuses { id name color description }
    """

    /// The document when the audience has no GitHub App: asks for nothing the helpers decode.
    static func noGitHub(_ name: String) -> String { "query \(name) { id }" }

    static func gitHubCommunity(_ shape: SchemaShape) -> String {
        guard shape.has("Audience", "github") else { return noGitHub("GitHubCommunity") }
        return """
        query GitHubCommunity($first: Int) {
          github {
            viewerLogin
            organization { login name description url avatarUrl websiteUrl }
            repositories(first: $first) {
              name nameWithOwner description url language stars forks openIssues pushedAt topics
            }
            projects { \(gitHubProjectFields) }
          }
        }
        """
    }

    static func gitHubProject(_ shape: SchemaShape) -> String {
        guard shape.has("Audience", "github") else { return noGitHub("GitHubProject") }
        return """
        query GitHubProject($number: Int!) {
          github { project(number: $number) { \(gitHubProjectFields) readme items { \(gitHubItemFields) } } }
        }
        """
    }

    static func myGitHubItems(_ shape: SchemaShape) -> String {
        guard shape.has("Audience", "github") else { return noGitHub("MyGitHubItems") }
        return "query MyGitHubItems { github { myItems { \(gitHubItemFields) } } }"
    }
}

/// The community: its organization, repositories and projects, in one read for a GitHub tab.
public struct GitHubCommunity: Codable, Sendable, Hashable {
    public let organization: GitHubOrganization?
    public let repositories: [GitHubRepository]
    public let projects: [GitHubProject]
    /// The signed-in person's connected GitHub login, whose items ``AudienceSession/myGitHubItems()`` lists; nil until
    /// they connect GitHub (show ``GitHubCopy/connectToSeeYourWork`` then).
    public let viewerLogin: String?

    public init(organization: GitHubOrganization? = nil, repositories: [GitHubRepository] = [],
                projects: [GitHubProject] = [], viewerLogin: String? = nil)
    {
        self.organization = organization
        self.repositories = repositories
        self.projects = projects
        self.viewerLogin = viewerLogin
    }
}

/// `github { … }` on the root, the audience; nil when the audience has no GitHub App.
struct GitHubResponse: Decodable, Sendable {
    struct Mixin: Decodable, Sendable {
        var viewerLogin: String?
        var organization: GitHubOrganization?
        var repositories: [GitHubRepository]?
        var projects: [GitHubProject]?
        var project: GitHubProject?
        var myItems: [GitHubProjectItem]?
    }

    var github: Mixin?
}

extension AudienceSession {
    /// The community's GitHub organization, its public repositories (most recently pushed first) and its open public
    /// projects (without items). Nil when the audience has no GitHub App.
    public func gitHubCommunity(repositories first: Int = 30) async throws -> GitHubCommunity? {
        let response = try await graphQL(types: Queries.gitHubTypes, variables: ["first": .int(first)],
                                         operationName: "GitHubCommunity", as: GitHubResponse.self,
                                         document: Queries.gitHubCommunity)
        guard let github = response.github else { return nil }
        return GitHubCommunity(organization: github.organization, repositories: github.repositories ?? [],
                               projects: github.projects ?? [], viewerLogin: github.viewerLogin)
    }

    /// A public project with its README and items (the first 100, in the project's order); ``GitHubProject/columns``
    /// groups them by Status. Nil when there's no such public project or the audience has no GitHub App.
    public func gitHubProject(number: Int) async throws -> GitHubProject? {
        try await graphQL(types: Queries.gitHubTypes, variables: ["number": .int(number)],
                          operationName: "GitHubProject", as: GitHubResponse.self,
                          document: Queries.gitHubProject).github?.project
    }

    /// Items on the open public projects assigned to the signed-in person's connected GitHub account
    /// (``GitHubCommunity/viewerLogin``). Empty until they connect GitHub.
    public func myGitHubItems() async throws -> [GitHubProjectItem] {
        try await graphQL(types: Queries.gitHubTypes, operationName: "MyGitHubItems", as: GitHubResponse.self,
                          document: Queries.myGitHubItems).github?.myItems ?? []
    }
}

/// The words around GitHub, shared with Android so both apps say the same thing.
public enum GitHubCopy {
    public static let title = "GitHub"
    public static let projects = "Projects"
    public static let repositories = "Repositories"
    public static let myWork = "Assigned to you"
    public static let noStatus = "No status"
    public static let openOnGitHub = "Open on GitHub"
    public static let connectToSeeYourWork = "Connect GitHub to see what's assigned to you."
    public static let nothingAssigned = "Nothing on the projects is assigned to you."
    public static func type(_ type: GitHubItemType) -> String {
        switch type {
        case .issue: "Issue"
        case .pullRequest: "Pull request"
        case .draftIssue: "Draft"
        }
    }
}
