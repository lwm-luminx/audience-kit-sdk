package com.audiencekit

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject

/**
 * What venue staff do about a message the audience's AI host flagged in their room: the API's `FlaggedMessageAction`
 * (`reviewFlaggedMessage`). Velvet's simple version of the admins' moderation decisions. The same as the Swift SDK's.
 */
@Serializable
public enum class FlaggedMessageAction(
    /** The button's label. */
    public val title: String,
    /** What it did, once done ("Removed"). */
    public val doneTitle: String,
) {
    /** Nothing to do: it leaves the list. */
    DISMISS("Dismiss", "Dismissed"),
    /** Takes the message out of the room for everyone. */
    REMOVE("Remove", "Removed"),
    /** A private line from the venue to the sender, which only they see, and a push. */
    WARN("Warn", "Warned"),
    /** Out of the room for a few minutes ([FlaggedMessages.COOLDOWN_MINUTES] unless the app says). */
    COOLDOWN("Cooldown", "Cooled down"),
    /** Files it in the audience admins' Reports queue for a closer look: the existing flow for anything bigger. */
    ESCALATE("Escalate", "Escalated"),
    /** Bans the sender from the venue. Always confirm first ([FlaggedMessageCopy.BAN_TITLE]). */
    BAN("Ban", "Banned"),
    ;

    /** Whether it acts on the sender or their message; only those that don't apply to someone who runs the room. */
    public val actsOnSender: Boolean get() = this != DISMISS && this != ESCALATE

    /** Whether the app asks before doing it. */
    public val needsConfirmation: Boolean get() = this == BAN

    public companion object {
        /** The one-tap actions, in the order a row offers them. Ban sits apart, behind its own confirmation. */
        public val QUICK: List<FlaggedMessageAction> = listOf(DISMISS, REMOVE, WARN, COOLDOWN)
    }
}

/**
 * A message in a venue's room the AI host flagged or ruled something about, as its staff see it
 * (`Venue.flaggedMessages` on the staff endpoint): the message, why, and what the host suggests.
 */
@Serializable
public data class FlaggedMessage(
    /** For [FlaggedMessages.reviewVariables]. */
    val id: String,
    /** The venue message's ID; null when AudienceKit has no transcript of it. */
    val messageId: String? = null,
    val text: String? = null,
    val sentAt: String? = null,
    val senderId: String? = null,
    /** As the room shows them ("Aurora B."). */
    val senderName: String? = null,
    /** The sender runs the room (staff, a manager, the venue): only DISMISS and ESCALATE apply. */
    val senderRunsRoom: Boolean = false,
    /** Why it was flagged, in a line. */
    val reason: String = "",
    val category: String? = null,
    val categoryTitle: String? = null,
    val ruling: String? = null,
    val confidence: Double? = null,
    val suggestedAction: FlaggedMessageAction = FlaggedMessageAction.DISMISS,
    /** What the server already did about it (the host removed it, a provider banned the sender). */
    val doneActions: List<FlaggedMessageAction> = emptyList(),
    /** Already out of the room. */
    val removed: Boolean = false,
    /** What staff did; null while it waits. */
    val review: FlaggedMessageAction? = null,
    val reviewedAt: String? = null,
    val reviewedByName: String? = null,
    val analyzedAt: String = "",
) {
    /** Still waiting for staff. */
    val isOpen: Boolean get() = review == null

    /**
     * The actions that apply to it, quick ones first: someone who runs the room is only dismissed or escalated, and a
     * message already out of the room isn't removed again.
     */
    val availableActions: List<FlaggedMessageAction>
        get() = FlaggedMessageAction.entries.filter { action ->
            when {
                senderRunsRoom && action.actsOnSender -> false
                action == FlaggedMessageAction.REMOVE && removed -> false
                action == FlaggedMessageAction.ESCALATE && messageId == null -> false
                action.actsOnSender && senderId == null -> false
                else -> true
            }
        }

    /** One line under the message: what the host suggests, and what it already did ("Suggested: Warn · Already removed"). */
    val suggestionLine: String
        get() = buildList {
            add("${FlaggedMessageCopy.SUGGESTED}: ${suggestedAction.title}")
            if (doneActions.isNotEmpty()) add("Already " + doneActions.joinToString(", ") { it.doneTitle.lowercase() })
        }.joinToString(" · ")
}

/**
 * The GraphQL for Velvet's flagged messages, shared by every staff app (and iOS, word for word) so none writes its own.
 * They run on the staff endpoint, which this SDK doesn't call: StaffKit's session sends them with these variables, and
 * [parseList] and [parseReview] read the answers.
 */
public object FlaggedMessages {
    /** A cooldown's length when the app doesn't ask, as the API's default. */
    public const val COOLDOWN_MINUTES: Int = 10

