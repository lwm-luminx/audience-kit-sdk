import { RequestPacer } from "./pacer.js";
import { AudienceKitError, type GraphQLErrorEntry } from "./errors.js";
import {
  ENVIRONMENT_HEADER,
  resolveConfiguration,
  type AudienceKitConfiguration,
  type DeviceDescription,
  type ResolvedConfiguration,
} from "./configuration.js";
import { CONSUMER_ENDPOINT, endpointPath, type GraphQLEndpoint } from "./endpoint.js";
import { describeOperation, type GraphQLMonitor } from "./monitor.js";
import { SchemaShape } from "./schemaShape.js";
import { FetchTransport, type HttpRequest, type HttpResponse, type HttpTransport } from "./transport.js";
import { InMemoryTokenStore, type TokenStore } from "./tokenStore.js";
import { AudienceKitSDK } from "./version.js";
import { coordinatesInput, type Coordinates } from "./coordinates.js";
import * as Queries from "./queries.js";
import {
  connectionItems,
  type Admission,
  type AdmissionOffer,
  type Article,
  type ArticlesPage,
  type CalendarFeed,
  type Community,
  type Publication,
  type PublicListing,
  type PublicListingsPage,
  type ReportResult,
  type ReportTarget,
  type Audience,
  type AudienceLocale,
  type Branding,
  type ChatMessage,
  type ChatRoom,
  type Connection,
  type CoverPurchase,
  type Credential,
  type Event,
  type EventRSVP,
  type EventSeries,
  type EventWindow,
  type Node,
  type Person,
  type RSVPState,
  type SelfUser,
  type SocialLink,
  type Tag,
  type TribeIdentification,
  type Tribes,
  type Venue,
  type VenueCover,
  type VenueDetail,
  chatRoomArgument,
} from "./models.js";

/** A change to the client's session. */
export type SessionEvent =
  /** A sign-in stored a new session. */
  | "signedIn"
  /** `signOut()` was called. */
  | "signedOut"
  /**
   * The API rejected the stored session (HTTP 401, or `sessionRejected()` for a socket), e.g. after the person removed
   * the app from Facebook. The token has been forgotten; sign in again. Emitted once per session, however many calls
   * were refused.
   */
  | "sessionEnded";

export type SessionListener = (event: SessionEvent) => void;

/** A REST request as the client makes it, for an app that calls an endpoint the SDK has no helper for. */
export interface APIRequest {
  method?: string;
  /** The path under the base URL, e.g. `/v1/branding`. */
  path: string;
  query?: Record<string, string | null | undefined>;
  /** A JSON body. */
  body?: unknown;
  /** Whether to send the session token (the default). A 401 on an authenticated request ends the session. */
  authenticated?: boolean;
  /** Extra headers, sent alongside the client's own. */
  headers?: Record<string, string>;
  signal?: AbortSignal;
}

export interface GraphQLOptions {
  variables?: Record<string, unknown> | null;
  operationName?: string | null;
  /** The consumer view by default; a package built on the SDK passes its own. */
  endpoint?: GraphQLEndpoint;
  signal?: AbortSignal;
}

export interface AudienceKitClientOptions {
  configuration?: AudienceKitConfiguration;
  /** Where the session lives between calls: in memory by default. */
  tokenStore?: TokenStore;
  /** How HTTP requests go out: the global `fetch` by default. */
  transport?: HttpTransport;
  /** Told about every GraphQL operation the client runs. */
  monitor?: GraphQLMonitor;
  /**
   * Paces requests and backs off when the API answers 429 (`RequestPacer`), so no timer or retry loop can flood
   * the API. One per client by default.
   */
  pacer?: RequestPacer;
}

/** The environment variables `AudienceKitClient.fromEnvironment` reads. */
export type EnvironmentVariables = Record<string, string | undefined>;

/** How long before a service token's session expires the client trades the token again, in seconds. */
export const SERVICE_RENEW_BEFORE_SECONDS = 60;

/** The sign-in JSON (`POST /v1/token`), which says everything the app needs about the session so it never decodes the JWT. */
export type SignInResult = Credential;

/** A sign in with Apple credential, as Apple's web or native sign-in hands it over. */
export interface AppleCredential {
  identityToken: string;
  authorizationCode?: string | null;
  /** The return URL Apple's web sign-in was opened with; Apple needs it again to exchange the code. */
  redirectUri?: string | null;
  /** The nonce that binds the token to this app. */
  nonce?: string | null;
  /** Apple sends the name only the first time someone signs in to the app. */
  firstName?: string | null;
  lastName?: string | null;
}

interface GraphQLResponse<T> {
  data?: T | null;
  errors?: GraphQLErrorEntry[] | null;
}

interface SchemaFieldsType {
  fields?: { name: string }[] | null;
}

/**
 * Talks to the AudienceKit API on behalf of one audience and one signed-in person.
 *
 * The app owns the login (Facebook, Google, Apple or an App Review code); hand what it gets to a sign-in method. After
 * that, every call carries the session token as `Authorization: Bearer <token>`. When the API rejects it, the call
 * throws an `AudienceKitError` with code `UNAUTHORIZED` and `sessionEnded` fires.
 */
export class AudienceKitClient {
  readonly configuration: ResolvedConfiguration;
  private readonly tokenStore: TokenStore;
  private readonly transport: HttpTransport;
  private readonly monitor: GraphQLMonitor | null;
  /** Paces this client's requests and backs off on 429 (`RequestPacer`). */
  readonly pacer: RequestPacer;
  private readonly listeners = new Set<SessionListener>();
  private resolvedAudienceId: string | null = null;
  /** The fields each type has in an audience's schema, by "audience|endpoint|type" (`schemaFields`). */
  private readonly schemaFieldCache = new Map<string, Set<string>>();
  /** The service token (`akst_…`) this client trades for sessions, when it acts for the audience. */
  private serviceToken: string | null = null;
  /** When the traded service session expires, in milliseconds since the epoch. */
  private serviceExpiresAt: number | null = null;
  private serviceTrade: Promise<Credential> | null = null;

  constructor(options: AudienceKitClientOptions = {}) {
    this.configuration = resolveConfiguration(options.configuration);
    this.tokenStore = options.tokenStore ?? new InMemoryTokenStore();
    this.transport = options.transport ?? new FetchTransport();
    this.monitor = options.monitor ?? null;
    this.pacer = options.pacer ?? new RequestPacer();
  }

