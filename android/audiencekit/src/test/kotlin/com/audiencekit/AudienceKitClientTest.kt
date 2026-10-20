package com.audiencekit

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.net.UnknownHostException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

private const val AUDIENCE_ID = "b0f8b66a-e636-495d-9475-0f5317ea08e0"
private val device = DeviceDescription(identifier = "device-1", model = "Google Pixel 9", version = "2.0", build = "42")

private fun makeClient(
    stub: StubTransport,
    host: String? = "hotmess.admin.audiencekit.com",
    audienceId: String? = AUDIENCE_ID,
    token: String? = "session-token",
    environment: AudienceKitEnvironment = AudienceKitEnvironment.PRODUCTION,
): Pair<AudienceKitClient, InMemoryTokenStore> {
    val store = InMemoryTokenStore(token)
    val configuration = AudienceKitConfiguration(
        baseUrl = StubTransport.BASE_URL,
        host = host,
        audienceId = audienceId,
        facebookAppId = "842337999153841",
        environment = environment,
    )
    return AudienceKitClient(configuration, store, stub) to store
}

/** The next event, or null when none is waiting. */
private suspend fun <T> Flow<T>.firstOrNull(timeoutMillis: Long): T? = withTimeoutOrNull(timeoutMillis + 1) { first() }

private fun JsonObject.string(key: String) = (get(key) as? JsonPrimitive)?.content

class SdkTest {
    @Test
    fun versionIsSet() {
        assertTrue(AudienceKitSDK.VERSION.isNotEmpty())
    }
}

class SignInTest {
    @Test
    fun exchangesTheFacebookTokenAndStoresTheSession() = runTest {
        val stub = StubTransport {
            StubTransport.json(
                200,
                """{"token":"jwt-1","userId":"u-1","audienceId":"$AUDIENCE_ID","role":"member",
                 "endpoint":"https://api.audiencekit.test/v1/audience/$AUDIENCE_ID/graphql","venueDeviceId":null,"expiresAt":null}""",
            )
        }
        val (client, store) = makeClient(stub, token = null)

        val result = client.signIn("fb-token", device)

        assertEquals("jwt-1", result.token)
        assertEquals("u-1", result.userId)
        assertEquals(AUDIENCE_ID, result.audienceId)
        assertEquals("member", result.role)
        assertEquals("https://api.audiencekit.test/v1/audience/$AUDIENCE_ID/graphql", result.endpoint)
        assertNull(result.expiresAt)
        assertEquals("jwt-1", store.loadToken())
        assertEquals(AUDIENCE_ID, store.loadAudienceId())
        assertTrue(client.isSignedIn)
        assertEquals(SessionEvent.SIGNED_IN, client.sessionEvents.first())

        val request = stub.requests.single()
        assertEquals("POST", request.method)
        assertEquals("/v1/token", request.path)
        assertNull(request.header("Authorization"))
        assertEquals("application/json", request.header("Content-Type"))

        val body = request.jsonBody()
        assertEquals("fb-token", body.string("facebook_token"))
        assertEquals("hotmess.admin.audiencekit.com", body.string("host"))
        assertEquals("842337999153841", body.string("facebook_app_id"))
        assertEquals(
            mapOf("identifier" to "device-1", "type" to "android", "model" to "Google Pixel 9", "version" to "2.0", "build" to "42"),
            body["device"]!!.jsonObject.mapValues { it.value.jsonPrimitive.content },
        )
    }

    @Test
    fun exchangesAnOAuthCode() = runTest {
        val stub = StubTransport { StubTransport.json(200, """{"token":"jwt-2","userId":"u-1","role":"member","endpoint":"https://api.audiencekit.test/v1/tenants/graphql"}""") }
        val (client, store) = makeClient(stub, token = null)

        client.signIn(facebookCode = "code-1", redirectUri = "fbconnect://cct.social.hotmess.android", device = device)

        val body = stub.requests.single().jsonBody()
        assertEquals("code-1", body.string("code"))
        assertEquals("fbconnect://cct.social.hotmess.android", body.string("redirect_uri"))
        assertFalse("facebook_token" in body)
        assertEquals("hotmess.admin.audiencekit.com", body.string("host"))
        assertEquals("842337999153841", body.string("facebook_app_id"))
        assertEquals("jwt-2", store.loadToken())
    }

    @Test
    fun exchangesAnOAuthCodeForTheAppTheDialogUsed() = runTest {
        val stub = StubTransport { StubTransport.json(200, """{"token":"jwt-2","userId":"u-1","role":"member","endpoint":"https://api.audiencekit.test/v1/tenants/graphql"}""") }
        val (client, _) = makeClient(stub, token = null)

        client.signIn("code-1", "fbconnect://cct.social.hotmess.android", device, facebookAppId = "713525445368431")

        assertEquals("713525445368431", stub.requests.single().jsonBody().string("facebook_app_id"))
    }

    @Test
    fun leavesOutTheHostWhenNoneIsConfigured() = runTest {
        val stub = StubTransport { StubTransport.json(200, """{"token":"jwt-1","userId":"u-1","role":"member","endpoint":"https://api.audiencekit.test/v1/tenants/graphql"}""") }
        val (client, _) = makeClient(stub, host = null, token = null)

        client.signIn("fb-token", device)

        assertFalse("host" in stub.requests.single().jsonBody())
    }

    @Test
    fun aRejectedFacebookTokenIsNotASessionEnding() = runTest {
        val stub = StubTransport { StubTransport.json(401, "{}") }
        val (client, store) = makeClient(stub, token = null)

        assertFailsWith<AudienceKitException.SignInRejected> { client.signIn("bad", device) }
        assertNull(store.loadToken())
    }

