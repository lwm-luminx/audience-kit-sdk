package com.audiencekit

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

private fun gitHubClient(stub: StubTransport): AudienceKitClient = AudienceKitClient(
    AudienceKitConfiguration(baseUrl = StubTransport.BASE_URL, audienceId = "2416ce6c-f28a-4460-8b6f-840f3c0027c9"),
    InMemoryTokenStore("session-token"),
    stub,
)

private fun RecordedRequest.document(): String = (jsonBody()["query"] as JsonPrimitive).content
private fun RecordedRequest.operation(): String? = (jsonBody()["operationName"] as? JsonPrimitive)?.content
private fun RecordedRequest.variable(name: String) = jsonBody()["variables"]?.jsonObject?.get(name)

private const val STATUSES_JSON = """[{"id":"a","name":"Todo","color":"GRAY","description":null},
 {"id":"b","name":"In Progress","color":"YELLOW","description":"Someone is on it"}]"""
private const val ITEM_JSON = """
{"id":"PVTI_7","type":"ISSUE","title":"Port the site to Workers","number":7,
 "url":"https://github.com/hack-different/website/issues/7","state":"OPEN","repository":"hack-different/website",
 "status":"In Progress","updatedAt":"2026-11-12T10:00:00Z","assignees":[{"login":"octocat","avatarUrl":null,"url":null}],
 "labels":[{"name":"good first issue","color":"7057ff"}]}
"""
private const val DRAFT_JSON = """
{"id":"PVTI_9","type":"DRAFT_ISSUE","title":"Plan the meetup","number":null,"url":null,"state":null,
 "repository":null,"status":null,"updatedAt":null,"assignees":[],"labels":[]}
"""

class GitHubTest {
    @Test
    fun theCommunityDecodesItsOrganizationRepositoriesAndProjects() = runTest {
        val stub = StubTransport {
            StubTransport.json(
                200,
                """{"data":{"github":{"viewerLogin":"octocat",
                  "organization":{"login":"hack-different","name":"Hack Different","description":null,
                    "url":"https://github.com/hack-different","avatarUrl":null,"websiteUrl":"https://hackdiffe.rent"},
                  "repositories":[{"name":"website","nameWithOwner":"hack-different/website","description":null,
                    "url":"https://github.com/hack-different/website","language":"JavaScript","stars":12,"forks":3,
                    "openIssues":4,"pushedAt":"2026-11-10T00:00:00Z","topics":["cloudflare-workers"]}],
                  "projects":[{"number":1,"title":"Roadmap","shortDescription":null,"url":"u","itemCount":3,
                    "updatedAt":null,"statuses":$STATUSES_JSON}]}}}""",
            )
        }

        val community = gitHubClient(stub).gitHubCommunity(repositories = 10)!!

        assertEquals("Hack Different", community.organization?.displayName)
        assertEquals("octocat", community.viewerLogin)
        assertEquals(12, community.repositories.single().stars)
        assertEquals(listOf("Todo", "In Progress"), community.projects.single().statuses.map { it.name })
        assertNull(community.projects.single().items)
        val request = stub.requests.last()
        assertEquals("GitHubCommunity", request.operation())
        assertEquals(JsonPrimitive(10), request.variable("first"))
    }

    @Test
    fun aProjectGroupsItsItemsByStatus() = runTest {
        val stub = StubTransport {
            StubTransport.json(
                200,
                """{"data":{"github":{"project":{"number":1,"title":"Roadmap","shortDescription":null,"url":"u",
                  "itemCount":2,"updatedAt":null,"readme":"# Roadmap","statuses":$STATUSES_JSON,
                  "items":[$ITEM_JSON,$DRAFT_JSON]}}}}""",
            )
        }

        val board = gitHubClient(stub).gitHubProject(1)!!

        assertEquals("# Roadmap", board.readme)
        assertEquals(listOf("Todo", "In Progress", GitHubCopy.NO_STATUS), board.columns.map { it.status })
        assertEquals("website#7", board.columns[1].items.single().reference)
        assertEquals(GitHubItemType.DRAFT_ISSUE, board.columns[2].items.single().type)
        assertNull(board.columns[2].items.single().reference)
        assertTrue(stub.requests.last().document().contains("items"))
    }

    @Test
    fun myItemsAreThoseAssignedToMe() = runTest {
        val stub = StubTransport { StubTransport.json(200, """{"data":{"github":{"myItems":[$ITEM_JSON]}}}""") }

        val items = gitHubClient(stub).myGitHubItems()

        assertEquals("octocat", items.single().assignees.single().login)
        assertFalse(items.single().isDone)
    }

    @Test
    fun anAudienceWithoutAGitHubAppGetsNothing() = runTest {
        val stub = StubTransport { request ->
            when {
                request.operation() == "SchemaFields" -> {
                    val entries = Regex("""(t\d+): __type\(name: "(\w+)"\)""").findAll(request.document()).map {
                        "\"${it.groupValues[1]}\":{\"fields\":[{\"name\":\"id\"}]}"
                    }
                    StubTransport.json(200, """{"data":{${entries.joinToString(",")}}}""")
                }
                request.document().contains("github") -> StubTransport.json(
                    200,
                    """{"errors":[{"message":"Field 'github' doesn't exist on type 'Audience'","extensions":{"code":"undefinedField"}}]}""",
                )
                else -> StubTransport.json(200, """{"data":{"id":"2416ce6c-f28a-4460-8b6f-840f3c0027c9"}}""")
            }
        }
        val client = gitHubClient(stub)

        assertNull(client.gitHubCommunity())
        assertNull(client.gitHubProject(1))
        assertTrue(client.myGitHubItems().isEmpty())
    }
}
