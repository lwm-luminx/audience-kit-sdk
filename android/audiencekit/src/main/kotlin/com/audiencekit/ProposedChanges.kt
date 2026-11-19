package com.audiencekit

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import java.net.URI

/** What a reviewer decides about a proposed change: the API's `SubmissionDecisionAction` (`decideSubmission`). */
public enum class ProposedChangeAction {
    /** Apply it as proposed. */
    APPROVE,
    /** Apply the reviewer's version instead (a social profile's other handle). */
    EDIT_APPROVE,
    /** Ask the venue's staff to confirm it first. */
    NEEDS_VENUE,
    /** Don't apply it; needs a reason, which whoever suggested it sees. */
    REJECT,
}

/**
 * A change waiting for a person before it reaches a live listing, the web console's Proposed changes: a profile an
 * import wasn't sure of, a member's correction, a missing venue or event, a closure, a tag or a tribe. The API's
 * `Submission` (audience_kit_api doc/CONTRIBUTIONS.md), read on the staff endpoint by audience administrators. The same
 * as the Swift SDK's.
 */
public data class ProposedChange(
    val id: String,
    /** `SubmissionKind`: SOCIAL_LINK, CORRECTION, MISSING_VENUE, MISSING_EVENT, CLOSED, TAG_SUGGESTION, … */
    val kind: String,
    /** `SubmissionStatus`: SUBMITTED, RESEARCHING, IN_REVIEW, NEEDS_VENUE, APPROVED, REJECTED, MERGED. */
    val status: String,
    /** low, normal or high. */
    val risk: String = "normal",
    val createdAt: String = "",
    val decidedAt: String? = null,
    val proposed: JsonObject = JsonObject(emptyMap()),
    val current: JsonObject = JsonObject(emptyMap()),
    /** For a social profile: the handles found, the proposed one first. */
    val choices: List<String> = emptyList(),
    val choiceProfiles: List<Profile> = emptyList(),
    /** What the submitter wrote. */
    val body: String? = null,
    /** Links and photos: [{kind, url, photoId, photoUrl}]. */
    val evidence: List<JsonObject> = emptyList(),
    /** attendee, talent, venue_staff, admin or system. */
    val submitterRole: String = "",
    val reporterCount: Int = 1,
    val disputeCount: Int = 0,
    val person: Listing? = null,
    val venue: Listing? = null,
    val event: Listing? = null,
    val locale: Listing? = null,
    val research: List<Research> = emptyList(),
    val decisions: List<Decision> = emptyList(),
) {
    /** A listing it's about: a person, venue, event or locale. */
    public data class Listing(val id: String, val name: String?)

    /** What an Instagram account looks like, read in the background (`SocialProfilePreview`). */
    public data class Profile(
        val username: String,
        /** pending, ready, failed or unavailable. */
        val status: String = "ready",
        val name: String? = null,
        val pictureUrl: String? = null,
        val biography: String? = null,
        val followersCount: Int? = null,
        val postsCount: Int? = null,
        val imageUrls: List<String> = emptyList(),
        val error: String? = null,
    ) {
        val isPending: Boolean get() = status == "pending"
    }

    /** What researching it found; [recommendation] is approve, reject, needs_venue or unsure. */
    public data class Research(val summary: String?, val recommendation: String?)

    /** A decision on it. */
    public data class Decision(val action: String, val reason: String?, val createdAt: String, val reviewer: Listing?)

    /** One field it changes: from what (null when the listing has no such field yet) to what. */
    public data class Change(val field: String, val from: String?, val to: String) {
        /** "Opening hours" for `opening_hours`. */
        val title: String get() = this.field.replace('_', ' ').replaceFirstChar { it.uppercase() }
    }

    val isSocialLink: Boolean get() = kind == "SOCIAL_LINK"
    val isHighRisk: Boolean get() = risk == "high"
    val isOpen: Boolean get() = decidedAt == null
    /** Still waiting on a reviewer here: open, and not handed to the venue's staff. */
    val isWaiting: Boolean get() = isOpen && status != "NEEDS_VENUE"
    /** Whether "Ask the venue" makes sense: a change about a venue, not a social profile. */
    val canAskVenue: Boolean get() = isWaiting && !isSocialLink && venue != null

    /** For a social profile: the network (instagram, tiktok, …). */
    val provider: String? get() = proposed.text("provider")
    /** For a social profile: the handle it proposes. */
    val proposedHandle: String? get() = proposed.text("handle")
    /** For a social profile: the listing's handle now. */
    val currentHandle: String? get() = current.text("handle")
    /** For a social profile: the handles found that have no profile card, which get their own button. */
    val uncardedChoices: List<String> get() = choiceProfiles.map { it.username }.toSet().let { carded -> choices.filter { it !in carded } }
    /** Whether any profile is still being read, so the queue should look again shortly. */
    val isReadingProfiles: Boolean get() = choiceProfiles.any { it.isPending }

    /** What it would change, field by field, in the API's order. */
    val changes: List<Change>
        get() = proposed.keys.sorted().map { field -> Change(field, current[field]?.let(::show), show(proposed.getValue(field))) }

    /** The evidence's links, to look at. */
    val evidenceLinks: List<String> get() = evidence.mapNotNull { it.text("url") ?: it.text("photoUrl") }

    /** The listing it's about. */
    val subject: Listing? get() = person ?: event ?: venue

    /** "Instagram for Murray Hill", "Correction: The Wildrose". */
    val title: String
        get() {
            val about = subject?.name
            if (isSocialLink) return "${ProposedChanges.networkTitle(provider) ?: "Profile"} for ${about ?: "a listing"}"
            val kindTitle = ProposedChanges.kindTitle(kind)
            val name = about ?: proposed.text("name") ?: proposed.text("tribe_name")
            return name?.let { "$kindTitle: $it" } ?: kindTitle
        }

    /** "From an import · Seattle", "From 3 people". */
    val source: String
        get() {
            val who = if (reporterCount > 1) "$reporterCount people" else ProposedChanges.roleTitle(submitterRole)
            return listOfNotNull("From $who", locale?.name).joinToString(" · ")
        }

    /** The status in words: "In review", "Asked the venue", "Approved". */
    val statusTitle: String get() = ProposedChanges.statusTitle(status)

    /** The latest research's summary, with its recommendation: "Research (needs venue): …". */
    val researchLine: String?
        get() {
            val latest = research.lastOrNull() ?: return null
            val summary = latest.summary?.takeIf { it.isNotEmpty() } ?: return null
            val recommendation = latest.recommendation?.let { " (${it.replace('_', ' ')})" }.orEmpty()
            return "Research$recommendation: $summary"
        }

    /** Who decided and why: "Approved by Rick M.", "Rejected by Rick M. · Not a match". */
    val decisionLine: String?
        get() {
            if (decidedAt == null) return null
            val decision = decisions.lastOrNull() ?: return null
            val line = "$statusTitle by ${decision.reviewer?.name ?: "an admin"}"
            return decision.reason?.takeIf { it.isNotEmpty() }?.let { "$line · $it" } ?: line
        }

    /** The profile page for [handle] on this change's network, where the network has one. */
    public fun profileUrl(handle: String): String? = ProposedChanges.profileUrl(provider, handle)

    private fun show(value: JsonElement): String = when (value) {
        is JsonNull -> "—"
        is JsonPrimitive -> when {
            value.isString -> value.content.ifEmpty { "—" }
            value.booleanOrNull != null -> if (value.booleanOrNull == true) "Yes" else "No"
            else -> value.content
        }
        is JsonArray -> value.joinToString(", ") { show(it) }
        is JsonObject -> value.toString()
    }
}

