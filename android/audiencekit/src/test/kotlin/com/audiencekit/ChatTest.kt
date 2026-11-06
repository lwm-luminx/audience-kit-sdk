package com.audiencekit

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

private const val CHAT_AUDIENCE_ID = "b0f8b66a-e636-495d-9475-0f5317ea08e0"

private fun chatClient(stub: StubTransport): AudienceKitClient = AudienceKitClient(
    AudienceKitConfiguration(baseUrl = StubTransport.BASE_URL, audienceId = CHAT_AUDIENCE_ID),
    InMemoryTokenStore("session-token"),
    stub,
)

private fun RecordedRequest.document(): String = (jsonBody()["query"] as JsonPrimitive).content
private fun RecordedRequest.operation(): String? = (jsonBody()["operationName"] as? JsonPrimitive)?.content
private fun RecordedRequest.variable(name: String): String? =
    (jsonBody()["variables"]?.jsonObject?.get(name) as? JsonPrimitive)?.content

private const val LINE = """{"id":"m-1","body":"hi","message":"hi","name":"Ada L.","userId":"u-2","sentAt":"2026-11-06T18:00:00Z","kind":"TEXT","pinned":false}"""

private const val VENUE_DETAIL = """
{"data":{"venues":{"venue":{"id":"v-1","name":"801 Labs","hidden":false,"order":0,"photoUrl":null,
  "bannerUrl":null,"description":"Salt Lake's hackerspace","locale":{"id":"l-1","name":"Salt Lake City"},
  "location":{"id":"loc-1","point":"POINT (-111.89 40.76)","address":"615 S 300 W"},"tags":[],
  "profile":{"address":"615 S 300 W","phone":"+18015550100","website":"https://801labs.org",
    "socialLinks":{"nodes":[{"id":"s-1","handle":"801labs","provider":"discord","url":"https://discord.gg/x"}]}},
  "chat":{"open":true,"recentMessages":{"nodes":[$LINE]}},
  "events":{"upcoming":{"nodes":[{"id":"e-1","name":"Open hack night","startAt":"2026-11-10T02:00:00Z",
    "isFeatured":false,"isCanceled":false,"tags":[]}]}}}}}}
"""

/** A Venue without the Listings, Chat or Events modules' fields, as introspection shows it. */
private val bareVenueFields = mapOf(
    "Event" to listOf("id", "name", "startAt"),
    "Locale" to listOf("id", "name"),
    "Location" to listOf("id", "point", "address"),
    "Venue" to listOf("id", "name", "locale", "location", "tags"),
)

private fun bareSchema(request: RecordedRequest): StubTransport.Reply {
    val entries = Regex("""(t\d+): __type\(name: "(\w+)"\)""").findAll(request.document()).map { match ->
        val (alias, type) = match.destructured
        val fields = bareVenueFields[type]?.joinToString(",", """{"fields":[""", "]}") { """{"name":"$it"}""" } ?: "null"
        "\"$alias\":$fields"
    }
    return StubTransport.json(200, """{"data":{${entries.joinToString(",")}}}""")
}

class ChatQueriesTest {
    @Test
    fun venueDetailReadsTheProfileChatAndEvents() = runTest {
        val stub = StubTransport { StubTransport.json(200, VENUE_DETAIL) }

        val detail = chatClient(stub).venueDetail("v-1")!!

        val request = stub.requests.single()
        assertEquals("VenueDetail", request.operation())
        assertEquals("v-1", request.variable("id"))
        assertEquals("801 Labs", detail.venue.name)
        assertEquals("Salt Lake's hackerspace", detail.description)
        assertEquals("615 S 300 W", detail.address)
        assertEquals("+18015550100", detail.phone)
        assertEquals("https://801labs.org", detail.website)
        assertEquals(listOf(SocialLink("s-1", "801labs", "discord", "https://discord.gg/x")), detail.socialLinks)
        assertEquals(true, detail.chatOpen)
        assertEquals(listOf("Ada L."), detail.recentMessages?.map { it.name })
        assertEquals(listOf("e-1"), detail.upcomingEvents?.map { it.id })
        assertEquals(40.76, detail.venue.location?.coordinate?.latitude)
    }

    @Test
    fun venueDetailIsNullForAVenueThatIsNotThere() = runTest {
        val stub = StubTransport { StubTransport.json(200, """{"data":{"venues":{"venue":null}}}""") }

        assertNull(chatClient(stub).venueDetail("v-404"))
    }

