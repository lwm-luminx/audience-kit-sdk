package com.audiencekit

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

private const val EVENTS_AUDIENCE_ID = "b0f8b66a-e636-495d-9475-0f5317ea08e0"

private fun eventsClient(stub: StubTransport): AudienceKitClient = AudienceKitClient(
    AudienceKitConfiguration(baseUrl = StubTransport.BASE_URL, audienceId = EVENTS_AUDIENCE_ID),
    InMemoryTokenStore("session-token"),
    stub,
)

private fun RecordedRequest.document(): String = (jsonBody()["query"] as JsonPrimitive).content
private fun RecordedRequest.operation(): String? = (jsonBody()["operationName"] as? JsonPrimitive)?.content

/** An audience without RSVP, People, Ticketing, Listings, Google Places or Friends, as introspection shows it. */
private val reducedFields = mapOf(
    "Event" to listOf("id", "name", "startAt", "locale", "tags", "venue"),
    "EventSeries" to listOf("id", "name", "venue"),
    "Locale" to listOf("id", "name"),
    "Location" to listOf("id", "point", "address"),
    "Person" to listOf("id", "name"),
    "Venue" to listOf("id", "name", "locale", "location", "tags", "events", "chat"),
)

private fun reducedSchema(request: RecordedRequest): StubTransport.Reply {
    val entries = Regex("""(t\d+): __type\(name: "(\w+)"\)""").findAll(request.document()).map { match ->
        val (alias, type) = match.destructured
        val fields = reducedFields[type]?.joinToString(",", """{"fields":[""", "]}") { """{"name":"$it"}""" } ?: "null"
        "\"$alias\":$fields"
    }
    return StubTransport.json(200, """{"data":{${entries.joinToString(",")}}}""")
}

private const val EVENT_JSON = """
{"id":"e-1","name":"DEF CON 35","startAt":"2027-08-05T16:00:00Z","isFeatured":true,"isCanceled":false,
 "locale":{"id":"l-1","name":"Las Vegas"},"tags":[],
 "venue":{"name":"LVCC","venue":{"id":"v-1","name":"LVCC","location":{"id":"loc-1","point":"POINT (-115.1523 36.1318)"}}},
 "rsvp":{"mine":"ATTENDING","count":12},
 "people":{"hosts":{"nodes":[{"id":"p-1","name":"Dark Tangent"}]},"lineup":{"nodes":[]}},
 "tickets":{"url":"https://defcon.org/tickets",
   "offers":{"nodes":[{"price":{"cents":46000,"currency":"usd"},"url":"https://defcon.org/tickets",
     "seller":{"key":"defcon","name":"DEF CON"}}]},
   "cover":{"charge":null}}}
"""

class EventsTest {
    @Test
    fun eventsDecodeEveryModulesFieldsAndTheWktPoint() = runTest {
        val stub = StubTransport { StubTransport.json(200, """{"data":{"events":{"list":{"nodes":[$EVENT_JSON]}}}}""") }

        val events = eventsClient(stub).events(localeId = "l-1")

        val variables = stub.requests.single().jsonBody()["variables"]!!.jsonObject
        assertEquals("UPCOMING", (variables["window"] as JsonPrimitive).content)
        assertEquals("l-1", (variables["localeId"] as JsonPrimitive).content)
        // No page: a page of 100 events is over the API's complexity budget.
        assertEquals(JsonNull, variables["first"])
        val event = events.single()
        assertEquals("LVCC", event.venueName)
        assertEquals(36.1318, event.venue?.location?.coordinate?.latitude)
        assertEquals(RSVPState.ATTENDING, event.rsvp?.mine)
        assertEquals(listOf("Dark Tangent"), event.hosts?.map { it.name })
        assertEquals("https://defcon.org/tickets", event.ticketUrl)
        assertEquals(
            listOf(AdmissionOffer(Money(46000, "usd"), "https://defcon.org/tickets", AdmissionOffer.Seller("defcon", "DEF CON"))),
            event.ticketOffers,
        )
        assertNull(event.coverCharge)
        val document = stub.requests.single().document()
        assertTrue("offers { nodes { price { cents currency } url seller { key name } } }" in document)
        assertTrue("cover { charge {" in document)
    }