/**
 * A performer's headshot found elsewhere (their own Instagram posts, or a worker's find) that nobody has approved yet:
 * `headshotsToReview`. Approving lets posters use it; removing drops it.
 */
public data class HeadshotToReview(
    val id: String,
    val url: String,
    /** instagram or worker. */
    val origin: String,
    val sourceUrl: String?,
    val person: ProposedChange.Listing,
) {
    /** "From their Instagram" or "Found by a worker". */
    val originTitle: String get() = if (origin == "instagram") "From their Instagram" else "Found by a worker"
}

/** Two venues someone said are different places (`venues { dismissedDuplicates }`), kept so the call can be undone. */
public data class VenueDuplicateDismissal(
    val id: String,
    val active: Boolean,
    val note: String?,
    val dismissedAt: String,
    val dismissedBy: ProposedChange.Listing?,
    val reasons: List<VenueDuplicateReason>,
    /** Why they look the same today; empty when they no longer do. */
    val currentReasons: List<VenueDuplicateReason>,
    val venues: List<VenueDuplicate.Venue>,
) {
    /** "The Edge and Edge NYC". */
    val title: String get() = venues.joinToString(" and ") { it.name ?: "Unnamed venue" }

    /** "Dismissed by Rick M. · Two floors · No longer look alike". */
    val detail: String
        get() = buildList {
            add("Dismissed by ${dismissedBy?.name ?: "an admin"}")
            note?.takeIf { it.isNotEmpty() }?.let(::add)
            add(if (currentReasons.isEmpty()) "No longer look alike" else "Still: " + currentReasons.joinToString(", ") { it.title })
        }.joinToString(" · ")
}

