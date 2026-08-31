import assert from "node:assert/strict";
import { access, readFile, readdir } from "node:fs/promises";
import { dirname, extname, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const projectRoot = resolve(fileURLToPath(new URL("../", import.meta.url)));

test("retains the exact frozen rollback provenance and required Sites surface", async () => {
  const source = JSON.parse(await readFile(resolve(projectRoot, "FROZEN_SOURCE.json"), "utf8"));
  assert.equal(source.sourceRepository, "ZPCoder/ember-protocol-monolith");
  assert.equal(source.sourceTag, "monolith-freeze-v1");
  assert.equal(source.sourceCommit, "ba8610c7664f0f8a7cfdd70f479e61c8c41a77d1");
  assert.equal(source.authorityStatus, "deprecated-emergency-rollback-only");

  for (const required of [
    ".openai/hosting.json",
    "app/GameApp.tsx",
    "build/sites-vite-plugin.ts",
    "db/game-store.ts",
    "db/schema.ts",
    "drizzle/0000_polite_fabian_cortez.sql",
    "lib/game/engine.ts",
    "tests/game-engine.test.ts",
    "worker/index.ts",
  ]) {
    await access(resolve(projectRoot, required));
  }
});

test("cannot become a reverse dependency or silently carry card binaries", async () => {
  const packageJson = JSON.parse(await readFile(resolve(projectRoot, "package.json"), "utf8"));
  const dependencyNames = Object.keys({
    ...packageJson.dependencies,
    ...packageJson.devDependencies,
  });
  assert.equal(dependencyNames.some((name) => name.startsWith("@zpcoder/ember-")), false);

  const cardFiles = await readdir(resolve(projectRoot, "public/cards"));
  assert.deepEqual(cardFiles.filter((file) => file.endsWith(".webp")), []);

  for (const forbidden of ["flutter_app", "server", "docker"]) {
    await assert.rejects(access(resolve(projectRoot, forbidden)));
  }

  const sourceFiles = await Promise.all(
    ["app", "build", "db", "lib", "worker"].map((root) => walk(resolve(projectRoot, root))),
  );
  for (const file of sourceFiles.flat().filter((entry) => [".ts", ".tsx", ".mjs"].includes(extname(entry)))) {
    const contents = await readFile(file, "utf8");
    assert.doesNotMatch(contents, /@zpcoder\/ember-/);
    for (const match of contents.matchAll(/(?:from\s+|import\s*\()["'](\.[^"']+)["']/g)) {
      const imported = resolve(dirname(file), match[1]);
      assert.ok(
        imported === projectRoot || imported.startsWith(`${projectRoot}${sep}`),
        `${file} imports outside the frozen fallback: ${match[1]}`,
      );
    }
  }
});

async function walk(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const candidate = resolve(directory, entry.name);
    if (entry.isDirectory()) {
      files.push(...await walk(candidate));
    } else {
      files.push(candidate);
    }
  }
  return files;
}
