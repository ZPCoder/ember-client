# Frozen React/Sites emergency fallback

This subtree is the self-contained React, Worker, D1 migration, and Sites build
surface extracted from `monolith-freeze-v1` at commit
`ba8610c7664f0f8a7cfdd70f479e61c8c41a77d1`. Its application, game, database,
worker, migrations, lockfile, and release tests are retained together so Ops
can reproduce the last known monolith release without importing code from the
Cocos client or any sibling repository.

## Authority and isolation

This is a deprecated operational rollback tuple, not the architectural source
of truth. Cocos, the new backend, protocol, SDK, and config packages must never
import it. No feature development or forward database migration belongs here.
It may be deployed only as the complete frozen monolith rollback, against its
matching rollback data plan; it must not concurrently write to the new
backend's production database. The planned protocol client/backend adapter will
eventually replace this whole subtree.

## Verification

From this directory, `npm ci && npm test` executes the frozen 235-rule suite,
the isolation test, a production Sites/Worker build, and publication checks.
The 1,000 card WebPs are intentionally absent from Git. A normal source build
validates their immutable manifest and proves no WebPs were committed.

Before promotion, Ops must hydrate all manifest paths into `public/cards` from
the approved object-store asset bundle and run:

```sh
npm run test:hydrated-release
```

That gate checks all 1,000 files, dimensions, minimum size, and uniqueness. A
source-only build is never sufficient authorization to publish the fallback.