    @Test
    fun anEventsPageCarriesItsCommunityChats() = runTest {
        val links = """"socialLinks":{"nodes":[""" +
            """{"id":"s-1","handle":"defcon","provider":"discord","url":"https://discord.gg/defcon"},""" +
            """{"id":"s-2","handle":"#dc:example.org","provider":"matrix","url":"https://matrix.to/#/#dc:example.org"},""" +
            """{"id":"s-3","handle":"defcon","provider":"x","url":"https://x.com/defcon"}]}"""
        val stub = StubTransport {
            StubTransport.json(200, """{"data":{"events":{"event":${EVENT_JSON.trim().dropLast(1)},$links}}}}""")
        }

        val event = eventsClient(stub).event("e-1")!!

        assertTrue("socialLinks { nodes { id handle provider url } }" in stub.requests.single().document())
        assertEquals(listOf("discord", "matrix", "x"), event.socialLinks?.map { it.provider })
        assertEquals(listOf("Discord", "Matrix"), event.communityChats.map { it.networkName })
        assertEquals("https://discord.gg/defcon", event.communityChats.first().url)
    }

    @Test
    fun eventListsLeaveLinksOut() = runTest {
        val stub = StubTransport { StubTransport.json(200, """{"data":{"events":{"list":{"nodes":[$EVENT_JSON]}}}}""") }

        val event = eventsClient(stub).events().single()

        assertFalse("socialLinks" in stub.requests.single().document())
        assertNull(event.socialLinks)
        assertEquals(emptyList(), event.communityChats)
    }

    @Test
    fun socialLinksNameTheirNetworks() {
        val names = listOf("irc", "mailing_list", "apple_music", "tiktok").map { SocialLink("i", "h", it).networkName }
        assertEquals(listOf("IRC", "Mailing list", "Apple Music", "TikTok"), names)
        assertTrue(SocialLink("i", "h", "irc").isCommunityChat)
        assertFalse(SocialLink("i", "h", "instagram").isCommunityChat)
    }

    @Test
    fun venueOffersListEveryWayInForTheNight() = runTest {
        val stub = StubTransport {
            StubTransport.json(
                200,
                """{"data":{"venues":{"venue":{"id":"v-1","tickets":{"offers":{"nodes":[""" +
                    """{"price":{"cents":1500,"currency":"usd"},"url":null,"seller":{"key":"audiencekit","name":"AudienceKit"}}]}}}}}}""",
            )
        }

        val offers = eventsClient(stub).venueOffers("v-1", night = "2026-11-07")

        assertEquals(listOf("audiencekit"), offers.map { it.seller.key })
        assertEquals(Money(1500, "usd"), offers.single().price)
        val request = stub.requests.single()
        assertEquals("VenueOffers", request.operation())
        assertEquals("2026-11-07", (request.jsonBody()["variables"]!!.jsonObject["night"] as JsonPrimitive).content)
    }

    @Test
    fun venueCoverAndOffersWithoutTicketingAskOnlyForTheVenue() = runTest {
        val stub = StubTransport { request ->
            when {
                request.operation() == "SchemaFields" -> reducedSchema(request)
                "tickets" in request.document() -> StubTransport.json(
                    200,
                    """{"errors":[{"message":"Field 'tickets' doesn't exist on type 'Venue'","extensions":{"code":"undefinedField"}}]}""",
                )
                else -> StubTransport.json(200, """{"data":{"venues":{"venue":{"id":"v-1","name":"801 Labs"}}}}""")
            }
        }
        val client = eventsClient(stub)

        val cover = client.venueCover("v-1")
        assertEquals("801 Labs", cover?.name)
        assertNull(cover?.coverCharge)

        assertEquals(emptyList<AdmissionOffer>(), client.venueOffers("v-1"))
        assertEquals(listOf("VenueCover", "SchemaFields", "VenueCover", "VenueOffers"), stub.requests.map { it.operation() })
        assertFalse("\$night" in stub.requests[3].document())
    }