  /**
   * A client configured from the environment, for servers, jobs and scripts: `AUDIENCEKIT_TOKEN` (a service token,
   * `akst_…`, traded for sessions as `useServiceToken` does, or another bearer value such as an application API key)
   * and, when set, `AUDIENCEKIT_BASE_URL`, `AUDIENCEKIT_HOST`, `AUDIENCEKIT_AUDIENCE_ID` and `AUDIENCEKIT_ENVIRONMENT`.
   * Reads `process.env` unless given `environment`.
   */
  static fromEnvironment(
    environment: EnvironmentVariables = (globalThis as { process?: { env: EnvironmentVariables } }).process?.env ?? {},
    options: Omit<AudienceKitClientOptions, "configuration"> = {},
  ): AudienceKitClient {
    const read = (name: string): string | undefined => {
      const value = environment[name];
      return value ? value : undefined;
    };
    const client = new AudienceKitClient({
      ...options,
      configuration: {
        baseUrl: read("AUDIENCEKIT_BASE_URL"),
        host: read("AUDIENCEKIT_HOST"),
        audienceId: read("AUDIENCEKIT_AUDIENCE_ID"),
        environment: read("AUDIENCEKIT_ENVIRONMENT") === "staging" ? "staging" : undefined,
      },
      // Each client keeps its own session: one traded from a service token isn't meant to outlive the process.
      tokenStore: options.tokenStore ?? new InMemoryTokenStore(),
    });
    const token = read("AUDIENCEKIT_TOKEN");
    if (token?.startsWith("akst_")) client.serviceToken = token;
    else if (token) client.bearerToken = token;
    return client;
  }

  /** A bearer value from the environment, stored on first use (the token store's methods may be async). */
  private bearerToken: string | null = null;

  /**
   * Acts for the audience with a service token an admin minted in its console (`akst_<prefix>_<secret>`): a server or
   * agent rather than a person. The client trades it at `POST /v1/token/service` for an hour-long session now, trades
   * it again a minute before that runs out, and once more when the API refuses the session (after a key rotation). A
   * token with `public:read` reads the public listings (`publicListings()`). A revoked token throws `UNAUTHORIZED`.
   */
  async useServiceToken(serviceToken: string): Promise<Credential> {
    this.serviceToken = serviceToken;
    this.bearerToken = null;
    return this.tradeServiceToken();
  }

  /**
   * Sends `token` as is (an application API key, or a session JWT minted elsewhere) as `Authorization: Bearer`, to the
   * configured base URL and audience.
   */
  async useBearerToken(token: string): Promise<void> {
    this.serviceToken = null;
    this.serviceExpiresAt = null;
    this.bearerToken = null;
    await this.store({ token, userId: "", audienceId: this.configuration.audienceId, role: "bearer", expiresAt: null });
  }

  /** Trades the service token for a session, once at a time however many calls ask together. */
  private tradeServiceToken(): Promise<Credential> {
    this.serviceTrade ??= this.performServiceTrade().finally(() => {
      this.serviceTrade = null;
    });
    return this.serviceTrade;
  }

  private async performServiceTrade(): Promise<Credential> {
    const secret = this.serviceToken;
    if (secret === null) throw AudienceKitError.notSignedIn();
    const response = await this.perform(
      { method: "POST", path: "/v1/token/service", body: { service_token: secret }, authenticated: false },
      null,
    );
    if (response.status === 401 || response.status === 403) {
      this.serviceToken = null;
      this.serviceExpiresAt = null;
      throw new AudienceKitError("UNAUTHORIZED", "The service token was refused: it is invalid or was revoked.", {
        status: response.status,
      });
    }
    if (response.status < 200 || response.status >= 300) throw AudienceKitError.forStatus(response.status);
    const json = this.parseJson(response.body) as Partial<Credential> | null;
    if (!json || typeof json !== "object" || typeof json.token !== "string") {
      throw AudienceKitError.decoding("The service token response had no token.");
    }
    const credential: Credential = { ...json, token: json.token, userId: json.userId ?? "", role: json.role ?? "service" };
    const expires = credential.expiresAt ? Date.parse(credential.expiresAt) : NaN;
    this.serviceExpiresAt = Number.isNaN(expires) ? null : expires;
    await this.store(credential);
    return credential;
  }

  /** Makes sure a service token or a bearer value from the environment has a session before a call that needs one. */
  private async ensureSession(): Promise<void> {
    if (this.bearerToken !== null) {
      const token = this.bearerToken;
      await this.useBearerToken(token);
      return;
    }
    if (this.serviceToken === null) return;
    const stored = await this.storedToken();
    const renewAt = this.serviceExpiresAt === null ? null : this.serviceExpiresAt - SERVICE_RENEW_BEFORE_SECONDS * 1000;
    if (stored === null || (renewAt !== null && Date.now() >= renewAt)) await this.tradeServiceToken();
  }

  /** Listens for session changes, to route between sign-in and content. Returns a function that stops listening. */
  onSession(listener: SessionListener): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  private emit(event: SessionEvent): void {
    for (const listener of this.listeners) listener(event);
  }

  // Session

  /** Whether a session token is stored. It may still be rejected by the API. */
  async isSignedIn(): Promise<boolean> {
    return (await this.storedToken()) !== null;
  }

  /**
   * The stored session token, for the rare connection the SDK doesn't make itself (an Action Cable websocket). Never
   * log it. When the API refuses it there, hand it to `sessionRejected`.
   */
  async sessionToken(): Promise<string | null> {
    return this.tokenStore.loadToken();
  }

  /**
   * Exchanges a Facebook user access token for an AudienceKit session and stores it. Sends the configured `host` and
   * `facebookAppId` so the API checks the token against the right Facebook app and binds the session to the audience.
   */
  signIn(facebookAccessToken: string, device: DeviceDescription): Promise<SignInResult> {
    return this.exchange("/v1/token", {
      facebook_token: facebookAccessToken,
      host: this.configuration.host,
      facebook_app_id: this.configuration.facebookAppId,
      device: this.deviceBody(device),
    });
  }

  /**
   * Exchanges the code from Facebook's OAuth dialog for an AudienceKit session and stores it (Facebook Login for
   * Business, whose dialog takes branding's `facebook_login_config_id`). `redirectUri` must be exactly the one the
   * dialog was opened with, and `facebookAppId` the app it was opened for (the configured one by default).
   */
  signInWithFacebookCode(
    code: string,
    redirectUri: string,
    device: DeviceDescription,
    facebookAppId: string | null = this.configuration.facebookAppId,
  ): Promise<SignInResult> {
    return this.exchange("/v1/token", {
      code,
      redirect_uri: redirectUri,
      host: this.configuration.host,
      facebook_app_id: facebookAppId,
      device: this.deviceBody(device),
    });
  }

  /**
   * Exchanges a Google ID token for an AudienceKit session and stores it. The ID token only carries the account's
   * primary email; pass `accessToken` (an OAuth token for `https://www.googleapis.com/auth/user.emails.read`) and the
   * API can also match an existing account by the Google account's other verified emails.
   */
  signInWithGoogle(
    idToken: string,
    device: DeviceDescription,
    options: { name?: string | null; accessToken?: string | null } = {},
  ): Promise<SignInResult> {
    return this.exchange("/v1/token/google", {
      id_token: idToken,
      access_token: options.accessToken ?? null,
      host: this.configuration.host,
      device: this.deviceBody(device),
      name: options.name ?? null,
    });
  }