    @Test
    fun venueDetailWithoutTheListingsChatOrEventsModulesLeavesThosePartsNull() = runTest {
        val stub = StubTransport { request ->
            when {
                request.operation() == "SchemaFields" -> bareSchema(request)
                "profile" in request.document() -> StubTransport.json(
                    200,
                    """{"errors":[{"message":"Field 'profile' doesn't exist on type 'Venue'","extensions":{"code":"undefinedField"}}]}""",
                )
                else -> StubTransport.json(
                    200,
                    """{"data":{"venues":{"venue":{"id":"v-1","name":"801 Labs","hidden":false,"order":0,"locale":{"id":"l-1","name":"Salt Lake City"},"tags":[],"description":null}}}}""",
                )
            }
        }

        val detail = chatClient(stub).venueDetail("v-1")!!

        assertEquals(listOf("VenueDetail", "SchemaFields", "VenueDetail"), stub.requests.map { it.operation() })
        val retried = stub.requests.last().document()
        for (field in listOf("profile", "chat {", "events {", "recentMessages")) assertFalse(field in retried, field)
        assertEquals("801 Labs", detail.venue.name)
        assertNull(detail.address)
        assertNull(detail.socialLinks)
        assertNull(detail.chatOpen)
        assertNull(detail.recentMessages)
        assertNull(detail.upcomingEvents)
    }

    @Test
    fun aVenueThatDoesNotDecodeIsADecodingError() = runTest {
        val stub = StubTransport { StubTransport.json(200, """{"data":{"venues":{"venue":{"id":"v-1","name":"No locale"}}}}""") }

        kotlin.test.assertFailsWith<AudienceKitException.Decoding> { chatClient(stub).venueDetail("v-1") }
    }

    @Test
    fun graphQLEnvelopeEdgeCases() = runTest {
        suspend fun eventsFrom(body: String, status: Int = 200) = chatClient(StubTransport { StubTransport.json(status, body) }).events()

        kotlin.test.assertFailsWith<AudienceKitException.Decoding> { eventsFrom("""{"data":null}""") }
        kotlin.test.assertFailsWith<AudienceKitException.Decoding> { eventsFrom("<html>Bad gateway</html>") }
        val error = kotlin.test.assertFailsWith<AudienceKitException.GraphQL> { eventsFrom("""{"errors":[{"message":"Boom"}]}""") }
        assertTrue("Boom" in (error.message ?: ""), error.message)
        assertEquals(emptyList(), eventsFrom("""{"data":{"events":{"list":{"nodes":[]}}},"errors":[]}"""))
    }

    @Test
    fun anRsvpAnswerThisSdkDoesNotKnowReadsAsUnsure() = runTest {
        val stub = StubTransport {
            StubTransport.json(200, """{"data":{"events":{"list":{"nodes":[{"id":"e-1","name":"x","startAt":"2026-11-10T02:00:00Z","tags":[],"rsvp":{"mine":"PLUS_ONE","count":3}}]}}}}""")
        }

        val rsvp = chatClient(stub).events().single().rsvp
        assertEquals(RSVPState.UNSURE, rsvp?.mine)
        assertEquals(3, rsvp?.count)
    }

    @Test
    fun eventSeriesDecodeAndNameTheirFilters() = runTest {
        val stub = StubTransport {
            StubTransport.json(
                200,
                """{"data":{"events":{"series":{"nodes":[{"id":"s-1","name":"Open hack night","description":null,
                  "recurrenceText":"Every Tuesday","startsOn":"2026-01-06","startTime":"19:00","timeZone":"America/Denver",
                  "durationMinutes":180,"bannerUrl":null,"locale":null,"tags":[],
                  "venue":{"name":"801 Labs","venue":{"id":"v-1","name":"801 Labs","photoUrl":null,"location":null}}}]}}}}""",
            )
        }

        val series = chatClient(stub).eventSeries(venueId = "v-1", first = 5).single()

        val request = stub.requests.single()
        assertEquals("EventSeries", request.operation())
        assertEquals("v-1", request.variable("venueId"))
        assertEquals("5", request.variable("first"))
        assertEquals(kotlinx.serialization.json.JsonNull, request.jsonBody()["variables"]!!.jsonObject["localeId"] ?: kotlinx.serialization.json.JsonNull)
        assertEquals("Every Tuesday", series.recurrenceText)
        assertEquals("2026-01-06", series.startsOn)
        assertEquals("19:00", series.startTime)
        assertEquals("America/Denver", series.timeZone)
        assertEquals(180, series.durationMinutes)
        assertEquals("v-1", series.venue?.id)
        assertEquals("801 Labs", series.venueName)
    }

