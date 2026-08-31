import assert from "node:assert/strict";
import test from "node:test";

import {
  CHANNEL_CAPABILITIES,
  assertQaIdentityGate,
  channelLogin,
} from "../assets/scripts/auth/ChannelAuthPort.ts";
import { CLIENT_BUDGETS, evaluatePerformance } from "../assets/scripts/performance/Budgets.ts";
import { FACTION_IDS, HERO_FORM_IDS } from "../assets/scripts/presentation/FactionCatalog.ts";
import { evaluateReferenceFixture } from "../reference-react/src/reference-harness.ts";

test("hero catalog has 20 factions plus one independent hero-card form", () => {
  assert.equal(FACTION_IDS.length, 20);
  assert.equal(new Set(FACTION_IDS).size, 20);
  assert.equal(HERO_FORM_IDS.length, 21);
  assert.equal(HERO_FORM_IDS.at(-1), "hero-card-transformed");
});

test("launch budgets and no-payment channel capability are executable policy", () => {
  assert.equal(CLIENT_BUDGETS.creatorVersion, "3.8.8");
  assert.equal(CLIENT_BUDGETS.browserBaseline, "webgl2");
  assert.equal(CLIENT_BUDGETS.compressedBootBytes, 15 * 1024 * 1024);
  assert.equal(CLIENT_BUDGETS.peakMemoryBytes, 800 * 1024 * 1024);
  assert.equal(CHANNEL_CAPABILITIES.supportsPayment, false);
  assert.deepEqual(evaluatePerformance({
    framesPerSecond: 29,
    peakMemoryBytes: CLIENT_BUDGETS.peakMemoryBytes + 1,
    compressedBootBytes: CLIENT_BUDGETS.compressedBootBytes + 1,
    firstInteractionMilliseconds: 8_001,
  }), [
    "fps-below-hard-floor",
    "peak-memory-over-budget",
    "compressed-boot-over-budget",
    "first-interaction-over-budget",
  ]);
});

test("desktop builds fail closed unless they use an internal QA identity", () => {
  assert.doesNotThrow(() => assertQaIdentityGate({
    buildTarget: "macos",
    environment: "internal-qa",
    identityProvider: "internal-qa",
    publicDistribution: false,
  }));
  assert.throws(() => assertQaIdentityGate({
    buildTarget: "windows",
    environment: "production",
    identityProvider: "4399-h5",
    publicDistribution: false,
  }), /internal-qa-identity/);
});

test("channel login forwards only an opaque ticket and never trusts a client UID", async () => {
  let forwarded: unknown;
  const gateway = {
    async exchange(request: unknown) {
      forwarded = request;
      return { accessToken: "short", expiresAt: "2030-01-01", playerId: "server-player", configVersion: "v1" };
    },
  };
  await channelLogin(gateway, { platform: "4399-h5", ticket: "one-time", clientVersion: "1.0.0" });
  assert.deepEqual(forwarded, { platform: "4399-h5", ticket: "one-time", clientVersion: "1.0.0" });
  await assert.rejects(channelLogin(gateway, {
    platform: "4399-h5",
    ticket: "one-time",
    clientVersion: "1.0.0",
    uid: "attacker-controlled",
  } as never), /uid-forbidden/);
});

test("React protocol reference hash is independent of object key insertion order", () => {
  const left = evaluateReferenceFixture({
    seed: 7,
    commands: [{ type: "end-turn", player: 0 }],
    snapshot: { version: 2, activePlayer: 1 },
    events: [{ seq: 1, type: "turn-ended" }],
  });
  const right = evaluateReferenceFixture({
    seed: 7,
    commands: [{ player: 0, type: "end-turn" }],
    snapshot: { activePlayer: 1, version: 2 },
    events: [{ type: "turn-ended", seq: 1 }],
  });
  assert.deepEqual(left, right);
});