  /**
   * Exchanges a Google OAuth access token (from Google Identity Services' token client, which gives a browser no ID
   * token) for an AudienceKit session and stores it. The API checks the token was issued to one of its client IDs.
   */
  signInWithGoogleAccessToken(accessToken: string, device: DeviceDescription): Promise<SignInResult> {
    return this.exchange("/v1/token/google", { access_token: accessToken, host: this.configuration.host, device: this.deviceBody(device) });
  }

  /**
   * Connects a Google account to the signed-in account, so Google signs in to it from then on, and stores the session
   * the API answers with. Refusals throw `SIGN_IN_FAILED` with the API's reason and keep the current session.
   */
  async connectGoogle(idToken: string, device: DeviceDescription): Promise<SignInResult> {
    const token = await this.storedToken();
    if (token === null) throw AudienceKitError.notSignedIn();
    return this.exchange(
      "/v1/token/google",
      { id_token: idToken, host: this.configuration.host, device: this.deviceBody(device), connect: true },
      token,
    );
  }

  /** Exchanges a Sign in with Apple credential for an AudienceKit session and stores it (`POST /v1/token/apple`). */
  signInWithApple(credential: AppleCredential, device: DeviceDescription): Promise<SignInResult> {
    return this.exchange("/v1/token/apple", {
      identity_token: credential.identityToken,
      authorization_code: credential.authorizationCode ?? null,
      redirect_uri: credential.redirectUri ?? null,
      nonce: credential.nonce ?? null,
      first_name: credential.firstName ?? null,
      last_name: credential.lastName ?? null,
      host: this.configuration.host,
      device: this.deviceBody(device),
    });
  }

  /**
   * Signs in with an App Review code (`POST /v1/token/review`) and stores the session. It works only while the audience
   * is in App Review; a wrong or expired code throws `SIGN_IN_REJECTED` with the API's reason.
   */
  signInWithReviewCode(code: string, device: DeviceDescription): Promise<SignInResult> {
    return this.exchange("/v1/token/review", { code: code.trim(), host: this.configuration.host, device: this.deviceBody(device) });
  }

  /**
   * Re-issues the session token at `POST /v1/token/refresh` (the same session, signed with the API's current key) and
   * stores it. A 401 means the session ended, like any other call.
   */
  async refreshSession(): Promise<SignInResult> {
    const text = await this.data({ method: "POST", path: "/v1/token/refresh" });
    const result = this.decodeCredential(text);
    await this.store(result);
    return result;
  }

  /**
   * Makes `credential` the session: one minted outside the SDK, such as a venue device's or one the platform console
   * handed over. Fires `signedIn`.
   */
  async adopt(credential: Credential): Promise<void> {
    await this.store(credential);
    this.emit("signedIn");
  }

  /** Forgets the session. (The Facebook or Google session belongs to the app; log out of it too.) */
  async signOut(): Promise<void> {
    try {
      await this.tokenStore.deleteToken();
    } catch {
      // Nothing to keep anyway.
    }
    this.resolvedAudienceId = null;
    this.schemaFieldCache.clear();
    this.serviceToken = null;
    this.serviceExpiresAt = null;
    this.bearerToken = null;
    this.emit("signedOut");
  }

  /**
   * Ends the session because the API refused `token` on a connection the SDK doesn't make itself (an Action Cable
   * socket closed with `"reason": "unauthorized"`, a Server-Sent Events stream answered 401). Forgets the token and
   * fires `sessionEnded`, once: when the store no longer holds `token` it does nothing and returns false.
   */
  async sessionRejected(token: string): Promise<boolean> {
    if ((await this.storedToken()) !== token) return false;
    try {
      await this.tokenStore.deleteToken();
    } catch {
      // The token is gone from the client's point of view either way.
    }
    this.resolvedAudienceId = null;
    this.emit("sessionEnded");
    return true;
  }

  private deviceBody(device: DeviceDescription): Record<string, unknown> {
    return { type: "node", ...device };
  }

  /** Posts a sign-in to `path` and stores the session it answers with. `token` is a session being connected. */
  private async exchange(path: string, body: Record<string, unknown>, token: string | null = null): Promise<SignInResult> {
    // Nulls are left out, as the API expects (an absent host, no Facebook app).
    const sent = Object.fromEntries(Object.entries(body).filter(([, value]) => value !== null && value !== undefined));
    const response = await this.perform({ method: "POST", path, body: sent, authenticated: false }, token);
    if (response.status === 401) throw AudienceKitError.signInRejected(this.restMessage(response.body));
    if (response.status === 400) throw AudienceKitError.signInFailed(this.restMessage(response.body));
    if (response.status < 200 || response.status >= 300) throw AudienceKitError.forStatus(response.status);

    const result = this.decodeCredential(response.body);
    await this.store(result);
    this.emit("signedIn");
    return result;
  }

  private decodeCredential(text: string): Credential {
    const json = this.parseJson(text) as Partial<Credential> | null;
    if (!json || typeof json !== "object" || typeof json.token !== "string" || typeof json.userId !== "string") {
      throw AudienceKitError.decoding("The sign-in response had no token.");
    }
    return json as Credential;
  }

  private async store(credential: Credential): Promise<void> {
    try {
      await this.tokenStore.saveToken(credential.token);
      await this.tokenStore.saveAudienceId?.(credential.audienceId ?? null);
    } catch (error) {
      throw AudienceKitError.tokenStorage(error instanceof Error ? error.message : String(error));
    }
    this.resolvedAudienceId = credential.audienceId ?? null;
  }

  /** The `message` of a REST error, `{ "error": "<code>", "message": "..." }`, when the body is one. */
  private restMessage(body: string): string | null {
    try {
      const json = JSON.parse(body) as { message?: unknown } | null;
      return json && typeof json.message === "string" ? json.message : null;
    } catch {
      return null;
    }
  }

  // Branding and audience

  /** The audience's public branding for the configured host (or `host`). No sign-in needed. */
  async branding(host?: string): Promise<Branding> {
    const brandingHost = host ?? this.configuration.host;
    if (!brandingHost) throw AudienceKitError.missingConfiguration("branding needs a host");
    const response = await this.perform({ path: "/v1/branding", query: { host: brandingHost }, authenticated: false }, null);
    if (response.status < 200 || response.status >= 300) throw AudienceKitError.forStatus(response.status);
    const branding = this.parseJson(response.body) as Branding | null;
    if (!branding || typeof branding !== "object" || !branding.audience?.id) {
      throw AudienceKitError.decoding("The branding had no audience.");
    }
    return branding;
  }

  /**
   * The audience this client queries: the configured ID, the audience the sign-in named (kept in the token store), or
   * the audience that owns the configured host.
   */
  async audienceId(): Promise<string> {
    await this.ensureSession();
    const known = this.configuration.audienceId ?? this.resolvedAudienceId;
    if (known) return known;

    try {
      const stored = await this.tokenStore.loadAudienceId?.();
      if (stored) {
        this.resolvedAudienceId = stored;
        return stored;
      }
    } catch {
      // Fall through to the host.
    }

    if (!this.configuration.host) throw AudienceKitError.missingConfiguration("set an audienceId or a host");
    const id = (await this.branding()).audience.id;
    this.resolvedAudienceId = id;
    return id;
  }

