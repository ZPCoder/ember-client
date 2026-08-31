# React protocol reference and retained fallback source

The filtered monolith React client remains the visual/protocol baseline during
the migration. `src/reference-harness.ts` canonicalizes each redacted snapshot
and event list into a deterministic hash. Cocos, React, local AI, and server
replay fixtures must agree on that hash before a compatibility tuple can ship.

`legacy/` preserves the complete frozen monolith UI, Worker, rule/database
dependencies, D1 migrations, dependency lock, and Sites layout under
`legacy/.openai/hosting.json`. It can reproduce the `monolith-freeze-v1`
rollback build without reaching into another repository.

It is still architecturally non-authoritative: active Cocos, SDK, backend, and
protocol code must never import it. Ops may select it only as a whole frozen
rollback tuple, after hydrating the remote card-art bundle and passing the
documented release gate. A future generated protocol/backend adapter replaces
this subtree rather than evolving its duplicated rules.
