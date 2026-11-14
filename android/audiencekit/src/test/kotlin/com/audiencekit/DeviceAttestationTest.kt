package com.audiencekit

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

private const val TOKEN_JSON =
    """{"token":"jwt-1","userId":"u-1","audienceId":"a-1","role":"member","endpoint":"https://api.audiencekit.test/v1/audiences/a-1/graphql"}"""

private fun challengeJson(value: String, mode: String = "enforce") =
    """{"challenge":"$value","expiresAt":"2026-11-10T20:00:00Z","mode":"$mode"}"""

private val device = DeviceDescription(identifier = "pixel-1")

/** Play Integrity stand-in: answers a token naming the challenge it was given. */
private class FakeIntegrity(private val reason: String? = null, private val fails: Boolean = false) : DeviceAttestor {
    val challenges = mutableListOf<String>()
    var forgotten = 0

    override suspend fun unsupportedReason(): String? = reason

    override suspend fun attest(challenge: String): DeviceAttestation {
        challenges += challenge
        if (fails) error("Play services are missing")
        return DeviceAttestation(platform = "android", challenge = challenge, packageName = "social.hotmess.android.app",
            token = "integrity-$challenge")
    }

    override suspend fun forgetKey() {
        forgotten += 1
    }
}

private fun client(stub: StubTransport, attestor: DeviceAttestor?) = AudienceKitClient(
    AudienceKitConfiguration(baseUrl = StubTransport.BASE_URL, host = "hotmess.social", audienceId = "a-1"),
    InMemoryTokenStore(null),
    stub,
    deviceAttestor = attestor,
)

private fun RecordedRequest.attestation(): JsonObject? = jsonBody()["attestation"]?.jsonObject

class DeviceAttestationTest {
    @Test
    fun sendsAPlayIntegrityTokenOverAFreshChallengeWithEverySignIn() = runTest {
        var issued = 0
        val stub = StubTransport { request ->
            when (request.path) {
                "/v1/token/attestation" -> StubTransport.json(200, challengeJson("c-${++issued}"))
                else -> StubTransport.json(200, TOKEN_JSON)
            }
        }
        val attestor = FakeIntegrity()

        client(stub, attestor).signIn(facebookAccessToken = "fb", device = device)
        client(stub, attestor).signInWithGoogle(idToken = "google", device = device)

        assertEquals(listOf("c-1", "c-2"), attestor.challenges)
        assertEquals("hotmess.social", stub.requests[0].jsonBody()["host"]?.jsonPrimitive?.content)
        val facebook = stub.requests.first { it.path == "/v1/token" }.attestation()!!
        assertEquals("android", facebook["platform"]?.jsonPrimitive?.content)
        assertEquals("c-1", facebook["challenge"]?.jsonPrimitive?.content)
        assertEquals("social.hotmess.android.app", facebook["package_name"]?.jsonPrimitive?.content)
        assertEquals("integrity-c-1", facebook["token"]?.jsonPrimitive?.content)
        assertEquals("fb", stub.requests.first { it.path == "/v1/token" }.jsonBody()["facebook_token"]?.jsonPrimitive?.content)
        val google = stub.requests.first { it.path == "/v1/token/google" }.attestation()!!
        assertEquals("integrity-c-2", google["token"]?.jsonPrimitive?.content)
    }

    @Test
    fun throwsDeviceNotTrustedWhenTheAudienceRefuses() = runTest {
        val stub = StubTransport { request ->
            when (request.path) {
                "/v1/token/attestation" -> StubTransport.json(200, challengeJson("c"))
                else -> StubTransport.json(403, """{"error":"FORBIDDEN","message":"Only the real app","reason":"device_not_trusted"}""")
            }
        }

        val error = assertFailsWith<AudienceKitException.DeviceNotTrusted> {
            client(stub, FakeIntegrity()).signIn(facebookAccessToken = "fb", device = device)
        }
        assertEquals("Only the real app", error.message)
        assertFailsWith<AudienceKitException.DeviceNotTrusted> {
            client(stub, FakeIntegrity()).signInWithReviewCode("123456", device)
        }
    }

    @Test
    fun forgetsTheKeyAndTriesOnceMoreWhenTheAPIDoesNotKnowIt() = runTest {
        var signIns = 0
        val stub = StubTransport { request ->
            when {
                request.path == "/v1/token/attestation" -> StubTransport.json(200, challengeJson("c"))
                ++signIns == 1 -> StubTransport.json(403, """{"error":"FORBIDDEN","reason":"attestation_key_unknown"}""")
                else -> StubTransport.json(200, TOKEN_JSON)
            }
        }
        val attestor = FakeIntegrity()

        val result = client(stub, attestor).signIn(facebookAccessToken = "fb", device = device)

        assertEquals("u-1", result.userId)
        assertEquals(1, attestor.forgotten)
        assertEquals(2, signIns)
    }