  // GraphQL

  /**
   * Runs a GraphQL operation against the audience's endpoint and returns its `data`. Throws a `GRAPHQL` error when the
   * response carries errors, even alongside data.
   */
  async graphQL<T = Record<string, unknown>>(query: string, options: GraphQLOptions = {}): Promise<T> {
    const endpoint = options.endpoint ?? CONSUMER_ENDPOINT;
    const audienceId = await this.audienceId();
    const { type, name } = describeOperation(query, options.operationName);
    const headers: Record<string, string> = { "X-APOLLO-OPERATION-TYPE": type };
    if (name) headers["X-APOLLO-OPERATION-NAME"] = name;
    const body: Record<string, unknown> = { query };
    if (options.variables) body.variables = options.variables;
    if (options.operationName) body.operationName = options.operationName;

    const started = Date.now();
    try {
      const text = await this.data({ method: "POST", path: endpointPath(endpoint, audienceId), body, headers, signal: options.signal });
      const envelope = this.parseJson(text) as GraphQLResponse<T> | null;
      if (!envelope || typeof envelope !== "object") throw AudienceKitError.decoding("The response wasn't a GraphQL envelope.");
      // Errors first: a refused mutation comes back as `{"errors":[…],"data":{"field":null}}`.
      if (envelope.errors && envelope.errors.length > 0) throw AudienceKitError.graphQL(envelope.errors);
      if (envelope.data === null || envelope.data === undefined) throw AudienceKitError.decoding("The response had no data.");
      this.monitor?.({ name, type, endpoint, durationMillis: Date.now() - started });
      return envelope.data;
    } catch (error) {
      this.monitor?.({ name, type, endpoint, durationMillis: Date.now() - started, error: error instanceof Error ? error.message : String(error) });
      throw error;
    }
  }

  /**
   * The fields each of `types` has in the audience's schema (introspection), by type name; a type the schema doesn't
   * have is left out. Cached until sign-out, so each type is asked about once.
   */
  async schemaFields(types: readonly string[], endpoint: GraphQLEndpoint = CONSUMER_ENDPOINT): Promise<Record<string, Set<string>>> {
    const prefix = `${await this.audienceId()}|${endpoint.segment}|`;
    const missing = [...new Set(types.filter((type) => !this.schemaFieldCache.has(prefix + type)))].sort();
    if (missing.length > 0) {
      const selections = missing.map((name, index) => `t${index}: __type(name: "${name}") { fields(includeDeprecated: true) { name } }`);
      const result = await this.graphQL<Record<string, SchemaFieldsType | null>>(`query SchemaFields { ${selections.join(" ")} }`, {
        operationName: "SchemaFields",
        endpoint,
      });
      missing.forEach((name, index) => {
        const fields = result[`t${index}`]?.fields ?? [];
        this.schemaFieldCache.set(prefix + name, new Set(fields.map((field) => field.name)));
      });
    }
    return this.knownSchemaFields(prefix, types)!;
  }

  private knownSchemaFields(prefix: string, types: readonly string[]): Record<string, Set<string>> | null {
    const known: Record<string, Set<string>> = {};
    for (const type of types) {
      const fields = this.schemaFieldCache.get(prefix + type);
      if (!fields) return null;
      if (fields.size > 0) known[type] = fields;
    }
    return known;
  }

  /**
   * Runs the operation `document` builds, first for an audience with every module; when the API refuses a field
   * (`undefinedField`), asks the schema which fields `types` have and runs it again with only those. The answer is
   * cached, so later operations go straight to the right document.
   */
  async graphQLForShape<T>(
    types: readonly string[],
    document: (shape: SchemaShape) => string,
    options: GraphQLOptions = {},
  ): Promise<T> {
    const endpoint = options.endpoint ?? CONSUMER_ENDPOINT;
    const audienceId = this.configuration.audienceId ?? this.resolvedAudienceId;
    const known = audienceId ? this.knownSchemaFields(`${audienceId}|${endpoint.segment}|`, types) : null;
    if (known) return this.graphQL<T>(document(new SchemaShape(known)), options);
    try {
      return await this.graphQL<T>(document(SchemaShape.EVERYTHING), options);
    } catch (error) {
      if (!(error instanceof AudienceKitError) || !error.isUndefinedField) throw error;
      return this.graphQL<T>(document(new SchemaShape(await this.schemaFields(types, endpoint))), options);
    }
  }

  /** The audience, with its theme. */
  audience(): Promise<Audience> {
    return this.graphQL<Audience>(Queries.audience, { operationName: "Audience" });
  }

  /** The audience's venues; without their Facebook Pages or Google place IDs in an audience without those modules. */
  async venues(): Promise<Venue[]> {
    const data = await this.graphQLForShape<{ venues?: { list: Connection<Venue> } | null }>(Queries.LISTING_TYPES, Queries.venues, {
      operationName: "Venues",
    });
    return connectionItems(data.venues?.list);
  }

  /** The people the audience follows. */
  async people(): Promise<Person[]> {
    const data = await this.graphQLForShape<{ people?: { list: Connection<Person> } | null }>(Queries.LISTING_TYPES, Queries.people, {
      operationName: "People",
    });
    return connectionItems(data.people?.list);
  }

  /** The audience's locales; without their Google place IDs for an audience without Listings or Google Places. */
  async locales(): Promise<AudienceLocale[]> {
    const data = await this.graphQLForShape<{ locales?: AudienceLocale[] | null }>(Queries.LISTING_TYPES, Queries.locales, {
      operationName: "Locales",
    });
    return data.locales ?? [];
  }

  /** The signed-in user, or null when the API has no current user. */
  async me(): Promise<SelfUser | null> {
    const data = await this.graphQL<{ me?: { self: SelfUser } | null }>(Queries.me, { operationName: "Me" });
    return data.me?.self ?? null;
  }

  /** Any record by its `id` (its UUID), or null when it doesn't exist or belongs to another audience. */
  async node(id: string): Promise<Node | null> {
    const data = await this.graphQL<{ node?: Node | null }>(Queries.node, { variables: { id }, operationName: "Node" });
    return data.node ?? null;
  }

  /** The audience's locale nearest a position, or null when it has none. */
  async closestLocale(near: Coordinates): Promise<AudienceLocale | null> {
    const data = await this.graphQLForShape<{ closestLocale?: AudienceLocale | null }>(Queries.LISTING_TYPES, Queries.closestLocale, {
      variables: { near: coordinatesInput(near) },
      operationName: "ClosestLocale",
    });
    return data.closestLocale ?? null;
  }

