package com.audiencekit

import kotlinx.serialization.Serializable

// GitHub: the community's GitHub organization, its public repositories and its public GitHub Projects with each item's
// Status, read by the audience's own GitHub App (the API's `github` mixin, doc/GITHUB.md). Audiences without a GitHub
// App don't have the mixin, so every helper here returns nothing for them.

/** The community's GitHub organization. */
@Serializable
public data class GitHubOrganization(
    val login: String,
    val name: String? = null,
    val description: String? = null,
    val url: String,
    val avatarUrl: String? = null,
    val websiteUrl: String? = null,
) {
    /** Its display name, else its login. */
    val displayName: String get() = name ?: login
}

/** One of the organization's public repositories. */
@Serializable
public data class GitHubRepository(
    val name: String,
    val nameWithOwner: String,
    val description: String? = null,
    val url: String,
    val language: String? = null,
    val stars: Int = 0,
    val forks: Int = 0,
    val openIssues: Int = 0,
    /** ISO 8601. */
    val pushedAt: String? = null,
    val topics: List<String> = emptyList(),
)

/** A GitHub account, as an item's assignee. */
@Serializable
public data class GitHubPerson(val login: String, val avatarUrl: String? = null, val url: String? = null)

/** A label on an issue or pull request; [color] is six hex digits without `#`. */
@Serializable
public data class GitHubLabel(val name: String, val color: String? = null)

/** One of a project's Status columns (Todo, In Progress, Done), in the project's order. */
@Serializable
public data class GitHubStatus(
    val id: String,
    val name: String,
    /** GitHub's name for its color: GRAY, BLUE, GREEN, YELLOW, ORANGE, RED, PINK or PURPLE. */
    val color: String? = null,
    val description: String? = null,
)

/** What a project item is. */
public enum class GitHubItemType {
    ISSUE,
    PULL_REQUEST,

    /** A draft on the project itself: no repository, number or link. */
    DRAFT_ISSUE,
}

/** An item on a project: an issue, pull request or draft, with its Status. */
@Serializable
public data class GitHubProjectItem(
    val id: String,
    val type: GitHubItemType = GitHubItemType.ISSUE,
    val title: String,
    val number: Int? = null,
    val url: String? = null,
    /** OPEN, CLOSED or MERGED as GitHub says; null for drafts. */
    val state: String? = null,
    /** owner/name; null for drafts. */
    val repository: String? = null,
    /** The name of its Status column ([GitHubProject.statuses]), null when unset. */
    val status: String? = null,
    val assignees: List<GitHubPerson> = emptyList(),
    val labels: List<GitHubLabel> = emptyList(),
    /** ISO 8601. */
    val updatedAt: String? = null,
) {
    /** "website#7" for issues and pull requests; null for drafts. */
    val reference: String?
        get() = if (repository == null || number == null) null else "${repository.substringAfterLast('/')}#$number"

    /** Whether it's closed or merged. */
    val isDone: Boolean get() = state == "CLOSED" || state == "MERGED"
}

/** A board column: a Status and its items. */
public data class GitHubColumn(val status: String, val items: List<GitHubProjectItem>)

/** One of the organization's public GitHub Projects. Lists leave out [items] and [readme]; [gitHubProject] reads them. */
@Serializable
public data class GitHubProject(
    val number: Int,
    val title: String,
    val shortDescription: String? = null,
    val readme: String? = null,
    val url: String,
    val itemCount: Int = 0,
    /** ISO 8601. */
    val updatedAt: String? = null,
    val statuses: List<GitHubStatus> = emptyList(),
    val items: List<GitHubProjectItem>? = null,
) {
    /** Its items as a board: one column per Status in the project's order, then "No status" when any item has none. */
    val columns: List<GitHubColumn>
        get() {
            val all = items.orEmpty()
            val known = statuses.map { it.name }.toSet()
            val columns = statuses.map { status -> GitHubColumn(status.name, all.filter { it.status == status.name }) }
            val unsorted = all.filter { it.status == null || it.status !in known }
            return if (unsorted.isEmpty()) columns else columns + GitHubColumn(GitHubCopy.NO_STATUS, unsorted)
        }
}

/** The community: its organization, repositories and projects, in one read for a GitHub tab. */
public data class GitHubCommunity(
    val organization: GitHubOrganization?,
    val repositories: List<GitHubRepository>,
    val projects: List<GitHubProject>,
    /**
     * The signed-in person's connected GitHub login, whose items [myGitHubItems] lists; null until they connect GitHub
     * (show [GitHubCopy.CONNECT_TO_SEE_YOUR_WORK] then).
     */
    val viewerLogin: String? = null,
)

