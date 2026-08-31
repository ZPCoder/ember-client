# Ember Client

The primary client is a Cocos Creator **3.8.8** TypeScript project for the 4399
PC H5 launch. Windows and macOS builds are internal QA artifacts only. The
repository also carries a tiny React protocol reference harness, the filtered
React/Sites source for migration reference, and a temporary operator-only
Flutter save exporter.

## Authority boundary

The client renders versioned, player-redacted snapshots and ordered events. A
player gesture can only call a `CommandSink` with a `BattleCommand`; it never
mutates a formal PVP snapshot, inventory, currency, deck, or match result. The
authoritative rules ship from `ember-sdk` and run locally only for offline AI;
formal PVP and all durable assets remain server-owned.

Dependency direction is fixed as `ember-protocol -> ember-sdk -> ember-client`
and `ember-config -> ember-client`. The narrow local `ProtocolPort` is a
consumer-side structural boundary, not another rule/schema implementation. A
cross-repository compatibility job must prove the generated protocol types
satisfy it.

The three upstream packages are optional peers because the dependency-free
boundary tests run before GitHub Packages credentials are available. Production
compatibility builds must install the exact tuple recorded by `ember-ops`.

## Retained migration references

- `reference-react/src` is the small deterministic protocol parity harness.
- `reference-react/legacy` preserves the filtered React source, its lockfile,
  and its Sites `.openai/hosting.json`. It is a **non-authoritative migration
  reference**, not a standalone split-repository release yet: the historical
  API route still depends on server/rule modules that now belong to backend and
  SDK packages. Until that adapter work lands, emergency rollback uses the
  frozen `monolith-freeze-v1` Sites release.
- `legacy-flutter-app` is the frozen Flutter source and 90-test baseline. It is
  excluded from Cocos builds and must not receive product features.
- `tools/flutter-save-exporter` is the temporary, operator-only JSON normalizer;
  it is never bundled into either player client.

## Local checks without Creator

```sh
npm test
```

The tests use Node's built-in TypeScript stripping and need no downloaded npm
packages. They verify monotonic snapshot/event application, command-only user
input, polling/WebSocket transport parity, 21 hero forms, performance budgets,
the React reference hash, and protocol-shaped save-export validation. Run
`npm ci` to install the locked public tooling before `npm run typecheck:ci`.

This machine does not currently have Cocos Creator installed, so no `.scene` or
`.meta` file is checked in by hand. Follow `docs/EDITOR_BOOTSTRAP.md` on a
licensed workstation to let Creator generate them, then run a WebGL2 preview.

## Release gates

- Browser baseline: WebGL2; WebGPU is optional enhancement only.
- Compressed boot payload: <= 15 MB; first interaction <= 8 seconds at 20 Mbps.
- 1080p integrated-GPU target: 60 FPS, hard floor 30 FPS; peak memory <= 800 MB.
- Formal PVP accepts only short-lived server sessions and redacted state.
- Windows/macOS packages require test identity and must never be publicly
  distributed. No updater, public signing/notarization, or standalone account
  system is part of this release.
- Payment capability is false for the first 4399 submission; there is no
  recharge UI or product catalog.
