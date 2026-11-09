package com.audiencekit

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

private fun soapboxClient(stub: StubTransport): AudienceKitClient = AudienceKitClient(
    AudienceKitConfiguration(baseUrl = StubTransport.BASE_URL, audienceId = "b0f8b66a-e636-495d-9475-0f5317ea08e2"),
    InMemoryTokenStore("session-token"),
    stub,
)

private fun RecordedRequest.document(): String = (jsonBody()["query"] as JsonPrimitive).content
private fun RecordedRequest.operation(): String? = (jsonBody()["operationName"] as? JsonPrimitive)?.content
private fun RecordedRequest.variable(name: String) = jsonBody()["variables"]?.jsonObject?.get(name)

private const val PUBLICATION_JSON =
    """{"id":"pub-1","name":"QSaltLake","photoUrl":null,"trusted":true,"acceptsOpEds":true}"""
private const val ARTICLE_JSON = """
{"id":"a-1","slug":"pride-2027","title":"Pride 2027","summary":"What's on","byline":"QSaltLake","kind":"ARTICLE",
 "publishedAt":"2027-06-01T16:00:00Z","edited":false,"pinned":true,"teaser":false,"canonicalUrl":null,
 "disclosure":"QSaltLake sponsors the festival.","heroPhotoUrl":null,"heroAltText":null,"publication":$PUBLICATION_JSON}
"""

/** Introspection for an audience without the Soapbox module: no `soapbox`, no `articles` anywhere. */
private fun withoutSoapbox(request: RecordedRequest): StubTransport.Reply {
    val entries = Regex("""(t\d+): __type\(name: "(\w+)"\)""").findAll(request.document()).map { match ->
        val (alias, _) = match.destructured
        "\"$alias\":{\"fields\":[{\"name\":\"id\"},{\"name\":\"name\"}]}"
    }
    return StubTransport.json(200, """{"data":{${entries.joinToString(",")}}}""")
}

private val undefinedSoapbox = StubTransport.json(
    200,
    """{"errors":[{"message":"Field 'soapbox' doesn't exist on type 'Audience'","extensions":{"code":"undefinedField"}}]}""",
)

class SoapboxTest {
    @Test
    fun aLocalesNewsDecodes() = runTest {
        val stub = StubTransport {
            StubTransport.json(200, """{"data":{"soapbox":{"articles":{"nodes":[$ARTICLE_JSON]}}}}""")
        }

        val articles = soapboxClient(stub).articles(localeId = "l-1", first = 10)

        val article = articles.single()
        assertEquals("Pride 2027", article.title)
        assertEquals("QSaltLake", article.publication.name)
        assertTrue(article.pinned)
        assertFalse(article.isOpEd)
        assertEquals("QSaltLake sponsors the festival.", article.disclosure)
        assertNull(article.body)
        val request = stub.requests.single()
        assertEquals("Articles", request.operation())
        assertEquals("l-1", request.variable("localeId")!!.jsonPrimitive.content)
        assertEquals(JsonNull, request.variable("publicationId"))
    }

    @Test
    fun anArticleReadsItsBodyAndSubjects() = runTest {
        val json = ARTICLE_JSON.trim().removeSuffix("}") +
            ""","body":"# Pride","venues":[{"id":"v-1","name":"Club Try-Angles"}],"events":[],"people":[],"locales":[]}"""
        val stub = StubTransport { StubTransport.json(200, """{"data":{"soapbox":{"article":$json}}}""") }

        val article = soapboxClient(stub).article("a-1")

        assertEquals("# Pride", article?.body)
        assertEquals(listOf(ArticleSubject("v-1", "Club Try-Angles")), article?.venues)
        assertTrue("body" in stub.requests.single().document())
    }

    @Test
    fun articlesAboutEachKindOfListingReadTheirMixin() = runTest {
        val list = """{"articles":{"list":{"nodes":[$ARTICLE_JSON]}}}"""
        val stub = StubTransport { request ->
            val document = request.document()
            val data = when {
                "venues {" in document -> """{"venues":{"venue":$list}}"""
                "events {" in document -> """{"events":{"event":$list}}"""
                "people {" in document -> """{"people":{"person":$list}}"""
                else -> """{"locale":$list}"""
            }
            StubTransport.json(200, """{"data":$data}""")
        }
        val client = soapboxClient(stub)

        for (topic in listOf(
            ArticleTopic.Venue("v-1"), ArticleTopic.Event("e-1"), ArticleTopic.Person("p-1"), ArticleTopic.Locale("l-1"),
        )) {
            assertEquals(listOf("a-1"), client.articlesAbout(topic, first = 3).map { it.id })
        }
        assertEquals(List(4) { "ArticlesAbout" }, stub.requests.map { it.operation() })
        assertEquals("p-1", stub.requests[2].variable("id")!!.jsonPrimitive.content)
    }

