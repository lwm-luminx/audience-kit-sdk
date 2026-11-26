// What a consumer website (hotmess.social) asks the API, on top of an `AudienceKitClient`: its pages' GraphQL
// (`Website.Queries`) and the public REST calls that need no sign-in (share links, the cover and safety posters, the
// community resource directory, invitations, the promoted rate card). Moved here from hotmess.social so apps share them.

import type { AudienceKitClient } from "../client.js";
import { AudienceKitError } from "../errors.js";
import type * as Models from "./models.js";
import * as Queries from "./queries.js";

/** A JSON object as the API sends it, for the REST answers a site reads with its own parser. */
export type Json = Record<string, unknown>;

/** The details of a safety alert from a poster (lower-case, as the REST API takes them). */
export interface GuestSafetyDetails {
  place?: string | null;
  concerns?: string[];
  description?: string | null;
}

/** The variables `updatePrivacyChoices` takes: only the choices to change. */
export interface PrivacyChoicesUpdate {
  saleShareOptOut?: boolean;
  adMeasurement?: boolean;
  personalizedAds?: boolean;
}

function found<T>(value: T | null | undefined): T {
  if (value === null || value === undefined) throw AudienceKitError.notFound();
  return value;
}

function nodes<T>(connection: Models.Connection<T> | null | undefined): T[] {
  return (connection?.nodes ?? []).filter((node): node is T => node !== null && node !== undefined);
}

function draftVariables(draft: Models.SafetyDraft): Json {
  const description = draft.description.trim();
  return { place: draft.place, concerns: draft.concerns, description: description || null };
}

type AlertPayload<K extends string> = Record<K, { safetyAlert: Models.SafetyAlert | null } | null>;

function alertFrom<K extends string>(payload: AlertPayload<K>, key: K): Models.SafetyAlert {
  const alert = payload[key]?.safetyAlert;
  if (!alert) throw AudienceKitError.decoding(`${key} returned no alert.`);
  return alert;
}

/**
 * A website's calls. `new WebsiteClient(client)`; REST calls that name the audience send the client's configured
 * `host` (or the one given).
 */
export class WebsiteClient {
  constructor(readonly client: AudienceKitClient) {}

  /** Runs one of `Queries`, naming its operation in the body (`operationName`), as the API's logs and mocks read it. */
  private graphQL<T>(query: string, variables: Json = {}): Promise<T> {
    const operationName = /^\s*(?:query|mutation)\s+(\w+)/.exec(query)![1]!;
    return this.client.graphQL<T>(query, { variables, operationName });
  }

  private host(host?: string | null): string {
    const chosen = host ?? this.client.configuration.host;
    if (!chosen) throw AudienceKitError.missingConfiguration("this call needs a host");
    return chosen;
  }

  private async json<T>(path: string, options: { method?: string; query?: Record<string, string>; body?: unknown; headers?: Record<string, string>; authenticated?: boolean } = {}): Promise<T> {
    const text = await this.client.data({ ...options, path, authenticated: options.authenticated ?? false });
    try {
      return JSON.parse(text) as T;
    } catch {
      throw AudienceKitError.decoding(`${path} didn't answer JSON.`);
    }
  }

  /** `json`, but null for a 404. */
  private async jsonOrNull<T>(path: string, options: Parameters<WebsiteClient["json"]>[1] = {}): Promise<T | null> {
    try {
      return await this.json<T>(path, options);
    } catch (error) {
      if (error instanceof AudienceKitError && error.code === "NOT_FOUND") return null;
      throw error;
    }
  }

  // Pages

  /** Records where someone is, which is how the API knows the venue they're at, and answers what's around them. */
  async now(latitude: number, longitude: number): Promise<Models.Now> {
    return (await this.graphQL<{ reportLocation: Models.Now }>(Queries.now, { position: { latitude, longitude } })).reportLocation;
  }

  /** The cities someone is in, innermost first. */
  async whereAmI(latitude: number, longitude: number): Promise<Models.Place[]> {
    const { reportLocation } = await this.graphQL<{ reportLocation: { locale: Models.Place | null; locales: Models.Place[] | null } }>(
      Queries.whereAmI,
      { position: { latitude, longitude } },
    );
    return [...(reportLocation.locales ?? []), ...(reportLocation.locale ? [reportLocation.locale] : [])];
  }

  /** A venue and its upcoming events, in one request. Throws `NOT_FOUND` for one that isn't there. */
  async venue(id: string): Promise<{ venue: Models.Venue; events: Models.Event[] }> {
    const { events, ...venue } = found((await this.graphQL<{ venues: { venue: Models.Venue | null } }>(Queries.venuePage, { id })).venues.venue);
    return { venue, events: nodes(events?.upcoming) };
  }

