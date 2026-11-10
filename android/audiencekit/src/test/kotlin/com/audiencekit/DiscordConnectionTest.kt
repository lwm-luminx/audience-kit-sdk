package com.audiencekit

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonPrimitive
import java.net.URI
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class DiscordConnectionTest {
    private val device = DeviceDescription(identifier = "device-1", model = "Google Pixel 9", version = "2.0", build = "42")
    private val token = """{"token":"jwt-connected","userId":"u-2","audienceId":"b0f8b66a-e636-495d-9475-0f5317ea08e1",""" +
        """"role":"member","endpoint":"https://api.audiencekit.test/graphql"}"""

    private fun client(stub: StubTransport, token: String? = "jwt-apple"): Pair<AudienceKitClient, InMemoryTokenStore> {
        val store = InMemoryTokenStore(token)
        val configuration = AudienceKitConfiguration(
            baseUrl = StubTransport.BASE_URL,
            host = "hackdiffe.rent",
            audienceId = "b0f8b66a-e636-495d-9475-0f5317ea08e1",
        )
        return AudienceKitClient(configuration, store, stub) to store
    }

    @Test
    fun startsOnTheApiWithTheVerifiersHash() {
        val connection = DiscordConnection("https://api.audiencekit.test/", "rent.hackdiffe.app", verifier = "v-1")
        val url = URI(connection.authorizationUrl())

        assertEquals("api.audiencekit.test", url.host)
        assertEquals("/v1/token/discord/authorize", url.path)
        val query = url.query.split("&").associate { it.substringBefore("=") to it.substringAfter("=") }
        assertEquals("android", query["platform"])
        assertEquals("rent.hackdiffe.app", query["app"])
        assertEquals(AppleWebSignIn.sha256Hex("v-1"), query["challenge"])
        assertEquals(64, DiscordConnection("https://x", "a.b").verifier.length)
    }

    @Test
    fun readsTheHandBack() {
        val connection = DiscordConnection("https://api.audiencekit.test", "rent.hackdiffe.app")
        assertEquals(DiscordConnection.Result.Ticket("t 1"), connection.result("audiencekit-discord://callback?ticket=t%201"))
        assertEquals(DiscordConnection.Result.Cancelled, connection.result("audiencekit-discord://callback?error=access_denied"))
        assertEquals(
            DiscordConnection.Result.Failed("Nope"),
            connection.result("audiencekit-discord://callback?error=sign_in_failed&error_description=Nope"),
        )
        assertEquals(DiscordConnection.Result.Failed(DiscordConnection.FAILED), connection.result("audiencekit-discord://callback"))
        assertEquals(DiscordConnection.Result.Failed(DiscordConnection.FAILED), connection.result("https://evil.example/?ticket=t"))
        assertTrue(connection.isCallback("audiencekit-discord://callback?ticket=t"))
        assertFalse(connection.isCallback("audiencekit-apple://callback?ticket=t"))
    }

    @Test
    fun connectsDiscordToTheSignedInAccount() = runTest {
        val stub = StubTransport { StubTransport.json(200, token) }
        val (client, store) = client(stub)
        val connection = DiscordConnection(StubTransport.BASE_URL, "rent.hackdiffe.app", verifier = "v-1")

        val result = client.connectDiscord(DiscordConnection.Result.Ticket("t-1"), connection, device)

        assertEquals("u-2", result?.userId)
        assertEquals("jwt-connected", store.loadToken())
        val request = stub.requests.single()
        assertEquals("/v1/token/discord", request.path)
        assertEquals("Bearer jwt-apple", request.header("Authorization"))
        val body = request.jsonBody()
        assertEquals("t-1", body["ticket"]!!.jsonPrimitive.content)
        assertEquals("v-1", body["verifier"]!!.jsonPrimitive.content)
        assertEquals("hackdiffe.rent", body["host"]!!.jsonPrimitive.content)
        assertTrue(body["connect"]!!.jsonPrimitive.boolean)
    }

    @Test
    fun aCancelledOrFailedConnectionSendsNothing() = runTest {
        val stub = StubTransport { StubTransport.json(500, "{}") }
        val (client, store) = client(stub)
        val connection = DiscordConnection(StubTransport.BASE_URL, "rent.hackdiffe.app")

        assertNull(client.connectDiscord(DiscordConnection.Result.Cancelled, connection, device))
        val failed = assertFailsWith<AudienceKitException.SignInFailed> {
            client.connectDiscord(DiscordConnection.Result.Failed("Discord said no"), connection, device)
        }
        assertEquals("Discord said no", failed.faultMessage)
        assertTrue(stub.requests.isEmpty())
        assertEquals("jwt-apple", store.loadToken())
    }

    @Test
    fun aRefusedConnectionKeepsTheSession() = runTest {
        val stub = StubTransport {
            StubTransport.json(400, """{"error":"INVALID","message":"This account already has a different Discord account"}""")
        }
        val (client, store) = client(stub)

        val refused = assertFailsWith<AudienceKitException.SignInFailed> { client.connectDiscord("t-1", "v-1", device) }
        assertEquals("This account already has a different Discord account", refused.faultMessage)
        assertEquals("jwt-apple", store.loadToken())
    }

    @Test
    fun connectingNeedsASession() = runTest {
        val (client, _) = client(StubTransport { StubTransport.json(200, token) }, token = null)
        assertFailsWith<AudienceKitException.NotSignedIn> { client.connectDiscord("t-1", "v-1", device) }
    }

    @Test
    fun readsTheConnectedDiscord() = runTest {
        val connected = StubTransport {
            StubTransport.json(200, """{"data":{"me":{"self":{"signedInWithDiscord":true,"discordUsername":"nelly"}}}}""")
        }
        val (client, _) = client(connected)
        assertEquals(ConnectedDiscord("nelly"), client.connectedDiscord())
        assertEquals("ConnectedDiscord", (connected.requests.single().jsonBody()["operationName"] as JsonPrimitive).content)

        val none = StubTransport {
            StubTransport.json(200, """{"data":{"me":{"self":{"signedInWithDiscord":false,"discordUsername":null}}}}""")
        }
        assertNull(client(none).first.connectedDiscord())

        val older = StubTransport {
            StubTransport.json(200, """{"errors":[{"message":"Field 'signedInWithDiscord' doesn't exist","extensions":{"code":"undefinedField"}}]}""")
        }
        assertNull(client(older).first.connectedDiscord())
    }
}
