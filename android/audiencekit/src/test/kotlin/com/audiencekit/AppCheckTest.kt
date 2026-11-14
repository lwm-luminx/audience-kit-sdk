package com.audiencekit

import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.milliseconds

class AppCheckTest {
    @Test
    fun recordsEachOutcomeAndReportsThem() = runTest {
        val check = AppCheck()
        val log = GraphQLOperationLog()
        log.record(GraphQLOperationEvent("Venues", "query", GraphQLEndpoint.CONSUMER, 12.milliseconds))
        log.record(GraphQLOperationEvent("Pings", "query", GraphQLEndpoint.CONSUMER, 30.milliseconds, error = "Timed out"))

        check.run {
            step("Signed in") { "As Rick." }
            step("Upcoming events") { null }
            step("Safety") { throw AppCheck.Problem("Location is off for this app.") }
            skip("Venues nearby", because = "No position yet.")
        }

        assertEquals(
            listOf(AppCheck.Outcome.OK, AppCheck.Outcome.EMPTY, AppCheck.Outcome.FAILED, AppCheck.Outcome.SKIPPED),
            check.steps.map { it.outcome },
        )
        assertTrue(check.state.value.hasFailures)
        assertFalse(check.state.value.isRunning)
        val report = check.report("Hot Mess 2.7 (1), https://api.audiencekit.com", log).lines()
        assertEquals("Hot Mess 2.7 (1), https://api.audiencekit.com", report[0])
        assertTrue(report[1].startsWith("OK Signed in ("))
        assertTrue(report[2].endsWith("Nothing came back."))
        assertTrue(report[3].startsWith("FAIL Safety (") && report[3].endsWith("Location is off for this app."))
        assertEquals("SKIP Venues nearby (0 ms): No position yet.", report[4])
        assertEquals(listOf("Failed requests:", "- Pings: Timed out"), report.drop(5))
    }

    @Test
    fun aNewRunStartsClean() = runTest {
        val check = AppCheck()
        check.run { step("One") { "1" } }
        check.run { step("Two") { "2" } }
        assertEquals(listOf("Two"), check.steps.map { it.name })
    }

    @Test
    fun theLogKeepsTheNewestAndPassesEventsOn() {
        val passed = mutableListOf<String?>()
        val log = GraphQLOperationLog(capacity = 2, also = { passed += it.name })
        listOf("A", "B", "C").forEach {
            log.record(GraphQLOperationEvent(it, "query", GraphQLEndpoint.CONSUMER, 1.milliseconds, error = "x"))
        }
        assertEquals(listOf("B", "C"), log.entries().map { it.name })
        assertEquals(listOf("C", "B"), log.failures().map { it.name })
        assertEquals(listOf<String?>("A", "B", "C"), passed)
    }
}