    @Test
    fun surfacesTheErrorMessage() = runTest {
        val stub = StubTransport { StubTransport.json(400, """{"error":"INVALID","message":"Facebook token invalid"}""") }
        val (client, _) = makeClient(stub, token = null)

        val error = assertFailsWith<AudienceKitException.SignInFailed> { client.signIn("bad", device) }
        assertEquals("Facebook token invalid", error.faultMessage)
        assertEquals("Facebook token invalid", error.message)
    }

    @Test
    fun exchangesTheGoogleIdTokenAndStoresTheSession() = runTest {
        val stub = StubTransport {
            StubTransport.json(
                200,
                """{"token":"jwt-google","userId":"u-google","audienceId":"$AUDIENCE_ID","role":"member",
                 "endpoint":"https://api.audiencekit.test/v1/audience/$AUDIENCE_ID/graphql","venueDeviceId":null,"expiresAt":null}""",
            )
        }
        val (client, store) = makeClient(stub, token = null)

        val result = client.signInWithGoogle("google-id-token", device, name = "Ada Byron")

        assertEquals("jwt-google", result.token)
        assertEquals("u-google", result.userId)
        assertEquals(AUDIENCE_ID, result.audienceId)
        assertEquals("member", result.role)
        assertEquals("jwt-google", store.loadToken())
        assertEquals(AUDIENCE_ID, store.loadAudienceId())
        assertTrue(client.isSignedIn)
        assertEquals(SessionEvent.SIGNED_IN, client.sessionEvents.first())

        val request = stub.requests.single()
        assertEquals("POST", request.method)
        assertEquals("/v1/token/google", request.path)
        assertNull(request.header("Authorization"))

        val body = request.jsonBody()
        assertEquals("google-id-token", body.string("id_token"))
        assertEquals("hotmess.admin.audiencekit.com", body.string("host"))
        assertEquals("Ada Byron", body.string("name"))
        assertEquals(
            mapOf("identifier" to "device-1", "type" to "android", "model" to "Google Pixel 9", "version" to "2.0", "build" to "42"),
            body["device"]!!.jsonObject.mapValues { it.value.jsonPrimitive.content },
        )
    }

    @Test
    fun sendsTheGoogleAccessTokenForOtherEmails() = runTest {
        val stub = StubTransport {
            StubTransport.json(200, """{"token":"jwt-google","userId":"u-google","audienceId":"$AUDIENCE_ID","role":"member","endpoint":"https://api.audiencekit.test/graphql"}""")
        }
        val (client, _) = makeClient(stub, token = null)

        client.signInWithGoogle("google-id-token", device, accessToken = "google-access-token")

        val body = stub.requests.single().jsonBody()
        assertEquals("google-access-token", body.string("access_token"))
        assertNull(body["connect"])
    }

    @Test
    fun signsInWithAppleWithTheNonceAndReturnURL() = runTest {
        val stub = StubTransport {
            StubTransport.json(200, """{"token":"jwt-apple","userId":"u-apple","audienceId":"$AUDIENCE_ID","role":"member","endpoint":"https://api.audiencekit.test/graphql"}""")
        }
        val (client, store) = makeClient(stub, token = null)
        val signIn = AppleWebSignIn("social.hotmess.signin", "https://api.audiencekit.test/v1/token/apple/callback",
            "social.hotmess.android.app", state = "social.hotmess.android.app~s", nonce = "raw-nonce")
        val credential = AppleWebSignIn.Result.Credential("apple-id-token", "apple-code", "Ada", null)

        val result = client.signInWithApple(credential, signIn, device)

        assertEquals("jwt-apple", result.token)
        assertEquals("jwt-apple", store.loadToken())
        assertEquals(SessionEvent.SIGNED_IN, client.sessionEvents.first())
        val request = stub.requests.single()
        assertEquals("/v1/token/apple", request.path)
        assertNull(request.header("Authorization"))
        val body = request.jsonBody()
        assertEquals("apple-id-token", body.string("identity_token"))
        assertEquals("apple-code", body.string("authorization_code"))
        assertEquals("https://api.audiencekit.test/v1/token/apple/callback", body.string("redirect_uri"))
        assertEquals("raw-nonce", body.string("nonce"))
        assertEquals("Ada", body.string("first_name"))
        assertNull(body["last_name"])
        assertEquals("hotmess.admin.audiencekit.com", body.string("host"))
    }

    @Test
    fun connectsGoogleToTheSignedInAccount() = runTest {
        val stub = StubTransport {
            StubTransport.json(200, """{"token":"jwt-connected","userId":"u-1","audienceId":"$AUDIENCE_ID","role":"member","endpoint":"https://api.audiencekit.test/graphql"}""")
        }
        val (client, store) = makeClient(stub, token = "jwt-facebook")

        val result = client.connectGoogle("google-id-token", device)

        assertEquals("jwt-connected", result.token)
        assertEquals("jwt-connected", store.loadToken())
        val request = stub.requests.single()
        assertEquals("/v1/token/google", request.path)
        assertEquals("Bearer jwt-facebook", request.header("Authorization"))
        assertEquals("true", request.jsonBody()["connect"]!!.jsonPrimitive.content)
    }

    @Test
    fun aRefusedGoogleConnectionKeepsTheSession() = runTest {
        val stub = StubTransport {
            StubTransport.json(400, """{"error":"INVALID","message":"That Google account already signs in to another account"}""")
        }
        val (client, store) = makeClient(stub, token = "jwt-facebook")

        val error = assertFailsWith<AudienceKitException.SignInFailed> { client.connectGoogle("google-id-token", device) }

        assertEquals("That Google account already signs in to another account", error.faultMessage)
        assertEquals("jwt-facebook", store.loadToken())
    }

