package com.audiencekit

import kotlin.time.Duration

/**
 * An app's monitoring (New Relic, say), told about every GraphQL operation the client runs. Hand one to
 * [AudienceKitClient].
 *
 * Requests also carry `X-APOLLO-OPERATION-NAME` and `X-APOLLO-OPERATION-TYPE`, which New Relic's mobile agent
 * records with each network request, so those show up by operation even without a monitor. Calls come from the
 * calling coroutine and should return quickly.
 */
public fun interface GraphQLMonitor {
    public fun record(event: GraphQLOperationEvent)
}

/** One GraphQL operation the client ran: answered, or failed ([error]). */
public data class GraphQLOperationEvent(
    /** The operation's name: the one passed with it, or the one its document gives (`query Venues { … }`). */
    val name: String?,
    /** `query`, `mutation` or `subscription`. */
    val type: String,
    val endpoint: GraphQLEndpoint,
    /** How long the request took. */
    val duration: Duration,
    /** What went wrong, when it did. */
    val error: String? = null,
) {
    public companion object {
        private val operation = Regex("""(?:^|[\s}])(query|mutation|subscription)\b\s*([_A-Za-z][_0-9A-Za-z]*)?""")

        /**
         * The operation's type and name, from its document: the first `query`, `mutation` or `subscription` and the
         * name after it. A document that opens with `{` is an anonymous query. [operationName], when given, wins.
         */
        public fun describe(query: String, operationName: String? = null): Pair<String, String?> {
            val match = operation.find(query) ?: return "query" to operationName
            val name = match.groups[2]?.value
            return match.groupValues[1] to (operationName ?: name)
        }
    }
}
