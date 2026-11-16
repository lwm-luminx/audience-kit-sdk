package com.audiencekit

import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import java.io.File
import java.security.MessageDigest
import java.util.Base64
import java.util.concurrent.ConcurrentHashMap

/**
 * How a GraphQL call uses the on-device cache ([AudienceKitClient.graphQL]).
 *
 * The cache keeps the last good response for each query, so a flaky connection or a failing API shows the last thing
 * the person saw instead of an error. Only queries are kept, never mutations (unless the caller names a `cacheKey` for
 * a mutation that reads, such as a position report that returns what's nearby).
 */
public sealed interface GraphQLCachePolicy {
    /** Always ask the API; never read or write the cache. The default. */
    public data object NetworkOnly : GraphQLCachePolicy

    /**
     * Ask the API and keep a good answer. When the API can't answer (offline, a 5xx, a GraphQL error, a response the
     * app can't decode), return the last good answer instead, if it is no older than [maxAgeMillis]. Refusals (signed
     * out, forbidden, not found) still throw.
     */
    public data class NetworkFirst(val maxAgeMillis: Long = DEFAULT_MAX_AGE_MILLIS) : GraphQLCachePolicy

    /** Return a kept answer no older than [freshForMillis] without asking; otherwise behave as [NetworkFirst]. */
    public data class CacheFirst(val freshForMillis: Long, val maxAgeMillis: Long = DEFAULT_MAX_AGE_MILLIS) :
        GraphQLCachePolicy

    /**
     * Ask the API and keep a good answer, but never answer from the cache: for a background refresh, which needs to
     * see failures (to back off) while screens keep showing the last good answer.
     */
    public data object Refresh : GraphQLCachePolicy

    public companion object {
        /** A week: older answers are more confusing than an error. */
        public const val DEFAULT_MAX_AGE_MILLIS: Long = 7L * 24 * 60 * 60 * 1000
    }
}

internal val GraphQLCachePolicy.maxAgeMillis: Long?
    get() = when (this) {
        GraphQLCachePolicy.NetworkOnly, GraphQLCachePolicy.Refresh -> null
        is GraphQLCachePolicy.NetworkFirst -> maxAgeMillis
        is GraphQLCachePolicy.CacheFirst -> maxAgeMillis
    }

/** Where a [GraphQLResult] came from. */
public enum class GraphQLResultSource { NETWORK, CACHE }

/** A GraphQL answer, where it came from, when the API sent it, and why the API failed when the cache answered. */
public data class GraphQLResult<T>(
    val value: T,
    val source: GraphQLResultSource,
    val fetchedAtMillis: Long,
    val error: AudienceKitException? = null,
) {
    /** An older answer the API couldn't refresh, so a screen can say "Showing what we had at 9:41". */
    val isStale: Boolean get() = error != null
}

/**
 * Whether a kept answer is a fair stand-in when a query fails this way: the API couldn't answer, rather than refused.
 * `undefinedField` is left to the SDK, which asks the schema and retries with fewer fields.
 */
public val AudienceKitException.allowsCachedAnswer: Boolean
    get() = when (this) {
        is AudienceKitException.Network, is AudienceKitException.Decoding -> true
        is AudienceKitException.GraphQL -> !isUndefinedField
        is AudienceKitException.Http -> status >= 500 || status == 408 || status == 429
        else -> false
    }

/** One kept response: the whole successful GraphQL response body, decoded again on the way out. */
@Serializable
public data class GraphQLCacheEntry(val key: String, val body: String, val storedAtMillis: Long)

/**
 * Where [AudienceKitClient] keeps the last good answer to each query. Pass one as the client's `cache` to turn caching
 * on; [FileGraphQLCache] keeps answers across launches. The client empties it on sign-out and account deletion, and
 * keys every entry by audience and person.
 */
public interface GraphQLCache {
    public fun entry(key: String): GraphQLCacheEntry?
    public fun store(entry: GraphQLCacheEntry)
    public fun removeEntriesStoredBefore(millis: Long)
    public fun removeAll()
}