/** A page of the queue: [ProposedChanges.QUEUE_QUERY]'s answer. */
public data class ProposedChangesPage(val changes: List<ProposedChange>, val totalCount: Int)

/**
 * The GraphQL for reviewing an audience's proposed changes and headshots, and undoing "Not a duplicate", from a staff
 * app (Focus), as the web console's Proposed changes and Venues pages do: shared so no app writes its own, and the same
 * as the Swift SDK's. They run on the staff endpoint, which this SDK doesn't call: StaffKit's session sends them, and
 * the `parse` functions read the answers. The API decides who may: the queue needs `audience:moderate:*`, undoing a
 * dismissal `venues:write:*`.
 */
public object ProposedChanges {
    /** 24 rows keep the query within a moderator's complexity budget, as on the console; deciding brings in the rest. */
    public const val PAGE_SIZE: Int = 24

    public const val QUEUE_QUERY: String = """
        # endpoint: staff
        query FocusProposedChanges(${'$'}open: Boolean!, ${'$'}first: Int!) {
          submissions(open: ${'$'}open, first: ${'$'}first) {
            totalCount
            nodes {
              id kind status risk createdAt decidedAt proposed current choices
              choiceProfiles { username status name pictureUrl biography followersCount postsCount imageUrls error }
              body evidence submitterRole reporterCount disputeCount person { id name } venue { id name }
              event { id name } locale { id name } research { summary recommendation }
              decisions { action reason createdAt reviewer { id name } }
            }
          }
        }
    """

    /** How many are waiting, for a badge. */
    public const val OPEN_COUNT_QUERY: String = """
        # endpoint: staff
        query FocusProposedChangesCount { submissions(open: true, first: 1) { totalCount } }
    """

    public const val DECIDE_MUTATION: String = """
        # endpoint: staff
        mutation FocusDecideProposedChange(${'$'}id: ID!, ${'$'}action: SubmissionDecisionAction!, ${'$'}proposed: JSON, ${'$'}reason: String) {
          decideSubmission(input: { id: ${'$'}id, action: ${'$'}action, proposed: ${'$'}proposed, reason: ${'$'}reason }) {
            submission { id status decidedAt }
          }
        }
    """

    public const val HEADSHOTS_QUERY: String = """
        # endpoint: staff
        query FocusHeadshotsToReview { headshotsToReview(limit: 24) { id url origin sourceUrl person { id name } } }
    """