    @Test
    fun signOutForgetsTheToken() = runTest {
        val stub = StubTransport { StubTransport.json(200, "{}") }
        val (client, store) = makeClient(stub)

        client.signOut()

        assertNull(store.loadToken())
        assertEquals(SessionEvent.SIGNED_OUT, client.sessionEvents.first())
    }
}

class GraphQLTest {
    private val venuesResponse = """
        {"data":{"venues":{"list":{"nodes":[{
          "id":"Z2lkOi8vaG90LW1lc3MvVmVudWUvMTIz","name":null,"hidden":false,"order":3,
          "photoUrl":"/v1/photos/abc","bannerUrl":null,
          "profile":{"facebook":{"page":{"id":"p-1","name":"The Stud","photoUrl":"https://cdn.example/stud.jpg","bannerUrl":null}}},
          "locale":{"id":"l-1","name":"San Francisco","label":"SF","cityNames":null,"bannerUrl":null},
          "location":{"id":"loc-1","point":"POINT (-122.4194 37.7749)","places":{"placeId":"ChIJplace"}},
          "addedLater":"new API fields don't break old clients"
        },{
          "id":"v-2","name":"Pony","hidden":false,"order":4,"photoUrl":null,"bannerUrl":null,"profile":{"facebook":{"page":null}},
          "locale":{"id":"l-2","name":"Seattle","label":"SEA","cityNames":["Seattle","Capitol Hill"],"bannerUrl":null},
          "location":null,"tags":[{"id":"t-1","name":"Leather","color":"#222222"}]
        }]}}}}
    """.trimIndent()

    @Test
    fun stagingBuildsSayTheyAreStagingOnEveryRequest() = runTest {
        val stub = StubTransport { StubTransport.json(200, venuesResponse) }
        val (client, _) = makeClient(stub, environment = AudienceKitEnvironment.STAGING)

        client.venues()

        assertEquals("staging", stub.requests.single().header("X-AudienceKit-Environment"))
    }

    @Test
    fun sendsTheSessionTokenToTheAudienceEndpoint() = runTest {
        val stub = StubTransport { StubTransport.json(200, venuesResponse) }
        val (client, _) = makeClient(stub)

        val venues = client.venues()

        val request = stub.requests.single()
        assertEquals("POST", request.method)
        assertEquals("/v1/audience/$AUDIENCE_ID/graphql", request.path)
        assertEquals("Bearer session-token", request.header("Authorization"))
        assertEquals("AudienceKit-Kotlin/${AudienceKitSDK.VERSION}", request.header("X-AudienceKit-Client"))
        assertEquals(AudienceKitSDK.API_VERSION, request.header("X-AudienceKit-API-Version"))
        assertNull(request.header("X-AudienceKit-Environment"))

        val body = request.jsonBody()
        assertEquals("Venues", body.string("operationName"))
        assertTrue(body.string("query")!!.contains("venues"))

        assertEquals(2, venues.size)
        val venue = venues.first()
        assertEquals("The Stud", venue.name)
        assertEquals(3, venue.order)
        assertEquals("SF", venue.locale.label)
        assertEquals(Coordinate(latitude = 37.7749, longitude = -122.4194), venue.location?.coordinate)
        assertEquals("ChIJplace", venue.location?.googlePlaceId)
        assertEquals("${StubTransport.BASE_URL}/v1/photos/abc", client.url(venue.photoUrl))
        assertEquals("https://cdn.example/stud.jpg", client.url(venue.page?.photoUrl))
        assertNull(client.url(null))

        // A venue added without a Facebook Page has its own name, and cityNames is a list.
        val pageless = venues.last()
        assertNull(pageless.page)
        assertEquals("Pony", pageless.name)
        assertEquals(listOf("Seattle", "Capitol Hill"), pageless.locale.cityNames)

        // Tags default to none when the response leaves them out.
        assertEquals(emptyList(), venue.tags)
        assertEquals(listOf(Tag(id = "t-1", name = "Leather", color = "#222222")), pageless.tags)
    }

    @Test
    fun sendsVariables() = runTest {
        val stub = StubTransport { StubTransport.json(200, """{"data":{"node":{"__typename":"Venue","id":"v-1"}}}""") }
        val (client, _) = makeClient(stub)

        val node = client.node("v-1")

        assertEquals(Node(id = "v-1", typename = "Venue"), node)
        assertEquals(JsonObject(mapOf("id" to JsonPrimitive("v-1"))), stub.requests.single().jsonBody()["variables"])
    }

    @Test
    fun decodesPeopleMeAndTheAudience() = runTest {
        val stub = StubTransport { request ->
            when (request.jsonBody().string("operationName")) {
                "People" -> StubTransport.json(
                    200,
                    """{"data":{"people":{"list":{"nodes":[{"id":"pe-1","order":1,"global":false,"likeRequired":true,
                      "profile":{"facebook":{"page":{"id":"p-2","name":"DJ Example","photoUrl":null,"bannerUrl":null}}}},
                      {"id":"pe-2","name":"DJ Nobody","order":2,"global":false,"likeRequired":false,"profile":{"facebook":{"page":null}}}]}}}}""",
                )
                "Me" -> StubTransport.json(
                    200,
                    """{"data":{"me":{"self":{"id":"u-1","name":"Rick Mark","firstName":"Rick","lastName":"Mark",
                      "emailAddress":null,"isAdmin":true,"presence":"PUSH"}}}}""",
                )
                else -> StubTransport.json(
                    200,
                    """{"data":{"id":"a-1","name":"Hot Mess","subdomain":"hotmess",
                      "theme":{"preset":"hot_mess","tagline":"Queer nights out","light":[{"name":"accent","value":"#9c1c62"}],"dark":[]}}}""",
                )
            }
        }
        val (client, _) = makeClient(stub)

        val people = client.people()
        // Talent added by name has no Facebook Page yet.
        assertEquals(listOf("DJ Example", "DJ Nobody"), people.map { it.name })
        assertNull(people.last().page)
        assertEquals(true, people.first().likeRequired)

        val me = client.me()
        assertEquals("Rick", me?.firstName)
        assertEquals(true, me?.isAdmin)
        assertEquals(Presence.PUSH, me?.presence)

        val audience = client.audience()
        assertEquals("hotmess", audience.subdomain)
        assertEquals(listOf(ThemeToken("accent", "#9c1c62")), audience.theme?.light)
    }