/** Builds cache keys: API, audience, person, endpoint, and the caller's key or the document with sorted variables. */
public object GraphQLCacheKey {
    public fun make(
        apiBase: String,
        audienceId: String?,
        person: String?,
        endpointPath: String,
        query: String,
        variables: Map<String, JsonElement>?,
        cacheKey: String?,
    ): String {
        val operation = cacheKey?.let { "key:$it" } ?: run {
            val normalized = query.split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
            "doc:$normalized|vars:${variables?.let { canonical(JsonObject(it)) }.orEmpty()}"
        }
        return listOf(apiBase, audienceId ?: "-", person ?: "-", endpointPath, operation).joinToString("|")
    }

    /** Who a session token belongs to: its JWT `sub`, or a digest of the token when it isn't a JWT. */
    internal fun person(token: String?): String? {
        token ?: return null
        val sub = runCatching {
            val payload = String(Base64.getUrlDecoder().decode(token.split(".")[1]))
            (Json.parseToJsonElement(payload) as JsonObject)["sub"]?.let { (it as JsonPrimitive).contentOrNull }
        }.getOrNull()
        return sub ?: "t:" + digest(token)
    }

    internal fun digest(text: String): String =
        MessageDigest.getInstance("SHA-256").digest(text.toByteArray()).joinToString("") { "%02x".format(it) }

    private fun canonical(element: JsonElement): String = when (element) {
        is JsonObject -> element.entries.sortedBy { it.key }
            .joinToString(",", "{", "}") { (key, value) -> JsonPrimitive(key).toString() + ":" + canonical(value) }
        is kotlinx.serialization.json.JsonArray -> element.joinToString(",", "[", "]") { canonical(it) }
        else -> element.toString()
    }
}

/** Keeps answers in memory: for tests, and apps that only want fallback within one launch. */
public class InMemoryGraphQLCache : GraphQLCache {
    private val entries = ConcurrentHashMap<String, GraphQLCacheEntry>()
    public val size: Int get() = entries.size
    override fun entry(key: String): GraphQLCacheEntry? = entries[key]
    override fun store(entry: GraphQLCacheEntry) { entries[entry.key] = entry }
    override fun removeEntriesStoredBefore(millis: Long) { entries.values.removeIf { it.storedAtMillis < millis } }
    override fun removeAll() { entries.clear() }
}

/**
 * Keeps answers as files in [directory], so they outlive the launch. On Android pass a folder under
 * `context.cacheDir` (e.g. `File(context.cacheDir, "audiencekit-graphql")`): the system may clear it when space runs
 * low, and it is never backed up, which suits data the API can always send again.
 */
public class FileGraphQLCache(public val directory: File) : GraphQLCache {
    private val lock = Any()
    private val json = Json { ignoreUnknownKeys = true }

    override fun entry(key: String): GraphQLCacheEntry? = synchronized(lock) {
        runCatching { json.decodeFromString(GraphQLCacheEntry.serializer(), file(key).readText()) }
            .getOrNull()?.takeIf { it.key == key }
    }

    override fun store(entry: GraphQLCacheEntry): Unit = synchronized(lock) {
        runCatching {
            directory.mkdirs()
            val target = file(entry.key)
            val temp = File(directory, target.name + ".tmp")
            temp.writeText(json.encodeToString(GraphQLCacheEntry.serializer(), entry))
            if (!temp.renameTo(target)) {
                target.delete()
                temp.renameTo(target)
            }
        }
    }

    override fun removeEntriesStoredBefore(millis: Long): Unit = synchronized(lock) {
        directory.listFiles().orEmpty().forEach { file ->
            val entry = runCatching { json.decodeFromString(GraphQLCacheEntry.serializer(), file.readText()) }.getOrNull()
            if (entry == null || entry.storedAtMillis < millis) file.delete()
        }
    }