    public const val APPROVE_HEADSHOT_MUTATION: String = """
        # endpoint: staff
        mutation FocusApproveHeadshot(${'$'}id: ID!) { setPersonHeadshotApproval(input: { id: ${'$'}id, approved: true }) { person { id } } }
    """

    public const val REMOVE_HEADSHOT_MUTATION: String = """
        # endpoint: staff
        mutation FocusRemoveHeadshot(${'$'}id: ID!) { removePersonHeadshot(input: { id: ${'$'}id }) { person { id } } }
    """

    public const val DISMISSED_DUPLICATES_QUERY: String = """
        # endpoint: staff
        query FocusDismissedVenueDuplicates {
          venues { dismissedDuplicates { id active note dismissedAt dismissedBy { id name } reasons currentReasons venues { id name } } }
        }
    """

    public const val RESTORE_DUPLICATE_MUTATION: String = """
        # endpoint: staff
        mutation FocusRestoreVenueDuplicate(${'$'}id: ID!) { restoreVenueDuplicate(input: { id: ${'$'}id }) { clientMutationId } }
    """

    /** The variables for [QUEUE_QUERY]: open ones (first in line first), or decided ones (newest first). */
    public fun queueVariables(open: Boolean, first: Int = PAGE_SIZE): Map<String, JsonElement> =
        mapOf("open" to JsonPrimitive(open), "first" to JsonPrimitive(first))

    /** The variables for [DECIDE_MUTATION] approving it as proposed. */
    public fun approveVariables(change: ProposedChange): Map<String, JsonElement> = decideVariables(change.id, ProposedChangeAction.APPROVE)

    /**
     * The variables for [DECIDE_MUTATION] approving a social profile with [handle]: as proposed when it is the proposed
     * one, else EDIT_APPROVE with {provider, handle}. A pasted profile link or "@" is trimmed to the handle.
     */
    public fun approveVariables(change: ProposedChange, handle: String): Map<String, JsonElement> {
        val chosen = handle(handle)
        if (chosen == change.proposedHandle) return approveVariables(change)
        return decideVariables(change.id, ProposedChangeAction.EDIT_APPROVE,
            proposed = JsonObject(mapOf("provider" to JsonPrimitive(change.provider.orEmpty()), "handle" to JsonPrimitive(chosen))))
    }

    /** The variables for [DECIDE_MUTATION] rejecting it; [reason] is required, and whoever suggested it sees it. */
    public fun rejectVariables(change: ProposedChange, reason: String): Map<String, JsonElement> =
        decideVariables(change.id, ProposedChangeAction.REJECT, reason = reason.trim())

    /** The variables for [DECIDE_MUTATION] asking the venue's staff to confirm it. */
    public fun askVenueVariables(change: ProposedChange): Map<String, JsonElement> = decideVariables(change.id, ProposedChangeAction.NEEDS_VENUE)

    /** The variables for [DECIDE_MUTATION]. */
    public fun decideVariables(
        id: String,
        action: ProposedChangeAction,
        proposed: JsonElement? = null,
        reason: String? = null,
    ): Map<String, JsonElement> = mapOf(
        "id" to JsonPrimitive(id),
        "action" to JsonPrimitive(action.name),
        "proposed" to (proposed ?: JsonNull),
        "reason" to (reason?.let(::JsonPrimitive) ?: JsonNull),
    )

    /** The variables for the headshot mutations and [RESTORE_DUPLICATE_MUTATION]. */
    public fun idVariables(id: String): Map<String, JsonElement> = mapOf("id" to JsonPrimitive(id))

    /** The reject reason to start from: an import's proposal is usually just not a match. */
    public fun suggestedRejectReason(change: ProposedChange): String = if (change.submitterRole == "system") "Not a match" else ""

