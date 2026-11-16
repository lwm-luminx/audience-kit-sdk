package com.audiencekit

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class PrivateChatsTest {
    private fun client(stub: StubTransport) = AudienceKitClient(
        AudienceKitConfiguration(baseUrl = StubTransport.BASE_URL, audienceId = "b0f8b66a-e636-495d-9475-0f5317ea08e1"),
        InMemoryTokenStore("session-token"),
        stub,
    )

    private val line = """{"id":"ping-1.a","chatId":"ping-1","body":"Door at 10?","isMine":true,""" +
        """"sentAt":"2026-11-16T05:00:00Z","sender":{"id":"u1","name":"Bo Peep"}}"""

    @Test
    fun sendingALineNamesTheChat() = runTest {
        val stub = StubTransport {
            StubTransport.Reply.Json(200, """{"data":{"sendPrivateChatMessage":{"message":$line}}}""")
        }

        val message = client(stub).sendPrivateChatMessage("Door at 10?", "ping-1")

        assertEquals(PrivateChatMessage("ping-1.a", "ping-1", "Door at 10?", true, PrivateChatMessage.Sender("u1", "Bo Peep"),
            "2026-11-16T05:00:00Z"), message)
        val body = stub.requests[0].jsonBody()
        assertEquals("SendPrivateChatMessage", (body["operationName"] as JsonPrimitive).content)
        assertEquals("ping-1", body["variables"]!!.jsonObject["chatId"]!!.jsonPrimitive.content)
    }

    @Test
    fun aPingChatComesFromItsNode() = runTest {
        val stub = StubTransport {
            StubTransport.Reply.Json(200,
                """{"data":{"node":{"id":"1","chat":{"id":"ping-1","closesAt":"2026-11-16T12:00:00Z","messages":[$line]}}}}""")
        }

        val chat = client(stub).pingChat("1")!!

        assertTrue(chat.isPing)
        assertEquals(listOf("Door at 10?"), chat.messages.map { it.body })
    }

    @Test
    fun eventsDecodeLinesAndClosing() {
        fun event(text: String) = PrivateChatEvent.decode(Json.parseToJsonElement(text) as JsonObject)

        assertEquals("Door at 10?",
            (event("""{"chatId":"ping-1","closed":false,"message":$line}""") as PrivateChatEvent.Message).message.body)
        assertEquals(PrivateChatEvent.Closed("ping-1"), event("""{"chatId":"ping-1","closed":true,"message":null}"""))
        assertNull(event("""{"closed":true}"""))
    }
}
