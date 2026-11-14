package com.audiencekit

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class FlaggedMessagesTest {
    private val node = """
        {"id":"fa-1","messageId":"m-1","text":"who wants molly","sentAt":"2026-11-14T03:00:00Z","senderId":"u-9",
         "senderName":"Sam R.","senderRunsRoom":false,"reason":"Offering pills","category":"DRUG_SALES",
         "categoryTitle":"Drug sales","ruling":"private_nudge","confidence":0.9,"suggestedAction":"WARN",
         "doneActions":[],"removed":false,"review":null,"reviewedAt":null,"reviewedByName":null,
         "analyzedAt":"2026-11-14T03:00:01Z","somethingNew":1}
    """.trimIndent()

    private fun data(json: String): JsonObject = Json.parseToJsonElement(json).jsonObject

    @Test
    fun readsTheVenuesQueue() {
        val messages = FlaggedMessages.parseList(
            data("""{"venues":{"venue":{"flaggedMessages":{"totalCount":1,"nodes":[$node]}}}}"""),
        )

        val message = messages.single()
        assertEquals("fa-1", message.id)
        assertEquals(FlaggedMessageAction.WARN, message.suggestedAction)
        assertTrue(message.isOpen)
        assertEquals(FlaggedMessageAction.entries, message.availableActions)
        assertEquals("Suggested: Warn", message.suggestionLine)
    }

    @Test
    fun aVenueWithoutTheFieldHasNone() {
        assertTrue(FlaggedMessages.parseList(data("""{"venues":{"venue":null}}""")).isEmpty())
        assertTrue(FlaggedMessages.parseList(data("""{"venues":{"venue":{"flaggedMessages":null}}}""")).isEmpty())
    }

    @Test
    fun aReviewSendsTheActionAndItsDetails() {
        assertEquals(
            JsonObject(mapOf("id" to JsonPrimitive("fa-1"), "action" to JsonPrimitive("COOLDOWN"), "minutes" to JsonPrimitive(5))),
            FlaggedMessages.reviewVariables("fa-1", FlaggedMessageAction.COOLDOWN, minutes = 5, text = "  ")["input"],
        )
        assertEquals(
            JsonObject(mapOf("id" to JsonPrimitive("x"), "action" to JsonPrimitive("WARN"), "text" to JsonPrimitive("Be kind"))),
            FlaggedMessages.reviewVariables("x", FlaggedMessageAction.WARN, text = " Be kind ")["input"],
        )
        val reviewed = node.replace("\"review\":null", "\"review\":\"COOLDOWN\"")
        val message = FlaggedMessages.parseReview(data("""{"reviewFlaggedMessage":{"flaggedMessage":$reviewed}}"""))
        assertEquals(FlaggedMessageAction.COOLDOWN, message?.review)
        assertFalse(message!!.isOpen)
        assertNull(FlaggedMessages.parseReview(data("""{"reviewFlaggedMessage":null}""")))
    }

    @Test
    fun theQueryAndReviewAskForTheSameFields() {
        assertTrue(FlaggedMessages.QUERY.contains("flaggedMessages(first: 50, includeReviewed: \$includeReviewed)"))
        assertTrue(FlaggedMessages.QUERY.contains(FlaggedMessages.FIELDS))
        assertTrue(FlaggedMessages.REVIEW_MUTATION.contains("reviewFlaggedMessage(input: \$input)"))
        assertTrue(FlaggedMessages.REVIEW_MUTATION.contains(FlaggedMessages.FIELDS))
        assertEquals(
            mapOf("id" to JsonPrimitive("v-1"), "includeReviewed" to JsonPrimitive(false)),
            FlaggedMessages.queryVariables("v-1"),
        )
    }

    @Test
    fun theRoomsOwnPeopleAreOnlyDismissedOrEscalated() {
        val message = FlaggedMessage(
            id = "fa-2", messageId = "m-2", senderId = "u-2", senderRunsRoom = true, reason = "Spam",
            suggestedAction = FlaggedMessageAction.REMOVE, doneActions = listOf(FlaggedMessageAction.REMOVE), removed = true,
        )

        assertEquals(listOf(FlaggedMessageAction.DISMISS, FlaggedMessageAction.ESCALATE), message.availableActions)
        assertEquals("Suggested: Remove · Already removed", message.suggestionLine)
        assertEquals(listOf(FlaggedMessageAction.DISMISS), FlaggedMessage(id = "fa-3").availableActions)
    }

    @Test
    fun theCopyMatchesTheActions() {
        assertEquals(
            listOf(FlaggedMessageAction.DISMISS, FlaggedMessageAction.REMOVE, FlaggedMessageAction.WARN, FlaggedMessageAction.COOLDOWN),
            FlaggedMessageAction.QUICK,
        )
        assertTrue(FlaggedMessageAction.BAN.needsConfirmation)
        assertFalse(FlaggedMessageAction.ESCALATE.actsOnSender)
        assertEquals("10 min", FlaggedMessageCopy.minutes(10))
        assertTrue(FlaggedMessageCopy.defaultWarning("Purr").contains("staff at Purr"))
        assertTrue(FlaggedMessageCopy.COOLDOWN_OPTIONS.contains(FlaggedMessages.COOLDOWN_MINUTES))
        assertTrue(FlaggedMessageCopy.COOLDOWN_OPTIONS.all { it <= FlaggedMessages.COOLDOWN_MAX_MINUTES })
    }
}
