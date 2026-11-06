/**
 * Which of an audience's GraphQL endpoints a request goes to, by its path segment. The SDK speaks only to the consumer
 * view, which grants a signed-in member their own records and nothing more, whatever their role. A package built on the
 * SDK adds the endpoints it needs.
 */
export interface GraphQLEndpoint {
  segment: string;
}

/** `/v1/audience/<id>/graphql`, for the apps people use. */
export const CONSUMER_ENDPOINT: GraphQLEndpoint = { segment: "graphql" };

/** The endpoint's path for an audience. */
export function endpointPath(endpoint: GraphQLEndpoint, audienceId: string): string {
  return `/v1/audience/${audienceId}/${endpoint.segment}`;
}
