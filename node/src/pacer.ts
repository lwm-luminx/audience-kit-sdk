import { AudienceKitError } from "./errors.js";

/** What to do with a request now: send it, wait first, or fail it because the API asked this client to wait. */
export type PacerAdmission = { kind: "send" } | { kind: "wait"; millis: number } | { kind: "paused"; retryAfterMillis: number };

export interface RequestPacerOptions {
  /** The most requests that may go out at once (20). */
  burst?: number;
  /** How many requests a second the bucket refills by (8). */
  perSecond?: number;
  /** The longest a backoff lasts, whatever `Retry-After` says (120,000 ms). */
  maximumBackoffMillis?: number;
  /** Milliseconds since the epoch (tests). */
  now?: () => number;
  /** Extra wait as a fraction of the backoff, 0 to 0.25 at random by default (tests pass 0). */
  jitter?: () => number;
}

/**
 * Keeps one client from flooding the API (a request storm), whatever the app's timers and retries do.
 *
 * - Pacing: a token bucket, up to `burst` requests at once refilling at `perSecond`; a request beyond that waits.
 * - Backing off: when the API answers 429 (rate limited), or 503 (unavailable) with a `Retry-After`, every request is held back until the
 *   answer's `Retry-After` has passed, or without one for 1, 2, 4… seconds up to `maximumBackoffMillis` after each one
 *   in a row (with jitter). A held-back request fails at once with an `HTTP` 429 error and never reaches the network.
 *   The first answer that doesn't ask for one ends the backoff.
 *
 * `AudienceKitClient` keeps one and sends every HTTP request through it.
 */
export class RequestPacer {
  readonly burst: number;
  readonly perSecond: number;
  readonly maximumBackoffMillis: number;
  private readonly now: () => number;
  private readonly jitter: () => number;
  private tokens: number;
  private refilledAt: number | null = null;
  private pausedUntilMillis: number | null = null;
  private strikes = 0;

  constructor(options: RequestPacerOptions = {}) {
    this.burst = Math.max(1, options.burst ?? 20);
    this.perSecond = Math.max(0.1, options.perSecond ?? 8);
    this.maximumBackoffMillis = options.maximumBackoffMillis ?? 120_000;
    this.now = options.now ?? Date.now;
    this.jitter = options.jitter ?? (() => Math.random() * 0.25);
    this.tokens = this.burst;
  }

  /** Whether a request may go out now. `send` takes a token; `wait` means ask again after that long. */
  admit(): PacerAdmission {
    const now = this.now();
    if (this.pausedUntilMillis !== null && this.pausedUntilMillis > now) {
      return { kind: "paused", retryAfterMillis: this.pausedUntilMillis - now };
    }
    this.pausedUntilMillis = null;
    if (this.refilledAt !== null) {
      this.tokens = Math.min(this.burst, this.tokens + (Math.max(0, now - this.refilledAt) / 1000) * this.perSecond);
    }
    this.refilledAt = now;
    if (this.tokens >= 1) {
      this.tokens -= 1;
      return { kind: "send" };
    }
    return { kind: "wait", millis: Math.max(1, Math.ceil(((1 - this.tokens) / this.perSecond) * 1000)) };
  }

  /** Waits for a turn, or throws while the API has asked this client to wait. */
  async acquire(): Promise<void> {
    for (;;) {
      const admission = this.admit();
      if (admission.kind === "send") return;
      if (admission.kind === "paused") {
        throw new AudienceKitError("HTTP", `The server asked this app to slow down. Trying again in ${Math.ceil(admission.retryAfterMillis / 1000)}s.`, { status: 429 });
      }
      await new Promise((resolve) => setTimeout(resolve, admission.millis));
    }
  }

  /** Learns from a response: 429, or 503 with a `Retry-After`, starts (or lengthens) a backoff; anything else ends it. */
  observe(status: number, retryAfter: string | null | undefined): void {
    if (status !== 429 && !(status === 503 && RequestPacer.retryAfterMillis(retryAfter, this.now()) !== null)) {
      this.strikes = 0;
      return;
    }
    this.strikes += 1;
    const now = this.now();
    const fallback = 2 ** Math.min(this.strikes - 1, 6) * 1000;
    const wait = Math.min(RequestPacer.retryAfterMillis(retryAfter, now) ?? fallback, this.maximumBackoffMillis);
    const until = now + Math.round(wait * (1 + this.jitter()));
    this.pausedUntilMillis = Math.max(this.pausedUntilMillis ?? until, until);
  }

  /** When the API has asked this client to wait until (epoch milliseconds), if it still has. */
  pausedUntil(): number | null {
    return this.pausedUntilMillis !== null && this.pausedUntilMillis > this.now() ? this.pausedUntilMillis : null;
  }

  /** A `Retry-After` value in milliseconds: delta-seconds, or an HTTP date. */
  static retryAfterMillis(value: string | null | undefined, now: number): number | null {
    const text = value?.trim();
    if (!text) return null;
    if (/^\d+(\.\d+)?$/.test(text)) return Math.max(0, Number(text) * 1000);
    const date = Date.parse(text);
    return Number.isNaN(date) ? null : Math.max(0, date - now);
  }
}
