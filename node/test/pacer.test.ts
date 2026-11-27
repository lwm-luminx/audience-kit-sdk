import { describe, expect, it } from "vitest";
import { AudienceKitClient, AudienceKitError, RequestPacer } from "../src/index.js";
import type { HttpRequest, HttpResponse, HttpTransport } from "../src/transport.js";

describe("RequestPacer", () => {
  let now = 1_800_000_000_000;
  const pacer = (options: { burst?: number; perSecond?: number; maximumBackoffMillis?: number } = {}) =>
    new RequestPacer({ ...options, now: () => now, jitter: () => 0 });

  it("sends a burst, then makes the rest wait their turn", () => {
    const p = pacer({ burst: 3, perSecond: 2 });
    expect([p.admit(), p.admit(), p.admit()]).toEqual([{ kind: "send" }, { kind: "send" }, { kind: "send" }]);
    expect(p.admit()).toEqual({ kind: "wait", millis: 500 });
    now += 500;
    expect(p.admit()).toEqual({ kind: "send" });
  });

  it("holds every request for Retry-After on a 429", () => {
    const p = pacer();
    p.observe(429, "30");
    now += 10_000;
    expect(p.admit()).toEqual({ kind: "paused", retryAfterMillis: 20_000 });
    now += 20_000;
    expect(p.admit()).toEqual({ kind: "send" });
    expect(p.pausedUntil()).toBeNull();
  });

  it("backs off exponentially without Retry-After, up to the maximum", () => {
    const p = pacer({ maximumBackoffMillis: 10_000 });
    const waits = Array.from({ length: 6 }, () => {
      p.observe(429, null);
      return (p.pausedUntil() ?? now) - now;
    });
    expect(waits).toEqual([1_000, 2_000, 4_000, 8_000, 10_000, 10_000]);
  });

  it("waits on a 503 only when it says how long", () => {
    const p = pacer();
    p.observe(503, null);
    expect(p.pausedUntil()).toBeNull();
    p.observe(503, "5");
    expect((p.pausedUntil() ?? 0) - now).toBe(5_000);
  });

  it("reads Retry-After as seconds or an HTTP date", () => {
    const second = 1_800_000_000_000;
    expect(RequestPacer.retryAfterMillis(new Date(second + 45_000).toUTCString(), second)).toBe(45_000);
    expect(RequestPacer.retryAfterMillis("12", now)).toBe(12_000);
    expect(RequestPacer.retryAfterMillis("soon", now)).toBeNull();
  });

  it("stops a client calling the API after a 429 until Retry-After", async () => {
    let calls = 0;
    const transport: HttpTransport = {
      async execute(_request: HttpRequest): Promise<HttpResponse> {
        calls += 1;
        return { status: 429, body: '{"error":"RATE_LIMITED"}', headers: { "retry-after": "60" } };
      },
    };
    const client = new AudienceKitClient({ configuration: { baseUrl: "https://api.test", host: "x.test" }, transport });
    for (let i = 0; i < 5; i += 1) {
      await expect(client.data({ path: "/v1/status", authenticated: false })).rejects.toBeInstanceOf(AudienceKitError);
    }
    expect(calls).toBe(1);
    expect(client.pacer.pausedUntil()).not.toBeNull();
  });
});
