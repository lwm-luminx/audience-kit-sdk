package com.audiencekit

import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.serializer
import java.io.IOException
import java.net.URI
import java.net.URISyntaxException
import java.net.URLEncoder
import kotlin.time.TimeSource

/** A change to the client's session. */
public enum class SessionEvent {
    /** [AudienceKitClient.signIn] stored a new session. */
    SIGNED_IN,

    /** [AudienceKitClient.signOut] was called. */
    SIGNED_OUT,

    /**
     * The API rejected the stored session (HTTP 401, or [AudienceKitClient.sessionRejected] for a socket or stream),
     * e.g. after the person removed the app from Facebook or the token was issued for another endpoint. The token has
     * been forgotten; show sign-in again. Emitted once per session, however many calls were refused.
     */
    SESSION_ENDED,
}

/**
 * What a successful sign-in returns: the token JSON of `POST /v1/token`, which says everything the app needs about
 * the session so it never decodes the JWT.
 */
@Serializable
public data class SignInResult(
    /** The session JWT, already saved to the client's [TokenStore]. */
    val token: String,
    /** The signed-in person's id. */
    val userId: String,
    /** The audience the session was signed in on; null for a platform sign-in. */
    val audienceId: String? = null,
    /** The person's role at [audienceId]: `member`, `listing`, `admin` or `venue_device`. */
    val role: String,
    /** The absolute URL of the GraphQL endpoint the token is for (the audience's graphql, or another endpoint for a package built on the SDK). */
    val endpoint: String,
    /** The venue device grant a device session was redeemed from; null for a person's session. */
    val venueDeviceId: String? = null,
    /** When the token expires, ISO 8601; null while sessions don't expire. */
    val expiresAt: String? = null,
)

/**
 * An HTTP request to one of the API's REST endpoints, for calls the GraphQL schema doesn't cover yet.
 */
public class APIRequest(
    public val method: String = "GET",
    /** The path under the base URL, e.g. `/v1/branding`. */
    public val path: String,
    public val queryItems: List<Pair<String, String?>> = emptyList(),
    /** A JSON body. */
    public val body: ByteArray? = null,
    /** Whether to send the session token. A 401 on an authenticated request ends the session. */
    public val authenticated: Boolean = true,
    /** Extra headers, sent alongside the client's own. */
    public val headers: Map<String, String> = emptyMap(),
)

/**
 * Talks to the AudienceKit API on behalf of one audience and one signed-in person.
 *
 * The app owns Facebook Login; hand the resulting access token to [signIn]. After that, every call
 * carries the session token as `Authorization: Bearer <token>`. When the API rejects it, the call throws
 * [AudienceKitException.Unauthorized] and [sessionEvents] emits [SessionEvent.SESSION_ENDED].
 *
 * Every call is a `suspend` function that is safe to call from the main thread. A [monitor], when given, is told
 * about each GraphQL operation.
 */
