package com.audiencekit

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

private fun adsClient(stub: StubTransport): AudienceKitClient = AudienceKitClient(
    AudienceKitConfiguration(baseUrl = StubTransport.BASE_URL, audienceId = "b0f8b66a-e636-495d-9475-0f5317ea0898"),
    InMemoryTokenStore("session-token"),
    stub,
)

private const val AD_JSON = """
{"id":"ad-1","category":"small_business","label":"Ad","sponsorName":"Club Verse","soldBy":"QSaltLake",
 "headline":"Two-for-one Thursdays","body":null,"imageUrl":null,"imageAlt":null,"linkUrl":"https://verse.example",
 "linkLabel":"See the menu"}
"""

class PublisherAdsTest {
    @Test
    fun anArticlesPublisherAdDecodesWithWhoSoldIt() = runTest {
        val stub = StubTransport {
            StubTransport.json(200, """{"data":{"soapbox":{"article":{"id":"a-1","ad":$AD_JSON}}}}""")
        }

        val ad = assertNotNull(adsClient(stub).publisherAdForArticle("a-1"))

        assertEquals("Ad", ad.label)
        assertEquals("QSaltLake", ad.soldBy)
        assertTrue(ad.isPublisherAd)
        assertEquals("Two-for-one Thursdays", ad.content.headline)
        assertEquals("Sold by QSaltLake", PublisherAdCopy.soldBy("QSaltLake"))
        assertEquals("ArticleAd", (stub.requests.first().jsonBody()["operationName"] as JsonPrimitive).content)
    }

    @Test
    fun noPublisherAdIsNull() = runTest {
        val stub = StubTransport {
            StubTransport.json(200, """{"data":{"soapbox":{"publication":{"id":"p-1","ad":null}}}}""")
        }

        assertNull(adsClient(stub).publisherAdForPublication("p-1"))
    }

    @Test
    fun anAudienceCardIsNotAPublisherAd() {
        val card = PromoCard("c", "health", "Promoted", "Clinic", CardContent("Free testing"))
        assertFalse(card.isPublisherAd)
        assertTrue(PublisherAdCopy.why("QSaltLake").contains("keeps all of the money"))
    }
}
