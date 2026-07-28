import assert from "node:assert/strict";
import { access, readFile, stat } from "node:fs/promises";
import test from "node:test";

const projectRoot = new URL("../", import.meta.url);

test("build emits a deployable worker, D1 metadata, and migration", async () => {
  const [worker, hosting, migration] = await Promise.all([
    stat(new URL("../dist/server/index.js", import.meta.url)),
    readFile(new URL("../dist/.openai/hosting.json", import.meta.url), "utf8"),
    readFile(
      new URL("../dist/.openai/drizzle/0000_polite_fabian_cortez.sql", import.meta.url),
      "utf8",
    ),
  ]);

  assert.ok(worker.size > 10_000);
  assert.deepEqual(JSON.parse(hosting), {
    project_id: "appgprj_6a6856ce43d881918a7688aecdfb4647",
    d1: "DB",
    r2: null,
  });
  assert.match(migration, /CREATE TABLE `players`/);
  assert.match(migration, /CREATE TABLE `match_records`/);
});

test("ships the complete product surface and removes starter assets", async () => {
  const [page, game, layout, packageJson, catalog, og] = await Promise.all([
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/GameApp.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/layout.tsx", import.meta.url), "utf8"),
    readFile(new URL("../package.json", import.meta.url), "utf8"),
    readFile(new URL("../lib/game/catalog.ts", import.meta.url), "utf8"),
    stat(new URL("../public/og.png", import.meta.url)),
  ]);
  const cardIds = [...catalog.matchAll(/\bid:\s*"([^"]+)"/g)].map((match) => match[1]);
  const cardArt = await Promise.all(
    cardIds.map((cardId) =>
      stat(new URL(`../public/cards/${cardId}.webp`, import.meta.url)),
    ),
  );

  assert.match(page, /<GameApp/);
  assert.match(layout, /generateMetadata/);
  assert.match(layout, /\/og\.png/);
  assert.match(layout, /lang="zh-CN"/);
  assert.match(game, /战情总览/);
  assert.match(game, /卡牌收藏/);
  assert.match(game, /卡组工坊/);
  assert.match(game, /战术对战/);
  assert.match(game, /运营台/);
  assert.match(game, /\/api\/game/);
  assert.match(game, /\/cards\/\$\{card\.id\}\.webp/);
  assert.doesNotMatch(game, /<svg/i);
  assert.doesNotMatch(packageJson, /react-loading-skeleton/);
  assert.ok(og.size > 100_000);
  assert.equal(cardIds.length, 24);
  assert.ok(cardArt.every((asset) => asset.size > 100_000));

  await assert.rejects(
    access(new URL("../app/_sites-preview", projectRoot)),
  );
});
