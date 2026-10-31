package com.audiencekit

/**
 * Entry point for the AudienceKit client SDK.
 *
 * Create an [AudienceKitClient] with an [AudienceKitConfiguration], sign the person in with a
 * Facebook access token your app obtained, then query the audience's data over GraphQL.
 */
public object AudienceKitSDK {
    /** The SDK's semantic version. */
    public const val VERSION: String = "0.35.0"

    /**
     * The API contract this SDK speaks, the date it was last broken, sent on every call as
     * `X-AudienceKit-API-Version`. The API refuses a version it doesn't serve with 400 `unsupported_api_version`.
     */
    public const val API_VERSION: String = "2026-10-11"

    /** The hosted AudienceKit API. */
    public const val PRODUCTION_BASE_URL: String = "https://api.audiencekit.com"
}