    override fun removeAll(): Unit = synchronized(lock) { directory.deleteRecursively() }

    private fun file(key: String) = File(directory, GraphQLCacheKey.digest(key).take(32) + ".json")
}

// region Visited locales

/** A locale the person has been in, as remembered on this phone. */
@Serializable
public data class VisitedLocale(val id: String, val name: String, val lastVisitedAtMillis: Long)

/** Where [VisitedLocales] keeps its list: a JSON string. */
public interface VisitedLocaleStore {
    public fun load(): String?
    public fun save(value: String?)
}

public class InMemoryVisitedLocaleStore(private var value: String? = null) : VisitedLocaleStore {
    override fun load(): String? = value
    override fun save(value: String?) { this.value = value }
}

/** Keeps the list in [file] (on Android, under `context.noBackupFilesDir`, so it stays on the phone). */
public class FileVisitedLocaleStore(private val file: File) : VisitedLocaleStore {
    override fun load(): String? = runCatching { file.readText() }.getOrNull()
    override fun save(value: String?) {
        if (value == null) file.delete() else runCatching { file.parentFile?.mkdirs(); file.writeText(value) }
    }
}

/**
 * The locales the person has been in lately, kept on the phone only and never sent, so a background refresh knows
 * which cities' data to keep fresh (Rick, 2026-11-15). Keep one [store] per audience; [removeAll] on sign-out.
 */
public class VisitedLocales(
    private val store: VisitedLocaleStore,
    public val limit: Int = 5,
    public val windowMillis: Long = 30L * 24 * 60 * 60 * 1000,
) {
    private val serializer = ListSerializer(VisitedLocale.serializer())

    /** Notes that the person is in [id] now (or at [atMillis]). */
    @Synchronized
    public fun record(id: String, name: String, atMillis: Long = System.currentTimeMillis()) {
        val all = listOf(VisitedLocale(id, name, atMillis)) + load().filter { it.id != id }
        store.save(Json.encodeToString(serializer, prune(all, atMillis)))
    }

    /** The locales visited within [windowMillis], most recent first. */
    @Synchronized
    public fun recent(nowMillis: Long = System.currentTimeMillis()): List<VisitedLocale> = prune(load(), nowMillis)

    @Synchronized
    public fun removeAll() { store.save(null) }

    private fun prune(locales: List<VisitedLocale>, now: Long) =
        locales.filter { now - it.lastVisitedAtMillis <= windowMillis }.sortedByDescending { it.lastVisitedAtMillis }
            .take(limit)

    private fun load(): List<VisitedLocale> =
        store.load()?.let { runCatching { Json.decodeFromString(serializer, it) }.getOrNull() }.orEmpty()
}

/**
 * Spaces out background refreshes: after a failure it waits longer each time (doubling from [baseMillis] up to
 * [capMillis]), and a success resets it, so a failing API is never asked in a tight loop.
 */
@Serializable
public data class RefreshBackoff(
    val baseMillis: Long = 15L * 60 * 1000,
    val capMillis: Long = 6L * 60 * 60 * 1000,
    val failures: Int = 0,
    val lastAttemptAtMillis: Long? = null,
) {
    val intervalMillis: Long get() = minOf(capMillis, baseMillis shl minOf(failures, 16))

    public fun isDue(nowMillis: Long = System.currentTimeMillis()): Boolean =
        lastAttemptAtMillis == null || nowMillis - lastAttemptAtMillis >= intervalMillis

    public fun nextAtMillis(nowMillis: Long = System.currentTimeMillis()): Long =
        lastAttemptAtMillis?.plus(intervalMillis) ?: nowMillis

    public fun succeeded(atMillis: Long = System.currentTimeMillis()): RefreshBackoff =
        copy(failures = 0, lastAttemptAtMillis = atMillis)

    public fun failed(atMillis: Long = System.currentTimeMillis()): RefreshBackoff =
        copy(failures = failures + 1, lastAttemptAtMillis = atMillis)
}

// endregion