    @Test
    fun decodesPresenceLeniently() {
        val json = Json { ignoreUnknownKeys = true }
        val friends = json.decodeFromString<List<Friend>>(
            """[{"id":"f-1","presence":"ONLINE"},{"id":"f-2","presence":"online"},
              {"id":"f-3","presence":"AWAY"},{"id":"f-4"}]""",
        )

        assertEquals(listOf(Presence.ONLINE, Presence.ONLINE, Presence.OFFLINE, null), friends.map { it.presence })
    }

    @Test
    fun throwsGraphQLErrorsWithTheirMessages() = runTest {
        val stub = StubTransport {
            StubTransport.json(
                200,
                """{"data":null,"errors":[{"message":"Field 'nope' doesn't exist on type 'Query'",
                  "path":["query","nope"],"extensions":{"code":"undefinedField"}}]}""",
            )
        }
        val (client, _) = makeClient(stub)

        val error = assertFailsWith<AudienceKitException.GraphQL> { client.graphQL<JsonObject>("{ nope }") }
        val first = error.errors.first()
        assertEquals("Field 'nope' doesn't exist on type 'Query'", first.message)
        assertEquals(listOf(JsonPrimitive("query"), JsonPrimitive("nope")), first.path)
        assertEquals(JsonPrimitive("undefinedField"), first.extensions?.get("code"))
    }

    @Test
    fun aRejectedSessionEndsIt() = runTest {
        val stub = StubTransport { StubTransport.json(401, "{}") }
        val (client, store) = makeClient(stub)

        assertFailsWith<AudienceKitException.Unauthorized> { client.venues() }

        assertNull(store.loadToken())
        assertFalse(client.isSignedIn)
        assertEquals(SessionEvent.SESSION_ENDED, client.sessionEvents.first())
    }

    @Test
    fun manyRejectedCallsEndTheSessionOnce() = runTest {
        val stub = StubTransport { StubTransport.json(401, "{}") }
        val (client, _) = makeClient(stub)

        assertFailsWith<AudienceKitException.Unauthorized> { client.venues() }
        // Signed out now, so later calls don't reach the API at all.
        assertFailsWith<AudienceKitException.NotSignedIn> { client.people() }
        assertFalse(client.sessionRejected("session-token"))

        assertEquals(listOf(SessionEvent.SESSION_ENDED), client.sessionEvents.take(1).toList())
        assertNull(client.sessionEvents.firstOrNull(timeoutMillis = 0))
        assertEquals(1, stub.requests.size)
    }

    @Test
    fun aRefusalOfAnOlderTokenKeepsANewerSession() = runTest {
        lateinit var store: InMemoryTokenStore
        val stub = StubTransport {
            // The person signed in again while the old token's call was in flight.
            store.saveToken("newer-token")
            StubTransport.json(401, "{}")
        }
        val made = makeClient(stub)
        val client = made.first
        store = made.second

        assertFailsWith<AudienceKitException.Unauthorized> { client.venues() }

        assertEquals("newer-token", store.loadToken())
        assertEquals("Bearer session-token", stub.requests.single().header("Authorization"))
        assertNull(client.sessionEvents.firstOrNull(timeoutMillis = 0))
    }

    @Test
    fun aSocketTheServerRefusedEndsTheSession() = runTest {
        val stub = StubTransport { StubTransport.json(200, "{}") }
        val (client, store) = makeClient(stub)

        assertFalse(client.sessionRejected("someone-elses-token"))
        assertEquals("session-token", store.loadToken())

        assertTrue(client.sessionRejected("session-token"))
        assertNull(store.loadToken())
        assertEquals(SessionEvent.SESSION_ENDED, client.sessionEvents.first())
        assertFalse(client.sessionRejected("session-token"))
    }

    @Test
    fun aRefusedSignInIsNotASessionEnding() = runTest {
        val stub = StubTransport { StubTransport.json(401, "{}") }
        val (client, store) = makeClient(stub)

        assertFailsWith<AudienceKitException.SignInRejected> { client.signIn("facebook-token", device) }
        assertEquals("session-token", store.loadToken())
        assertNull(client.sessionEvents.firstOrNull(timeoutMillis = 0))
    }

    @Test
    fun forbiddenIsNotASessionEnding() = runTest {
        val stub = StubTransport { StubTransport.json(403, "{}") }
        val (client, store) = makeClient(stub)

        assertFailsWith<AudienceKitException.Forbidden> { client.venues() }
        assertEquals("session-token", store.loadToken())
    }

    @Test
    fun requiresASession() = runTest {
        val stub = StubTransport { StubTransport.json(200, "{}") }
        val (client, _) = makeClient(stub, token = null)

        assertFailsWith<AudienceKitException.NotSignedIn> { client.venues() }
        assertTrue(stub.requests.isEmpty())
    }

