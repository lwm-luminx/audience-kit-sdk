package com.audiencekit

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

private fun adFreeClient(stub: StubTransport): AudienceKitClient = AudienceKitClient(
    AudienceKitConfiguration(baseUrl = StubTransport.BASE_URL, audienceId = "b0f8b66a-e636-495d-9475-0f5317ea08e3"),
    InMemoryTokenStore("session-token"),
    stub,
)

private fun RecordedRequest.document(): String = (jsonBody()["query"] as JsonPrimitive).content
private fun RecordedRequest.operation(): String? = (jsonBody()["operationName"] as? JsonPrimitive)?.content
private fun RecordedRequest.variable(name: String) = jsonBody()["variables"]?.jsonObject?.get(name)

class AdFreeTipsTest {
    @Test
    fun startingAnAdFreeTipReturnsTheWebCheckout() = runTest {
        val stub = StubTransport {
            StubTransport.json(
                200,
                """{"data":{"startTip":{"checkoutUrl":"https://api.example/v1/tips/t-1/checkout?token=x","tip":{"id":"t-1"}}}}""",
            )
        }

        val checkout = adFreeClient(stub).startAdFreeTip(publicationId = "pub-1", amountCents = 500)

        assertEquals(AdFreeTipCheckout("t-1", "https://api.example/v1/tips/t-1/checkout?token=x"), checkout)
        val request = stub.requests.single()
        assertEquals("StartAdFreeTip", request.operation())
        assertEquals(JsonPrimitive("pub-1"), request.variable("publicationId"))
        assertEquals(JsonPrimitive(500), request.variable("amountCents"))
        assertFalse(request.document().contains("paymentIntentClientSecret"))
    }

    @Test
    fun anAdFreeTipWithoutACheckoutThrows() = runTest {
        val stub = StubTransport {
            StubTransport.json(200, """{"data":{"startTip":{"checkoutUrl":null,"tip":{"id":"t-1"}}}}""")
        }

        assertFailsWith<AdFreeTipUnavailableException> {
            adFreeClient(stub).startAdFreeTip(publicationId = "pub-1", amountCents = 500)
        }
    }

    @Test
    fun confirmingATipReadsWhenAdsComeBack() = runTest {
        val stub = StubTransport {
            StubTransport.json(
                200,
                """{"data":{"confirmTip":{"tip":{"id":"t-1","status":"PAID","readsAdFreeUntil":"2026-12-14T12:00:00Z"}}}}""",
            )
        }

        val tip = adFreeClient(stub).confirmTip("t-1")

        assertTrue(tip!!.isPaid)
        assertEquals("2026-12-14T12:00:00Z", tip.readsAdFreeUntil)
        assertEquals(JsonPrimitive("t-1"), stub.requests.single().variable("tipId"))
    }

    @Test
    fun soapboxQueriesAskForAdFreeFieldsOnlyWhenTheApiHasThem() {
        val newer = SchemaShape(
            mapOf(
                "Article" to setOf("viewerAdFree"),
                "Publication" to setOf("adFreeOffered"),
                "Audience" to setOf("soapbox"),
            ),
        )
        val older = SchemaShape(
            mapOf("Article" to setOf("id"), "Publication" to setOf("id"), "Audience" to setOf("soapbox")),
        )

        assertTrue(SoapboxQueries.article(newer).contains("viewerAdFree"))
        assertTrue(SoapboxQueries.article(newer).contains("acceptsOpEds adFreeOffered"))
        assertFalse(SoapboxQueries.article(older).contains("viewerAdFree"))
        assertTrue(
            SoapboxQueries.publication(newer).contains("adFreeTipCents adFreeDays viewerAdFree viewerAdFreeUntil"),
        )
        assertFalse(SoapboxQueries.publication(older).contains("adFree"))
    }

    @Test
    fun anArticleDecodesWhetherTheReaderTipped() {
        val article = AudienceKitClient.json.decodeFromString(
            Article.serializer(),
            """{"id":"a-1","title":"Pride","publication":{"id":"pub-1","name":"QSaltLake","adFreeOffered":true},"viewerAdFree":true}""",
        )
        assertTrue(article.showsWithoutAds)
        assertEquals(true, article.publication.adFreeOffered)

        val older = AudienceKitClient.json.decodeFromString(
            Article.serializer(),
            """{"id":"a-1","title":"Pride","publication":{"id":"pub-1","name":"QSaltLake"}}""",
        )
        assertFalse(older.showsWithoutAds)
        assertNull(older.publication.adFreeOffered)
    }

    @Test
    fun adFreeTipsAreOfferedInUsStorefrontsOnly() {
        val offered = Publication(id = "p", name = "QSaltLake", adFreeOffered = true, adFreeTipCents = 500)
        assertTrue(AdFreeTips.isOffered(offered, "US"))
        assertTrue(AdFreeTips.isOffered(offered, "usa"))
        assertFalse(AdFreeTips.isOffered(offered, "GB"))
        assertFalse(AdFreeTips.isOffered(offered, null))
        assertFalse(AdFreeTips.isOffered(Publication(id = "p", name = "Q"), "US"))
        assertTrue(AdFreeTips.isOffered(PublicationSummary(id = "p", name = "Q", adFreeOffered = true), "US"))
    }

    @Test
    fun adFreeTipsCopyNamesThePublicationAndTheTerms() {
        assertEquals("Tip QSaltLake to read without ads", AdFreeTips.button("QSaltLake"))
        val explanation = AdFreeTips.explanation("QSaltLake", tipCents = 500, days = 30)
        assertTrue(explanation.contains("$5 or more goes straight to QSaltLake"))
        assertTrue(explanation.contains("without ads for 30 days"))
        assertEquals("$5.50", AdFreeTips.money(550))
        assertEquals("Thanks for supporting QSaltLake. No ads here for you.", AdFreeTips.thanks("QSaltLake", null))
        assertTrue(AdFreeTips.thanks("QSaltLake", "Dec 14, 2026").endsWith("until Dec 14, 2026."))
    }
}
