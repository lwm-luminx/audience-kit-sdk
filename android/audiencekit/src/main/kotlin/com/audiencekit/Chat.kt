package com.audiencekit

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.transformWhile
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull

/** A chat room: a venue's, or a locale's (out in the city, away from its venues). */
public sealed interface ChatRoom {
    /** The venue's or locale's ID. */
    public val id: String

    public data class Venue(override val id: String) : ChatRoom
    public data class Locale(override val id: String) : ChatRoom

    /** Its subscription field (`venueChat`, `localeChat`). */
    public val subscriptionField: String get() = if (this is Venue) "venueChat" else "localeChat"

    /** The argument naming it, on its subscription and on `sendMyChatMessage`'s input. */
    public val argumentName: String get() = if (this is Venue) "venueId" else "localeId"
}

/** One message in a chat room: the API's `ChatMessage` (or `VenueMessage`, its stored form). */
@Serializable
public data class ChatMessage(
    val id: String,
    /** What it says, rendered for display. */
    val body: String = "",
    /** The text as sent. */
    val message: String = "",
    /** Who sent it, as the room shows them (non-friends as "First L."), or the venue's name. */
    val name: String? = null,
    val userId: String? = null,
    val avatarUrl: String? = null,
    /** A photo message's photo. */
    val photoUrl: String? = null,
    /** ISO 8601. */
    val sentAt: String? = null,
    /** The API's `ChatRole` (`HOST`, `STAFF`, `VENUE`); null for a member. */
    val role: String? = null,
    /** The API's `ChatKind`: `TEXT`, `ANNOUNCEMENT`, `PHOTO`, `EVENT`, `SPECIAL`, `PROMPT`, `REQUEST`. */
    val kind: String = "TEXT",
    val title: String? = null,
    val pinned: Boolean = false,
)

/** Someone in a chat room when you join it: the API's `ChatRosterPerson`. */
@Serializable
public data class ChatRosterPerson(
    val userId: String,
    val name: String? = null,
    val avatarUrl: String? = null,
    val friend: Boolean = false,
)

/** What a chat room's subscription sends (the API's `ChatRoomEvent` union), decoded. */
public sealed interface ChatRoomEvent {
    /** Joined: who's here, the recent history (oldest first) and the pinned message. */
    public data class Joined(
        val people: List<ChatRosterPerson>,
        val history: List<ChatMessage>,
        val pinned: ChatMessage?,
        /** True when the signed-in user isn't at the venue, so they can read but not post. */
        val outOfRange: Boolean,
    ) : ChatRoomEvent

    public data class Posted(val message: ChatMessage) : ChatRoomEvent
    public data class Updated(val message: ChatMessage) : ChatRoomEvent
    public data class Removed(val messageId: String) : ChatRoomEvent
    public data class PinChanged(val messageId: String, val pinned: Boolean, val announcement: ChatMessage?) : ChatRoomEvent
    public data class Cleared(val clearedAt: String?, val expired: Boolean) : ChatRoomEvent
    public data class PresenceChanged(val userId: String, val name: String?, val avatarUrl: String?, val presence: String) :
        ChatRoomEvent
    public data class RangeChanged(val outOfRange: Boolean) : ChatRoomEvent

    /** The server took the user out of the room: `AWAY`, `BANNED`, `MOVED` or `REMOVED`. */
    public data class Left(val reason: String) : ChatRoomEvent

    /** An event this SDK doesn't know yet, by its `__typename`. */
    public data class Unknown(val typename: String) : ChatRoomEvent

    public companion object {
        /** The subscription field's value (`data.room`), decoded. */
        public fun decode(room: JsonObject): ChatRoomEvent {
            val json = AudienceKitClient.json
            fun string(key: String) = (room[key] as? JsonPrimitive)?.contentOrNull
            fun bool(key: String) = (room[key] as? JsonPrimitive)?.booleanOrNull
            // A message that doesn't decode is left out (or makes the event Unknown) rather than failing the stream.
            fun message(element: Any?) = (element as? JsonObject)?.let {
                runCatching { json.decodeFromJsonElement(ChatMessage.serializer(), it) }.getOrNull()
            }
            fun posted(element: Any?) = message((element as? JsonObject)?.get("message"))
            val typename = string("__typename").orEmpty()
            return when (typename) {
                "ChatJoined" -> Joined(
                    people = ((room["roster"] as? JsonObject)?.get("people") as? JsonArray).orEmpty().mapNotNull {
                        runCatching { json.decodeFromJsonElement(ChatRosterPerson.serializer(), it) }.getOrNull()
                    },
                    history = (room["history"] as? JsonArray).orEmpty().mapNotNull(::posted),
                    pinned = posted(room["pinnedMessage"]),
                    outOfRange = bool("outOfRange") ?: false,
                )
                "ChatMessagePosted" -> message(room["message"])?.let(::Posted)
                "ChatMessageUpdated" -> message(room["message"])?.let(::Updated)
                "ChatMessageRemoved" -> string("messageId")?.let(::Removed)
                "ChatPinChanged" -> string("messageId")?.let {
                    PinChanged(it, bool("pinned") ?: false, message(room["announcement"]))
                }
                "ChatRoomCleared" -> Cleared(string("clearedAt"), bool("expired") ?: false)
                "ChatPresenceChanged" -> string("userId")?.let {
                    PresenceChanged(it, string("name"), string("avatarUrl"), string("presence") ?: "OFFLINE")
                }
                "ChatRangeChanged" -> RangeChanged(bool("outOfRange") ?: false)
                "ChatLeft" -> Left(string("reason") ?: "REMOVED")
                else -> null
            } ?: Unknown(typename)
        }
    }
}

