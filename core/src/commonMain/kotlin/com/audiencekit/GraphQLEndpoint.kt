package com.audiencekit

/**
 * Which of an audience's GraphQL endpoints a request goes to, by its path segment. The SDK speaks only to the
 * consumer view, which grants a signed-in member their own records and nothing more, whatever their role. A package
 * built on the SDK adds the endpoints it needs as extensions on the companion (StaffKit adds its staff endpoint).
 */
public data class GraphQLEndpoint(public val segment: String) {
    /** The endpoint's path for an audience. */
    public fun path(audienceId: String): String = "/v1/audience/$audienceId/$segment"

    public companion object {
        /** `/v1/audience/<id>/graphql`, for the apps people use. */
        public val CONSUMER: GraphQLEndpoint = GraphQLEndpoint("graphql")
    }
}