    @Test
    fun saysWhyWhenTheDeviceCannotAttest() = runTest {
        val stub = StubTransport { StubTransport.json(200, TOKEN_JSON) }

        client(stub, FakeIntegrity(reason = "emulator")).signIn(facebookAccessToken = "fb", device = device)

        assertEquals(listOf("/v1/token"), stub.requests.map { it.path })
        val proof = stub.requests[0].attestation()!!
        assertTrue(proof["unsupported"]!!.jsonPrimitive.boolean)
        assertEquals("emulator", proof["reason"]?.jsonPrimitive?.content)
    }

    @Test
    fun saysAttestFailedWhenPlayIntegrityThrows() = runTest {
        val stub = StubTransport { request ->
            if (request.path == "/v1/token/attestation") StubTransport.json(200, challengeJson("c"))
            else StubTransport.json(200, TOKEN_JSON)
        }

        client(stub, FakeIntegrity(fails = true)).signIn(facebookAccessToken = "fb", device = device)

        assertEquals("attest_failed", stub.requests.last().attestation()!!["reason"]?.jsonPrimitive?.content)
    }

    @Test
    fun skipsTheWorkWhenOffOrOnAnOlderAPIOrWithoutAnAttestor() = runTest {
        val off = StubTransport { request ->
            if (request.path == "/v1/token/attestation") StubTransport.json(200, challengeJson("c", mode = "off"))
            else StubTransport.json(200, TOKEN_JSON)
        }
        val attestor = FakeIntegrity()
        client(off, attestor).signIn(facebookAccessToken = "fb", device = device)
        assertNull(off.requests.last().attestation())
        assertTrue(attestor.challenges.isEmpty())

        val older = StubTransport { request ->
            if (request.path == "/v1/token/attestation") StubTransport.json(404, "{}")
            else StubTransport.json(200, TOKEN_JSON)
        }
        client(older, attestor).signIn(facebookAccessToken = "fb", device = device)
        assertNull(older.requests.last().attestation())

        val none = StubTransport { StubTransport.json(200, TOKEN_JSON) }
        client(none, null).signIn(facebookAccessToken = "fb", device = device)
        assertEquals(listOf("/v1/token"), none.requests.map { it.path })
        assertFalse(none.requests[0].jsonBody().containsKey("attestation"))
    }

    @Test
    fun defaultsDoNothing() = runTest {
        val attestor = object : DeviceAttestor {
            override suspend fun attest(challenge: String) = DeviceAttestation.unsupported("android", "x")
        }
        assertNull(attestor.unsupportedReason())
        attestor.forgetKey()
    }

    private fun methodsJson(mode: String, required: Boolean, warning: String?) =
        """{"methods":["google"],"warnings":{},"deviceAttestation":{"mode":"$mode","required":$required,"warning":${warning?.let { "\"$it\"" } ?: "null"}}}"""

    @Test
    fun warnsThatSignInIsBlockedWhenTheDeviceCannotAttestAndTheAudienceEnforces() = runTest {
        val stub = StubTransport { StubTransport.json(200, methodsJson("enforce", true, "Blocked here.")) }

        val notice = client(stub, FakeIntegrity(reason = "emulator")).deviceAttestationNotice()!!

        assertTrue(notice.blocksSignIn)
        assertEquals("Blocked here.", notice.message)
        assertEquals("Sign-in is blocked on this device", notice.title)
        assertEquals("/v1/token/methods", stub.requests.first().path)
    }

    @Test
    fun warnsWithoutBlockingInReportModeAndWhenThereIsNoAttestorAtAll() = runTest {
        val stub = StubTransport { StubTransport.json(200, methodsJson("report", false, null)) }

        val notice = client(stub, null).deviceAttestationNotice()!!

        assertEquals("no_attestor", notice.reason)
        assertFalse(notice.blocksSignIn)
        assertEquals(DeviceAttestationNotice.defaultMessage(false), notice.message)
    }

    @Test
    fun saysNothingWhenTheDeviceCanAttestOrTheAudienceDoesNotCheck() = runTest {
        val off = StubTransport { StubTransport.json(200, methodsJson("off", false, null)) }

        assertNull(client(off, FakeIntegrity(reason = "emulator")).deviceAttestationNotice())
        assertNull(client(off, FakeIntegrity()).deviceAttestationNotice())
        assertEquals(1, off.requests.size)
    }

    @Test
    fun stillWarnsWhenTheApiCannotSay() = runTest {
        val old = StubTransport { StubTransport.json(200, """{"methods":["google"]}""") }

        val notice = client(old, FakeIntegrity(reason = "unsupported")).deviceAttestationNotice()!!

        assertFalse(notice.blocksSignIn)
        assertTrue(DeviceAttestationNotice.defaultMessage(true).contains("sign-in is blocked"))
    }
}
