import { AudienceKitSDK } from "./version.js";

/**
 * Which build of the app is calling. Staging builds talk to the production API but sign people in with the audience's
 * staging Facebook app; the client says so with the `X-AudienceKit-Environment: staging` header. Development builds
 * run against a local API, which uses its own Facebook app, so they stay `production`.
 */
export type AudienceKitEnvironment = "production" | "staging";

/** The header that carries the environment. Production builds leave it out. */
export const ENVIRONMENT_HEADER = "X-AudienceKit-Environment";

/** Where the SDK talks to and which audience it speaks for. */
export interface AudienceKitConfiguration {
  /** The API's base URL, `https://api.audiencekit.com` by default, or `http://localhost:3000` for a local server. */
  baseUrl?: string;
  /**
   * A host that names the audience, e.g. `hotmess.social` once that domain is verified, or
   * `hotmess.admin.audiencekit.com`, which works as soon as the audience exists.
   *
   * Sent with sign-in, so the session is bound to the audience and the token is checked against the audience's own
   * apps, and used to look up branding. Without a host the API only accepts tokens from the AudienceKit platform app.
   */
  host?: string;
  /**
   * The audience's ID (a UUID). When unset the client works it out from the session the sign-in named, or from
   * `branding()` for `host`.
   */
  audienceId?: string;
  /** The Facebook app the build signs people in with: one of the audience's own apps, or the platform app. */
  facebookAppId?: string;
  /** The build's environment. `staging` makes the API sign people in with the audience's staging Facebook app. */
  environment?: AudienceKitEnvironment;
}

/** The device a session is created on. The API records it alongside the session. */
export interface DeviceDescription {
  /** A stable identifier for this install or server. */
  identifier: string;
  /** `node` for this SDK; `ios`, `android` or `web` for an app relaying through a server. */
  type?: string;
  /** The hardware model or host, e.g. `MacBookPro18,3`. */
  model?: string;
  /** The app's version. */
  version?: string;
  /** The app's build number. */
  build?: string;
}

/** `configuration` with every default filled in. */
export interface ResolvedConfiguration {
  baseUrl: string;
  host: string | null;
  audienceId: string | null;
  facebookAppId: string | null;
  environment: AudienceKitEnvironment;
}

export function resolveConfiguration(configuration: AudienceKitConfiguration = {}): ResolvedConfiguration {
  return {
    baseUrl: (configuration.baseUrl ?? AudienceKitSDK.PRODUCTION_BASE_URL).replace(/\/+$/, ""),
    host: configuration.host ?? null,
    audienceId: configuration.audienceId ?? null,
    facebookAppId: configuration.facebookAppId ?? null,
    environment: configuration.environment ?? "production",
  };
}
