package com.audiencekit

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.Serializable
import java.io.IOException
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

private const val CACHE_AUDIENCE = "00000000-0000-4000-8000-000000000044"

@Serializable
private data class Greeting(val hello: String)

/** Answers [answer] until [failure] is set. */
private class Flaky {
    var failure: StubTransport.Reply? = null
    var answer = "world"
    fun respond(): StubTransport.Reply = failure ?: StubTransport.json(200, """{"data":{"hello":"$answer"}}""")
}

private fun cachingClient(
    stub: StubTransport,
    cache: GraphQLCache = InMemoryGraphQLCache(),
    policy: GraphQLCachePolicy = GraphQLCachePolicy.NetworkFirst(),
    token: String = makeJwt(mapOf("sub" to "u-1")),
): AudienceKitClient = AudienceKitClient(
    AudienceKitConfiguration(baseUrl = StubTransport.BASE_URL, audienceId = CACHE_AUDIENCE),
    InMemoryTokenStore(token),
    stub,
    cache = cache,
    defaultCachePolicy = policy,
)

class GraphQLCacheTest {
    private val hello = "query Hello { hello }"

    @Test
    fun aFailedQueryReturnsTheLastGoodAnswer() = runTest {
        val flaky = Flaky()
        val client = cachingClient(StubTransport { flaky.respond() })
        val fresh = client.graphQLResult(hello, Greeting.serializer())
        assertEquals(GraphQLResultSource.NETWORK, fresh.source)
        assertFalse(fresh.isStale)

        for (failure in listOf(
            StubTransport.failure(IOException("offline")),
            StubTransport.json(503, "{}"),
            StubTransport.json(429, "{}"),
            StubTransport.json(200, """{"data":null,"errors":[{"message":"boom"}]}"""),
            StubTransport.json(200, """{"data":{"hello":{"no":1}}}"""),
        )) {
            flaky.failure = failure
            val kept = client.graphQLResult(hello, Greeting.serializer())
            assertEquals("world", kept.value.hello)
            assertEquals(GraphQLResultSource.CACHE, kept.source)
            assertTrue(kept.isStale)
            assertEquals(fresh.fetchedAtMillis, kept.fetchedAtMillis)
        }
    }

    @Test
    fun refusalsStillThrow() = runTest {
        val flaky = Flaky()
        val client = cachingClient(StubTransport { flaky.respond() })
        client.graphQL(hello, Greeting.serializer())
        flaky.failure = StubTransport.json(403, "{}")
        assertFailsWith<AudienceKitException.Forbidden> { client.graphQL(hello, Greeting.serializer()) }
        flaky.failure = StubTransport.json(404, "{}")
        assertFailsWith<AudienceKitException.NotFound> { client.graphQL(hello, Greeting.serializer()) }
        flaky.failure = StubTransport.json(
            200, """{"data":null,"errors":[{"message":"no","extensions":{"code":"undefinedField"}}]}""",
        )
        assertFailsWith<AudienceKitException.GraphQL> { client.graphQL(hello, Greeting.serializer()) }
    }

    @Test
    fun networkOnlyKeepsNothing() = runTest {
        val flaky = Flaky()
        val client = cachingClient(StubTransport { flaky.respond() }, policy = GraphQLCachePolicy.NetworkOnly)
        client.graphQL(hello, Greeting.serializer())
        flaky.failure = StubTransport.failure(IOException("offline"))
        assertFailsWith<AudienceKitException.Network> { client.graphQL(hello, Greeting.serializer()) }
    }

    @Test
    fun variablesAreOrderIndependent() = runTest {
        val stub = StubTransport { request ->
            val a = request.jsonBody()["variables"].toString()
            StubTransport.json(200, """{"data":{"hello":${kotlinx.serialization.json.JsonPrimitive(a)}}}""")
        }
        val client = cachingClient(stub)
        val doc = "query Hello(\$a: String) { hello }"
        client.graphQL(doc, Greeting.serializer(), graphQLVariables("a" to "x", "b" to 1))
        val kept = client.cachedGraphQL("query  Hello(\$a: String)\n{ hello }", Greeting.serializer(),
            graphQLVariables("b" to 1, "a" to "x"))
        assertNotNull(kept)
        assertNull(client.cachedGraphQL(doc, Greeting.serializer(), graphQLVariables("a" to "y")))
    }

    @Test
    fun mutationsAreKeptOnlyUnderAKey() = runTest {
        val flaky = Flaky()
        val client = cachingClient(StubTransport { flaky.respond() })
        val doc = "mutation Report(\$p: Int) { hello }"
        client.graphQL(doc, Greeting.serializer(), graphQLVariables("p" to 1))
        assertNull(client.cachedGraphQL(doc, Greeting.serializer(), graphQLVariables("p" to 1)))

        client.graphQL(doc, Greeting.serializer(), graphQLVariables("p" to 2), cacheKey = "now")
        flaky.failure = StubTransport.failure(IOException("lost"))
        val kept = client.graphQLResult(doc, Greeting.serializer(), graphQLVariables("p" to 3), cacheKey = "now")
        assertTrue(kept.isStale)
    }

