import assert from "node:assert/strict";
import { readFile, readdir, stat } from "node:fs/promises";
import { dirname, extname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const files = await walk(root);
const relativeFiles = files.map((file) => relative(root, file));

assert.equal(relativeFiles.some((file) => file.endsWith(".scene")), false, "do not handwrite Creator scenes");
assert.equal(relativeFiles.some((file) => file.endsWith(".meta")), false, "do not handwrite Creator metadata");
assert.equal(relativeFiles.some((file) => file.includes("node_modules/")), false);

for (const file of files.filter((candidate) => extname(candidate) === ".ts" && candidate.includes("/assets/"))) {
  const source = await readFile(file, "utf8");
  assert.equal(
    /from\s+["'][^"']+\.ts["']/.test(source),
    false,
    `${relative(root, file)} uses a .ts import specifier unsupported by Creator`,
  );
}

const packageJson = JSON.parse(await readFile(join(root, "package.json"), "utf8"));
const packageLock = JSON.parse(await readFile(join(root, "package-lock.json"), "utf8"));
assert.equal(packageJson.creator.version, "3.8.8");
assert.equal(packageJson.devDependencies["@cocos/creator-types"], "3.8.8");
assert.equal(packageLock.name, "@zpcoder/ember-client");
assert.equal(packageLock.version, "0.1.0");
assert.equal(
  packageLock.packages["node_modules/@cocos/creator-types"].integrity,
  "sha512-VAn8lWxUZ7LwPWwU/Lj7BOjsy0EoNFtjTqO7jz9bysYdjAJu7Jht/WKJbWYNHeZEC/omE7rTw98giuVRiTuELg==",
);
assert.equal(packageJson.devDependencies["@changesets/cli"], undefined);
assert.match(packageJson.scripts.changeset, /@changesets\/cli@2\.29\.8/);
for (const dependency of [
  "@zpcoder/ember-config",
  "@zpcoder/ember-protocol",
  "@zpcoder/ember-sdk",
]) {
  assert.equal(packageJson.peerDependencies[dependency], "^0.1.0");
  assert.equal(packageJson.peerDependenciesMeta[dependency].optional, true);
}

await stat(join(root, "reference-react/legacy/.openai/hosting.json"));
await stat(join(root, "reference-react/legacy/package-lock.json"));
await stat(join(root, "legacy-flutter-app/pubspec.lock"));

const migration = await readFile(join(root, "MIGRATION.md"), "utf8");
assert.match(migration, /monolith-freeze-v1/);
assert.match(migration, /ba8610c7664f0f8a7cfdd70f479e61c8c41a77d1/);

const sceneCoordinator = await readFile(
  join(root, "assets/scripts/scenes/SceneCoordinator.ts"),
  "utf8",
);
for (const scene of [
  "BootLogin",
  "Collection",
  "DeckBuilder",
  "PackOpening",
  "Battle",
  "OnlineLobby",
  "Profile",
]) {
  assert.match(sceneCoordinator, new RegExp(`"${scene}"`));
}

const authoritativeView = await readFile(
  join(root, "assets/scripts/presentation/AuthoritativeBattleView.ts"),
  "utf8",
);
assert.match(authoritativeView, /#commandSink\.send/);
assert.doesNotMatch(authoritativeView, /applyCommand|dispatchRule|mutateAsset|setCurrency/);

const exporterReadme = await readFile(
  join(root, "tools/flutter-save-exporter/README.md"),
  "utf8",
);
assert.match(exporterReadme, /not bundled\s+into Cocos/i);
assert.match(exporterReadme, /does not upload/i);

const largeFiles = [];
for (const file of files) {
  const info = await stat(file);
  if (info.size > 5 * 1024 * 1024) {
    largeFiles.push(relative(root, file));
  }
}
assert.deepEqual(largeFiles, [], "large art or bundles must not be committed");

process.stdout.write(`static client boundary check passed (${files.length} files)\n`);

async function walk(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const output = [];
  for (const entry of entries) {
    if ([
      ".git",
      "node_modules",
      "library",
      "local",
      "temp",
      "build",
      "profiles",
      "native",
      "legacy",
      "legacy-flutter-app",
    ].includes(entry.name)) {
      continue;
    }
    const path = join(directory, entry.name);
    if (entry.isDirectory()) {
      output.push(...await walk(path));
    } else {
      output.push(path);
    }
  }
  return output;
}