  /**
   * Records the user's position and says where that is (`venue`, `locale`, `nearbyVenues`, `audience`). Select the
   * fields the app needs and read the result yourself.
   */
  async reportLocation<T = Record<string, unknown>>(position: Coordinates, fields: string): Promise<T> {
    const data = await this.graphQL<{ reportLocation: T }>(Queries.reportLocation(fields), {
      variables: { position: coordinatesInput(position) },
      operationName: "ReportLocation",
    });
    return data.reportLocation;
  }

  /** Sets the signed-in user's RSVP to an event and returns the event's RSVPs afterwards (without attendees). */
  async rsvp(eventId: string, state: RSVPState = "ATTENDING"): Promise<EventRSVP> {
    const data = await this.graphQL<{ rsvpEvent: { event: { rsvp: RawRSVP } } }>(Queries.rsvpEvent, {
      variables: { eventId, state },
      operationName: "RSVPEvent",
    });
    return toEventRSVP(data.rsvpEvent.event.rsvp);
  }

  /** Takes back the signed-in user's RSVP, as if they'd never answered. Someone holding a ticket stays going. */
  async cancelRSVP(eventId: string): Promise<EventRSVP> {
    const data = await this.graphQL<{ cancelRsvp: { event: { rsvp: RawRSVP } } }>(Queries.cancelRsvp, {
      variables: { eventId },
      operationName: "CancelRSVP",
    });
    return toEventRSVP(data.cancelRsvp.event.rsvp);
  }

  /** Who's going to an event and the first `first` of them by name, or null when there's no such event. */
  async eventRSVP(eventId: string, first = 50): Promise<EventRSVP | null> {
    const data = await this.graphQL<{ events: { event?: { rsvp: RawRSVP } | null } }>(Queries.eventRsvp, {
      variables: { id: eventId, first },
      operationName: "EventRSVP",
    });
    const rsvp = data.events.event?.rsvp;
    return rsvp ? toEventRSVP(rsvp) : null;
  }

  /** The tribes people can identify with here, and the signed-in user's own (empty when signed out). */
  async tribes(): Promise<Tribes> {
    const data = await this.graphQL<{ tribes?: Tag[] | null; me?: { self: { tribes: TribeIdentification[] } } | null }>(Queries.tribes, {
      operationName: "Tribes",
    });
    return { available: data.tribes ?? [], mine: data.me?.self?.tribes ?? [] };
  }

  /** Identifies the signed-in user with a tribe, privately unless `isPrivate` is false. Returns their tribes afterwards. */
  async identifyWithTribe(tagId: string, isPrivate = true): Promise<TribeIdentification[]> {
    const data = await this.graphQL<{ identifyWithTribe: { tribes: TribeIdentification[] } }>(Queries.identifyWithTribe, {
      variables: { tagId, isPrivate },
      operationName: "IdentifyWithTribe",
    });
    return data.identifyWithTribe.tribes;
  }

  /** Takes the signed-in user out of a tribe; nothing is kept. Returns their tribes afterwards. */
  async leaveTribe(tagId: string): Promise<TribeIdentification[]> {
    const data = await this.graphQL<{ leaveTribe: { tribes: TribeIdentification[] } }>(Queries.leaveTribe, {
      variables: { tagId },
      operationName: "LeaveTribe",
    });
    return data.leaveTribe.tribes;
  }

  /** Stores the push notification token for the device this session signed in on. */
  async registerDevice(notificationToken: string): Promise<void> {
    await this.graphQL(Queries.registerDevice, { variables: { notificationToken }, operationName: "RegisterDevice" });
  }

  // Cover charge

  /** A venue's cover tonight and the signed-in user's pass for it, or null when the venue doesn't exist. */
  async venueCover(venueId: string): Promise<VenueCover | null> {
    const data = await this.graphQLForShape<{ venues: { venue?: VenueCover | null } }>(Queries.VENUE_TICKET_TYPES, Queries.venueCover, {
      variables: { id: venueId },
      operationName: "VenueCover",
    });
    return data.venues.venue ?? null;
  }

  /**
   * Starts paying tonight's cover at a venue. For a Stripe venue, finish the payment with Stripe, then call
   * `confirmCover`. For a Square venue, make a payment token and call `payCover`. Asking again the same night returns
   * the same pass.
   *
   * On a sliding scale (`CoverCharge.scale`) `amountCents` is what the buyer chose, from its min to its max; left out,
   * the suggested (or fixed) amount.
   */
  async buyCover(venueId: string, amountCents?: number): Promise<CoverPurchase> {
    const amount = amountCents == null ? null : { cents: amountCents, currency: "usd" };
    const data = await this.graphQL<{ buyCover: CoverPurchase }>(Queries.buyCover, { variables: { venueId, amount }, operationName: "BuyCover" });
    return data.buyCover;
  }

  /** Starts paying tonight's coat check at a venue for `quantity` coats, the same way as `buyCover`. */
  async buyCoatCheck(venueId: string, quantity = 1): Promise<CoverPurchase> {
    const data = await this.graphQL<{ buyCoatCheck: CoverPurchase }>(Queries.buyCoatCheck, {
      variables: { venueId, quantity },
      operationName: "BuyCoatCheck",
    });
    return data.buyCoatCheck;
  }

  /** Pays a Square venue's cover with a payment token (nonce) from Square's SDK. */
  async payCover(admissionId: string, sourceId: string, verificationToken: string | null = null): Promise<Admission> {
    const data = await this.graphQL<{ payCover: { admission: Admission } }>(Queries.payCover, {
      variables: { admissionId, sourceId, verificationToken },
      operationName: "PayCover",
    });
    return data.payCover.admission;
  }

  /** Checks a cover payment with its provider after the app finishes paying, so the pass works straight away. */
  async confirmCover(admissionId: string): Promise<Admission> {
    const data = await this.graphQL<{ confirmCover: { admission: Admission } }>(Queries.confirmCover, {
      variables: { admissionId },
      operationName: "ConfirmCover",
    });
    return data.confirmCover.admission;
  }

  /** Refunds a cover. Buyers can refund their own until it's scanned in or the night is over. */
  async refundAdmission(admissionId: string): Promise<Admission> {
    const data = await this.graphQL<{ refundAdmission: { admission: Admission } }>(Queries.refundAdmission, {
      variables: { admissionId },
      operationName: "RefundAdmission",
    });
    return data.refundAdmission.admission;
  }

  /** The signed-in user's cover passes, newest first. */
  async admissions(): Promise<Admission[]> {
    const data = await this.graphQL<{ me?: { cover: { admissions: Connection<Admission> } } | null }>(Queries.admissions, {
      operationName: "Admissions",
    });
    return connectionItems(data.me?.cover.admissions);
  }

  // Events

  /**
   * The audience's events, soonest first for `UPCOMING` (latest first for `PAST`), in a locale or at a venue when
   * given. Up to `first` of them.
   */
  async events(options: { window?: EventWindow; localeId?: string | null; venueId?: string | null; first?: number } = {}): Promise<Event[]> {
    const data = await this.graphQLForShape<{ events?: { list?: Connection<Event> | null } | null }>(Queries.EVENT_TYPES, Queries.events, {
      variables: {
        window: options.window ?? "UPCOMING",
        localeId: options.localeId ?? null,
        venueId: options.venueId ?? null,
        first: options.first ?? 100,
      },
      operationName: "Events",
    });
    return connectionItems(data.events?.list);
  }

