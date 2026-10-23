package com.audiencekit

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import java.io.IOException

/** Everything an [AudienceKitClient] call can fail with. */
public sealed class AudienceKitException(message: String, cause: Throwable? = null) : Exception(message, cause) {
    /** There is no stored session; sign in first. */
    public class NotSignedIn : AudienceKitException("You're not signed in.")

    /**
     * The API rejected the session token (HTTP 401): the person signed out elsewhere, removed the app
     * from Facebook, or the session was revoked. The client has already forgotten the token; sign in again.
     */
    public class Unauthorized : AudienceKitException("Your session has ended. Sign in again to continue.")

    /**
     * `POST /v1/token` refused the Facebook token (HTTP 401): it's invalid, or it belongs to a Facebook
     * app the audience doesn't use. For Google (`POST /v1/token/google`) it carries the API's reason, such as an
     * API without the app's Google client ID.
     */
    public class SignInRejected(message: String = "Sign-in was refused. The Facebook login isn't valid for this app.") :
        AudienceKitException(message)

    /** `POST /v1/token` failed (HTTP 400). Carries the API's `message` when it sent one. */
    public data class SignInFailed(val faultMessage: String?) : AudienceKitException(faultMessage ?: "Sign-in failed.")

    /** The credentials are valid but not allowed here (HTTP 403), e.g. a session bound to another audience. */
    public class Forbidden : AudienceKitException("You don't have access to this.")

    /** The audience, record or host doesn't exist (HTTP 404). */
    public class NotFound : AudienceKitException("That isn't available.")

    /** Any other unsuccessful HTTP status. */
    public data class Http(val status: Int) : AudienceKitException("The server responded with status $status.")

    /** The request never got a response: offline, timed out, TLS failure and so on. */
    public class Network(cause: IOException) :
        AudienceKitException(cause.message ?: "The network request failed.", cause) {
        override val cause: IOException get() = super.cause as IOException
    }

    /** The response wasn't the JSON the SDK expected. */
    public data class Decoding(val detail: String) :
        AudienceKitException("The server sent a response the app didn't understand. $detail")

    /** The GraphQL operation returned errors. */
    public data class GraphQL(val errors: List<GraphQLError>) :
        AudienceKitException(errors.joinToString("\n") { it.message })

    /** The configuration is missing something this call needs, e.g. [AudienceKitConfiguration.host]. */
    public data class MissingConfiguration(val detail: String) :
        AudienceKitException("AudienceKit isn't configured: $detail")

    /** The [TokenStore] couldn't save the session token. */
    public data class TokenStorage(val detail: String) :
        AudienceKitException("The session couldn't be saved on this device. $detail")
}

/** One entry of a GraphQL response's `errors` array. */
@Serializable
public data class GraphQLError(
    val message: String,
    /** The response path of the field that failed, e.g. `["venues", 0, "page"]`. */
    val path: List<JsonElement>? = null,
    /** Extra detail: `code` on every error the API raises, `fields` on an INVALID one, `reason` on a FORBIDDEN one. */
    val extensions: Map<String, JsonElement>? = null,
) {
    /**
     * The error's code: `UNAUTHENTICATED`, `FORBIDDEN`, `NOT_FOUND`, `INVALID`, `RATE_LIMITED`, `CONFLICT`, `INTERNAL`
     * or `UNAVAILABLE`; null for an error graphql-ruby raised itself (a bad query). Apps branch on this, never on the
     * message.
     */
    public val code: String? get() = (extensions?.get("code") as? JsonPrimitive)?.contentOrNull

    /** An INVALID error's messages by field (`extensions.fields`), empty for any other error. */
    public val fields: Map<String, List<String>>
        get() = (extensions?.get("fields") as? JsonObject)?.mapValues { (_, value) ->
            (value as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull } ?: emptyList()
        } ?: emptyMap()

    /** Why a FORBIDDEN error refused (`no_permission`, `banned`, `venue_device`, ...), when the API said. */
    public val reason: String? get() = (extensions?.get("reason") as? JsonPrimitive)?.contentOrNull
}