    /** The longest cooldown the API takes. */
    public const val COOLDOWN_MAX_MINUTES: Int = 30

    /** The fields [QUERY] and [REVIEW_MUTATION] read of a flagged message. */
    public const val FLAGGED_MESSAGE_FIELDS: String = "id messageId text sentAt senderId senderName senderRunsRoom reason category categoryTitle ruling confidence suggestedAction doneActions removed review reviewedAt reviewedByName analyzedAt"

    public const val QUERY: String = """
        # endpoint: staff
        query VelvetFlaggedMessages(${'$'}id: ID!, ${'$'}includeReviewed: Boolean) {
          venues { venue(id: ${'$'}id) { flaggedMessages(first: 50, includeReviewed: ${'$'}includeReviewed) {
            totalCount nodes { $FLAGGED_MESSAGE_FIELDS }
          } } }
        }
    """

    public const val REVIEW_MUTATION: String = """
        # endpoint: staff
        mutation VelvetReviewFlaggedMessage(${'$'}input: FlaggedMessageReviewInput!) {
          reviewFlaggedMessage(input: ${'$'}input) { flaggedMessage { $FLAGGED_MESSAGE_FIELDS } }
        }
    """

    private val json = Json { ignoreUnknownKeys = true; coerceInputValues = true }

    /** The variables for [QUERY]. */
    public fun queryVariables(venueId: String, includeReviewed: Boolean = false): Map<String, JsonElement> =
        mapOf("id" to JsonPrimitive(venueId), "includeReviewed" to JsonPrimitive(includeReviewed))

    /** The variables for [REVIEW_MUTATION]: [minutes] is a cooldown's length, [text] a warning's words or an escalation's note. */
    public fun reviewVariables(
        id: String,
        action: FlaggedMessageAction,
        minutes: Int? = null,
        text: String? = null,
    ): Map<String, JsonElement> = mapOf(
        "input" to JsonObject(
            buildMap {
                put("id", JsonPrimitive(id))
                put("action", JsonPrimitive(action.name))
                minutes?.let { put("minutes", JsonPrimitive(it)) }
                text?.trim()?.takeIf { it.isNotEmpty() }?.let { put("text", JsonPrimitive(it)) }
            },
        ),
    )

    /** One `FlaggedMessage` object, as the API sends it. */
    public fun parse(node: JsonObject): FlaggedMessage = json.decodeFromJsonElement(FlaggedMessage.serializer(), node)

    /** [QUERY]'s `data`: the venue's flagged messages, empty when it has none or can't see them. */
    public fun parseList(data: JsonObject): List<FlaggedMessage> {
        val nodes = (data["venues"] as? JsonObject)?.get("venue")?.let { it as? JsonObject }
            ?.get("flaggedMessages")?.let { it as? JsonObject }?.get("nodes") ?: return emptyList()
        return runCatching { nodes.jsonArray.map { parse(it.jsonObject) } }.getOrDefault(emptyList())
    }

    /** [REVIEW_MUTATION]'s `data`: the message as it now stands. */
    public fun parseReview(data: JsonObject): FlaggedMessage? =
        ((data["reviewFlaggedMessage"] as? JsonObject)?.get("flaggedMessage") as? JsonObject)?.let(::parse)
}

/** The words around flagged messages, the same as the Swift SDK's. */
public object FlaggedMessageCopy {
    public const val TITLE: String = "Flagged messages"
    public const val EMPTY: String = "Nothing flagged in the chat. The AI host will put anything that needs a look here."
    public const val SUGGESTED: String = "Suggested"
    public const val MORE: String = "More"
    public const val BAN_TITLE: String = "Ban them from the venue?"
    public const val BAN_DETAIL: String = "They'll be taken out of the chat and stop seeing the venue, its events and " +
        "lineups. You can lift a ban from Bans."
    public const val WARN_TITLE: String = "Warn privately"
    public const val WARN_DETAIL: String = "Only they see it, in the chat and as a notification."
    public const val ESCALATE_TITLE: String = "Escalate to the admins"
    public const val ESCALATE_DETAIL: String = "It goes to the audience's admins to look at. Add a note if it helps."
    public const val ESCALATE_NOTE_PLACEHOLDER: String = "What should they know? (optional)"
    public const val COOLDOWN_TITLE: String = "Cool them down"
    public val COOLDOWN_OPTIONS: List<Int> = listOf(5, 10, 30)
    public const val RUNS_ROOM: String = "From the venue's own people: dismiss it or escalate it."

    /** "10 min", for a cooldown choice. */
    public fun minutes(minutes: Int): String = "$minutes min"

    /** The suggested words for a warning at a venue, which staff can change. */
    public fun defaultWarning(venueName: String): String =
        "A note from the staff at $venueName: please keep the chat friendly and within the house rules."
}
