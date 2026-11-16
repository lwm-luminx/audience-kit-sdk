package com.audiencekit

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.transformWhile
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull

/**
 * A Ping's or Quickie pairing's chat (the API's `PrivateChat`): a short-lived chat for a ping's circle, or a Quickie
 * pair once both accepted. What's said is kept only until it closes, then deleted. Read it from `Ping.chat` or
 * `PairUpMatch.chat` (put [PrivateChat.GRAPHQL_FIELDS] in the app's query), or with [pingChat].
 */
@Serializable
public data class PrivateChat(
    /** `ping-<ping id>` or `quickie-<match id>`. */
    val id: String,
    /** ISO 8601: when it closes at the latest. Ending the ping or the pairing closes it sooner. */
    val closesAt: String,
    /** Its newest lines, oldest first. */
    val messages: List<PrivateChatMessage> = emptyList(),
) {
    public val isPing: Boolean get() = id.startsWith("ping-")
    public val isQuickie: Boolean get() = id.startsWith("quickie-")

    public companion object {
        /** Its fields, for an app's own ping or Quickie query: `chat { $GRAPHQL_FIELDS }`. */
        public const val GRAPHQL_FIELDS: String = "id closesAt messages { ${PrivateChatMessage.GRAPHQL_FIELDS} }"
    }
}

/** A line in a [PrivateChat]. Its [id] also names its chat: report it with [ReportTarget.PRIVATE_MESSAGE]. */
@Serializable
public data class PrivateChatMessage(
    val id: String,
    val chatId: String,
    val body: String,
    val isMine: Boolean = false,
    /** Null when they've deleted their account. */
    val sender: Sender? = null,
    /** ISO 8601. */
    val sentAt: String,
) {
    /** [name] is in full for friends, first name and last initial for anyone else. */
    @Serializable
    public data class Sender(val id: String, val name: String)

    public companion object {
        public const val GRAPHQL_FIELDS: String = "id chatId body isMine sentAt sender { id name }"
    }
}

/** What [privateChats] sends: a new line in one of the person's chats, or a chat closing. */
public sealed interface PrivateChatEvent {
    public data class Message(val message: PrivateChatMessage) : PrivateChatEvent

    /** What was said in it is gone, and nothing more can be sent. */
    public data class Closed(val chatId: String) : PrivateChatEvent

    public companion object {
        /** The subscription field's value (`data.privateChat`), decoded; null when it can't be read. */
        public fun decode(event: JsonObject): PrivateChatEvent? {
            val chatId = (event["chatId"] as? JsonPrimitive)?.contentOrNull ?: return null
            val closed = (event["closed"] as? JsonPrimitive)?.booleanOrNull ?: false
            val message = (event["message"] as? JsonObject)?.let {
                runCatching { AudienceKitClient.json.decodeFromJsonElement(PrivateChatMessage.serializer(), it) }.getOrNull()
            }
            return if (message != null && !closed) Message(message) else Closed(chatId)
        }
    }
}

/** The progress of [privateChats]. */
public sealed interface PrivateChatUpdate {
    /** Running: lines arrive from now on. Sent again after every reconnect, so refetch the open chat then. */
    public data object Subscribed : PrivateChatUpdate
    public data class Event(val event: PrivateChatEvent) : PrivateChatUpdate
    public data class Refused(val errors: JsonArray) : PrivateChatUpdate
    public data class Disconnected(val reason: String?, val reconnects: Boolean) : PrivateChatUpdate
}

/** The words around Ping and Quickie chats, shared with iOS. */
public object PrivateChatCopy {
    public const val PLACEHOLDER: String = "Say something"
    public const val PING_TITLE: String = "Chat with your circle"
    public const val QUICKIE_TITLE: String = "Chat to find each other"
    public const val EPHEMERAL: String = "Messages disappear when the chat ends."
    public const val CLOSED: String = "This chat has ended."
}

internal val PING_CHAT_QUERY: String = """
    query PingChat(${'$'}id: ID!) {
      node(id: ${'$'}id) { ... on Ping { id chat { ${PrivateChat.GRAPHQL_FIELDS} } } }
    }
""".trimIndent()

internal val SEND_PRIVATE_CHAT_MESSAGE: String = """
    mutation SendPrivateChatMessage(${'$'}chatId: ID!, ${'$'}body: String!) {
      sendPrivateChatMessage(input: { chatId: ${'$'}chatId, body: ${'$'}body }) { message { ${PrivateChatMessage.GRAPHQL_FIELDS} } }
    }
""".trimIndent()

internal val PRIVATE_CHAT_SUBSCRIPTION: String = """
    subscription PrivateChat {
      privateChat { chatId closed message { ${PrivateChatMessage.GRAPHQL_FIELDS} } }
    }
""".trimIndent()

@Serializable
internal data class PingChatResponse(val node: Node? = null) {
    @Serializable internal data class Node(val chat: PrivateChat? = null)
}

@Serializable
internal data class SendPrivateChatMessageResponse(val sendPrivateChatMessage: Payload) {
    @Serializable internal data class Payload(val message: PrivateChatMessage)
}

/** A ping's chat, when the signed-in person is in its circle and someone has joined; null otherwise. */
public suspend fun AudienceKitClient.pingChat(pingId: String): PrivateChat? =
    graphQL(PING_CHAT_QUERY, PingChatResponse.serializer(), graphQLVariables("id" to pingId), "PingChat").node?.chat

/**
 * Says something in a Ping or Quickie chat. Throws when the chat has ended, the word list refuses it, or the person is
 * sending too fast.
 */
public suspend fun AudienceKitClient.sendPrivateChatMessage(body: String, chatId: String): PrivateChatMessage =
    graphQL(SEND_PRIVATE_CHAT_MESSAGE, SendPrivateChatMessageResponse.serializer(),
        graphQLVariables("chatId" to chatId, "body" to body), "SendPrivateChatMessage").sendPrivateChatMessage.message

/** Every Ping and Quickie chat the signed-in person is in, in [audienceId]: new lines and chats closing. */
public fun CableConnection.privateChats(audienceId: String): Flow<PrivateChatUpdate> =
    subscribe(audienceId, PRIVATE_CHAT_SUBSCRIPTION, operationName = "PrivateChat").transformWhile { event ->
        when (event) {
            CableEvent.Subscribed -> emit(PrivateChatUpdate.Subscribed)
            is CableEvent.Result -> {
                val result = event.result
                val data = result.data?.get("privateChat") as? JsonObject
                when {
                    data != null -> PrivateChatEvent.decode(data)?.let { emit(PrivateChatUpdate.Event(it)) }
                    result.errors.isNotEmpty() -> {
                        emit(PrivateChatUpdate.Refused(result.errors))
                        return@transformWhile false
                    }
                }
            }
            CableEvent.Rejected -> emit(PrivateChatUpdate.Refused(JsonArray(emptyList())))
            is CableEvent.Disconnected -> emit(PrivateChatUpdate.Disconnected(event.reason, event.reconnects))
        }
        true
    }