    /** `@murrayhill`, `instagram.com/murrayhill/` or `https://www.tiktok.com/@murrayhill` → `murrayhill`. */
    public fun handle(text: String): String {
        var handle = text.trim()
        if ("/" in handle) {
            val path = runCatching { URI(if ("://" in handle) handle else "https://$handle").path }.getOrNull()
            path?.split('/')?.firstOrNull { it.isNotEmpty() }?.let { handle = it }
        }
        return handle.trimStart('@')
    }

    /** [QUEUE_QUERY]'s `data`; empty for someone who isn't allowed to see it. */
    public fun parseQueue(data: JsonObject): ProposedChangesPage {
        val connection = data["submissions"] as? JsonObject ?: return ProposedChangesPage(emptyList(), 0)
        val nodes = (connection["nodes"] as? JsonArray).orEmpty().mapNotNull { parseChange(it as? JsonObject) }
        return ProposedChangesPage(nodes, connection.int("totalCount") ?: nodes.size)
    }

    /** [OPEN_COUNT_QUERY]'s `data`. */
    public fun parseOpenCount(data: JsonObject): Int = (data["submissions"] as? JsonObject)?.int("totalCount") ?: 0

    /** [HEADSHOTS_QUERY]'s `data`. */
    public fun parseHeadshots(data: JsonObject): List<HeadshotToReview> =
        (data["headshotsToReview"] as? JsonArray).orEmpty().mapNotNull { row ->
            val obj = row as? JsonObject ?: return@mapNotNull null
            HeadshotToReview(
                id = obj.text("id") ?: return@mapNotNull null,
                url = obj.text("url") ?: return@mapNotNull null,
                origin = obj.text("origin").orEmpty(),
                sourceUrl = obj.text("sourceUrl"),
                person = listing(obj["person"] as? JsonObject) ?: return@mapNotNull null,
            )
        }

    /** [DISMISSED_DUPLICATES_QUERY]'s `data`, the ones still standing first, newest first, as the API sends them. */
    public fun parseDismissedDuplicates(data: JsonObject): List<VenueDuplicateDismissal> {
        val rows = (data["venues"] as? JsonObject)?.get("dismissedDuplicates") as? JsonArray ?: return emptyList()
        return rows.mapNotNull { row ->
            val obj = row as? JsonObject ?: return@mapNotNull null
            VenueDuplicateDismissal(
                id = obj.text("id") ?: return@mapNotNull null,
                active = (obj["active"] as? JsonPrimitive)?.booleanOrNull ?: false,
                note = obj.text("note"),
                dismissedAt = obj.text("dismissedAt").orEmpty(),
                dismissedBy = listing(obj["dismissedBy"] as? JsonObject),
                reasons = reasons(obj["reasons"]),
                currentReasons = reasons(obj["currentReasons"]),
                venues = (obj["venues"] as? JsonArray).orEmpty().mapNotNull { venue ->
                    (venue as? JsonObject)?.let { v -> v.text("id")?.let { VenueDuplicate.Venue(it, v.text("name")) } }
                },
            )
        }
    }

    /** [DECIDE_MUTATION]'s `data`: the decided change's status, or null when nothing was decided. */
    public fun parseDecided(data: JsonObject): String? =
        ((data["decideSubmission"] as? JsonObject)?.get("submission") as? JsonObject)?.text("status")

    internal fun kindTitle(kind: String): String = when (kind) {
        "SOCIAL_LINK" -> "Social profile"
        "CORRECTION" -> "Correction"
        "MISSING_VENUE" -> "Missing venue"
        "MISSING_EVENT" -> "Missing event"
        "CLOSED" -> "Reported closed"
        "TAG_SUGGESTION" -> "Tag"
        "LOCAL_RULES_CORRECTION" -> "Local rules"
        "TALENT_LINK" -> "Performer"
        "TRIBE_SUGGESTION" -> "Tribe"
        else -> "Change"
    }

    internal fun roleTitle(role: String): String = when (role) {
        "system" -> "an import"
        "attendee" -> "a member"
        "talent" -> "talent"
        "venue_staff" -> "venue staff"
        "admin" -> "an admin"
        else -> "someone"
    }