    @Test
    fun cacheFirstAndRefresh() = runTest {
        val flaky = Flaky()
        val stub = StubTransport { flaky.respond() }
        val client = cachingClient(stub, policy = GraphQLCachePolicy.CacheFirst(freshForMillis = 60_000))
        client.graphQL(hello, Greeting.serializer())
        flaky.answer = "again"
        assertEquals("world", client.graphQL(hello, Greeting.serializer()).hello)
        assertEquals(1, stub.requests.size)

        assertEquals("again", client.graphQL(hello, Greeting.serializer(), cachePolicy = GraphQLCachePolicy.Refresh).hello)
        flaky.failure = StubTransport.failure(IOException("offline"))
        assertFailsWith<AudienceKitException.Network> {
            client.graphQL(hello, Greeting.serializer(), cachePolicy = GraphQLCachePolicy.Refresh)
        }
        assertEquals("again", client.graphQL(hello, Greeting.serializer(), cachePolicy = GraphQLCachePolicy.NetworkFirst()).hello)
    }

    @Test
    fun anotherPersonNeverSeesTheAnswerAndSignOutEmptiesTheCache() = runTest {
        val stub = StubTransport { StubTransport.json(200, """{"data":{"hello":"world"}}""") }
        val cache = InMemoryGraphQLCache()
        val first = cachingClient(stub, cache)
        first.graphQL(hello, Greeting.serializer())
        assertEquals(1, cache.size)
        val second = cachingClient(stub, cache, token = makeJwt(mapOf("sub" to "u-2")))
        assertNull(second.cachedGraphQL(hello, Greeting.serializer()))
        first.signOut()
        assertEquals(0, cache.size)
    }

    @Test
    fun fileCacheKeepsAnswersAcrossInstances() {
        val dir = Files.createTempDirectory("gql").toFile()
        try {
            FileGraphQLCache(dir).store(GraphQLCacheEntry("a", "1", System.currentTimeMillis()))
            FileGraphQLCache(dir).store(GraphQLCacheEntry("b", "2", 0))
            val cache = FileGraphQLCache(dir)
            assertEquals("1", cache.entry("a")?.body)
            assertNull(cache.entry("c"))
            cache.removeEntriesStoredBefore(1000)
            assertNull(cache.entry("b"))
            assertNotNull(cache.entry("a"))
            cache.removeAll()
            assertNull(cache.entry("a"))
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test
    fun visitedLocalesKeepTheRecentFew() {
        val visited = VisitedLocales(InMemoryVisitedLocaleStore(), limit = 2, windowMillis = 1000)
        val now = 10_000L
        visited.record("sf", "San Francisco", now - 2000)
        visited.record("den", "Denver", now - 30)
        visited.record("la", "Los Angeles", now - 20)
        visited.record("den", "Denver", now - 10)
        assertEquals(listOf("den", "la"), visited.recent(now).map { it.id })
        visited.removeAll()
        assertTrue(visited.recent(now).isEmpty())
    }

    @Test
    fun backoffDoublesAndResets() {
        var backoff = RefreshBackoff(baseMillis = 10, capMillis = 35)
        assertTrue(backoff.isDue(1000))
        backoff = backoff.failed(1000)
        assertEquals(20, backoff.intervalMillis)
        assertFalse(backoff.isDue(1019))
        assertTrue(backoff.isDue(1020))
        backoff = backoff.failed(1000)
        assertEquals(35, backoff.intervalMillis)
        assertEquals(1035, backoff.nextAtMillis())
        assertEquals(10, backoff.succeeded(1000).intervalMillis)
    }

    @Test
    fun cachedVenuesReadsTheLastListWithoutTheNetwork() = runTest {
        val body = """{"data":{"venues":{"list":{"nodes":[{"id":"v-1","name":"Purr","hidden":false,"order":1,""" +
            """"locale":{"id":"l-1","name":"San Francisco"},"tags":[]}]}}}}"""
        val cache = InMemoryGraphQLCache()
        val client = cachingClient(StubTransport { StubTransport.json(200, body) }, cache = cache)
        assertNull(client.cachedVenues())

        client.venues()

        // A relaunch: a new client that hasn't learned the audience's schema shape still finds the list.
        val offline = StubTransport { StubTransport.failure(IOException("offline")) }
        val relaunched = cachingClient(offline, cache = cache)
        assertEquals(listOf("v-1"), assertNotNull(relaunched.cachedVenues()).map { it.id })
        assertTrue(offline.requests.isEmpty())
        assertNull(relaunched.cachedVenues(maxAgeMillis = -1))
    }
}
