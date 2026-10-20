package com.audiencekit

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import java.io.IOException
import java.net.URI

/** A recorded request, with helpers for assertions. */
class RecordedRequest(private val request: HttpRequest) {
    val method: String get() = request.method
    val uri: URI = URI(request.url)
    val path: String get() = uri.path
    val query: String? get() = uri.rawQuery

    fun header(name: String): String? = request.headers.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value

    fun jsonBody(): JsonObject = Json.parseToJsonElement(request.body!!.toString(Charsets.UTF_8)).jsonObject
}

/** Answers every request with [respond] and records what was sent, so tests run offline. */
class StubTransport(private val respond: (RecordedRequest) -> Reply) : HttpTransport {
    sealed interface Reply {
        data class Json(val status: Int, val body: String) : Reply
        data class Failure(val error: IOException) : Reply
    }

    val requests = mutableListOf<RecordedRequest>()

    override suspend fun execute(request: HttpRequest): HttpResponse {
        val recorded = RecordedRequest(request)
        requests += recorded
        return when (val reply = respond(recorded)) {
            is Reply.Json -> HttpResponse(reply.status, reply.body.toByteArray())
            is Reply.Failure -> throw reply.error
        }
    }

    companion object {
        const val BASE_URL = "https://api.audiencekit.test"

        fun json(status: Int, body: String): Reply = Reply.Json(status, body)
        fun failure(error: IOException): Reply = Reply.Failure(error)
    }
}

/** An unsigned JWT carrying [claims]. */
fun makeJwt(claims: Map<String, String>): String {
    val encoder = java.util.Base64.getUrlEncoder().withoutPadding()
    fun segment(json: String) = encoder.encodeToString(json.toByteArray())
    val payload = claims.entries.joinToString(",", "{", "}") { (key, value) -> "\"$key\":\"$value\"" }
    return "${segment("""{"alg":"HS256"}""")}.${segment(payload)}.signature"
}