    @Test
    fun reportsNetworkFailures() = runTest {
        val offline = UnknownHostException("api.audiencekit.test")
        val stub = StubTransport { StubTransport.failure(offline) }
        val (client, _) = makeClient(stub)

        val error = assertFailsWith<AudienceKitException.Network> { client.venues() }
        assertSame(offline, error.cause)
    }

    @Test
    fun reportsMalformedResponses() = runTest {
        val stub = StubTransport { StubTransport.json(200, """{"data":{"venues":"nope"}}""") }
        val (client, _) = makeClient(stub)

        assertFailsWith<AudienceKitException.Decoding> { client.venues() }
    }
}

class MobileOperationsTest {
    @Test
    fun findsTheClosestLocale() = runTest {
        val stub = StubTransport {
            StubTransport.json(200, """{"data":{"closestLocale":{"id":"l-1","name":"Seattle","label":"SEA"}}}""")
        }
        val (client, _) = makeClient(stub)

        val locale = client.closestLocale(Coordinates(latitude = 47.6, longitude = -122.3, beaconMajor = 0))

        assertEquals("Seattle", locale?.name)
        val near = stub.requests.single().jsonBody()["variables"]!!.jsonObject["near"]!!.jsonObject
        assertEquals(47.6, near["latitude"]!!.jsonPrimitive.double)
        assertEquals(-122.3, near["longitude"]!!.jsonPrimitive.double)
        assertFalse("beaconMajor" in near)
    }

    @Test
    fun setsAnRSVP() = runTest {
        val stub = StubTransport {
            StubTransport.json(
                200,
                """{"data":{"rsvpEvent":{"event":{"id":"e-1","rsvp":{"count":3,"mine":"ATTENDING","mineSource":"RSVP"}}}}}""",
            )
        }
        val (client, _) = makeClient(stub)

        val state = client.setRSVP(RSVPState.ATTENDING, eventId = "e-1")

        assertEquals(RSVPState.ATTENDING, state)
        val body = stub.requests.single().jsonBody()
        val variables = body["variables"]!!.jsonObject
        assertEquals("e-1", variables.string("eventId"))
        assertEquals("ATTENDING", variables.string("state"))
        assertTrue(body.string("query")!!.contains("rsvp { count mine mineSource }"))
    }

    @Test
    fun cancelsAnRSVPButATicketHolderStaysGoing() = runTest {
        val stub = StubTransport {
            StubTransport.json(
                200,
                """{"data":{"cancelRsvp":{"event":{"id":"e-1","rsvp":{"count":2,"mine":"ATTENDING","mineSource":"TICKET"}}}}}""",
            )
        }
        val (client, _) = makeClient(stub)

        val rsvp = client.cancelRSVP(eventId = "e-1")

        assertEquals(EventRSVP(count = 2, mine = RSVPState.ATTENDING, mineSource = RSVPSource.TICKET), rsvp)
        assertEquals("CancelRSVP", stub.requests.single().jsonBody().string("operationName"))
    }

    @Test
    fun readsWhoIsGoing() = runTest {
        val stub = StubTransport {
            StubTransport.json(
                200,
                """{"data":{"events":{"event":{"id":"e-1","rsvp":{"count":2,"mine":"UNSURE","mineSource":null,""" +
                    """"counts":null,"attendees":{"nodes":[{"profile":{"id":"u-1","name":"Frankie Friend","avatarUrl":null},""" +
                    """"friend":true,"source":"RSVP"},{"profile":{"id":"u-2","name":"Sam S.","avatarUrl":null},"friend":false,""" +
                    """"source":"TICKET"}]}}}}}}""",
            )
        }
        val (client, _) = makeClient(stub)

        val rsvp = client.eventRSVP(eventId = "e-1", first = 10)!!

        assertEquals(2, rsvp.count)
        assertEquals(RSVPState.UNSURE, rsvp.mine)
        assertEquals(null, rsvp.counts)
        assertEquals(
            listOf(
                EventAttendee(Profile("u-1", "Frankie Friend"), friend = true, source = RSVPSource.RSVP),
                EventAttendee(Profile("u-2", "Sam S."), friend = false, source = RSVPSource.TICKET),
            ),
            rsvp.attendees,
        )
        assertEquals(10, stub.requests.single().jsonBody()["variables"]!!.jsonObject["first"]!!.jsonPrimitive.int)
    }

    @Test
    fun registersTheDevice() = runTest {
        val stub = StubTransport { StubTransport.json(200, """{"data":{"registerDevice":{"registered":true}}}""") }
        val (client, _) = makeClient(stub)

        client.registerDevice(notificationToken = "fcm")

        val body = stub.requests.single().jsonBody()
        assertEquals("RegisterDevice", body.string("operationName"))
        assertEquals("fcm", body["variables"]!!.jsonObject.string("notificationToken"))
    }

    @Serializable
    data class ReportLocationResponse(val reportLocation: Payload) {
        @Serializable data class Payload(val locale: Locale?, val nearbyVenues: List<NearbyVenue>?)
        @Serializable data class Locale(val name: String)
        @Serializable data class NearbyVenue(val id: String, val distance: Double)
    }

