import assert from "node:assert/strict";
import test from "node:test";

import { normalizeLegacyFlutterSave } from "../src/legacy-save.ts";

test("normalizes a complete development save into LegacyFlutterSaveV1", () => {
  const output = normalizeLegacyFlutterSave({
    commander_name: "  QA Commander  ",
    collection: { "ember-card-1": 2 },
    coins: 125,
    arcaneDust: 40,
    cardPacks: { core: 3 },
    deckSlots: [{ slot: 26, name: "Wild QA", format: "wild", cardIds: ["ember-card-1"] }],
    format: "wild",
    stats: { wins: 5, losses: 2, draws: 1 },
  });
  assert.equal(output.schemaVersion, 1);
  assert.equal(output.commanderName, "QA Commander");
  assert.equal(output.decks[0]?.slot, 26);
  assert.equal(output.format, "wild");
  assert.equal(Object.isFrozen(output.collection), true);
  assert.deepEqual(Object.keys(output).sort(), [
    "schemaVersion",
    "commanderName",
    "collection",
    "gold",
    "dust",
    "packs",
    "decks",
    "format",
    "record",
  ].sort());
});

test("rejects negative, fractional and unreasonably large assets", () => {
  for (const gold of [-1, 1.5, 1_000_000_001]) {
    assert.throws(() => normalizeLegacyFlutterSave({
      commanderName: "QA",
      collection: {},
      gold,
      dust: 0,
      packs: {},
      decks: [],
      record: {},
    }), /gold must be a non-negative safe integer/);
  }
});

test("rejects more than 27 deck slots and repeated slot IDs", () => {
  const base = {
    commanderName: "QA",
    collection: {},
    gold: 0,
    dust: 0,
    packs: {},
    record: {},
  };
  assert.throws(() => normalizeLegacyFlutterSave({
    ...base,
    decks: Array.from({ length: 28 }, (_, slot) => ({ slot, cardIds: [] })),
  }), /at most 27/);
  assert.throws(() => normalizeLegacyFlutterSave({
    ...base,
    decks: [{ slot: 0, cardIds: [] }, { slot: 0, cardIds: [] }],
  }), /must be unique/);
});

test("rejects malformed card identifiers before an administrator can preview them", () => {
  assert.throws(() => normalizeLegacyFlutterSave({
    commanderName: "QA",
    collection: { "": 1 },
    gold: 0,
    dust: 0,
    packs: {},
    decks: [],
    record: {},
  }), /collection.id/);
});

test("enforces the canonical protocol collection and pack limits", () => {
  const base = {
    commanderName: "QA",
    gold: 0,
    dust: 0,
    decks: [],
    record: {},
  };
  assert.throws(() => normalizeLegacyFlutterSave({
    ...base,
    collection: { "ember-card-1": 1_000 },
    packs: {},
  }), /collection\.ember-card-1.*999/);
  assert.throws(() => normalizeLegacyFlutterSave({
    ...base,
    collection: {},
    packs: { core: 1_000_001 },
  }), /packs\.core.*1000000/);
});