/** A chat room subscription's progress ([CableConnection.chat]). */
public sealed interface ChatRoomUpdate {
    /** The subscription is running: events arrive from now on. Sent again after every reconnect. */
    public data object Subscribed : ChatRoomUpdate
    public data class Event(val event: ChatRoomEvent) : ChatRoomUpdate

    /** The server refused the subscription (not at the venue, say), with its errors. The flow ends after this. */
    public data class Refused(val errors: JsonArray) : ChatRoomUpdate

    /** The socket dropped; the connection reconnects unless [reconnects] is false. */
    public data class Disconnected(val reason: String?, val reconnects: Boolean) : ChatRoomUpdate
}

/** One of a venue's or person's social media profiles: the API's `SocialLink`. */
@Serializable
public data class SocialLink(val id: String, val handle: String, val provider: String, val url: String? = null)

/** A venue's page: the venue and what the modules its audience has add to it; a module it lacks leaves its part null. */
public data class VenueDetail(
    val venue: Venue,
    val description: String?,
    val address: String?,
    val phone: String?,
    val website: String?,
    val socialLinks: List<SocialLink>?,
    val chatOpen: Boolean?,
    val recentMessages: List<ChatMessage>?,
    val upcomingEvents: List<Event>?,
)

public const val CHAT_MESSAGE_FIELDS: String = "id body message name userId avatarUrl photoUrl sentAt role kind title pinned"

public fun Queries.venueDetail(shape: SchemaShape): String {
    // A variable the document doesn't use is an error, so recentMessages goes with the chat field.
    val recentMessages = if (shape.has("Venue", "chat")) ", \$recentMessages: Int" else ""
    val fields = buildString {
        append(venueFields(shape)).append(" description")
        if (shape.has("Venue", "profile")) {
            append(" profile { address phone website socialLinks { nodes { id handle provider url } } }")
        }
        if (shape.has("Venue", "chat")) {
            append(" chat { open recentMessages(limit: \$recentMessages) { nodes { $CHAT_MESSAGE_FIELDS } } }")
        }
        if (shape.has("Venue", "events")) append(" events { upcoming(first: 20) { nodes { ${eventFields(shape)} } } }")
    }
    return """
        query VenueDetail(${'$'}id: ID!$recentMessages) {
          venues { venue(id: ${'$'}id) { $fields } }
        }
    """.trimIndent()
}

public val Queries.sendChatMessage: String get() = """
    mutation SendMyChatMessage(${'$'}input: ChatMessageSendOwnInput!) {
      sendMyChatMessage(input: ${'$'}input) { message { $CHAT_MESSAGE_FIELDS } }
    }
""".trimIndent()

public val Queries.removeChatMessage: String get() = """
    mutation RemoveMyChatMessage(${'$'}messageId: ID!) {
      removeMyChatMessage(input: { messageId: ${'$'}messageId }) { deletedId }
    }
""".trimIndent()

/** A chat room's subscription, aliased to `room` whichever field it is. */
public fun Queries.chatRoom(room: ChatRoom, watch: Boolean = false): String = """
    subscription ChatRoom(${'$'}id: ID!) {
      room: ${room.subscriptionField}(${room.argumentName}: ${'$'}id${if (watch) ", watch: true" else ""}) {
        __typename
        ... on ChatJoined {
          outOfRange
          roster { people { userId name avatarUrl friend } }
          history { message { ...Line } }
          pinnedMessage { message { ...Line } }
        }
        ... on ChatMessagePosted { message { ...Line } }
        ... on ChatMessageUpdated { message { ...Line } }
        ... on ChatMessageRemoved { messageId }
        ... on ChatPinChanged { messageId pinned announcement { ...Line } }
        ... on ChatRoomCleared { clearedAt expired }
        ... on ChatPresenceChanged { userId name avatarUrl presence }
        ... on ChatRangeChanged { outOfRange }
        ... on ChatLeft { reason }
      }
    }
    fragment Line on ChatMessage { $CHAT_MESSAGE_FIELDS }
""".trimIndent()

