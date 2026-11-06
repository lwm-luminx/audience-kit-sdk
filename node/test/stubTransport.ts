import type { HttpRequest, HttpResponse, HttpTransport } from "../src/index.js";

/** A recorded request, with helpers for assertions. */
export class RecordedRequest {
  readonly method: string;
  readonly url: URL;
  readonly headers: Record<string, string>;
  readonly body: string | null;

  constructor(request: HttpRequest) {
    this.method = request.method;
    this.url = new URL(request.url);
    this.headers = request.headers;
    this.body = request.body;
  }

  get path(): string {
    return this.url.pathname;
  }

  header(name: string): string | undefined {
    const key = Object.keys(this.headers).find((k) => k.toLowerCase() === name.toLowerCase());
    return key === undefined ? undefined : this.headers[key];
  }

  json(): Record<string, unknown> {
    return JSON.parse(this.body ?? "null") as Record<string, unknown>;
  }

  /** The GraphQL document a request carries. */
  get query(): string {
    return String(this.json().query);
  }

  get variables(): Record<string, unknown> {
    return (this.json().variables as Record<string, unknown>) ?? {};
  }
}

export type Reply = { status: number; body: string } | { error: Error };

export const json = (status: number, body: unknown): Reply => ({ status, body: typeof body === "string" ? body : JSON.stringify(body) });
export const data = (data: unknown): Reply => json(200, { data });
export const failure = (error: Error): Reply => ({ error });

/** Answers every request with `respond` and records what was sent, so tests run offline. */
export class StubTransport implements HttpTransport {
  readonly requests: RecordedRequest[] = [];

  constructor(private readonly respond: (request: RecordedRequest) => Reply) {}

  async execute(request: HttpRequest): Promise<HttpResponse> {
    const recorded = new RecordedRequest(request);
    this.requests.push(recorded);
    const reply = this.respond(recorded);
    if ("error" in reply) throw reply.error;
    return { status: reply.status, body: reply.body };
  }

  get last(): RecordedRequest {
    return this.requests[this.requests.length - 1]!;
  }
}

export const BASE_URL = "https://api.audiencekit.test";
export const AUDIENCE_ID = "b0f8b66a-e636-495d-9475-0f5317ea08e0";
