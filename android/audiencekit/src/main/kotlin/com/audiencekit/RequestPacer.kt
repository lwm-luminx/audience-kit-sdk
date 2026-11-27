package com.audiencekit

import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.random.Random

/**
 * Keeps one client from flooding the API (a request storm), whatever the app's timers and retries do.
 *
 * - **Pacing.** A token bucket: up to [burst] requests at once, refilling at [perSecond]. A request beyond that waits
 *   its turn.
 * - **Backing off.** When the API answers 429 (rate limited), or 503 (unavailable) with a `Retry-After`, every request
 *   the client makes is held back until the answer's `Retry-After` has passed, or, without one, for 1, 2, 4… seconds up to
 *   [maximumBackoffMillis] after each one in a row (with jitter). A held-back request fails at once with
 *   [AudienceKitException.Http] 429 and never reaches the network, so a cached answer stands in where there is one
 *   ([GraphQLCache]). The first answer that doesn't ask for one ends the backoff.
 *
 * [AudienceKitClient] keeps one and sends every HTTP request through it.
 */
public class RequestPacer(
    public val burst: Double = 20.0,
    public val perSecond: Double = 8.0,
    public val maximumBackoffMillis: Long = 120_000,
    private val clock: () -> Long = System::currentTimeMillis,
    private val jitter: () -> Double = { Random.nextDouble(0.0, 0.25) },
) {
    private val mutex = Mutex()
    private var tokens = max(1.0, burst)
    private var refilledAt: Long? = null
    private var pausedUntil: Long? = null
    private var strikes = 0

    /** What to do with a request now. */
    public sealed interface Admission {
        public data object Send : Admission
        public data class Wait(val millis: Long) : Admission
        public data class Paused(val retryAfterMillis: Long) : Admission
    }

    /** Whether a request may go out now. [Admission.Send] takes a token; [Admission.Wait] means ask again after it. */
    public suspend fun admit(): Admission = mutex.withLock {
        val now = clock()
        pausedUntil?.let { if (it > now) return@withLock Admission.Paused(it - now) }
        pausedUntil = null
        refilledAt?.let { tokens = min(max(1.0, burst), tokens + max(0L, now - it) / 1000.0 * perSecond) }
        refilledAt = now
        if (tokens >= 1) {
            tokens -= 1
            Admission.Send
        } else {
            Admission.Wait(max(1L, ((1 - tokens) / perSecond * 1000).toLong()))
        }
    }

    /** Waits for a turn, or throws while the API has asked this client to wait. */
    public suspend fun acquire() {
        while (true) {
            when (val admission = admit()) {
                Admission.Send -> return
                is Admission.Wait -> delay(admission.millis)
                is Admission.Paused -> throw AudienceKitException.Http(429)
            }
        }
    }

    /** Learns from a response: 429, or 503 with a `Retry-After`, starts (or lengthens) a backoff; anything else ends it. */
    public suspend fun observe(status: Int, retryAfter: String?): Unit = mutex.withLock {
        if (status != 429 && !(status == 503 && retryAfterMillis(retryAfter, clock()) != null)) {
            strikes = 0
            return@withLock
        }
        strikes += 1
        val now = clock()
        val fallback = (2.0.pow(min(strikes - 1, 6)) * 1000).toLong()
        val wait = min(retryAfterMillis(retryAfter, now) ?: fallback, maximumBackoffMillis)
        val until = now + (wait * (1 + jitter())).toLong()
        pausedUntil = max(pausedUntil ?: until, until)
    }

    /** When the API has asked this client to wait until (epoch milliseconds), if it still has. */
    public suspend fun pausedUntil(): Long? = mutex.withLock { pausedUntil?.takeIf { it > clock() } }

    internal companion object {
        /** A `Retry-After` value in milliseconds: delta-seconds, or an HTTP date. */
        fun retryAfterMillis(value: String?, now: Long): Long? {
            val text = value?.trim().orEmpty()
            if (text.isEmpty()) return null
            text.toDoubleOrNull()?.let { return max(0L, (it * 1000).toLong()) }
            return runCatching {
                max(0L, ZonedDateTime.parse(text, DateTimeFormatter.RFC_1123_DATE_TIME).toInstant().toEpochMilli() - now)
            }.getOrNull()
        }
    }
}
