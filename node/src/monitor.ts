import type { GraphQLEndpoint } from "./endpoint.js";

/** One GraphQL operation the client ran: answered, or failed (`error`). */
export interface GraphQLOperationEvent {
  /** The operation's name: the one passed with it, or the one its document gives (`query Venues { … }`). */
  name: string | null;
  /** `query`, `mutation` or `subscription`. */
  type: string;
  endpoint: GraphQLEndpoint;
  /** How long the request took, in milliseconds. */
  durationMillis: number;
  /** What went wrong, when it did. */
  error?: string;
}

/**
 * An app's monitoring (New Relic, say), told about every GraphQL operation the client runs. Requests also carry
 * `X-APOLLO-OPERATION-NAME` and `X-APOLLO-OPERATION-TYPE`. Return quickly.
 */
export type GraphQLMonitor = (event: GraphQLOperationEvent) => void;

const OPERATION = /(?:^|[\s}])(query|mutation|subscription)\b\s*([_A-Za-z][_0-9A-Za-z]*)?/;

/**
 * The operation's type and name, from its document: the first `query`, `mutation` or `subscription` and the name after
 * it. A document that opens with `{` is an anonymous query. `operationName`, when given, wins.
 */
export function describeOperation(query: string, operationName?: string | null): { type: string; name: string | null } {
  const match = OPERATION.exec(query);
  if (!match) return { type: "query", name: operationName ?? null };
  return { type: match[1]!, name: operationName ?? match[2] ?? null };
}