    @Test
    fun anAudienceWithoutSoapboxGetsNothing() = runTest {
        val stub = StubTransport { request ->
            when {
                request.operation() == "SchemaFields" -> withoutSoapbox(request)
                "soapbox" in request.document() || "articles" in request.document() -> undefinedSoapbox
                else -> StubTransport.json(200, """{"data":{"id":"b0f8b66a-e636-495d-9475-0f5317ea08e2"}}""")
            }
        }
        val client = soapboxClient(stub)

        assertEquals(emptyList(), client.articles())
        assertNull(client.article("a-1"))
        assertEquals(emptyList(), client.publications())
        assertNull(client.publication("pub-1"))
        assertEquals(emptyList(), client.myOpEds())
        assertEquals(emptyList(), client.articlesAbout(ArticleTopic.Venue("v-1")))
        assertEquals(
            listOf("Articles", "SchemaFields", "Articles", "Article", "Publications", "Publication", "MyOpEds", "ArticlesAbout"),
            stub.requests.map { it.operation() },
        )
        assertEquals("query ArticlesAbout { id }", stub.requests.last().document())
    }

    @Test
    fun publicationsAndMyOpEdsDecode() = runTest {
        val stub = StubTransport { request ->
            when (request.operation()) {
                "Publications" -> StubTransport.json(
                    200,
                    """{"data":{"soapbox":{"publications":[{"id":"pub-1","name":"QSaltLake","masthead":"QSaltLake",
                    "trusted":true,"acceptsOpEds":true,"opEdGuidelines":"800 words.","locale":{"id":"l-1","name":"Salt Lake City"},
                    "person":{"id":"p-9","name":"QSaltLake"}}]}}}""",
                )
                "Publication" -> StubTransport.json(200, """{"data":{"soapbox":{"publication":null}}}""")
                else -> StubTransport.json(
                    200,
                    """{"data":{"soapbox":{"myOpEds":[{"id":"a-2","title":"Fund the center","kind":"OP_ED",
                    "status":"DECLINED","reviewNote":"Ran a similar piece","submittedAt":"2027-05-01T00:00:00Z",
                    "publication":$PUBLICATION_JSON}]}}}""",
                )
            }
        }
        val client = soapboxClient(stub)

        val publication = client.publications().single()
        assertEquals("800 words.", publication.opEdGuidelines)
        assertEquals("Salt Lake City", publication.locale?.name)
        assertNull(client.publication("pub-2"))
        val opEd = client.myOpEds().single()
        assertTrue(opEd.isOpEd)
        assertEquals(ArticleStatus.DECLINED, opEd.status)
        assertEquals("Not running", SoapboxCopy.status(opEd.status!!))
    }

    @Test
    fun submittingAnOpEdSendsItsFields() = runTest {
        val stub = StubTransport {
            StubTransport.json(
                200,
                """{"data":{"submitOpEd":{"article":{"id":"a-3","title":"Fund the center","kind":"OP_ED",
                "status":"SUBMITTED","publication":$PUBLICATION_JSON}}}}""",
            )
        }

        val article = soapboxClient(stub).submitOpEd("pub-1", "Fund the center", "It matters.")

        assertEquals(ArticleStatus.SUBMITTED, article.status)
        val request = stub.requests.single()
        assertEquals("SubmitOpEd", request.operation())
        assertEquals("It matters.", request.variable("body")!!.jsonPrimitive.content)
        assertEquals(JsonNull, request.variable("byline"))
    }

    @Test
    fun aRefusedOpEdThrows() = runTest {
        val stub = StubTransport { StubTransport.json(200, """{"data":{"submitOpEd":{"article":null}}}""") }

        assertFailsWith<OpEdNotSubmittedException> { soapboxClient(stub).submitOpEd("pub-1", "T", "B", byline = "Me") }
        assertEquals("Me", stub.requests.single().variable("byline")!!.jsonPrimitive.content)
    }

    @Test
    fun theCopyCoversEveryStatus() {
        for (status in ArticleStatus.entries) assertTrue(SoapboxCopy.status(status).isNotEmpty())
        assertEquals("Write an op-ed", SoapboxCopy.WRITE_OP_ED)
    }
}
