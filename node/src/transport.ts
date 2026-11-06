import { AudienceKitError } from "./errors.js";

/** An HTTP request as the client hands it to an `HttpTransport`. */
export interface HttpRequest {
  method: string;
  url: string;
  headers: Record<string, string>;
  /** A JSON body, or null. */
  body: string | null;
  /** Cancels the request. */
  signal?: AbortSignal;
}

/** What an `HttpTransport` got back. */
export interface HttpResponse {
  status: number;
  body: string;
}

/**
 * Sends the client's HTTP requests. The default, `FetchTransport`, uses the global `fetch` (Node 18+, every browser);
 * implement this to route the SDK through an app's own HTTP client, or to stub it in tests.
 *
 * Reject when there's no response (the client reports it as a `NETWORK` error); any status code is a response.
 */
export interface HttpTransport {
  execute(request: HttpRequest): Promise<HttpResponse>;
}

/** The `fetch` signature the transport needs, so an app can pass its own (undici's, a polyfill's, a stub's). */
export type FetchLike = (url: string, init: RequestInit) => Promise<Response>;

/** An `HttpTransport` over `fetch`, with a timeout (30 seconds by default). */
export class FetchTransport implements HttpTransport {
  private readonly fetchImpl: FetchLike;
  private readonly timeoutMillis: number;

  constructor(options: { fetch?: FetchLike; timeoutMillis?: number } = {}) {
    const impl = options.fetch ?? (globalThis.fetch as FetchLike | undefined);
    if (!impl) throw AudienceKitError.missingConfiguration("this runtime has no fetch; pass one to FetchTransport");
    this.fetchImpl = impl;
    this.timeoutMillis = options.timeoutMillis ?? 30_000;
  }

  async execute(request: HttpRequest): Promise<HttpResponse> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(new Error(`The request timed out after ${this.timeoutMillis}ms.`)), this.timeoutMillis);
    const onAbort = () => controller.abort(request.signal?.reason);
    request.signal?.addEventListener("abort", onAbort, { once: true });
    try {
      const response = await this.fetchImpl(request.url, {
        method: request.method,
        headers: request.headers,
        body: request.body,
        signal: controller.signal,
        redirect: "follow",
      });
      return { status: response.status, body: await response.text() };
    } finally {
      clearTimeout(timer);
      request.signal?.removeEventListener("abort", onAbort);
    }
  }
}
