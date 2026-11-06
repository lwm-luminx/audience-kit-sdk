/**
 * Somewhere to keep the session between calls and launches: the token, and the audience it was signed in on. Session
 * tokens don't expire (they are revoked), so treat them like passwords and never log them. The default keeps them in
 * memory; a server keeps them wherever it keeps secrets, a CLI in the OS keychain.
 */
export interface TokenStore {
  loadToken(): string | null | Promise<string | null>;
  saveToken(token: string): void | Promise<void>;
  deleteToken(): void | Promise<void>;
  /**
   * The audience the stored session was signed in on (`audienceId` in the sign-in JSON), kept beside the token so the
   * client needn't decode the JWT. Not a secret. A store that keeps nothing here makes the client look the audience
   * up from the configured host.
   */
  loadAudienceId?(): string | null | Promise<string | null>;
  saveAudienceId?(audienceId: string | null): void | Promise<void>;
}

/** Keeps the session in memory only: the default, and what tests use. */
export class InMemoryTokenStore implements TokenStore {
  private token: string | null;
  private audienceId: string | null;

  constructor(token: string | null = null, audienceId: string | null = null) {
    this.token = token;
    this.audienceId = audienceId;
  }

  loadToken(): string | null {
    return this.token;
  }

  saveToken(token: string): void {
    this.token = token;
  }

  deleteToken(): void {
    this.token = null;
    this.audienceId = null;
  }

  loadAudienceId(): string | null {
    return this.audienceId;
  }

  saveAudienceId(audienceId: string | null): void {
    this.audienceId = audienceId;
  }
}
