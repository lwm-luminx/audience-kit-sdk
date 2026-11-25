// A Velvet screen's venue device sign-in, for screens that run JavaScript (Samsung TVs on Tizen): QR pairing and
// typed codes (doc/VENUE_DEVICES.md in the API), then GraphQL on the token's staff endpoint and its cable.

import { AudienceKitSDK } from "../version.js";
import { GraphQLCable, realtimeUrl, type CableHandlers, type CableSocketFactory } from "./cable.js";

/** Where the screen keeps its sign-in between launches (a TV's localStorage). */
export interface VelvetStorage {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
}

/** The venue a device is signed in to (`venue_device` in the API's answer). */
export interface VenueDevice {
  id: string;
  venueId: string;
  venueName: string;
  permissions: string[];
  audienceId: string;
}

/** A pairing the screen shows while it waits: `url` as a QR code, `code` as text. */
export interface VenuePairing {
  code: string;
  url: string;
  pollToken: string;
  expiresAt: Date;
  /** Seconds between asks. */
  interval: number;
}

interface Stored {
  token: string;
  endpoint: string;
  device: VenueDevice;
}

const STORAGE_KEY = "velvet.device";

export type FetchLike = (url: string, init: { method: string; headers: Record<string, string>; body?: string }) =>
  Promise<{ status: number; ok: boolean; json(): Promise<unknown> }>;

export interface VenueDeviceClientOptions {
  baseUrl?: string;
  storage: VelvetStorage;
  fetch?: FetchLike;
  socket?: CableSocketFactory;
  /** Told once when the API ends this device's sign-in (revoked, or the venue's access went). */
  onEnded?: () => void;
}

/** An answer the API refused, with its HTTP status. */
export class VelvetHttpError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

function deviceFrom(value: unknown): VenueDevice | null {
  const body = (value ?? {}) as Record<string, unknown>;
  const audience = (body.audience ?? {}) as Record<string, unknown>;
  if (typeof body.id !== "string" || typeof body.venue_id !== "string") return null;
  return {
    id: body.id,
    venueId: body.venue_id,
    venueName: typeof body.venue_name === "string" ? body.venue_name : "",
    permissions: Array.isArray(body.permissions) ? body.permissions.map(String) : [],
    audienceId: typeof audience.id === "string" ? audience.id : "",
  };
}

export class VenueDeviceClient {
  readonly baseUrl: string;
  private readonly storage: VelvetStorage;
  private readonly fetchImpl: FetchLike;
  private readonly socket: CableSocketFactory | null;
  private readonly onEnded: (() => void) | undefined;
  private stored: Stored | null;
  private cable: GraphQLCable | null = null;

  constructor(options: VenueDeviceClientOptions) {
    this.baseUrl = (options.baseUrl ?? AudienceKitSDK.PRODUCTION_BASE_URL).replace(/\/+$/, "");
    this.storage = options.storage;
    const globalFetch = (globalThis as { fetch?: FetchLike }).fetch;
    this.fetchImpl = options.fetch ?? ((url, init) => globalFetch!(url, init));
    const SocketType = (globalThis as { WebSocket?: new (url: string, protocols: string[]) => unknown }).WebSocket;
    this.socket = options.socket ?? (SocketType ? (url, protocols) => new SocketType(url, protocols) as never : null);
    this.onEnded = options.onEnded;
    this.stored = this.load();
  }

  /** The venue this screen is signed in to, or null. */
  get device(): VenueDevice | null {
    return this.stored?.device ?? null;
  }

  /** Starts pairing this screen by QR code. `platform` says what's asking: "tizen" for a Samsung TV. */
  async startPairing(identifier: string, platform: string): Promise<VenuePairing> {
    const body = (await this.rest("POST", "/v1/venue-devices/pairings", { identifier, platform })) as Record<string, unknown>;
    return {
      code: String(body.code ?? ""),
      url: String(body.url ?? ""),
      pollToken: String(body.poll_token ?? ""),
      expiresAt: new Date(String(body.expires_at ?? "")),
      interval: Number(body.interval ?? 3) || 3,
    };
  }

  /**
   * Whether a venue manager has approved the pairing: null while it waits; once approved, signs this screen in.
   * Throws a VelvetHttpError (410) once the pairing expired or was already picked up.
   */
  async claimPairing(pairing: VenuePairing): Promise<VenueDevice | null> {
    const response = await this.request("POST", "/v1/venue-devices/pairings/claim", { poll_token: pairing.pollToken }, false);
    if (response.status === 202) return null;
    return this.adopt(await this.body(response));
  }

