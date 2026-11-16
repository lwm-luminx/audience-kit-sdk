package com.audiencekit

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

private fun contactClient(stub: StubTransport): AudienceKitClient = AudienceKitClient(
    AudienceKitConfiguration(baseUrl = StubTransport.BASE_URL, audienceId = "b0f8b66a-e636-495d-9475-0f5317ea08e3"),
    InMemoryTokenStore("session-token"),
    stub,
)

private fun RecordedRequest.document(): String = (jsonBody()["query"] as JsonPrimitive).content
private fun RecordedRequest.operation(): String? = (jsonBody()["operationName"] as? JsonPrimitive)?.content
private fun RecordedRequest.variable(name: String) = jsonBody()["variables"]?.jsonObject?.get(name)

private const val JORDAN_HASH = "568bb17dbe82b2d378c7867777b9e84d8d128b7950fb137fc4e38f4ea808e33c"

private fun stateJson(
    enabled: Boolean = false,
    verified: Boolean = false,
    matches: String = "[]",
    requests: String = "[]",
): String = """{"enabled":$enabled,"phoneVerified":$verified,"phoneNumber":${if (verified) "\"+12065550142\"" else "null"},""" +
    """"firstName":"Danny","lastName":"Ortiz","codeResendAt":"2026-11-16T07:00:30Z","lastCheckedAt":null,""" +
    """"nextCheckAt":"2026-11-16T07:00:00Z","contactsChecked":0,"textCodesAvailable":true,""" +
    """"matches":$matches,"incomingRequests":$requests}"""

/** The same vectors as the Swift SDK's ContactMatchingTests.swift and the API's doc/CONTACT_FRIEND_MATCHING.md. */
class ContactHashingTest {
    @Test
    fun namesNormalizeAsTheApiDoes() {
        assertEquals("joseluis", ContactHashing.normalizeName(" José-Luis "))
        assertEquals("obrien", ContactHashing.normalizeName("O'Brien"))
        assertEquals("asaoberg2", ContactHashing.normalizeName("ÅSA Öberg 2"))
        assertEquals("fiona", ContactHashing.normalizeName("ﬁona"))
        assertEquals("", ContactHashing.normalizeName("李"))
    }

    @Test
    fun aContactHashesToTheDocumentedVector() {
        assertEquals(
            "5e55a1b55a29bb89dcb5e2694e558276db8bed11535dc6c0d96db558acc35339",
            ContactHashing.hash("José-Luis", "O'Brien", "+12065550142"),
        )
        assertEquals(JORDAN_HASH, ContactHashing.hash("Jordan", "Park", "+12065550177"))
    }

    @Test
    fun numbersBecomeE164WithThePhonesRegion() {
        val cases = listOf(
            Triple("(206) 555-0142", "US", "+12065550142"),
            Triple("1-206-555-0142", "us", "+12065550142"),
            Triple("+1 206 555 0142", "GB", "+12065550142"),
            Triple("206.555.0142 x12", "CA", "+12065550142"),
            Triple("011 44 20 7946 0958", "US", "+442079460958"),
            Triple("020 7946 0958", "GB", "+442079460958"),
            Triple("00 1 206 555 0142", "GB", "+12065550142"),
            Triple("0412 345 678", "AU", "+61412345678"),
            Triple("0011 44 20 7946 0958", "AU", "+442079460958"),
            Triple("55 1234 5678", "MX", "+525512345678"),
            Triple("044 55 1234 5678", "MX", "+525512345678"),
            Triple("01 55 1234 5678", "MX", "+525512345678"),
            Triple("06 1234 5678", "IT", "+390612345678"),
            Triple("8 (912) 345-67-89", "RU", "+79123456789"),
            Triple("06 30 123 4567", "HU", "+36301234567"),
            Triple("8 612 34567", "LT", "+37061234567"),
            Triple("8 029 123-45-67", "BY", "+375291234567"),
            Triple("٠٤١٢٣٤٥٦٧٨", "AU", "+61412345678"),
        )
        for ((number, region, expected) in cases) assertEquals(expected, ContactHashing.e164(number, region), number)
    }

    @Test
    fun numbersThatCantBeReadAreSkipped() {
        assertNull(ContactHashing.e164("555-0142", "US"))
        assertNull(ContactHashing.e164("(106) 555-0142", "US"))
        assertNull(ContactHashing.e164("(206) 155-0142", "US"))
        assertNull(ContactHashing.e164("206 555 0142", null))
        assertNull(ContactHashing.e164("206 555 0142", "ZZ"))
        assertNull(ContactHashing.e164("+0 123 456 789", "US"))
        assertNull(ContactHashing.e164("+44 12", "US"))
        assertNull(ContactHashing.e164("", "US"))
        assertEquals("44", ContactHashing.callingCode("gb"))
        assertNull(ContactHashing.callingCode(null))
    }

