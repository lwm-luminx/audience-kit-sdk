package com.audiencekit

/**
 * Somewhere to keep the session token between launches.
 *
 * Session tokens don't expire (they are revoked), so treat them like passwords: on Android use
 * `KeystoreTokenStore` from `audiencekit-android`, and never log them.
 */
public interface TokenStore {
    public fun loadToken(): String?
    public fun saveToken(token: String)
    public fun deleteToken()

    /**
     * The audience the stored session was signed in on (`audienceId` in the sign-in JSON), kept beside the token so the
     * client needn't decode the JWT. Not a secret. A store that keeps nothing here makes the client look the audience
     * up from the configured host on each launch.
     */
    public fun loadAudienceId(): String? = null
    public fun saveAudienceId(audienceId: String?) {}
}

/** Keeps the token in memory only, for tests and previews. */
public class InMemoryTokenStore(token: String? = null, audienceId: String? = null) : TokenStore {
    @Volatile private var token: String? = token
    @Volatile private var audienceId: String? = audienceId

    override fun loadToken(): String? = token

    override fun saveToken(token: String) {
        this.token = token
    }

    override fun deleteToken() {
        token = null
        audienceId = null
    }

    override fun loadAudienceId(): String? = audienceId

    override fun saveAudienceId(audienceId: String?) {
        this.audienceId = audienceId
    }
}
