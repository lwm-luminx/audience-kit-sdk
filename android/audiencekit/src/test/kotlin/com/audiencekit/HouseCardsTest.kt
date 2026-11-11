package com.audiencekit

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

private fun houseClient(stub: StubTransport): AudienceKitClient = AudienceKitClient(
    AudienceKitConfiguration(baseUrl = StubTransport.BASE_URL, audienceId = "b0f8b66a-e636-495d-9475-0f5317ea08e0"),
    InMemoryTokenStore("session-token"),
    stub,
)

private fun RecordedRequest.document(): String = (jsonBody()["query"] as JsonPrimitive).content
private fun RecordedRequest.operation(): String? = (jsonBody()["operationName"] as? JsonPrimitive)?.content

private const val HOUSE_LAYOUT = """
{"data":{"layout":{"id":"lay-1","refreshAfter":60,"cards":[
  {"id":"promo.slot:1","kind":"promo.slot","rank":1,"title":null,"candidates":[
    {"id":"pp-v","category":"audiencekit","label":"From AudienceKit","sponsorName":"AudienceKit",
     "staffApp":"velvet","headline":"Run your venue with Velvet","venue":null,"event":null},
    {"id":"pp-p","category":"audiencekit","label":"From AudienceKit","sponsorName":"AudienceKit",
     "staffApp":"pager","headline":"Powered by AudienceKit","venue":null,"event":null}]}
]}}}
"""

class HouseCardsTest {
    @Test
    fun skipsAudienceKitCardsAboutAStaffAppThePhoneHas() = runTest {
        val stub = StubTransport { StubTransport.json(200, HOUSE_LAYOUT) }
        val layout = houseClient(stub).layout(LayoutScreen.VENUES, listOf("promo.slot"))

        assertTrue("staffApp" in stub.requests.single().document())
        val slot = layout.card("promo.slot")!!
        val velvet = slot.candidates!!.first()
        assertEquals(StaffApp.VELVET, velvet.staffApp)
        assertTrue(velvet.isFromAudienceKit)
        // An app this SDK doesn't know is no staff app at all, so the card always shows.
        assertNull(slot.candidates!!.last().staffApp)

        assertEquals("pp-v", slot.promo(CardFilter())?.id)
        assertEquals("pp-p", slot.promo(CardFilter(installedStaffApps = setOf(StaffApp.VELVET)))?.id)
        assertEquals("pp-v", slot.promo(CardFilter(installedStaffApps = setOf(StaffApp.BACKSTAGE)))?.id)
    }

    @Test
    fun asksAgainWithoutStaffAppsOnAnOlderApi() = runTest {
        val stub = StubTransport { request ->
            when {
                request.operation() == "SchemaFields" -> StubTransport.json(
                    200,
                    """{"data":{"t0":{"fields":[{"name":"id"},{"name":"category"},{"name":"sponsorName"}]}}}""",
                )
                "staffApp" in request.document() -> StubTransport.json(
                    200,
                    """{"errors":[{"message":"Field 'staffApp' doesn't exist on type 'PromoCard'","extensions":{"code":"undefinedField"}}]}""",
                )
                else -> StubTransport.json(200, HOUSE_LAYOUT.replace("\"staffApp\":\"velvet\",", "").replace("\"staffApp\":\"pager\",", ""))
            }
        }

        val layout = houseClient(stub).layout(LayoutScreen.VENUES, listOf("promo.slot"))

        assertEquals(listOf("Layout", "SchemaFields", "Layout"), stub.requests.map { it.operation() })
        assertFalse("staffApp" in stub.requests.last().document())
        assertEquals(listOf("pp-v", "pp-p"), layout.card("promo.slot")?.candidates?.map { it.id })
    }

    @Test
    fun staffAppLinksAndWords() {
        assertEquals("audiencekit-velvet://venue?id=v+1&audience=a-1", StaffApp.velvet("v 1", "a-1"))
        assertEquals("audiencekit-backstage://person?id=p-1", StaffApp.backstage("p-1", null))
        assertEquals("com.audiencekit.Backstage", StaffApp.BACKSTAGE.androidPackage)
        assertEquals("Open in Velvet", StaffApp.VELVET.linkTitle(installed = true))
        assertEquals("Join the Velvet beta", StaffApp.VELVET.linkTitle(installed = false))
        assertEquals("Get Backstage", StaffApp.BACKSTAGE.linkTitle(installed = false))
        assertEquals(StaffApp.FOCUS, StaffApp.fromKey("focus"))
        assertNull(StaffApp.fromKey(null))
        assertEquals(
            "https://audiencekit.com/apps/velvet/?utm_source=com.hotmess&utm_medium=app&utm_campaign=staff_app",
            StaffApp.VELVET.downloadUrl("com.hotmess"),
        )
    }

    @Test
    fun platformCreditWordsAndLinks() {
        assertEquals("Powered by AudienceKit", PlatformCredit.poweredBy)
        assertEquals("A Love Wins Media product", PlatformCredit.product)
        assertEquals("Powered by AudienceKit. A Love Wins Media product.", PlatformCredit.spoken)
        assertEquals("© 2026 Love Wins Media, Inc.", PlatformCredit.copyright(2026))
        assertEquals(listOf("Privacy", "Terms", "Child safety", "Contact"), PlatformCredit.policies.map { it.title })
        assertEquals(
            "https://audiencekit.com/privacy/?utm_source=audiencekit-app&utm_medium=app&utm_campaign=policy",
            PlatformCredit.policyUrl(PlatformCredit.policies.first()),
        )
        assertEquals(
            "https://lovewins.media/?utm_source=com.hotmess&utm_medium=app&utm_campaign=credit",
            PlatformCredit.companyUrl("com.hotmess"),
        )
        assertEquals(
            "https://audiencekit.com/?utm_source=audiencekit-app&utm_medium=app&utm_campaign=venue_cta",
            PlatformCredit.callToActionUrl(""),
        )
    }
}