    internal fun statusTitle(status: String): String = when (status) {
        "SUBMITTED" -> "Filed"
        "RESEARCHING" -> "Researching"
        "IN_REVIEW" -> "In review"
        "NEEDS_VENUE" -> "Asked the venue"
        "APPROVED" -> "Approved"
        "REJECTED" -> "Rejected"
        "MERGED" -> "Merged"
        else -> status.lowercase().replaceFirstChar { it.uppercase() }
    }

    /** "Instagram" for instagram. */
    public fun networkTitle(provider: String?): String? = when (provider) {
        "instagram" -> "Instagram"
        "facebook" -> "Facebook"
        "tiktok" -> "TikTok"
        "x" -> "X"
        "threads" -> "Threads"
        "bluesky" -> "Bluesky"
        "youtube" -> "YouTube"
        "soundcloud" -> "SoundCloud"
        "spotify" -> "Spotify"
        "apple_music" -> "Apple Music"
        "linktree" -> "Linktree"
        else -> null
    }

    internal fun profileUrl(provider: String?, handle: String): String? = when (provider) {
        "instagram" -> "https://www.instagram.com/$handle/"
        "tiktok" -> "https://www.tiktok.com/@$handle"
        "x" -> "https://x.com/$handle"
        "threads" -> "https://www.threads.net/@$handle"
        "facebook" -> "https://www.facebook.com/$handle"
        else -> null
    }

    private fun parseChange(obj: JsonObject?): ProposedChange? {
        obj ?: return null
        return ProposedChange(
            id = obj.text("id") ?: return null,
            kind = obj.text("kind").orEmpty(),
            status = obj.text("status").orEmpty(),
            risk = obj.text("risk") ?: "normal",
            createdAt = obj.text("createdAt").orEmpty(),
            decidedAt = obj.text("decidedAt"),
            proposed = obj["proposed"] as? JsonObject ?: JsonObject(emptyMap()),
            current = obj["current"] as? JsonObject ?: JsonObject(emptyMap()),
            choices = (obj["choices"] as? JsonArray).orEmpty().mapNotNull { (it as? JsonPrimitive)?.contentOrNull },
            choiceProfiles = (obj["choiceProfiles"] as? JsonArray).orEmpty().mapNotNull { row ->
                val p = row as? JsonObject ?: return@mapNotNull null
                ProposedChange.Profile(
                    username = p.text("username") ?: return@mapNotNull null,
                    status = p.text("status") ?: "ready",
                    name = p.text("name"),
                    pictureUrl = p.text("pictureUrl"),
                    biography = p.text("biography"),
                    followersCount = p.int("followersCount"),
                    postsCount = p.int("postsCount"),
                    imageUrls = (p["imageUrls"] as? JsonArray).orEmpty().mapNotNull { (it as? JsonPrimitive)?.contentOrNull },
                    error = p.text("error"),
                )
            },
            body = obj.text("body"),
            evidence = (obj["evidence"] as? JsonArray).orEmpty().mapNotNull { it as? JsonObject },
            submitterRole = obj.text("submitterRole").orEmpty(),
            reporterCount = obj.int("reporterCount") ?: 1,
            disputeCount = obj.int("disputeCount") ?: 0,
            person = listing(obj["person"] as? JsonObject),
            venue = listing(obj["venue"] as? JsonObject),
            event = listing(obj["event"] as? JsonObject),
            locale = listing(obj["locale"] as? JsonObject),
            research = (obj["research"] as? JsonArray).orEmpty().mapNotNull { row ->
                (row as? JsonObject)?.let { ProposedChange.Research(it.text("summary"), it.text("recommendation")) }
            },
            decisions = (obj["decisions"] as? JsonArray).orEmpty().mapNotNull { row ->
                val d = row as? JsonObject ?: return@mapNotNull null
                ProposedChange.Decision(d.text("action").orEmpty(), d.text("reason"), d.text("createdAt").orEmpty(),
                    listing(d["reviewer"] as? JsonObject))
            },
        )
    }

