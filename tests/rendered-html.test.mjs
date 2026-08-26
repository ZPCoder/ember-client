import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { access, readFile, stat } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import test from "node:test";

import sharp from "sharp";

import { CARD_CATALOG } from "../lib/game/catalog.ts";

const projectRoot = new URL("../", import.meta.url);

test("build emits a deployable worker, D1 metadata, and migrations", async () => {
  const [worker, hosting, migration, matchmakingMigration, formatMigration] = await Promise.all([
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
    readFile(
      new URL("../dist/.openai/drizzle/0004_absent_jack_murdock.sql", import.meta.url),
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
  assert.match(formatMigration, /CREATE TABLE `pvp_format_matchmaking_ratings`/);
  assert.match(formatMigration, /ALTER TABLE `match_records` ADD `ranked_format`/);
});

test("ships the complete product surface and removes starter assets", async () => {
  const [page, game, styles, worker, ranked, rankedRewards, cardBacks, catchUpPack, training, gameStore, gameRoute, layout, packageJson, og, artManifest, imageGenManifest] = await Promise.all([
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/GameApp.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/globals.css", import.meta.url), "utf8"),
    readFile(new URL("../worker/index.ts", import.meta.url), "utf8"),
    readFile(new URL("../lib/game/ranked.ts", import.meta.url), "utf8"),
    readFile(new URL("../lib/game/ranked-rewards.ts", import.meta.url), "utf8"),
    readFile(new URL("../lib/game/card-backs.ts", import.meta.url), "utf8"),
    readFile(new URL("../lib/game/catch-up-pack.ts", import.meta.url), "utf8"),
    readFile(new URL("../lib/game/training.ts", import.meta.url), "utf8"),
    readFile(new URL("../db/game-store.ts", import.meta.url), "utf8"),
    readFile(new URL("../app/api/game/route.ts", import.meta.url), "utf8"),
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
  assert.match(game, /删除卡组/);
  assert.match(game, /delete_deck/);
  assert.match(gameStore, /export async function deleteDeck/);
  assert.match(game, /战术对战/);
  assert.match(game, /运营台/);
  assert.match(game, /批量开启/);
  assert.match(game, /揭示下一张/);
  assert.match(game, /全部揭示/);
  assert.match(gameRoute, /open_packs/);
  assert.match(gameStore, /export async function openPacks/);
  assert.match(game, /全金色版本/);
  assert.match(game, /GOLDEN_BULK_PACK_MAX_COUNT/);
  assert.match(gameStore, /goldenCollection/);
  assert.match(gameRoute, /parseCardQuality/);
  assert.match(game, /新兵晋升轨道/);
  assert.match(game, /claim_apprentice_reward/);
  assert.match(game, /APPRENTICE_MILESTONES/);
  assert.match(game, /新兵专属匹配池/);
  assert.match(game, /保留进度并重试/);
  assert.match(game, /训练对局不计入正式战绩与奖励/);
  assert.match(game, /三关首领教学/);
  assert.match(game, /可交互战场机关/);
  assert.match(game, /BATTLEFIELD_TOY_LABELS/);
  assert.match(game, /场景共鸣/);
  assert.match(game, /trainingChapterProgressForCommands/);
  assert.match(game, /trainingChapterCommandAllowed/);
  assert.match(game, /trainingActive && trainingChapterId && preparedCommand\.player === 0/);
  assert.match(training, /雾门哨兵/);
  assert.match(training, /棱镜守门人/);
  assert.match(training, /逆流档案官/);
  assert.match(training, /kind: "use-coin"/);
  assert.match(training, /kind: "discover"/);
  assert.match(gameStore, /export async function completeTrainingChapter/);
  assert.match(gameStore, /replayAiProofState/);
  assert.match(gameStore, /trainingCampaign/);
  assert.match(gameRoute, /complete_training_chapter/);
  assert.match(gameStore, /TRAINING_MATCH_NO_SETTLEMENT/);
  assert.match(game, /改打 AI 演算/);
  assert.match(game, /apprenticeMatchPoolForFacts/);
  assert.match(game, /隐藏水平匹配 · 数值不公开/);
  assert.match(game, /显示段位不参与选人/);
  assert.match(game, /匹配质量/);
  assert.match(game, /rankedLadders/);
  assert.match(game, /Standard 标准/);
  assert.match(game, /Wild 狂野/);
  assert.match(game, /独立段位与隐藏水平/);
  assert.match(game, /赛季天梯奖励/);
  assert.match(game, /下月首次登录只结算一份/);
  assert.match(game, /任意段位赢得 5 场 Ranked/);
  assert.match(game, /跨赛季传说成就/);
  assert.match(game, /在 2026 圣甲虫之年的六个不同赛季达到传说/);
  assert.match(game, /天梯预备套牌/);
  assert.match(game, /activate_ladder_ready/);
  assert.match(game, /claim_ladder_ready_deck/);
  assert.match(game, /purchase_ladder_ready_deck/);
  assert.match(game, /claim_catch_up_pack/);
  assert.match(game, /previewCatchUpPack/);
  assert.match(game, /曾获得完成度 · 每系列 1–10 · 稀有\+ ≥20%/);
  assert.match(catchUpPack, /圣甲虫回归追赶包/);
  assert.match(game, /前 50 张传说保底/);
  assert.match(gameStore, /generateCatchUpPack/);
  assert.match(gameStore, /recordCatchUpCards\(state\.catchUpPack, grantedCardIds\)/);
  assert.match(game, /collectionWithTrialCards/);
  assert.match(game, /trialCardsAreActive/);
  assert.match(game, /试玩卡生效中/);
  assert.match(gameStore, /TRIAL_CARD_ACCESS_MS/);
  assert.match(game, /星港重启任务链/);
  assert.match(game, /claim_return_quest/);
  assert.match(game, /RETURN_QUEST_STAGES/);
  assert.match(gameStore, /export async function claimReturnQuest/);
  assert.match(game, /ladderReadyDecksForTrial/);
  assert.match(game, /激活时锁定当前环境版本/);
  assert.match(gameStore, /catalogVersionId/);
  assert.match(gameStore, /purchaseLadderReadyDeck/);
  assert.match(gameStore, /refreshLadderReadyReturnEligibility/);
  assert.match(gameStore, /updated_at AS lastActiveAt/);
  assert.match(game, /离开 90 天后可重新符合资格/);
  assert.match(game, /ladder-ready-\$\{catalog\.id\}-\$\{offer\.id\}/);
  assert.match(game, /领取后其余套牌每套/);
  assert.match(game, /AI 与在线对战均可使用/);
  assert.match(game, /预备 · 全部能量/);
  assert.match(game, /type: "prepare-card"/);
  assert.match(game, /伪装 · 敌方战场/);
  assert.match(game, /fragmentLabel/);
  assert.match(game, /card\.shatter/);
  assert.match(game, /herald: Boolean\(raw\.herald\)/);
  assert.match(game, /colossal: Boolean\(raw\.colossal\)/);
  assert.match(game, /heraldCount/);
  assert.match(game, /hero-core__herald/);
  assert.match(game, /cardRuleForHandSlot/);
  assert.match(game, /placement: pendingCardPlacement/);
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
  assert.match(styles, /\.hand-card__prepare/);
  assert.match(styles, /\.hand-card__disguise/);
  assert.match(styles, /\.hand-card__fragment/);
  assert.match(styles, /\.hand-card--reassembled/);
  assert.match(styles, /\.hero-core__herald/);
  assert.match(styles, /\.game-card__cost\.is-discounted/);
  assert.match(styles, /\.turn-clock/);
  assert.match(styles, /\.board-slot/);
  assert.match(styles, /battle-target-pulse/);
  assert.match(styles, /battle-target-impact/);
  assert.match(styles, /board-unit__target-preview/);
  assert.match(styles, /board-unit--frozen/);
  assert.match(styles, /board-unit__status/);
  assert.match(styles, /\.screen\.battle-room/);
  assert.match(styles, /@keyframes battle-room-enter/);
  assert.match(styles, /\.mini-reveal--back/);
  assert.match(styles, /@keyframes card-reveal-flip/);
  assert.match(styles, /\.battle-fx__card-reveal/);
  assert.match(styles, /\.battlefield-toys/);
  assert.match(styles, /\.battlefield--theme-mist/);
  assert.match(styles, /\.battlefield--theme-prism/);
  assert.match(styles, /\.battlefield--theme-tide/);
  assert.match(styles, /@keyframes board-resonance-enter/);
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
  assert.match(worker, /case "prepare-card"/);
  assert.match(worker, /safeEvent\.type === "card-prepared"/);
  assert.match(worker, /safeEvent\.type === "card-shattered"/);
  assert.match(worker, /safeEvent\.type === "card-reassembled"/);
  assert.match(worker, /raw\.placement === "friendly"/);
  assert.match(worker, /raw\.placement === "enemy"/);
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
  assert.match(rankedRewards, /ETERNAL_SCARAB_LEGEND_SEASON_TARGET = 6/);
  assert.match(rankedRewards, /legendSeasonCardBackUnlocked/);
  assert.match(cardBacks, /DEFAULT_CARD_BACK_ID = "ember-core"/);
  assert.match(cardBacks, /RANDOM_OWNED_CARD_BACK_ID = "random-owned"/);
  assert.match(cardBacks, /RANDOM_FAVORITE_CARD_BACK_ID = "random-favorites"/);
  assert.match(cardBacks, /normalizeFavoriteCardBackIds/);
  assert.match(cardBacks, /cardBackIsUnlocked/);
  assert.match(gameStore, /CARD_BACK_LOCKED/);
  assert.match(gameRoute, /deck\.cardBackId/);
  assert.match(gameRoute, /set_favorite_card_backs/);
  assert.match(game, /aria-label="选择牌组卡背"/);
  assert.match(game, /battle-deck-back--\$\{cardBackDefinition\(cardBackIds\[0\]\)\.kind\}/);
  assert.match(game, /card-back--\$\{cardBackDefinition\(cardBackIds\[1\]\)\.kind\}/);
  assert.match(worker, /pvpAccountAuthorizesLoadout/);
  assert.match(worker, /parsePvpReadyLoadout/);
  assert.match(worker, /resolveCardBackSelection/);
  assert.match(worker, /cardBackIds/);
  assert.match(styles, /\.deck-card-back-select/);
  assert.match(styles, /\.deck-card-back-favorites/);
  assert.match(styles, /\.card-back-preview--legend/);
  assert.match(styles, /\.card-back-preview--random/);
  assert.match(gameStore, /applyRankedMatchResult/);
  assert.match(gameStore, /rollRankedSeason/);
  assert.match(styles, /@keyframes battle-card-reveal/);
  assert.match(styles, /\.battlefield__fx-layer/);
  assert.match(styles, /battle-banner-enter 840ms/);
  assert.match(styles, /@keyframes battle-lunge-player/);
  assert.match(game, /data-card-signature/);
  assert.match(styles, /\.battle-fx--signature-dawn-charge/);
  assert.match(styles, /\.battle-fx--signature-prism-break/);
  assert.match(styles, /\.battle-fx--signature-orbit-discover/);
  assert.match(styles, /@keyframes battle-signature-dawn-streak/);
  assert.match(styles, /@keyframes battle-signature-prism-shard/);
  assert.match(styles, /@keyframes battle-signature-orbit/);
  assert.match(styles, /\.battle-fx__signature,[\s\S]*display: none/);
  assert.match(game, /draggable=\{!mulliganActive && !disabled\}/);
  assert.match(game, /event\.dataTransfer\.setData\("text\/plain", `card:/);
  assert.match(game, /event\.dataTransfer\.setData\("text\/plain", `attacker:/);
  assert.match(game, /onDropTarget=\{\(event\) => dropAttack/);
  assert.match(game, /event\.pointerType === "mouse"/);
  assert.match(game, /Math\.hypot\(/);
  assert.match(game, /distance < 12/);
  assert.match(game, /elementFromPoint\(event\.clientX, event\.clientY\)/);
  assert.match(game, /onDragAttack\(pointerDrag\.intent\.unitId/);
  assert.match(game, /setPointerDragPosition\(\{ x: event\.clientX, y: event\.clientY \}\)/);
  assert.match(game, /battle-drag-proxy--\$\{dragIntent\.kind\}/);
  assert.match(game, /speechSynthesis/);
  assert.match(game, /lastSpokenTrainingLineRef/);
  assert.match(game, /utterance\.lang = "zh-CN"/);
  assert.match(game, /trainingVoiceLine\.role === "mentor" \? 1\.06 : 0\.78/);
  assert.match(game, /speech\.cancel\(\)/);
  assert.match(game, /语音演绎/);
  assert.match(game, /data-battle-drop="friendly-board"/);
  assert.match(game, /dropKey="enemy-hero"/);
  assert.match(game, /onPointerCancel=\{[^\n]*cancelPointerDrag/);
  assert.match(styles, /\.board-row--drop-ready/);
  assert.match(styles, /\.board-unit--draggable/);
  assert.match(styles, /\.hero-core--drop-ready/);
  assert.match(styles, /\.hand-card--dragging/);
  assert.match(styles, /\.battle-drag-proxy/);
  assert.match(styles, /\.battle-training__voice/);
  assert.match(styles, /pointer-events: none/);
  assert.match(styles, /touch-action: none/);
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
