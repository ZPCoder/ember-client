# Internal desktop QA policy

Windows and macOS output exists solely to exercise Cocos behavior off-browser.
Every desktop build must satisfy all of these gates:

- environment is `internal-qa` and `TestIdentityGate` succeeds;
- production channel tickets and production player assets are rejected;
- artifact retention is at most 14 days and access is limited to the QA team;
- the About panel carries `NOT FOR PUBLIC DISTRIBUTION`;
- no updater, payment, standalone registration, public signing, notarization,
  store upload, or public download URL is configured.

The Windows artifact is produced on a Windows runner; the macOS artifact on a
macOS runner. A release workflow must fail closed when any test-identity secret
or environment marker is missing.
