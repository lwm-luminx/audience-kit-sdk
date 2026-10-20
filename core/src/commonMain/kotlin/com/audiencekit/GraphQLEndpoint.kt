package com.audiencekit

/**
 * Which of an audience's GraphQL endpoints a request goes to. They serve the same graph: the consumer view grants a
 * signed-in member their own records and nothing more, whatever their role, and leaves out what no member could use;
 * the staff view (staffql) is for staff work (an admin console, venue and talent apps, working a door), whose roles
 * grant what they grant there, and turns anyone else away.
 */
public enum class GraphQLEndpoint(public val segment: String) {
    /** `/v1/audience/<id>/graphql`, for the apps people use. */
    CONSUMER("graphql"),

    /** `/v1/audience/<id>/staffql`, for staff work. */
    STAFF("staffql"),
    ;

    /** The endpoint's path for an audience. */
    public fun path(audienceId: String): String = "/v1/audience/$audienceId/$segment"
}
