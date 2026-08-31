# Cocos Creator editor bootstrap

1. Install Cocos Dashboard and Creator 3.8.8, then import this directory.
2. Allow Creator to generate `library`, `temp`, and all `.meta` files. Do not
   copy metadata from another project.
3. Create these scenes using exactly these names: `BootLogin`, `Collection`,
   `DeckBuilder`, `PackOpening`, `Battle`, `OnlineLobby`, and `Profile`.
4. In `BootLogin`, add a root node with `EmberBootstrap`; it builds the
   placeholder 3D battlefield programmatically and installs scene routing.
5. In `Battle`, add `AuthoritativeBattleView` and connect a presentation adapter
   for cards, heroes, camera, animations, and effects. Do not attach game-rule
   scripts to presentation nodes.
6. Mark folders according to `assets/bundles/README.md` in the Inspector. Creator
   stores bundle flags in its generated folder metadata.
7. Configure the Web Mobile build for WebGL2. Keep WebGPU behind a detected
   capability flag. Build Windows/macOS only in protected internal-QA CI.

The procedural models are deliberately unlicensed placeholder geometry. Replace
them with reviewed commercial assets while preserving the rig, presentation,
and bundle ports.