    @Test
    fun eventSeriesAreEmptyWhenThereAreNone() = runTest {
        val stub = StubTransport { StubTransport.json(200, """{"data":{"events":{"series":null}}}""") }

        assertEquals(emptyList(), chatClient(stub).eventSeries())
    }

    @Test
    fun sendChatMessageToAVenueRepliesToAPrompt() = runTest {
        val stub = StubTransport {
            StubTransport.json(200, """{"data":{"sendMyChatMessage":{"message":$LINE}}}""")
        }

        chatClient(stub).sendChatMessage("hi", ChatRoom.Venue("v-1"), promptId = "p-1")

        val input = stub.requests.single().jsonBody()["variables"]!!.jsonObject["input"]!!.jsonObject
        assertEquals("v-1", input["venueId"]!!.jsonPrimitive.content)
        assertEquals("hi", input["message"]!!.jsonPrimitive.content)
        assertEquals("p-1", input["promptId"]!!.jsonPrimitive.content)
        assertNull(input["localeId"])
    }

    @Test
    fun removeChatMessageNamesTheMessage() = runTest {
        val stub = StubTransport {
            StubTransport.json(200, """{"data":{"removeMyChatMessage":{"deletedId":"m-1"}}}""")
        }

        chatClient(stub).removeChatMessage("m-1")

        val request = stub.requests.single()
        assertEquals("RemoveMyChatMessage", request.operation())
        assertEquals("m-1", request.variable("messageId"))
    }

    @Test
    fun removingSomeoneElsesMessageThrows() = runTest {
        val stub = StubTransport {
            StubTransport.json(200, """{"errors":[{"message":"Not yours","extensions":{"code":"FORBIDDEN"}}]}""")
        }

        kotlin.test.assertFailsWith<AudienceKitException.GraphQL> { chatClient(stub).removeChatMessage("m-1") }
    }

    @Test
    fun everyChatRoomEventDecodes() {
        fun decode(json: String) = ChatRoomEvent.decode(Json.parseToJsonElement(json).jsonObject)
        val message = ChatMessage(id = "m-1", body = "hi", message = "hi", name = "Ada L.", userId = "u-2", sentAt = "2026-11-06T18:00:00Z")

        assertEquals(
            ChatRoomEvent.Joined(emptyList(), emptyList(), message, false),
            decode("""{"__typename":"ChatJoined","roster":null,"history":[],"pinnedMessage":{"message":$LINE}}"""),
        )
        assertEquals(ChatRoomEvent.Updated(message), decode("""{"__typename":"ChatMessageUpdated","message":$LINE}"""))
        assertEquals(
            ChatRoomEvent.PinChanged("m-1", true, message),
            decode("""{"__typename":"ChatPinChanged","messageId":"m-1","pinned":true,"announcement":$LINE}"""),
        )
        assertEquals(
            ChatRoomEvent.PinChanged("m-1", false, null),
            decode("""{"__typename":"ChatPinChanged","messageId":"m-1","pinned":false,"announcement":null}"""),
        )
        assertEquals(
            ChatRoomEvent.Cleared("2026-11-06T18:00:00Z", true),
            decode("""{"__typename":"ChatRoomCleared","clearedAt":"2026-11-06T18:00:00Z","expired":true}"""),
        )
        assertEquals(
            ChatRoomEvent.PresenceChanged("u-2", "Ada L.", null, "ONLINE"),
            decode("""{"__typename":"ChatPresenceChanged","userId":"u-2","name":"Ada L.","presence":"ONLINE"}"""),
        )
        assertEquals(
            ChatRoomEvent.PresenceChanged("u-2", null, null, "OFFLINE"),
            decode("""{"__typename":"ChatPresenceChanged","userId":"u-2"}"""),
        )
        assertEquals(ChatRoomEvent.RangeChanged(true), decode("""{"__typename":"ChatRangeChanged","outOfRange":true}"""))
        assertEquals(ChatRoomEvent.Left("REMOVED"), decode("""{"__typename":"ChatLeft"}"""))
        // A known event missing what identifies it can't be acted on.
        assertEquals(ChatRoomEvent.Unknown("ChatMessageRemoved"), decode("""{"__typename":"ChatMessageRemoved"}"""))
        assertEquals(ChatRoomEvent.Unknown("ChatMessagePosted"), decode("""{"__typename":"ChatMessagePosted","message":null}"""))
        assertEquals(ChatRoomEvent.Unknown(""), decode("""{}"""))
    }