  async event(id: string): Promise<Models.Event> {
    return found((await this.graphQL<{ events: { event: Models.Event | null } }>(Queries.eventPage, { id })).events.event);
  }

  async person(id: string): Promise<Models.Person> {
    return found((await this.graphQL<{ people: { person: Models.Person | null } }>(Queries.personPage, { id })).people.person);
  }

  async post(id: string): Promise<Models.Post> {
    return found((await this.graphQL<{ posts: { post: Models.Post | null } }>(Queries.post, { id })).posts.post);
  }

  /** The id of the person signed in to the audience, or null when the session isn't (the API answers no `me`). */
  async viewerId(): Promise<string | null> {
    const data = await this.graphQL<{ me: { self: { id: string } | null } | null }>(Queries.viewer);
    return data.me?.self?.id ?? null;
  }

  // Posters

  /** Venues (visible ones) matching a search by name. */
  async posterSearch(search: string): Promise<Models.PosterVenue[]> {
    return nodes((await this.graphQL<{ venues: { list: Models.Connection<Models.PosterVenue> } }>(Queries.posterSearch, { search })).venues.list);
  }

  /** A venue's upcoming events, each with the series it belongs to. */
  async posterNights(venueId: string): Promise<Models.PosterEvent[]> {
    const result = await this.graphQL<{ venues: { venue: { events: { upcoming: Models.Connection<Models.PosterEvent> } } | null } }>(
      Queries.posterNights,
      { id: venueId },
    );
    return nodes(found(result.venues.venue).events.upcoming);
  }

  /** A series and its coming dates. */
  async posterSeries(id: string): Promise<{ series: Models.PosterSeries; events: Models.PosterEvent[] }> {
    const result = await this.graphQL<{ events: { eventSeries: (Models.PosterSeries & { events: Models.PosterEvent[] | null }) | null } }>(
      Queries.posterSeries,
      { id },
    );
    const { events, ...series } = found(result.events.eventSeries);
    return { series, events: events ?? [] };
  }

  async posterVenue(id: string): Promise<Models.PosterVenue> {
    return found((await this.graphQL<{ venues: { venue: Models.PosterVenue | null } }>(Queries.posterVenue, { id })).venues.venue);
  }

  /** An event, and its share link signed to open for a year (null when the API won't sign one). */
  async posterEvent(id: string, path = `/events/${id}`): Promise<{ event: Models.PosterEvent; link: string | null }> {
    const result = await this.graphQL<{ events: { event: Models.PosterEvent | null }; shareLink: { url: string } | null }>(
      Queries.posterEvent,
      { id, path },
    );
    return { event: found(result.events.event), link: result.shareLink?.url ?? null };
  }

  /** What a venue charges at the door, for its cover poster: null when it has no cover set up. */
  async posterCover(venueId: string): Promise<Models.PosterCover | null> {
    const result = await this.graphQL<{ venues: { venue: { tickets: { cover: Models.PosterCover | null } | null } | null } }>(
      Queries.posterCover,
      { id: venueId },
    );
    return found(result.venues.venue).tickets?.cover ?? null;
  }

  /** The venue's safety poster link, made the first time; only its managers get one (FORBIDDEN for anyone else). */
  async printSafetyPoster(venueId: string): Promise<string> {
    const result = await this.graphQL<{ printSafetyPoster: { safetyPoster: { url: string } | null } | null }>(Queries.printSafetyPoster, { venueId });
    const url = result.printSafetyPoster?.safetyPoster?.url;
    if (!url) throw AudienceKitError.decoding("printSafetyPoster returned no poster.");
    return url;
  }

  // Safety alerts

  /** Whether someone can send a safety alert from a venue; null for no such venue. */
  async venueSafety(venueId: string): Promise<Models.VenueSafety | null> {
    return (await this.graphQL<{ venues: { venue: Models.VenueSafety | null } }>(Queries.venueSafety, { id: venueId })).venues.venue;
  }

  async sendSafetyAlert(venueId: string, draft: Models.SafetyDraft): Promise<Models.SafetyAlert> {
    return alertFrom(await this.graphQL<AlertPayload<"sendSafetyAlert">>(Queries.sendSafetyAlert, { venueId, ...draftVariables(draft) }), "sendSafetyAlert");
  }

  async updateSafetyAlert(id: string, draft: Models.SafetyDraft): Promise<Models.SafetyAlert> {
    return alertFrom(await this.graphQL<AlertPayload<"updateSafetyAlert">>(Queries.updateSafetyAlert, { id, ...draftVariables(draft) }), "updateSafetyAlert");
  }

  async remindSafetyAlert(id: string): Promise<Models.SafetyAlert> {
    return alertFrom(await this.graphQL<AlertPayload<"remindSafetyAlert">>(Queries.remindSafetyAlert, { id }), "remindSafetyAlert");
  }

