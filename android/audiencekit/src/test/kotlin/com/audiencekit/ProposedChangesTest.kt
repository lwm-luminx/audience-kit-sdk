package com.audiencekit

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ProposedChangesTest {
    private fun data(json: String): JsonObject = Json.parseToJsonElement(json).jsonObject

    private val queue = """
    {"submissions":{"totalCount":31,"nodes":[
     {"id":"s-1","kind":"SOCIAL_LINK","status":"IN_REVIEW","risk":"normal","createdAt":"2026-11-04T02:10:00Z",
      "decidedAt":null,"proposed":{"provider":"instagram","handle":"murrayhill"},"current":{"handle":"oldhill"},
      "choices":["murrayhill","murrayhillnyc"],
      "choiceProfiles":[{"username":"murrayhill","status":"ready","name":"Murray Hill","pictureUrl":null,
       "biography":"Comedian","followersCount":1200,"postsCount":40,"imageUrls":["https://x/1.jpg"],"error":null}],
      "body":null,"evidence":[],"submitterRole":"system","reporterCount":1,"disputeCount":0,
      "person":{"id":"p-1","name":"Murray Hill"},"venue":null,"event":null,"locale":{"id":"l-1","name":"New York"},
      "research":[],"decisions":[]},
     {"id":"s-2","kind":"CORRECTION","status":"IN_REVIEW","risk":"high","createdAt":"2026-11-04T02:10:00Z",
      "decidedAt":null,"proposed":{"phone":"555-1234","opening_hours":"Daily 4pm","is_open":false},
      "current":{"phone":"555-0000"},"choices":[],"choiceProfiles":[],"body":"Their number changed",
      "evidence":[{"kind":"link","url":"https://wildrose.com/contact"},{"kind":"photo","photoUrl":"https://cdn/p.jpg"}],
      "submitterRole":"attendee","reporterCount":3,"disputeCount":2,"person":null,
      "venue":{"id":"v-1","name":"The Wildrose"},"event":null,"locale":null,
      "research":[{"summary":"The site lists the new number","recommendation":"needs_venue"}],"decisions":[]},
     null]}}
    """

    @Test
    fun theQueueReadsSocialProfilesAndCorrections() {
        val page = ProposedChanges.parseQueue(data(queue))
        assertEquals(31, page.totalCount)
        assertEquals(2, page.changes.size)

        val social = page.changes[0]
        assertTrue(social.isSocialLink && social.isWaiting && !social.canAskVenue)
        assertEquals("Instagram for Murray Hill", social.title)
        assertEquals("From an import · New York", social.source)
        assertEquals("murrayhill", social.proposedHandle)
        assertEquals("oldhill", social.currentHandle)
        assertEquals(listOf("murrayhillnyc"), social.uncardedChoices)
        assertEquals(1200, social.choiceProfiles[0].followersCount)
        assertFalse(social.isReadingProfiles)
        assertEquals("https://www.instagram.com/murrayhill/", social.profileUrl("murrayhill"))
        assertEquals("Now: @oldhill · Found: @murrayhill, @murrayhillnyc", ProposedChangesCopy.socialLine(social))
        assertEquals("Not a match", ProposedChanges.suggestedRejectReason(social))

        val correction = page.changes[1]
        assertEquals("Correction: The Wildrose", correction.title)
        assertEquals("From 3 people", correction.source)
        assertTrue(correction.isHighRisk && correction.canAskVenue)
        assertEquals(
            listOf(
                ProposedChange.Change("is_open", null, "No"),
                ProposedChange.Change("opening_hours", null, "Daily 4pm"),
                ProposedChange.Change("phone", "555-0000", "555-1234"),
            ),
            correction.changes,
        )
        assertEquals("Opening hours", correction.changes[1].title)
        assertEquals(listOf("https://wildrose.com/contact", "https://cdn/p.jpg"), correction.evidenceLinks)
        assertEquals("Research (needs venue): The site lists the new number", correction.researchLine)
        assertNull(correction.decisionLine)
        assertEquals(0, ProposedChanges.parseQueue(data("""{"submissions":null}""")).totalCount)
    }

    @Test
    fun aDecidedChangeSaysWhoDecided() {
        val change = ProposedChanges.parseQueue(data("""
            {"submissions":{"totalCount":1,"nodes":[{"id":"s-3","kind":"TRIBE_SUGGESTION","status":"REJECTED",
             "risk":"low","createdAt":"2026-11-04T02:10:00Z","decidedAt":"2026-11-05T02:10:00Z",
             "proposed":{"tribe_name":"Bears"},"current":{},"choices":[],"choiceProfiles":[],"body":null,
             "evidence":null,"submitterRole":"martian","reporterCount":1,"disputeCount":0,"person":null,"venue":null,
             "event":null,"locale":null,"research":[],"decisions":[{"action":"REJECT","reason":"Already there",
             "createdAt":"2026-11-05T02:10:00Z","reviewer":{"id":"u-1","name":"Rick M."}}]}]}}
        """)).changes.single()
        assertEquals("Tribe: Bears", change.title)
        assertEquals("From someone", change.source)
        assertFalse(change.isOpen || change.isWaiting)
        assertEquals("Rejected by Rick M. · Already there", change.decisionLine)
        assertTrue(change.evidenceLinks.isEmpty())
    }

    @Test
    fun decidingSendsTheActionAndWhatToApply() {
        val change = ProposedChanges.parseQueue(data(queue)).changes.first()
        assertEquals(mapOf("open" to JsonPrimitive(false), "first" to JsonPrimitive(24)), ProposedChanges.queueVariables(false))
        assertEquals(
            mapOf("id" to JsonPrimitive("s-1"), "action" to JsonPrimitive("APPROVE"), "proposed" to JsonNull, "reason" to JsonNull),
            ProposedChanges.approveVariables(change),
        )
        assertEquals(JsonPrimitive("APPROVE"), ProposedChanges.approveVariables(change, "@murrayhill")["action"])
        val other = ProposedChanges.approveVariables(change, "https://www.instagram.com/murrayhillnyc/")
        assertEquals(JsonPrimitive("EDIT_APPROVE"), other["action"])
        assertEquals(
            JsonObject(mapOf("provider" to JsonPrimitive("instagram"), "handle" to JsonPrimitive("murrayhillnyc"))),
            other["proposed"],
        )
        assertEquals(JsonPrimitive("Not her"), ProposedChanges.rejectVariables(change, "  Not her  ")["reason"])
        assertEquals(JsonPrimitive("NEEDS_VENUE"), ProposedChanges.askVenueVariables(change)["action"])
        assertEquals(mapOf("id" to JsonPrimitive("h-1")), ProposedChanges.idVariables("h-1"))
        assertEquals("murray", ProposedChanges.handle("tiktok.com/@murray"))
        assertEquals("murray", ProposedChanges.handle(" @@murray "))
        assertEquals("@murrayhillnyc is now Murray Hill’s Instagram.", ProposedChangesCopy.handleApproved(change, "@murrayhillnyc"))
        assertEquals("APPROVED", ProposedChanges.parseDecided(data("""{"decideSubmission":{"submission":{"id":"s-1","status":"APPROVED","decidedAt":null}}}""")))
        assertNull(ProposedChanges.parseDecided(data("""{"decideSubmission":null}""")))
        assertEquals(31, ProposedChanges.parseOpenCount(data("""{"submissions":{"totalCount":31}}""")))
        assertEquals(0, ProposedChanges.parseOpenCount(data("""{}""")))
    }

    @Test
    fun headshotsAndDismissalsParse() {
        val headshots = ProposedChanges.parseHeadshots(data("""
            {"headshotsToReview":[{"id":"h-1","url":"https://cdn/h.jpg","origin":"instagram","sourceUrl":null,
             "person":{"id":"p-1","name":"Murray Hill"}},{"id":"h-2","url":"https://cdn/w.jpg","origin":"worker",
             "sourceUrl":"https://example.com","person":{"id":"p-2","name":null}},{"id":"h-3"}]}
        """))
        assertEquals(listOf("From their Instagram", "Found by a worker"), headshots.map { it.originTitle })
        assertTrue(ProposedChanges.parseHeadshots(data("""{"headshotsToReview":null}""")).isEmpty())
        assertEquals("Approved for them. Its cut-out is on the way.", ProposedChangesCopy.headshotApproved(null))

        val dismissals = ProposedChanges.parseDismissedDuplicates(data("""
            {"venues":{"dismissedDuplicates":[
             {"id":"d-1","active":true,"note":"Two floors","dismissedAt":"2026-11-08T08:00:00Z",
              "dismissedBy":{"id":"u-1","name":"Rick M."},"reasons":["SAME_NAME"],"currentReasons":["SAME_NAME"],
              "venues":[{"id":"a","name":"The Edge"},{"id":"b","name":"Edge NYC"}]},
             {"id":"d-2","active":false,"note":null,"dismissedAt":"2026-11-08T08:00:00Z","dismissedBy":null,
              "reasons":["SAME_PLACE"],"currentReasons":[],"venues":[{"id":"c","name":null}]}]}}
        """))
        assertEquals(listOf("d-1"), dismissals.filter { it.active }.map { it.id })
        assertEquals("The Edge and Edge NYC", dismissals[0].title)
        assertEquals("Dismissed by Rick M. · Two floors · Still: Same name in the same locale", dismissals[0].detail)
        assertEquals("Dismissed by an admin · No longer look alike", dismissals[1].detail)
        assertTrue(ProposedChanges.parseDismissedDuplicates(data("""{"venues":null}""")).isEmpty())
    }

    @Test
    fun theCopyCountsWhatIsLeft() {
        assertEquals("Showing 24 of 31. Decide these to see the rest.", ProposedChangesCopy.showing(24, 31, true))
        assertEquals("Showing 24 of 31.", ProposedChangesCopy.showing(24, 31, false))
        assertEquals("2 say it’s wrong.", ProposedChangesCopy.disputes(2))
        assertEquals("Apple Music", ProposedChanges.networkTitle("apple_music"))
        assertNull(ProposedChanges.networkTitle("myspace"))
        assertEquals("In review", ProposedChange("s", "CORRECTION", "IN_REVIEW").statusTitle)
        assertEquals("Odd", ProposedChange("s", "CORRECTION", "ODD").statusTitle)
    }
}
