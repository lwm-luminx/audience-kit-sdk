package com.audiencekit

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ModerationTest {
    private fun client(stub: StubTransport) = AudienceKitClient(
        AudienceKitConfiguration(baseUrl = StubTransport.BASE_URL, audienceId = "b0f8b66a-e636-495d-9475-0f5317ea08e1"),
        InMemoryTokenStore("session-token"),
        stub,
    )

    @Test
    fun reportingAMessageSendsItsFrameAndCanBlock() = runTest {
        val stub = StubTransport {
            StubTransport.Reply.Json(200, """{"data":{"reportContent":{"reported":true,"blocked":true}}}""")
        }

        val result = client(stub).reportContent(ReportTarget.MESSAGE, "frame-1", reason = "Spam", block = true)

        assertEquals(ReportResult(reported = true, blocked = true), result)
        val body = stub.requests[0].jsonBody()
        assertEquals("ReportContent", (body["operationName"] as JsonPrimitive).content)
        val variables = body["variables"]!!.jsonObject
        assertEquals("MESSAGE", variables["targetType"]!!.jsonPrimitive.content)
        assertEquals("frame-1", variables["targetId"]!!.jsonPrimitive.content)
        assertEquals("Spam", variables["reason"]!!.jsonPrimitive.content)
        assertTrue(variables["block"]!!.jsonPrimitive.boolean)
    }

    @Test
    fun aReportWithoutAReasonSendsNull() = runTest {
        val stub = StubTransport {
            StubTransport.Reply.Json(200, """{"data":{"reportContent":{"reported":true,"blocked":false}}}""")
        }

        val result = client(stub).reportContent(ReportTarget.PERSON, "user-2")

        assertTrue(result.reported)
        assertFalse(result.blocked)
        val variables = stub.requests[0].jsonBody()["variables"]!!.jsonObject
        assertEquals(JsonNull, variables["reason"])
        assertFalse(variables["block"]!!.jsonPrimitive.boolean)
    }

    @Test
    fun aMissingPayloadIsNotReported() = runTest {
        val stub = StubTransport { StubTransport.Reply.Json(200, """{"data":{"reportContent":null}}""") }

        assertEquals(ReportResult(), client(stub).reportContent(ReportTarget.MESSAGE, "frame-1"))
    }

    @Test
    fun blockingAndUnblockingSendTheUserId() = runTest {
        val stub = StubTransport { request ->
            val name = (request.jsonBody()["operationName"] as JsonPrimitive).content
            val field = if (name == "BlockUser") "blockUser" else "unblockUser"
            StubTransport.Reply.Json(200, """{"data":{"$field":{"blockedUsers":[{"id":"user-2"}]}}}""")
        }
        val client = client(stub)

        client.blockUser("user-2")
        client.unblockUser("user-2")

        assertEquals(listOf("BlockUser", "UnblockUser"), stub.requests.map { (it.jsonBody()["operationName"] as JsonPrimitive).content })
        assertEquals("user-2", stub.requests[1].jsonBody()["variables"]!!.jsonObject["userId"]!!.jsonPrimitive.content)
    }

    @Test
    fun aFailedBlockThrows() = runTest {
        val stub = StubTransport {
            StubTransport.Reply.Json(200, """{"data":{"blockUser":null},"errors":[{"message":"nope"}]}""")
        }

        assertFailsWith<AudienceKitException.GraphQL> { client(stub).blockUser("user-2") }
    }

    @Test
    fun theCopyOffersReasons() {
        assertTrue(ReportCopy.REASONS.contains("Spam"))
    }
}