@Serializable
internal data class VenueDetailResponse(val venues: Mixin? = null) {
    @Serializable internal data class Mixin(val venue: JsonObject? = null)

    @Serializable
    internal data class Extra(
        val description: String? = null,
        val profile: Profile? = null,
        val chat: Chat? = null,
        val events: Events? = null,
    )

    @Serializable
    internal data class Profile(
        val address: String? = null,
        val phone: String? = null,
        val website: String? = null,
        val socialLinks: Connection<SocialLink>? = null,
    )

    @Serializable internal data class Chat(val open: Boolean? = null, val recentMessages: Connection<ChatMessage>? = null)

    @Serializable internal data class Events(val upcoming: Connection<Event>? = null)
}

@Serializable
internal data class SendChatMessageResponse(val sendMyChatMessage: Payload) {
    @Serializable internal data class Payload(val message: ChatMessage)
}

@Serializable
internal data class RemoveChatMessageResponse(val removeMyChatMessage: Payload? = null) {
    @Serializable internal data class Payload(val deletedId: String? = null)
}

/**
 * A venue's page with its [recentMessages] latest chat messages (the API gives at most 20), or null when it doesn't
 * exist or belongs to another audience.
 */
public suspend fun AudienceKitClient.venueDetail(id: String, recentMessages: Int = 20): VenueDetail? {
    val variables = graphQLVariables("id" to id, "recentMessages" to recentMessages)
    val venue = graphQL(EVENT_TYPES, VenueDetailResponse.serializer(), variables, "VenueDetail") {
        Queries.venueDetail(it)
    }.venues?.venue ?: return null
    val json = AudienceKitClient.json
    // Decoded here from the raw object, so wrap failures the way every other call reports them.
    val (extra, decoded) = try {
        json.decodeFromJsonElement(VenueDetailResponse.Extra.serializer(), venue) to
            json.decodeFromJsonElement(Venue.serializer(), venue)
    } catch (e: IllegalArgumentException) { // SerializationException is one
        throw AudienceKitException.Decoding(e.message ?: e.toString())
    }
    return VenueDetail(
        venue = decoded,
        description = extra.description,
        address = extra.profile?.address,
        phone = extra.profile?.phone,
        website = extra.profile?.website,
        socialLinks = extra.profile?.socialLinks?.items,
        chatOpen = extra.chat?.open,
        recentMessages = extra.chat?.recentMessages?.items,
        upcomingEvents = extra.events?.upcoming?.items,
    )
}

/** Posts the signed-in user's message to a chat room, as a reply to a chat prompt when [promptId] is given. */
public suspend fun AudienceKitClient.sendChatMessage(text: String, room: ChatRoom, promptId: String? = null): ChatMessage {
    val input = buildMap<String, Any?> {
        put(room.argumentName, room.id)
        put("message", text)
        promptId?.let { put("promptId", it) }
    }
    return graphQL(Queries.sendChatMessage, SendChatMessageResponse.serializer(), graphQLVariables("input" to input), "SendMyChatMessage")
        .sendMyChatMessage.message
}

/** Takes back one of the signed-in user's own messages. */
public suspend fun AudienceKitClient.removeChatMessage(id: String) {
    graphQL(Queries.removeChatMessage, RemoveChatMessageResponse.serializer(), graphQLVariables("messageId" to id), "RemoveMyChatMessage")
}

/**
 * Joins a chat room (or, with [watch], follows it without being in it: no presence) in [audienceId] and emits what
 * happens in it. Cancelling the collector leaves the room.
 */
public fun CableConnection.chat(audienceId: String, room: ChatRoom, watch: Boolean = false): Flow<ChatRoomUpdate> {
    val variables = JsonObject(mapOf("id" to JsonPrimitive(room.id)))
    // transformWhile, not collect: returning false ends the flow (and leaves the room) once the server refuses it.
    return subscribe(audienceId, Queries.chatRoom(room, watch), variables, "ChatRoom").transformWhile { event ->
        when (event) {
            CableEvent.Subscribed -> emit(ChatRoomUpdate.Subscribed)
            is CableEvent.Result -> {
                val result = event.result
                val data = result.data?.get("room") as? JsonObject
                when {
                    data != null -> emit(ChatRoomUpdate.Event(ChatRoomEvent.decode(data)))
                    result.errors.isNotEmpty() -> {
                        emit(ChatRoomUpdate.Refused(result.errors))
                        return@transformWhile false
                    }
                }
            }
            CableEvent.Rejected -> emit(ChatRoomUpdate.Refused(JsonArray(emptyList())))
            is CableEvent.Disconnected -> emit(ChatRoomUpdate.Disconnected(event.reason, event.reconnects))
        }
        true
    }
}