    private fun reasons(value: JsonElement?): List<VenueDuplicateReason> =
        (value as? JsonArray).orEmpty().map { VenueDuplicateReason.from((it as? JsonPrimitive)?.contentOrNull) }

    private fun listing(obj: JsonObject?): ProposedChange.Listing? =
        obj?.text("id")?.let { ProposedChange.Listing(it, obj.text("name")) }

    private fun JsonObject.int(key: String): Int? = (this[key] as? JsonPrimitive)?.intOrNull
}

private fun JsonObject.text(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content

/** The words around proposed changes, the same as the Swift SDK's and the web console's. */
public object ProposedChangesCopy {
    public const val TITLE: String = "Proposed changes"
    public const val SUMMARY: String = "Changes that need a person before they go live: profiles an import wasn’t sure " +
        "of, and what members suggest. Approve to apply one, or reject it and nothing changes."
    public const val TO_REVIEW: String = "To review"
    public const val DECIDED: String = "Decided"
    public const val APPROVE: String = "Approve"
    public const val REJECT: String = "Reject"
    public const val ASK_VENUE: String = "Ask the venue"
    public const val OTHER: String = "Other…"
    public const val OTHER_PROMPT: String = "Which handle or profile link is theirs?"
    public const val REJECT_PROMPT: String = "Why reject it? Whoever suggested it sees this."
    public const val REJECT_REASON_REQUIRED: String = "Say why it was rejected."
    public const val NOTHING_TO_REVIEW: String = "Nothing to review"
    public const val NOTHING_TO_REVIEW_DETAIL: String = "When an import isn’t sure of a change, or a member suggests " +
        "one, it waits here until someone approves it."
    public const val NOTHING_DECIDED: String = "Nothing decided yet"
    public const val NOTHING_DECIDED_DETAIL: String = "Changes you approve or reject stay here, with what was decided."
    public const val APPROVED: String = "Approved, and the listing is updated."
    public const val REJECTED: String = "Rejected. Nothing changed."
    public const val ASKED_VENUE: String = "Asked the venue’s staff to confirm it."
    public const val HEADSHOTS: String = "Headshots to review"
    public const val HEADSHOTS_DETAIL: String = "Picked from each performer’s own Instagram posts and cropped, or found " +
        "by a worker. Approve the ones that are really them and look right."
    public const val REMOVE_HEADSHOT: String = "Remove"
    public const val HEADSHOT_REMOVED: String = "Removed."
    public const val NOT_DUPLICATES: String = "Not duplicates"
    public const val NOT_DUPLICATES_DETAIL: String = "Pairs someone said are different places. Undo one to see it suggested again."
    public const val UNDO: String = "Undo"

    /** "Use @murrayhill". */
    public fun use(handle: String): String = "Use @$handle"

    /** After approving a social profile: "@murrayhill is now Murray Hill’s Instagram." */
    public fun handleApproved(change: ProposedChange, handle: String): String {
        val network = ProposedChanges.networkTitle(change.provider) ?: "profile"
        return "@${ProposedChanges.handle(handle)} is now ${change.subject?.name ?: "their"}’s $network."
    }

    /** After approving a headshot. */
    public fun headshotApproved(name: String?): String = "Approved for ${name ?: "them"}. Its cut-out is on the way."

    /** "Showing 24 of 31. Decide these to see the rest." */
    public fun showing(shown: Int, total: Int, open: Boolean): String =
        "Showing $shown of $total." + if (open) " Decide these to see the rest." else ""

    /** "Now: @old · Found: @a, @b". */
    public fun socialLine(change: ProposedChange): String =
        "Now: ${change.currentHandle?.let { "@$it" } ?: "none"} · Found: " + change.choices.joinToString(", ") { "@$it" }

    /** "2 say it’s wrong." */
    public fun disputes(count: Int): String = "$count say it’s wrong."
}