  /** One event, or null when it doesn't exist or belongs to another audience. */
  async event(id: string): Promise<Event | null> {
    const data = await this.graphQLForShape<{ events?: { event?: Event | null } | null }>(Queries.EVENT_TYPES, Queries.event, {
      variables: { id },
      operationName: "Event",
    });
    return data.events?.event ?? null;
  }

  /** The audience's recurring events by name, in a locale or at a venue when given. Up to `first` of them. */
  async eventSeries(options: { localeId?: string | null; venueId?: string | null; first?: number } = {}): Promise<EventSeries[]> {
    const data = await this.graphQLForShape<{ events?: { series?: Connection<EventSeries> | null } | null }>(
      Queries.EVENT_TYPES,
      Queries.eventSeries,
      {
        variables: { localeId: options.localeId ?? null, venueId: options.venueId ?? null, first: options.first ?? 100 },
        operationName: "EventSeries",
      },
    );
    return connectionItems(data.events?.series);
  }

  /**
   * Every way into a venue on a night (tonight when `night` is null, `yyyy-MM-dd` otherwise): its cover and tickets on
   * its events' partner listings. Empty when there are none, or without the Ticketing module.
   */
  async venueOffers(venueId: string, night: string | null = null): Promise<AdmissionOffer[]> {
    const data = await this.graphQLForShape<{ venues?: { venue?: { tickets?: { offers?: Connection<AdmissionOffer> | null } | null } | null } | null }>(
      Queries.VENUE_TICKET_TYPES,
      Queries.venueOffers,
      { variables: { id: venueId, night }, operationName: "VenueOffers" },
    );
    return connectionItems(data.venues?.venue?.tickets?.offers);
  }

  // Venue page and chat

  /**
   * A venue's page with its `recentMessages` latest chat messages (the API gives at most 20), or null when it doesn't
   * exist or belongs to another audience.
   */
  async venueDetail(id: string, recentMessages = 20): Promise<VenueDetail | null> {
    const data = await this.graphQLForShape<{ venues?: { venue?: RawVenueDetail | null } | null }>(Queries.EVENT_TYPES, Queries.venueDetail, {
      variables: { id, recentMessages },
      operationName: "VenueDetail",
    });
    const venue = data.venues?.venue;
    if (!venue) return null;
    const { description, profile, chat, events, ...rest } = venue;
    return {
      venue: { ...rest, profile: profile ?? null } as Venue,
      description: description ?? null,
      address: profile?.address ?? null,
      phone: profile?.phone ?? null,
      website: profile?.website ?? null,
      socialLinks: profile?.socialLinks ? connectionItems(profile.socialLinks) : null,
      chatOpen: chat?.open ?? null,
      recentMessages: chat ? connectionItems(chat.recentMessages) : null,
      upcomingEvents: events ? connectionItems(events.upcoming) : null,
    };
  }

  /** Posts the signed-in user's message to a chat room, as a reply to a chat prompt when `promptId` is given. */
  async sendChatMessage(text: string, room: ChatRoom, promptId: string | null = null): Promise<ChatMessage> {
    const input: Record<string, unknown> = { [chatRoomArgument(room)]: room.id, message: text };
    if (promptId) input.promptId = promptId;
    const data = await this.graphQL<{ sendMyChatMessage: { message: ChatMessage } }>(Queries.sendChatMessage, {
      variables: { input },
      operationName: "SendMyChatMessage",
    });
    return data.sendMyChatMessage.message;
  }

  /** Takes back one of the signed-in user's own messages. */
  async removeChatMessage(id: string): Promise<void> {
    await this.graphQL(Queries.removeChatMessage, { variables: { messageId: id }, operationName: "RemoveMyChatMessage" });
  }

  /**
   * Everything the audience lists, read in one go: the audience, its locales, venues, people, upcoming events and event
   * series. A part whose module the audience doesn't have comes back empty.
   */
  async community(): Promise<Community> {
    const optional = async <T>(read: () => Promise<T>): Promise<T | null> => {
      try {
        return await read();
      } catch (error) {
        if (error instanceof AudienceKitError && error.isUndefinedField) return null;
        throw error;
      }
    };
    const [audience, locales, venues, people, events, eventSeries] = await Promise.all([
      optional(() => this.audience()),
      optional(() => this.locales()),
      optional(() => this.venues()),
      optional(() => this.people()),
      optional(() => this.events()),
      optional(() => this.eventSeries()),
    ]);
    return {
      audience,
      locales: locales ?? [],
      venues: venues ?? [],
      people: people ?? [],
      events: events ?? [],
      eventSeries: eventSeries ?? [],
    };
  }

  // Soapbox (news)

  /**
   * The audience's live articles, pinned first, then newest: a locale's news, or one publication's, when given. Empty
   * when the audience doesn't have Soapbox.
   */
  async articles(options: { localeId?: string | null; publicationId?: string | null; first?: number | null } = {}): Promise<Article[]> {
    const data = await this.graphQLForShape<SoapboxData>(Queries.SOAPBOX_TYPES, Queries.articles, {
      variables: compact({ localeId: options.localeId, publicationId: options.publicationId, first: options.first }),
      operationName: "Articles",
    });
    return data.soapbox?.articles?.nodes?.filter(isPresent) ?? [];
  }

  /**
   * A page of the audience's live articles, for lists that "Show more": pass the last page's `endCursor` as `after`
   * for the next.
   */
  async articlesPage(
    options: { localeId?: string | null; publicationId?: string | null; first?: number; after?: string | null } = {},
  ): Promise<ArticlesPage> {
    const data = await this.graphQLForShape<SoapboxData>(Queries.SOAPBOX_TYPES, Queries.articlesPage, {
      variables: compact({ localeId: options.localeId, publicationId: options.publicationId, first: options.first ?? 20, after: options.after }),
      operationName: "ArticlesPage",
    });
    const connection = data.soapbox?.articles;
    return {
      articles: connection?.nodes?.filter(isPresent) ?? [],
      endCursor: connection?.pageInfo?.endCursor ?? null,
      hasNextPage: connection?.pageInfo?.hasNextPage ?? false,
    };
  }

  /** The audience's national news: articles its admins featured nationally in the last 14 days (a locale's share, when given). */
  async nationalArticles(options: { localeId?: string | null; first?: number | null } = {}): Promise<Article[]> {
    const data = await this.graphQLForShape<SoapboxData>(Queries.SOAPBOX_TYPES, Queries.nationalArticles, {
      variables: compact({ localeId: options.localeId, first: options.first }),
      operationName: "NationalArticles",
    });
    return data.soapbox?.articles?.nodes?.filter(isPresent) ?? [];
  }