  async cancelSafetyAlert(id: string): Promise<Models.SafetyAlert> {
    return alertFrom(await this.graphQL<AlertPayload<"cancelSafetyAlert">>(Queries.cancelSafetyAlert, { id }), "cancelSafetyAlert");
  }

  async sendSafetyAlertMessage(id: string, body: string): Promise<Models.SafetyAlert> {
    return alertFrom(
      await this.graphQL<AlertPayload<"sendSafetyAlertMessage">>(Queries.sendSafetyAlertMessage, { id, body: body.trim() }),
      "sendSafetyAlertMessage",
    );
  }

  async safetyAlert(id: string): Promise<Models.SafetyAlert | null> {
    return (await this.graphQL<{ me: { safetyAlert: Models.SafetyAlert | null } | null }>(Queries.safetyAlert, { id })).me?.safetyAlert ?? null;
  }

  async mySafetyAlerts(): Promise<Models.SafetyAlert[]> {
    return (await this.graphQL<{ me: { safetyAlerts: Models.SafetyAlert[] | null } | null }>(Queries.mySafetyAlerts)).me?.safetyAlerts ?? [];
  }

  /** "Need support?": the region's lines (the audience's own region when `region` is null). */
  async supportResources(region: string | null = null): Promise<Models.SupportResources> {
    return (await this.graphQL<{ supportResources: Models.SupportResources }>(Queries.supportResources, { region })).supportResources;
  }

  /** "Get a ride": the region's ride apps. */
  async supportRides(region: string | null = null): Promise<Models.SupportRide[]> {
    return (await this.graphQL<{ supportResources: { rides: Models.SupportRide[] | null } }>(Queries.supportRides, { region })).supportResources.rides ?? [];
  }

  // Privacy choices

  async privacy(): Promise<Models.Privacy> {
    return this.graphQL<Models.Privacy>(Queries.privacy);
  }

  async updatePrivacyChoices(update: PrivacyChoicesUpdate): Promise<Models.PrivacyChoices> {
    return (await this.graphQL<{ updatePrivacyChoices: { privacy: Models.PrivacyChoices } }>(Queries.updatePrivacyChoices, { ...update }))
      .updatePrivacyChoices.privacy;
  }

  /** Starts a privacy pass's checkout, which returns to `returnUrl`. */
  async startPrivacyPass(returnUrl: string | null = null): Promise<Models.PrivacyPassCheckout> {
    return (await this.graphQL<{ startPrivacyPass: Models.PrivacyPassCheckout }>(Queries.startPrivacyPass, { returnUrl })).startPrivacyPass;
  }

  // Public REST

  /**
   * The ways the audience lets people sign in (`GET /v1/token/methods`), with the warning to show before each one that
   * has one; null when the API can't say (an API from before the setting answers 404).
   */
  async signInMethods(host?: string): Promise<Models.SignInMethods | null> {
    const answer = await this.jsonOrNull<{ methods?: string[]; warnings?: Record<string, string> }>("/v1/token/methods", {
      query: { host: this.host(host) },
    });
    return answer?.methods ? { methods: answer.methods, warnings: answer.warnings ?? {} } : null;
  }

  /**
   * The API's answer for a share link (`GET /v1/share`): 200 with the card a link preview shows, 404 for nothing to
   * share, 410 for an expired or forged signed link. `signature` is the link's `e`, or null for an unsigned one.
   */
  async shareLink<T = Json>(path: string, signature: string | null = null, host?: string): Promise<Models.ShareLinkAnswer<T>> {
    const query: Record<string, string> = { path, host: this.host(host) };
    if (signature !== null) query.e = signature;
    try {
      return { status: 200, card: await this.json<T>("/v1/share", { query }) };
    } catch (error) {
      if (error instanceof AudienceKitError && error.status !== undefined) return { status: error.status, card: null };
      throw error;
    }
  }

  /** A Ping's invitation (`GET /v1/share/invitation`), for its signed link; null when it ended or isn't there. */
  async invitation<T = Json>(pingId: string, signature: string, host?: string): Promise<T | null> {
    try {
      return await this.json<T>("/v1/share/invitation", { query: { host: this.host(host), path: `/pings/${pingId}`, e: signature } });
    } catch (error) {
      if (error instanceof AudienceKitError && error.status !== undefined && error.status < 500 && error.status !== 429) return null;
      throw error;
    }
  }

  /** The promoted placement rate card (`GET /v1/promoted/rate_card`). */
  rateCard<T = Json>(): Promise<T> {
    return this.json<T>("/v1/promoted/rate_card");
  }

