package com.audiencekit

import kotlinx.serialization.Serializable

/**
 * What [reportContent] reports: the API's `ReportTarget`. Chat needs [MESSAGE] (a message's frame id) and [PERSON]
 * (a member's user id, as chat gives it).
 */
public enum class ReportTarget {
    MESSAGE,
    PERSON,
    PHOTO,
    PING,
    POST,
    POST_COMMENT,
    VENUE,
}

/** What happened to a report: whether it was filed, and whether the person behind it is now blocked. */
@Serializable
public data class ReportResult(val reported: Boolean = false, val blocked: Boolean = false)

/**
 * Files a report with the audience's admins (Google Play's user-generated content policy, App Store guideline 1.2):
 * `reportContent`. With [block], the person behind it is blocked too, when there is one. [reason] is optional; offer
 * [ReportCopy.REASONS].
 */
public suspend fun AudienceKitClient.reportContent(
    targetType: ReportTarget,
    targetId: String,
    reason: String? = null,
    block: Boolean = false,
): ReportResult = graphQL(
    """
    mutation ReportContent(${'$'}targetType: ReportTarget!, ${'$'}targetId: ID!, ${'$'}reason: String, ${'$'}block: Boolean) {
      reportContent(input: { targetType: ${'$'}targetType, targetId: ${'$'}targetId, reason: ${'$'}reason, block: ${'$'}block }) {
        reported
        blocked
      }
    }
    """.trimIndent(),
    ReportContentResponse.serializer(),
    graphQLVariables("targetType" to targetType.name, "targetId" to targetId, "reason" to reason, "block" to block),
    "ReportContent",
).reportContent ?: ReportResult()

/** Blocks a member (their user id): they and the signed-in person stop seeing each other's messages. */
public suspend fun AudienceKitClient.blockUser(userId: String) {
    graphQL(
        "mutation BlockUser(${'$'}userId: ID!) { blockUser(input: { userId: ${'$'}userId }) { blockedUsers { id } } }",
        BlockedUsersResponse.serializer(),
        graphQLVariables("userId" to userId),
        "BlockUser",
    )
}

/** Unblocks a member blocked with [blockUser] or a report. */
public suspend fun AudienceKitClient.unblockUser(userId: String) {
    graphQL(
        "mutation UnblockUser(${'$'}userId: ID!) { unblockUser(input: { userId: ${'$'}userId }) { blockedUsers { id } } }",
        BlockedUsersResponse.serializer(),
        graphQLVariables("userId" to userId),
        "UnblockUser",
    )
}

/** The words around reporting and blocking, the same as the Swift SDK's, so both apps say the same thing. */
public object ReportCopy {
    public const val REPORT_MESSAGE: String = "Report message"
    public const val BLOCK_PERSON: String = "Block"
    public const val REPORT_TITLE: String = "Report this message?"
    public const val REPORT_DETAIL: String = "The audience's admins will look at it. You can block the sender too, " +
        "so you stop seeing each other's messages."
    public const val ALSO_BLOCK: String = "Also block the sender"
    public const val BLOCK_TITLE: String = "Block this person?"
    public const val BLOCK_DETAIL: String = "You'll stop seeing each other's messages. You can unblock them later."
    public const val REPORTED: String = "Thanks. The admins will look at it."
    public const val BLOCKED: String = "Blocked."
    public val REASONS: List<String> = listOf("Spam", "Harassment or hate", "Sexual content", "Child safety", "Scam or fraud", "Other")
}

@Serializable
private data class ReportContentResponse(val reportContent: ReportResult? = null)

@Serializable
private data class BlockedUsersResponse(val blockUser: Payload? = null, val unblockUser: Payload? = null) {
    @Serializable
    data class Payload(val blockedUsers: List<Entry> = emptyList())

    @Serializable
    data class Entry(val id: String)
}
