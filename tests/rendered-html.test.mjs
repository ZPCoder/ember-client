import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { access, readFile, stat } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import test from "node:test";

import sharp from "sharp";

import { CARD_CATALOG } from "../lib/game/catalog.ts";

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
  const [page, game, styles, layout, packageJson, og] = await Promise.all([
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/GameApp.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/globals.css", import.meta.url), "utf8"),
    readFile(new URL("../app/layout.tsx", import.meta.url), "utf8"),
    readFile(new URL("../package.json", import.meta.url), "utf8"),
    stat(new URL("../public/og.png", import.meta.url)),
  ]);
  const cardIds = CARD_CATALOG.map((card) => card.id);
  const cardArt = await Promise.all(
    cardIds.map(async (cardId) => {
      const assetUrl = new URL(`../public/cards/${cardId}.webp`, import.meta.url);
      const [asset, contents] = await Promise.all([
        stat(assetUrl),
        readFile(fileURLToPath(assetUrl)),
      ]);
      const metadata = await sharp(contents).metadata();
      const hash = createHash("sha256").update(contents).digest("hex");
      return { asset, hash, metadata };
    }),
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
  assert.match(game, /<Image[\s\S]*?\bunoptimized\b[\s\S]*?\/>/);
  assert.match(game, /AudioContext/);
  assert.match(game, /battleEventsToEffects/);
  assert.match(game, /BATTLE_EFFECT_STEP_MS = 1200/);
  assert.match(game, /BATTLE_EFFECT_QUEUE_LIMIT = 40/);
  assert.match(game, /TURN_TIME_LIMIT_SECONDS = 75/);
  assert.match(game, /turnClockSeconds/);
  assert.match(game, /board-slot/);
  assert.match(game, /跳过回放/);
  assert.match(game, /aria-pressed=\{soundEnabled\}/);
  assert.match(game, /heroPowerTarget/);
  assert.match(game, /board-unit__inspect/);
  assert.match(game, /board-unit__target-hint/);
  assert.match(game, /hero-core__target-hint/);
  assert.match(game, /board-unit__target-preview/);
  assert.match(game, /hero-core__target-preview/);
  assert.match(game, /target-prompt__preview/);
  assert.match(game, /取消攻击目标选择/);
  assert.match(game, /hero-core__health-bar/);
  assert.match(game, /hero-core__mobile-health/);
  assert.match(game, /board-unit__impact/);
  assert.match(game, /hero-core__impact/);
  assert.match(game, /ai-archetype-picker/);
  assert.match(game, /AI_ARCHETYPES/);
  assert.match(game, /选择演算对手/);
  assert.match(styles, /\.ai-archetype-picker/);
  assert.match(styles, /\.turn-clock/);
  assert.match(styles, /\.board-slot/);
  assert.match(styles, /battle-target-pulse/);
  assert.match(styles, /battle-target-impact/);
  assert.match(styles, /board-unit__target-preview/);
  assert.match(styles, /\.battlefield__fx-layer/);
  assert.match(styles, /battle-banner-enter 840ms/);
  assert.match(styles, /@keyframes battle-lunge-player/);
  assert.match(styles, /@media \(prefers-reduced-motion: reduce\)/);
  assert.doesNotMatch(game, /<svg/i);
  assert.doesNotMatch(packageJson, /react-loading-skeleton/);
  assert.ok(og.size > 100_000);
  assert.equal(cardIds.length, 210);
  assert.ok(cardArt.every(({ asset }) => asset.size > 75_000));
  assert.ok(
    cardArt.every(({ metadata }) =>
      metadata.format === "webp" && metadata.width === 768 && metadata.height === 960,
    ),
  );
  assert.equal(new Set(cardArt.map(({ hash }) => hash)).size, 210);

  await assert.rejects(
    access(new URL("../app/_sites-preview", projectRoot)),
  );
});
