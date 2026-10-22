package com.audiencekit

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.SendChannel
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.buffer
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull

/** What one subscription on the [CableConnection] hears. */
public sealed interface CableEvent {
    /** Action Cable confirmed the channel and the operation was sent to run (again, after a reconnect). */
    public data object Subscribed : CableEvent

    /** One `{"result":{"data":…,"errors":…},"more":…}` message; [GraphQLCable.result] reads it. */
    public data class Result(val json: JsonObject) : CableEvent {
        public val result: GraphQLCable.Envelope.Result get() = GraphQLCable.result(json)
    }

    /** The channel was refused (another audience, a ban, signed out). The flow ends after it. */
    public data object Rejected : CableEvent

    /**
     * The socket went away. With [reconnects] the connection is already reconnecting and will subscribe
     * and run the operation again (a [Subscribed] follows); without, the flow ends after it.
     */
    public data class Disconnected(val reason: String?, val reconnects: Boolean) : CableEvent
}

/** One websocket, as [CableConnection] needs it: a seam so the protocol can be tested without a server. */
public interface CableSocket {
    public fun send(text: String): Boolean
    public fun close(code: Int, reason: String?)

    /** What the socket tells the connection, from any thread. */
    public interface Listener {
        public fun onMessage(text: String)
        public fun onClosed(reason: String?)
        public fun onFailure(reason: String?)
    }
}

/**
 * Opens a [CableSocket] to the realtime URL with these handshake [headers] (the token, the contract version, the
 * client). The SDK has no websocket of its own: an app opens one with its HTTP stack (OkHttp's `newWebSocket`).
 */
public fun interface CableSocketFactory {
    public fun open(url: String, headers: Map<String, String>, listener: CableSocket.Listener): CableSocket
}

/**
 * The app's one Action Cable connection, which every GraphQL subscription shares: each [subscribe] is
 * one `GraphQLChannel` subscription on it, told apart by its identifier.
 *
 * The socket opens with the first subscription and closes after the last ends, so collectors scoped to
 * the screen (or the app being in front and signed in) decide when it's open. The token is read on
 * every (re)open. Action Cable pings every 3 seconds: [SILENCE_MS] without a frame, or a failure, and
 * the socket is dropped, every subscriber told [CableEvent.Disconnected] (reconnecting), and it
 * reconnects with backoff, subscribing and running every live operation again once welcomed.
 *
 * The handshake is dressed like any API request: `Authorization: Bearer <token>` (the only scheme the API accepts),
 * the contract version in `X-AudienceKit-API-Version`, the client in `X-AudienceKit-Client`, and [headers] (the
 * environment's, for a staging build).
 *
 * A connection refused as unauthorized tells [onUnauthorized] the token and ends every subscription.
 */