    @Test
    fun anAudienceWithoutAModuleGetsTheQueryAgainWithoutItsFields() = runTest {
        val stub = StubTransport { request ->
            when {
                request.operation() == "SchemaFields" -> reducedSchema(request)
                "rsvp" in request.document() -> StubTransport.json(
                    200,
                    """{"errors":[{"message":"Field 'rsvp' doesn't exist on type 'Event'","extensions":{"code":"undefinedField"}}]}""",
                )
                else -> StubTransport.json(
                    200,
                    """{"data":{"events":{"list":{"nodes":[{"id":"e-2","name":"801 Labs open night","venue":{"name":"801 Labs"}}]}}}}""",
                )
            }
        }
        val client = eventsClient(stub)

        val events = client.events()

        assertEquals(listOf("801 Labs open night"), events.map { it.name })
        assertNull(events.single().rsvp)
        assertEquals(listOf("Events", "SchemaFields", "Events"), stub.requests.map { it.operation() })
        val retried = stub.requests[2].document()
        for (field in listOf("rsvp", "people", "tickets", "places", "profile")) assertFalse(field in retried, field)
        assertTrue("venue { name venue" in retried)

        // Remembered: the next call goes straight to the reduced document.
        client.event("e-2")
        assertEquals(4, stub.requests.size)
        assertFalse("rsvp" in stub.requests[3].document())
    }

    @Test
    fun otherGraphQLErrorsAreNotRetried() = runTest {
        val stub = StubTransport {
            StubTransport.json(200, """{"errors":[{"message":"Not allowed","extensions":{"code":"FORBIDDEN"}}]}""")
        }

        assertFailsWith<AudienceKitException.GraphQL> { eventsClient(stub).events() }
        assertEquals(1, stub.requests.size)
    }

    @Test
    fun sendChatMessageNamesTheRoom() = runTest {
        val stub = StubTransport {
            StubTransport.json(
                200,
                """{"data":{"sendMyChatMessage":{"message":{"id":"m-9","body":"on my way","message":"on my way","kind":"TEXT","pinned":false}}}}""",
            )
        }

        val message = eventsClient(stub).sendChatMessage("on my way", ChatRoom.Locale("l-1"))

        assertEquals("m-9", message.id)
        val input = stub.requests.single().jsonBody()["variables"]!!.jsonObject["input"]!!.jsonObject
        assertEquals("l-1", (input["localeId"] as JsonPrimitive).content)
        assertNull(input["venueId"])
    }

    @Test
    fun chatRoomEventsDecode() {
        fun decode(json: String) = ChatRoomEvent.decode(Json.parseToJsonElement(json).jsonObject)
        val line = """{"id":"m-1","body":"hi","message":"hi","name":"Ada L.","userId":"u-2","kind":"TEXT","pinned":false}"""
        val message = ChatMessage(id = "m-1", body = "hi", message = "hi", name = "Ada L.", userId = "u-2")

        assertEquals(
            ChatRoomEvent.Joined(listOf(ChatRosterPerson("u-2", "Ada L.", null, true)), listOf(message), null, true),
            decode(
                """{"__typename":"ChatJoined","outOfRange":true,"roster":{"people":[{"userId":"u-2","name":"Ada L.","friend":true}]},""" +
                    """"history":[{"message":$line}],"pinnedMessage":null}""",
            ),
        )
        assertEquals(ChatRoomEvent.Posted(message), decode("""{"__typename":"ChatMessagePosted","message":$line}"""))
        assertEquals(ChatRoomEvent.Removed("m-1"), decode("""{"__typename":"ChatMessageRemoved","messageId":"m-1"}"""))
        assertEquals(ChatRoomEvent.Left("BANNED"), decode("""{"__typename":"ChatLeft","reason":"BANNED"}"""))
        assertEquals(ChatRoomEvent.Unknown("ChatSomethingNew"), decode("""{"__typename":"ChatSomethingNew"}"""))
    }

    @Test
    fun chatRoomDocumentNamesItsField() {
        assertTrue("room: venueChat(venueId: \$id)" in Queries.chatRoom(ChatRoom.Venue("v-1")))
        assertTrue("room: localeChat(localeId: \$id, watch: true)" in Queries.chatRoom(ChatRoom.Locale("l-1"), watch = true))
    }
}