    @Test
    fun reportsTheLocationIntoTheCallersModel() = runTest {
        val stub = StubTransport {
            StubTransport.json(200, """{"data":{"reportLocation":{"locale":{"name":"Nearby"},"nearbyVenues":[{"id":"v-1","distance":0.4}]}}}""")
        }
        val (client, _) = makeClient(stub)
        val here = Coordinates(latitude = 37.77, longitude = -122.42)

        val response = client.graphQL<ReportLocationResponse>(
            Queries.reportLocation("locale { name } nearbyVenues { id distance }"),
            variables = graphQLVariables("position" to here),
        )

        assertEquals("Nearby", response.reportLocation.locale?.name)
        assertEquals(0.4, response.reportLocation.nearbyVenues!!.single().distance)
        val body = stub.requests.single().jsonBody()
        assertTrue(body.string("query")!!.contains("{ locale { name } nearbyVenues { id distance } }"))
        assertEquals(here.toGraphQLValue(), body["variables"]!!.jsonObject["position"])
    }
}

class AudienceResolutionTest {
    @Test
    fun usesTheAudienceTheSignInNamed() = runTest {
        val stub = StubTransport { StubTransport.json(200, """{"data":{"venues":{"list":{"nodes":[]}}}}""") }
        val (client, store) = makeClient(stub, audienceId = null, token = "session-token")
        store.saveAudienceId("from-sign-in")

        client.venues()

        assertEquals(listOf("/v1/audience/from-sign-in/graphql"), stub.requests.map { it.path })
    }

    @Test
    fun signingInNamesTheAudienceWithoutDecodingTheToken() = runTest {
        val stub = StubTransport { request ->
            if (request.path == "/v1/token") {
                StubTransport.json(
                    200,
                    """{"token":"${makeJwt(mapOf("id" to "u-1", "audience_id" to "from-claims"))}","userId":"u-1",
                     "audienceId":"from-json","role":"member","endpoint":"https://api.audiencekit.test/v1/audience/from-json/graphql"}""",
                )
            } else {
                StubTransport.json(200, """{"data":{"venues":{"list":{"nodes":[]}}}}""")
            }
        }
        val (client, store) = makeClient(stub, audienceId = null, token = null)

        client.signIn("fb-token", device)
        client.venues()

        assertEquals("from-json", store.loadAudienceId())
        assertEquals("/v1/audience/from-json/graphql", stub.requests.last().path)
    }

    @Test
    fun looksUpTheHostsAudienceForAPlatformSession() = runTest {
        val stub = StubTransport { request ->
            if (request.path == "/v1/branding") {
                StubTransport.json(
                    200,
                    """{"audience":{"id":"from-branding","name":"Hot Mess","subdomain":"hotmess"},
                     "facebook_app_id":"713525445368431","theme":{"preset":"hot_mess","tagline":null,"light":{},"dark":{}}}""",
                )
            } else {
                StubTransport.json(200, """{"data":{"venues":{"list":{"nodes":[]}}}}""")
            }
        }
        val (client, _) = makeClient(stub, audienceId = null, token = makeJwt(mapOf("id" to "u-1")))

        client.venues()
        client.venues()

        assertEquals(
            listOf("/v1/branding", "/v1/audience/from-branding/graphql", "/v1/audience/from-branding/graphql"),
            stub.requests.map { it.path },
        )
    }

    @Test
    fun needsAnAudienceOrAHost() = runTest {
        val stub = StubTransport { StubTransport.json(200, "{}") }
        val (client, _) = makeClient(stub, host = null, audienceId = null, token = "not-a-jwt")

        assertFailsWith<AudienceKitException.MissingConfiguration> { client.venues() }
        assertTrue(stub.requests.isEmpty())
    }
}

class BrandingTest {
    @Test
    fun fetchesBrandingWithoutASession() = runTest {
        val stub = StubTransport {
            StubTransport.json(
                200,
                """{"audience":{"id":"a-1","name":"Hot Mess","subdomain":"hotmess"},
                 "facebook_app_id":"713525445368431","facebook_login_config_id":"4085560021745660",
                 "theme":{"preset":"hot_mess","tagline":"Queer nights out","light":{"accent":"#9c1c62"},"dark":{}}}""",
            )
        }
        val (client, _) = makeClient(stub, token = null)

        val branding = client.branding()

        val request = stub.requests.single()
        assertEquals("GET", request.method)
        assertEquals("host=hotmess.admin.audiencekit.com", request.query)
        assertNull(request.header("Authorization"))

        assertEquals("Hot Mess", branding.audience.name)
        assertEquals("713525445368431", branding.facebookAppId)
        assertEquals("4085560021745660", branding.facebookLoginConfigId)
        assertEquals("hot_mess", branding.theme.preset)
        assertEquals(RGBAColor.fromHex("#9c1c62"), branding.theme.color("accent"))
        assertEquals(RGBAColor.fromHex("#9c1c62"), branding.theme.color("accent", dark = true))
        assertNull(branding.theme.color("missing"))
    }

    @Test
    fun anUnknownHostIsNotFound() = runTest {
        val stub = StubTransport { StubTransport.json(404, "{}") }
        val (client, _) = makeClient(stub, token = null)

        assertFailsWith<AudienceKitException.NotFound> { client.branding(host = "nobody.example") }
        assertEquals("host=nobody.example", stub.requests.single().query)
    }

    @Test
    fun toleratesAMissingTheme() {
        val json = """{"audience":{"id":"a","name":"A","subdomain":"a"},"facebook_app_id":null,"theme":{}}"""
        val branding = AudienceKitClient.json.decodeFromString(Branding.serializer(), json)
        assertEquals("default", branding.theme.preset)
        assertTrue(branding.theme.light.isEmpty())
    }
}

