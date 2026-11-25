// GraphQL subscriptions over the API's Action Cable (GraphQLChannel), for a runtime with a browser WebSocket: the
// TypeScript side of CableConnection/GraphQLCable in the Kotlin SDK. One socket carries every operation, each on its
// own channel subscription; it reconnects with backoff and runs every live operation again once welcomed.

/** The browser WebSocket's shape, as far as the cable uses it (a seam for tests). */
export interface CableSocket {
  readonly readyState: number;
  onopen: ((event: unknown) => void) | null;
  onmessage: ((event: { data: unknown }) => void) | null;
  onclose: ((event: unknown) => void) | null;
  onerror: ((event: unknown) => void) | null;
  send(data: string): void;
  close(): void;
}

export type CableSocketFactory = (url: string, protocols: string[]) => CableSocket;

/** One result of an operation: `event` is the subscription field's value. */
export interface CableResult {
  data: Record<string, unknown> | null;
  errors: unknown[];
  more: boolean;
  event: Record<string, unknown> | null;
}

export interface CableHandlers {
  onResult(result: CableResult): void;
  /** The channel was refused (another audience, signed out): the operation is over. */
  onRejected?(): void;
}

interface Operation {
  identifier: string;
  execute: string;
  handlers: CableHandlers;
}

/** Action Cable pings every 3 seconds; this long without a frame means the socket is gone. */
export const CABLE_SILENCE_MS = 12_000;

/** `wss://<host>/connection` for an API base URL (`ws://` for a local http one). */
export function realtimeUrl(baseUrl: string): string {
  const url = new URL(baseUrl);
  const scheme = url.protocol === "http:" ? "ws:" : "wss:";
  return `${scheme}//${url.host}${url.pathname.replace(/\/+$/, "")}/connection`;
}

export class GraphQLCable {
  private socket: CableSocket | null = null;
  private welcomed = false;
  private readonly operations = new Map<string, Operation>();
  private retry = 0;
  private reopenTimer: ReturnType<typeof setTimeout> | null = null;
  private silenceTimer: ReturnType<typeof setTimeout> | null = null;
  private closed = false;

  constructor(
    private readonly url: string,
    private readonly token: () => string | null,
    private readonly audienceId: string,
    private readonly open: CableSocketFactory,
    private readonly endpoint: string = "staffql",
  ) {}

  /** Runs `query` while subscribed; returns what stops it. */
  subscribe(query: string, variables: Record<string, unknown>, handlers: CableHandlers): () => void {
    const channelId = Math.random().toString(36).slice(2) + Date.now().toString(36);
    const identifier = JSON.stringify({
      channel: "GraphQLChannel",
      audience_id: this.audienceId,
      channelId,
      ...(this.endpoint === "graphql" ? {} : { endpoint: this.endpoint }),
    });
    const execute = JSON.stringify({
      command: "message",
      identifier,
      data: JSON.stringify({ action: "execute", query, variables }),
    });
    const operation: Operation = { identifier, execute, handlers };
    this.operations.set(identifier, operation);
    this.closed = false;
    if (this.socket && this.welcomed) this.send({ command: "subscribe", identifier });
    else this.connect();
    return () => {
      if (this.operations.get(identifier) !== operation) return;
      this.operations.delete(identifier);
      if (this.welcomed) this.send({ command: "unsubscribe", identifier });
      if (this.operations.size === 0) this.close();
    };
  }

  /** Closes the socket and forgets every operation. */
  close(): void {
    this.closed = true;
    this.operations.clear();
    this.clearTimers();
    const socket = this.socket;
    this.socket = null;
    this.welcomed = false;
    if (socket) {
      socket.onclose = null;
      socket.close();
    }
  }

  private connect(): void {
    if (this.socket || this.closed) return;
    const token = this.token();
    if (!token) return;
    const socket = this.open(this.url, ["actioncable-v1-json", `jwt.${token}`]);
    this.socket = socket;
    this.welcomed = false;
    socket.onmessage = (event) => this.receive(String(event.data));
    socket.onclose = () => this.dropped();
    socket.onerror = () => socket.close();
    this.heard();
  }

  private receive(text: string): void {
    this.heard();
    let frame: Record<string, unknown>;
    try {
      frame = JSON.parse(text) as Record<string, unknown>;
    } catch {
      return;
    }
    const identifier = typeof frame.identifier === "string" ? frame.identifier : null;
    const operation = identifier ? this.operations.get(identifier) : undefined;
    switch (frame.type) {
      case "welcome":
        this.welcomed = true;
        this.retry = 0;
        this.operations.forEach((op) => this.send({ command: "subscribe", identifier: op.identifier }));
        return;
      case "confirm_subscription":
        if (operation) this.socket?.send(operation.execute);
        return;
      case "reject_subscription":
        if (operation && identifier) {
          this.operations.delete(identifier);
          operation.handlers.onRejected?.();
        }
        return;
      case "disconnect":
        this.socket?.close();
        return;
      case undefined: {
        // Action Cable reuses `message` for its ping counter, so only an object there is a result.
        const message = frame.message;
        if (!operation || !message || typeof message !== "object") return;
        const body = message as { result?: { data?: Record<string, unknown>; errors?: unknown[] }; more?: boolean };
        const data = body.result?.data ?? null;
        const first = data ? Object.values(data)[0] : null;
        operation.handlers.onResult({
          data,
          errors: body.result?.errors ?? [],
          more: body.more ?? true,
          event: first && typeof first === "object" && !Array.isArray(first) ? (first as Record<string, unknown>) : null,
        });
        return;
      }
      default:
        return;
    }
  }

  private send(frame: Record<string, unknown>): void {
    this.socket?.send(JSON.stringify(frame));
  }

  /** A frame arrived: the socket is alive for another while. */
  private heard(): void {
    if (this.silenceTimer) clearTimeout(this.silenceTimer);
    this.silenceTimer = setTimeout(() => this.socket?.close(), CABLE_SILENCE_MS);
  }

  private dropped(): void {
    this.socket = null;
    this.welcomed = false;
    if (this.silenceTimer) clearTimeout(this.silenceTimer);
    if (this.closed || this.operations.size === 0) return;
    const delay = Math.min(30_000, 1_000 * 2 ** this.retry);
    this.retry += 1;
    this.reopenTimer = setTimeout(() => {
      this.reopenTimer = null;
      this.connect();
    }, delay);
  }

  private clearTimers(): void {
    if (this.reopenTimer) clearTimeout(this.reopenTimer);
    if (this.silenceTimer) clearTimeout(this.silenceTimer);
    this.reopenTimer = null;
    this.silenceTimer = null;
  }
}