    @Test
    fun aBatchSkipsContactsWithoutAFullNameOrNumber() {
        val contacts = listOf(
            DeviceContact("Jordan", "Park", listOf("(206) 555-0177", "+1 206 555 0177")),
            DeviceContact("Mom", "", listOf("206-555-0100")),
            DeviceContact("Sam", "Lee", listOf("12")),
            DeviceContact("Rick", "Mark", listOf("206-555-0111", "020 7946 0958")),
        )

        val batch = ContactHashing.batch(contacts, "US")

        assertEquals(2, batch.contactCount)
        assertEquals(1, batch.skippedWithoutFullName)
        assertEquals(1, batch.skippedWithoutNumber)
        assertEquals(2, batch.hashes.size)
        assertEquals(batch.names.keys, batch.hashes.toSet())
        assertEquals("Jordan Park", batch.names[JORDAN_HASH])
        assertEquals("We checked 2 contacts and skipped 1 with only a first name.", ContactMatchingCopy.checked(batch))
    }

    @Test
    fun aBatchStopsAtTheLimit() {
        val contacts = (0 until 5).map {
            DeviceContact("A$it", "B", listOf("20655501${40 + it}", "20655502${40 + it}"))
        }

        val batch = ContactHashing.batch(contacts, "US", limit = 5)

        assertEquals(4, batch.hashes.size)
        assertEquals(2, batch.contactCount)
        assertEquals(3, batch.skippedOverLimit)
        assertEquals("We checked 2 contacts.", ContactMatchingCopy.checked(batch))
    }
}

class ContactMatchingTest {
    @Test
    fun readingContactMatching() = runTest {
        val request = """{"id":"r-1","status":"PENDING","createdAt":"2026-11-16T06:00:00Z","user":{"id":"u-2","name":"Jordan P.","avatarUrl":null},"friend":{"id":"u-1","name":"Danny Ortiz","avatarUrl":null}}"""
        val matches = """[{"status":"INCOMING","user":{"id":"u-2","name":"Jordan P.","avatarUrl":"/a.jpg"},"request":$request}]"""
        val stub = StubTransport {
            StubTransport.json(200, """{"data":{"me":{"contactMatching":${stateJson(true, true, matches, "[$request]")}}}}""")
        }

        val state = contactClient(stub).contactMatching()

        assertTrue(state.enabled && state.phoneVerified)
        assertEquals("+12065550142", state.phoneNumber)
        assertEquals(ContactMatchStatus.INCOMING, state.matches.single().status)
        assertNull(state.matches.single().contactHash)
        assertEquals("Jordan P.", state.incomingRequests.single().user.name)
        assertEquals(FriendRequestStatus.PENDING, state.incomingRequests.single().status)
        assertTrue(state.addable.isEmpty())
        assertFalse(state.canOffer)
        val sent = stub.requests.single()
        assertEquals("ContactMatching", sent.operation())
        assertTrue(sent.document().contains("textCodesAvailable"))
        assertFalse(sent.document().contains("contactHash"))
    }

    @Test
    fun theOfferHidesWhenCodesCantBeTexted() {
        assertTrue(ContactMatching().canOffer)
        assertTrue(ContactMatching(textCodesAvailable = true).canOffer)
        assertFalse(ContactMatching(textCodesAvailable = false).canOffer)
        assertFalse(ContactMatching(enabled = true).canOffer)
    }

    @Test
    fun anOlderApiIsAskedWithoutTheNewFields() = runTest {
        val stub = StubTransport { request ->
            val document = request.document()
            when {
                document.contains("__type") -> StubTransport.json(
                    200,
                    """{"data":{"t0":{"fields":[{"name":"status"}]},"t1":{"fields":[{"name":"enabled"}]}}}""",
                )
                document.contains("textCodesAvailable") -> StubTransport.json(
                    200,
                    """{"errors":[{"message":"Field 'textCodesAvailable' doesn't exist on type 'ContactMatching'","extensions":{"code":"undefinedField"}}]}""",
                )
                else -> StubTransport.json(
                    200,
                    """{"data":{"me":{"contactMatching":{"enabled":false,"phoneVerified":false,"contactsChecked":0,"matches":[],"incomingRequests":[]}}}}""",
                )
            }
        }

        val state = contactClient(stub).contactMatching()

        assertNull(state.textCodesAvailable)
        assertTrue(state.canOffer)
        assertFalse(stub.requests.last().document().contains("textCodesAvailable"))
    }

