# React protocol reference and retained fallback source

The filtered monolith React client remains the visual/protocol baseline during
the migration. `src/reference-harness.ts` canonicalizes each redacted snapshot
and event list into a deterministic hash. Cocos, React, local AI, and server
replay fixtures must agree on that hash before a compatibility tuple can ship.

`legacy/` preserves the filtered monolith UI, its dependency lock, and the
existing Sites layout under `legacy/.openai/hosting.json`. It is deliberately
non-authoritative and cannot write formal assets or PVP state directly.

The legacy subtree is not yet a standalone build: its historical API route
references server and rule modules that moved to `ember-backend-admin` and
`ember-sdk`. Until that route is replaced by generated protocol clients, the
emergency H5 rollback target is the frozen `monolith-freeze-v1` Sites release.
Do not silently deploy this subtree as a replacement for that release.
