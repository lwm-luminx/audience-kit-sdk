package com.audiencekit

import java.net.URI
import java.net.URLDecoder
import java.net.URLEncoder
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64

/**
 * Sign in with Apple on Android, which has no Apple sign-in of its own: Apple's web sign-in, opened in a Custom Tab.
 *
 * Open [authorizationUrl] in a Custom Tab. Apple posts the result to the API's return URL ([redirectUri],
 * `<baseUrl>/v1/token/apple/callback`), which hands it to the app on an intent for [CALLBACK_SCHEME]`://`[CALLBACK_HOST]
 * naming the app's package. Declare that scheme and host on the activity that takes it, pass the URL it gets to
 * [result], and sign in with [AudienceKitClient.signInWithApple].
 *
 * [state] and [nonce] must survive until the result comes back; keep them (e.g. in preferences) when the app may be
 * stopped meanwhile, and rebuild this with them. The nonce never leaves the app: Apple gets its SHA-256 and puts that in
 * the identity token, and the API signs in only with the nonce itself, so a token picked up on its way through the
 * browser is no use to anyone else.
 *
 * [servicesId] is a Services ID configured for Sign in with Apple whose return URLs include [redirectUri], and one the
 * API accepts (see the API's doc/TOKENS.md, "Sign in with Apple on Android").
 */
public class AppleWebSignIn(
    public val servicesId: String,
    /** The API's return URL; see [callbackUrl]. */
    public val redirectUri: String,
    /** The app's package, which the API sends the result back to. */
    public val packageName: String,
    public val state: String = "$packageName$STATE_SEPARATOR${random()}",
    public val nonce: String = random(),
) {
    /** What came back from Apple. */
    public sealed interface Result {
        /** The person signed in; hand this to [AudienceKitClient.signInWithApple]. */
        public data class Credential(
            val identityToken: String,
            val authorizationCode: String?,
            /** Apple sends the name the first time someone signs in to the app only. */
            val firstName: String?,
            val lastName: String?,
        ) : Result

        /** The person closed Apple's sign-in. */
        public data object Cancelled : Result

        public data class Failed(val reason: String) : Result
    }

    /** Apple's sign-in page, for a Custom Tab. */
    public fun authorizationUrl(): String {
        val query = listOf(
            "client_id" to servicesId,
            "redirect_uri" to redirectUri,
            "response_type" to "code id_token",
            "response_mode" to "form_post",
            "scope" to "name email",
            "state" to state,
            "nonce" to sha256Hex(nonce),
        ).joinToString("&") { (key, value) -> "$key=${encode(value)}" }
        return "$AUTHORIZE_URL?$query"
    }

    /** Whether [url] is the API handing back an Apple sign-in. */
    public fun isCallback(url: String): Boolean = isCallbackUrl(url)

    /** Reads the API's hand-back. A state that isn't [state] is a sign-in this app didn't start, and fails. */
    public fun result(url: String): Result {
        val parameters = parameters(url) ?: return Result.Failed("That isn't a Sign in with Apple result.")
        if (parameters["state"] != state) return Result.Failed("That Sign in with Apple wasn't started here. Try again.")

        parameters["error"]?.let { error ->
            return if (error == "user_cancelled_authorize") Result.Cancelled else Result.Failed("Apple said: $error")
        }
        val identityToken = parameters["id_token"]?.takeIf { it.isNotBlank() }
            ?: return Result.Failed("Apple didn't send an identity token.")
        return Result.Credential(
            identityToken = identityToken,
            authorizationCode = parameters["code"]?.takeIf { it.isNotBlank() },
            firstName = parameters["first_name"]?.takeIf { it.isNotBlank() },
            lastName = parameters["last_name"]?.takeIf { it.isNotBlank() },
        )
    }

    public companion object {
        public const val AUTHORIZE_URL: String = "https://appleid.apple.com/auth/authorize"

        /** The scheme and host the API hands the result back on; declare them on the activity that takes it. */
        public const val CALLBACK_SCHEME: String = "audiencekit-apple"
        public const val CALLBACK_HOST: String = "callback"

        /** The API's return URL path, which the Services ID must list with the API's host. */
        public const val CALLBACK_PATH: String = "/v1/token/apple/callback"

        private const val STATE_SEPARATOR = "~"

        /** The return URL on the API at [baseUrl], e.g. `https://api.audiencekit.com/v1/token/apple/callback`. */
        public fun callbackUrl(baseUrl: String): String = baseUrl.trimEnd('/') + CALLBACK_PATH

        /** Whether [url] is the API handing back an Apple sign-in, before knowing which one. */
        public fun isCallbackUrl(url: String): Boolean = runCatching {
            val uri = URI(url)
            uri.scheme == CALLBACK_SCHEME && uri.host == CALLBACK_HOST
        }.getOrDefault(false)

        private fun parameters(url: String): Map<String, String>? {
            if (!isCallbackUrl(url)) return null
            val query = runCatching { URI(url).rawQuery }.getOrNull() ?: return emptyMap()
            return query.split("&").filter { it.isNotEmpty() }.associate { pair ->
                val (key, value) = pair.split("=", limit = 2).let { it[0] to it.getOrElse(1) { "" } }
                decode(key) to decode(value)
            }
        }

        private fun random(): String {
            val bytes = ByteArray(32).also { SecureRandom().nextBytes(it) }
            return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
        }

        internal fun sha256Hex(value: String): String =
            MessageDigest.getInstance("SHA-256").digest(value.toByteArray()).joinToString("") { "%02x".format(it) }

        private fun encode(value: String) = URLEncoder.encode(value, Charsets.UTF_8.name()).replace("+", "%20")

        private fun decode(value: String) = URLDecoder.decode(value, Charsets.UTF_8.name())
    }
}