public class AudienceKitClient(
    public val configuration: AudienceKitConfiguration,
    private val tokenStore: TokenStore = InMemoryTokenStore(),
    private val transport: HttpTransport = UrlConnectionTransport(),
    public val monitor: GraphQLMonitor? = null,
) {
    private val sessionChannel = Channel<SessionEvent>(Channel.UNLIMITED)

    /** Session changes, for the app to route between sign-in and content. Collect it from one place. */
    public val sessionEvents: Flow<SessionEvent> = sessionChannel.receiveAsFlow()

    @Volatile private var resolvedAudienceId: String? = null

    /** Makes ending a refused session check-and-forget, so concurrent 401s end it once. */
    private val sessionLock = Any()

    // region Session

    /** Whether a session token is stored. It may still be rejected by the API. */
    public val isSignedIn: Boolean get() = storedToken() != null

    /**
     * The stored session token, for the rare connection the SDK doesn't make itself (e.g. the
     * Action Cable websocket). Never log it. When the API refuses it there, hand it to [sessionRejected].
     */
    public fun sessionToken(): String? = tokenStore.loadToken()

    /**
     * Exchanges a Facebook user access token for an AudienceKit session and stores it.
     *
     * Sends [AudienceKitConfiguration.host] and [AudienceKitConfiguration.facebookAppId] so the API
     * checks the token against the right Facebook app and binds the session to the audience.
     */
    public suspend fun signIn(facebookAccessToken: String, device: DeviceDescription): SignInResult =
        signIn(
            SignInRequest(
                facebookToken = facebookAccessToken,
                host = configuration.host,
                facebookAppId = configuration.facebookAppId,
                device = device,
            ),
        )

    /**
     * Exchanges the code from Facebook's OAuth dialog for an AudienceKit session and stores it.
     *
     * Use this with Facebook Login for Business, whose dialog takes the audience's
     * [Branding.facebookLoginConfigId] as `config_id` and which the Facebook Android SDK can't open.
     * The API trades the code for a token with the app secret, so [redirectUri] must be exactly the
     * one the dialog was opened with, and [facebookAppId] the app it was opened for (by default
     * [AudienceKitConfiguration.facebookAppId]; pass [Branding.facebookAppId] when the dialog used
     * the audience's app).
     */
    public suspend fun signIn(
        facebookCode: String,
        redirectUri: String,
        device: DeviceDescription,
        facebookAppId: String? = configuration.facebookAppId,
    ): SignInResult = signIn(
        SignInRequest(
            code = facebookCode,
            redirectUri = redirectUri,
            host = configuration.host,
            facebookAppId = facebookAppId,
            device = device,
        ),
    )

    /**
     * Exchanges a Google ID token for an AudienceKit session and stores it.
     *
     * The ID token only carries the Google account's primary email. Pass [accessToken], an OAuth access token for
     * the `https://www.googleapis.com/auth/user.emails.read` scope, and the API can also match an existing account by
     * the Google account's other verified emails. Without it, sign-in works the same, matching by the primary one.
     */
    public suspend fun signInWithGoogle(
        idToken: String,
        device: DeviceDescription,
        name: String? = null,
        accessToken: String? = null,
    ): SignInResult = signIn(
        GoogleSignInRequest(
            idToken = idToken,
            accessToken = accessToken,
            host = configuration.host,
            device = device,
            name = name,
        ),
    )

    /**
     * Connects a Google account to the signed-in account, so Google signs in to it from then on, and stores the session
     * the API answers with (for the account that now has Google; when the Google account already had its own account,
     * the two became one). Use it when someone who signed in with Facebook or Apple wants Google too, whatever email
     * either account has.
     *
     * Refusals throw [AudienceKitException.SignInFailed] with the API's reason (such as a Google account that already
     * signs in to another account) and keep the current session.
     */
    public suspend fun connectGoogle(idToken: String, device: DeviceDescription): SignInResult {
        val token = storedToken() ?: throw AudienceKitException.NotSignedIn()
        return signIn(
            GoogleSignInRequest(idToken = idToken, host = configuration.host, device = device, connect = true),
            token,
        )
    }

    private suspend fun signIn(body: SignInRequest): SignInResult {
        val request = APIRequest(
            method = "POST",
            path = "/v1/token",
            body = encodeJson.encodeToString(SignInRequest.serializer(), body).toByteArray(),
            authenticated = false,
        )

        val response = perform(request)
        when (response.status) {
            in 200..299 -> Unit
            401 -> throw AudienceKitException.SignInRejected()
            400 -> {
                val error = runCatching { decodeJson.decodeFromString(ErrorEnvelope.serializer(), response.text) }
                throw AudienceKitException.SignInFailed(error.getOrNull()?.message)
            }
            else -> throw errorForStatus(response.status)
        }

        val result = decode(SignInResult.serializer(), response.text, decodeJson)
        try {
            tokenStore.saveToken(result.token)
            tokenStore.saveAudienceId(result.audienceId)
        } catch (e: Exception) {
            throw AudienceKitException.TokenStorage(e.toString())
        }
        resolvedAudienceId = result.audienceId
        sessionChannel.trySend(SessionEvent.SIGNED_IN)
        return result
    }

    /**
     * Exchanges a Sign in with Apple identity token for an AudienceKit session and stores it (`POST /v1/token/apple`).
     *
     * On Android the credential comes from Apple's web sign-in ([AppleWebSignIn]): pass its [AppleWebSignIn.Result.Credential]
     * and the [AppleWebSignIn] that started it, whose nonce binds the token to this app and whose return URL Apple needs
     * again to exchange the authorization code (which lets the API revoke the sign-in when the account is deleted).
     * Apple sends the name only the first time someone signs in to the app; the credential carries it then.
     */
    public suspend fun signInWithApple(
        credential: AppleWebSignIn.Result.Credential,
        signIn: AppleWebSignIn,
        device: DeviceDescription,
    ): SignInResult = signInWithApple(
        AppleSignInRequest(
            identityToken = credential.identityToken,
            authorizationCode = credential.authorizationCode,
            redirectUri = signIn.redirectUri,
            nonce = signIn.nonce,
            firstName = credential.firstName,
            lastName = credential.lastName,
            host = configuration.host,
            device = device,
        ),
    )

    private suspend fun signInWithApple(body: AppleSignInRequest): SignInResult =
        exchange("/v1/token/apple", encodeJson.encodeToString(AppleSignInRequest.serializer(), body).toByteArray())

    /** [token] is the session being connected (for `connect`); a refusal never ends it. */
    private suspend fun signIn(body: GoogleSignInRequest, token: String? = null): SignInResult =
        exchange("/v1/token/google", encodeJson.encodeToString(GoogleSignInRequest.serializer(), body).toByteArray(), token)

    /**
     * Posts a sign-in to [path] and stores the session it answers with. [token] is a session being connected, sent as
     * Authorization; a refusal never ends it.
     */
    private suspend fun exchange(path: String, body: ByteArray, token: String? = null): SignInResult {
        val request = APIRequest(method = "POST", path = path, body = body, authenticated = false)

        val response = perform(request, token)
        when (response.status) {
            in 200..299 -> Unit
            401 -> {
                val error = runCatching { decodeJson.decodeFromString(ErrorEnvelope.serializer(), response.text) }
                throw AudienceKitException.SignInRejected(error.getOrNull()?.message ?: "Sign-in was refused. Google didn't vouch for that account.")
            }
            400 -> {
                val error = runCatching { decodeJson.decodeFromString(ErrorEnvelope.serializer(), response.text) }
                throw AudienceKitException.SignInFailed(error.getOrNull()?.message)
            }
            else -> throw errorForStatus(response.status)
        }

        val result = decode(SignInResult.serializer(), response.text, decodeJson)
        try {
            tokenStore.saveToken(result.token)
            tokenStore.saveAudienceId(result.audienceId)
        } catch (e: Exception) {
            throw AudienceKitException.TokenStorage(e.toString())
        }
        resolvedAudienceId = result.audienceId
        sessionChannel.trySend(SessionEvent.SIGNED_IN)
        return result
    }

    /**
     * Re-issues the session token at `POST /v1/token/refresh` (the same session, signed with the API's current key)
     * and stores it. Sessions don't expire yet; call this after a long time away, or when the API says the token's
     * key was retired. A 401 means the session ended, like any other call.
     */
    public suspend fun refreshSession(): SignInResult {
        val text = data(APIRequest(method = "POST", path = "/v1/token/refresh")).toString(Charsets.UTF_8)
        val result = decode(SignInResult.serializer(), text, decodeJson)
        try {
            tokenStore.saveToken(result.token)
            tokenStore.saveAudienceId(result.audienceId)
        } catch (e: Exception) {
            throw AudienceKitException.TokenStorage(e.toString())
        }
        resolvedAudienceId = result.audienceId
        return result
    }

    /** Forgets the session on this device. (The Facebook session belongs to the app; log out of it too.) */
    public fun signOut() {
        runCatching { tokenStore.deleteToken() }
        resolvedAudienceId = null
        sessionChannel.trySend(SessionEvent.SIGNED_OUT)
    }

    // endregion

    // region Branding

    /** The audience's public branding for [AudienceKitConfiguration.host] (or [host]). No sign-in needed. */
    public suspend fun branding(host: String? = null): Branding {
        val brandingHost = host ?: configuration.host
            ?: throw AudienceKitException.MissingConfiguration("branding needs a host")

        val request = APIRequest(path = "/v1/branding", queryItems = listOf("host" to brandingHost), authenticated = false)
        val response = perform(request)
        if (response.status !in 200..299) throw errorForStatus(response.status)

        return decode(Branding.serializer(), response.text, decodeJson)
    }

    // endregion

    // region Audience

    /**
     * The audience this client queries: the configured ID, the audience the sign-in named (`audienceId` in the
     * token JSON, kept in the [TokenStore]), or the audience that owns the configured host.
     */
    public suspend fun audienceId(): String {
        (configuration.audienceId ?: resolvedAudienceId)?.let { return it }

        runCatching { tokenStore.loadAudienceId() }.getOrNull()?.let {
            resolvedAudienceId = it
            return it
        }

        if (configuration.host == null) {
            throw AudienceKitException.MissingConfiguration("set an audienceId or a host")
        }

        return branding().audience.id.also { resolvedAudienceId = it }
    }

    // endregion

    // region GraphQL

    /**
     * Runs a GraphQL operation against the audience's endpoint and decodes its `data` with [deserializer].
     *
     * Throws [AudienceKitException.GraphQL] when the response carries errors, even alongside data.
     * Pass a [json] to decode into the app's own models with its own settings. [endpoint] is the consumer view;
     * a package built on the SDK passes its own.
     */
    public suspend fun <T> graphQL(
        query: String,
        deserializer: KSerializer<T>,
        variables: Map<String, JsonElement>? = null,
        operationName: String? = null,
        json: Json = decodeJson,
        endpoint: GraphQLEndpoint = GraphQLEndpoint.CONSUMER,
    ): T {
        val audienceId = audienceId()
        val body = encodeJson.encodeToString(
            GraphQLRequest.serializer(),
            GraphQLRequest(query = query, variables = variables, operationName = operationName),
        )
        val (type, name) = GraphQLOperationEvent.describe(query, operationName)
        val request = APIRequest(
            method = "POST",
            path = endpoint.path(audienceId),
            body = body.toByteArray(),
            headers = buildMap {
                put("X-APOLLO-OPERATION-TYPE", type)
                name?.let { put("X-APOLLO-OPERATION-NAME", it) }
            },
        )

        val started = TimeSource.Monotonic.markNow()
        val result = runCatching {
            val text = data(request).toString(Charsets.UTF_8)
            // Errors first: a refused mutation comes back as `{"errors":[…],"data":{"field":null}}`, which the
            // caller's types usually can't hold, so decoding `data` first would hide the refusal.
            val envelope = decode(GraphQLResponse.serializer(JsonElement.serializer()), text, json)

            if (!envelope.errors.isNullOrEmpty()) throw AudienceKitException.GraphQL(envelope.errors)
            val data = envelope.data?.takeUnless { it is JsonNull }
                ?: throw AudienceKitException.Decoding("The response had no data.")
            decode(deserializer, data, json)
        }
        monitor?.record(
            GraphQLOperationEvent(
                name = name,
                type = type,
                endpoint = endpoint,
                duration = started.elapsedNow(),
                error = result.exceptionOrNull()?.let { it.message ?: it.toString() },
            ),
        )
        return result.getOrThrow()
    }

    /** [graphQL] for a `@Serializable` type, e.g. `client.graphQL<MyResponse>(query)`. */
    public suspend inline fun <reified T> graphQL(
        query: String,
        variables: Map<String, JsonElement>? = null,
        operationName: String? = null,
        json: Json = AudienceKitClient.json,
        endpoint: GraphQLEndpoint = GraphQLEndpoint.CONSUMER,
    ): T = graphQL(query, json.serializersModule.serializer<T>(), variables, operationName, json, endpoint)

    /** The audience, with its theme. */
    public suspend fun audience(): Audience =
        graphQL(Queries.audience, Audience.serializer(), operationName = "Audience")

    /** The audience's venues. */
    public suspend fun venues(): List<Venue> =
        graphQL(Queries.venues, VenuesResponse.serializer(), operationName = "Venues").venues?.list?.nodes.orEmpty()

    /** The people the audience follows. */
    public suspend fun people(): List<Person> =
        graphQL(Queries.people, PeopleResponse.serializer(), operationName = "People").people?.list?.nodes.orEmpty()

    /** The audience's locales. */
    public suspend fun locales(): List<AudienceLocale> =
        graphQL(Queries.locales, LocalesResponse.serializer(), operationName = "Locales").locales

    /** The signed-in user, or `null` when the API has no current user. */
    public suspend fun me(): SelfUser? = graphQL(Queries.me, MeResponse.serializer(), operationName = "Me").me?.self

    /** Any record by its `id` (its UUID), or `null` when it doesn't exist or belongs to another audience. */
    public suspend fun node(id: String): Node? =
        graphQL(Queries.node, NodeResponse.serializer(), graphQLVariables("id" to id), "Node").node

    /** The audience's locale nearest a position, or `null` when it has none. */
    public suspend fun closestLocale(near: Coordinates): AudienceLocale? =
        graphQL(
            Queries.closestLocale,
            ClosestLocaleResponse.serializer(),
            mapOf("near" to near.toGraphQLValue()),
            "ClosestLocale",
        ).closestLocale

    /**
     * Sets the signed-in user's RSVP to an event in AudienceKit (it isn't sent to Facebook). Returns their answer
     * afterwards: still [RSVPState.ATTENDING] for someone holding a ticket, whatever they said.
     */
    public suspend fun setRSVP(state: RSVPState, eventId: String): RSVPState =
        rsvp(eventId, state).mine

    /** Sets the signed-in user's RSVP, as [setRSVP], and returns the event's RSVPs afterwards (without attendees). */
    public suspend fun rsvp(eventId: String, state: RSVPState = RSVPState.ATTENDING): EventRSVP =
        graphQL(
            Queries.rsvpEvent,
            RSVPEventResponse.serializer(),
            graphQLVariables("eventId" to eventId, "state" to state),
            "RSVPEvent",
        ).rsvpEvent.event.rsvp.toEventRSVP()

    /**
     * Takes back the signed-in user's RSVP, as if they'd never answered. Someone holding a ticket stays going. Returns
     * the event's RSVPs afterwards (without attendees).
     */
    public suspend fun cancelRSVP(eventId: String): EventRSVP =
        graphQL(
            Queries.cancelRsvp,
            CancelRSVPResponse.serializer(),
            graphQLVariables("eventId" to eventId),
            "CancelRSVP",
        ).cancelRsvp.event.rsvp.toEventRSVP()

    /** Who's going to an event and the first [first] of them by name, or `null` when there's no such event. */
    public suspend fun eventRSVP(eventId: String, first: Int = 50): EventRSVP? =
        graphQL(
            Queries.eventRsvp,
            EventRSVPResponse.serializer(),
            graphQLVariables("id" to eventId, "first" to first),
            "EventRSVP",
        ).events.event?.rsvp?.toEventRSVP()

    /** The tribes people can identify with here, and the signed-in user's own (empty when signed out). */
    public suspend fun tribes(): Tribes {
        val data = graphQL(Queries.tribes, TribesResponse.serializer(), operationName = "Tribes")
        return Tribes(available = data.tribes, mine = data.me?.self?.tribes.orEmpty())
    }

    /**
     * Identifies the signed-in user with a tribe, privately unless [isPrivate] is false, or changes that. Returns
     * their tribes here afterwards.
     */
    public suspend fun identifyWithTribe(tagId: String, isPrivate: Boolean = true): List<TribeIdentification> =
        graphQL(
            Queries.identifyWithTribe,
            IdentifyWithTribeResponse.serializer(),
            graphQLVariables("tagId" to tagId, "isPrivate" to isPrivate),
            "IdentifyWithTribe",
        ).identifyWithTribe.tribes

    /** Takes the signed-in user out of a tribe; nothing is kept. Returns their tribes here afterwards. */
    public suspend fun leaveTribe(tagId: String): List<TribeIdentification> =
        graphQL(Queries.leaveTribe, LeaveTribeResponse.serializer(), graphQLVariables("tagId" to tagId), "LeaveTribe")
            .leaveTribe.tribes

    /** Stores the push notification (FCM) token for the device this session signed in on. */
    public suspend fun registerDevice(notificationToken: String) {
        graphQL(
            Queries.registerDevice,
            RegisterDeviceResponse.serializer(),
            graphQLVariables("notificationToken" to notificationToken),
            "RegisterDevice",
        )
    }

    // endregion

    // region Cover charge

    /** A venue's cover tonight and the signed-in user's pass for it, or `null` when the venue doesn't exist. */
    public suspend fun venueCover(venueId: String): VenueCover? =
        graphQL(Queries.venueCover, VenueCoverResponse.serializer(), graphQLVariables("id" to venueId), "VenueCover").venues.venue

    /**
     * Starts paying tonight's cover at a venue. For a Stripe venue, finish the payment with Stripe's payment
     * sheet, set up with [CoverPurchase.publishableKey] on the venue's account [CoverPurchase.stripeAccountId],
     * then call [confirmCover]. For a Square venue ([CoverPurchase.isSquare]), make a payment token with Square's
     * In-App Payments SDK and call [payCover]. Asking again the same night returns the same pass.
     */
    public suspend fun buyCover(venueId: String): CoverPurchase =
        graphQL(Queries.buyCover, BuyCoverResponse.serializer(), graphQLVariables("venueId" to venueId), "BuyCover").buyCover

    /**
     * Pays a Square venue's cover with a payment token (nonce) from Square's In-App Payments SDK: a card, Google
     * Pay or Apple Pay. The returned pass is paid when Square took the payment.
     */
    public suspend fun payCover(admissionId: String, sourceId: String, verificationToken: String? = null): Admission =
        graphQL(
            Queries.payCover,
            PayCoverResponse.serializer(),
            graphQLVariables("admissionId" to admissionId, "sourceId" to sourceId, "verificationToken" to verificationToken),
            "PayCover",
        ).payCover.admission

    /** Checks a cover payment with its provider after the app finishes paying, so the pass works straight away. */
    public suspend fun confirmCover(admissionId: String): Admission =
        graphQL(
            Queries.confirmCover,
            ConfirmCoverResponse.serializer(),
            graphQLVariables("admissionId" to admissionId),
            "ConfirmCover",
        ).confirmCover.admission

    /** Refunds a cover. Buyers can refund their own until it's scanned in or the night is over. */
    public suspend fun refundAdmission(admissionId: String): Admission =
        graphQL(
            Queries.refundAdmission,
            RefundAdmissionResponse.serializer(),
            graphQLVariables("admissionId" to admissionId),
            "RefundAdmission",
        ).refundAdmission.admission

    /** The signed-in user's cover passes, newest first. */
    public suspend fun admissions(): List<Admission> =
        graphQL(Queries.admissions, AdmissionsResponse.serializer(), operationName = "Admissions")
            .me?.cover?.admissions?.nodes.orEmpty()

    // endregion

    // region REST

    /** Sends a request to a REST endpoint and returns the body of a successful response. */
    public suspend fun data(request: APIRequest): ByteArray {
        val token = if (request.authenticated) storedToken() ?: throw AudienceKitException.NotSignedIn() else null

        val response = perform(request, token)
        return when {
            response.status in 200..299 -> response.body
            response.status == 401 && token != null -> {
                sessionRejected(token)
                throw AudienceKitException.Unauthorized()
            }
            else -> throw errorForStatus(response.status)
        }
    }

    /**
     * Ends the session because the API refused [token], for connections the SDK doesn't make itself: an Action Cable
     * socket the server closed with `"reason": "unauthorized"`, or a Server-Sent Events stream answered with HTTP 401.
     * (A 403 or a rejected channel subscription is a refusal of that one thing, not of the session; don't call this.)
     *
     * Forgets the token and emits [SessionEvent.SESSION_ENDED], once: when the store no longer holds [token] (the
     * session already ended, or the person has signed in again since) it does nothing and returns false.
     */
    public fun sessionRejected(token: String): Boolean {
        synchronized(sessionLock) {
            if (storedToken() != token) return false
            runCatching { tokenStore.deleteToken() }
            resolvedAudienceId = null
        }
        sessionChannel.trySend(SessionEvent.SESSION_ENDED)
        return true
    }

    /** Resolves a URL the API sent (absolute, or a path relative to the base URL). */
    public fun url(string: String?): String? {
        if (string.isNullOrEmpty()) return null
        return try {
            URI(configuration.baseUrl).resolve(string).toString()
        } catch (_: URISyntaxException) {
            null
        } catch (_: IllegalArgumentException) {
            null
        }
    }

    // endregion

    private fun storedToken(): String? = runCatching { tokenStore.loadToken() }.getOrNull()

    private suspend fun perform(
        request: APIRequest,
        token: String? = if (request.authenticated) storedToken() else null,
    ): HttpResponse {
        val httpRequest = makeHttpRequest(request, token)
        return try {
            transport.execute(httpRequest)
        } catch (e: IOException) {
            throw AudienceKitException.Network(e)
        }
    }

    private fun makeHttpRequest(request: APIRequest, token: String?): HttpRequest {
        val base = configuration.baseUrl.trimEnd('/')
        val path = if (request.path.startsWith("/")) request.path else "/${request.path}"
        val query = request.queryItems.joinToString("&") { (name, value) ->
            if (value == null) encode(name) else "${encode(name)}=${encode(value)}"
        }
        val url = base + path + if (query.isEmpty()) "" else "?$query"

        val headers = buildMap {
            put("Accept", "application/json")
            put("X-AudienceKit-Client", "AudienceKit-Kotlin/${AudienceKitSDK.VERSION}")
            put("X-AudienceKit-API-Version", AudienceKitSDK.API_VERSION)
            if (configuration.environment != AudienceKitEnvironment.PRODUCTION) {
                put(AudienceKitEnvironment.HEADER, configuration.environment.value)
            }
            if (request.body != null) put("Content-Type", "application/json")
            token?.let { put("Authorization", "Bearer $it") }
            putAll(request.headers)
        }

        return HttpRequest(method = request.method, url = url, headers = headers, body = request.body)
    }

    private fun encode(value: String) = URLEncoder.encode(value, Charsets.UTF_8.name()).replace("+", "%20")

    public companion object {
        /** The JSON settings the client decodes with: unknown keys are ignored, so new API fields don't break apps. */
        public val json: Json = Json {
            ignoreUnknownKeys = true
            explicitNulls = false
            coerceInputValues = true
        }

        private val decodeJson get() = json

        // Defaults are sent (the device `type`); nulls are left out, as the API expects.
        private val encodeJson = Json {
            encodeDefaults = true
            explicitNulls = false
        }

        private fun errorForStatus(status: Int): AudienceKitException = when (status) {
            401 -> AudienceKitException.Unauthorized()
            403 -> AudienceKitException.Forbidden()
            404 -> AudienceKitException.NotFound()
            else -> AudienceKitException.Http(status)
        }

        private fun <T> decode(deserializer: KSerializer<T>, text: String, json: Json): T = try {
            json.decodeFromString(deserializer, text)
        } catch (e: SerializationException) {
            throw AudienceKitException.Decoding(e.message ?: e.toString())
        } catch (e: IllegalArgumentException) {
            throw AudienceKitException.Decoding(e.message ?: e.toString())
        }

        private fun <T> decode(deserializer: KSerializer<T>, element: JsonElement, json: Json): T = try {
            json.decodeFromJsonElement(deserializer, element)
        } catch (e: SerializationException) {
            throw AudienceKitException.Decoding(e.message ?: e.toString())
        } catch (e: IllegalArgumentException) {
            throw AudienceKitException.Decoding(e.message ?: e.toString())
        }
    }
}

