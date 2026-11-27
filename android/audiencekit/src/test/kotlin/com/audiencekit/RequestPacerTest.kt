package com.audiencekit

import kotlinx.coroutines.test.runTest
import java.time.ZoneOffset
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class RequestPacerTest {
    private var now = 1_800_000_000_000L
    private fun pacer(burst: Double = 20.0, perSecond: Double = 8.0, maximum: Long = 120_000) =
        RequestPacer(burst, perSecond, maximum, clock = { now }, jitter = { 0.0 })

    @Test
    fun sendsABurstThenMakesTheRestWaitTheirTurn() = runTest {
        val pacer = pacer(burst = 3.0, perSecond = 2.0)
        repeat(3) { assertEquals(RequestPacer.Admission.Send, pacer.admit()) }
        assertEquals(RequestPacer.Admission.Wait(500), pacer.admit())
        now += 500
        assertEquals(RequestPacer.Admission.Send, pacer.admit())
    }

    @Test
    fun holdsEveryRequestForRetryAfterOnA429() = runTest {
        val pacer = pacer()
        pacer.observe(429, "30")
        now += 10_000
        assertEquals(RequestPacer.Admission.Paused(20_000), pacer.admit())
        now += 20_000
        assertEquals(RequestPacer.Admission.Send, pacer.admit())
        assertNull(pacer.pausedUntil())
    }

    @Test
    fun backsOffExponentiallyWithoutRetryAfterAndStopsAtTheMaximum() = runTest {
        val pacer = pacer(maximum = 10_000)
        val waits = (0 until 6).map {
            pacer.observe(429, null)
            pacer.pausedUntil()!! - now
        }
        assertEquals(listOf(1_000L, 2_000, 4_000, 8_000, 10_000, 10_000), waits)
    }

    @Test
    fun a503WaitsOnlyWhenItSaysHowLong() = runTest {
        val pacer = pacer()
        pacer.observe(503, null)
        assertNull(pacer.pausedUntil())
        pacer.observe(503, "5")
        assertEquals(5_000L, pacer.pausedUntil()!! - now)
    }

    @Test
    fun anyOtherAnswerEndsTheStreak() = runTest {
        val pacer = pacer()
        pacer.observe(429, null)
        pacer.observe(429, null)
        now += 5_000
        pacer.observe(200, null)
        pacer.observe(429, null)
        assertEquals(1_000L, pacer.pausedUntil()!! - now)
    }

    @Test
    fun readsRetryAfterAsSecondsOrAnHTTPDate() {
        val date = DateTimeFormatter.RFC_1123_DATE_TIME.format(
            ZonedDateTime.ofInstant(Instant.ofEpochMilli(now + 45_000), ZoneOffset.UTC),
        )
        assertEquals(45_000L, RequestPacer.retryAfterMillis(date, now))
        assertEquals(12_000L, RequestPacer.retryAfterMillis("12", now))
        assertNull(RequestPacer.retryAfterMillis("soon", now))
    }

    @Test
    fun aClientStopsCallingTheAPIAfterA429UntilRetryAfter() = runTest {
        val stub = object : HttpTransport {
            var calls = 0
            override suspend fun execute(request: HttpRequest): HttpResponse {
                calls += 1
                return HttpResponse(429, """{"error":"RATE_LIMITED"}""".toByteArray(), mapOf("Retry-After" to "60"))
            }
        }
        val client = AudienceKitClient(
            AudienceKitConfiguration(baseUrl = StubTransport.BASE_URL, audienceId = "00000000-0000-4000-8000-000000000001"),
            InMemoryTokenStore(makeJwt(mapOf("sub" to "u-1"))),
            stub,
        )
        repeat(5) {
            assertFailsWith<AudienceKitException> { client.graphQL("{ name }", kotlinx.serialization.json.JsonObject.serializer()) }
        }
        assertEquals(1, stub.calls)
        assertNotNull(client.pacer.pausedUntil())
    }
}