  /** The cities with community resources (`GET /v1/audience/:id/community_resources/locales`). */
  async communityResourceLocales<T = Json>(): Promise<T> {
    return this.json<T>(`/v1/audience/${await this.client.audienceId()}/community_resources/locales`);
  }

  /** A city's community resource directory, or null for no such city. */
  async communityResources<T = Json>(localeId: string): Promise<T | null> {
    return this.jsonOrNull<T>(`/v1/audience/${await this.client.audienceId()}/community_resources`, { query: { locale_id: localeId } });
  }

  /**
   * Where a venue's short link (`/v/<code>`) goes (`GET /v1/public/v/:code`, a `public:read` service session), or null
   * for no such venue.
   */
  async publicShortLink(code: string): Promise<string | null> {
    const answer = await this.jsonOrNull<{ path?: unknown }>(`/v1/public/v/${encodeURIComponent(code)}`, { authenticated: true });
    return typeof answer?.path === "string" ? answer.path : null;
  }

  // The cover poster: a venue's lobby poster, paid without an account (audience_kit_api doc/APP_CLIP_CHECKOUT.md).

  /** What a cover poster sells right now (`GET /v1/cover/:code`); null for a code that names no venue. */
  coverPoster<T = Json>(code: string, host?: string): Promise<T | null> {
    return this.jsonOrNull<T>(`/v1/cover/${encodeURIComponent(code)}`, { query: { host: this.host(host) } });
  }

  /**
   * Starts a guest's cover checkout (`POST /v1/clip/covers`). `amountCents` is what the guest chose to pay for each cover
   * on a sliding scale; null pays the set price.
   */
  startGuestCover<T = Json>(venueId: string, quantity: number, tier: string | null, amountCents: number | null = null): Promise<T> {
    const body: Json = { host: this.host(), venue_id: venueId, quantity, tier };
    if (amountCents !== null) body.amount_cents = amountCents;
    return this.json<T>("/v1/clip/covers", { method: "POST", body });
  }

  /** Confirms a guest's paid cover with its one-time claim token; answers `{ admission }`. */
  confirmGuestCover<T = Json>(admissionId: string, claimToken: string): Promise<T> {
    return this.json<T>(`/v1/clip/covers/${encodeURIComponent(admissionId)}/confirm`, {
      method: "POST",
      body: { host: this.host(), claim_token: claimToken },
    });
  }

  // The safety poster: a guest without an account sends the venue's staff a safety alert, then follows it with the
  // guest token the API hands back once (audience_kit_api doc/SAFETY_ALERTS.md, "Safety posters").

  private safetyCall<T>(path: string, token: string | null, method = "GET", body?: unknown): Promise<T> {
    return this.json<T>(path, {
      method,
      body,
      query: { host: this.host() },
      headers: token ? { "X-Safety-Token": token } : undefined,
    });
  }

  /** The venue a safety poster names, and whether its staff are on shift; null for no such poster. */
  async safetyPoster<T = Json>(code: string): Promise<T | null> {
    try {
      return await this.safetyCall<T>(`/v1/safety/posters/${encodeURIComponent(code)}`, null);
    } catch (error) {
      if (error instanceof AudienceKitError && error.code === "NOT_FOUND") return null;
      throw error;
    }
  }

  /** Sends a safety alert from a poster; answers `{ alert, guest_token }`. */
  sendGuestSafetyAlert<T = Json>(code: string, details: GuestSafetyDetails, token: string | null = null): Promise<T> {
    return this.safetyCall<T>(`/v1/safety/posters/${encodeURIComponent(code)}/alerts`, token, "POST", details);
  }

  /** A guest's alert; answers `{ alert }`. */
  guestSafetyAlert<T = Json>(id: string, token: string): Promise<T> {
    return this.safetyCall<T>(`/v1/safety/alerts/${encodeURIComponent(id)}`, token);
  }

  updateGuestSafetyAlert<T = Json>(id: string, token: string, details: GuestSafetyDetails): Promise<T> {
    return this.safetyCall<T>(`/v1/safety/alerts/${encodeURIComponent(id)}/details`, token, "POST", details);
  }

  remindGuestSafetyAlert<T = Json>(id: string, token: string): Promise<T> {
    return this.safetyCall<T>(`/v1/safety/alerts/${encodeURIComponent(id)}/remind`, token, "POST");
  }

  cancelGuestSafetyAlert<T = Json>(id: string, token: string): Promise<T> {
    return this.safetyCall<T>(`/v1/safety/alerts/${encodeURIComponent(id)}/cancel`, token, "POST");
  }

  messageGuestSafetyAlert<T = Json>(id: string, token: string, body: string): Promise<T> {
    return this.safetyCall<T>(`/v1/safety/alerts/${encodeURIComponent(id)}/messages`, token, "POST", { body });
  }
}
