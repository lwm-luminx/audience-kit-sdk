package com.audiencekit

import com.sun.net.httpserver.HttpServer
import kotlinx.coroutines.test.runTest
import java.net.InetSocketAddress
import java.net.ServerSocket
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

/** The default transport against a real local HTTP server. */
class UrlConnectionTransportTest {
    private val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0).apply {
        createContext("/v1/audience/a-1/graphql") { exchange ->
            val sentBody = exchange.requestBody.readBytes().toString(Charsets.UTF_8)
            val reply = if (exchange.requestHeaders.getFirst("Authorization") == "Bearer good" && sentBody.contains("Me")) {
                """{"data":{"me":{"self":{"id":"u-1","name":"Rick"}}}}"""
            } else {
                "{}"
            }
            val status = if (reply == "{}") 401 else 200
            exchange.sendResponseHeaders(status, reply.length.toLong())
            exchange.responseBody.use { it.write(reply.toByteArray()) }
        }
        start()
    }

    private val baseUrl = "http://127.0.0.1:${server.address.port}"

    @AfterTest
    fun stop() = server.stop(0)

    private fun client(token: String, baseUrl: String = this.baseUrl) = AudienceKitClient(
        AudienceKitConfiguration(baseUrl = baseUrl, audienceId = "a-1"),
        InMemoryTokenStore(token),
    )

    @Test
    fun postsAndReadsTheResponse() = runTest {
        assertEquals(SelfUser(id = "u-1", name = "Rick"), client("good").me())
    }

    @Test
    fun readsErrorStatuses() = runTest {
        val client = client("revoked")
        assertFailsWith<AudienceKitException.Unauthorized> { client.me() }
        assertEquals(false, client.isSignedIn)
    }

    @Test
    fun aRefusedConnectionIsANetworkError() = runTest {
        val closedPort = ServerSocket(0).use { it.localPort }
        assertFailsWith<AudienceKitException.Network> { client("good", "http://127.0.0.1:$closedPort").me() }
    }
}
