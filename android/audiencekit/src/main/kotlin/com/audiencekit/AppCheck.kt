package com.audiencekit

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlin.time.TimeSource

/**
 * A "Check the app" run: the app's own list of everything it reads, one step at a time, with what each returned or
 * why it failed, so a broken screen can be traced to the call behind it. The Swift SDK's `AppCheck`, with the same
 * steps, marks and report, so a report from either app reads the same.
 *
 * The app writes the steps, since only it knows what its screens load; a later step can use what an earlier one found:
 *
 * ```kotlin
 * check.run {
 *     step("Signed in") { client.me()?.let { "As ${it.firstName}." } }
 *     var localeId: String? = null
 *     step("Your locale") { closestLocale()?.also { localeId = it.id }?.name }
 *     if (localeId == null) skip("Upcoming events", because = "No locale to look in.")
 * }
 * ```
 */
public class AppCheck {
    public enum class Outcome(public val mark: String) {
        /** It worked and found something. */
        OK("OK"),

        /** It worked and found nothing: often the reason a screen is empty. */
        EMPTY("EMPTY"),

        /** It threw. */
        FAILED("FAIL"),

        /** The app didn't run it ([skip]), usually because an earlier step found nothing. */
        SKIPPED("SKIP"),
    }

    public data class Step(val name: String, val outcome: Outcome, val detail: String, val milliseconds: Long)

    /** An error a step throws to fail with a plain sentence ("Location is off for this app."). */
    public class Problem(message: String) : Exception(message)

    /** What a run's state is now, for a screen to draw. */
    public data class State(val steps: List<Step> = emptyList(), val isRunning: Boolean = false) {
        val hasFailures: Boolean get() = steps.any { it.outcome == Outcome.FAILED }
    }

    private val _state = MutableStateFlow(State())
    public val state: StateFlow<State> = _state.asStateFlow()
    public val steps: List<Step> get() = _state.value.steps

    /** Clears the steps and runs [checks]. A run already going is left to finish and this one is ignored. */
    public suspend fun run(checks: suspend AppCheck.() -> Unit) {
        if (_state.value.isRunning) return
        _state.value = State(isRunning = true)
        try {
            checks()
        } finally {
            _state.update { it.copy(isRunning = false) }
        }
    }

    /** Times one step. [body] returns a one-line summary of what it found, or null when it found nothing. */
    public suspend fun step(name: String, body: suspend () -> String?): Outcome {
        val started = TimeSource.Monotonic.markNow()
        val (outcome, detail) = try {
            body()?.let { Outcome.OK to it } ?: (Outcome.EMPTY to "Nothing came back.")
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Throwable) {
            Outcome.FAILED to describe(error)
        }
        append(Step(name, outcome, detail, started.elapsedNow().inWholeMilliseconds))
        return outcome
    }

    /** Records a step that wasn't run, and why. */
    public fun skip(name: String, because: String) {
        append(Step(name, Outcome.SKIPPED, because, 0))
    }

    /**
     * Everything on one plain-text page for a bug report: the title line (app, version, server), each step, then the
     * log's recent failed requests.
     */
    public fun report(title: String, log: GraphQLOperationLog? = null): String {
        val lines = mutableListOf(title)
        steps.mapTo(lines) { "${it.outcome.mark} ${it.name} (${it.milliseconds} ms): ${it.detail}" }
        val failures = log?.failures().orEmpty()
        if (failures.isNotEmpty()) {
            lines += "Failed requests:"
            failures.mapTo(lines) { "- ${it.name ?: "unnamed"}: ${it.error.orEmpty()}" }
        }
        return lines.joinToString("\n")
    }

    private fun append(step: Step) {
        _state.update { it.copy(steps = it.steps + step) }
    }

    public companion object {
        /** The error's own sentence where it has one, so GraphQL errors read as the server put them. */
        public fun describe(error: Throwable): String = error.message?.takeIf { it.isNotBlank() } ?: error.toString()
    }
}

/**
 * The client's recent GraphQL operations, for "Check the app" to list the failed ones. Hand it to [AudienceKitClient]
 * as its monitor; [also] passes every event on to another monitor (New Relic, say) too.
 */
public class GraphQLOperationLog(
    private val capacity: Int = 50,
    private val also: GraphQLMonitor? = null,
) : GraphQLMonitor {
    private val entries = ArrayDeque<GraphQLOperationEvent>()

    override fun record(event: GraphQLOperationEvent) {
        synchronized(entries) {
            entries.addLast(event)
            while (entries.size > capacity) entries.removeFirst()
        }
        also?.record(event)
    }

    /** Everything recorded, oldest first. */
    public fun entries(): List<GraphQLOperationEvent> = synchronized(entries) { entries.toList() }

    /** The failed operations, newest first. */
    public fun failures(): List<GraphQLOperationEvent> = entries().filter { it.error != null }.reversed()
}
