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
}

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
  private readonly listeners = new Set<SessionListener>();
  private resolvedAudienceId: string | null = null;
  /** The fields each type has in an audience's schema, by "audience|endpoint|type" (`schemaFields`). */
  private readonly schemaFieldCache = new Map<string, Set<string>>();

  constructor(options: AudienceKitClientOptions = {}) {
    this.configuration = resolveConfiguration(options.configuration);
    this.tokenStore = options.tokenStore ?? new InMemoryTokenStore();
    this.transport = options.transport ?? new FetchTransport();
    this.monitor = options.monitor ?? null;
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
   */
  async buyCover(venueId: string): Promise<CoverPurchase> {
    const data = await this.graphQL<{ buyCover: CoverPurchase }>(Queries.buyCover, { variables: { venueId }, operationName: "BuyCover" });
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

  // REST

  /** Sends a request to a REST endpoint and returns the body of a successful response. */
  async data(request: APIRequest): Promise<string> {
    const authenticated = request.authenticated ?? true;
    const token = authenticated ? await this.storedToken() : null;
    if (authenticated && token === null) throw AudienceKitError.notSignedIn();

    const response = await this.perform(request, token);
    if (response.status >= 200 && response.status < 300) return response.body;
    if (response.status === 401 && token !== null) {
      await this.sessionRejected(token);
      throw AudienceKitError.unauthorized();
    }
    throw AudienceKitError.forStatus(response.status);
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
    try {
      return await this.transport.execute(this.makeHttpRequest(request, token));
    } catch (error) {
      throw AudienceKitError.network(error);
    }
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