private val HttpResponse.text: String get() = body.toString(Charsets.UTF_8)

// Wire types

@Serializable
internal data class SignInRequest(
    @SerialName("facebook_token") val facebookToken: String? = null,
    val code: String? = null,
    @SerialName("redirect_uri") val redirectUri: String? = null,
    val host: String? = null,
    @SerialName("facebook_app_id") val facebookAppId: String? = null,
    val device: DeviceDescription,
)

@Serializable
internal data class AppleSignInRequest(
    @SerialName("identity_token") val identityToken: String,
    @SerialName("authorization_code") val authorizationCode: String? = null,
    @SerialName("redirect_uri") val redirectUri: String? = null,
    val nonce: String? = null,
    @SerialName("first_name") val firstName: String? = null,
    @SerialName("last_name") val lastName: String? = null,
    val host: String? = null,
    val device: DeviceDescription,
)

@Serializable
internal data class GoogleSignInRequest(
    @SerialName("id_token") val idToken: String,
    @SerialName("access_token") val accessToken: String? = null,
    val host: String? = null,
    val device: DeviceDescription,
    val name: String? = null,
    val connect: Boolean? = null,
)

/** A REST error: `{ "error": "<code>", "message": "..." }` (the API's doc/TOKENS.md, "Error codes"). */
@Serializable
internal data class ErrorEnvelope(val error: String? = null, val message: String? = null)

@Serializable
internal data class GraphQLRequest(
    val query: String,
    val variables: Map<String, JsonElement>? = null,
    val operationName: String? = null,
)

@Serializable
internal data class GraphQLResponse<T>(
    val data: T? = null,
    val errors: List<GraphQLError>? = null,
)