/**
 * The community's GitHub organization, its public repositories (most recently pushed first) and its open public
 * projects (without items). Null when the audience has no GitHub App.
 */
public suspend fun AudienceKitClient.gitHubCommunity(repositories: Int = 30): GitHubCommunity? = graphQL(
    GitHubQueries.TYPES,
    GitHubResponse.serializer(),
    graphQLVariables("first" to repositories),
    "GitHubCommunity",
    GitHubQueries::community,
).github?.let {
    GitHubCommunity(it.organization, it.repositories.orEmpty(), it.projects.orEmpty(), it.viewerLogin)
}

/**
 * A public project with its README and items (the first 100, in the project's order); [GitHubProject.columns] groups
 * them by Status. Null when there's no such public project or the audience has no GitHub App.
 */
public suspend fun AudienceKitClient.gitHubProject(number: Int): GitHubProject? = graphQL(
    GitHubQueries.TYPES,
    GitHubResponse.serializer(),
    graphQLVariables("number" to number),
    "GitHubProject",
    GitHubQueries::project,
).github?.project

/**
 * Items on the open public projects assigned to the signed-in person's connected GitHub account
 * ([GitHubCommunity.viewerLogin]). Empty until they connect GitHub.
 */
public suspend fun AudienceKitClient.myGitHubItems(): List<GitHubProjectItem> = graphQL(
    GitHubQueries.TYPES,
    GitHubResponse.serializer(),
    null,
    "MyGitHubItems",
    GitHubQueries::myItems,
).github?.myItems.orEmpty()

/** The words around GitHub, the same as the Swift SDK's, so both apps say the same thing. */
public object GitHubCopy {
    public const val TITLE: String = "GitHub"
    public const val PROJECTS: String = "Projects"
    public const val REPOSITORIES: String = "Repositories"
    public const val MY_WORK: String = "Assigned to you"
    public const val NO_STATUS: String = "No status"
    public const val OPEN_ON_GITHUB: String = "Open on GitHub"
    public const val CONNECT_TO_SEE_YOUR_WORK: String = "Connect GitHub to see what's assigned to you."
    public const val NOTHING_ASSIGNED: String = "Nothing on the projects is assigned to you."

    public fun type(type: GitHubItemType): String = when (type) {
        GitHubItemType.ISSUE -> "Issue"
        GitHubItemType.PULL_REQUEST -> "Pull request"
        GitHubItemType.DRAFT_ISSUE -> "Draft"
    }
}

internal object GitHubQueries {
    /** The type the documents depend on: the root's `github`. */
    val TYPES: List<String> = listOf("Audience")

    const val ITEM_FIELDS: String = "id type title number url state repository status updatedAt " +
        "assignees { login avatarUrl url } labels { name color }"
    const val PROJECT_FIELDS: String =
        "number title shortDescription url itemCount updatedAt statuses { id name color description }"

    /** The document when the audience has no GitHub App: asks for nothing the helpers decode. */
    fun noGitHub(name: String): String = "query $name { id }"

    fun community(shape: SchemaShape): String = if (!shape.has("Audience", "github")) noGitHub("GitHubCommunity") else """
        query GitHubCommunity(${'$'}first: Int) {
          github {
            viewerLogin
            organization { login name description url avatarUrl websiteUrl }
            repositories(first: ${'$'}first) {
              name nameWithOwner description url language stars forks openIssues pushedAt topics
            }
            projects { $PROJECT_FIELDS }
          }
        }
    """.trimIndent()

    fun project(shape: SchemaShape): String = if (!shape.has("Audience", "github")) noGitHub("GitHubProject") else """
        query GitHubProject(${'$'}number: Int!) {
          github { project(number: ${'$'}number) { $PROJECT_FIELDS readme items { $ITEM_FIELDS } } }
        }
    """.trimIndent()

    fun myItems(shape: SchemaShape): String =
        if (!shape.has("Audience", "github")) noGitHub("MyGitHubItems")
        else "query MyGitHubItems { github { myItems { $ITEM_FIELDS } } }"
}

@Serializable
internal data class GitHubResponse(val github: Mixin? = null) {
    @Serializable
    data class Mixin(
        val viewerLogin: String? = null,
        val organization: GitHubOrganization? = null,
        val repositories: List<GitHubRepository>? = null,
        val projects: List<GitHubProject>? = null,
        val project: GitHubProject? = null,
        val myItems: List<GitHubProjectItem>? = null,
    )
}