  /** One article with its Markdown `body` and what it is about; null when there's none, or no Soapbox. */
  async article(id: string): Promise<Article | null> {
    const data = await this.graphQLForShape<SoapboxData>(Queries.SOAPBOX_TYPES, Queries.article, { variables: { id }, operationName: "Article" });
    return data.soapbox?.article ?? null;
  }

  /** Live articles about a venue, event or person, newest first, or a locale's news: "In the news" on a listing's page. */
  async articlesAbout(topic: Queries.ArticleTopic, id: string, first: number | null = null): Promise<Article[]> {
    type Listing = { articles?: { list?: Connection<Article> | null } | null } | null;
    const data = await this.graphQLForShape<{
      venues?: { venue?: Listing };
      events?: { event?: Listing };
      people?: { person?: Listing };
      locale?: Listing;
    }>([...Queries.SOAPBOX_TYPES, Queries.articlesAboutType(topic)], (shape) => Queries.articlesAbout(topic, shape), {
      variables: compact({ id, first }),
      operationName: "ArticlesAbout",
    });
    const listing = data.venues?.venue ?? data.events?.event ?? data.people?.person ?? data.locale ?? null;
    return connectionItems(listing?.articles?.list ?? null);
  }

  /** The audience's publications. */
  async publications(): Promise<Publication[]> {
    const data = await this.graphQLForShape<SoapboxData>(Queries.SOAPBOX_TYPES, Queries.publications, { operationName: "Publications" });
    return data.soapbox?.publications ?? [];
  }

  /** The publications covering a locale: the "local publishers" at the top of its news. */
  async localPublications(localeId: string): Promise<Publication[]> {
    const wanted = localeId.toLowerCase();
    return (await this.publications()).filter((publication) => publication.locale?.id.toLowerCase() === wanted);
  }

  /** One publication, for its page and its "Write an op-ed" button; null when there's none. */
  async publication(id: string): Promise<Publication | null> {
    const data = await this.graphQLForShape<SoapboxData>(Queries.SOAPBOX_TYPES, Queries.publication, {
      variables: { id },
      operationName: "Publication",
    });
    return data.soapbox?.publication ?? null;
  }

  /** The op-eds the signed-in person sent, newest first, with their `status` and the publication's `reviewNote`. */
  async myOpEds(): Promise<Article[]> {
    const data = await this.graphQLForShape<SoapboxData>(Queries.SOAPBOX_TYPES, Queries.myOpEds, { operationName: "MyOpEds" });
    return data.soapbox?.myOpEds ?? [];
  }

  /**
   * Sends a publication that accepts op-eds an op-ed under the signed-in person's name (`byline` overrides it). The
   * publication runs it or declines it with a note; `myOpEds()` shows which.
   */
  async submitOpEd(input: { publicationId: string; title: string; body: string; summary?: string | null; byline?: string | null }): Promise<Article> {
    const data = await this.graphQL<{ submitOpEd: { article: Article } }>(Queries.submitOpEd, {
      variables: { summary: null, byline: null, ...input },
      operationName: "SubmitOpEd",
    });
    return data.submitOpEd.article;
  }

  // Calendar subscription

  /** The signed-in person's calendar subscription, or null before they made one. */
  async calendarFeed(): Promise<CalendarFeed | null> {
    const data = await this.graphQL<{ me?: { calendarFeed?: CalendarFeed | null } | null }>(Queries.calendarFeed, { operationName: "CalendarFeed" });
    return data.me?.calendarFeed ?? null;
  }

  /**
   * Their subscription, made on first ask: `url`, `webcalUrl` and `googleUrl` add every event they're going to to their
   * own calendar. `reset` gives it a new link, so the old one stops working.
   */
  async createCalendarFeed(reset = false): Promise<CalendarFeed> {
    const data = await this.graphQL<{ createCalendarFeed: { calendarFeed: CalendarFeed } }>(Queries.createCalendarFeed, {
      variables: { reset },
      operationName: "CreateCalendarFeed",
    });
    return data.createCalendarFeed.calendarFeed;
  }

  /** Follows a venue in their subscription, so every event there shows up in their calendar (or, with `following` false, stops). */
  async followVenueInCalendar(venueId: string, following = true): Promise<CalendarFeed> {
    const data = await this.graphQL<{ setCalendarFeedVenue: { calendarFeed: CalendarFeed } }>(Queries.setCalendarFeedVenue, {
      variables: { venueId, following },
      operationName: "SetCalendarFeedVenue",
    });
    return data.setCalendarFeedVenue.calendarFeed;
  }

  /** Ends their subscription: calendars subscribed to it stop updating. */
  async deleteCalendarFeed(): Promise<boolean> {
    const data = await this.graphQL<{ deleteCalendarFeed?: { deleted?: boolean } | null }>(Queries.deleteCalendarFeed, {
      operationName: "DeleteCalendarFeed",
    });
    return data.deleteCalendarFeed?.deleted === true;
  }

  // Moderation and the account

  /**
   * Files a report with the audience's admins (App Store guideline 1.2, Google Play's user-generated content policy).
   * With `block`, the person behind it is blocked too. Offer `REPORT_REASONS` as the reasons.
   */
  async reportContent(targetType: ReportTarget, id: string, options: { reason?: string | null; block?: boolean } = {}): Promise<ReportResult> {
    const data = await this.graphQL<{ reportContent?: Partial<ReportResult> | null }>(Queries.reportContent, {
      variables: { targetType, targetId: id, reason: options.reason ?? null, block: options.block ?? false },
      operationName: "ReportContent",
    });
    return { reported: data.reportContent?.reported === true, blocked: data.reportContent?.blocked === true };
  }

  /** Blocks a member (their user ID): they and the signed-in person stop seeing each other's messages. */
  async blockUser(userId: string): Promise<void> {
    await this.graphQL(Queries.blockUser, { variables: { userId }, operationName: "BlockUser" });
  }

  /** Unblocks a member blocked with `blockUser` or a report. */
  async unblockUser(userId: string): Promise<void> {
    await this.graphQL(Queries.unblockUser, { variables: { userId }, operationName: "UnblockUser" });
  }

  /**
   * Deletes the signed-in person's account for good (App Store guideline 5.1.1(v), Google Play's account deletion
   * rule). The API erases their data and signs them out everywhere, so the session is forgotten here too. It can't be
   * undone: ask first. Returns whether the account is gone; when it isn't, the person stays signed in.
   */
  async deleteAccount(): Promise<boolean> {
    const data = await this.graphQL<{ deleteAccount?: { deleted?: boolean } | null }>(Queries.deleteAccount, {
      variables: { confirm: true },
      operationName: "DeleteAccount",
    });
    const deleted = data.deleteAccount?.deleted === true;
    if (deleted) await this.signOut();
    return deleted;
  }

  // Public listings (REST)