class ValuesTest {
    @Test
    fun parsesHexColors() {
        assertEquals(RGBAColor(1.0, 0.0, 0.0), RGBAColor.fromHex("#ff0000"))
        assertEquals(RGBAColor(0.0, 1.0, 0.0), RGBAColor.fromHex("0f0"))
        assertEquals(0x80 / 255.0, RGBAColor.fromHex("#0000ff80")?.alpha)
        assertNull(RGBAColor.fromHex("nope"))
        assertEquals(0xFF9C1C62.toInt(), RGBAColor.fromHex("#9c1c62")?.toArgb())
        assertEquals(0x800000FF.toInt(), RGBAColor.fromHex("#0000ff80")?.toArgb())
    }

    @Test
    fun carriesDesignTokens() {
        assertEquals(RGBAColor.fromHex("#b8236f"), DesignTokens.hotMess.accent)
        assertEquals(RGBAColor.fromHex("#ff7ab6"), DesignTokens.hotMessDark.accent)
        assertEquals(DesignTokens.hotMessDark, DesignTokens.presets["hot_mess"]?.dark)
        assertEquals(DesignTokens.light, DesignTokens.presets["default"]?.light)
        assertEquals(0x8C1C141A.toInt(), DesignTokens.hotMess.glass.toArgb())
        assertEquals(16f, DesignTokens.Spacing.s4)
    }

    @Test
    fun parsesWktPoints() {
        assertEquals(Coordinate(latitude = 37.25, longitude = -122.5), Coordinate.fromWkt("POINT (-122.5 37.25)"))
        assertEquals(Coordinate(latitude = 2.0, longitude = 1.0), Coordinate.fromWkt("SRID=4326;POINT(1 2)"))
        assertNull(Coordinate.fromWkt("POLYGON ((0 0, 1 1))"))
        assertNull(Coordinate.fromWkt(""))
    }

    @Test
    fun convertsGraphQLVariables() {
        val variables = graphQLVariables("id" to "v-1", "limit" to 10, "state" to RSVPState.MAYBE, "ids" to listOf("a", null))
        assertEquals(JsonPrimitive("v-1"), variables["id"])
        assertEquals(JsonPrimitive(10), variables["limit"])
        assertEquals(JsonPrimitive("MAYBE"), variables["state"])
        assertEquals(JsonArray(listOf(JsonPrimitive("a"), kotlinx.serialization.json.JsonNull)), variables["ids"])
        assertFailsWith<IllegalArgumentException> { graphQLValueOf(Any()) }
    }

    @Test
    fun inMemoryStoreRoundTrips() {
        val store = InMemoryTokenStore()
        assertNull(store.loadToken())
        store.saveToken("t")
        assertEquals("t", store.loadToken())
        store.deleteToken()
        assertNull(store.loadToken())
    }
}

private const val ADMISSION_JSON =
    """{"id":"7b4e0c6a-1d2f-4e8a-9c3b-5f6a7b8c9d0e","status":"PAID","night":"2026-10-09",
    "amount":{"cents":1000,"currency":"usd"},"fee":{"cents":50,"currency":"usd"},"total":{"cents":1112,"currency":"usd"},
    "isRefundable":true,"scanCount":0,"checkedInAt":null,
    "passSecret":"AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=",
    "profile":{"id":"u-alex","name":"Alex","avatarUrl":"https://cdn.example/alex.jpg"},"venue":{"id":"v-1","name":"The Wildrose","photoUrl":null},
    "event":null}"""

class CoverChargeTest {
    @Test
    fun readsAVenuesCoverAndTheViewersPass() = runTest {
        val stub = StubTransport {
            StubTransport.json(
                200,
                """{"data":{"venues":{"venue":{"id":"v-1","name":"The Wildrose","tickets":{"cover":{
                 "charge":{"amount":{"cents":1000,"currency":"usd"},"total":{"cents":1112,"currency":"usd"},
                 "fee":{"cents":50,"currency":"usd"},"night":"2026-10-09",
                 "from":"21:00","payable":true,"event":{"id":"e-1","name":"Drag Bingo"}},
                 "viewerAdmission":$ADMISSION_JSON}}}}}}""",
            )
        }
        val (client, _) = makeClient(stub)

        val cover = client.venueCover("v-1")!!

        assertEquals(Money.usd(1112), cover.coverCharge?.total)
        assertEquals("21:00", cover.coverCharge?.from)
        assertTrue(cover.coverCharge!!.payable)
        assertEquals(CoverEvent("e-1", "Drag Bingo"), cover.coverCharge?.event)
        assertEquals(AdmissionStatus.PAID, cover.viewerAdmission?.status)
        assertEquals("The Wildrose", cover.viewerAdmission?.venue?.name)
        val body = stub.requests.single().jsonBody()
        assertEquals("VenueCover", body.string("operationName"))
        assertEquals("v-1", body["variables"]!!.jsonObject.string("id"))
    }

    @Test
    fun buysCover() = runTest {
        val stub = StubTransport {
            StubTransport.json(
                200,
                """{"data":{"buyCover":{"admission":${ADMISSION_JSON.replace("\"PAID\"", "\"PENDING\"")},
                 "paymentIntentClientSecret":"pi_1_secret_2","publishableKey":"pk_test_1","stripeAccountId":"acct_1"}}}""",
            )
        }
        val (client, _) = makeClient(stub)

        val purchase = client.buyCover(venueId = "v-1")

        assertEquals("pi_1_secret_2", purchase.paymentIntentClientSecret)
        assertEquals("pk_test_1", purchase.publishableKey)
        assertEquals("acct_1", purchase.stripeAccountId)
        assertEquals(AdmissionStatus.PENDING, purchase.admission.status)
        assertFalse(purchase.isPaid)
        val body = stub.requests.single().jsonBody()
        assertEquals("BuyCover", body.string("operationName"))
        assertEquals("v-1", body["variables"]!!.jsonObject.string("venueId"))
    }

