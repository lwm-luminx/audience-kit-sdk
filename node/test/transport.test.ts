import { describe, expect, it, vi } from "vitest";
import { AudienceKitError, FetchTransport, InMemoryTokenStore } from "../src/index.js";

describe("the fetch transport", () => {
  const request = { method: "POST", url: "https://api.audiencekit.test/v1/x", headers: { Accept: "application/json" }, body: "{}" };

  it("sends the request through fetch and reads the text", async () => {
    const fetchImpl = vi.fn(async (_url: string, init: RequestInit) => new Response("ok", { status: 201 }));
    const transport = new FetchTransport({ fetch: fetchImpl });
    expect(await transport.execute(request)).toEqual({ status: 201, body: "ok" });
    const [url, init] = fetchImpl.mock.calls[0]!;
    expect(url).toBe(request.url);
    expect(init).toMatchObject({ method: "POST", headers: request.headers, body: "{}", redirect: "follow" });
    expect(init.signal).toBeInstanceOf(AbortSignal);
  });

  it("uses the global fetch by default", () => {
    expect(() => new FetchTransport()).not.toThrow();
  });

  it("refuses to start without any fetch", () => {
    const original = globalThis.fetch;
    // @ts-expect-error simulating a runtime without fetch
    globalThis.fetch = undefined;
    try {
      expect(() => new FetchTransport()).toThrow(AudienceKitError);
    } finally {
      globalThis.fetch = original;
    }
  });

  it("times out", async () => {
    const fetchImpl = (_url: string, init: RequestInit) =>
      new Promise<Response>((_resolve, reject) => {
        init.signal?.addEventListener("abort", () => reject(init.signal?.reason));
      });
    const transport = new FetchTransport({ fetch: fetchImpl, timeoutMillis: 5 });
    await expect(transport.execute(request)).rejects.toThrow("timed out");
  });

  it("aborts when the caller's signal does", async () => {
    const controller = new AbortController();
    const fetchImpl = (_url: string, init: RequestInit) =>
      new Promise<Response>((_resolve, reject) => {
        init.signal?.addEventListener("abort", () => reject(init.signal?.reason));
      });
    const transport = new FetchTransport({ fetch: fetchImpl });
    const pending = transport.execute({ ...request, signal: controller.signal });
    controller.abort(new Error("cancelled"));
    await expect(pending).rejects.toThrow("cancelled");
  });
});

describe("the in-memory token store", () => {
  it("keeps the token and audience together", () => {
    const store = new InMemoryTokenStore();
    expect(store.loadToken()).toBeNull();
    store.saveToken("t");
    store.saveAudienceId("a");
    expect(store.loadToken()).toBe("t");
    expect(store.loadAudienceId()).toBe("a");
    store.deleteToken();
    expect(store.loadToken()).toBeNull();
    expect(store.loadAudienceId()).toBeNull();
  });
});
