/**
 * Entry point constants for the AudienceKit Node SDK. The package keeps its own version (package.json), separate from
 * the Swift and Kotlin SDKs' `VERSION`; `scripts/node-version.sh` checks that this constant matches package.json.
 */
export const AudienceKitSDK = {
  /** The SDK's semantic version. */
  VERSION: "0.1.0",
  /**
   * The API contract this SDK speaks, the date it was last broken, sent on every call as `X-AudienceKit-API-Version`.
   * The API refuses a version it doesn't serve with 400 `unsupported_api_version`.
   */
  API_VERSION: "2026-10-11",
  /** The hosted AudienceKit API. */
  PRODUCTION_BASE_URL: "https://api.audiencekit.com",
} as const;
