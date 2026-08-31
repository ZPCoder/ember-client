# Temporary Flutter save exporter

This is an operator/developer tool for named test users only. It is not bundled
into Cocos, is not reachable from a player-facing route, and does not upload or
import assets. It reads a locally obtained Flutter JSON snapshot, validates and
normalizes it as the generated protocol contract `LegacyFlutterSaveV1` (with
`schemaVersion: 1` and `format`), then writes the normalized JSON to stdout. An
administrator separately previews and applies the migration through the audited
backend API.

The CLI fails closed unless the operator explicitly sets:

```sh
EMBER_MIGRATION_OPERATOR_ACK=I_UNDERSTAND_DEV_ONLY \
  node --experimental-strip-types src/cli.ts ./test-user-save.json
```

Delete this entire directory after the migration window closes.
