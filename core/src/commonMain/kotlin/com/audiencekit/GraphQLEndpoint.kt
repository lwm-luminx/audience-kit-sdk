package com.audiencekit

/**
 * Which of an audience's GraphQL endpoints a request goes to, by its path segment. The SDK speaks only to the
 * consumer view, which grants a signed-in member their own records and nothing more, whatever their role. A package
 * built on the SDK adds the endpoints it needs as extensions on the companion (StaffKit adds its staff endpoint).
 */
public data class GraphQLEndpoint(
    public val segment: String,
    /**
     * Whether it's under `/v1/` itself, with no audience in its path: StaffKit's audience-less `/v1/staffql`, one
     * staff sign-in's audiences and the listings it manages, in no audience or any number of them. Calls to it need no audience.
     */
    public val audienceless: Boolean = false,
) {
    /** The endpoint's path for an audience; an audience-less endpoint's ignores it. */
    public fun path(audienceId: String?): String =
        if (audienceless) "/v1/$segment" else "/v1/audience/${audienceId.orEmpty()}/$segment"

    public companion object {
        /** `/v1/audience/<id>/graphql`, for the apps people use. */
        public val CONSUMER: GraphQLEndpoint = GraphQLEndpoint("graphql")
    }
}
