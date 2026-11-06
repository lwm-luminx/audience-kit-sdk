package com.audiencekit

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** The promo views the Swift SDK's PromoViews suite checks, on the Kotlin recorder (virtual time). */
@OptIn(ExperimentalCoroutinesApi::class)
class PromoViewRecorderTest {
    private val stub = StubTransport { StubTransport.json(200, """{"data":{"recordCardViews":{"recorded":1}}}""") }

    private fun TestScope.recorder(token: String? = "session-token") = PromoViewRecorder(
        AudienceKitClient(
            AudienceKitConfiguration(baseUrl = StubTransport.BASE_URL, audienceId = "b0f8b66a-e636-495d-9475-0f5317ea08e0"),
            InMemoryTokenStore(token),
            stub,
        ),
        backgroundScope,
        minimumOnScreenMillis = 1_000,
    )

    /** The client's HTTP runs off the test's virtual clock, so wait (in real time) for its calls to land. */
    private suspend fun TestScope.settle(transport: StubTransport = stub, count: Int) {
        advanceUntilIdle()
        withContext(Dispatchers.Default) { withTimeout(5_000) { while (transport.requests.size < count) delay(10) } }
        delay(50)
        advanceUntilIdle()
    }

    private fun calls() = stub.requests.map { it.jsonBody()["variables"]!!.jsonObject }
    private fun ids(index: Int) = calls()[index]["promoIds"]!!.jsonArray.map { it.jsonPrimitive.content }
    private fun layout(index: Int) = (calls()[index]["layoutId"] as? JsonPrimitive)?.takeIf { it.isString }?.content

    @Test
    fun aPromoOnScreenLongEnoughIsReportedOncePerLayout() = runTest {
        val recorder = recorder()

        recorder.appeared("p-1", "lay-1")
        recorder.appeared("p-2", "lay-1")
        advanceTimeBy(1_600)
        settle(count = 1)

        assertEquals(1, calls().size)
        assertEquals(setOf("p-1", "p-2"), ids(0).toSet())
        assertEquals("lay-1", layout(0))

        recorder.disappeared("p-1")
        recorder.appeared("p-1", "lay-1")
        advanceUntilIdle()
        assertEquals(1, calls().size, "seen again in the same layout: not reported again")
    }

    @Test
    fun aPromoScrolledPastQuicklyIsNotReported() = runTest {
        val recorder = recorder()

        recorder.appeared("p-1", "lay-1")
        advanceTimeBy(500)
        recorder.disappeared("p-1")
        advanceUntilIdle()

        assertTrue(calls().isEmpty())
    }

    @Test
    fun signedOutViewsAreNotReported() = runTest {
        val recorder = recorder(token = null)

        recorder.appeared("p-1", null)
        advanceUntilIdle()

        assertTrue(calls().isEmpty())
    }

    @Test
    fun onePromoInTwoLayoutsIsReportedInEach() = runTest {
        val recorder = recorder()

        recorder.appeared("p-1", "home")
        advanceTimeBy(1_100)
        recorder.disappeared("p-1")
        recorder.appeared("p-1", "venue")
        settle(count = 2)

        assertEquals(setOf("home", "venue"), calls().indices.map { layout(it) }.toSet())
    }

    @Test
    fun viewsAreSentTenAtATime() = runTest {
        val recorder = recorder()

        repeat(12) { recorder.appeared("p-$it", null) }
        settle(count = 2)

        assertEquals(listOf(2, 10), calls().indices.map { ids(it).size }.sorted())
    }

    @Test
    fun aFailedReportIsDroppedQuietly() = runTest {
        val failing = StubTransport { StubTransport.json(500, "{}") }
        val recorder = PromoViewRecorder(
            AudienceKitClient(AudienceKitConfiguration(baseUrl = StubTransport.BASE_URL, audienceId = "a"), InMemoryTokenStore("t"), failing),
            backgroundScope,
        )

        recorder.appeared("p-1", null)
        settle(failing, count = 1)

        assertEquals(1, failing.requests.size)
    }
}