  /**
   * One page (from 1) of the audience's public listings: up to 500 venues, then events, then posts, as its websites
   * show them. Needs a service token with the `public:read` scope (`useServiceToken`).
   */
  async publicListingsPage(page = 1): Promise<PublicListingsPage> {
    const json = this.parseJson(await this.data({ path: "/v1/public/listings", query: { page: String(Math.max(1, page)) } })) as {
      listings?: PublicListing[] | null;
      page_count?: number | string | null;
      next_page?: number | string | null;
    } | null;
    const number = (value: unknown): number | null => {
      const parsed = typeof value === "number" ? value : typeof value === "string" && value !== "" ? Number(value) : NaN;
      return Number.isFinite(parsed) ? parsed : null;
    };
    return {
      listings: Array.isArray(json?.listings) ? json.listings : [],
      pageCount: number(json?.page_count) ?? 1,
      nextPage: number(json?.next_page),
    };
  }

  /** Every public listing, page by page. */
  async publicListings(): Promise<PublicListing[]> {
    const listings: PublicListing[] = [];
    let page = 1;
    for (;;) {
      const found = await this.publicListingsPage(page);
      listings.push(...found.listings);
      if (found.nextPage === null || found.nextPage <= page) return listings;
      page = found.nextPage;
    }
  }

  /** One public listing, or null when there's none. */
  async publicListing(kind: "venue" | "event" | "post", id: string): Promise<PublicListing | null> {
    const paths = { venue: "venues", event: "events", post: "posts" } as const;
    const path = paths[kind];
    if (!path) throw new TypeError(`A listing is a venue, event or post, not ${String(kind)}.`);
    try {
      return this.parseJson(await this.data({ path: `/v1/public/${path}/${encodeURIComponent(id)}` })) as PublicListing;
    } catch (error) {
      if (error instanceof AudienceKitError && error.code === "NOT_FOUND") return null;
      throw error;
    }
  }

  /** Tonight at a venue, as a screen facing the room shows it: tonight's event, who's on and what's next. */
  async publicTonight<T = Record<string, unknown>>(venueId: string): Promise<T> {
    return this.parseJson(await this.data({ path: `/v1/public/venues/${encodeURIComponent(venueId)}/tonight` })) as T;
  }

  // REST

  /** Sends a request to a REST endpoint and returns the body of a successful response. */
  async data(request: APIRequest): Promise<string> {
    const authenticated = request.authenticated ?? true;
    if (authenticated) await this.ensureSession();
    let token = authenticated ? await this.storedToken() : null;
    if (authenticated && token === null) throw AudienceKitError.notSignedIn();

    let response = await this.perform(request, token);
    if (response.status === 401 && token !== null && this.serviceToken !== null) {
      // A service session the API refused (a key rotation, say): trade the token once more and try again.
      token = (await this.tradeServiceToken()).token;
      response = await this.perform(request, token);
    }
    if (response.status >= 200 && response.status < 300) return response.body;
    if (response.status === 401 && token !== null) {
      await this.sessionRejected(token);
      throw AudienceKitError.unauthorized();
    }
    throw AudienceKitError.forStatus(response.status, response.body);
  }

  /** Resolves a URL the API sent (absolute, or a path relative to the base URL). */
  url(string: string | null | undefined): string | null {
    if (!string) return null;
    try {
      return new URL(string, `${this.configuration.baseUrl}/`).toString();
    } catch {
      return null;
    }
  }

  private async storedToken(): Promise<string | null> {
    try {
      return (await this.tokenStore.loadToken()) ?? null;
    } catch {
      return null;
    }
  }

  private async perform(request: APIRequest, token: string | null): Promise<HttpResponse> {
    await this.pacer.acquire();
    let response: HttpResponse;
    try {
      response = await this.transport.execute(this.makeHttpRequest(request, token));
    } catch (error) {
      throw AudienceKitError.network(error);
    }
    const headers = response.headers ?? {};
    this.pacer.observe(response.status, headers["retry-after"] ?? headers["Retry-After"]);
    return response;
  }

  private makeHttpRequest(request: APIRequest, token: string | null): HttpRequest {
    const path = request.path.startsWith("/") ? request.path : `/${request.path}`;
    const query = Object.entries(request.query ?? {})
      .filter((entry): entry is [string, string | null] => entry[1] !== undefined)
      .map(([name, value]) => (value === null ? encodeURIComponent(name) : `${encodeURIComponent(name)}=${encodeURIComponent(value)}`))
      .join("&");
    const url = this.configuration.baseUrl + path + (query ? `?${query}` : "");

    const headers: Record<string, string> = {
      Accept: "application/json",
      "X-AudienceKit-Client": `AudienceKit-Node/${AudienceKitSDK.VERSION}`,
      "X-AudienceKit-API-Version": AudienceKitSDK.API_VERSION,
    };
    if (this.configuration.environment !== "production") headers[ENVIRONMENT_HEADER] = this.configuration.environment;
    const body = request.body === undefined ? null : JSON.stringify(request.body);
    if (body !== null) headers["Content-Type"] = "application/json";
    if (token !== null) headers.Authorization = `Bearer ${token}`;
    Object.assign(headers, request.headers ?? {});

    return { method: request.method ?? "GET", url, headers, body, signal: request.signal };
  }

  private parseJson(text: string): unknown {
    try {
      return JSON.parse(text);
    } catch (error) {
      throw AudienceKitError.decoding(error instanceof Error ? error.message : "The body wasn't JSON.");
    }
  }
}

interface SoapboxData {
  soapbox?: {
    articles?: { nodes?: (Article | null)[] | null; pageInfo?: { endCursor?: string | null; hasNextPage?: boolean } | null } | null;
    article?: Article | null;
    publications?: Publication[] | null;
    publication?: Publication | null;
    myOpEds?: Article[] | null;
  } | null;
}

/** `values` without the nulls and undefineds, for variables a document declares as optional. */
function compact(values: Record<string, unknown>): Record<string, unknown> | null {
  const kept = Object.fromEntries(Object.entries(values).filter(([, value]) => value !== null && value !== undefined));
  return Object.keys(kept).length > 0 ? kept : null;
}

function isPresent<T>(value: T | null | undefined): value is T {
  return value !== null && value !== undefined;
}

/** An event's rsvp mixin as the API sends it, attendees in a connection. */
interface RawRSVP {
  count: number;
  mine: RSVPState;
  mineSource?: EventRSVP["mineSource"];
  counts?: EventRSVP["counts"];
  attendees?: Connection<EventRSVP["attendees"][number]> | null;
}

function toEventRSVP(raw: RawRSVP): EventRSVP {
  return { count: raw.count, mine: raw.mine, mineSource: raw.mineSource ?? null, counts: raw.counts ?? null, attendees: connectionItems(raw.attendees) };
}

interface RawVenueDetail extends Omit<Venue, "profile"> {
  description?: string | null;
  profile?: (Venue["profile"] & { address?: string | null; phone?: string | null; website?: string | null; socialLinks?: Connection<SocialLink> | null }) | null;
  chat?: { open?: boolean | null; recentMessages?: Connection<ChatMessage> | null } | null;
  events?: { upcoming?: Connection<Event> | null } | null;
}