    @Test
    fun paysSquareCoverWithAToken() = runTest {
        val stub = StubTransport { request ->
            if (request.jsonBody().string("operationName") == "BuyCover") {
                StubTransport.json(
                    200,
                    """{"data":{"buyCover":{"admission":${ADMISSION_JSON.replace("\"PAID\"", "\"PENDING\"")},
                     "provider":"SQUARE","paymentIntentClientSecret":null,"publishableKey":null,"stripeAccountId":null,
                     "squareApplicationId":"sq0idp-1","squareLocationId":"L1"}}}""",
                )
            } else {
                StubTransport.json(200, """{"data":{"payCover":{"admission":$ADMISSION_JSON}}}""")
            }
        }
        val (client, _) = makeClient(stub)

        val purchase = client.buyCover(venueId = "v-1")
        assertTrue(purchase.isSquare)
        assertFalse(purchase.isPaid)
        assertEquals("sq0idp-1", purchase.squareApplicationId)
        assertEquals("L1", purchase.squareLocationId)

        val admission = client.payCover(admissionId = purchase.admission.id, sourceId = "cnon:ok")
        assertEquals(AdmissionStatus.PAID, admission.status)
        val variables = stub.requests.last().jsonBody()["variables"]!!.jsonObject
        assertEquals("cnon:ok", variables.string("sourceId"))
    }

    @Test
    fun anAlreadyPaidCoverHasNothingToPay() = runTest {
        val stub = StubTransport {
            StubTransport.json(
                200,
                """{"data":{"buyCover":{"admission":$ADMISSION_JSON,"paymentIntentClientSecret":null,
                 "publishableKey":"pk_test_1","stripeAccountId":"acct_1"}}}""",
            )
        }
        val (client, _) = makeClient(stub)

        assertTrue(client.buyCover(venueId = "v-1").isPaid)
    }

    @Test
    fun confirmsAndRefundsCover() = runTest {
        val stub = StubTransport { request ->
            val name = request.jsonBody().string("operationName")
            val admission = if (name == "RefundAdmission") ADMISSION_JSON.replace("\"PAID\"", "\"REFUNDED\"") else ADMISSION_JSON
            val field = if (name == "RefundAdmission") "refundAdmission" else "confirmCover"
            StubTransport.json(200, """{"data":{"$field":{"admission":$admission}}}""")
        }
        val (client, _) = makeClient(stub)

        assertEquals(AdmissionStatus.PAID, client.confirmCover("a-1").status)
        assertEquals(AdmissionStatus.REFUNDED, client.refundAdmission("a-1").status)
        assertEquals(listOf("ConfirmCover", "RefundAdmission"), stub.requests.map { it.jsonBody().string("operationName") })
        assertEquals(listOf("a-1", "a-1"), stub.requests.map { it.jsonBody()["variables"]!!.jsonObject.string("admissionId") })
    }

    @Test
    fun listsTheViewersPasses() = runTest {
        val stub = StubTransport { StubTransport.json(200, """{"data":{"me":{"cover":{"admissions":{"nodes":[$ADMISSION_JSON]}}}}}""") }
        val (client, _) = makeClient(stub)

        val admission = client.admissions().single()

        assertEquals(Profile("u-alex", "Alex", "https://cdn.example/alex.jpg"), admission.profile)
        assertTrue(admission.isPaid)
        assertTrue(admission.isRefundable)
        assertEquals("HMC1.7b4e0c6a-1d2f-4e8a-9c3b-5f6a7b8c9d0e.59713440.NQh13_EnQAdAX6cE", admission.passCode(1_791_403_200))
    }

    @Test
    fun readsStatusesFromANewerApiAsUnknown() {
        val admission = AudienceKitClient.json.decodeFromString(
            Admission.serializer(),
            ADMISSION_JSON.replace("\"PAID\"", "\"HELD\""),
        )
        assertEquals(AdmissionStatus.UNKNOWN, admission.status)
    }
}

class CoverPassTest {
    // Computed with the API's CoverPass (Ruby): window 1791403200 / 30, HMAC-SHA256 keyed with bytes 0..31.
    private val id = "7b4e0c6a-1d2f-4e8a-9c3b-5f6a7b8c9d0e"
    private val secret = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8="

    @Test
    fun matchesTheApisCode() {
        assertEquals("HMC1.$id.59713440.NQh13_EnQAdAX6cE", CoverPass.code(id, secret, 1_791_403_200))
        assertEquals("HMC1.$id.59713440.NQh13_EnQAdAX6cE", CoverPass.code(id, secret, 1_791_403_229))
        assertEquals("HMC1.$id.59713441.fLqBsZEABOJedMNz", CoverPass.code(id, secret, 1_791_403_230))
    }

    @Test
    fun changesEveryThirtySeconds() {
        assertEquals(59_713_440, CoverPass.window(1_791_403_200))
        assertEquals(30, CoverPass.secondsUntilNextWindow(1_791_403_200))
        assertEquals(1, CoverPass.secondsUntilNextWindow(1_791_403_229))
    }

    @Test
    fun recognisesPassCodes() {
        assertTrue(CoverPass.isPassCode(CoverPass.code(id, secret, 1_791_403_200)))
        assertFalse(CoverPass.isPassCode("https://hotmess.social/venues/1"))
        assertFalse(CoverPass.isPassCode("HMC1.$id.soon.sig"))
    }

    @Test
    fun needsABase64Secret() {
        assertFailsWith<IllegalArgumentException> { CoverPass.code(id, "not base64!", 0) }
    }
}
