package com.audiencekit

import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class DeleteAccountTest {
    private fun client(stub: StubTransport): Pair<AudienceKitClient, InMemoryTokenStore> {
        val store = InMemoryTokenStore("session-token")
        val client = AudienceKitClient(
            AudienceKitConfiguration(baseUrl = StubTransport.BASE_URL, audienceId = "b0f8b66a-e636-495d-9475-0f5317ea08e1"),
            store,
            stub,
        )
        return client to store
    }

    @Test
    fun deletingTheAccountConfirmsAndSignsOutOnThisDevice() = runTest {
        val stub = StubTransport { StubTransport.Reply.Json(200, """{"data":{"deleteAccount":{"deleted":true}}}""") }
        val (client, store) = client(stub)

        assertTrue(client.deleteAccount())

        assertNull(store.loadToken())
        assertEquals(SessionEvent.SIGNED_OUT, client.sessionEvents.first())
        val body = stub.requests[0].jsonBody()
        assertEquals("DeleteAccount", (body["operationName"] as JsonPrimitive).content)
        assertTrue(body["variables"]!!.jsonObject["confirm"]!!.jsonPrimitive.boolean)
    }

    @Test
    fun anAccountTheApiKeptStaysSignedIn() = runTest {
        val stub = StubTransport { StubTransport.Reply.Json(200, """{"data":{"deleteAccount":{"deleted":false}}}""") }
        val (client, store) = client(stub)

        assertFalse(client.deleteAccount())
        assertEquals("session-token", store.loadToken())
    }

    @Test
    fun aFailedDeleteThrowsAndKeepsTheSession() = runTest {
        val stub = StubTransport {
            StubTransport.Reply.Json(200, """{"data":{"deleteAccount":null},"errors":[{"message":"nope"}]}""")
        }
        val (client, store) = client(stub)

        assertFailsWith<AudienceKitException.GraphQL> { client.deleteAccount() }
        assertEquals("session-token", store.loadToken())
    }
}