public class CableConnection(
    private val url: String,
    private val token: () -> String?,
    private val socketFactory: CableSocketFactory,
    private val headers: Map<String, String> = emptyMap(),
    /** Runs the silence watchdog and reconnect delays. */
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
) {
    /** A connection to [configuration]'s API, with its environment's header. */
    public constructor(configuration: AudienceKitConfiguration, token: () -> String?, socketFactory: CableSocketFactory) :
        this(
            GraphQLCable.realtimeUrl(configuration.baseUrl) ?: error("No realtime URL for ${configuration.baseUrl}"),
            token,
            socketFactory,
            if (configuration.environment == AudienceKitEnvironment.PRODUCTION) emptyMap()
            else mapOf(AudienceKitEnvironment.HEADER to configuration.environment.value),
        )

    /**
     * Told the token of a connection the server refused as unauthorized (`reject_unauthorized_connection`),
     * on the socket's thread. The app points it at its session, which ends the way an HTTP 401 ends it.
     */
    @Volatile public var onUnauthorized: ((token: String) -> Unit)? = null

    private inner class Subscription(
        val identifier: String,
        val executeFrame: String,
        val channel: SendChannel<CableEvent>,
    ) {
        /** Confirmed (on this socket); messages before that aren't routed to it. */
        var confirmed = false
    }

    private val lock = Any()
    private val subscriptions = LinkedHashMap<String, Subscription>()
    private var socket: CableSocket? = null
    private var socketToken: String? = null
    private var welcomed = false

    /** Which socket is current; callbacks from an older one are ignored. */
    private var generation = 0
    private var backoffMs = INITIAL_BACKOFF_MS
    private var watchdog: Job? = null
    private var reconnect: Job? = null

    /** Whether a socket is open or opening (or about to reconnect). */
    public val isActive: Boolean get() = synchronized(lock) { socket != null || reconnect != null }

    /**
     * Runs [query] with [variables] in [audienceId], in the [endpoint]'s view (the staff tools' `staffql` or the
     * apps' `graphql`), while collected. Events end with the operation (`more: false`), a rejection, or the
     * connection refused; cancelling the collector unsubscribes.
     */
    public fun subscribe(
        audienceId: String,
        query: String,
        variables: JsonObject = JsonObject(emptyMap()),
        operationName: String? = null,
        endpoint: GraphQLEndpoint = GraphQLEndpoint.CONSUMER,
    ): Flow<CableEvent> = callbackFlow {
        val identifier = GraphQLCable.identifier(audienceId, GraphQLCable.newChannelId(), endpoint)
        val subscription = Subscription(identifier, GraphQLCable.execute(identifier, query, variables, operationName), channel)
        add(subscription)
        awaitClose { remove(subscription) }
    }.buffer(Channel.UNLIMITED)

    /** Closes the socket and ends every subscription (signing out). */
    public fun disconnect() {
        val ended = synchronized(lock) {
            val all = subscriptions.values.toList()
            subscriptions.clear()
            teardown()
            backoffMs = INITIAL_BACKOFF_MS
            all
        }
        ended.forEach { it.channel.close() }
    }

    private fun add(subscription: Subscription) = synchronized(lock) {
        subscriptions[subscription.identifier] = subscription
        when {
            socket == null && reconnect == null -> open()
            welcomed -> socket?.send(GraphQLCable.subscribe(subscription.identifier))
        }
    }

    private fun remove(subscription: Subscription) = synchronized(lock) {
        if (subscriptions.remove(subscription.identifier) === subscription && welcomed) {
            socket?.send(GraphQLCable.unsubscribe(subscription.identifier))
        }
        if (subscriptions.isEmpty()) {
            teardown()
            backoffMs = INITIAL_BACKOFF_MS
        }
    }

    /** Opens a socket; under [lock]. */
    private fun open() {
        generation += 1
        welcomed = false
        val current = generation
        val token = token()
        socketToken = token
        socket = socketFactory.open(url, handshake(token), listener(current))
        watch(current)
    }

    private fun handshake(token: String?): Map<String, String> = buildMap {
        put("X-AudienceKit-API-Version", AudienceKitSDK.API_VERSION)
        put("X-AudienceKit-Client", "AudienceKit-Kotlin/${AudienceKitSDK.VERSION}")
        putAll(headers)
        token?.let { put("Authorization", "Bearer $it") }
    }

    /** Closes the socket and stops its timers, without telling anyone; under [lock]. */
    private fun teardown() {
        generation += 1
        welcomed = false
        watchdog?.cancel()
        watchdog = null
        reconnect?.cancel()
        reconnect = null
        socket?.close(1000, null)
        socket = null
        socketToken = null
    }

    /** (Re)starts the silence watchdog for socket [current]; under [lock]. */
    private fun watch(current: Int) {
        watchdog?.cancel()
        watchdog = scope.launch {
            delay(SILENCE_MS)
            synchronized(lock) { if (current == generation) drop("No word from the server") }
        }
    }

    /** The socket failed, went quiet or was closed: tell everyone, and reconnect after backoff; under [lock]. */
    private fun drop(reason: String?) {
        teardown()
        if (subscriptions.isEmpty()) return
        subscriptions.values.forEach {
            it.confirmed = false
            it.channel.trySend(CableEvent.Disconnected(reason, reconnects = true))
        }
        val wait = backoffMs
        backoffMs = (backoffMs * 2).coerceAtMost(MAX_BACKOFF_MS)
        reconnect = scope.launch {
            delay(wait)
            synchronized(lock) {
                reconnect = null
                if (socket == null && subscriptions.isNotEmpty()) open()
            }
        }
    }

    /** The server refused or ended the connection for good: everyone's flow ends; under [lock]. */
    private fun end(reason: String?) {
        val all = subscriptions.values.toList()
        subscriptions.clear()
        teardown()
        backoffMs = INITIAL_BACKOFF_MS
        all.forEach {
            it.channel.trySend(CableEvent.Disconnected(reason, reconnects = false))
            it.channel.close()
        }
    }

    private fun listener(current: Int) = object : CableSocket.Listener {
        override fun onMessage(text: String) {
            var unauthorized: String? = null
            synchronized(lock) {
                if (current != generation) return
                watch(current)
                unauthorized = receive(text)
            }
            unauthorized?.let { token -> onUnauthorized?.invoke(token) }
        }

        override fun onClosed(reason: String?) = synchronized(lock) {
            if (current == generation) drop(reason)
        }

        override fun onFailure(reason: String?) = synchronized(lock) {
            if (current == generation) drop(reason)
        }
    }

    /** Handles one frame; the token to report as unauthorized, if the server refused it. Under [lock]. */
    private fun receive(text: String): String? {
        val frame = runCatching { GraphQLCable.json.parseToJsonElement(text) as? JsonObject }.getOrNull() ?: return null
        val identifier = (frame["identifier"] as? JsonPrimitive)?.contentOrNull
        val subscription = identifier?.let { subscriptions[it] }
        when ((frame["type"] as? JsonPrimitive)?.contentOrNull) {
            "welcome" -> {
                welcomed = true
                backoffMs = INITIAL_BACKOFF_MS
                subscriptions.values.forEach { socket?.send(GraphQLCable.subscribe(it.identifier)) }
            }
            "confirm_subscription" -> subscription?.let {
                if (it.confirmed) return null
                it.confirmed = true
                socket?.send(it.executeFrame)
                it.channel.trySend(CableEvent.Subscribed)
            }
            "reject_subscription" -> subscription?.let {
                subscriptions.remove(it.identifier)
                it.channel.trySend(CableEvent.Rejected)
                it.channel.close()
                if (subscriptions.isEmpty()) teardown()
            }
            "disconnect" -> {
                val reason = (frame["reason"] as? JsonPrimitive)?.contentOrNull
                val reconnects = (frame["reconnect"] as? JsonPrimitive)?.booleanOrNull ?: true
                if (reason == "unauthorized") {
                    val refused = socketToken
                    end(reason)
                    return refused
                }
                if (reconnects) drop(reason) else end(reason)
            }
            // Pings, and anything else.
            "ping" -> Unit
            null -> {
                // Action Cable reuses `message` for its ping counter, so only an object there is a result.
                val message = frame["message"] as? JsonObject ?: return null
                val target = subscription?.takeIf { it.confirmed } ?: return null
                target.channel.trySend(CableEvent.Result(message))
                if ((message["more"] as? JsonPrimitive)?.booleanOrNull == false) {
                    // The operation is over; the channel goes too.
                    subscriptions.remove(target.identifier)
                    socket?.send(GraphQLCable.unsubscribe(target.identifier))
                    target.channel.close()
                    if (subscriptions.isEmpty()) teardown()
                }
            }
        }
        return null
    }

    public companion object {
        /** Action Cable pings every 3 seconds; this long without a frame and the socket is gone. */
        public const val SILENCE_MS: Long = 12_000L
        public const val INITIAL_BACKOFF_MS: Long = 1_000L
        public const val MAX_BACKOFF_MS: Long = 30_000L
    }
}
