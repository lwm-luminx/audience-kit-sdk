package com.audiencekit

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.runInterruptible
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/** An HTTP request as the client hands it to an [HttpTransport]. */
public class HttpRequest(
    public val method: String,
    public val url: String,
    public val headers: Map<String, String>,
    public val body: ByteArray?,
)

/** What an [HttpTransport] got back. */
public class HttpResponse(
    public val status: Int,
    public val body: ByteArray,
)

/**
 * Sends the client's HTTP requests. The default, [UrlConnectionTransport], needs no dependencies;
 * implement this to route the SDK through an app's own OkHttp client, or to stub it in tests.
 *
 * Throw an [IOException] when there's no response; any status code is a response.
 */
public fun interface HttpTransport {
    public suspend fun execute(request: HttpRequest): HttpResponse
}

/** An [HttpTransport] over [HttpURLConnection], which the JVM and Android both have. */
public class UrlConnectionTransport(
    private val connectTimeoutMillis: Int = 15_000,
    private val readTimeoutMillis: Int = 30_000,
) : HttpTransport {
    override suspend fun execute(request: HttpRequest): HttpResponse = coroutineScope {
        val connection = URL(request.url).openConnection() as HttpURLConnection
        // Blocking reads don't notice coroutine cancellation; closing the connection unblocks them.
        val cancelWatcher = launch {
            try {
                awaitCancellation()
            } finally {
                connection.disconnect()
            }
        }
        try {
            runInterruptible(Dispatchers.IO) { connection.exchange(request) }
        } finally {
            cancelWatcher.cancel()
        }
    }

    private fun HttpURLConnection.exchange(request: HttpRequest): HttpResponse {
        requestMethod = request.method
        connectTimeout = connectTimeoutMillis
        readTimeout = readTimeoutMillis
        useCaches = false
        instanceFollowRedirects = true
        request.headers.forEach { (name, value) -> setRequestProperty(name, value) }

        request.body?.let { body ->
            doOutput = true
            setFixedLengthStreamingMode(body.size)
            outputStream.use { it.write(body) }
        }

        val status = responseCode
        val stream = if (status >= 400) errorStream else inputStream
        val body = stream?.use { it.readBytes() } ?: ByteArray(0)
        return HttpResponse(status, body)
    }
}
