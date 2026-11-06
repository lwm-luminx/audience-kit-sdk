import { createHmac } from "node:crypto";

/**
 * The QR code on a cover pass. The app makes it from the pass's `passSecret` every `COVER_PASS_WINDOW_SECONDS`, so it
 * works with no signal and a screenshot stops scanning within a minute:
 *
 *     HMC1.<admission id>.<window>.<signature>
 *
 * where window is the Unix time divided by the window length and signature is the first 16 characters of the unpadded
 * URL-safe Base64 HMAC-SHA256 of `<admission id>.<window>`, keyed with the Base64-decoded secret. The door accepts a
 * couple of windows either side, for clock drift between the phones.
 */
export const COVER_PASS_PREFIX = "HMC1";
export const COVER_PASS_WINDOW_SECONDS = 30;

/** The window `epochSeconds` falls in. */
export function coverPassWindow(epochSeconds: number): number {
  return Math.floor(epochSeconds / COVER_PASS_WINDOW_SECONDS);
}

/** Seconds from `epochSeconds` until the code changes. */
export function secondsUntilNextCoverPassWindow(epochSeconds: number): number {
  const into = ((epochSeconds % COVER_PASS_WINDOW_SECONDS) + COVER_PASS_WINDOW_SECONDS) % COVER_PASS_WINDOW_SECONDS;
  return COVER_PASS_WINDOW_SECONDS - into;
}

export function coverPassSignature(admissionId: string, passSecret: string, window: number): string {
  const key = Buffer.from(passSecret, "base64");
  return createHmac("sha256", key).update(`${admissionId}.${window}`, "utf8").digest("base64url").slice(0, 16);
}

/** The pass's code at `epochSeconds` (now by default). */
export function coverPassCode(admissionId: string, passSecret: string, epochSeconds: number = Math.floor(Date.now() / 1000)): string {
  const window = coverPassWindow(epochSeconds);
  return [COVER_PASS_PREFIX, admissionId, String(window), coverPassSignature(admissionId, passSecret, window)].join(".");
}

/** Whether `code` looks like a cover pass, before asking the API. */
export function isCoverPassCode(code: string): boolean {
  const parts = code.trim().split(".");
  return (
    parts.length === 4 &&
    parts[0] === COVER_PASS_PREFIX &&
    parts[1]!.length > 0 &&
    /^[0-9]+$/.test(parts[2]!) &&
    parts[3]!.length > 0
  );
}
