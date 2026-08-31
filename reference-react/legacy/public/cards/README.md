# Remote card-art mount point

The frozen fallback references 1,000 WebPs listed in
`../card-art-manifest.json`. They are deliberately not stored in Git. Ops must
hydrate this directory from the approved immutable object-store bundle and run
`npm run test:hydrated-release` before promotion.
