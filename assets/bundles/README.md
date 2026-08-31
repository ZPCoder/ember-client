# Remote Asset Bundle layout

Creator folder metadata (generated in the editor) must define these immutable
bundle names:

| Bundle | Contents | Lifetime |
| --- | --- | --- |
| `bootstrap` | boot/login shell and compatibility screen | app lifetime |
| `common-ui` | shared fonts, panels, icons | app lifetime after login |
| `battlefield` | board meshes, shaders, camera and common VFX | one battle |
| `heroes-01` … `heroes-04` | five faction modules per group | on demand |
| `card-thumbnails` | collection/deck thumbnails | per catalog page |
| `card-full` | full-resolution 2D card faces | explicit card/battle demand |

Only `bootstrap` is included in the initial package. `RemoteBundleLoader`
requires a fail-closed `BundleIntegrityVerifier` supplied by the config/SDK
download adapter before loading a remote URL, reference-counts consumers, and
releases unused bundles/assets. Bundle archives come from object storage;
Git contains only manifests and licensed Creator-importable source assets.
