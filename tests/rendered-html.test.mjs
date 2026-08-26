import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { access, readFile, stat } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import test from "node:test";

import sharp from "sharp";

import { CARD_CATALOG } from "../lib/game/catalog.ts";

const projectRoot = new URL("../", import.meta.url);

test("build emits a deployable worker, D1 metadata, and migrations", async () => {
  const [worker, hosting, migration, matchmakingMigration] = await Promise.all([
    stat(new URL("../dist/server/index.js", import.meta.url)),
    readFile(new URL("../dist/.openai/hosting.json", import.meta.url), "utf8"),
    readFile(
      new URL("../dist/.openai/drizzle/0000_polite_fabian_cortez.sql", import.meta.url),
      "utf8",
    ),
    readFile(
      new URL("../dist/.openai/drizzle/0003_thick_miss_america.sql", import.meta.url),
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
  assert.match(matchmakingMigration, /CREATE TABLE IF NOT EXISTS `pvp_matchmaking_ratings`/);
  assert.match(matchmakingMigration, /CREATE TABLE IF NOT EXISTS `pvp_mmr_settlements`/);
  assert.match(matchmakingMigration, /pvp_matchmaking_ratings_format_rating_idx/);
});

test("ships the complete product surface and removes starter assets", async () => {
  const [page, game, styles, worker, ranked, rankedRewards, gameStore, layout, packageJson, og, artManifest, imageGenManifest] = await Promise.all([
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/GameApp.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/globals.css", import.meta.url), "utf8"),
    readFile(new URL("../worker/index.ts", import.meta.url), "utf8"),
    readFile(new URL("../lib/game/ranked.ts", import.meta.url), "utf8"),
    readFile(new URL("../lib/game/ranked-rewards.ts", import.meta.url), "utf8"),
    readFile(new URL("../db/game-store.ts", import.meta.url), "utf8"),
    readFile(new URL("../app/layout.tsx", import.meta.url), "utf8"),
    readFile(new URL("../package.json", import.meta.url), "utf8"),
    stat(new URL("../public/og.png", import.meta.url)),
    readFile(new URL("../public/card-art-manifest.json", import.meta.url), "utf8"),
    readFile(new URL("../public/card-art-imagegen.json", import.meta.url), "utf8"),
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
  assert.match(game, /新兵晋升轨道/);
  assert.match(game, /claim_apprentice_reward/);
  assert.match(game, /APPRENTICE_MILESTONES/);
  assert.match(game, /新兵专属匹配池/);
  assert.match(game, /改打 AI 演算/);
  assert.match(game, /apprenticeMatchPoolForFacts/);
  assert.match(game, /隐藏水平匹配 · 数值不公开/);
  assert.match(game, /显示段位不参与选人/);
  assert.match(game, /匹配质量/);
  assert.match(game, /胜利星级 ×/);
  assert.match(game, /当前 10\/5 段位保护生效/);
  assert.match(game, /每月从青铜 10 重启/);
  assert.match(game, /赛季天梯奖励/);
  assert.match(game, /下月首次登录自动入库/);
  assert.match(game, /任意段位赢得 5 场 Ranked/);
  assert.match(game, /天梯预备套牌/);
  assert.match(game, /activate_ladder_ready/);
  assert.match(game, /claim_ladder_ready_deck/);
  assert.match(game, /LADDER_READY_DECKS/);
  assert.match(game, /AI 与在线对战均可使用/);
  assert.match(game, /\/api\/game/);
  assert.match(game, /\/cards\/\$\{card\.id\}\.webp/);
  assert.match(game, /<Image[\s\S]*?\bunoptimized\b[\s\S]*?\/>/);
  assert.match(game, /AudioContext/);
  assert.match(game, /battleEventsToEffects/);
  assert.match(game, /battleEventsToEffects\(next\.events\.slice\(previousEventCount\)\),\s*\{ lock: true \}/);
  assert.match(game, /BATTLE_EFFECT_STEP_MS = 1200/);
  assert.match(game, /BATTLE_EFFECT_QUEUE_LIMIT = 96/);
  assert.match(game, /TURN_TIME_LIMIT_SECONDS = 75/);
  assert.match(game, /turn-timed-out/);
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
  assert.match(game, /targetPromptAttacker/);
  assert.match(game, /有效攻击/);
  assert.match(game, /武器有效攻击/);
  assert.match(game, /targetPreviewForPendingUnit/);
  assert.match(game, /预计冻结/);
  assert.match(game, /预计破甲/);
  assert.match(game, /先破护盾/);
  assert.match(game, /反击 −/);
  assert.match(game, /取消攻击目标选择/);
  assert.match(game, /hero-core__health-bar/);
  assert.match(game, /hero-core__mobile-health/);
  assert.match(game, /board-unit__impact/);
  assert.match(game, /frozenTurns/);
  assert.match(game, /board-unit__status/);
  assert.match(game, /hero-core__impact/);
  assert.match(game, /battle-fx__card-reveal/);
  assert.match(game, /eager/);
  assert.match(game, /ai-archetype-picker/);
  assert.match(game, /AI_ARCHETYPES/);
  assert.match(game, /选择演算对手/);
  assert.match(styles, /\.ai-archetype-picker/);
  assert.match(styles, /\.apprentice-track/);
  assert.match(styles, /\.apprentice-track__pool/);
  assert.match(styles, /\.pvp-lobby__pool/);
  assert.match(styles, /\.pvp-lobby__queue\.is-protected/);
  assert.match(styles, /\.pvp-lobby__mmr/);
  assert.match(styles, /\.pvp-lobby__match-rule/);
  assert.match(styles, /\.apprentice-step\.is-ready/);
  assert.match(styles, /\.ladder-ready__grid/);
  assert.match(styles, /\.ladder-ready-card\.is-claimed/);
  assert.match(styles, /\.ranked-rewards-grid/);
  assert.match(styles, /\.ranked-reward-card\.is-earned/);
  assert.match(styles, /\.ranked-rewards-history/);
  assert.match(styles, /\.turn-clock/);
  assert.match(styles, /\.board-slot/);
  assert.match(styles, /battle-target-pulse/);
  assert.match(styles, /battle-target-impact/);
  assert.match(styles, /board-unit__target-preview/);
  assert.match(styles, /board-unit--frozen/);
  assert.match(styles, /board-unit__status/);
  assert.match(styles, /\.screen\.battle-room/);
  assert.match(styles, /@keyframes battle-room-enter/);
  assert.match(styles, /\.battle-fx__card-reveal/);
  assert.match(worker, /pvp_queue_format_pool_joined_idx/);
  assert.match(worker, /pvp_queue_format_pool_rating_joined_idx/);
  assert.match(worker, /q\.pool = \?/);
  assert.match(worker, /apprenticeMatchPoolForFacts/);
  assert.match(worker, /pvp_matchmaking_ratings/);
  assert.match(worker, /pvp_mmr_settlements/);
  assert.match(worker, /updateHiddenMmr/);
  assert.match(worker, /MATCHMAKING_WINDOW_INITIAL/);
  assert.match(worker, /MATCHMAKING_WINDOW_STEP_MS/);
  assert.match(worker, /正在按隐藏水平寻找/);
  assert.match(ranked, /LADDER_RANKS_PER_LEAGUE = 10/);
  assert.match(ranked, /LADDER_STARS_PER_RANK = 3/);
  assert.match(ranked, /resetRankedSnapshotForSeason/);
  assert.match(ranked, /normalizeRankedSnapshot/);
  assert.match(ranked, /crossedRankFloors/);
  assert.match(ranked, /progress < LADDER_DIAMOND_FIVE_PROGRESS/);
  assert.match(rankedRewards, /RANKED_SEASON_REWARD_LEVELS/);
  assert.match(rankedRewards, /RANKED_FIRST_TIME_REWARD_LEVELS/);
  assert.match(rankedRewards, /applyOutstandingRankedRewards/);
  assert.match(rankedRewards, /rollRankedSeason/);
  assert.match(gameStore, /applyRankedMatchResult/);
  assert.match(gameStore, /rollRankedSeason/);
  assert.match(styles, /@keyframes battle-card-reveal/);
  assert.match(styles, /\.battlefield__fx-layer/);
  assert.match(styles, /battle-banner-enter 840ms/);
  assert.match(styles, /@keyframes battle-lunge-player/);
  assert.match(styles, /@media \(prefers-reduced-motion: reduce\)/);
  assert.doesNotMatch(game, /<svg/i);
  assert.doesNotMatch(packageJson, /react-loading-skeleton/);
  assert.ok(og.size > 100_000);
  assert.equal(cardIds.length, 1000);
  const parsedManifest = JSON.parse(artManifest);
  const parsedImageGenManifest = JSON.parse(imageGenManifest);
  assert.equal(parsedManifest.catalogCount, cardIds.length);
  assert.equal(parsedManifest.cards.length, cardIds.length);
  assert.equal(parsedImageGenManifest.workflow, "built-in-imagegen-one-card-per-call");
  assert.equal(parsedImageGenManifest.generatedCount, parsedImageGenManifest.cards.length);
  assert.ok(parsedImageGenManifest.cards.length >= 5);
  assert.ok(parsedImageGenManifest.cards.every((entry) => cardIds.includes(entry.id)));
  assert.deepEqual(
    new Set(parsedManifest.cards.map((entry) => entry.id)),
    new Set(cardIds),
  );
  // Generated WebP art is intentionally optimized for mobile delivery; even
  // the smallest card remains a real bitmap rather than a placeholder.
  assert.ok(cardArt.every(({ asset }) => asset.size > 8_000));
  assert.ok(
    cardArt.every(({ metadata }) =>
      metadata.format === "webp" &&
      ((metadata.width === 384 && metadata.height === 480) ||
        (metadata.width === 512 && metadata.height === 640) ||
        (metadata.width === 768 && metadata.height === 960)),
    ),
  );
  assert.equal(new Set(cardArt.map(({ hash }) => hash)).size, 1000);

  await assert.rejects(
    access(new URL("../app/_sites-preview", projectRoot)),
  );
});
