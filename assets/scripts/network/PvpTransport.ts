export type TransportKind = "polling" | "websocket";

export interface PvpSession {
  readonly sessionId: string;
  readonly accessToken: string;
  readonly eventsUrl: string;
  readonly commandsUrl: string;
  readonly websocketUrl?: string;
  /** Server-issued, single-use upgrade ticket; never put the bearer token in a URL. */
  readonly websocketTicket?: string;
  readonly initialCursor?: number;
}

export interface TransportMessage {
  readonly cursor: number;
  readonly payload: unknown;
}

export type TransportListener = (message: Readonly<TransportMessage>) => void;

export interface PvpTransport {
  readonly kind: TransportKind;
  readonly connected: boolean;
  connect(session: Readonly<PvpSession>): Promise<void>;
  send(commandEnvelope: Readonly<Record<string, unknown>>): Promise<void>;
  subscribe(listener: TransportListener): () => void;
  close(): void;
}

export interface PollingDependencies {
  readonly fetch: typeof globalThis.fetch;
  readonly setInterval: typeof globalThis.setInterval;
  readonly clearInterval: typeof globalThis.clearInterval;
  readonly intervalMs: number;
}

export class PollingPvpTransport implements PvpTransport {
  readonly kind = "polling" as const;
  readonly #listeners = new Set<TransportListener>();
  readonly #deps: PollingDependencies;
  #session: Readonly<PvpSession> | null = null;
  #timer: ReturnType<typeof setInterval> | null = null;
  #cursor = 0;
  #polling = false;

  constructor(dependencies?: Partial<PollingDependencies>) {
    this.#deps = {
      fetch: dependencies?.fetch ?? globalThis.fetch.bind(globalThis),
      setInterval: dependencies?.setInterval ?? globalThis.setInterval.bind(globalThis),
      clearInterval: dependencies?.clearInterval ?? globalThis.clearInterval.bind(globalThis),
      intervalMs: dependencies?.intervalMs ?? 350,
    };
  }

  get connected(): boolean {
    return this.#session !== null;
  }

  async connect(session: Readonly<PvpSession>): Promise<void> {
    this.close();
    this.#session = Object.freeze({ ...session });
    this.#cursor = session.initialCursor ?? 0;
    try {
      await this.pollOnce();
      this.#timer = this.#deps.setInterval(() => void this.pollOnce(), this.#deps.intervalMs);
    } catch (error) {
      this.close();
      throw error;
    }
  }

  async send(commandEnvelope: Readonly<Record<string, unknown>>): Promise<void> {
    const session = this.#requireSession();
    const response = await this.#deps.fetch(session.commandsUrl, {
      method: "POST",
      headers: this.#headers(session),
      body: JSON.stringify(commandEnvelope),
    });
    if (!response.ok) {
      throw new Error(`pvp-command-http-${response.status}`);
    }
  }

  subscribe(listener: TransportListener): () => void {
    this.#listeners.add(listener);
    return () => this.#listeners.delete(listener);
  }

  close(): void {
    if (this.#timer !== null) {
      this.#deps.clearInterval(this.#timer);
    }
    this.#timer = null;
    this.#session = null;
    this.#polling = false;
  }

  async pollOnce(): Promise<void> {
    if (!this.#session || this.#polling) {
      return;
    }
    this.#polling = true;
    try {
      const separator = this.#session.eventsUrl.includes("?") ? "&" : "?";
      const response = await this.#deps.fetch(
        `${this.#session.eventsUrl}${separator}cursor=${this.#cursor}`,
        { headers: this.#headers(this.#session) },
      );
      if (!response.ok) {
        throw new Error(`pvp-events-http-${response.status}`);
      }
      const body = (await response.json()) as {
        readonly cursor?: number;
        readonly events?: readonly unknown[];
      };
      let next = this.#cursor;
      for (const payload of body.events ?? []) {
        const payloadCursor = readPayloadCursor(payload) ?? next + 1;
        if (payloadCursor <= next) {
          continue;
        }
        next = payloadCursor;
        this.#emit({ cursor: payloadCursor, payload });
      }
      this.#cursor = Math.max(next, body.cursor ?? next);
    } finally {
      this.#polling = false;
    }
  }

  #emit(message: TransportMessage): void {
    for (const listener of this.#listeners) {
      listener(Object.freeze(message));
    }
  }

  #headers(session: Readonly<PvpSession>): HeadersInit {
    return {
      authorization: `Bearer ${session.accessToken}`,
      "content-type": "application/json",
      "x-pvp-session": session.sessionId,
    };
  }

  #requireSession(): Readonly<PvpSession> {
    if (!this.#session) {
      throw new Error("pvp-transport-not-connected");
    }
    return this.#session;
  }
}