    @Test
    fun oneBadMessageDoesNotLoseTheJoin() {
        val noId = """{"body":"hi","kind":"TEXT"}"""
        val joined = ChatRoomEvent.decode(
            Json.parseToJsonElement(
                """{"__typename":"ChatJoined","roster":{"people":[{"userId":"u-2"},{"name":"?"}]},""" +
                    """"history":[{"message":$LINE},{"message":$noId}],"pinnedMessage":{"message":$noId}}""",
            ).jsonObject,
        )

        val event = assertIs<ChatRoomEvent.Joined>(joined)
        assertEquals(listOf("m-1"), event.history.map { it.id })
        assertEquals(listOf("u-2"), event.people.map { it.userId })
        assertNull(event.pinned)
        assertEquals(
            ChatRoomEvent.Unknown("ChatMessagePosted"),
            ChatRoomEvent.decode(Json.parseToJsonElement("""{"__typename":"ChatMessagePosted","message":$noId}""").jsonObject),
        )
    }

    @Test
    fun aMessageWithOnlyAnIdTakesTheDefaults() {
        val message = AudienceKitClient.json.decodeFromString(ChatMessage.serializer(), """{"id":"m-2","role":"HOST","kind":"PHOTO","photoUrl":"https://x/p.jpg"}""")

        assertEquals("", message.body)
        assertEquals("HOST", message.role)
        assertEquals("PHOTO", message.kind)
        assertFalse(message.pinned)
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
class ChatSubscriptionTest {
    private class FakeSocket(val listener: CableSocket.Listener) : CableSocket {
        val sent = mutableListOf<JsonObject>()
        override fun send(text: String): Boolean {
            sent += Json.parseToJsonElement(text).jsonObject
            return true
        }

        override fun close(code: Int, reason: String?) = Unit

        fun receive(frame: String) = listener.onMessage(frame)
        fun identifier(): String = sent.first { it["command"]!!.jsonPrimitive.content == "subscribe" }["identifier"]!!.jsonPrimitive.content
        fun execute(): JsonObject = Json.parseToJsonElement(
            sent.first { it["command"]!!.jsonPrimitive.content == "message" }["data"]!!.jsonPrimitive.content,
        ).jsonObject

        fun result(identifier: String, result: String, more: Boolean = true) =
            receive(JsonObject(mapOf("identifier" to JsonPrimitive(identifier), "message" to Json.parseToJsonElement("""{"result":$result,"more":$more}"""))).toString())
    }

    private class FakeFactory : CableSocketFactory {
        val sockets = mutableListOf<FakeSocket>()
        override fun open(url: String, headers: Map<String, String>, listener: CableSocket.Listener): CableSocket =
            FakeSocket(listener).also { sockets += it }
    }

    private class Collected(val updates: MutableList<ChatRoomUpdate>, val job: Job)

    private fun TestScope.collect(flow: Flow<ChatRoomUpdate>): Collected {
        val updates = mutableListOf<ChatRoomUpdate>()
        val job = backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { flow.toList(updates) }
        return Collected(updates, job)
    }

    /** A chat subscription on a welcomed, confirmed socket, and its identifier. */
    private fun TestScope.joined(room: ChatRoom, watch: Boolean = false): Triple<Collected, FakeSocket, String> {
        val factory = FakeFactory()
        val cable = CableConnection("wss://example.test/connection", { "t-1" }, factory, scope = backgroundScope)
        val collected = collect(cable.chat(CHAT_AUDIENCE_ID, room, watch))
        runCurrent()
        val socket = factory.sockets.single()
        socket.receive("""{"type":"welcome"}""")
        val identifier = socket.identifier()
        socket.receive(JsonObject(mapOf("type" to JsonPrimitive("confirm_subscription"), "identifier" to JsonPrimitive(identifier))).toString())
        runCurrent()
        return Triple(collected, socket, identifier)
    }

    @Test
    fun runsTheRoomsSubscriptionAndEmitsItsEvents() = runTest {
        val (collected, socket, identifier) = joined(ChatRoom.Venue("v-1"))

        val execute = socket.execute()
        assertEquals("ChatRoom", execute["operationName"]!!.jsonPrimitive.content)
        assertEquals("v-1", execute["variables"]!!.jsonObject["id"]!!.jsonPrimitive.content)
        assertTrue("room: venueChat(venueId: \$id)" in execute["query"]!!.jsonPrimitive.content)

        socket.result(identifier, """{"data":{"room":{"__typename":"ChatJoined","outOfRange":false,"roster":{"people":[]},"history":[{"message":$LINE}],"pinnedMessage":null}}}""")
        socket.result(identifier, """{"data":{"room":{"__typename":"ChatMessageRemoved","messageId":"m-1"}}}""")
        runCurrent()

        assertEquals(ChatRoomUpdate.Subscribed, collected.updates[0])
        val joined = assertIs<ChatRoomEvent.Joined>(assertIs<ChatRoomUpdate.Event>(collected.updates[1]).event)
        assertEquals(listOf("m-1"), joined.history.map { it.id })
        assertEquals(ChatRoomUpdate.Event(ChatRoomEvent.Removed("m-1")), collected.updates[2])
        assertTrue(collected.job.isActive)
    }

    @Test
    fun watchingALocaleAsksToWatch() = runTest {
        val (_, socket, _) = joined(ChatRoom.Locale("l-1"), watch = true)

        assertTrue("room: localeChat(localeId: \$id, watch: true)" in socket.execute()["query"]!!.jsonPrimitive.content)
    }

    @Test
    fun aRefusedRoomEmitsItsErrorsAndEnds() = runTest {
        val (collected, socket, identifier) = joined(ChatRoom.Venue("v-1"))

        socket.result(identifier, """{"data":null,"errors":[{"message":"You're not at this venue"}]}""")
        runCurrent()

        val refused = assertIs<ChatRoomUpdate.Refused>(collected.updates.last())
        assertEquals("You're not at this venue", refused.errors.single().jsonObject["message"]!!.jsonPrimitive.content)
        assertFalse(collected.job.isActive, "the flow ends after Refused")
    }

    @Test
    fun aRejectedChannelIsRefusedWithNoErrors() = runTest {
        val factory = FakeFactory()
        val cable = CableConnection("wss://example.test/connection", { "t-1" }, factory, scope = backgroundScope)
        val collected = collect(cable.chat(CHAT_AUDIENCE_ID, ChatRoom.Venue("v-1")))
        runCurrent()
        val socket = factory.sockets.single()
        socket.receive("""{"type":"welcome"}""")
        socket.receive(JsonObject(mapOf("type" to JsonPrimitive("reject_subscription"), "identifier" to JsonPrimitive(socket.identifier()))).toString())
        runCurrent()

        assertEquals(listOf<ChatRoomUpdate>(ChatRoomUpdate.Refused(kotlinx.serialization.json.JsonArray(emptyList()))), collected.updates)
        assertFalse(collected.job.isActive)
    }

    @Test
    fun aDroppedSocketSaysItReconnects() = runTest {
        val (collected, socket, _) = joined(ChatRoom.Venue("v-1"))

        socket.listener.onClosed("network")
        runCurrent()

        assertEquals(ChatRoomUpdate.Disconnected("network", true), collected.updates.last())
        assertTrue(collected.job.isActive)
    }

    @Test
    fun aServerDisconnectWithoutReconnectEndsTheRoom() = runTest {
        val (collected, socket, _) = joined(ChatRoom.Venue("v-1"))

        socket.receive("""{"type":"disconnect","reason":"server_restart","reconnect":false}""")
        runCurrent()

        assertEquals(ChatRoomUpdate.Disconnected("server_restart", false), collected.updates.last())
        assertFalse(collected.job.isActive)
    }

    @Test
    fun aResultWithNeitherDataNorErrorsIsSkipped() = runTest {
        val (collected, socket, identifier) = joined(ChatRoom.Venue("v-1"))

        socket.result(identifier, """{"data":{"room":null}}""")
        runCurrent()

        assertEquals(listOf<ChatRoomUpdate>(ChatRoomUpdate.Subscribed), collected.updates)
    }
}
