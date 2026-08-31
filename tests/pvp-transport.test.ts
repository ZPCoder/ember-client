import assert from "node:assert/strict";
import test from "node:test";

import {
  PollingPvpTransport,
  WebSocketPvpTransport,
  createPvpTransport,
  type WebSocketLike,
} from "../assets/scripts/network/PvpTransport.ts";

test("transport factory keeps polling and WebSocket behind one interface", () => {
  assert.equal(createPvpTransport("polling").kind, "polling");
  assert.equal(createPvpTransport("websocket", { websocketFactory: () => fakeSocket() }).kind, "websocket");
});

test("polling transport resumes from cursor and sends a bearer-authorized command", async () => {
  const calls: Array<{ url: string; init?: RequestInit }> = [];
  const fakeFetch = async (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
    const url = String(input);
    calls.push({ url, init });
    if (init?.method === "POST") {
      return new Response("{}", { status: 200 });
    }
    return new Response(JSON.stringify({ cursor: 9, events: [{ type: "snapshot" }] }), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  };
  let scheduled: (() => void) | null = null;
  const transport = new PollingPvpTransport({
    fetch: fakeFetch,
    setInterval: ((callback: () => void) => {
      scheduled = callback;
      return 7;
    }) as typeof setInterval,
    clearInterval: (() => undefined) as typeof clearInterval,
    intervalMs: 350,
  });
  const received: unknown[] = [];
  transport.subscribe((message) => received.push(message.payload));
  await transport.connect({
    sessionId: "session-1",
    accessToken: "short-token",
    eventsUrl: "https://game.invalid/v1/pvp/events",
    commandsUrl: "https://game.invalid/v1/pvp/commands",
    initialCursor: 8,
  });
  await transport.send({ command: { type: "end-turn" } });

  assert.equal(typeof scheduled, "function");
  assert.equal(calls[0]?.url.endsWith("cursor=8"), true);
  assert.equal(calls[0]?.url.includes("short-token"), false);
  assert.deepEqual(received, [{ type: "snapshot" }]);
  assert.equal(new Headers(calls[1]?.init?.headers).get("authorization"), "Bearer short-token");
  transport.close();
});

test("WebSocket uses a single-use upgrade ticket and de-duplicates cursors", async () => {
  const socket = fakeSocket();
  let openedUrl = "";
  const transport = new WebSocketPvpTransport((url) => {
    openedUrl = url;
    return socket;
  });
  const received: number[] = [];
  transport.subscribe((message) => received.push(message.cursor));
  const connected = transport.connect({
    sessionId: "session-1",
    accessToken: "bearer-must-not-enter-url",
    websocketUrl: "wss://game.invalid/v1/pvp/events",
    websocketTicket: "single-use-ticket",
    eventsUrl: "https://game.invalid/events",
    commandsUrl: "https://game.invalid/commands",
    initialCursor: 4,
  });
  socket.readyState = 1;
  socket.onopen?.();
  await connected;
  socket.onmessage?.({ data: JSON.stringify({ cursor: 5, payload: { type: "attack" } }) });
  socket.onmessage?.({ data: JSON.stringify({ cursor: 5, payload: { type: "duplicate" } }) });
  await transport.send({ command: { type: "attack" } });

  assert.equal(openedUrl.includes("ticket=single-use-ticket"), true);
  assert.equal(openedUrl.includes("bearer-must-not-enter-url"), false);
  assert.deepEqual(received, [5]);
  assert.equal(socket.sent.length, 1);
});

function fakeSocket(): WebSocketLike & { readyState: number; sent: string[] } {
  return {
    readyState: 0,
    onopen: null,
    onmessage: null,
    onerror: null,
    onclose: null,
    sent: [],
    send(data: string) {
      this.sent.push(data);
    },
    close() {
      this.readyState = 3;
      this.onclose?.();
    },
  };
}
