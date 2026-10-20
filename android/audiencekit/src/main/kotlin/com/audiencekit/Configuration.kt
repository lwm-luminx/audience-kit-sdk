package com.audiencekit

import kotlinx.serialization.Serializable

/**
 * Which build of the app is calling. Staging builds talk to the production API but sign people in
 * with the audience's staging Facebook app; the client says so with the
 * `X-AudienceKit-Environment: staging` header. Development builds run against a local API, which
 * uses its own Facebook app, so they stay [PRODUCTION].
 */
public enum class AudienceKitEnvironment(public val value: String) {
    PRODUCTION("production"),
    STAGING("staging"),
    ;

    public companion object {
        /** The header that carries the environment. Production builds leave it out. */
        public const val HEADER: String = "X-AudienceKit-Environment"
    }
}

/** Where the SDK talks to and which audience it speaks for. */
public data class AudienceKitConfiguration(
    /** The API's base URL, e.g. `https://api.audiencekit.com` or `http://10.0.2.2:3000` from the emulator. */
    val baseUrl: String = AudienceKitSDK.PRODUCTION_BASE_URL,
    /**
     * A host that names the audience, e.g. `hotmess.social` once that domain is verified, or
     * `hotmess.admin.audiencekit.com`, which works as soon as the audience exists.
     *
     * Sent with sign-in, so the session is bound to the audience and the Facebook token is checked
     * against the audience's Facebook apps, and used to look up [Branding]. Without a host the API
     * only accepts tokens from the AudienceKit platform Facebook app.
     */
    val host: String? = null,
    /**
     * The audience's ID (a UUID). When `null` the client works it out from the session token's
     * `audienceId` the sign-in named, or from [AudienceKitClient.branding] for [host].
     */
    val audienceId: String? = null,
    /**
     * The Facebook app the build signs people in with. The API only accepts the audience's own
     * apps (production, staging, development) or the platform app.
     */
    val facebookAppId: String? = null,
    /**
     * The build's environment. [AudienceKitEnvironment.STAGING] makes the API sign people in with,
     * and [AudienceKitClient.branding] return, the audience's staging Facebook app.
     */
    val environment: AudienceKitEnvironment = AudienceKitEnvironment.PRODUCTION,
)

/** The device a session is created on. The API records it alongside the session. */
@Serializable
public data class DeviceDescription(
    /** A stable identifier for this install, e.g. `Settings.Secure.ANDROID_ID`. */
    val identifier: String,
    /** `android` for Android clients. */
    val type: String = "android",
    /** The hardware model, e.g. `Google Pixel 9`. */
    val model: String? = null,
    /** The app's version name. */
    val version: String? = null,
    /** The app's version code. */
    val build: String? = null,
) {
    /** Extended by `audiencekit-android` with `DeviceDescription.current(context)`. */
    public companion object
}
