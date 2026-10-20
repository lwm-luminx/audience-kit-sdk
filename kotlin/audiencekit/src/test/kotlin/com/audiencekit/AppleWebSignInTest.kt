package com.audiencekit

import java.net.URI
import java.net.URLDecoder
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class AppleWebSignInTest {
    private val signIn = AppleWebSignIn(
        servicesId = "social.hotmess.signin",
        redirectUri = AppleWebSignIn.callbackUrl("https://api.audiencekit.com/"),
        packageName = "social.hotmess.android.app",
    )

    private fun query(url: String) = URI(url).rawQuery.split("&").associate {
        val (key, value) = it.split("=", limit = 2)
        key to URLDecoder.decode(value, Charsets.UTF_8)
    }

    @Test
    fun opensApplesFormPostSignInWithTheNoncesHash() {
        val url = signIn.authorizationUrl()
        assertTrue(url.startsWith("https://appleid.apple.com/auth/authorize?"))
        val query = query(url)
        assertEquals("social.hotmess.signin", query["client_id"])
        assertEquals("https://api.audiencekit.com/v1/token/apple/callback", query["redirect_uri"])
        assertEquals("code id_token", query["response_type"])
        assertEquals("form_post", query["response_mode"])
        assertEquals("name email", query["scope"])
        assertEquals(signIn.state, query["state"])
        assertTrue(signIn.state.startsWith("social.hotmess.android.app~"))
        assertEquals(AppleWebSignIn.sha256Hex(signIn.nonce), query["nonce"])
        assertNotEquals(signIn.nonce, query["nonce"])
        assertFalse(url.contains(signIn.nonce))
    }

    @Test
    fun readsTheCredentialTheAPIHandsBack() {
        val url = "audiencekit-apple://callback?code=c-1&first_name=Ada&id_token=jwt.a.b&last_name=Byron+Lovelace" +
            "&state=${signIn.state}"
        assertTrue(AppleWebSignIn.isCallbackUrl(url))
        assertEquals(
            AppleWebSignIn.Result.Credential("jwt.a.b", "c-1", "Ada", "Byron Lovelace"),
            signIn.result(url),
        )
    }

    @Test
    fun refusesAnotherSignInsState() {
        val url = "audiencekit-apple://callback?id_token=jwt&state=social.hotmess.android.app~other"
        assertIs<AppleWebSignIn.Result.Failed>(signIn.result(url))
    }

    @Test
    fun readsACancelledSignIn() {
        val url = "audiencekit-apple://callback?error=user_cancelled_authorize&state=${signIn.state}"
        assertEquals(AppleWebSignIn.Result.Cancelled, signIn.result(url))
    }

    @Test
    fun ignoresOtherLinks() {
        assertFalse(AppleWebSignIn.isCallbackUrl("hotmess://venues/1"))
        assertIs<AppleWebSignIn.Result.Failed>(signIn.result("https://hotmess.social/venues/1"))
    }

    @Test
    fun keepsStateAndNonceWhenRebuilt() {
        val again = AppleWebSignIn(signIn.servicesId, signIn.redirectUri, signIn.packageName, signIn.state, signIn.nonce)
        assertEquals(signIn.authorizationUrl(), again.authorizationUrl())
    }
}