  /** Signs in with a device code typed with the remote (Velvet › Settings › Devices & codes, or App Review's). */
  async redeem(code: string, identifier: string): Promise<VenueDevice> {
    return this.adopt(await this.rest("POST", "/v1/venue-devices/redeem", { code: code.trim(), identifier }));
  }

  /** The server's clock (`/v1/status`'s `api.time`), for timing the board against it. */
  async serverTime(): Promise<Date | null> {
    const body = (await this.rest("GET", "/v1/status")) as { api?: { time?: string } };
    const time = body.api?.time ? Date.parse(body.api.time) : NaN;
    return Number.isNaN(time) ? null : new Date(time);
  }

  /** Runs `query` on the device's endpoint; the `data` it answers. Throws on errors. */
  async graph(query: string, variables: Record<string, unknown> = {}): Promise<Record<string, unknown>> {
    const stored = this.stored;
    if (!stored) throw new VelvetHttpError(401, "This screen isn't signed in");
    const response = await this.request("POST", stored.endpoint, { query, variables }, true);
    const body = (await this.body(response)) as { data?: Record<string, unknown>; errors?: { message?: string }[] };
    if (body.errors && body.errors.length > 0 && !body.data) {
      throw new VelvetHttpError(200, body.errors.map((error) => error.message ?? "GraphQL error").join("; "));
    }
    return body.data ?? {};
  }

  /** Follows a subscription on the device's cable; returns what stops it. */
  subscribe(query: string, variables: Record<string, unknown>, handlers: CableHandlers): () => void {
    const stored = this.stored;
    if (!stored || !this.socket) return () => undefined;
    if (!this.cable) {
      this.cable = new GraphQLCable(realtimeUrl(this.baseUrl), () => this.stored?.token ?? null, stored.device.audienceId, this.socket);
    }
    return this.cable.subscribe(query, variables, handlers);
  }

  /** Forgets the sign-in on this screen (and tells the API, best effort). */
  async signOut(): Promise<void> {
    const signedIn = !!this.stored;
    if (signedIn) await this.request("DELETE", "/v1/token", undefined, true).catch(() => undefined);
    this.forget();
  }

  private forget(): void {
    this.cable?.close();
    this.cable = null;
    this.stored = null;
    this.storage.removeItem(STORAGE_KEY);
  }

  private adopt(body: unknown): VenueDevice {
    const answer = (body ?? {}) as Record<string, unknown>;
    const device = deviceFrom(answer.venue_device);
    const token = typeof answer.token === "string" ? answer.token : "";
    if (!device || !token) throw new Error("The server did not return a venue device session.");
    if (!device.audienceId && typeof answer.audienceId === "string") device.audienceId = answer.audienceId;
    const endpoint =
      typeof answer.endpoint === "string" && answer.endpoint
        ? answer.endpoint
        : `${this.baseUrl}/v1/audience/${device.audienceId}/staffql`;
    this.cable?.close();
    this.cable = null;
    this.stored = { token, endpoint, device };
    this.storage.setItem(STORAGE_KEY, JSON.stringify(this.stored));
    return device;
  }

  private load(): Stored | null {
    try {
      const value = JSON.parse(this.storage.getItem(STORAGE_KEY) ?? "null") as Stored | null;
      return value && value.token && value.endpoint && value.device?.venueId ? value : null;
    } catch {
      return null;
    }
  }

  private async rest(method: string, path: string, body?: unknown): Promise<unknown> {
    return this.body(await this.request(method, path, body, false));
  }

  private async request(method: string, path: string, body: unknown, authenticated: boolean) {
    const headers: Record<string, string> = {
      Accept: "application/json",
      "X-AudienceKit-Client": `AudienceKit-Node/${AudienceKitSDK.VERSION}`,
      "X-AudienceKit-API-Version": AudienceKitSDK.API_VERSION,
    };
    if (body !== undefined) headers["Content-Type"] = "application/json";
    if (authenticated && this.stored) headers.Authorization = `Bearer ${this.stored.token}`;
    const url = /^https?:\/\//.test(path) ? path : `${this.baseUrl}${path}`;
    const response = await this.fetchImpl(url, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
    if (response.status === 401 && authenticated && this.stored) {
      this.forget();
      this.onEnded?.();
    }
    return response;
  }

  private async body(response: { status: number; ok: boolean; json(): Promise<unknown> }): Promise<unknown> {
    const body = await response.json().catch(() => ({}));
    if (!response.ok) {
      const error = (body as { error?: { message?: string } | string }).error;
      const message = typeof error === "string" ? error : error?.message;
      throw new VelvetHttpError(response.status, message || `HTTP ${response.status}`);
    }
    return body;
  }
}