    @Test
    fun verifyingANumber() = runTest {
        val stub = StubTransport { request ->
            val verify = request.operation() == "VerifyContactPhone"
            val key = if (verify) "verifyContactPhone" else "startContactPhoneVerification"
            StubTransport.json(200, """{"data":{"$key":{"contactMatching":${stateJson(verified = verify)}}}}""")
        }
        val client = contactClient(stub)

        val started = client.startContactPhoneVerification("+12065550142", "Danny", "Ortiz")
        val verified = client.verifyContactPhone("424242")

        assertFalse(started.phoneVerified)
        assertEquals("2026-11-16T07:00:30Z", started.codeResendAt)
        assertTrue(verified.phoneVerified)
        assertEquals(JsonPrimitive("+12065550142"), stub.requests[0].variable("phoneNumber"))
        assertEquals(JsonPrimitive("Danny"), stub.requests[0].variable("firstName"))
        assertEquals(JsonPrimitive("424242"), stub.requests[1].variable("code"))
    }

    @Test
    fun checkingContactsRemembersWhatMatchesAreSavedAs() = runTest {
        val matches = """[{"status":"NONE","contactHash":"$JORDAN_HASH","user":{"id":"u-2","name":"Jordan P.","avatarUrl":null},"request":null}]"""
        val stub = StubTransport {
            StubTransport.json(
                200,
                """{"data":{"checkContacts":{"matches":$matches,"contactMatching":${stateJson(true, true, matches)}}}}""",
            )
        }
        val names = ContactMatchNames(InMemoryContactMatchNameStore())
        val batch = ContactHashing.batch(listOf(DeviceContact("Jordan", "Park", listOf("206-555-0177"))), "US")

        val result = contactClient(stub).checkContacts(batch, names)

        assertEquals(listOf("u-2"), result.matches.map { it.user.id })
        assertEquals(1, result.contactMatching.addable.size)
        assertEquals("Jordan Park", names.name("u-2"))
        assertEquals("In your contacts as Jordan Park", ContactMatchingCopy.savedAs(names.name("u-2")!!))
        val sent = stub.requests.single()
        assertEquals("CheckContacts", sent.operation())
        assertEquals(JsonArray(listOf(JsonPrimitive(JORDAN_HASH))), sent.variable("hashes"))
        assertEquals(JsonPrimitive(1), sent.variable("contactCount"))
        assertTrue(sent.document().contains("contactHash"))

        names.record(emptyList(), batch)
        assertNull(names.name("u-2"))
    }

    @Test
    fun requestsNamesAndTurningOff() = runTest {
        val stub = StubTransport { request ->
            val name = request.operation()!!
            val key = name.replaceFirstChar { it.lowercase() }
            StubTransport.json(
                200,
                """{"data":{"$key":{"contactMatching":${stateJson(name != "DisableContactMatching", true)}}}}""",
            )
        }
        val file = File.createTempFile("contact-names", ".json").also { it.delete() }
        val names = ContactMatchNames(FileContactMatchNameStore(file))
        names.record(
            listOf(ContactMatch(Profile("u-2", "Jordan P."), ContactMatchStatus.NONE, contactHash = "h")),
            ContactHashBatch(listOf("h"), 1, names = mapOf("h" to "Jordan Park")),
        )
        val client = contactClient(stub)

        client.sendFriendRequest("u-2")
        client.respondToFriendRequest("r-1", accept = false)
        client.setContactMatchName("Daniel", "Ortiz")
        assertEquals("Jordan Park", ContactMatchNames(FileContactMatchNameStore(file)).name("u-2"))
        val off = client.disableContactMatching(names)

        assertFalse(off.enabled)
        assertNull(names.name("u-2"))
        assertFalse(file.exists())
        assertEquals(
            listOf("SendFriendRequest", "RespondToFriendRequest", "SetContactMatchName", "DisableContactMatching"),
            stub.requests.map { it.operation() },
        )
        assertEquals(JsonPrimitive("u-2"), stub.requests[0].variable("userId"))
        assertEquals(JsonPrimitive("r-1"), stub.requests[1].variable("requestId"))
        assertEquals(JsonPrimitive(false), stub.requests[1].variable("accept"))
        assertEquals(JsonPrimitive("Daniel"), stub.requests[2].variable("firstName"))
    }

    @Test
    fun anAudienceWithoutMatchingThrows() = runTest {
        val stub = StubTransport { StubTransport.json(200, """{"data":{"me":null}}""") }

        assertFailsWith<ContactMatchingUnavailableException> { contactClient(stub).contactMatching() }
    }

    @Test
    fun theCopyCountsFriends() {
        assertEquals("1 friend is here", ContactMatchingCopy.friendsHere(1))
        assertEquals("4 friends are here", ContactMatchingCopy.friendsHere(4))
        assertEquals("Add 1 friend", ContactMatchingCopy.addFriends(1))
        assertEquals("Add 2 friends", ContactMatchingCopy.addFriends(2))
    }
}
