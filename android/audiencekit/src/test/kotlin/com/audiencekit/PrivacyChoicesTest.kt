package com.audiencekit

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

private fun privacyClient(stub: StubTransport): AudienceKitClient = AudienceKitClient(
    AudienceKitConfiguration(baseUrl = StubTransport.BASE_URL, audienceId = "b0f8b66a-e636-495d-9475-0f5317ea08e4"),
    InMemoryTokenStore("session-token"),
    stub,
)

private fun RecordedRequest.operation(): String? = (jsonBody()["operationName"] as? JsonPrimitive)?.content
private fun RecordedRequest.variable(name: String) = jsonBody()["variables"]?.jsonObject?.get(name)

private const val CHOICES = """{"saleShareOptedOut":true,"saleShareOptedOutAt":"2026-11-23T01:00:00Z","saleShareOptOutSource":"GLOBAL_PRIVACY_CONTROL","adMeasurement":true,"countedInAdMeasurement":true,"personalizedAds":false,"mayShare":false,"privacyPassUntil":null}"""

class PrivacyChoicesTest {
    @Test
    fun readsTheOfferAndTheMembersChoices() = runTest {
        val stub = StubTransport {
            StubTransport.json(
                200,
                """{"data":{"privacyOffer":{"choices":["SALE_SHARE_OPT_OUT","AD_MEASUREMENT","SOMETHING_NEW","PRIVACY_PASS"],"passCents":299,"passDays":30},"me":{"privacy":$CHOICES}}}""",
            )
        }

        val (offer, choices) = privacyClient(stub).privacy()

        assertEquals(
            PrivacyOffer(
                listOf(PrivacyChoiceKey.SALE_SHARE_OPT_OUT, PrivacyChoiceKey.AD_MEASUREMENT, PrivacyChoiceKey.PRIVACY_PASS),
                299,
                30,
            ),
            offer,
        )
        assertTrue(choices.isOn(PrivacyChoiceKey.SALE_SHARE_OPT_OUT))
        assertEquals(PrivacyOptOutSource.GLOBAL_PRIVACY_CONTROL, choices.saleShareOptOutSource)
        assertFalse(choices.mayShare)
        assertFalse(choices.isOn(PrivacyChoiceKey.PRIVACY_PASS))
    }

    @Test
    fun signedOutReadsTheDefaults() = runTest {
        val stub = StubTransport {
            StubTransport.json(
                200,
                """{"data":{"privacyOffer":{"choices":["SALE_SHARE_OPT_OUT"],"passCents":null,"passDays":30},"me":null}}""",
            )
        }

        val (offer, choices) = privacyClient(stub).privacy()

        assertEquals(listOf(PrivacyChoiceKey.SALE_SHARE_OPT_OUT), offer.choices)
        assertEquals(PrivacyChoices.DEFAULTS, choices)
    }

    @Test
    fun turningOneSwitchSendsOnlyThatChoice() = runTest {
        val stub = StubTransport {
            StubTransport.json(200, """{"data":{"updatePrivacyChoices":{"privacy":$CHOICES}}}""")
        }

        val choices = privacyClient(stub).setPrivacyChoice(PrivacyChoiceKey.SALE_SHARE_OPT_OUT, on = true)

        assertTrue(choices.saleShareOptedOut)
        val request = stub.requests.single()
        assertEquals("UpdatePrivacyChoices", request.operation())
        assertEquals(JsonPrimitive(true), request.variable("saleShareOptOut"))
        assertEquals(JsonNull, request.variable("adMeasurement"))
    }

    @Test
    fun startingAPrivacyPassReturnsTheCheckout() = runTest {
        val stub = StubTransport {
            StubTransport.json(
                200,
                """{"data":{"startPrivacyPass":{"checkoutUrl":"https://checkout.stripe.com/c/pay/cs_1","passId":"p-1"}}}""",
            )
        }

        val checkout = privacyClient(stub).startPrivacyPass(returnUrl = "hotmess://privacy")

        assertEquals(PrivacyPassCheckout("p-1", "https://checkout.stripe.com/c/pay/cs_1"), checkout)
        assertEquals(JsonPrimitive("hotmess://privacy"), stub.requests.single().variable("returnUrl"))
    }

    @Test
    fun aPrivacyPassWithoutACheckoutThrows() = runTest {
        val stub = StubTransport { StubTransport.json(200, """{"data":{"startPrivacyPass":null}}""") }

        assertFailsWith<PrivacyPassUnavailableException> { privacyClient(stub).startPrivacyPass() }
    }

    @Test
    fun offersThePassOnlyInUsStorefrontsOrOnTheWeb() {
        val offer = PrivacyOffer(listOf(PrivacyChoiceKey.SALE_SHARE_OPT_OUT, PrivacyChoiceKey.PRIVACY_PASS), 299, 30)

        assertTrue(PrivacyChoicesCopy.isPassOffered(offer, "US"))
        assertTrue(PrivacyChoicesCopy.isPassOffered(offer, "usa"))
        assertFalse(PrivacyChoicesCopy.isPassOffered(offer, "GB"))
        assertFalse(PrivacyChoicesCopy.isPassOffered(offer, null))
        assertTrue(PrivacyChoicesCopy.isPassOffered(offer, null, isWeb = true))
        assertFalse(PrivacyChoicesCopy.isPassOffered(PrivacyOffer.MINIMUM, "US"))
    }

    @Test
    fun privacyCopyNamesEachChoice() {
        assertEquals("Your privacy choices", PrivacyChoicesCopy.TITLE)
        assertEquals("Do not sell or share my personal information", PrivacyChoicesCopy.label(PrivacyChoiceKey.SALE_SHARE_OPT_OUT))
        assertEquals("Go without ads for 30 days, $2.99", PrivacyChoicesCopy.passButton(299, 30))
        assertTrue(PrivacyChoicesCopy.detail(PrivacyChoiceKey.SALE_SHARE_OPT_OUT, "Hot Mess").startsWith("Hot Mess doesn't sell"))
        assertTrue(PrivacyChoicesCopy.passExplanation(7).contains("nothing renews"))
        assertTrue(PrivacyChoicesCopy.intro("Hot Mess").contains("Hot Mess only"))
        assertTrue(PrivacyChoicesCopy.passRunning("Dec 23, 2026").contains("Dec 23, 2026"))
        PrivacyChoiceKey.entries.forEach { assertTrue(PrivacyChoicesCopy.detail(it, "Hot Mess").isNotEmpty()) }
    }
}
