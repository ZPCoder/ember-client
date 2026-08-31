# Monolith migration provenance

- Source repository: `ZPCoder/Ember-Protocol`
- Frozen source tag: `monolith-freeze-v1`
- Frozen source commit: `ba8610c7664f0f8a7cfdd70f479e61c8c41a77d1`
- Target repository: `ZPCoder/ember-client`
- Extraction rule: client-facing React code, Cocos sources, the frozen Flutter
  test baseline, and the temporary Flutter development-save exporter only. No
  server authority or database ownership crosses this boundary. Retained
  React/Flutter trees are non-shipping migration references.

The first migration commit in the extracted repository must retain this file.
Large card art is intentionally absent: CI resolves immutable resource IDs and
SHA-256 values from `ember-config`, then downloads assets from object storage.
Creator-importable 3D source assets use Git LFS; marketplace archives and built
bundles stay in object storage.
