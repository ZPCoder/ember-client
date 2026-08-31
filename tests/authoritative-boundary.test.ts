import assert from "node:assert/strict";
import test from "node:test";

import { AuthoritativeBattleStore } from "../assets/scripts/core/AuthoritativeBattleStore.ts";

interface Snapshot {
  readonly matchId: string;
  readonly stateVersion: number;
  readonly state: { readonly health: number; readonly hand: readonly string[] };
}

interface Event {
  readonly matchId: string;
  readonly cursor: number;
  readonly stateVersion: number;
  readonly eventId: string;
  readonly kind: string;
}

test("authoritative store applies only increasing snapshots and freezes its copy", () => {
  const store = new AuthoritativeBattleStore<Snapshot, Event>();
  const received: number[] = [];
  store.subscribeSnapshot((snapshot) => received.push(snapshot.stateVersion));
  const source = { matchId: "m-1", stateVersion: 3, state: { health: 28, hand: ["visible"] } };

  assert.equal(store.applyBatch({ snapshot: source }).snapshotApplied, true);
  source.state.health = 0;
  source.state.hand.push("mutation");
  assert.deepEqual(store.snapshot?.state, { health: 28, hand: ["visible"] });
  assert.equal(Object.isFrozen(store.snapshot?.state), true);

  assert.equal(store.applyBatch({
    snapshot: { matchId: "m-1", stateVersion: 2, state: { health: 1, hand: [] } },
  }).snapshotApplied, false);
  assert.deepEqual(received, [3]);
});

test("event overlap is idempotent and cursor ordered", () => {
  const store = new AuthoritativeBattleStore<Snapshot, Event>();
  const received: string[] = [];
  store.subscribeEvent((event) => received.push(event.eventId));

  const event1 = { matchId: "m-1", cursor: 1, stateVersion: 1, eventId: "e-1", kind: "attack" };
  const event2 = { matchId: "m-1", cursor: 2, stateVersion: 2, eventId: "e-2", kind: "damage" };
  const result = store.applyBatch({ events: [event2, event1, event1] });
  assert.equal(result.appliedEventCount, 2);
  assert.equal(result.cursor, 2);
  assert.deepEqual(received, ["e-1", "e-2"]);
  assert.equal(store.applyBatch({ events: [event1, event2] }).appliedEventCount, 0);
});

test("match transition is explicit and cross-match batches fail closed", () => {
  const store = new AuthoritativeBattleStore<Snapshot, Event>();
  store.applyBatch({
    snapshot: { matchId: "m-1", stateVersion: 1, state: { health: 30, hand: [] } },
  });
  assert.throws(() => store.applyBatch({
    snapshot: { matchId: "m-2", stateVersion: 2, state: { health: 30, hand: [] } },
  }), /match-id-mismatch/);
  store.resetForMatchTransition();
  assert.equal(store.stateVersion, -1);
  assert.equal(store.cursor, 0);
  assert.equal(store.applyBatch({
    snapshot: { matchId: "m-2", stateVersion: 1, state: { health: 30, hand: [] } },
  }).snapshotApplied, true);
});

test("an event-only batch locks match identity and observed state version", () => {
  const store = new AuthoritativeBattleStore<Snapshot, Event>();
  store.applyBatch({
    events: [{ matchId: "m-1", cursor: 4, stateVersion: 5, eventId: "e-4", kind: "attack" }],
  });
  assert.throws(() => store.applyBatch({
    snapshot: { matchId: "m-2", stateVersion: 6, state: { health: 30, hand: [] } },
  }), /match-id-mismatch/);
  assert.equal(store.applyBatch({
    snapshot: { matchId: "m-1", stateVersion: 4, state: { health: 30, hand: [] } },
  }).snapshotApplied, false);
  assert.equal(store.applyBatch({
    snapshot: { matchId: "m-1", stateVersion: 5, state: { health: 29, hand: [] } },
  }).snapshotApplied, true);
});