function readPayloadCursor(payload: unknown): number | null {
  if (!payload || typeof payload !== "object") {
    return null;
  }
  const cursor = (payload as { readonly cursor?: unknown }).cursor;
  return typeof cursor === "number" && Number.isSafeInteger(cursor) && cursor >= 0
    ? cursor
    : null;
}

export interface WebSocketLike {
  readonly readyState: number;
  onopen: (() => void) | null;
  onmessage: ((event: { readonly data: string }) => void) | null;
  onerror: (() => void) | null;
  onclose: (() => void) | null;
  send(data: string): void;
  close(): void;
}

export type WebSocketFactory = (url: string) => WebSocketLike;

function createBrowserWebSocket(url: string): WebSocketLike {
  const socket = new WebSocket(url);
  const bridge: WebSocketLike = {
    get readyState() {
      return socket.readyState;
    },
    onopen: null,
    onmessage: null,
    onerror: null,
    onclose: null,
    send(data) {
      socket.send(data);
    },
    close() {
      socket.close();
    },
  };
  socket.onopen = () => bridge.onopen?.();
  socket.onerror = () => bridge.onerror?.();
  socket.onclose = () => bridge.onclose?.();
  socket.onmessage = (event) => {
    if (typeof event.data === "string") {
      bridge.onmessage?.({ data: event.data });
    } else {
      bridge.onerror?.();
    }
  };
  return bridge;
}

export class WebSocketPvpTransport implements PvpTransport {
  readonly kind = "websocket" as const;
  readonly #listeners = new Set<TransportListener>();
  readonly #factory: WebSocketFactory;
  #socket: WebSocketLike | null = null;
  #session: Readonly<PvpSession> | null = null;
  #cursor = 0;

  constructor(factory?: WebSocketFactory) {
    this.#factory = factory ?? createBrowserWebSocket;
  }

  get connected(): boolean {
    return this.#socket?.readyState === 1;
  }

  connect(session: Readonly<PvpSession>): Promise<void> {
    this.close();
    if (!session.websocketUrl || !session.websocketTicket) {
      return Promise.reject(new Error("pvp-websocket-upgrade-ticket-missing"));
    }
    this.#session = Object.freeze({ ...session });
    this.#cursor = session.initialCursor ?? 0;
    const query = new URLSearchParams({
      sessionId: session.sessionId,
      ticket: session.websocketTicket,
      cursor: String(this.#cursor),
    });
    const separator = session.websocketUrl.includes("?") ? "&" : "?";
    const socket = this.#factory(`${session.websocketUrl}${separator}${query}`);
    this.#socket = socket;
    return new Promise((resolve, reject) => {
      socket.onopen = resolve;
      socket.onerror = () => reject(new Error("pvp-websocket-connect-failed"));
      socket.onclose = () => {
        if (this.#socket === socket) {
          this.#socket = null;
        }
      };
      socket.onmessage = (event) => {
        const parsed = JSON.parse(event.data) as TransportMessage;
        if (Number.isInteger(parsed.cursor) && parsed.cursor > this.#cursor) {
          this.#cursor = parsed.cursor;
          this.#emit(parsed);
        }
      };
    });
  }

  async send(commandEnvelope: Readonly<Record<string, unknown>>): Promise<void> {
    if (!this.connected || !this.#socket || !this.#session) {
      throw new Error("pvp-transport-not-connected");
    }
    this.#socket.send(JSON.stringify({
      type: "command",
      sessionId: this.#session.sessionId,
      commandEnvelope,
    }));
  }

  subscribe(listener: TransportListener): () => void {
    this.#listeners.add(listener);
    return () => this.#listeners.delete(listener);
  }

  close(): void {
    this.#socket?.close();
    this.#socket = null;
    this.#session = null;
  }

  #emit(message: Readonly<TransportMessage>): void {
    const frozen = Object.freeze({ ...message });
    for (const listener of this.#listeners) {
      listener(frozen);
    }
  }
}

export function createPvpTransport(
  kind: TransportKind,
  options?: {
    readonly polling?: Partial<PollingDependencies>;
    readonly websocketFactory?: WebSocketFactory;
  },
): PvpTransport {
  return kind === "websocket"
    ? new WebSocketPvpTransport(options?.websocketFactory)
    : new PollingPvpTransport(options?.polling);
}
