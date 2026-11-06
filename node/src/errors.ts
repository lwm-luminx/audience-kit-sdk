/** One entry of a GraphQL response's `errors` array. */
export interface GraphQLErrorEntry {
  message: string;
  /** The response path of the field that failed, e.g. `["venues", 0, "page"]`. */
  path?: (string | number)[] | null;
  /** Extra detail: `code` on every error the API raises, `fields` on an INVALID one, `reason` on a FORBIDDEN one. */
  extensions?: Record<string, unknown> | null;
}

/**
 * The error's code: `UNAUTHENTICATED`, `FORBIDDEN`, `NOT_FOUND`, `INVALID`, `RATE_LIMITED`, `CONFLICT`, `INTERNAL` or
 * `UNAVAILABLE`; null for an error graphql-ruby raised itself (a bad query). Apps branch on this, never on the message.
 */
export function graphQLErrorCode(error: GraphQLErrorEntry): string | null {
  const code = error.extensions?.code;
  return typeof code === "string" ? code : null;
}

/** An INVALID error's messages by field (`extensions.fields`), empty for any other error. */
export function graphQLErrorFields(error: GraphQLErrorEntry): Record<string, string[]> {
  const fields = error.extensions?.fields;
  if (!fields || typeof fields !== "object" || Array.isArray(fields)) return {};
  const result: Record<string, string[]> = {};
  for (const [name, messages] of Object.entries(fields as Record<string, unknown>)) {
    result[name] = Array.isArray(messages) ? messages.filter((m): m is string => typeof m === "string") : [];
  }
  return result;
}

/** Why a FORBIDDEN error refused (`no_permission`, `banned`, `venue_device`, ...), when the API said. */
export function graphQLErrorReason(error: GraphQLErrorEntry): string | null {
  const reason = error.extensions?.reason;
  return typeof reason === "string" ? reason : null;
}

/** What an `AudienceKitError` is about. Apps branch on this. */
export type AudienceKitErrorCode =
  /** There is no stored session; sign in first. */
  | "NOT_SIGNED_IN"
  /**
   * The API rejected the session token (HTTP 401): the person signed out elsewhere, removed the app from Facebook,
   * or the session was revoked. The client has already forgotten the token; sign in again.
   */
  | "UNAUTHORIZED"
  /** `POST /v1/token` refused the sign-in (HTTP 401): the token is invalid, or from an app the audience doesn't use. */
  | "SIGN_IN_REJECTED"
  /** `POST /v1/token` failed (HTTP 400). The message is the API's when it sent one. */
  | "SIGN_IN_FAILED"
  /** The credentials are valid but not allowed here (HTTP 403), e.g. a session bound to another audience. */
  | "FORBIDDEN"
  /** The audience, record or host doesn't exist (HTTP 404). */
  | "NOT_FOUND"
  /** Any other unsuccessful HTTP status (`status`). */
  | "HTTP"
  /** The request never got a response: offline, timed out, TLS failure and so on (`cause`). */
  | "NETWORK"
  /** The response wasn't the JSON the SDK expected. */
  | "DECODING"
  /** The GraphQL operation returned errors (`errors`). */
  | "GRAPHQL"
  /** The configuration is missing something this call needs, e.g. a `host`. */
  | "MISSING_CONFIGURATION"
  /** The `TokenStore` couldn't save the session. */
  | "TOKEN_STORAGE";

/** Everything an `AudienceKitClient` call can fail with. */
export class AudienceKitError extends Error {
  override readonly name = "AudienceKitError";
  readonly code: AudienceKitErrorCode;
  /** The HTTP status, for `HTTP`. */
  readonly status?: number;
  /** The GraphQL errors, for `GRAPHQL`. */
  readonly errors: GraphQLErrorEntry[];
  /** The API's own message, for `SIGN_IN_FAILED` and `SIGN_IN_REJECTED`, when it sent one. */
  readonly faultMessage?: string;

  constructor(
    code: AudienceKitErrorCode,
    message: string,
    options: { status?: number; errors?: GraphQLErrorEntry[]; cause?: unknown; faultMessage?: string } = {},
  ) {
    super(message, options.cause === undefined ? undefined : { cause: options.cause });
    this.code = code;
    this.status = options.status;
    this.errors = options.errors ?? [];
    this.faultMessage = options.faultMessage;
  }

  /** Whether the session ended (`UNAUTHORIZED`): show sign-in again. */
  get isUnauthenticated(): boolean {
    return this.code === "UNAUTHORIZED";
  }

  /** The query asks for a field this audience's schema doesn't have (a module it hasn't installed). */
  get isUndefinedField(): boolean {
    return this.errors.some((error) => graphQLErrorCode(error) === "undefinedField");
  }

  static notSignedIn(): AudienceKitError {
    return new AudienceKitError("NOT_SIGNED_IN", "You're not signed in.");
  }

  static unauthorized(): AudienceKitError {
    return new AudienceKitError("UNAUTHORIZED", "Your session has ended. Sign in again to continue.");
  }

  static signInRejected(message?: string | null): AudienceKitError {
    return new AudienceKitError(
      "SIGN_IN_REJECTED",
      message ?? "Sign-in was refused. The login isn't valid for this app.",
      { faultMessage: message ?? undefined },
    );
  }

  static signInFailed(message?: string | null): AudienceKitError {
    return new AudienceKitError("SIGN_IN_FAILED", message ?? "Sign-in failed.", { faultMessage: message ?? undefined });
  }

  static forbidden(): AudienceKitError {
    return new AudienceKitError("FORBIDDEN", "You don't have access to this.");
  }

  static notFound(): AudienceKitError {
    return new AudienceKitError("NOT_FOUND", "That isn't available.");
  }

  static http(status: number): AudienceKitError {
    return new AudienceKitError("HTTP", `The server responded with status ${status}.`, { status });
  }

  static network(cause: unknown): AudienceKitError {
    const message = cause instanceof Error && cause.message ? cause.message : "The network request failed.";
    return new AudienceKitError("NETWORK", message, { cause });
  }

  static decoding(detail: string): AudienceKitError {
    return new AudienceKitError("DECODING", `The server sent a response the app didn't understand. ${detail}`);
  }

  static graphQL(errors: GraphQLErrorEntry[]): AudienceKitError {
    return new AudienceKitError("GRAPHQL", errors.map((error) => error.message).join("\n"), { errors });
  }

  static missingConfiguration(detail: string): AudienceKitError {
    return new AudienceKitError("MISSING_CONFIGURATION", `AudienceKit isn't configured: ${detail}`);
  }

  static tokenStorage(detail: string): AudienceKitError {
    return new AudienceKitError("TOKEN_STORAGE", `The session couldn't be saved. ${detail}`);
  }

  /** The error for an unsuccessful HTTP status. */
  static forStatus(status: number): AudienceKitError {
    switch (status) {
      case 401:
        return AudienceKitError.unauthorized();
      case 403:
        return AudienceKitError.forbidden();
      case 404:
        return AudienceKitError.notFound();
      default:
        return AudienceKitError.http(status);
    }
  }
}
