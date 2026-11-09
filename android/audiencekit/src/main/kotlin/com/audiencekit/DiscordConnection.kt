package com.audiencekit

import java.net.URI
import java.net.URLDecoder
import java.net.URLEncoder
import java.security.SecureRandom

/**
 * Connecting a Discord account to the signed-in one, for someone who signed in another way (Sign in with Apple, say),
 * so the audience's Discord bridge knows them as the same person and can show them its channels.
 *
 * Discord's OAuth needs the API's client secret, so the API runs it and the app only ever holds a short-lived ticket
 * bound to a [verifier] that never goes through the browser:
 *
 * 1. Open [authorizationUrl] in a Custom Tab.
 * 2. The API hands the answer back on an intent for [CALLBACK_SCHEME]`://`[CALLBACK_HOST] naming [packageName]; declare
 *    that scheme and host on the activity that takes it and pass the URL it gets to [result].
 * 3. Connect with [AudienceKitClient.connectDiscord].
 *
 * The app must be listed in the audience's console (Apps). [verifier] must survive until the answer comes back; keep
 * it (e.g. in preferences) when the app may be stopped meanwhile, and rebuild this with it.
 */
public class DiscordConnection(
    /** The API the session belongs to, e.g. [AudienceKitConfiguration.baseUrl]. */
    public val baseUrl: String,
    /** The app's package, which the API sends the answer back to. */
    public val packageName: String,
    public val verifier: String = random(),
) {
    /** What came back from the API. */
    public sealed interface Result {
        /** Discord said who they are; hand this to [AudienceKitClient.connectDiscord]. */
        public data class Ticket(val ticket: String) : Result

        /** They cancelled on Discord's page. */
        public data object Cancelled : Result

        public data class Failed(val reason: String) : Result
    }

    /** The API's page that starts Discord's sign-in, for a Custom Tab. */
    public fun authorizationUrl(): String {
        val query = listOf("platform" to "android", "app" to packageName, "challenge" to AppleWebSignIn.sha256Hex(verifier))
            .joinToString("&") { (key, value) -> "$key=${encode(value)}" }
        return "${baseUrl.trimEnd('/')}$AUTHORIZE_PATH?$query"
    }

    /** Whether [url] is the API handing back a Discord connection. */
    public fun isCallback(url: String): Boolean = isCallbackUrl(url)

    /** Reads the API's hand-back. */
    public fun result(url: String): Result {
        if (!isCallbackUrl(url)) return Result.Failed(FAILED)
        val parameters = runCatching { URI(url).rawQuery }.getOrNull().orEmpty()
            .split("&").filter { it.isNotEmpty() }
            .associate { pair -> pair.split("=", limit = 2).let { decode(it[0]) to decode(it.getOrElse(1) { "" }) } }
            .filterValues { it.isNotBlank() }
        parameters["ticket"]?.let { return Result.Ticket(it) }
        return when (parameters["error"]) {
            "access_denied" -> Result.Cancelled
            else -> Result.Failed(parameters["error_description"] ?: FAILED)
        }
    }

    public companion object {
        /** The scheme and host the API hands the answer back on; declare them on the activity that takes it. */
        public const val CALLBACK_SCHEME: String = "audiencekit-discord"
        public const val CALLBACK_HOST: String = "callback"
        public const val AUTHORIZE_PATH: String = "/v1/token/discord/authorize"
        internal const val FAILED = "Discord didn't connect. Try again."

        /** Whether [url] is the API handing back a Discord connection, before knowing which one. */
        public fun isCallbackUrl(url: String): Boolean = runCatching {
            val uri = URI(url)
            uri.scheme == CALLBACK_SCHEME && uri.host == CALLBACK_HOST
        }.getOrDefault(false)

        private fun random(): String {
            val bytes = ByteArray(32).also { SecureRandom().nextBytes(it) }
            return bytes.joinToString("") { "%02x".format(it) }
        }

        private fun encode(value: String) = URLEncoder.encode(value, Charsets.UTF_8.name()).replace("+", "%20")

        private fun decode(value: String) = URLDecoder.decode(value, Charsets.UTF_8.name())
    }
}

/** The Discord account connected to the signed-in one; [username] as of the last time they signed in or connected. */
public data class ConnectedDiscord(val username: String?)

/** Words shared with iOS's ConnectDiscordButton, so both apps say the same thing. */
public object ConnectDiscordCopy {
    public const val CONNECT: String = "Connect Discord"
    public const val CONNECTED_LABEL: String = "Discord"
    public const val CONNECTED: String = "Connected"
    public const val FAILED_TITLE: String = "Couldn't connect Discord"
    public const val EXPLANATION: String = "Connect your Discord account to see the community's Discord channels " +
        "here as yourself. We only learn your Discord name; nothing is posted for you."
}
