"use client";

import Image from "next/image";
import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
  type ReactNode,
} from "react";
import {
  APPRENTICE_MILESTONES,
  CARD_CATALOG,
  GENERATED_CARD_DEFINITIONS,
  CARD_SET_DEFINITIONS,
  AI_ARCHETYPES,
  DEFAULT_OPPONENT_DECK,
  DEFAULT_STARTER_DECK,
  drawPack,
  ETERNAL_SCARAB_CARD_BACK_NAME,
  ETERNAL_SCARAB_LEGEND_SEASON_TARGET,
  KEYWORD_DEFINITIONS,
  MINION_TYPE_DEFINITIONS,
  MINION_TYPE_ORDER,
  REWARD_TRACK,
  craftCost,
  disenchantValue,
  TRAIT_DEFINITIONS,
  TRAIT_ORDER,
  applyCommand,
  applyRankedMatchResult,
  apprenticeMatchPoolForFacts,
  apprenticeMilestoneComplete,
  apprenticeMilestoneProgress,
  apprenticeTrackComplete,
  battleEventsToEffects,
  cardAvailableInRankedFormat,
  chooseAiMulliganIndexes,
  completeDeckFromCollection,
  createMatch,
  createRankedRewardState,
  factionForDeck,
  findMissingDeckCards,
  formatDeckShareText,
  getHeroPower,
  hasMinionType,
  getLadderReadyDeck,
  getTraitStatuses,
  LADDER_DIAMOND_FIVE_PROGRESS,
  LADDER_READY_DECKS,
  LADDER_READY_TRIAL_DAYS,
  LADDER_READY_TRIAL_MS,
  LADDER_START_RATING,
  MAX_SAVED_DECKS,
  createRankedSnapshot,
  createRankedLadders,
  decodeDeckCode,
  deckRecipesForFaction,
  describeRankedRewardBundle,
  eternalScarabCardBackEarned,
  eternalScarabLegendProgress,
  encodeDeckCode,
  highestRankedFormat,
  ladderLabelForProgress,
  ladderProgressForRating,
  normalizeRankedRewardState,
  normalizeRankedLadders,
  removeSavedDeck,
  RANKED_FIRST_TIME_REWARD_LEVELS,
  rankedSeasonRewardForPeak,
  rollRankedSeason,
  rankedFormatLabel,
  totalRankedWins,
  ladderReadyTrialIsActive,
  planAiTurnReplay,
  previewDeckCode,
  shouldScheduleLocalAiTurn,
  suggestDeckReplacements,
  EXPANDED_FACTION_THEMES,
  validateDeck,
  validateDeckForFormat,
  type BattleEffectKind,
  type BattleCommand,
  type CardDefinition,
  type CardTargetRule,
  type DeckRecipe,
  type Faction,
  type HeroPowerEffect,
  type Keyword,
  type MinionType,
  type LadderReadyDeckId,
  type MatchQuality,
  type MissingDeckCard,
  type MatchState,
  type RankedSnapshot,
  type RankedFormat,
  type RankedLadders,
  type RankedRewardState,
  type SpellSchool,
  type Trait,
  type BattleVisualEffect,
  type AiArchetype,
  type ApprenticeMatchPool,
  type ApprenticeMilestoneId,
} from "@/lib/game";

type SectionKey = "overview" | "collection" | "deck" | "battle" | "operations";
type BattleTarget = { kind: "unit" | "hero"; id?: string };
type BattleHeroEffect = "damage" | "heal" | "shield";
type BattleUnitEffect =
  | "summon"
  | "attack"
  | "damage"
  | "heal"
  | "buff"
  | "shield";

function battleImpactText(effect?: BattleVisualEffect): string | undefined {
  if (!effect) return undefined;
  if (effect.kind === "damage") return effect.amount && effect.amount > 0 ? `−${effect.amount}` : undefined;
  if (effect.kind === "heal") return effect.amount && effect.amount > 0 ? `+${effect.amount}` : undefined;
  if (effect.kind === "shield") {
    return effect.label.includes("吸收") && effect.amount && effect.amount > 0
      ? `吸收 ${effect.amount}`
      : "护盾";
  }
  if (effect.kind === "buff") return "增幅";
  if (effect.kind === "transform") return "变形";
  if (effect.kind === "destroy") return "离线";
  return undefined;
}

type CatalogCard = {
  id: string;
  name: string;
  cost: number;
  type: "unit" | "spell" | "weapon" | "hero";
  faction: Faction;
  rarity: string;
  description: string;
  attack?: number;
  health?: number;
  durability?: number;
  spellDamage?: number;
  tradeable?: boolean;
  preparable?: boolean;
  disguised?: boolean;
  shatter?: boolean;
  herald?: boolean;
  colossal?: boolean;
  quickdraw?: boolean;
  heroCard?: boolean;
  target: CardTargetRule;
  keywords: Keyword[];
  traits: Trait[];
  minionTypes: MinionType[];
  school?: SpellSchool;
  set?: CardDefinition["set"];
};

type PlayerTask = {
  id: string;
  title: string;
  description: string;
  progress: number;
  target: number;
  rewardGold: number;
  rewardXp?: number;
  period?: "daily" | "weekly";
  claimed: boolean;
};

type SavedDeck = {
  id: string;
  name: string;
  cardIds: string[];
  format: RankedFormat;
  updatedAt: string;
};

type RecentMatch = {
  id: string;
  result: "win" | "loss" | "draw";
  mode: string;
  format?: "ranked" | "casual";
  rankedFormat?: RankedFormat;
  opponent: string;
  rewardGold: number;
  createdAt: string;
};

type PlayerSnapshot = {
  id: string;
  email: string;
  displayName: string;
  currencies: { gold: number; dust: number };
  packsAvailable: number;
  packPity?: { packsOpened: number; packsSinceLegendary: number };
  collection: Record<string, number>;
  decks: SavedDeck[];
  activeDeckId: string | null;
  tasks: PlayerTask[];
  taskCycle?: {
    dayKey: string;
    weekKey: string;
    dailyRerollsRemaining: number;
    packsBoughtToday: number;
    aiRewardsToday?: number;
    weeklyFreePackClaimed?: boolean;
  };
  progression?: { xp: number; level: number };
  rankedLadders: RankedLadders;
  ladder?: RankedSnapshot;
  rankedRewards?: RankedRewardState;
  friends?: Array<{ id: string; displayName: string; status: "pending" | "accepted"; direction: "incoming" | "outgoing" }>;
  chatMessages?: Array<{ id: string; senderId: string; recipientId: string; text: string; createdAt: string }>;
  blockedPlayerIds?: string[];
  rewardTrack?: { claimedLevels: number[] };
  apprenticeTrack?: { claimedMilestones: ApprenticeMilestoneId[] };
  ladderReady?: {
    activatedAt: string | null;
    expiresAt: string | null;
    claimedDeckId: LadderReadyDeckId | null;
  };
  recentMatches: RecentMatch[];
  stats: { wins: number; losses: number; matchesPlayed: number };
  updatedAt: string;
};

type GamePayload = {
  ok: true;
  identity?: { email: string; displayName: string; isDemo: boolean; isAnonymous?: boolean; canLinkDevice?: boolean };
  player: PlayerSnapshot;
  openedCards?: Array<{ cardId: string; count: number }>;
  claimedTaskId?: string;
  rewardGold?: number;
  costGold?: number;
  task?: PlayerTask;
  level?: number;
  reward?: { title: string; kind: "gold" | "pack" | "dust"; amount: number };
  apprenticeMilestoneId?: ApprenticeMilestoneId;
  displayName?: string;
  friendId?: string;
  message?: { id: string; senderId: string; recipientId: string; text: string; createdAt: string };
  targetId?: string;
  cardId?: string;
  amount?: number;
  kind?: "craft" | "disenchant";
  savedDeck?: SavedDeck;
  deletedDeckId?: string;
  claimedLadderReadyDeck?: SavedDeck;
  aiMatch?: {
    token: string;
    seed: number;
    startingPlayer: 0 | 1;
    rankedFormat: RankedFormat;
    playerDeck: string[];
    opponentArchetypeId: string;
    expiresAt: string;
  };
  localFallback?: boolean;
};

type AiMatchProofPayload = {
  ticketToken: string;
  seed: number;
  startingPlayer: 0 | 1;
  rankedFormat: RankedFormat;
  playerDeck: string[];
  opponentArchetypeId: string;
  commands: BattleCommand[];
};

type BattleUnit = {
  id: string;
  cardId: string;
  name: string;
  attack: number;
  health: number;
  maxHealth: number;
  stars: 1 | 2;
  canAttack: boolean;
  attacksMade: number;
  keywords: Keyword[];
  minionTypes: MinionType[];
  stealthActive: boolean;
  frozenTurns: number;
  summoningSick: boolean;
  rushOnly: boolean;
  furyStacks: number;
  spellDamage: number;
  temporaryAttackBonus: number;
  temporaryHealthBonus: number;
};

type BattleSide = {
  health: number;
  maxHealth: number;
  armor: number;
  heroId: string;
  heroName: string;
  heroPowerUsed: boolean;
  heroPowerName: string;
  heroPowerDescription: string;
  heroPowerCost: number;
  heroPowerTarget: CardTargetRule;
  heroPowerEffect: HeroPowerEffect;
  coinAvailable: boolean;
  heroHasAttacked: boolean;
  heroAttackBonus: number;
  secrets: Array<{ secretId: string; name: string; description: string }>;
  overload: number;
  overloadLocked: number;
  spellSchoolsPlayedThisTurn: SpellSchool[];
  spellSchoolsPlayedLastTurn: SpellSchool[];
  deathHistory: Array<{
    entityId: string;
    cardId: string;
    name: string;
    diedTurn: number;
    deathOrder: number;
    minionTypes: MinionType[];
  }>;
  discardHistory: Array<{
    discardId: string;
    cardId: string;
    name: string;
    discardedTurn: number;
    discardOrder: number;
    fragment?: "left" | "right";
  }>;
  weapon: {
    cardId: string;
    name: string;
    attack: number;
    durability: number;
    maxDurability: number;
  } | null;
  mana: number;
  maxMana: number;
  heraldCount: number;
  deckCount: number;
  hand: Array<{
    instanceId: string;
    cardId: string;
    handIndex: number;
    costReduction: number;
    fragment?: "left" | "right";
    fragmentGroupId?: string;
    enteredTurn: number;
  }>;
  board: BattleUnit[];
};

type BattleReport = {
  reason: "hero-defeated" | "fatigue" | "concede" | "draw" | null;
  cardsPlayed: [number, number];
  attacks: [number, number];
  damage: [number, number];
  healing: [number, number];
  unitsDied: [number, number];
  cardsDrawn: [number, number];
};

type BattleView = {
  status: "mulligan" | "discover" | "choose-one" | "playing" | "finished";
  mulliganDone: boolean;
  winner: "player" | "ai" | null;
  currentPlayer: "player" | "ai";
  turn: number;
  player: BattleSide;
  ai: BattleSide;
  log: string[];
  discover: {
    sourceCardId: string;
    choices: Array<{ cardId: string; currentCost?: number; fragment?: "left" | "right" }>;
  } | null;
  chooseOne: { player: "player" | "ai"; sourceCardId: string; options: Array<{ label: string }>; remainingChoices: number; sourceKind: "spell" | "hero-card" } | null;
  report: BattleReport;
};

type PvpRole = "host" | "guest";
type PvpFormat = "ranked" | "casual";
type PvpStatus = "offline" | "connecting" | "connected" | "queue" | "room" | "ready" | "playing" | "error";

type PvpState = {
  status: PvpStatus;
  url: string;
  playerId: string | null;
  roomCode: string | null;
  role: PvpRole | null;
  format: PvpFormat;
  rankedFormat: RankedFormat;
  matchPool: ApprenticeMatchPool | null;
  matchQuality: MatchQuality | null;
  peerName: string | null;
  localReady: boolean;
  remoteReady: boolean;
  remoteReadyDeck: string[] | null;
  message: string;
};

type PvpIncoming =
  | { id: number; type: "match-start"; payload: { seed: number; startingPlayer?: 0 | 1; deck?: string[]; decks?: [string[], string[]]; matchToken?: string; format?: PvpFormat; rankedFormat?: RankedFormat } }
  | { id: number; type: "match-sync"; payload: { state: MatchState; matchToken?: string; format?: PvpFormat; rankedFormat?: RankedFormat } }
  | { id: number; type: "command"; command: BattleCommand; state?: MatchState; matchToken?: string }
  | { id: number; type: "room-reset" }
  | { id: number; type: "rejected"; message: string; resync?: boolean };

function swapPlayerReferences(message: string): string {
  return message.replace(/玩家 ([01])/g, (_match, player: string) =>
    `玩家 ${player === "0" ? "1" : "0"}`,
  );
}

function formatBattleLogMessage(message: string): string {
  return message
    .replace(/玩家 0 的英雄/g, "我方核心")
    .replace(/玩家 1 的英雄/g, "敌方核心")
    .replace(/玩家 0 的核心/g, "我方核心")
    .replace(/玩家 1 的核心/g, "敌方核心")
    .replace(/玩家 0/g, "我方")
    .replace(/玩家 1/g, "敌方")
    .replace(/(?<=[\u4e00-\u9fff」])\s+(?=[\u4e00-\u9fff「])/g, "");
}

function orientPvpMatchForLocal(state: MatchState, role: PvpRole): MatchState {
  if (role === "host") return state;
  const swap = (player: 0 | 1): 0 | 1 => (player === 0 ? 1 : 0);
  const players = state.players.map((player, index) => ({
    ...player,
    id: swap(index as 0 | 1),
    hero: { ...player.hero },
    weapon: player.weapon ? { ...player.weapon } : null,
    secrets: (player.secrets ?? []).map((secret) => ({ ...secret, effect: { ...secret.effect } })),
    deck: [...player.deck],
    deckCostOverrides: [...(player.deckCostOverrides ?? player.deck.map(() => null))],
    hand: [...player.hand],
    board: player.board.map((unit) => ({
      ...unit,
      owner: swap(unit.owner),
      minionTypes: [...(unit.minionTypes ?? [])],
    })),
  })) as [MatchState["players"][0], MatchState["players"][1]];
  return {
    ...state,
    activePlayer: swap(state.activePlayer),
    mulliganDone: [state.mulliganDone?.[1] ?? true, state.mulliganDone?.[0] ?? true],
    discover: state.discover
      ? {
          ...state.discover,
          player: swap(state.discover.player),
          choices: [...state.discover.choices],
          choiceSnapshots: state.discover.choiceSnapshots?.map((choice) => ({ ...choice })),
        }
      : null,
    chooseOne: state.chooseOne
      ? {
          ...state.chooseOne,
          player: swap(state.chooseOne.player),
          options: state.chooseOne.options.map((option) => ({ ...option, effects: [...option.effects] })),
          chosenLabels: [...(state.chooseOne.chosenLabels ?? [])],
          target: state.chooseOne.target
            ? state.chooseOne.target.kind === "hero"
              ? { ...state.chooseOne.target, player: swap(state.chooseOne.target.player) }
              : { ...state.chooseOne.target }
            : undefined,
        }
      : null,
    players: [players[1], players[0]],
    winner: state.winner === null ? null : swap(state.winner),
    result: state.result
      ? { ...state.result, winner: state.result.winner === null ? null : swap(state.result.winner) }
      : null,
    events: state.events.map((event) => ({
      ...event,
      message: swapPlayerReferences(event.message),
      player: event.player === undefined ? undefined : swap(event.player),
      data: event.data ? (() => {
        const target = event.data?.target as { kind?: string; player?: number } | undefined;
        return {
          ...event.data,
          ...(typeof event.data.winner === "number" ? { winner: swap(event.data.winner as 0 | 1) } : {}),
          ...(event.data.attackerPlayer === 0 || event.data.attackerPlayer === 1
            ? { attackerPlayer: swap(event.data.attackerPlayer) }
            : {}),
          ...(event.data.triggeringPlayer === 0 || event.data.triggeringPlayer === 1
            ? { triggeringPlayer: swap(event.data.triggeringPlayer) }
            : {}),
          ...(event.data.sourcePlayer === 0 || event.data.sourcePlayer === 1
            ? { sourcePlayer: swap(event.data.sourcePlayer) }
            : {}),
          ...(event.data.targetPlayer === 0 || event.data.targetPlayer === 1
            ? { targetPlayer: swap(event.data.targetPlayer) }
            : {}),
          ...(target?.kind === "hero" && (target.player === 0 || target.player === 1)
            ? { target: { ...target, player: swap(target.player) } }
            : {}),
        };
      })() : undefined,
    })),
  };
}

function getDefaultPvpUrl(): string {
  if (typeof window === "undefined") return "ws://127.0.0.1:8787";
  const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
  const isLocal = window.location.hostname === "localhost" || window.location.hostname === "127.0.0.1";
  return isLocal ? `${protocol}//127.0.0.1:8787` : `${protocol}//${window.location.host}/api/pvp`;
}

type ValidationView = {
  valid: boolean;
  errors: string[];
};

const NAV_ITEMS: Array<{ id: SectionKey; label: string; eyebrow: string; icon: IconName }> = [
  { id: "overview", label: "战情总览", eyebrow: "COMMAND", icon: "radar" },
  { id: "collection", label: "卡牌收藏", eyebrow: "ARCHIVE", icon: "cards" },
  { id: "deck", label: "卡组工坊", eyebrow: "ARSENAL", icon: "layers" },
  { id: "battle", label: "战术对战", eyebrow: "BATTLE", icon: "swords" },
  { id: "operations", label: "运营台", eyebrow: "OPS", icon: "chart" },
];

const CARD_USAGE = [
  { name: "棱镜守卫", faction: "星穹", usage: 68, winRate: 53.8, trend: "+3.2%" },
  { name: "焰脊先锋", faction: "烬火", usage: 61, winRate: 52.6, trend: "+1.7%" },
  { name: "晨辉斥候", faction: "曜光", usage: 58, winRate: 51.4, trend: "+0.8%" },
  { name: "雾汐潜行者", faction: "幽潮", usage: 55, winRate: 50.7, trend: "+0.3%" },
  { name: "世界根母", faction: "苍林", usage: 49, winRate: 49.8, trend: "−0.2%" },
  { name: "天铸雷王", faction: "雷铸", usage: 46, winRate: 49.1, trend: "−0.9%" },
  { name: "远途商队卫", faction: "中立", usage: 43, winRate: 48.7, trend: "−1.1%" },
];

const FACTION_BALANCE_COLORS = ["#e9cc78", "#68a9d8", "#b6a17e", "#e46d3f", "#a692d1", "#79b980", "#65cdda", "#79dcff", "#e2b45d", "#e24d62", "#67e8d4", "#7359a8", "#8bd7ec", "#e08e55", "#dcecff", "#f0a9e6", "#f36b52", "#e5c779", "#7bbf76", "#ffe3a2"];

const FACTION_BALANCE: Array<{ faction: Faction; winRate: number; color: string }> = EXPANDED_FACTION_THEMES.map((theme, index) => ({
  faction: theme.faction,
  winRate: Number((48.7 + ((index * 17) % 34) / 10).toFixed(1)),
  color: FACTION_BALANCE_COLORS[index] ?? "#86aaa3",
}));

const TYPE_LABEL: Record<string, string> = {
  unit: "单位",
  minion: "单位",
  spell: "战术",
  weapon: "武器",
  hero: "英雄",
};

const SPELL_SCHOOL_LABEL: Record<SpellSchool, string> = {
  radiance: "曜术",
  tide: "潮术",
  construct: "构术",
  ember: "烬术",
  astral: "星术",
  verdant: "森术",
  storm: "雷术",
};

const SPELL_SCHOOL_ORDER = Object.keys(SPELL_SCHOOL_LABEL) as SpellSchool[];

const FACTION_DEFINITIONS: Record<Faction, { sigil: string; doctrine: string; tone: string }> = Object.freeze(
  Object.fromEntries(EXPANDED_FACTION_THEMES.map((theme) => [theme.faction, { sigil: theme.sigil, doctrine: theme.doctrine, tone: theme.tone }])) as Record<Faction, { sigil: string; doctrine: string; tone: string }>,
);

const FACTION_ORDER = Object.keys(FACTION_DEFINITIONS) as Faction[];

type IconName =
  | "radar"
  | "cards"
  | "layers"
  | "swords"
  | "chart"
  | "coin"
  | "dust"
  | "pack"
  | "search"
  | "shield"
  | "spark"
  | "check"
  | "arrow"
  | "plus"
  | "minus"
  | "clock"
  | "user"
  | "bot"
  | "menu"
  | "trash"
  | "close";

const rawCatalog = CARD_CATALOG as readonly CardDefinition[] as unknown as ReadonlyArray<
  Record<string, unknown>
>;

function asString(value: unknown, fallback = "") {
  return typeof value === "string" ? value : fallback;
}

function asNumber(value: unknown, fallback = 0) {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function cardFromRaw(raw: Record<string, unknown>): CatalogCard {
  const rawType = asString(raw.type, "unit").toLowerCase();
  const rawRarity = asString(raw.rarity, "普通").toLowerCase();
  const rarity =
    rawRarity === "传说" || rawRarity === "legendary"
      ? "legendary"
      : rawRarity === "史诗" || rawRarity === "epic"
        ? "epic"
        : rawRarity === "稀有" || rawRarity === "rare"
          ? "rare"
          : "common";
  return {
    id: asString(raw.id ?? raw.cardId),
    name: asString(raw.name, "未命名协议"),
    cost: asNumber(raw.cost ?? raw.manaCost),
    type: rawType === "weapon" ? "weapon" : rawType === "spell" ? "spell" : rawType === "hero" ? "hero" : "unit",
    faction: asString(raw.faction ?? raw.camp, "中立") as Faction,
    rarity,
    description: asString(raw.description ?? raw.text, "战术资料尚未解密。"),
    attack:
      typeof (raw.attack ?? raw.power) === "number"
        ? asNumber(raw.attack ?? raw.power)
        : undefined,
    health:
      typeof (raw.health ?? raw.toughness) === "number"
        ? asNumber(raw.health ?? raw.toughness)
        : undefined,
    durability:
      typeof raw.durability === "number"
        ? asNumber(raw.durability)
        : undefined,
    spellDamage:
      typeof raw.spellDamage === "number"
        ? asNumber(raw.spellDamage)
        : undefined,
    tradeable: raw.tradeable === true,
    preparable: raw.preparable === true,
    disguised: raw.disguised === true,
    shatter: Boolean(raw.shatter),
    herald: Boolean(raw.herald),
    colossal: Boolean(raw.colossal),
    quickdraw: Array.isArray(raw.quickdraw) && raw.quickdraw.length > 0,
    heroCard: Boolean(raw.heroCard),
    target: asString(raw.target, "none") as CardTargetRule,
    keywords: Array.isArray(raw.keywords)
      ? (raw.keywords.map(String) as Keyword[])
      : [],
    traits: Array.isArray(raw.traits)
      ? (raw.traits.map(String) as Trait[])
      : [],
    minionTypes: Array.isArray(raw.minionTypes)
      ? (raw.minionTypes.map(String) as MinionType[])
      : [],
    school:
      typeof raw.school === "string"
        ? (raw.school as SpellSchool)
        : undefined,
    set: typeof raw.set === "string" ? raw.set as CardDefinition["set"] : undefined,
  };
}

const CATALOG: CatalogCard[] = rawCatalog.map(cardFromRaw);
const GENERATED_CATALOG: CatalogCard[] = (GENERATED_CARD_DEFINITIONS as readonly CardDefinition[] as unknown as ReadonlyArray<Record<string, unknown>>).map(cardFromRaw);
const CARD_BY_ID = new Map([...CATALOG, ...GENERATED_CATALOG].map((card) => [card.id, card]));
const CARD_RULE_BY_ID = new Map([...CARD_CATALOG, ...GENERATED_CARD_DEFINITIONS].map((card) => [card.id, card]));

function cardRuleForHandSlot(
  handCard: BattleSide["hand"][number],
): CardDefinition | undefined {
  const rule = CARD_RULE_BY_ID.get(handCard.cardId);
  if (!rule || !handCard.fragment || !rule.shatter) return rule;
  return {
    ...rule,
    target: rule.shatter[`${handCard.fragment}Target`] ?? rule.target,
    effect: [...rule.shatter[handCard.fragment]],
  };
}

function getStarterDeck(): string[] {
  const raw = DEFAULT_STARTER_DECK as unknown;
  if (Array.isArray(raw)) {
    return raw.map((item) =>
      typeof item === "string"
        ? item
        : asString((item as Record<string, unknown>)?.id ?? (item as Record<string, unknown>)?.cardId),
    );
  }
  if (raw && typeof raw === "object") {
    const ids = (raw as Record<string, unknown>).cardIds;
    if (Array.isArray(ids)) return ids.map((item) => String(item));
  }
  return CATALOG.slice(0, 15).flatMap((card) => [card.id, card.id]).slice(0, 30);
}

const STARTER_IDS = getStarterDeck();

function formatTime(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "刚刚";
  return new Intl.DateTimeFormat("zh-CN", {
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  }).format(date);
}

function formatUtcResetCountdown(period: "day" | "week", now: number): string {
  if (!now) return "计算中…";
  const next = new Date(now);
  if (period === "day") {
    next.setUTCHours(24, 0, 0, 0);
  } else {
    const day = next.getUTCDay() || 7;
    next.setUTCDate(next.getUTCDate() + (8 - day));
    next.setUTCHours(0, 0, 0, 0);
  }
  const seconds = Math.max(0, Math.floor((next.getTime() - now) / 1000));
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const remainingSeconds = seconds % 60;
  return `${hours}时 ${minutes.toString().padStart(2, "0")}分 ${remainingSeconds.toString().padStart(2, "0")}秒`;
}

function formatLadderReadyCountdown(expiresAt: string | null | undefined, now: number): string {
  if (!expiresAt || !now) return "尚未激活";
  const seconds = Math.max(0, Math.floor((Date.parse(expiresAt) - now) / 1000));
  if (seconds <= 0) return "试玩已到期";
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  return `${days}天 ${hours.toString().padStart(2, "0")}时 ${minutes.toString().padStart(2, "0")}分`;
}

function makeId(prefix: string) {
  if (typeof crypto !== "undefined" && "randomUUID" in crypto) {
    return `${prefix}-${crypto.randomUUID()}`;
  }
  return `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

type ProfileSource = "cloud" | "device" | "demo" | "cached";

const LOCAL_PROFILE_KEY_PREFIX = "astra-protocol:player:v2:";

function localProfileKey(email: string): string {
  return `${LOCAL_PROFILE_KEY_PREFIX}${encodeURIComponent(email.trim().toLowerCase())}`;
}

function isPlayerSnapshot(value: unknown): value is PlayerSnapshot {
  if (!value || typeof value !== "object") return false;
  const candidate = value as Partial<PlayerSnapshot>;
  return (
    typeof candidate.id === "string" &&
    typeof candidate.email === "string" &&
    typeof candidate.displayName === "string" &&
    !!candidate.currencies &&
    typeof candidate.currencies.gold === "number" &&
    typeof candidate.currencies.dust === "number" &&
    typeof candidate.packsAvailable === "number" &&
    !!candidate.collection &&
    typeof candidate.collection === "object" &&
    Array.isArray(candidate.decks) &&
    Array.isArray(candidate.tasks) &&
    Array.isArray(candidate.recentMatches) &&
    !!candidate.stats &&
    typeof candidate.stats.matchesPlayed === "number" &&
    typeof candidate.updatedAt === "string"
  );
}

function readLocalPlayer(email: string): PlayerSnapshot | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = window.localStorage.getItem(localProfileKey(email));
    if (!raw) return null;
    const parsed: unknown = JSON.parse(raw);
    if (!isPlayerSnapshot(parsed)) return null;
    const now = new Date().toISOString();
    const seasonKey = now.slice(0, 7);
    const rankedLadders = normalizeRankedLadders(parsed.rankedLadders, parsed.ladder, seasonKey);
    const rolled = rollRankedSeason({
      ladders: rankedLadders,
      rankedRewards: normalizeRankedRewardState(parsed.rankedRewards),
      collection: parsed.collection,
      packsAvailable: parsed.packsAvailable,
    }, CARD_CATALOG, seasonKey, now);
    const migrated = {
      ...parsed,
      decks: parsed.decks.map((deck) => ({
        ...deck,
        format: deck.format === "wild" || validateDeckForFormat(deck.cardIds, "standard").valid ? deck.format ?? "standard" : "wild",
      })),
      rankedLadders: rolled.ladders,
      ladder: undefined,
      rankedRewards: rolled.rankedRewards,
      collection: rolled.collection,
      packsAvailable: rolled.packsAvailable,
    };
    persistLocalPlayer(migrated);
    return migrated;
  } catch {
    return null;
  }
}

function persistLocalPlayer(player: PlayerSnapshot): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(localProfileKey(player.email), JSON.stringify(player));
  } catch {
    // Private browsing and quota errors must not break the game surface.
  }
}

function makeDemoPlayer(identity?: {
  displayName: string;
  email: string;
}): PlayerSnapshot {
  const seasonKey = new Date().toISOString().slice(0, 7);
  const collection = Object.fromEntries(CATALOG.map((card) => [card.id, 2]));
  const deck: SavedDeck = {
    id: "demo-starter",
    name: "星火远征队",
    cardIds: [...STARTER_IDS],
    format: "standard",
    updatedAt: new Date().toISOString(),
  };
  return {
    id: "local-commander",
    email: identity?.email ?? "commander@aether.local",
    displayName: identity?.displayName ?? "旅者 071",
    currencies: { gold: 1280, dust: 360 },
    packsAvailable: 1,
    packPity: { packsOpened: 0, packsSinceLegendary: 0 },
    collection,
    decks: [deck],
    activeDeckId: deck.id,
    tasks: [
      {
        id: "daily-battle",
        title: "战术热身",
        description: "完成 1 场对战",
        progress: 0,
        target: 1,
        rewardGold: 120,
        rewardXp: 150,
        period: "daily",
        claimed: false,
      },
      {
        id: "daily-play",
        title: "能量调度",
        description: "在对战中使用 8 张卡牌",
        progress: 5,
        target: 8,
        rewardGold: 80,
        rewardXp: 150,
        period: "daily",
        claimed: false,
      },
      {
        id: "collection",
        title: "档案扩容",
        description: "收藏 1000 张不同卡牌",
        progress: Math.min(CATALOG.length, 1000),
        target: 1000,
        rewardGold: 150,
        rewardXp: 150,
        period: "daily",
        claimed: false,
      },
      {
        id: "weekly-win-five",
        title: "周常·战术胜利",
        description: "赢得 5 场对战",
        progress: 2,
        target: 5,
        rewardGold: 250,
        rewardXp: 500,
        period: "weekly",
        claimed: false,
      },
    ],
    taskCycle: { dayKey: new Date().toISOString().slice(0, 10), weekKey: "demo", dailyRerollsRemaining: 1, packsBoughtToday: 0, aiRewardsToday: 0, weeklyFreePackClaimed: false },
    progression: { xp: 850, level: 1 },
    rewardTrack: { claimedLevels: [] },
    apprenticeTrack: { claimedMilestones: [] },
    ladderReady: { activatedAt: null, expiresAt: null, claimedDeckId: null },
    rankedLadders: {
      ...createRankedLadders(seasonKey),
      standard: { ...createRankedSnapshot(seasonKey), wins: 7, losses: 3 },
    },
    rankedRewards: { ...createRankedRewardState(), earnedCardBackSeasons: [seasonKey] },
    recentMatches: [
      {
        id: "demo-match-1",
        result: "win",
        mode: "ai",
        opponent: "镜像演算体 K-7",
        rewardGold: 60,
        createdAt: new Date(Date.now() - 42 * 60 * 1000).toISOString(),
      },
      {
        id: "demo-match-2",
        result: "loss",
        mode: "ai",
        opponent: "边境巡弋者",
        rewardGold: 20,
        createdAt: new Date(Date.now() - 5 * 60 * 60 * 1000).toISOString(),
      },
    ],
    stats: { wins: 7, losses: 3, matchesPlayed: 10 },
    updatedAt: new Date().toISOString(),
  };
}

function applyLocalAction(
  current: PlayerSnapshot,
  action: string,
  body: Record<string, unknown>,
): GamePayload {
  const now = new Date().toISOString();
  if (action === "reset_demo") {
    const player = makeDemoPlayer({
      displayName: current.displayName,
      email: current.email,
    });
    return { ok: true, player, localFallback: true };
  }
  if (action === "create_ai_match") {
    const ladderReadyDeckId = asString(body.ladderReadyDeckId);
    const offer = ladderReadyDeckId ? getLadderReadyDeck(ladderReadyDeckId) : undefined;
    let playerDeck: readonly string[];
    let rankedFormat: RankedFormat;
    if (offer) {
      const trial = current.ladderReady;
      if (!trial?.activatedAt || !trial.expiresAt) throw new Error("请先激活七日试玩。");
      if (trial.claimedDeckId) throw new Error("永久领取后，其他套牌试玩已经结束。");
      if (!ladderReadyTrialIsActive(trial)) throw new Error("七日试玩已经结束，请选择一套永久领取。");
      playerDeck = offer.deck;
      rankedFormat = "standard";
    } else {
      const deckId = asString(body.deckId);
      const deck = current.decks.find((candidate) => candidate.id === deckId);
      if (!deck) throw new Error("AI 对局必须使用已保存的卡组或有效试玩套牌。");
      playerDeck = deck.cardIds;
      rankedFormat = deck.format === "wild" ? "wild" : "standard";
    }
    const validation = validateDeckForFormat(playerDeck, rankedFormat);
    if (!validation.valid) throw new Error(validation.errors[0]?.message ?? "卡组不符合组牌规则。");
    const archetypeId = asString(body.opponentArchetypeId);
    if (!AI_ARCHETYPES.some((candidate) => candidate.id === archetypeId)) {
      throw new Error("AI 对手原型不存在。");
    }
    const randomness = crypto.getRandomValues(new Uint32Array(2));
    return {
      ok: true,
      player: current,
      aiMatch: {
        token: `local-${crypto.randomUUID()}`,
        seed: (randomness[0] ?? 0) & 0x7fffffff,
        startingPlayer: ((randomness[1] ?? 0) & 1) as 0 | 1,
        rankedFormat,
        playerDeck: [...playerDeck],
        opponentArchetypeId: archetypeId,
        expiresAt: new Date(Date.now() + 2 * 60 * 60 * 1_000).toISOString(),
      },
      localFallback: true,
    };
  }
  if (action === "activate_ladder_ready") {
    const trial = current.ladderReady ?? { activatedAt: null, expiresAt: null, claimedDeckId: null };
    if (trial.claimedDeckId) throw new Error("本档案已经领取过一套天梯预备套牌。");
    if (trial.activatedAt) throw new Error("七日试玩已经激活。");
    const activatedAt = new Date();
    return {
      ok: true,
      player: {
        ...current,
        ladderReady: {
          activatedAt: activatedAt.toISOString(),
          expiresAt: new Date(activatedAt.getTime() + LADDER_READY_TRIAL_MS).toISOString(),
          claimedDeckId: null,
        },
        updatedAt: now,
      },
      localFallback: true,
    };
  }
  if (action === "claim_ladder_ready_deck") {
    const offer = getLadderReadyDeck(asString(body.deckId));
    if (!offer) throw new Error("天梯预备套牌不存在。");
    const trial = current.ladderReady;
    if (!trial?.activatedAt) throw new Error("请先激活七日试玩。");
    if (trial.claimedDeckId) throw new Error("本档案已经领取过一套天梯预备套牌。");
    const claimedLadderReadyDeck: SavedDeck = {
      id: `ladder-ready-${offer.id}`,
      name: `${offer.faction} · ${offer.name}`,
      cardIds: [...offer.deck],
      format: "standard",
      updatedAt: now,
    };
    if (current.decks.length >= MAX_SAVED_DECKS && !current.decks.some((deck) => deck.id === claimedLadderReadyDeck.id)) {
      throw new Error(`已保存卡组已达 ${MAX_SAVED_DECKS} 套上限，请先整理卡组。`);
    }
    const required = new Map<string, number>();
    offer.deck.forEach((cardId) => required.set(cardId, (required.get(cardId) ?? 0) + 1));
    const collection = { ...current.collection };
    required.forEach((count, cardId) => { collection[cardId] = Math.max(collection[cardId] ?? 0, count); });
    const player = {
      ...current,
      collection,
      decks: [...current.decks.filter((deck) => deck.id !== claimedLadderReadyDeck.id), claimedLadderReadyDeck],
      activeDeckId: claimedLadderReadyDeck.id,
      ladderReady: { ...trial, claimedDeckId: offer.id },
      updatedAt: now,
    };
    return { ok: true, player, claimedLadderReadyDeck, localFallback: true };
  }
  if (action === "update_profile") {
    const displayName = asString(body.displayName, current.displayName).trim().replace(/\s+/g, " ");
    if (displayName.length < 1 || displayName.length > 24) throw new Error("公开昵称必须为 1–24 个字符。");
    const player = { ...current, displayName, updatedAt: now };
    return { ok: true, player, displayName, localFallback: true };
  }
  if (action === "send_friend_request" || action === "accept_friend_request") {
    const friendId = asString(body.friendId).trim();
    if (!friendId || friendId === current.id) throw new Error("好友 UID 无效。");
    if ((current.blockedPlayerIds ?? []).includes(friendId)) throw new Error("该玩家已被屏蔽，无法建立好友关系。");
    const friends = [...(current.friends ?? [])];
    const existing = friends.find((friend) => friend.id === friendId);
    if (action === "send_friend_request" && existing?.status === "accepted") throw new Error("该玩家已经在好友列表中。");
    if (action === "accept_friend_request" && (!existing || existing.status !== "pending")) throw new Error("没有可接受的入站好友请求。");
    const nextFriends = existing
      ? friends.map((friend) => friend.id === friendId ? { ...friend, status: "accepted" as const, direction: "outgoing" as const } : friend)
      : [...friends, { id: friendId, displayName: "等待确认的指挥官", status: "pending" as const, direction: "outgoing" as const }];
    return { ok: true, player: { ...current, friends: nextFriends, updatedAt: now }, friendId, localFallback: true };
  }
  if (action === "send_chat") {
    const friendId = asString(body.friendId).trim();
    const text = asString(body.text).trim().replace(/\s+/g, " ");
    const friend = (current.friends ?? []).find((item) => item.id === friendId && item.status === "accepted");
    if (!friend) throw new Error("只有已接受的好友才能聊天。");
    if ((current.blockedPlayerIds ?? []).includes(friendId)) throw new Error("该玩家已被屏蔽。");
    if (!text || text.length > 240) throw new Error("聊天消息必须为 1–240 个字符。");
    const message = { id: makeId("chat"), senderId: current.id, recipientId: friendId, text, createdAt: now };
    return { ok: true, player: { ...current, chatMessages: [message, ...(current.chatMessages ?? [])].slice(0, 100), updatedAt: now }, message, localFallback: true };
  }
  if (action === "block_player" || action === "unblock_player") {
    const targetId = asString(body.targetId).trim();
    const blocked = new Set(current.blockedPlayerIds ?? []);
    if (action === "block_player") {
      if (blocked.has(targetId)) throw new Error("该玩家已经被屏蔽。");
      blocked.add(targetId);
    } else {
      if (!blocked.has(targetId)) throw new Error("该玩家当前没有被屏蔽。");
      blocked.delete(targetId);
    }
    return { ok: true, player: { ...current, blockedPlayerIds: [...blocked], updatedAt: now }, targetId, localFallback: true };
  }
  if (action === "report_player") {
    const targetId = asString(body.targetId).trim();
    const reason = asString(body.reason).trim();
    if (!targetId || reason.length < 2) throw new Error("举报信息不完整。");
    return { ok: true, player: { ...current, updatedAt: now }, targetId, localFallback: true };
  }
  if (action === "open_pack") {
    if (current.packsAvailable < 1) throw new Error("没有可开启的卡包。");
    const seed = current.stats.matchesPlayed + current.packsAvailable + current.currencies.gold;
    const packPity = current.packPity ?? { packsOpened: 0, packsSinceLegendary: 0 };
    const opened = drawPack(
      current.collection,
      [seed, seed + 7, seed + 14, seed + 21, seed + 28],
      { guaranteeLegendary: packPity.packsSinceLegendary >= 39 },
    );
    const openedMap = new Map(opened.map((entry) => [entry.cardId, entry.count]));
    const openedLegendary = opened.some((entry) => CARD_BY_ID.get(entry.cardId)?.rarity === "legendary");
    const collection = { ...current.collection };
    openedMap.forEach((count, id) => {
      collection[id] = (collection[id] ?? 0) + count;
    });
    const player = {
      ...current,
      packsAvailable: Math.max(0, current.packsAvailable - 1),
      packPity: {
        packsOpened: packPity.packsOpened + 1,
        packsSinceLegendary: openedLegendary ? 0 : packPity.packsSinceLegendary + 1,
      },
      collection,
      tasks: current.tasks.map((task) =>
        task.id.includes("pack") || task.description.includes("卡包")
          ? { ...task, progress: Math.min(task.target, task.progress + 1) }
          : task,
      ),
      updatedAt: now,
    };
    return {
      ok: true,
      player,
      openedCards: Array.from(openedMap, ([cardId, count]) => ({ cardId, count })),
      localFallback: true,
    };
  }

  if (action === "claim_weekly_pack") {
    const cycle = current.taskCycle ?? { dayKey: now.slice(0, 10), weekKey: "demo", dailyRerollsRemaining: 1, packsBoughtToday: 0, weeklyFreePackClaimed: false };
    if (cycle.weeklyFreePackClaimed) throw new Error("本周免费卡包已经领取。");
    const player = { ...current, packsAvailable: current.packsAvailable + 1, taskCycle: { ...cycle, weeklyFreePackClaimed: true }, updatedAt: now };
    return { ok: true, player, localFallback: true };
  }

  if (action === "buy_pack") {
    const cycle = current.taskCycle ?? { dayKey: now.slice(0, 10), weekKey: "demo", dailyRerollsRemaining: 1, packsBoughtToday: 0 };
    if (current.currencies.gold < 100) throw new Error("金币不足，无法购买卡包。");
    if (cycle.packsBoughtToday >= 10) throw new Error("今日卡包购买次数已达上限。");
    const player = {
      ...current,
      currencies: { ...current.currencies, gold: current.currencies.gold - 100 },
      packsAvailable: current.packsAvailable + 1,
      taskCycle: { ...cycle, packsBoughtToday: cycle.packsBoughtToday + 1 },
      updatedAt: now,
    };
    return { ok: true, player, costGold: 100, localFallback: true };
  }

  if (action === "reroll_task") {
    const taskId = asString(body.taskId);
    const cycle = current.taskCycle ?? { dayKey: now.slice(0, 10), weekKey: "demo", dailyRerollsRemaining: 1, packsBoughtToday: 0 };
    const taskIndex = current.tasks.findIndex((task) => task.id === taskId);
    const task = taskIndex >= 0 ? current.tasks[taskIndex] : null;
    if (!task) throw new Error("任务不存在。");
    if (task.period === "weekly" || task.claimed || task.progress > 0 || cycle.dailyRerollsRemaining < 1) {
      throw new Error("该任务当前不能重随。");
    }
    const replacements: PlayerTask[] = [
      { id: "play-three-matches", title: "持续交锋", description: "完成 3 场对战", progress: 0, target: 3, rewardGold: 100, rewardXp: 150, period: "daily", claimed: false },
      { id: "win-two-matches", title: "连胜协议", description: "赢得 2 场对战", progress: 0, target: 2, rewardGold: 150, rewardXp: 150, period: "daily", claimed: false },
      { id: "open-two-packs", title: "档案解密", description: "开启 2 个卡包", progress: 0, target: 2, rewardGold: 100, rewardXp: 150, period: "daily", claimed: false },
    ];
    const replacement = replacements[(current.stats.matchesPlayed + current.tasks.length) % replacements.length];
    const tasks = [...current.tasks];
    tasks[taskIndex] = replacement.id === task.id ? replacements[(replacements.indexOf(replacement) + 1) % replacements.length] : replacement;
    const player = { ...current, tasks, taskCycle: { ...cycle, dailyRerollsRemaining: cycle.dailyRerollsRemaining - 1 }, updatedAt: now };
    return { ok: true, player, task: tasks[taskIndex], localFallback: true };
  }

  if (action === "craft_card" || action === "disenchant_card") {
    const cardId = asString(body.cardId);
    const card = CARD_BY_ID.get(cardId);
    if (!card) throw new Error("卡牌不存在。");
    if (action === "craft_card") {
      const cost = craftCost(card.rarity as "普通" | "稀有" | "史诗" | "传说");
      if (current.currencies.dust < cost) throw new Error("星尘不足，无法制作这张卡。");
      const player = {
        ...current,
        currencies: { ...current.currencies, dust: current.currencies.dust - cost },
        collection: { ...current.collection, [cardId]: (current.collection[cardId] ?? 0) + 1 },
        updatedAt: now,
      };
      return { ok: true, player, cardId, amount: cost, kind: "craft", localFallback: true };
    }
    const owned = current.collection[cardId] ?? 0;
    const used = current.decks.reduce((sum, deck) => sum + deck.cardIds.filter((id) => id === cardId).length, 0);
    if (owned <= used) throw new Error("卡牌正在卡组中使用，至少保留卡组所需数量。");
    const value = disenchantValue(card.rarity as "普通" | "稀有" | "史诗" | "传说");
    const player = {
      ...current,
      currencies: { ...current.currencies, dust: current.currencies.dust + value },
      collection: { ...current.collection, [cardId]: owned - 1 },
      updatedAt: now,
    };
    return { ok: true, player, cardId, amount: value, kind: "disenchant", localFallback: true };
  }

  if (action === "claim_reward") {
    const level = Number(body.level);
    const reward = REWARD_TRACK.find((item) => item.level === level);
    if (!reward) throw new Error("奖励等级不存在。");
    const claimed = current.rewardTrack?.claimedLevels ?? [];
    if ((current.progression?.level ?? 1) < level) throw new Error("奖励等级尚未解锁。");
    if (claimed.includes(level)) throw new Error("该奖励已经领取。");
    const player = {
      ...current,
      currencies: {
        ...current.currencies,
        gold: current.currencies.gold + (reward.kind === "gold" ? reward.amount : 0),
        dust: current.currencies.dust + (reward.kind === "dust" ? reward.amount : 0),
      },
      packsAvailable: current.packsAvailable + (reward.kind === "pack" ? reward.amount : 0),
      rewardTrack: { claimedLevels: [...claimed, level].sort((a, b) => a - b) },
      updatedAt: now,
    };
    return { ok: true, player, level, reward, localFallback: true };
  }

  if (action === "claim_apprentice_reward") {
    const milestoneId = asString(body.milestoneId) as ApprenticeMilestoneId;
    const milestone = APPRENTICE_MILESTONES.find((item) => item.id === milestoneId);
    if (!milestone) throw new Error("新兵里程碑不存在。");
    const claimed = current.apprenticeTrack?.claimedMilestones ?? [];
    if (claimed.includes(milestone.id)) throw new Error("该新兵奖励已经领取。");
    const complete = apprenticeMilestoneComplete(milestone, {
      packsOpened: current.packPity?.packsOpened ?? 0,
      matchesPlayed: current.stats.matchesPlayed,
      wins: current.stats.wins,
      level: current.progression?.level ?? 1,
    });
    if (!complete) throw new Error("新兵里程碑尚未完成。");
    const player = {
      ...current,
      apprenticeTrack: { claimedMilestones: [...claimed, milestone.id] },
      currencies: {
        ...current.currencies,
        gold: current.currencies.gold + (milestone.reward.kind === "gold" ? milestone.reward.amount : 0),
        dust: current.currencies.dust + (milestone.reward.kind === "dust" ? milestone.reward.amount : 0),
      },
      packsAvailable: current.packsAvailable + (milestone.reward.kind === "pack" ? milestone.reward.amount : 0),
      updatedAt: now,
    };
    return {
      ok: true,
      player,
      apprenticeMilestoneId: milestone.id,
      reward: milestone.reward,
      localFallback: true,
    };
  }

  if (action === "save_deck") {
    const deckInput = (body.deck ?? {}) as Record<string, unknown>;
    const id = asString(deckInput.id) || makeId("local-deck");
    const savedDeck: SavedDeck = {
      id,
      name: asString(deckInput.name, "未命名卡组"),
      cardIds: Array.isArray(deckInput.cardIds) ? deckInput.cardIds.map(String) : [],
      format: deckInput.format === "wild" ? "wild" : "standard",
      updatedAt: now,
    };
    const validation = validateDeckForFormat(savedDeck.cardIds, savedDeck.format);
    if (!validation.valid) {
      throw new Error(validation.errors[0]?.message ?? "卡组不符合组牌规则。");
    }
    const ownedCounts = new Map<string, number>();
    savedDeck.cardIds.forEach((cardId) => {
      ownedCounts.set(cardId, (ownedCounts.get(cardId) ?? 0) + 1);
    });
    for (const [cardId, count] of ownedCounts) {
      if (count > (current.collection[cardId] ?? 0)) {
        throw new Error(`收藏中没有足够的「${cardId}」。`);
      }
    }
    const existing = current.decks.findIndex((deck) => deck.id === id);
    if (existing < 0 && current.decks.length >= MAX_SAVED_DECKS) {
      throw new Error(`最多只能保存 ${MAX_SAVED_DECKS} 套卡组。`);
    }
    const decks = [...current.decks];
    if (existing >= 0) decks[existing] = savedDeck;
    else decks.push(savedDeck);
    const player = { ...current, decks, activeDeckId: id, updatedAt: now };
    return { ok: true, player, savedDeck, localFallback: true };
  }

  if (action === "delete_deck") {
    const deckId = asString(body.deckId);
    const removal = removeSavedDeck(
      current.decks,
      current.activeDeckId,
      deckId,
    );
    if (!removal) {
      throw new Error("要删除的卡组不存在。");
    }
    const player = {
      ...current,
      decks: removal.decks,
      activeDeckId: removal.activeDeckId,
      updatedAt: now,
    };
    return { ok: true, player, deletedDeckId: deckId, localFallback: true };
  }

  if (action === "claim_task") {
    const taskId = asString(body.taskId);
    const task = current.tasks.find((item) => item.id === taskId);
    if (!task) throw new Error("任务不存在。");
    if (task.claimed) throw new Error("该任务奖励已经领取。");
    if (task.progress < task.target) throw new Error("任务尚未完成。");
    const rewardGold = task.rewardGold;
    const tasks = current.tasks.map((item) =>
      item.id === taskId ? { ...item, claimed: true } : item,
    );
    const player = {
      ...current,
      currencies: {
        ...current.currencies,
        gold: current.currencies.gold + rewardGold,
      },
      tasks,
      updatedAt: now,
    };
    return {
      ok: true,
      player,
      claimedTaskId: taskId,
      rewardGold,
      localFallback: true,
    };
  }

  if (action === "record_match") {
    if (body.result !== "win" && body.result !== "loss" && body.result !== "draw") throw new Error("对局结果无效。");
    if (body.mode !== "ai" && body.mode !== "pvp") throw new Error("对战模式无效。");
    const result = body.result;
    const cycle = current.taskCycle ?? { dayKey: now.slice(0, 10), weekKey: "demo", dailyRerollsRemaining: 1, packsBoughtToday: 0, aiRewardsToday: 0, weeklyFreePackClaimed: false };
    const aiRewardEligible = body.mode !== "ai" || (cycle.aiRewardsToday ?? 0) < 20;
    const rewardGold = result === "draw" ? 0 : aiRewardEligible ? result === "win" ? 60 : 20 : 0;
    const match: RecentMatch = {
      id: makeId("local-match"),
      result,
      mode: body.mode,
      ...(body.mode === "pvp" ? { format: body.format === "casual" ? "casual" : "ranked" } : {}),
      ...(body.mode === "pvp" ? { rankedFormat: body.rankedFormat === "wild" ? "wild" : "standard" } : {}),
      opponent: asString(body.opponent, "镜像演算体 K-7"),
      rewardGold,
      createdAt: now,
    };
    const tasks = current.tasks.map((task) => {
      const tracksBattle =
        task.id.includes("battle") ||
        task.description.includes("对战") ||
        task.description.includes("演算");
      const tracksWin = task.id.includes("win") || task.description.includes("赢得");
      return tracksBattle && (!tracksWin || result === "win") && !task.claimed
        ? { ...task, progress: Math.min(task.target, task.progress + 1) }
        : task;
    });
    const rankedEconomy = body.mode === "pvp" && body.format !== "casual"
      ? (() => {
          const seasonKey = now.slice(0, 7);
          const rankedFormat: RankedFormat = body.rankedFormat === "wild" ? "wild" : "standard";
          const rolled = rollRankedSeason({
            ladders: normalizeRankedLadders(current.rankedLadders, current.ladder, seasonKey),
            rankedRewards: normalizeRankedRewardState(current.rankedRewards),
            collection: current.collection,
            packsAvailable: current.packsAvailable,
          }, CARD_CATALOG, seasonKey, now);
          return applyRankedMatchResult(rolled, CARD_CATALOG, rankedFormat, result);
        })()
      : null;
    const player = {
      ...current,
      collection: rankedEconomy?.collection ?? current.collection,
      packsAvailable: rankedEconomy?.packsAvailable ?? current.packsAvailable,
      rankedRewards: rankedEconomy?.rankedRewards ?? current.rankedRewards,
      currencies: {
        ...current.currencies,
        gold: current.currencies.gold + rewardGold,
      },
      tasks,
      recentMatches: [match, ...current.recentMatches].slice(0, 20),
      stats: {
        wins: current.stats.wins + (result === "win" ? 1 : 0),
        losses: current.stats.losses + (result === "loss" ? 1 : 0),
        matchesPlayed: current.stats.matchesPlayed + 1,
      },
      progression: {
        xp: (current.progression?.xp ?? 0) + (aiRewardEligible ? 100 : 0),
        level: Math.floor(((current.progression?.xp ?? 0) + (aiRewardEligible ? 100 : 0)) / 1000) + 1,
      },
      taskCycle: {
        ...cycle,
        aiRewardsToday: body.mode === "ai" ? Math.min(20, (cycle.aiRewardsToday ?? 0) + 1) : cycle.aiRewardsToday,
      },
      rankedLadders: rankedEconomy?.ladders ?? current.rankedLadders,
      updatedAt: now,
    };
    return { ok: true, player, rewardGold, localFallback: true };
  }

  return { ok: true, player: { ...current, updatedAt: now }, localFallback: true };
}

function getSide(raw: Record<string, unknown>, side: "player" | "ai"): Record<string, unknown> {
  const direct = raw[side];
  if (direct && typeof direct === "object") return direct as Record<string, unknown>;
  const players = raw.players;
  if (players && typeof players === "object") {
    const collection = players as Record<string, unknown>;
    const selected =
      collection[side] ??
      collection[side === "player" ? "human" : "opponent"] ??
      (Array.isArray(players) ? players[side === "player" ? 0 : 1] : undefined);
    if (selected && typeof selected === "object") return selected as Record<string, unknown>;
  }
  return {};
}

function normalizeHand(
  value: unknown,
  reductionsValue?: unknown,
  fragmentsValue?: unknown,
  enteredTurnsValue?: unknown,
  entityIdsValue?: unknown,
): BattleSide["hand"] {
  if (!Array.isArray(value)) return [];
  const reductions = Array.isArray(reductionsValue) ? reductionsValue : [];
  const fragments = Array.isArray(fragmentsValue) ? fragmentsValue : [];
  const enteredTurns = Array.isArray(enteredTurnsValue) ? enteredTurnsValue : [];
  const entityIds = Array.isArray(entityIdsValue) ? entityIdsValue : [];
  return value.map((entry, index) => {
    const rawReduction = reductions[index];
    const costReduction = typeof rawReduction === "number" && Number.isFinite(rawReduction)
      ? Math.max(0, Math.floor(rawReduction))
      : 0;
    const rawFragment = fragments[index];
    const fragment = rawFragment && typeof rawFragment === "object"
      ? rawFragment as Record<string, unknown>
      : null;
    const piece = fragment?.piece === "left" || fragment?.piece === "right"
      ? fragment.piece
      : undefined;
    const fragmentGroupId = piece ? asString(fragment?.groupId) || undefined : undefined;
    const enteredTurn = Math.max(0, Math.floor(asNumber(enteredTurns[index], 0)));
    const projectedEntityId = asString(entityIds[index]);
    if (typeof entry === "string") return {
      instanceId: projectedEntityId || `legacy-hand-${index}-${entry}`,
      cardId: entry,
      handIndex: index,
      costReduction,
      fragment: piece,
      fragmentGroupId,
      enteredTurn,
    };
    const item = (entry ?? {}) as Record<string, unknown>;
    return {
      instanceId:
        projectedEntityId ||
        asString(item.instanceId ?? item.uid ?? item.id, `legacy-hand-${index}`),
      cardId: asString(item.cardId ?? item.definitionId ?? item.id),
      handIndex: index,
      costReduction,
      fragment: piece,
      fragmentGroupId,
      enteredTurn,
    };
  });
}

function normalizeBoard(value: unknown, turn: number): BattleUnit[] {
  if (!Array.isArray(value)) return [];
  return value.map((entry, index) => {
    const item = (entry ?? {}) as Record<string, unknown>;
    const cardId = asString(item.cardId ?? item.definitionId ?? item.id);
    const card = CARD_BY_ID.get(cardId);
    const health = asNumber(item.health ?? item.currentHealth, card?.health ?? 1);
    const keywords = Array.isArray(item.keywords) ? item.keywords.map(String) : [];
    const stealthActive =
      typeof item.stealthActive === "boolean"
        ? item.stealthActive
        : keywords.includes("stealth");
    const hasAttacked = Boolean(item.hasAttacked);
    const summonedTurn = asNumber(item.summonedTurn, -1);
    const attacksMade = asNumber(item.attacksMade, hasAttacked ? 1 : 0);
    const attack = asNumber(item.attack ?? item.power, card?.attack ?? 0);
    const frozenTurns = asNumber(item.frozenTurns, 0);
    const summoningSick =
      typeof item.summoningSick === "boolean"
        ? item.summoningSick
        : summonedTurn === turn &&
          !keywords.includes("charge") &&
          !keywords.includes("rush");
    return {
      id: asString(item.entityId ?? item.instanceId ?? item.uid ?? item.id, `unit-${index}`),
      cardId,
      name: asString(item.name, card?.name ?? "未知单位"),
      attack,
      health,
      maxHealth: asNumber(item.maxHealth, card?.health ?? health),
      stars: Math.min(
        2,
        Math.max(1, asNumber(item.stars ?? item.starLevel ?? item.rank, 1)),
      ) as 1 | 2,
      keywords: keywords as Keyword[],
      minionTypes: Array.isArray(item.minionTypes)
        ? (item.minionTypes.map(String) as MinionType[])
        : [...(card?.minionTypes ?? [])],
      stealthActive,
      frozenTurns,
      summoningSick,
      rushOnly: Boolean(item.rushOnly),
      furyStacks: asNumber(item.furyStacks, 0),
      spellDamage: asNumber(item.spellDamage, card?.spellDamage ?? 0),
      temporaryAttackBonus: asNumber(item.temporaryAttackBonus, 0),
      temporaryHealthBonus: asNumber(item.temporaryHealthBonus, 0),
      // A stale snapshot can carry a previously computed `canAttack` flag
      // even after the unit has reached zero health.  The death window always
      // wins over derived UI state, so never surface a dead unit as READY.
      canAttack: health > 0 && (
        typeof item.canAttack === "boolean"
          ? item.canAttack
          : attack > 0 &&
            !summoningSick &&
            frozenTurns <= 0 &&
            attacksMade < (keywords.includes("windfury") ? 2 : 1)
      ),
      attacksMade,
    };
  });
}

function battleFromRaw(value: unknown): BattleView | null {
  if (!value || typeof value !== "object") return null;
  const wrapper = value as Record<string, unknown>;
  const raw =
    wrapper.state && typeof wrapper.state === "object"
      ? (wrapper.state as Record<string, unknown>)
      : wrapper;
  const player = getSide(raw, "player");
  const ai = getSide(raw, "ai");
  const turn = asNumber(raw.turn ?? raw.turnNumber, 1);
  const normalizeSide = (side: Record<string, unknown>): BattleSide => ({
    health: asNumber(
      (side.hero as Record<string, unknown> | undefined)?.health ??
        side.health ??
        side.heroHealth ??
        side.hp,
      30,
    ),
    maxHealth: asNumber(
      (side.hero as Record<string, unknown> | undefined)?.maxHealth ??
        side.maxHealth ??
        side.maxHeroHealth,
      30,
    ),
    armor: asNumber(
      (side.hero as Record<string, unknown> | undefined)?.armor ?? side.armor,
      0,
    ),
    heroId: asString((side.hero as Record<string, unknown> | undefined)?.id, "faction-commander"),
    heroName: asString((side.hero as Record<string, unknown> | undefined)?.name, "远征指挥官"),
    heroPowerUsed: Boolean(side.heroPowerUsed),
    heroPowerName: asString(
      (side.heroPower as Record<string, unknown> | undefined)?.name ?? side.heroPowerName,
      "核心脉冲",
    ),
    heroPowerDescription: asString(
      (side.heroPower as Record<string, unknown> | undefined)?.description ?? side.heroPowerDescription,
      "对敌方核心造成 1 点伤害。",
    ),
    heroPowerCost: asNumber(
      (side.heroPower as Record<string, unknown> | undefined)?.cost ?? side.heroPowerCost,
      2,
    ),
    heroPowerTarget: asString(
      (side.heroPower as Record<string, unknown> | undefined)?.target ?? side.heroPowerTarget,
      "none",
    ) as CardTargetRule,
    heroPowerEffect: (
      (side.heroPower as Record<string, unknown> | undefined)?.effect ??
      side.heroPowerEffect ??
      { kind: "damage-enemy-hero", amount: 1 }
    ) as HeroPowerEffect,
    coinAvailable: Boolean(side.coinAvailable),
    heroHasAttacked: Boolean(side.heroHasAttacked),
    heroAttackBonus: asNumber(side.heroAttackBonus, 0),
    overload: asNumber(side.overload, 0),
    overloadLocked: asNumber(side.overloadLocked, 0),
    spellSchoolsPlayedThisTurn: Array.isArray(side.spellSchoolsPlayedThisTurn)
      ? side.spellSchoolsPlayedThisTurn
          .map(String)
          .filter((school): school is SpellSchool => SPELL_SCHOOL_ORDER.includes(school as SpellSchool))
      : [],
    spellSchoolsPlayedLastTurn: Array.isArray(side.spellSchoolsPlayedLastTurn)
      ? side.spellSchoolsPlayedLastTurn
          .map(String)
          .filter((school): school is SpellSchool => SPELL_SCHOOL_ORDER.includes(school as SpellSchool))
      : [],
    deathHistory: Array.isArray(side.deathHistory)
      ? side.deathHistory.map((entry, index) => {
          const record = (entry ?? {}) as Record<string, unknown>;
          const cardId = asString(record.cardId);
          return {
            entityId: asString(record.entityId, `death-${index}`),
            cardId,
            name: asString(record.name, CARD_BY_ID.get(cardId)?.name ?? "未知单位"),
            diedTurn: asNumber(record.diedTurn, 1),
            deathOrder: asNumber(record.deathOrder, index + 1),
            minionTypes: Array.isArray(record.minionTypes)
              ? (record.minionTypes.map(String) as MinionType[])
              : [...(CARD_BY_ID.get(cardId)?.minionTypes ?? [])],
          };
        })
      : [],
    discardHistory: Array.isArray(side.discardHistory)
      ? side.discardHistory.map((entry, index) => {
          const record = (entry ?? {}) as Record<string, unknown>;
          const cardId = asString(record.cardId);
          const fragment = record.fragment === "left" || record.fragment === "right"
            ? record.fragment
            : undefined;
          return {
            discardId: asString(record.discardId, `discard-${index}`),
            cardId,
            name: asString(record.name, CARD_BY_ID.get(cardId)?.name ?? "未知卡牌"),
            discardedTurn: asNumber(record.discardedTurn, 1),
            discardOrder: asNumber(record.discardOrder, index + 1),
            ...(fragment ? { fragment } : {}),
          };
        })
      : [],
    secrets: Array.isArray(side.secrets)
      ? side.secrets.map((entry) => {
          const secret = entry as Record<string, unknown>;
          return {
            secretId: asString(secret.secretId),
            name: asString(secret.name, "未知奥秘"),
            description: asString(secret.description, "等待敌方行动触发。"),
          };
        })
      : [],
    weapon:
      side.weapon && typeof side.weapon === "object"
        ? (() => {
            const weapon = side.weapon as Record<string, unknown>;
            const card = CARD_BY_ID.get(asString(weapon.cardId));
            return {
              cardId: asString(weapon.cardId),
              name: asString(weapon.name, card?.name ?? "未知武器"),
              attack: asNumber(weapon.attack, card?.attack ?? 0),
              durability: asNumber(weapon.durability, 0),
              maxDurability: asNumber(weapon.maxDurability, card?.durability ?? 1),
            };
          })()
        : null,
    mana: asNumber(side.mana ?? side.energy ?? side.currentMana),
    maxMana: asNumber(side.maxMana ?? side.maxEnergy, 1),
    heraldCount: asNumber(side.heraldCount),
    deckCount: Array.isArray(side.deck)
      ? side.deck.length
      : asNumber(side.deckCount ?? side.remainingDeck),
    hand: normalizeHand(
      side.hand,
      side.handCostReductions,
      side.handFragments,
      side.handEnteredTurns,
      side.handEntityIds,
    ),
    board: normalizeBoard(side.board ?? side.units, turn),
  });
  const statusRaw = asString(raw.status ?? raw.phase, "playing").toLowerCase();
  const isMulligan = statusRaw === "mulligan";
  const isDiscover = statusRaw === "discover";
  const isChooseOne = statusRaw === "choose-one";
  const rawDiscover = raw.discover && typeof raw.discover === "object"
    ? raw.discover as Record<string, unknown>
    : null;
  const discover = isDiscover && rawDiscover && Array.isArray(rawDiscover.choices)
    ? {
        sourceCardId: asString(rawDiscover.sourceCardId),
        choices: rawDiscover.choices.map((choice, index) => {
          const cardId = asString(choice);
          if (!cardId) return null;
          const snapshot = Array.isArray(rawDiscover.choiceSnapshots)
            && rawDiscover.choiceSnapshots[index]
            && typeof rawDiscover.choiceSnapshots[index] === "object"
            ? rawDiscover.choiceSnapshots[index] as Record<string, unknown>
            : null;
          const reduction = snapshot ? Math.max(0, asNumber(snapshot.costReduction, 0)) : undefined;
          const printedCost = CARD_BY_ID.get(cardId)?.cost;
          const fragment = snapshot?.fragment === "left" || snapshot?.fragment === "right"
            ? snapshot.fragment
            : undefined;
          return {
            cardId,
            ...(printedCost !== undefined && reduction !== undefined
              ? { currentCost: Math.max(0, printedCost - reduction) }
              : {}),
            ...(fragment ? { fragment } : {}),
          };
        }).filter((choice): choice is NonNullable<typeof choice> => Boolean(choice)),
      }
    : null;
  const rawChooseOne = raw.chooseOne && typeof raw.chooseOne === "object"
    ? raw.chooseOne as Record<string, unknown>
    : null;
  const chooseOne = isChooseOne && rawChooseOne && Array.isArray(rawChooseOne.options)
    ? {
        player: asNumber(rawChooseOne.player, 1) === 0 ? "player" as const : "ai" as const,
        sourceCardId: asString(rawChooseOne.sourceCardId),
        options: (asNumber(rawChooseOne.player, 1) === 0 ? rawChooseOne.options : [])
          .map((option) => {
            if (!option || typeof option !== "object") return null;
            return { label: asString((option as Record<string, unknown>).label, "选择分支") };
          })
          .filter((option): option is { label: string } => Boolean(option)),
        remainingChoices: Math.max(1, asNumber(rawChooseOne.remainingChoices, 1)),
        sourceKind: rawChooseOne.sourceKind === "hero-card" ? "hero-card" as const : "spell" as const,
      }
    : null;
  const winnerValue = raw.winner ?? raw.winnerId;
  const winnerRaw = asString(winnerValue).toLowerCase();
  const rawResult = raw.result && typeof raw.result === "object"
    ? raw.result as Record<string, unknown>
    : null;
  const reasonValue = rawResult?.reason ?? raw.reason;
  const reasonRaw = asString(reasonValue).toLowerCase();
  const report: BattleReport = {
    reason:
      reasonRaw === "hero-defeated" ||
      reasonRaw === "fatigue" ||
      reasonRaw === "concede" ||
      reasonRaw === "draw"
        ? reasonRaw
        : null,
    cardsPlayed: [0, 0],
    attacks: [0, 0],
    damage: [0, 0],
    healing: [0, 0],
    unitsDied: [0, 0],
    cardsDrawn: [0, 0],
  };
  const reportEvents = Array.isArray(raw.events) ? raw.events : [];
  reportEvents.forEach((entry) => {
    if (!entry || typeof entry !== "object") return;
    const event = entry as Record<string, unknown>;
    const player = event.player === 0 || event.player === 1 ? event.player : null;
    const type = asString(event.type);
    const data = event.data && typeof event.data === "object"
      ? event.data as Record<string, unknown>
      : {};
    if (player !== null && type === "card-played") report.cardsPlayed[player] += 1;
    if (player !== null && type === "attack") report.attacks[player] += 1;
    if (player !== null && type === "card-drawn") report.cardsDrawn[player] += 1;
    if (player !== null && type === "damage") report.damage[player] += asNumber(data.amount, 0);
    if (player !== null && type === "healing") report.healing[player] += asNumber(data.amount, 0);
    if (type === "unit-died") {
      const owner = data.targetPlayer === 0 || data.targetPlayer === 1
        ? data.targetPlayer
        : player;
      if (owner !== null) report.unitsDied[owner] += 1;
    }
  });
  const currentValue = raw.currentPlayer ?? raw.activePlayer ?? raw.activeSide;
  const currentRaw = asString(currentValue, "player").toLowerCase();
  const events = raw.log ?? raw.logs ?? raw.events;
  const log = Array.isArray(events)
    ? events
        .slice(-12)
        .map((event) =>
          formatBattleLogMessage(
            typeof event === "string"
              ? event
              : asString(
                (event as Record<string, unknown>)?.message ??
                  (event as Record<string, unknown>)?.text ??
                  (event as Record<string, unknown>)?.type,
                "战场状态已更新",
              ),
          ),
        )
    : [];
  return {
    status:
      isMulligan
        ? "mulligan"
        : isDiscover
          ? "discover"
          : isChooseOne
            ? "choose-one"
            : statusRaw === "finished" ||
              statusRaw === "ended" ||
              statusRaw === "game-over" ||
              winnerValue === 0 ||
              winnerValue === 1 ||
              Boolean(winnerRaw)
              ? "finished"
              : "playing",
    mulliganDone: Array.isArray(raw.mulliganDone)
      ? Boolean(raw.mulliganDone[0])
      : !isMulligan,
    winner:
      winnerValue === 0 || winnerRaw === "player" || winnerRaw === "human"
        ? "player"
        : winnerValue === 1 || winnerRaw === "ai" || winnerRaw === "opponent"
          ? "ai"
          : null,
    currentPlayer:
      currentValue === 1 ||
      currentRaw === "1" ||
      currentRaw === "ai" ||
      currentRaw === "opponent"
        ? "ai"
        : "player",
    turn,
    player: normalizeSide(player),
    ai: normalizeSide(ai),
    log,
    discover,
    chooseOne,
    report,
  };
}

function unwrapTransition(value: unknown): unknown {
  if (!value || typeof value !== "object") return value;
  const raw = value as Record<string, unknown>;
  return raw.state ?? raw.match ?? raw;
}

function validationFromRaw(value: unknown): ValidationView {
  if (typeof value === "boolean") {
    return { valid: value, errors: value ? [] : ["卡组未通过规则校验"] };
  }
  if (Array.isArray(value)) {
    return { valid: value.length === 0, errors: value.map(String) };
  }
  if (value && typeof value === "object") {
    const raw = value as Record<string, unknown>;
    const errors = Array.isArray(raw.errors)
      ? raw.errors.map((error) =>
          typeof error === "string"
            ? error
            : asString((error as Record<string, unknown>)?.message, "卡组规则错误"),
        )
      : [];
    return { valid: Boolean(raw.valid ?? raw.ok ?? errors.length === 0), errors };
  }
  return { valid: false, errors: ["无法校验卡组"] };
}

function Icon({ name, size = 20 }: { name: IconName; size?: number }) {
  const glyphs: Record<IconName, string> = {
    radar: "⌾",
    cards: "▣",
    layers: "≋",
    swords: "⚔",
    chart: "▥",
    coin: "◉",
    dust: "✦",
    pack: "▤",
    search: "⌕",
    shield: "◆",
    spark: "✦",
    check: "✓",
    arrow: "→",
    plus: "+",
    minus: "−",
    clock: "◷",
    user: "●",
    bot: "◇",
    menu: "☰",
    trash: "⌫",
    close: "×",
  };

  return (
    <span
      aria-hidden="true"
      className={`ui-icon ui-icon--${name}`}
      style={{ "--icon-size": `${size}px` } as CSSProperties}
    >
      {glyphs[name]}
    </span>
  );
}

function ProgressBar({
  value,
  max,
  label,
}: {
  value: number;
  max: number;
  label: string;
}) {
  const percent = max <= 0 ? 0 : Math.min(100, Math.max(0, (value / max) * 100));
  return (
    <div
      className="progress"
      role="progressbar"
      aria-label={label}
      aria-valuemin={0}
      aria-valuemax={max}
      aria-valuenow={Math.min(value, max)}
    >
      <span
        className="progress__fill"
        style={{ "--progress-value": `${percent}%` } as CSSProperties}
      />
    </div>
  );
}

function Sigil({ card }: { card: CatalogCard }) {
  const type = card.type === "spell" ? "spell" : card.type === "weapon" ? "weapon" : card.type === "hero" ? "hero" : "unit";
  return (
    <div className={`card-sigil card-sigil--${type}`} aria-hidden="true">
      <span className="card-sigil__orbit card-sigil__orbit--outer" />
      <span className="card-sigil__orbit card-sigil__orbit--inner" />
      <span className="card-sigil__glyph">{type === "unit" ? "◇" : type === "weapon" ? "⚔" : type === "hero" ? "♛" : "✦"}</span>
    </div>
  );
}

function CardArtwork({
  card,
  className = "",
  eager = false,
}: {
  card: Pick<CatalogCard, "id" | "name">;
  className?: string;
  eager?: boolean;
}) {
  return (
    <Image
      className={`card-artwork ${className}`.trim()}
      src={`/cards/${card.id}.webp`}
      alt=""
      width={768}
      height={960}
      unoptimized
      sizes="(max-width: 720px) 50vw, 220px"
      aria-hidden="true"
      loading={eager ? "eager" : "lazy"}
      decoding="async"
      draggable={false}
      onError={(event) => {
        event.currentTarget.hidden = true;
      }}
    />
  );
}

function CardTile({
  card,
  owned,
  countInDeck,
  compact = false,
  showDescription = false,
  action,
  actionLabel,
  disabled = false,
  costOverride,
}: {
  card: CatalogCard;
  owned?: number;
  countInDeck?: number;
  compact?: boolean;
  showDescription?: boolean;
  action?: () => void;
  actionLabel?: string;
  disabled?: boolean;
  costOverride?: number;
}) {
  const factionTone = FACTION_DEFINITIONS[card.faction]?.tone ?? "neutral";
  const cardClassName = `game-card game-card--faction-${factionTone} ${compact ? "game-card--compact" : ""}`;
  const displayedCost = typeof costOverride === "number"
    ? Math.max(0, Math.floor(costOverride))
    : card.cost;
  const content = (
    <>
      <div className="game-card__visual">
        <Sigil card={card} />
        <CardArtwork card={card} className="game-card__artwork" />
        <span className={`game-card__cost ${displayedCost < card.cost ? "is-discounted" : ""}`} aria-label={`${displayedCost} 点能量${displayedCost < card.cost ? `，原费用 ${card.cost}` : ""}`}>
          {displayedCost}
        </span>
        <span className={`game-card__rarity game-card__rarity--${card.rarity}`} />
        {typeof owned === "number" && (
          <span className="game-card__owned">持有 {owned}</span>
        )}
      </div>
      <div className="game-card__body">
        <div className="game-card__meta">
          <span>{card.faction}</span>
          <span>{TYPE_LABEL[card.type] ?? card.type}</span>
          {card.set && <span>{CARD_SET_DEFINITIONS[card.set].label}</span>}
        </div>
        <h3>{card.name}</h3>
        <div className="game-card__tags" aria-label="随从类型、卡牌特质与关键词">
          {card.minionTypes.map((minionType) => {
            const definition = MINION_TYPE_DEFINITIONS[minionType];
            return (
              <span
                className="card-tag card-tag--minion-type"
                title={`${definition.label}：${definition.description}`}
                aria-label={`随从类型：${definition.label}`}
                key={minionType}
              >
                {definition.sigil} {definition.label}
              </span>
            );
          })}
          {card.traits.map((trait) => {
            const definition = TRAIT_DEFINITIONS[trait];
            return (
              <span
                className={`card-tag card-tag--trait card-tag--${trait}`}
                title={`${definition.label}：${definition.descriptions[0]}`}
                aria-label={`${definition.label}：${definition.descriptions[0]}`}
                key={trait}
              >
                {definition.sigil} {definition.label}
              </span>
            );
          })}
          {card.school && (
            <span
              className="card-tag card-tag--school"
              aria-label={`战术学派：${SPELL_SCHOOL_LABEL[card.school]}`}
            >
              {SPELL_SCHOOL_LABEL[card.school]}
            </span>
          )}
          {card.keywords.map((keyword) => {
            const definition = KEYWORD_DEFINITIONS[keyword];
            return (
              <span
                className="card-tag card-tag--keyword"
                title={`${definition.label}：${definition.description}`}
                aria-label={`${definition.label}：${definition.description}`}
                key={keyword}
              >
                {definition.label}
              </span>
            );
          })}
        </div>
        {(!compact || showDescription) && <p>{card.description}</p>}
        <div className="game-card__footer">
          {card.type === "unit" ? (
            <div className="game-card__stats" aria-label={`攻击 ${card.attack ?? 0}，生命 ${card.health ?? 0}`}>
              <span className="game-card__attack">⚔ {card.attack ?? 0}</span>
              <span className="game-card__health">◆ {card.health ?? 0}</span>
            </div>
          ) : card.type === "weapon" ? (
            <div className="game-card__stats" aria-label={`攻击 ${card.attack ?? 0}，耐久 ${card.durability ?? 0}`}>
              <span className="game-card__attack">⚔ {card.attack ?? 0}</span>
              <span className="game-card__health">◈ {card.durability ?? 0}</span>
            </div>
          ) : card.type === "hero" ? (
            <span className="game-card__type">英雄替换 · 护甲</span>
          ) : (
            <span className="game-card__type">即时战术</span>
          )}
          {typeof countInDeck === "number" && countInDeck > 0 && (
            <span className="game-card__deck-count">× {countInDeck}</span>
          )}
        </div>
      </div>
    </>
  );

  if (action) {
    return (
      <button
        className={cardClassName}
        type="button"
        onClick={action}
        disabled={disabled}
        aria-label={actionLabel ?? card.name}
      >
        {content}
      </button>
    );
  }
  return <article className={cardClassName}>{content}</article>;
}

function EmptyState({
  icon,
  title,
  children,
  action,
}: {
  icon: IconName;
  title: string;
  children: ReactNode;
  action?: ReactNode;
}) {
  return (
    <div className="empty-state">
      <span className="empty-state__icon">
        <Icon name={icon} size={28} />
      </span>
      <h3>{title}</h3>
      <p>{children}</p>
      {action}
    </div>
  );
}

function SectionHeading({
  eyebrow,
  title,
  description,
  action,
}: {
  eyebrow: string;
  title: string;
  description: string;
  action?: ReactNode;
}) {
  return (
    <header className="section-heading">
      <div>
        <span className="section-heading__eyebrow">{eyebrow}</span>
        <h1>{title}</h1>
        <p>{description}</p>
      </div>
      {action && <div className="section-heading__action">{action}</div>}
    </header>
  );
}

type BattleSoundCue = BattleEffectKind | "select" | "error";
// Keep each combat beat readable on a phone. The reducer still emits every
// event; the client now replays a longer, ordered queue instead of collapsing
// an AI turn into one frame. Players can opt into an even slower cadence from
// the battle header when they want to inspect every beat.
// Keep the original baseline symbol for compatibility with cached clients;
// the standard live cadence intentionally adds 300 ms for readability.
const BATTLE_EFFECT_STEP_MS = 1200;
const BATTLE_EFFECT_STANDARD_STEP_MS = BATTLE_EFFECT_STEP_MS + 300;
const BATTLE_EFFECT_SLOW_STEP_MS = 2400;
// Give the opponent a readable planning window before its complete reducer
// transition is revealed. This keeps a full AI turn from collapsing into one
// frame on slower phones and makes the event stream match the board animation.
const AI_TURN_DELAY_MS = 2200;
// Keep the full event stream for long deathrattle / secret / AoE chains. The
// skip button remains available, so a long replay is inspectable without
// forcing the player to watch every beat.
const BATTLE_EFFECT_QUEUE_LIMIT = 96;
// A visible action clock gives each turn a readable rhythm and prevents a
// local match from feeling like an unbounded sandbox. PVP remains
// server-authoritative; the active client submits an end-turn command when
// its local clock expires.
const TURN_TIME_LIMIT_SECONDS = 75;
const BOARD_SLOT_COUNT = 7;

type BattleTone = {
  frequency: number;
  endFrequency?: number;
  duration: number;
  delay?: number;
  gain: number;
  wave?: OscillatorType;
};

const BATTLE_TONES: Record<BattleSoundCue, readonly BattleTone[]> = {
  start: [
    { frequency: 120, endFrequency: 180, duration: 0.28, gain: 0.045, wave: "sine" },
    { frequency: 360, endFrequency: 720, duration: 0.24, delay: 0.06, gain: 0.025 },
  ],
  draw: [
    { frequency: 520, endFrequency: 780, duration: 0.12, gain: 0.026, wave: "triangle" },
  ],
  trade: [
    { frequency: 260, endFrequency: 520, duration: 0.16, gain: 0.028, wave: "triangle" },
    { frequency: 780, endFrequency: 1040, duration: 0.18, delay: 0.08, gain: 0.022, wave: "sine" },
  ],
  card: [
    { frequency: 280, endFrequency: 540, duration: 0.18, gain: 0.035, wave: "triangle" },
    { frequency: 760, endFrequency: 920, duration: 0.1, delay: 0.08, gain: 0.018 },
  ],
  summon: [
    { frequency: 92, endFrequency: 150, duration: 0.34, gain: 0.052, wave: "sine" },
    { frequency: 310, endFrequency: 620, duration: 0.24, delay: 0.05, gain: 0.028, wave: "triangle" },
  ],
  attack: [
    { frequency: 540, endFrequency: 130, duration: 0.17, gain: 0.043, wave: "sawtooth" },
    { frequency: 88, endFrequency: 54, duration: 0.24, delay: 0.09, gain: 0.054, wave: "sine" },
  ],
  damage: [
    { frequency: 115, endFrequency: 48, duration: 0.18, gain: 0.06, wave: "square" },
    { frequency: 72, duration: 0.25, gain: 0.045, wave: "sine" },
  ],
  heal: [
    { frequency: 392, endFrequency: 587, duration: 0.28, gain: 0.028, wave: "sine" },
    { frequency: 659, endFrequency: 880, duration: 0.22, delay: 0.08, gain: 0.02 },
  ],
  buff: [
    { frequency: 330, endFrequency: 660, duration: 0.22, gain: 0.03, wave: "triangle" },
    { frequency: 495, endFrequency: 990, duration: 0.2, delay: 0.06, gain: 0.018 },
  ],
  shield: [
    { frequency: 920, endFrequency: 210, duration: 0.2, gain: 0.032, wave: "square" },
    { frequency: 1380, endFrequency: 420, duration: 0.12, delay: 0.025, gain: 0.014 },
  ],
  destroy: [
    { frequency: 170, endFrequency: 45, duration: 0.36, gain: 0.052, wave: "sawtooth" },
    { frequency: 68, endFrequency: 38, duration: 0.44, delay: 0.06, gain: 0.04 },
  ],
  turn: [
    { frequency: 392, endFrequency: 523, duration: 0.16, gain: 0.026, wave: "triangle" },
    { frequency: 587, endFrequency: 784, duration: 0.18, delay: 0.1, gain: 0.024 },
  ],
  win: [
    { frequency: 261.63, endFrequency: 523.25, duration: 0.46, gain: 0.035 },
    { frequency: 329.63, endFrequency: 659.25, duration: 0.42, delay: 0.08, gain: 0.03 },
    { frequency: 392, endFrequency: 783.99, duration: 0.48, delay: 0.16, gain: 0.028 },
  ],
  loss: [
    { frequency: 220, endFrequency: 110, duration: 0.48, gain: 0.035, wave: "triangle" },
    { frequency: 164.81, endFrequency: 82.41, duration: 0.52, delay: 0.08, gain: 0.032 },
  ],
  select: [
    { frequency: 520, endFrequency: 680, duration: 0.07, gain: 0.018, wave: "sine" },
  ],
  error: [
    { frequency: 150, endFrequency: 118, duration: 0.13, gain: 0.035, wave: "square" },
  ],
};

function scheduleBattleCue(
  context: AudioContext,
  master: GainNode,
  cue: BattleSoundCue,
) {
  const now = context.currentTime + 0.012;
  for (const tone of BATTLE_TONES[cue]) {
    const oscillator = context.createOscillator();
    const envelope = context.createGain();
    const start = now + (tone.delay ?? 0);
    const end = start + tone.duration;

    oscillator.type = tone.wave ?? "sine";
    oscillator.frequency.setValueAtTime(tone.frequency, start);
    if (tone.endFrequency) {
      oscillator.frequency.exponentialRampToValueAtTime(tone.endFrequency, end);
    }
    envelope.gain.setValueAtTime(0.0001, start);
    envelope.gain.exponentialRampToValueAtTime(tone.gain, start + 0.012);
    envelope.gain.exponentialRampToValueAtTime(0.0001, end);
    oscillator.connect(envelope);
    envelope.connect(master);
    oscillator.start(start);
    oscillator.stop(end + 0.02);
    oscillator.addEventListener(
      "ended",
      () => {
        oscillator.disconnect();
        envelope.disconnect();
      },
      { once: true },
    );
  }
}

function useBattleAudio() {
  const [soundEnabled, setSoundEnabled] = useState(true);
  const soundEnabledRef = useRef(true);
  const contextRef = useRef<AudioContext | null>(null);
  const masterGainRef = useRef<GainNode | null>(null);
  const resumePromiseRef = useRef<Promise<void> | null>(null);
  const pendingCueRef = useRef<BattleSoundCue | null>(null);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      try {
        const stored = window.localStorage.getItem("astra-battle-sound");
        if (stored === "off") {
          soundEnabledRef.current = false;
          setSoundEnabled(false);
        }
      } catch {
        // Sound preferences are optional; private browsing may disable storage.
      }
    }, 0);
    return () => window.clearTimeout(timer);
  }, []);

  const resumeAudio = useCallback((context: AudioContext) => {
    if (context.state === "running") return Promise.resolve();
    if (resumePromiseRef.current) return resumePromiseRef.current;

    const promise = context.resume().catch(() => {
      // Browsers may keep audio suspended until another trusted gesture.
    });
    resumePromiseRef.current = promise;
    void promise.finally(() => {
      if (resumePromiseRef.current === promise) {
        resumePromiseRef.current = null;
      }
    });
    return promise;
  }, []);

  const unlockAudio = useCallback(() => {
    if (typeof window === "undefined" || !soundEnabledRef.current) return null;
    const AudioContextConstructor =
      window.AudioContext ??
      (window as typeof window & { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!AudioContextConstructor) return null;

    try {
      let context = contextRef.current;
      if (!context || context.state === "closed") {
        context = new AudioContextConstructor();
        const master = context.createGain();
        master.gain.value = 0.42;
        master.connect(context.destination);
        contextRef.current = context;
        masterGainRef.current = master;
      }
      if (context.state === "suspended") {
        void resumeAudio(context);
      }
      return context;
    } catch {
      return null;
    }
  }, [resumeAudio]);

  const playSound = useCallback(
    (cue: BattleSoundCue) => {
      if (!soundEnabledRef.current) return;
      const context = unlockAudio();
      const master = masterGainRef.current;
      if (!context || !master) return;
      if (context.state === "running") {
        try {
          scheduleBattleCue(context, master, cue);
        } catch {
          // Audio feedback must never block a battle command.
        }
        return;
      }
      pendingCueRef.current = cue;
      void resumeAudio(context)
        .then(() => {
          const pendingCue = pendingCueRef.current;
          pendingCueRef.current = null;
          if (
            pendingCue &&
            soundEnabledRef.current &&
            contextRef.current === context &&
            masterGainRef.current === master &&
            context.state === "running"
          ) {
            scheduleBattleCue(context, master, pendingCue);
          }
        })
        .catch(() => {
          pendingCueRef.current = null;
        });
    },
    [resumeAudio, unlockAudio],
  );

  const toggleSound = useCallback(() => {
    const next = !soundEnabledRef.current;
    soundEnabledRef.current = next;
    setSoundEnabled(next);
    try {
      window.localStorage.setItem("astra-battle-sound", next ? "on" : "off");
    } catch {
      // Preference persistence is a convenience, not a battle dependency.
    }

    const context = next ? unlockAudio() : contextRef.current;
    const master = masterGainRef.current;
    if (context && master) {
      master.gain.cancelScheduledValues(context.currentTime);
      master.gain.setTargetAtTime(next ? 0.42 : 0.0001, context.currentTime, 0.012);
    }
    if (next) {
      playSound("select");
    }
  }, [playSound, unlockAudio]);

  useEffect(
    () => () => {
      const context = contextRef.current;
      contextRef.current = null;
      masterGainRef.current = null;
      pendingCueRef.current = null;
      resumePromiseRef.current = null;
      if (context && context.state !== "closed") {
        void context.close().catch(() => {
          // Audio cleanup must never affect the game surface.
        });
      }
    },
    [],
  );

  return { soundEnabled, unlockAudio, playSound, toggleSound };
}

function useWebPvp(displayName: string) {
  const socketRef = useRef<WebSocket | null>(null);
  const transportRef = useRef<"websocket" | "poll" | null>(null);
  const connectionIdRef = useRef(0);
  const incomingIdRef = useRef(0);
  const fallbackStartedRef = useRef<number | null>(null);
  const fallbackTimerRef = useRef<number | null>(null);
  const pollClientRef = useRef<string | null>(null);
  const pollCursorRef = useRef(0);
  const pollEndpointRef = useRef<string | null>(null);
  // Keep one opaque polling id per browser tab. sessionStorage survives a
  // refresh (and normal mobile tab restores) without making two tabs share a
  // live PVP session.
  const pollResumeClientRef = useRef<string | null>(null);
  const pollTimerRef = useRef<number | null>(null);
  const pollInFlightRef = useRef(false);
  // A browser can issue ready/start/command requests in the same render tick.
  // Serialize polling writes so HTTP scheduling cannot reorder the player's
  // intent before the Worker assigns an authoritative room sequence.
  const pollSendTailRef = useRef<Promise<void>>(Promise.resolve());
  const incomingQueueRef = useRef<PvpIncoming[]>([]);
  const lastSequenceRef = useRef(0);
  const [state, setState] = useState<PvpState>({
    status: "offline",
    url: getDefaultPvpUrl(),
    playerId: null,
    roomCode: null,
    role: null,
    format: "ranked",
    rankedFormat: "standard",
    matchPool: null,
    matchQuality: null,
    peerName: null,
    localReady: false,
    remoteReady: false,
    remoteReadyDeck: null,
    message: "未连接联机大厅",
  });
  const [incoming, setIncoming] = useState<PvpIncoming | null>(null);

  const enqueueIncoming = useCallback((event: PvpIncoming) => {
    setIncoming((current) => {
      if (current) {
        incomingQueueRef.current.push(event);
        return current;
      }
      return event;
    });
  }, []);

  const acknowledgeIncoming = useCallback((eventId: number) => {
    setIncoming((current) => {
      if (!current || current.id !== eventId) return current;
      return incomingQueueRef.current.shift() ?? null;
    });
  }, []);

  const handleMessage = useCallback((connectionId: number, raw: unknown) => {
    if (connectionIdRef.current !== connectionId) return;
    let message: Record<string, unknown>;
    try {
      const parsedMessage: unknown = typeof raw === "string" ? JSON.parse(raw) : raw;
      if (!parsedMessage || typeof parsedMessage !== "object") return;
      message = parsedMessage as Record<string, unknown>;
    } catch {
      return;
    }
    const type = String(message.type ?? "");
    if (type === "welcome") {
      setState((current) => ({ ...current, playerId: asString(message.playerId), message: "大厅已连接，创建或加入房间。" }));
      return;
    }
    if (type === "queue_joined") {
      const format: PvpFormat = message.format === "casual" ? "casual" : "ranked";
      const rankedFormat: RankedFormat = message.rankedFormat === "wild" ? "wild" : "standard";
      const matchPool: ApprenticeMatchPool | null = message.pool === "apprentice"
        ? "apprentice"
        : message.pool === "standard"
          ? "standard"
          : null;
      setState((current) => ({ ...current, status: "queue", roomCode: null, role: null, format, rankedFormat, matchPool: matchPool ?? current.matchPool, matchQuality: null, peerName: null, localReady: false, remoteReady: false, remoteReadyDeck: null, message: asString(message.message, "正在按隐藏水平寻找对手…") }));
      return;
    }
    if (type === "queue_left") {
      setState((current) => ({ ...current, status: "connected", roomCode: null, role: null, matchPool: null, matchQuality: null, peerName: null, message: asString(message.message, "已取消匹配。") }));
      return;
    }
    if (type === "room_created" || type === "room_joined") {
      const roomCode = asString(message.room);
      const format: PvpFormat = message.format === "casual" ? "casual" : "ranked";
      const rankedFormat: RankedFormat = message.rankedFormat === "wild" ? "wild" : "standard";
      const matchPool: ApprenticeMatchPool | null = message.pool === "apprentice"
        ? "apprentice"
        : message.pool === "standard"
          ? "standard"
          : null;
      const matchQuality: MatchQuality | null = message.matchQuality === "ideal" || message.matchQuality === "close" || message.matchQuality === "expanded"
        ? message.matchQuality
        : null;
      lastSequenceRef.current = 0;
      incomingQueueRef.current = [];
      setIncoming(null);
      setState((current) => ({
        ...current,
        status: "room",
        roomCode: roomCode || null,
        role: type === "room_created" ? "host" : "guest",
        format,
        rankedFormat,
        matchPool: matchPool ?? current.matchPool,
        matchQuality,
        localReady: false,
        remoteReady: false,
        remoteReadyDeck: null,
        message: asString(message.message, type === "room_created" ? "房间已创建，等待对手加入。" : "已加入房间，等待房主准备。"),
      }));
      return;
    }
    if (type === "peer_joined") {
      setState((current) => ({ ...current, peerName: asString(message.peerName, "对手"), status: "room", message: `${asString(message.peerName, "对手")} 已加入房间。` }));
      return;
    }
    if (type === "peer_left") {
      setState((current) => ({ ...current, peerName: null, remoteReady: false, remoteReadyDeck: null, status: "room", message: "对手已离开房间。" }));
      return;
    }
    if (type === "room_state") {
      const payload = message.payload;
      const players = payload && typeof payload === "object" && Array.isArray((payload as Record<string, unknown>).players)
        ? (payload as { players: Array<Record<string, unknown>> }).players
        : [];
      setState((current) => {
        const nextFormat: PvpFormat = payload && typeof payload === "object" && (payload as Record<string, unknown>).format === "casual" ? "casual" : current.format;
        const nextRankedFormat: RankedFormat = payload && typeof payload === "object" && (payload as Record<string, unknown>).rankedFormat === "wild" ? "wild" : current.rankedFormat;
        const peer = players.find((player) => asString(player.id) !== current.playerId);
        return peer
          ? { ...current, format: nextFormat, rankedFormat: nextRankedFormat, peerName: asString(peer.name, "对手"), status: current.localReady ? "ready" : "room" }
          : current;
      });
      return;
    }
    if (type === "error") {
      setState((current) => ({ ...current, status: "error", message: asString(message.message, "联机大厅返回错误。") }));
      return;
    }
    if (type === "action_rejected") {
      const rejection = asString(message.message, "服务器拒绝了这条指令。");
      setState((current) => ({ ...current, message: rejection }));
      enqueueIncoming({
        id: ++incomingIdRef.current,
        type: "rejected",
        message: rejection,
        ...(message.resync === true ? { resync: true } : {}),
      });
      return;
    }
    if (type === "match_sync") {
      const payload = message.payload;
      const state = payload && typeof payload === "object" ? (payload as Record<string, unknown>).state : null;
      if (!state || typeof state !== "object" || !Array.isArray((state as Record<string, unknown>).players)) return;
      const matchToken = payload && typeof payload === "object" ? asString((payload as Record<string, unknown>).matchToken) : "";
      const format: PvpFormat = payload && typeof payload === "object" && (payload as Record<string, unknown>).format === "casual" ? "casual" : "ranked";
      const rankedFormat: RankedFormat = payload && typeof payload === "object" && (payload as Record<string, unknown>).rankedFormat === "wild" ? "wild" : "standard";
      setState((current) => ({ ...current, format, rankedFormat, status: "playing", message: "已恢复联机对局状态。" }));
      enqueueIncoming({ id: ++incomingIdRef.current, type: "match-sync", payload: { state: state as MatchState, format, rankedFormat, ...(matchToken ? { matchToken } : {}) } });
      return;
    }
    if (type !== "action") return;
    const sequence = Number(message.sequence);
    if (Number.isFinite(sequence)) {
      if (sequence <= lastSequenceRef.current) return;
      lastSequenceRef.current = sequence;
    }
    const action = asString(message.action);
    const payload = message.payload && typeof message.payload === "object" ? message.payload as Record<string, unknown> : {};
    if (action === "ready") {
      const remoteDeck = Array.isArray(payload.deckIds) ? payload.deckIds.map(String) : [];
      setState((current) => ({ ...current, remoteReady: true, remoteReadyDeck: remoteDeck, status: current.localReady ? "ready" : current.status, message: `${asString(message.peerName, "对手")} 已准备。` }));
      return;
    }
    if (action === "match_start") {
      const deck = Array.isArray(payload.deck)
        ? payload.deck.map(String)
        : undefined;
      const decks = Array.isArray(payload.decks) && payload.decks.length === 2
        ? payload.decks.map((deck) => Array.isArray(deck) ? deck.map(String) : []) as [string[], string[]]
        : null;
      const seed = Number(payload.seed);
      if ((!deck && !decks) || !Number.isFinite(seed)) return;
      const startingPlayer: 0 | 1 = payload.startingPlayer === 1 ? 1 : 0;
      const format: PvpFormat = payload.format === "casual" ? "casual" : "ranked";
      const rankedFormat: RankedFormat = payload.rankedFormat === "wild" ? "wild" : "standard";
      setState((current) => ({ ...current, format, rankedFormat, status: "playing", message: "双方已准备，联机演算开始。" }));
      const matchToken = asString(payload.matchToken);
      enqueueIncoming({
        id: ++incomingIdRef.current,
        type: "match-start",
        payload: {
          seed,
          startingPlayer,
          format,
          rankedFormat,
          ...(deck ? { deck } : { decks: decks as [string[], string[]] }),
          ...(matchToken ? { matchToken } : {}),
        },
      });
      return;
    }
    if (action === "rematch") {
      setState((current) => ({
        ...current,
        status: "room",
        localReady: false,
        remoteReady: false,
        remoteReadyDeck: null,
        message: "本局已结束，可以重新准备下一局。",
      }));
      enqueueIncoming({ id: ++incomingIdRef.current, type: "room-reset" });
      return;
    }
    if (action === "command") {
      const command = payload.command;
      if (!command || typeof command !== "object" || typeof (command as Record<string, unknown>).type !== "string") return;
      const authoritativeState = payload.state && typeof payload.state === "object" && Array.isArray((payload.state as Record<string, unknown>).players)
        ? payload.state as MatchState
        : undefined;
      const matchToken = asString(payload.matchToken);
      enqueueIncoming({
        id: ++incomingIdRef.current,
        type: "command",
        command: command as BattleCommand,
        ...(authoritativeState ? { state: authoritativeState } : {}),
        ...(matchToken ? { matchToken } : {}),
      });
    }
  }, [enqueueIncoming]);

  const stopPolling = useCallback((leaveRoom = true) => {
    if (pollTimerRef.current !== null) {
      window.clearInterval(pollTimerRef.current);
      pollTimerRef.current = null;
    }
    const clientId = pollClientRef.current;
    const endpoint = pollEndpointRef.current;
    pollClientRef.current = null;
    pollEndpointRef.current = null;
    pollCursorRef.current = 0;
    pollInFlightRef.current = false;
    pollSendTailRef.current = Promise.resolve();
    if (leaveRoom && clientId && endpoint) {
      void fetch(`${endpoint}?clientId=${encodeURIComponent(clientId)}`, { method: "DELETE", keepalive: true }).catch(() => undefined);
    }
    incomingQueueRef.current = [];
    lastSequenceRef.current = 0;
  }, []);

  const disconnect = useCallback((message = "已离开联机大厅。") => {
    connectionIdRef.current += 1;
    fallbackStartedRef.current = null;
    if (fallbackTimerRef.current !== null) {
      window.clearTimeout(fallbackTimerRef.current);
      fallbackTimerRef.current = null;
    }
    transportRef.current = null;
    stopPolling(true);
    const socket = socketRef.current;
    socketRef.current = null;
    if (socket && socket.readyState !== WebSocket.CLOSED) socket.close();
    setIncoming(null);
    setState((current) => ({
      ...current,
      status: "offline",
      playerId: null,
      roomCode: null,
      role: null,
      format: "ranked",
      rankedFormat: "standard",
      matchPool: null,
      matchQuality: null,
      peerName: null,
      localReady: false,
      remoteReady: false,
      remoteReadyDeck: null,
      message,
    }));
  }, [stopPolling]);

  const startPolling = useCallback(async (rawUrl: string, connectionId: number) => {
    if (connectionIdRef.current !== connectionId || fallbackStartedRef.current !== connectionId) return;
    const parsed = new URL(rawUrl);
    const protocol = parsed.protocol === "wss:" ? "https:" : "http:";
    const endpoint = `${protocol}//${parsed.host}/api/pvp-poll`;
    transportRef.current = "poll";
    socketRef.current = null;
    pollEndpointRef.current = endpoint;
    try {
      const response = await fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          type: "connect",
          name: displayName || "旅者",
          clientId: (() => {
            if (pollResumeClientRef.current) return pollResumeClientRef.current;
            const storageKey = "astra-protocol:pvp-session:v1";
            let value = typeof window !== "undefined" ? window.sessionStorage.getItem(storageKey) : null;
            if (!value) {
              value = makeId("poll");
              if (typeof window !== "undefined") window.sessionStorage.setItem(storageKey, value);
            }
            pollResumeClientRef.current = value;
            return value;
          })(),
        }),
      });
      const payload = await response.json() as Record<string, unknown>;
      if (!response.ok || payload.ok !== true || typeof payload.clientId !== "string") {
        throw new Error(asString(payload.message, "联机大厅连接失败。"));
      }
      if (connectionIdRef.current !== connectionId || transportRef.current !== "poll") return;
      pollClientRef.current = payload.clientId;
      pollCursorRef.current = Number(payload.cursor) || 0;
      setState((current) => ({ ...current, status: "connected", url: rawUrl, message: "大厅已连接（HTTP 兼容模式），创建或加入房间。" }));
      if (Array.isArray(payload.messages)) payload.messages.forEach((message) => handleMessage(connectionId, message));
      const pollOnce = async () => {
        const clientId = pollClientRef.current;
        if (!clientId || pollInFlightRef.current || connectionIdRef.current !== connectionId || transportRef.current !== "poll") return;
        pollInFlightRef.current = true;
        try {
          const result = await fetch(`${endpoint}?clientId=${encodeURIComponent(clientId)}&cursor=${pollCursorRef.current}`, { cache: "no-store" });
          const next = await result.json() as Record<string, unknown>;
          if (!result.ok || next.ok !== true) {
            throw new Error(asString(next.message, "联机会话已过期。"));
          }
          pollCursorRef.current = Number(next.cursor) || pollCursorRef.current;
          if (Array.isArray(next.messages)) next.messages.forEach((message) => handleMessage(connectionId, message));
        } catch (error) {
          if (connectionIdRef.current === connectionId && transportRef.current === "poll") {
            transportRef.current = null;
            stopPolling(false);
            setState((current) => ({
              ...current,
              status: "error",
              message: error instanceof Error && error.message
                ? error.message
                : "联机大厅连接已断开，请重新连接。",
            }));
          }
        } finally {
          pollInFlightRef.current = false;
        }
      };
      pollTimerRef.current = window.setInterval(() => void pollOnce(), 700);
    } catch (error) {
      if (connectionIdRef.current !== connectionId) return;
      transportRef.current = null;
      stopPolling(false);
      setState((current) => ({
        ...current,
        status: "error",
        message: error instanceof Error && error.message
          ? error.message
          : "联机大厅连接失败，请稍后重试。",
      }));
    }
  }, [displayName, handleMessage, stopPolling]);

  const canFallbackToPolling = useCallback((parsed: URL) => {
    const isLocal = parsed.hostname === "localhost" || parsed.hostname === "127.0.0.1";
    return !isLocal && parsed.pathname === "/api/pvp";
  }, []);

  const tryStartPolling = useCallback((rawUrl: string, parsed: URL, connectionId: number) => {
    if (!canFallbackToPolling(parsed) || fallbackStartedRef.current === connectionId) return;
    fallbackStartedRef.current = connectionId;
    void startPolling(rawUrl, connectionId);
  }, [canFallbackToPolling, startPolling]);

  const connect = useCallback((rawUrl: string) => {
    const url = rawUrl.trim();
    let parsed: URL;
    try {
      parsed = new URL(url);
    } catch {
      setState((current) => ({ ...current, status: "error", message: "联机地址格式不正确。" }));
      return;
    }
    if (parsed.protocol !== "ws:" && parsed.protocol !== "wss:") {
      setState((current) => ({ ...current, status: "error", message: "联机地址必须使用 ws:// 或 wss://。" }));
      return;
    }

    disconnect("正在连接联机大厅…");
    const connectionId = connectionIdRef.current + 1;
    connectionIdRef.current = connectionId;
    transportRef.current = "websocket";
    fallbackStartedRef.current = null;
    setState((current) => ({
      ...current,
      status: "connecting",
      url,
      message: "正在连接联机大厅…",
    }));
    // The hosted Worker can route consecutive HTTP requests to different edge
    // isolates. Use the D1-backed polling transport in production so room
    // membership and messages are shared across browsers and devices. Keep
    // WebSocket for local development where the in-memory server is stable.
    if (canFallbackToPolling(parsed)) {
      transportRef.current = null;
      fallbackStartedRef.current = connectionId;
      void startPolling(url, connectionId);
      return;
    }
    const socket = new WebSocket(parsed.toString());
    socketRef.current = socket;
    socket.onopen = () => {
      if (connectionIdRef.current !== connectionId) return;
      if (fallbackTimerRef.current !== null) {
        window.clearTimeout(fallbackTimerRef.current);
        fallbackTimerRef.current = null;
      }
      if (transportRef.current !== "websocket") return;
      socket.send(JSON.stringify({ type: "hello", name: displayName || "旅者" }));
      setState((current) => ({ ...current, status: "connected", message: "大厅已连接，创建或加入房间。" }));
    };
    socket.onmessage = (event) => {
      handleMessage(connectionId, event.data);
    };
    socket.onerror = () => {
      if (connectionIdRef.current !== connectionId) return;
      if (canFallbackToPolling(parsed)) {
        setState((current) => ({ ...current, message: "WebSocket 不可用，正在切换兼容联机模式…" }));
        tryStartPolling(url, parsed, connectionId);
      } else {
        setState((current) => ({ ...current, status: "error", message: "联机大厅连接失败，请确认房间服务器地址。" }));
      }
    };
    socket.onclose = () => {
      if (connectionIdRef.current !== connectionId) return;
      if (transportRef.current !== "websocket") return;
      if (canFallbackToPolling(parsed)) {
        tryStartPolling(url, parsed, connectionId);
        return;
      }
      socketRef.current = null;
      setState((current) => ({ ...current, status: "offline", roomCode: null, role: null, format: "ranked", rankedFormat: "standard", matchPool: null, matchQuality: null, peerName: null, localReady: false, remoteReady: false, remoteReadyDeck: null, message: "联机大厅连接已断开。" }));
    };
    if (canFallbackToPolling(parsed)) {
      fallbackTimerRef.current = window.setTimeout(() => {
        fallbackTimerRef.current = null;
        if (connectionIdRef.current === connectionId && transportRef.current === "websocket" && socket.readyState !== WebSocket.OPEN) {
          tryStartPolling(url, parsed, connectionId);
          socket.close();
        }
      }, 1800);
    }
  }, [canFallbackToPolling, disconnect, displayName, handleMessage, startPolling, tryStartPolling]);

  const send = useCallback((message: Record<string, unknown>) => {
    if (transportRef.current === "poll") {
      const clientId = pollClientRef.current;
      const endpoint = pollEndpointRef.current;
      if (!clientId || !endpoint) {
        setState((current) => ({ ...current, status: "error", message: "联机连接尚未就绪。" }));
        return false;
      }
      const connectionId = connectionIdRef.current;
      const submit = async () => {
        if (
          connectionIdRef.current !== connectionId ||
          transportRef.current !== "poll" ||
          pollClientRef.current !== clientId ||
          pollEndpointRef.current !== endpoint
        ) return;
        try {
          const response = await fetch(endpoint, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ clientId, type: "message", message }),
          });
          const payload = await response.json().catch(() => ({})) as Record<string, unknown>;
          if (!response.ok || payload.ok !== true) {
            throw new Error(asString(payload.message, "服务器未接受这条联机指令。"));
          }
        } catch (error) {
          if (
            connectionIdRef.current !== connectionId ||
            transportRef.current !== "poll" ||
            pollClientRef.current !== clientId
          ) return;
          const failure = error instanceof Error && error.message
            ? error.message
            : "联机指令发送失败，请重试。";
          const isReady = message.type === "action" && message.action === "ready";
          setState((current) => ({
            ...current,
            localReady: isReady ? false : current.localReady,
            status: isReady && current.roomCode ? "room" : current.status,
            message: failure,
          }));
          enqueueIncoming({
            id: ++incomingIdRef.current,
            type: "rejected",
            message: failure,
            resync: true,
          });
        }
      };
      // `submit` contains its own error handling, so a failed request cannot
      // poison the tail and prevent later retry/sync messages from running.
      pollSendTailRef.current = pollSendTailRef.current.then(submit, submit);
      return true;
    }
    const socket = socketRef.current;
    if (!socket || socket.readyState !== WebSocket.OPEN) {
      setState((current) => ({ ...current, status: "error", message: "联机连接尚未就绪。" }));
      return false;
    }
    socket.send(JSON.stringify(message));
    return true;
  }, [enqueueIncoming]);

  const createRoom = useCallback((format: PvpFormat = "ranked", rankedFormat: RankedFormat = "standard") => {
    send({ type: "create_room", format, rankedFormat });
  }, [send]);

  const queue = useCallback((format: PvpFormat = "ranked", rankedFormat: RankedFormat = "standard") => {
    send({ type: "queue_join", format, rankedFormat });
  }, [send]);

  const leaveQueue = useCallback(() => {
    send({ type: "queue_leave" });
  }, [send]);

  const joinRoom = useCallback((roomCode: string) => {
    const room = roomCode.trim().toUpperCase();
    if (!/^[A-Z]{4}$/.test(room)) {
      setState((current) => ({ ...current, status: "error", message: "房间码必须是 4 位字母。" }));
      return;
    }
    send({ type: "join_room", room });
  }, [send]);

  const ready = useCallback((deckIds: string[]) => {
    if (send({ type: "action", action: "ready", payload: { deckIds } })) {
      setState((current) => ({ ...current, localReady: true, status: current.remoteReady ? "ready" : "ready", message: "你已准备，等待对手确认。" }));
    }
  }, [send]);

  const sendMatchStart = useCallback((payload: { decks: [string[], string[]] }) => {
    if (send({ type: "action", action: "match_start", payload })) {
      setState((current) => ({ ...current, status: "ready", message: "已提交开局请求，等待服务器确认。" }));
    }
  }, [send]);

  const sendCommand = useCallback((command: BattleCommand) => {
    return send({ type: "action", action: "command", payload: { command } });
  }, [send]);

  const requestRematch = useCallback(() => {
    if (state.role !== "host" || state.status === "offline" || !state.roomCode) return false;
    return send({ type: "action", action: "rematch", payload: {} });
  }, [send, state.role, state.roomCode, state.status]);

  const syncRoom = useCallback(() => {
    return send({ type: "sync" });
  }, [send]);

  const dispose = useCallback(() => {
    connectionIdRef.current += 1;
    fallbackStartedRef.current = null;
    if (fallbackTimerRef.current !== null) {
      window.clearTimeout(fallbackTimerRef.current);
      fallbackTimerRef.current = null;
    }
    transportRef.current = null;
    // Do not DELETE the D1 session during page teardown. The next page load
    // reuses the opaque session id and restores the room membership.
    stopPolling(false);
    const socket = socketRef.current;
    socketRef.current = null;
    if (socket && socket.readyState !== WebSocket.CLOSED) socket.close();
  }, [stopPolling]);

  useEffect(() => () => dispose(), [dispose]);

  return { state, incoming, acknowledgeIncoming, connect, disconnect, createRoom, queue, leaveQueue, joinRoom, ready, sendMatchStart, sendCommand, requestRematch, syncRoom };
}

export function GameApp({
  identity,
}: {
  identity?: {
    displayName: string;
    email: string;
    authenticated: boolean;
  };
}) {
  const [section, setSection] = useState<SectionKey>("overview");
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [player, setPlayer] = useState<PlayerSnapshot>(() => makeDemoPlayer(identity));
  const [profileSource, setProfileSource] = useState<ProfileSource>(
    identity?.authenticated ? "cloud" : "demo",
  );
  const [canLinkDevice, setCanLinkDevice] = useState(false);
  const isDemo = profileSource === "demo";
  const profileNodeLabel =
    profileSource === "cloud"
      ? "云端节点在线"
      : profileSource === "device"
        ? "本机节点在线"
      : profileSource === "cached"
        ? "本地缓存在线"
        : "演示节点在线";
  const profileStatusLabel =
    profileSource === "cloud"
      ? "已同步指挥官"
      : profileSource === "device"
        ? "访客档案已保存"
      : profileSource === "cached"
        ? "离线缓存档案"
        : "本地演示档案";
  const [loading, setLoading] = useState(true);
  const [apiBusy, setApiBusy] = useState<string | null>(null);
  const [notice, setNotice] = useState<{ tone: "info" | "success" | "warning"; text: string } | null>(
    null,
  );
  const [openedCards, setOpenedCards] = useState<Array<{ cardId: string; count: number }>>([]);
  const [search, setSearch] = useState("");
  const [factionFilter, setFactionFilter] = useState("全部");
  const [typeFilter, setTypeFilter] = useState("全部");
  const [rarityFilter, setRarityFilter] = useState("全部");
  const [traitFilter, setTraitFilter] = useState("全部");
  const [keywordFilter, setKeywordFilter] = useState("全部");
  const [minionTypeFilter, setMinionTypeFilter] = useState("全部");
  const [spellSchoolFilter, setSpellSchoolFilter] = useState("全部");
  const [deckName, setDeckName] = useState("星火远征队");
  const [deckFormat, setDeckFormat] = useState<RankedFormat>("standard");
  const [deckIds, setDeckIds] = useState<string[]>(() => [...STARTER_IDS]);
  const [editingDeckId, setEditingDeckId] = useState<string | null>(null);
  const [selectedLadderReadyDeckId, setSelectedLadderReadyDeckId] = useState<LadderReadyDeckId | null>(null);
  const [battle, setBattle] = useState<unknown>(null);
  const [inspectedCard, setInspectedCard] = useState<CatalogCard | null>(null);
  const [selectedAttacker, setSelectedAttacker] = useState<string | null>(null);
  const [pendingCard, setPendingCard] = useState<BattleSide["hand"][number] | null>(null);
  const [pendingCardPlacement, setPendingCardPlacement] = useState<"friendly" | "enemy">("friendly");
  const [pendingHeroPower, setPendingHeroPower] = useState(false);
  const [mulliganSelection, setMulliganSelection] = useState<number[]>([]);
  const [battleMessage, setBattleMessage] = useState("准备部署你的战术卡组。");
  const [battleEffect, setBattleEffect] = useState<BattleVisualEffect | null>(null);
  const [battleEffectCount, setBattleEffectCount] = useState(0);
  const [battleEffectsLocked, setBattleEffectsLocked] = useState(false);
  const [battleReplaySlow, setBattleReplaySlow] = useState(false);
  const [battleTurnClockSeconds, setBattleTurnClockSeconds] = useState<number | null>(null);
  const [trainingBriefingOpen, setTrainingBriefingOpen] = useState(false);
  const [trainingActive, setTrainingActive] = useState(false);
  const recordedBattleRef = useRef<string | null>(null);
  const aiMatchProofRef = useRef<AiMatchProofPayload | null>(null);
  const aiMatchStartingRef = useRef(false);
  const aiCommandTranscriptRef = useRef<BattleCommand[]>([]);
  const sectionRef = useRef<SectionKey>("overview");
  const battleEffectQueueRef = useRef<BattleVisualEffect[]>([]);
  const battleEffectTimerRef = useRef<number | null>(null);
  const battleEffectDrainingRef = useRef(false);
  const battleEffectLockRef = useRef(false);
  const aiReplayActiveRef = useRef(false);
  const aiReplayCompletionMessageRef = useRef<string | null>(null);
  const battleEffectSequenceRef = useRef(0);
  const battleReplaySlowRef = useRef(false);
  const aiReplayFinalStateRef = useRef<MatchState | null>(null);
  const aiTurnTimerRef = useRef<number | null>(null);
  const aiTurnGenerationRef = useRef(0);
  const mulliganSubmissionRef = useRef(false);
  const turnTimeoutHandledRef = useRef<number | null>(null);
  const declinedClipboardDeckCodeRef = useRef<string | null>(null);
  const endTurnRef = useRef<() => void>(() => undefined);
  const { soundEnabled, unlockAudio, playSound, toggleSound } = useBattleAudio();
  const pvp = useWebPvp(player.displayName);
  const [pvpUrl, setPvpUrl] = useState(() => getDefaultPvpUrl());
  const [pvpRoomInput, setPvpRoomInput] = useState("");
  const [onlineMatch, setOnlineMatch] = useState(false);
  const [onlineOpponent, setOnlineOpponent] = useState<string | null>(null);
  const [aiArchetypeId, setAiArchetypeId] = useState(AI_ARCHETYPES[0]?.id ?? "tide-control");
  const onlineStartSentRef = useRef(false);
  const pvpMatchTokenRef = useRef<string | null>(null);
  // Keep the seat assigned when this match began. Room ownership can move to
  // the guest after the original host leaves, but an archived match token
  // continues to identify that guest as player 1 for orientation/settlement.
  const pvpMatchPlayerRef = useRef<0 | 1 | null>(null);
  const pendingPvpCommandRef = useRef(false);
  const pvpEventCursorRef = useRef(0);

  const stopBattleEffects = useCallback(() => {
    if (battleEffectTimerRef.current !== null) {
      window.clearTimeout(battleEffectTimerRef.current);
      battleEffectTimerRef.current = null;
    }
    battleEffectQueueRef.current = [];
    battleEffectDrainingRef.current = false;
    battleEffectLockRef.current = false;
    aiReplayActiveRef.current = false;
    aiReplayCompletionMessageRef.current = null;
    setBattleEffect(null);
    setBattleEffectCount(0);
    setBattleEffectsLocked(false);
  }, []);

  const skipBattleReplay = useCallback(() => {
    aiTurnGenerationRef.current += 1;
    if (aiTurnTimerRef.current !== null) {
      window.clearTimeout(aiTurnTimerRef.current);
      aiTurnTimerRef.current = null;
    }
    const finalState = aiReplayFinalStateRef.current;
    aiReplayFinalStateRef.current = null;
    aiReplayCompletionMessageRef.current = null;
    if (finalState) {
      setBattle(finalState);
    }
    stopBattleEffects();
    if (finalState) {
      setBattleMessage(
        finalState.phase === "game-over"
          ? "敌方行动已结束，演算结果已锁定。"
          : "敌方行动回放已跳过，新的能量窗口已开启。",
      );
    }
  }, [stopBattleEffects]);

  const drainBattleEffects = useCallback(() => {
    if (battleEffectDrainingRef.current) return;
    battleEffectDrainingRef.current = true;

    const playNext = () => {
      const next = battleEffectQueueRef.current.shift();
      if (!next) {
        battleEffectDrainingRef.current = false;
        battleEffectTimerRef.current = null;
        if (battleEffectLockRef.current && !aiReplayActiveRef.current) {
          battleEffectLockRef.current = false;
          setBattleEffectsLocked(false);
          const completionMessage = aiReplayCompletionMessageRef.current;
          aiReplayCompletionMessageRef.current = null;
          if (completionMessage) setBattleMessage(completionMessage);
        }
        setBattleEffect(null);
        setBattleEffectCount(0);
        return;
      }

      setBattleEffect(next);
      setBattleEffectCount(battleEffectQueueRef.current.length);
      playSound(next.kind);
      battleEffectTimerRef.current = window.setTimeout(
        playNext,
        battleReplaySlowRef.current ? BATTLE_EFFECT_SLOW_STEP_MS : BATTLE_EFFECT_STANDARD_STEP_MS,
      );
    };

    playNext();
  }, [playSound]);

  const showBattleEffects = useCallback(
    (
      effects: readonly BattleVisualEffect[],
      options: { lock?: boolean; maxEffects?: number; reset?: boolean } = {},
    ) => {
      if (options.reset) {
        stopBattleEffects();
      }
      const maxEffects = options.maxEffects ?? BATTLE_EFFECT_QUEUE_LIMIT;
      // Event order is part of the rules. Never reorder a deathrattle or
      // secret chain merely to surface a visually important effect first.
      // Normal reducer transitions fit well below this cap; the final event is
      // retained for pathological snapshots so a terminal result is never
      // hidden behind a truncated middle section.
      const playlist = effects.length <= maxEffects
        ? [...effects]
        : [
            ...effects.slice(0, Math.max(0, maxEffects - 1)),
            ...(effects.at(-1) ? [effects.at(-1)!] : []),
          ];
      const capacity = Math.max(0, BATTLE_EFFECT_QUEUE_LIMIT - battleEffectQueueRef.current.length);
      const incoming = playlist.slice(0, capacity);
      const terminalEffect = playlist.at(-1);
      if (
        capacity > 0 &&
        terminalEffect &&
        (terminalEffect.kind === "win" || terminalEffect.kind === "loss") &&
        !incoming.some((effect) => effect.id === terminalEffect.id)
      ) {
        incoming[incoming.length - 1] = terminalEffect;
      }
      battleEffectQueueRef.current.push(...incoming);
      setBattleEffectCount(battleEffectQueueRef.current.length);

      if (options.lock) {
        battleEffectLockRef.current = true;
        setBattleEffectsLocked(true);
      }
      drainBattleEffects();
    },
    [drainBattleEffects, stopBattleEffects],
  );

  const toggleBattleReplaySpeed = useCallback(() => {
    const next = !battleReplaySlowRef.current;
    battleReplaySlowRef.current = next;
    setBattleReplaySlow(next);
    setBattleMessage(next ? "已切换为慢速回放，每个战斗事件停留更久。" : "已切换为标准回放。");
  }, []);

  useEffect(
    () => () => {
      aiTurnGenerationRef.current += 1;
      if (battleEffectTimerRef.current !== null) {
        window.clearTimeout(battleEffectTimerRef.current);
      }
      if (aiTurnTimerRef.current !== null) {
        window.clearTimeout(aiTurnTimerRef.current);
      }
    },
    [],
  );

  useEffect(() => {
    let active = true;
    async function hydrate() {
      try {
        const response = await fetch("/api/game", {
          method: "GET",
          headers: { Accept: "application/json" },
        });
        const payload = (await response.json()) as GamePayload | { ok: false };
        if (!response.ok || !payload.ok) throw new Error("无法读取玩家档案");
        if (!active) return;
        setPlayer(payload.player);
        const nextSource: ProfileSource = payload.identity?.isDemo
          ? "demo"
          : payload.identity?.isAnonymous
            ? "device"
            : "cloud";
        setProfileSource(nextSource);
        setCanLinkDevice(Boolean(payload.identity?.canLinkDevice));
        if (nextSource !== "cloud") persistLocalPlayer(payload.player);
        const firstDeck =
          payload.player.decks.find((deck) => deck.id === payload.player.activeDeckId) ??
          payload.player.decks[0];
        if (firstDeck) {
          setEditingDeckId(firstDeck.id);
          setDeckIds([...firstDeck.cardIds]);
          setDeckName(firstDeck.name);
          setDeckFormat(firstDeck.format ?? "standard");
        }
      } catch {
        if (!active) return;
        const email = identity?.email ?? "pilot@ember-protocol.local";
        const cached = readLocalPlayer(email);
        if (cached) {
          setPlayer(cached);
          setProfileSource(identity?.authenticated ? "cached" : "demo");
          const firstDeck =
            cached.decks.find((deck) => deck.id === cached.activeDeckId) ?? cached.decks[0];
          if (firstDeck) {
            setEditingDeckId(firstDeck.id);
            setDeckIds([...firstDeck.cardIds]);
            setDeckName(firstDeck.name);
            setDeckFormat(firstDeck.format ?? "standard");
          }
          setNotice({
            tone: "warning",
            text: identity?.authenticated
              ? "云端档案暂不可用，已载入本机缓存；恢复连接后再继续同步。"
              : "云端指挥链暂不可用，已载入本机演示档案。刷新页面不会丢失进度。",
          });
        } else {
          setProfileSource(identity?.authenticated ? "cached" : "demo");
          setNotice({
            tone: "warning",
            text: identity?.authenticated
              ? "云端档案暂不可用，当前使用本机临时档案。"
              : "云端指挥链暂不可用，已切换到本地演示档案。刷新后会保留本机进度。",
          });
          // Never seed an authenticated account's cache with the initial demo
          // state: that can overwrite a later cloud recovery on refresh.
          if (!identity?.authenticated) persistLocalPlayer(player);
        }
      } finally {
        if (active) setLoading(false);
      }
    }
    void hydrate();
    return () => {
      active = false;
    };
  // This is a one-time archive hydration; later mutations update state directly.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const postAction = useCallback(
    async (
      action: string,
      body: Record<string, unknown>,
    ): Promise<GamePayload | null> => {
      // A cached authenticated profile is deliberately read-only. Mutating it
      // locally would make the next successful sync overwrite the real cloud
      // account, which is especially dangerous for decks, rewards, and match
      // history. Keep the UI usable for browsing and local battles, but make
      // the sync boundary explicit until the profile can be reloaded.
      if (identity?.authenticated && profileSource === "cached") {
        setNotice({
          tone: "warning",
          text: "当前为云端档案的只读缓存，暂不能保存卡组、领取奖励或归档战绩；请恢复连接后重试。",
        });
        return null;
      }
      setApiBusy(action);
      let allowLocalFallback = true;
      try {
        const response = await fetch("/api/game", {
          method: "POST",
          headers: { "Content-Type": "application/json", Accept: "application/json" },
          body: JSON.stringify({ action, ...body }),
        });
        allowLocalFallback = response.status >= 500;
        const payload = (await response.json()) as
          | GamePayload
          | { ok: false; error?: { message?: string } };
        if (!response.ok || !payload.ok) {
          throw new Error(
            "error" in payload && payload.error?.message
              ? payload.error.message
              : "指挥请求未能完成",
          );
        }
        setPlayer(payload.player);
        if (profileSource !== "cloud" || payload.localFallback) {
          persistLocalPlayer(payload.player);
        }
        return payload;
      } catch (error) {
        // Authenticated profiles must remain cloud-authoritative. Applying a
        // local reward or deck mutation after a 5xx would create a divergent
        // account that can overwrite the real profile on a later retry.
        const isUnverifiedPvpResult = action === "record_match" && body.mode === "pvp";
        if (allowLocalFallback && !identity?.authenticated && !isUnverifiedPvpResult) {
          const localPayload = applyLocalAction(player, action, body);
          setPlayer(localPayload.player);
          setProfileSource(identity?.authenticated ? "cached" : "demo");
          persistLocalPlayer(localPayload.player);
          return localPayload;
        }
        setNotice({
          tone: "warning",
          text:
            error instanceof Error
              ? error.message
              : "请求失败，请稍后再试。",
        });
        return null;
      } finally {
        setApiBusy(null);
      }
    },
    [identity?.authenticated, player, profileSource],
  );

  const deckCounts = useMemo(() => {
    const counts = new Map<string, number>();
    deckIds.forEach((id) => counts.set(id, (counts.get(id) ?? 0) + 1));
    return counts;
  }, [deckIds]);

  const deckValidation = useMemo(() => {
    try {
      const raw = validateDeckForFormat(deckIds, deckFormat);
      const normalized = validationFromRaw(raw);
      if (deckIds.length !== 30) {
        return {
          valid: false,
          errors: [
            `卡组必须恰好为 30 张（当前 ${deckIds.length} 张）`,
            ...normalized.errors.filter((error) => !error.includes("30")),
          ],
        };
      }
      return normalized;
    } catch {
      return {
        valid: false,
        errors: [`卡组必须恰好为 30 张（当前 ${deckIds.length} 张）`],
      };
    }
  }, [deckFormat, deckIds]);

  const deckMissingCards = useMemo(
    () => findMissingDeckCards(deckIds, player.collection),
    [deckIds, player.collection],
  );
  const deckPlayable = deckValidation.valid && (
    Boolean(selectedLadderReadyDeckId) || deckMissingCards.length === 0
  );

  const factions = useMemo(
    () => ["全部", ...Array.from(new Set(CATALOG.map((card) => card.faction)))],
    [],
  );

  const traitOptions = useMemo(
    () => TRAIT_ORDER.map((trait) => ({
      id: trait,
      label: TRAIT_DEFINITIONS[trait].label,
    })),
    [],
  );

  const keywordOptions = useMemo(
    () => (Object.entries(KEYWORD_DEFINITIONS) as Array<[
      Keyword,
      (typeof KEYWORD_DEFINITIONS)[Keyword],
    ]>)
      .filter(([keyword]) => CATALOG.some((card) => card.keywords.includes(keyword)))
      .map(([id, definition]) => ({ id, label: definition.label })),
    [],
  );

  const minionTypeOptions = useMemo(
    () => MINION_TYPE_ORDER
      .filter((minionType) => CATALOG.some((card) => card.minionTypes.includes(minionType)))
      .map((minionType) => ({
        id: minionType,
        label: MINION_TYPE_DEFINITIONS[minionType].label,
      })),
    [],
  );

  const spellSchoolOptions = useMemo(
    () => SPELL_SCHOOL_ORDER
      .filter((school) => CATALOG.some((card) => card.school === school))
      .map((school) => ({ id: school, label: SPELL_SCHOOL_LABEL[school] })),
    [],
  );

  const filteredCards = useMemo(() => {
    const needle = search.trim().toLocaleLowerCase("zh-CN");
    const matches = CATALOG.filter((card) => {
      const matchesSearch =
        !needle ||
        card.name.toLocaleLowerCase("zh-CN").includes(needle) ||
        card.description.toLocaleLowerCase("zh-CN").includes(needle) ||
        card.minionTypes.some((minionType) =>
          MINION_TYPE_DEFINITIONS[minionType].label.toLocaleLowerCase("zh-CN").includes(needle),
        ) ||
        card.traits.some((trait) =>
          TRAIT_DEFINITIONS[trait].label.toLocaleLowerCase("zh-CN").includes(needle),
        ) ||
        card.keywords.some((keyword) =>
          KEYWORD_DEFINITIONS[keyword].label.toLocaleLowerCase("zh-CN").includes(needle),
        ) ||
        (card.school
          ? SPELL_SCHOOL_LABEL[card.school]
              .toLocaleLowerCase("zh-CN")
              .includes(needle)
          : false);
      return (
        matchesSearch &&
        (factionFilter === "全部" || card.faction === factionFilter) &&
        (typeFilter === "全部" || card.type === typeFilter) &&
        (rarityFilter === "全部" || card.rarity === rarityFilter) &&
        (minionTypeFilter === "全部" || hasMinionType(card.minionTypes, minionTypeFilter as MinionType)) &&
        (spellSchoolFilter === "全部" || card.school === spellSchoolFilter) &&
        (traitFilter === "全部" || card.traits.includes(traitFilter as Trait)) &&
        (keywordFilter === "全部" || card.keywords.includes(keywordFilter as Keyword))
      );
    });

    if (factionFilter !== "全部") return matches;

    const factionBuckets = FACTION_ORDER.map((faction) =>
      matches.filter((card) => card.faction === faction),
    );
    const longestBucket = Math.max(0, ...factionBuckets.map((cards) => cards.length));
    return Array.from({ length: longestBucket }, (_, index) =>
      factionBuckets.map((cards) => cards[index]).filter(Boolean),
    ).flat() as CatalogCard[];
  }, [factionFilter, keywordFilter, minionTypeFilter, rarityFilter, search, spellSchoolFilter, traitFilter, typeFilter]);

  const battleView = useMemo(() => battleFromRaw(battle), [battle]);
  const battleStatus = battleView?.status;
  const battleCurrentPlayer = battleView?.currentPlayer;
  const battleTurn = battleView?.turn;
  const hasBattleTurnClock = battleTurnClockSeconds !== null;
  const selectedAiArchetype = AI_ARCHETYPES.find((archetype) => archetype.id === aiArchetypeId) ?? AI_ARCHETYPES[0];

  const switchSection = (next: SectionKey) => {
    sectionRef.current = next;
    if (next !== "battle") {
      stopBattleEffects();
    }
    setSection(next);
    setSidebarOpen(false);
    if (typeof window !== "undefined") {
      window.scrollTo({ top: 0, behavior: "smooth" });
    }
  };

  const addCard = (card: CatalogCard) => {
    setSelectedLadderReadyDeckId(null);
    const owned = player.collection[card.id] ?? 0;
    const current = deckCounts.get(card.id) ?? 0;
    const limit = card.rarity === "legendary" ? 1 : 2;
    const definition = CARD_RULE_BY_ID.get(card.id);
    if (!definition || !cardAvailableInRankedFormat(definition, deckFormat)) {
      setNotice({ tone: "warning", text: `「${card.name}」已退出标准环境，请切换为狂野卡组。` });
      return;
    }
    if (deckIds.length >= 30) {
      setNotice({ tone: "warning", text: "卡组已满 30 张，请先移除一张卡牌。" });
      return;
    }
    if (current >= Math.min(limit, owned)) {
      setNotice({
        tone: "warning",
        text: owned < limit ? `你的收藏中只有 ${owned} 张「${card.name}」。` : `「${card.name}」已达到携带上限。`,
      });
      return;
    }
    setDeckIds((ids) => [...ids, card.id]);
  };

  const removeCard = (cardId: string) => {
    setSelectedLadderReadyDeckId(null);
    setDeckIds((ids) => {
      const index = ids.lastIndexOf(cardId);
      if (index < 0) return ids;
      return [...ids.slice(0, index), ...ids.slice(index + 1)];
    });
  };

  const autoCompleteDeck = () => {
    setSelectedLadderReadyDeckId(null);
    const completion = completeDeckFromCollection({
      cardIds: deckIds,
      collection: player.collection,
      format: deckFormat,
    });
    const added = completion.addedCardIds.length;
    if (added === 0) {
      setNotice({
        tone: "warning",
        text: "当前已选卡牌或收藏无法继续合法补全，请先移除冲突卡牌。",
      });
      return;
    }
    setDeckIds(completion.cardIds);
    const remaining = 30 - completion.cardIds.length;
    setNotice({
      tone: remaining === 0 ? "success" : "info",
      text: remaining === 0
        ? `智能补全已加入 ${added} 张收藏卡牌，并平衡费用曲线与协同。`
        : `已从收藏加入 ${added} 张卡牌；仍缺 ${remaining} 张可用卡牌。`,
    });
  };

  const applyDeckRecipe = (recipe: DeckRecipe) => {
    if (player.decks.length >= MAX_SAVED_DECKS) {
      setNotice({
        tone: "warning",
        text: `已使用全部 ${MAX_SAVED_DECKS} 个卡组栏位，请先删除一套再应用配方。`,
      });
      return;
    }
    const missing = findMissingDeckCards(recipe.cardIds, player.collection)
      .reduce((total, card) => total + card.missing, 0);
    setEditingDeckId(null);
    setSelectedLadderReadyDeckId(null);
    setDeckFormat(recipe.format);
    setDeckName(recipe.name);
    setDeckIds([...recipe.cardIds]);
    setNotice({
      tone: missing > 0 ? "info" : "success",
      text: missing > 0
        ? `已套用「${recipe.name}」草稿；缺少 ${missing} 张卡牌，可按建议逐张替换。`
        : `已套用「${recipe.name}」完整配方，可保存后投入演算。`,
    });
  };

  const saveDeck = async () => {
    if (selectedLadderReadyDeckId) {
      setNotice({ tone: "warning", text: "试玩套牌不能改写；永久领取后会自动加入已保存卡组。" });
      return;
    }
    if (!deckValidation.valid) {
      setNotice({ tone: "warning", text: deckValidation.errors[0] ?? "请先修正卡组规则错误。" });
      return;
    }
    if (deckMissingCards.length > 0) {
      const missingTotal = deckMissingCards.reduce((sum, item) => sum + item.missing, 0);
      setNotice({ tone: "warning", text: `还缺少 ${missingTotal} 张卡牌；请制作卡牌或使用替换建议后再保存。` });
      return;
    }
    const payload = await postAction("save_deck", {
      idempotencyKey: makeId("deck"),
      deck: {
        ...(editingDeckId ? { id: editingDeckId } : {}),
        name: deckName.trim() || "未命名卡组",
        cardIds: deckIds,
        format: deckFormat,
      },
    });
    if (payload) {
      if (payload.savedDeck) setEditingDeckId(payload.savedDeck.id);
      setNotice({
        tone: payload.localFallback ? "info" : "success",
        text: payload.localFallback
          ? "云端暂不可用，卡组已保存到本地演示档案。"
          : "卡组已加密保存，可立即投入演算。",
      });
    }
  };

  const deleteCurrentDeck = async () => {
    if (!editingDeckId || selectedLadderReadyDeckId) return;
    const existing = player.decks.find((deck) => deck.id === editingDeckId);
    if (!existing) return;
    if (
      typeof window !== "undefined" &&
      !window.confirm(`删除卡组「${existing.name}」？此操作不会分解或移除收藏中的卡牌。`)
    ) {
      return;
    }
    const payload = await postAction("delete_deck", {
      idempotencyKey: makeId(`delete-${editingDeckId}`),
      deckId: editingDeckId,
    });
    if (!payload) return;
    const nextDeck =
      payload.player.decks.find(
        (deck) => deck.id === payload.player.activeDeckId,
      ) ?? payload.player.decks[0];
    setSelectedLadderReadyDeckId(null);
    if (nextDeck) {
      setEditingDeckId(nextDeck.id);
      setDeckIds([...nextDeck.cardIds]);
      setDeckName(nextDeck.name);
      setDeckFormat(nextDeck.format ?? "standard");
    } else {
      setEditingDeckId(null);
      setDeckIds([...DEFAULT_STARTER_DECK]);
      setDeckName("新建战术卡组");
      setDeckFormat("standard");
    }
    setNotice({
      tone: payload.localFallback ? "info" : "success",
      text: `已删除「${existing.name}」，收藏中的卡牌保持不变。`,
    });
  };

  const importDeck = (code: string): boolean => {
    let decoded: ReturnType<typeof decodeDeckCode>;
    try {
      decoded = decodeDeckCode(code);
    } catch (error) {
      setNotice({
        tone: "warning",
        text: error instanceof Error ? error.message : "无法解析这段卡组代码。",
      });
      return false;
    }
    if (player.decks.length >= MAX_SAVED_DECKS) {
      setNotice({ tone: "warning", text: `已使用全部 ${MAX_SAVED_DECKS} 个卡组栏位，请先整理现有卡组。` });
      return false;
    }
    const format = decoded.format ?? deckFormat;
    const validation = validateDeckForFormat(decoded.cardIds, format);
    if (!validation.valid) {
      setNotice({ tone: "warning", text: validation.errors[0]?.message ?? "卡组代码不符合 30 张组牌规则。" });
      return false;
    }
    const missing = findMissingDeckCards(decoded.cardIds, player.collection);
    setEditingDeckId(null);
    setSelectedLadderReadyDeckId(null);
    setDeckIds([...decoded.cardIds]);
    setDeckName(decoded.name ?? "导入牌组");
    setDeckFormat(format);
    setNotice({
      tone: missing.length > 0 ? "info" : "success",
      text: missing.length > 0
        ? `已导入新的${rankedFormatLabel(format)}草稿；缺少 ${missing.reduce((sum, item) => sum + item.missing, 0)} 张卡牌，可按建议替换。`
        : `已导入新的${rankedFormatLabel(format)}卡组草稿，保存后会加入卡组列表。`,
    });
    return true;
  };

  const replaceMissingCard = (missingCardId: string, replacementCardId: string) => {
    const suggestions = suggestDeckReplacements({
      cardIds: deckIds,
      missingCardId,
      collection: player.collection,
      format: deckFormat,
    });
    if (!suggestions.includes(replacementCardId)) {
      setNotice({ tone: "warning", text: "这张卡当前不能作为合法替换。" });
      return;
    }
    const index = deckIds.lastIndexOf(missingCardId);
    if (index < 0) return;
    const next = [...deckIds];
    next[index] = replacementCardId;
    setDeckIds(next);
    setSelectedLadderReadyDeckId(null);
    setNotice({
      tone: "success",
      text: `已用「${CARD_BY_ID.get(replacementCardId)?.name ?? replacementCardId}」替换一张缺失卡牌。`,
    });
  };

  const selectDeck = (deckId: string) => {
    const selected = player.decks.find((deck) => deck.id === deckId);
    if (!selected) return;
    setEditingDeckId(selected.id);
    setSelectedLadderReadyDeckId(null);
    setDeckIds([...selected.cardIds]);
    setDeckName(selected.name);
    setDeckFormat(selected.format ?? "standard");
    setNotice({ tone: "info", text: `已载入「${selected.name}」，保存后将设为当前卡组。` });
  };

  const createBlankDeck = () => {
    setEditingDeckId(null);
    setSelectedLadderReadyDeckId(null);
    setDeckIds([...DEFAULT_STARTER_DECK]);
    setDeckName("新建战术卡组");
    setDeckFormat("standard");
    setNotice({ tone: "info", text: "已创建新的卡组草稿，保存后会加入你的卡组列表。" });
  };

  const createNewDeck = async () => {
    if (player.decks.length >= MAX_SAVED_DECKS) {
      setNotice({ tone: "warning", text: `已使用全部 ${MAX_SAVED_DECKS} 个卡组栏位，请先整理现有卡组。` });
      return;
    }
    let clipboardCode = "";
    try {
      clipboardCode = await navigator.clipboard?.readText() ?? "";
    } catch {
      // Clipboard access can be denied by the browser. Manual import remains available.
    }
    const preview = previewDeckCode(clipboardCode, deckFormat);
    if (
      preview &&
      preview.code !== declinedClipboardDeckCodeRef.current &&
      typeof window !== "undefined"
    ) {
      const missing = findMissingDeckCards(preview.cardIds, player.collection)
        .reduce((sum, item) => sum + item.missing, 0);
      const confirmed = window.confirm(
        `检测到剪贴板中的${rankedFormatLabel(preview.format)}卡组「${preview.name}」` +
        `${missing > 0 ? `，其中缺少 ${missing} 张卡牌` : ""}。是否导入为新卡组？`,
      );
      if (confirmed) {
        declinedClipboardDeckCodeRef.current = null;
        if (importDeck(preview.code)) return;
      } else {
        declinedClipboardDeckCodeRef.current = preview.code;
      }
    }
    createBlankDeck();
  };

  const openPack = async () => {
    if (player.packsAvailable <= 0) {
      setNotice({ tone: "info", text: "今日免费卡包已领取，明日 04:00 刷新。" });
      return;
    }
    const payload = await postAction("open_pack", {
      idempotencyKey: makeId("pack"),
    });
    if (payload) {
      setOpenedCards(payload.openedCards ?? []);
      setNotice({
        tone: payload.localFallback ? "info" : "success",
        text: payload.localFallback
          ? "档案包已在本地演示档案中解密。"
          : "档案包解密完成，新卡牌已归入收藏。",
      });
    }
  };

  const claimWeeklyPack = async () => {
    const payload = await postAction("claim_weekly_pack", {
      idempotencyKey: makeId("weekly-pack"),
    });
    if (payload) {
      setNotice({
        tone: payload.localFallback ? "info" : "success",
        text: `本周免费卡包已加入档案库${payload.localFallback ? "（本地演示）" : ""}。`,
      });
    }
  };

  const buyPack = async () => {
    const payload = await postAction("buy_pack", {
      idempotencyKey: makeId("shop-pack"),
    });
    if (payload) {
      setNotice({
        tone: payload.localFallback ? "info" : "success",
        text: `已购买 1 个档案包，消耗 ${payload.costGold ?? 100} 金币${payload.localFallback ? "（本地演示）" : ""}。`,
      });
    }
  };

  const rerollTask = async (task: PlayerTask) => {
    if (task.claimed || task.progress > 0 || task.period === "weekly") return;
    const payload = await postAction("reroll_task", {
      idempotencyKey: makeId(`reroll-${task.id}`),
      taskId: task.id,
    });
    if (payload) {
      setNotice({
        tone: payload.localFallback ? "info" : "success",
        text: `已重随任务为「${payload.task?.title ?? "新任务"}」。`,
      });
    }
  };

  const changeCardDust = async (action: "craft_card" | "disenchant_card", card: CatalogCard) => {
    const payload = await postAction(action, {
      idempotencyKey: makeId(`${action}-${card.id}`),
      cardId: card.id,
    });
    if (payload) {
      setNotice({
        tone: payload.localFallback ? "info" : "success",
        text: action === "craft_card"
          ? `已制作「${card.name}」，消耗 ${payload.amount ?? craftCost(card.rarity as "普通" | "稀有" | "史诗" | "传说")} 星尘。`
          : `已分解「${card.name}」，获得 ${payload.amount ?? disenchantValue(card.rarity as "普通" | "稀有" | "史诗" | "传说")} 星尘。`,
      });
    }
  };

  const claimReward = async (level: number) => {
    const payload = await postAction("claim_reward", {
      idempotencyKey: makeId(`reward-${level}`),
      level,
    });
    if (payload) {
      setNotice({ tone: payload.localFallback ? "info" : "success", text: `已领取 Lv.${level} 奖励：${payload.reward?.title ?? "奖励"}。` });
    }
  };

  const claimApprenticeReward = async (milestoneId: ApprenticeMilestoneId) => {
    const payload = await postAction("claim_apprentice_reward", {
      idempotencyKey: makeId(`apprentice-${milestoneId}`),
      milestoneId,
    });
    if (payload) {
      setNotice({
        tone: payload.localFallback ? "info" : "success",
        text: `新兵里程碑已结算：${payload.reward?.title ?? "成长奖励"}。`,
      });
    }
  };

  const activateLadderReady = async () => {
    const payload = await postAction("activate_ladder_ready", {
      idempotencyKey: makeId("ladder-ready-activate"),
    });
    if (payload) {
      setNotice({
        tone: payload.localFallback ? "info" : "success",
        text: `六套天梯预备套牌已解锁 ${LADDER_READY_TRIAL_DAYS} 天，可直接用于 AI 与在线对战。`,
      });
    }
  };

  const trialLadderReadyDeck = (deckId: LadderReadyDeckId) => {
    const offer = getLadderReadyDeck(deckId);
    const trial = player.ladderReady;
    if (!offer || !trial?.activatedAt || !trial.expiresAt) {
      setNotice({ tone: "warning", text: "请先激活七日试玩。" });
      return;
    }
    if (!ladderReadyTrialIsActive(trial)) {
      setNotice({ tone: "warning", text: trial.claimedDeckId ? "你已完成永久领取，其他试玩套牌已关闭。" : "试玩已经到期，请选择一套永久领取。" });
      return;
    }
    setSelectedLadderReadyDeckId(deckId);
    setEditingDeckId(null);
    setDeckIds([...offer.deck]);
    setDeckName(`${offer.faction} · ${offer.name}（试玩）`);
    setDeckFormat("standard");
    setTrainingActive(false);
    switchSection("battle");
    setNotice({ tone: "info", text: `已载入「${offer.name}」试玩套牌，可进入 AI 演算或在线对战。` });
  };

  const claimLadderReady = async (deckId: LadderReadyDeckId) => {
    const offer = getLadderReadyDeck(deckId);
    if (!offer) return;
    const payload = await postAction("claim_ladder_ready_deck", {
      idempotencyKey: makeId(`ladder-ready-claim-${deckId}`),
      deckId,
    });
    if (!payload?.claimedLadderReadyDeck) return;
    const saved = payload.claimedLadderReadyDeck;
    setSelectedLadderReadyDeckId(null);
    setEditingDeckId(saved.id);
    setDeckIds([...saved.cardIds]);
    setDeckName(saved.name);
    setDeckFormat(saved.format ?? "standard");
    setNotice({
      tone: payload.localFallback ? "info" : "success",
      text: `已永久领取「${offer.name}」：缺少卡牌已补齐，卡组已加入收藏。`,
    });
  };

  const claimTask = async (task: PlayerTask) => {
    if (task.claimed || task.progress < task.target) return;
    const payload = await postAction("claim_task", {
      idempotencyKey: makeId(`task-${task.id}`),
      taskId: task.id,
    });
    if (payload) {
      setNotice({
        tone: payload.localFallback ? "info" : "success",
        text: `任务结算完成，获得 ${payload.rewardGold ?? task.rewardGold} 金币${payload.localFallback ? "（本地演示）" : ""}。`,
      });
    }
  };

  const resetDemoProfile = async () => {
    if (!isDemo) return;
    if (typeof window !== "undefined" && !window.confirm("重置本地演示档案？收藏、卡组、任务和战绩都会恢复初始状态。")) {
      return;
    }
    const payload = await postAction("reset_demo", {});
    if (payload) {
      setOpenedCards([]);
      setSelectedLadderReadyDeckId(null);
      const firstDeck =
        payload.player.decks.find((deck) => deck.id === payload.player.activeDeckId) ??
        payload.player.decks[0];
      if (firstDeck) {
        setEditingDeckId(firstDeck.id);
        setDeckIds([...firstDeck.cardIds]);
        setDeckName(firstDeck.name);
        setDeckFormat(firstDeck.format ?? "standard");
      }
      setNotice({
        tone: payload.localFallback ? "info" : "success",
        text: "本地演示档案已重置，收藏、卡组、任务和战绩已恢复初始状态。",
      });
    }
  };

  const linkDeviceProfile = async () => {
    const payload = await postAction("link_device", {});
    if (payload) {
      setCanLinkDevice(false);
      setProfileSource("cloud");
      setNotice({ tone: "success", text: "本机访客档案已安全迁移到云端账号。" });
    }
  };

  const updateProfile = async (displayName: string) => {
    const nextName = displayName.trim().replace(/\s+/g, " ");
    if (!nextName || nextName.length > 24) {
      setNotice({ tone: "warning", text: "公开昵称必须为 1–24 个字符。" });
      return;
    }
    const payload = await postAction("update_profile", {
      idempotencyKey: makeId("profile"),
      displayName: nextName,
    });
    if (payload) {
      setNotice({
        tone: payload.localFallback ? "info" : "success",
        text: payload.localFallback ? "昵称已保存到本机档案。" : "昵称已保存到云端档案。",
      });
    }
  };

  const sendFriendRequest = async (friendId: string) => {
    const payload = await postAction("send_friend_request", {
      idempotencyKey: makeId("friend-request"),
      friendId,
    });
    if (payload) setNotice({ tone: payload.localFallback ? "info" : "success", text: payload.localFallback ? "好友请求已记录在本机档案。" : "好友请求已发送。" });
  };

  const acceptFriendRequest = async (friendId: string) => {
    const payload = await postAction("accept_friend_request", {
      idempotencyKey: makeId("friend-accept"),
      friendId,
    });
    if (payload) setNotice({ tone: payload.localFallback ? "info" : "success", text: payload.localFallback ? "好友已加入本机社交列表。" : "好友请求已接受。" });
  };

  const sendChatMessage = async (friendId: string, text: string) => {
    const payload = await postAction("send_chat", {
      idempotencyKey: makeId("chat"),
      friendId,
      text,
    });
    if (payload) setNotice({ tone: payload.localFallback ? "info" : "success", text: payload.localFallback ? "消息已记录在本机档案。" : "消息已发送。" });
  };

  const blockPlayer = async (targetId: string) => {
    const payload = await postAction("block_player", {
      idempotencyKey: makeId("block"),
      targetId,
    });
    if (payload) setNotice({ tone: payload.localFallback ? "info" : "success", text: payload.localFallback ? "已在本机屏蔽该玩家。" : "已屏蔽该玩家，聊天和好友邀请将被拦截。" });
  };

  const unblockPlayer = async (targetId: string) => {
    const payload = await postAction("unblock_player", {
      idempotencyKey: makeId("unblock"),
      targetId,
    });
    if (payload) setNotice({ tone: payload.localFallback ? "info" : "success", text: payload.localFallback ? "已解除本机屏蔽。" : "已解除屏蔽。" });
  };

  const reportPlayer = async (targetId: string, reason: string) => {
    const payload = await postAction("report_player", {
      idempotencyKey: makeId("report"),
      targetId,
      reason,
    });
    if (payload) setNotice({ tone: payload.localFallback ? "info" : "success", text: payload.localFallback ? "举报已记录在本机档案。" : "举报已提交，运营台会按规则复核。" });
  };

  // This transition is shared by AI and transport-driven PVP starts.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const beginBattle = (decks: [string[], string[]], startingPlayer: 0 | 1, online: boolean, rankedFormat: RankedFormat, opponentName?: string, seed?: number, opponentArchetypeId?: string, aiTicketToken?: string) => {
    const launchDeckValidation = validateDeck(decks[0]);
    if (!online && !launchDeckValidation.valid) {
      switchSection("deck");
      setNotice({ tone: "warning", text: `无法部署：${launchDeckValidation.errors[0]?.message ?? "服务端卡组无效"}` });
      return;
    }
    try {
      aiTurnGenerationRef.current += 1;
      if (aiTurnTimerRef.current !== null) {
        window.clearTimeout(aiTurnTimerRef.current);
        aiTurnTimerRef.current = null;
      }
      aiReplayFinalStateRef.current = null;
      mulliganSubmissionRef.current = false;
      unlockAudio();
      let next = createMatch({ decks, startingPlayer, rankedFormat, ...(seed === undefined ? {} : { seed }) });
      aiCommandTranscriptRef.current = [];
      aiMatchProofRef.current = null;
      // In a local match the AI confirms its opening hand immediately; the
      // human player still gets a visible mulligan decision window.
      if (!online) {
        if (!aiTicketToken) throw new Error("缺少服务端签发的 AI 对局凭证。");
        const aiMulliganCommand: BattleCommand = {
          type: "mulligan",
          player: 1,
          cardIndexes: chooseAiMulliganIndexes(next, 1),
        };
        const aiMulligan = applyCommand(next, aiMulliganCommand);
        if (aiMulligan.accepted) next = aiMulligan.state;
        if (aiMulligan.accepted) aiCommandTranscriptRef.current.push(aiMulliganCommand);
        aiMatchProofRef.current = {
          ticketToken: aiTicketToken,
          seed: next.seed,
          startingPlayer,
          rankedFormat,
          playerDeck: [...decks[0]],
          opponentArchetypeId: opponentArchetypeId ?? AI_ARCHETYPES[0]?.id ?? "tide-control",
          commands: aiCommandTranscriptRef.current,
        };
      }
      setBattle(unwrapTransition(next));
      setInspectedCard(null);
      setOnlineMatch(online);
      setOnlineOpponent(opponentName ?? (online ? "联机对手" : "镜像演算体 K-7"));
      if (!online) {
        pvpMatchTokenRef.current = null;
        pvpMatchPlayerRef.current = null;
      }
      pendingPvpCommandRef.current = false;
      setSelectedAttacker(null);
      setPendingCard(null);
      setPendingHeroPower(false);
      setMulliganSelection([]);
      setBattleMessage(online ? "联机战术链路建立，请先确认起手牌。" : "战术链路建立。点击不想保留的手牌，再确认起手。");
      recordedBattleRef.current = null;
      sectionRef.current = "battle";
      setSection("battle");
      if (typeof window !== "undefined") {
        window.scrollTo({ top: 0, behavior: "smooth" });
      }
      battleEffectSequenceRef.current += 1;
      const effectId = battleEffectSequenceRef.current;
      const openingEffects: BattleVisualEffect[] = [
        {
          id: `start-${effectId}`,
          kind: "start",
          side: "player",
          label: "战术链路建立",
        },
        ...(next.phase === "mulligan"
          ? []
          : [{
              id: `turn-${effectId}`,
              kind: "turn" as const,
              side: "player" as const,
              targetSide: "player" as const,
              label: "你的回合",
            }]),
      ];
      showBattleEffects(
        openingEffects,
        { reset: true },
      );
    } catch (error) {
      setNotice({
        tone: "warning",
        text: error instanceof Error ? `无法开始对战：${error.message}` : "战斗引擎暂不可用。",
      });
    }
  };

  const startBattle = async () => {
    if (aiMatchStartingRef.current) return;
    const requestedOpponent = selectedAiArchetype ?? AI_ARCHETYPES[0];
    const savedDeckId = editingDeckId;
    if (!selectedLadderReadyDeckId && !savedDeckId) {
      switchSection("deck");
      setNotice({ tone: "warning", text: "请先保存当前卡组，再开始 AI 演算。" });
      return;
    }
    if (!selectedLadderReadyDeckId && !deckPlayable) {
      switchSection("deck");
      setNotice({
        tone: "warning",
        text: deckMissingCards.length > 0
          ? "当前卡组仍有缺失卡牌，请先制作或替换后再投入对战。"
          : deckValidation.errors[0] ?? "当前卡组尚未完成。",
      });
      return;
    }
    aiMatchStartingRef.current = true;
    try {
      const payload = await postAction("create_ai_match", {
        ...(selectedLadderReadyDeckId
          ? { ladderReadyDeckId: selectedLadderReadyDeckId }
          : { deckId: savedDeckId }),
        opponentArchetypeId: requestedOpponent?.id ?? "tide-control",
      });
      const ticket = payload?.aiMatch;
      if (!ticket) return;
      const opponent = AI_ARCHETYPES.find(
        (candidate) => candidate.id === ticket.opponentArchetypeId,
      );
      if (!opponent) {
        setNotice({ tone: "warning", text: "服务端签发的 AI 对手已不可用，请稍后重试。" });
        return;
      }
      beginBattle(
        [[...ticket.playerDeck], [...(opponent.deck ?? DEFAULT_OPPONENT_DECK)]],
        ticket.startingPlayer,
        false,
        ticket.rankedFormat,
        opponent.name,
        ticket.seed,
        ticket.opponentArchetypeId,
        ticket.token,
      );
    } finally {
      aiMatchStartingRef.current = false;
    }
  };

  const startStandardBattle = () => {
    setTrainingActive(false);
    void startBattle();
  };

  const startTrainingBattle = () => {
    setTrainingActive(true);
    setTrainingBriefingOpen(false);
    void startBattle();
  };

  // In PVP the server reducer is authoritative. The local client only sends a
  // command and renders the resulting snapshot that the server broadcasts.
  const issueCommand = useCallback((command: BattleCommand, broadcast = true) => {
    if (!battle) return null;
    try {
      const previous = battle as MatchState;
      const preparedCommand = {
        ...(command.commandId ? command : { ...command, commandId: makeId("command") }),
        expectedVersion: command.expectedVersion ?? previous.version,
      } as BattleCommand;
      // The room transport can briefly remain in `ready` while the match-start
      // snapshot is being applied. The authoritative match state already
      // carries the active player and phase, so only a disconnected/error
      // transport should block a command here.
      if (
        onlineMatch &&
        (!pvp.state.roomCode || pvp.state.status === "offline" || pvp.state.status === "error" || pvp.state.status === "connecting")
      ) {
        setBattleMessage("联机连接已断开，无法继续发送指令。");
        return null;
      }
      if (onlineMatch && broadcast) {
        if (pendingPvpCommandRef.current) {
          setBattleMessage("上一条指令正在等待服务器结算。");
          return null;
        }
        pendingPvpCommandRef.current = true;
        if (!pvp.sendCommand(preparedCommand)) {
          pendingPvpCommandRef.current = false;
          setBattleMessage("联机连接尚未就绪，指令未发送。");
          return null;
        }
        setBattleMessage("指令已提交，等待服务器确认…");
        return null;
      }
      const previousEventCount = previous.events.length;
      const result = applyCommand(battle as MatchState, preparedCommand);
      if (!result.accepted) {
        setBattleMessage(result.error?.message ?? "该战术指令当前不可执行。");
        playSound("error");
        return null;
      }
      const next = unwrapTransition(result) as MatchState;
      if (!onlineMatch) {
        aiCommandTranscriptRef.current.push(preparedCommand);
      }
      setBattle(next);
      showBattleEffects(
        battleEventsToEffects(next.events.slice(previousEventCount)),
        { lock: true },
      );
      return next;
    } catch (error) {
      setBattleMessage(error instanceof Error ? error.message : "该战术指令当前不可执行。");
      playSound("error");
      return null;
    }
  }, [battle, onlineMatch, playSound, pvp, showBattleEffects]);

  const scheduleLocalAiTurn = useCallback((initialState: MatchState): boolean => {
    if (
      !shouldScheduleLocalAiTurn(initialState, onlineMatch) ||
      aiTurnTimerRef.current !== null ||
      aiReplayActiveRef.current
    ) {
      return false;
    }

    const generation = aiTurnGenerationRef.current;
    setBattleMessage("演算体正在规划反制路线…");
    aiTurnTimerRef.current = window.setTimeout(() => {
      aiTurnTimerRef.current = null;
      if (generation !== aiTurnGenerationRef.current) return;

      try {
        const plan = planAiTurnReplay(initialState, 1);
        if (generation !== aiTurnGenerationRef.current) return;
        aiCommandTranscriptRef.current.push(...plan.commands);

        const states = plan.steps.length > 0
          ? plan.steps.map((step, index) => {
              const previousEventCount = index === 0
                ? plan.initialEventCount
                : plan.steps[index - 1]?.eventCount ?? plan.initialEventCount;
              return {
                ...step,
                visualEffectCount: battleEventsToEffects(
                  step.state.events.slice(previousEventCount, step.eventCount),
                ).length,
              };
            })
          : [{
              state: plan.finalState,
              eventCount: plan.finalState.events.length,
              visualEffectCount: battleEventsToEffects(
                plan.finalState.events.slice(plan.initialEventCount),
              ).length,
            }];
        const replayFrames = [{
          state: initialState,
          eventCount: plan.initialEventCount,
          visualEffectCount: 0,
        }, ...states];
        const replayEffects = battleEventsToEffects(
          states.flatMap((step, index) => {
            const previousEventCount = index === 0
              ? plan.initialEventCount
              : states[index - 1]?.eventCount ?? plan.initialEventCount;
            return step.state.events.slice(previousEventCount, step.eventCount);
          }),
        );

        // Reveal each accepted AI command as a real board transition instead
        // of jumping directly to the final turn snapshot. The effect queue
        // remains the timing authority, so the board and the combat overlay
        // move at the same readable cadence on mobile and desktop.
        if (sectionRef.current === "battle") {
          aiReplayFinalStateRef.current = plan.finalState;
          aiReplayActiveRef.current = true;
          aiReplayCompletionMessageRef.current = plan.finalState.phase === "game-over"
            ? "敌方行动完成，正在结算演算结果。"
            : "敌方行动已结束，新的能量窗口已开启。";
          // Start from the pre-command board. Each post-command snapshot is
          // revealed only after that command's effects have had their full
          // playback window, so damage/death animation never trails a board
          // that has already jumped to the result.
          setBattle(replayFrames[0]?.state ?? plan.finalState);
          showBattleEffects(replayEffects, {
            lock: true,
            maxEffects: BATTLE_EFFECT_QUEUE_LIMIT,
          });
          let replayIndex = 1;
          const replayStepDuration = (frame: (typeof replayFrames)[number]) => {
            const beat = battleReplaySlowRef.current
              ? BATTLE_EFFECT_SLOW_STEP_MS
              : BATTLE_EFFECT_STANDARD_STEP_MS;
            return Math.max(1, frame.visualEffectCount) * beat;
          };
          const revealNext = () => {
            if (generation !== aiTurnGenerationRef.current) return;
            const step = replayFrames[replayIndex];
            if (!step) {
              aiTurnTimerRef.current = null;
              aiReplayFinalStateRef.current = null;
              aiReplayActiveRef.current = false;
              if (battleEffectLockRef.current && battleEffectQueueRef.current.length === 0) {
                battleEffectLockRef.current = false;
                setBattleEffectsLocked(false);
                setBattleEffect(null);
                setBattleEffectCount(0);
                aiReplayCompletionMessageRef.current = null;
                setBattleMessage(
                  plan.finalState.phase === "game-over"
                    ? "敌方行动完成，正在结算演算结果。"
                    : "敌方行动已结束，新的能量窗口已开启。",
                );
              } else {
                setBattleMessage("敌方动作已结算，正在完成战况回放…");
              }
              return;
            }
            replayIndex += 1;
            aiTurnTimerRef.current = window.setTimeout(
              () => {
                if (generation !== aiTurnGenerationRef.current) return;
                setBattle(step.state);
                revealNext();
              },
              replayStepDuration(step),
            );
          };
          revealNext();
          setBattleMessage("敌方正在逐步执行战术动作…");
        } else {
          setBattle(plan.finalState);
          setBattleMessage(
            plan.finalState.phase === "game-over"
              ? "敌方行动完成，正在结算演算结果。"
              : "敌方行动已结束，新的能量窗口已开启。",
          );
        }
      } catch (error) {
        setBattleMessage(error instanceof Error ? error.message : "AI 回合演算异常。");
        playSound("error");
      }
    }, AI_TURN_DELAY_MS);
    return true;
  }, [onlineMatch, playSound, showBattleEffects]);

  useEffect(() => {
    const event = pvp.incoming;
    if (!event || event.id <= pvpEventCursorRef.current) return;
    pvpEventCursorRef.current = event.id;
    if (event.type === "rejected") {
      pendingPvpCommandRef.current = false;
      mulliganSubmissionRef.current = false;
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setBattleMessage(event.message);
      playSound("error");
      if (event.resync) pvp.syncRoom();
      pvp.acknowledgeIncoming(event.id);
      return;
    }
    if (event.type === "room-reset") {
      aiTurnGenerationRef.current += 1;
      if (aiTurnTimerRef.current !== null) {
        window.clearTimeout(aiTurnTimerRef.current);
        aiTurnTimerRef.current = null;
      }
      aiReplayFinalStateRef.current = null;
      mulliganSubmissionRef.current = false;
      onlineStartSentRef.current = false;
      pendingPvpCommandRef.current = false;
      pvpMatchTokenRef.current = null;
      pvpMatchPlayerRef.current = null;
      recordedBattleRef.current = null;
      stopBattleEffects();
      setBattle(null);
      setOnlineMatch(false);
      setOnlineOpponent(null);
      setSelectedAttacker(null);
      setPendingCard(null);
      setPendingHeroPower(false);
      setMulliganSelection([]);
      setBattleMessage("房间已重置，双方点击“准备对战”开始下一局。");
      sectionRef.current = "battle";
      setSection("battle");
      pvp.acknowledgeIncoming(event.id);
      return;
    }
    if (event.type === "match-start") {
      const role = pvp.state.role;
      if (!role) {
        pvp.acknowledgeIncoming(event.id);
        return;
      }
      const localIndex = role === "host" ? 0 : 1;
      const localDeckCandidate = event.payload.deck ?? event.payload.decks?.[localIndex];
      const localDeck = localDeckCandidate && localDeckCandidate.length === 30
        ? localDeckCandidate
        : deckIds;
      // PVP state sync is authoritative; the placeholder opponent deck only
      // opens the local mulligan shell without exposing the real deck list.
      const orderedDecks: [string[], string[]] = [[...localDeck], [...DEFAULT_OPPONENT_DECK]];
      pvpMatchTokenRef.current = event.payload.matchToken ?? null;
      pvpMatchPlayerRef.current = localIndex;
      const canonicalStartingPlayer = event.payload.startingPlayer ?? 0;
      const localStartingPlayer = role === "host"
        ? canonicalStartingPlayer
        : canonicalStartingPlayer === 0 ? 1 : 0;
      beginBattle(orderedDecks, localStartingPlayer, true, event.payload.rankedFormat ?? pvp.state.rankedFormat, pvp.state.peerName ?? "联机对手", event.payload.seed);
      pvp.acknowledgeIncoming(event.id);
      return;
    }
    if (event.type === "match-sync") {
      const role = pvp.state.role;
      if (!role) {
        pvp.acknowledgeIncoming(event.id);
        return;
      }
      const nextMatchToken = event.payload.matchToken ?? null;
      if (pvpMatchPlayerRef.current === null || nextMatchToken !== pvpMatchTokenRef.current) {
        pvpMatchPlayerRef.current = role === "host" ? 0 : 1;
      }
      pvpMatchTokenRef.current = nextMatchToken;
      const stableRole = pvpMatchPlayerRef.current === 0 ? "host" : "guest";
      const oriented = orientPvpMatchForLocal(event.payload.state, stableRole);
      pendingPvpCommandRef.current = false;
      setBattle(oriented);
      mulliganSubmissionRef.current = false;
      setOnlineMatch(true);
      setOnlineOpponent(pvp.state.peerName ?? "联机对手");
      setSelectedAttacker(null);
      setPendingCard(null);
      setPendingHeroPower(false);
      setMulliganSelection([]);
      setBattleMessage(oriented.phase === "game-over" ? "已恢复已结束的联机战报。" : "已恢复联机对局，等待行动窗口。");
      sectionRef.current = "battle";
      setSection("battle");
      pvp.acknowledgeIncoming(event.id);
      return;
    }
    if (event.type === "command") {
      pendingPvpCommandRef.current = false;
      mulliganSubmissionRef.current = false;
      if (event.state) {
        const role = pvp.state.role;
        if (!role) {
          pvp.acknowledgeIncoming(event.id);
          return;
        }
        const previous = battle as MatchState | null;
        const nextMatchToken = event.matchToken ?? pvpMatchTokenRef.current;
        if (pvpMatchPlayerRef.current === null || nextMatchToken !== pvpMatchTokenRef.current) {
          pvpMatchPlayerRef.current = role === "host" ? 0 : 1;
        }
        pvpMatchTokenRef.current = nextMatchToken;
        const stableRole = pvpMatchPlayerRef.current === 0 ? "host" : "guest";
        const oriented = orientPvpMatchForLocal(event.state, stableRole);
        setBattle(oriented);
        setSelectedAttacker(null);
        setPendingCard(null);
        setPendingHeroPower(false);
        setMulliganSelection([]);
        if (previous) {
          showBattleEffects(battleEventsToEffects(oriented.events.slice(previous.events.length)), {
            lock: oriented.phase === "game-over",
            maxEffects: BATTLE_EFFECT_QUEUE_LIMIT,
          });
        }
        setBattleMessage(
          oriented.phase === "game-over"
            ? oriented.result?.winner === null
              ? "对局结束：双方战平。"
              : oriented.result?.winner === 0
                ? "对局结束：我方核心存活。"
                : "对局结束：敌方核心存活。"
            : oriented.activePlayer === 0 ? "服务器已结算，你的行动窗口已开启。" : "服务器已结算，等待对手行动…",
        );
        pvp.acknowledgeIncoming(event.id);
        return;
      }
      const remote = event.command;
      const target = remote.target;
      const role = pvpMatchPlayerRef.current === null
        ? pvp.state.role
        : pvpMatchPlayerRef.current === 0 ? "host" : "guest";
      const localPlayer = role === "guest" ? (remote.player === 0 ? 1 : 0) : remote.player;
      const mappedTarget = target?.kind === "hero" && role === "guest"
        ? { ...target, player: target.player === 0 ? 1 : 0 }
        : target;
      issueCommand({ ...remote, player: localPlayer, ...(mappedTarget ? { target: mappedTarget } : {}) } as BattleCommand, false);
      pvp.acknowledgeIncoming(event.id);
    }
  }, [battle, beginBattle, deckIds, issueCommand, playSound, pvp, showBattleEffects, stopBattleEffects]);

  useEffect(() => {
    if (
      pvp.state.role !== "host" ||
      !pvp.state.localReady ||
      !pvp.state.remoteReady ||
      !pvp.state.remoteReadyDeck ||
      onlineMatch ||
      onlineStartSentRef.current
    ) {
      return;
    }
    const payload = {
      decks: [[...deckIds], [...pvp.state.remoteReadyDeck]] as [string[], string[]],
    };
    pvp.sendMatchStart(payload);
    onlineStartSentRef.current = true;
  }, [deckIds, onlineMatch, pvp, pvp.sendMatchStart, pvp.state.localReady, pvp.state.remoteReady, pvp.state.remoteReadyDeck, pvp.state.peerName, pvp.state.role]);

  useEffect(() => {
    if (pvp.state.status === "offline" || !pvp.state.roomCode) {
      onlineStartSentRef.current = false;
      pvpEventCursorRef.current = 0;
      pendingPvpCommandRef.current = false;
      if (onlineMatch && battleView?.status === "playing") {
        // The disconnect event is an external transport update.
        // eslint-disable-next-line react-hooks/set-state-in-effect
        setBattleMessage("联机大厅已断开，本场演算暂停。重新连接后可再次开始。");
      }
    }
  }, [battleView?.status, onlineMatch, pvp.state.roomCode, pvp.state.status]);

  const toggleMulliganCard = (index: number) => {
    if (!battleView || battleView.status !== "mulligan" || battleView.mulliganDone) return;
    setMulliganSelection((current) =>
      current.includes(index)
        ? current.filter((item) => item !== index)
        : [...current, index],
    );
    playSound("select");
  };

  const confirmMulligan = () => {
    if (
      !battle ||
      !battleView ||
      battleView.status !== "mulligan" ||
      battleView.mulliganDone ||
      mulliganSubmissionRef.current
    ) return;
    mulliganSubmissionRef.current = true;
    const next = issueCommand({
      type: "mulligan",
      player: 0,
      cardIndexes: [...mulliganSelection].sort((left, right) => left - right),
    });
    setMulliganSelection([]);
    if (!next && (!onlineMatch || !pendingPvpCommandRef.current)) {
      mulliganSubmissionRef.current = false;
    }
    if (next) {
      const nextState = next as MatchState;
      const aiScheduled = scheduleLocalAiTurn(nextState);
      if (!aiScheduled) {
        setBattleMessage(
          nextState.phase === "mulligan"
            ? "起手已确认，等待对手完成换牌…"
            : "起手完成，第一回合行动窗口已开启。",
        );
      }
    }
  };

  const playCard = (
    handCard: BattleSide["hand"][number],
    placement: "friendly" | "enemy" = "friendly",
  ) => {
    if (battleEffectLockRef.current) {
      setBattleMessage("战况回放中，请等待行动窗口稳定。");
      return;
    }
    if (!battleView || battleView.status !== "playing" || battleView.currentPlayer !== "player") {
      setBattleMessage("当前不是你的行动窗口。");
      return;
    }
    if (pendingHeroPower) {
      setBattleMessage("请先完成或取消核心技能目标选择。");
      return;
    }
    const card = CARD_BY_ID.get(handCard.cardId);
    const ruleCard = cardRuleForHandSlot(handCard);
    if (placement === "enemy" && !card?.disguised) {
      setBattleMessage("只有伪装单位可以部署到敌方战场。");
      return;
    }
    const effectiveCost = card ? Math.max(0, card.cost - handCard.costReduction) : 0;
    if (card && effectiveCost > battleView.player.mana) {
      setBattleMessage(`能量不足：部署「${card.name}」需要 ${effectiveCost} 点能量。`);
      return;
    }
    const targetRule = ruleCard?.target ?? card?.target ?? "none";
    const hasAvailableTarget = (() => {
      switch (targetRule) {
        case "enemy-unit":
          return battleView.ai.board.some((unit) => unit.health > 0 && !unit.stealthActive);
        case "friendly-unit":
          return battleView.player.board.some((unit) => unit.health > 0);
        case "any-unit":
          return battleView.player.board.some((unit) => unit.health > 0) ||
            battleView.ai.board.some((unit) => unit.health > 0 && !unit.stealthActive);
        case "enemy-character":
          return true;
        case "friendly-character":
          return true;
        case "any-character":
          return true;
        default:
          return false;
      }
    })();
    if (card && targetRule !== "none" && card.type !== "unit" && !hasAvailableTarget) {
      setBattleMessage(`当前没有「${card.name}」可用的合法目标。`);
      return;
    }
    // Targeted Battlecry minions are legal to deploy without a target when
    // their target pool is empty; the reducer then skips only the Battlecry.
    // Keep the card playable instead of opening a selection state with no
    // clickable target to finish it.
    if (card && targetRule !== "none" && (card.type !== "unit" || hasAvailableTarget)) {
      setPendingCard(handCard);
      setPendingCardPlacement(placement);
      setPendingHeroPower(false);
      setSelectedAttacker(null);
      playSound("select");
      setBattleMessage(
        targetRule.startsWith("enemy")
          ? `请选择「${card.name}」的敌方目标。`
          : targetRule.startsWith("friendly")
            ? `请选择「${card.name}」的友方目标。`
            : `请选择「${card.name}」的目标。`,
      );
      return;
    }
    const next = issueCommand({
      type: "play-card",
      player: 0,
      cardId: handCard.cardId,
      handIndex: handCard.handIndex,
      placement,
    });
    if (next) setBattleMessage(
      placement === "enemy"
        ? `「${card?.name ?? "伪装单位"}」已潜入敌方战场。`
        : `已部署「${card?.name ?? "战术卡"}」。`,
    );
  };

  const tradeCard = (handCard: BattleSide["hand"][number]) => {
    if (battleEffectLockRef.current) {
      setBattleMessage("战况回放中，请等待行动窗口稳定。");
      return;
    }
    if (!battleView || battleView.status !== "playing" || battleView.currentPlayer !== "player") {
      setBattleMessage("当前不是你的行动窗口。");
      return;
    }
    const card = CARD_BY_ID.get(handCard.cardId);
    if (!card?.tradeable) {
      setBattleMessage("这张卡牌不可交易。");
      return;
    }
    if (battleView.player.mana < 1) {
      setBattleMessage("交易需要 1 点能量。");
      return;
    }
    const next = issueCommand({
      type: "trade-card",
      player: 0,
      cardId: handCard.cardId,
      handIndex: handCard.handIndex,
    });
    if (next) {
      setPendingCard(null);
      setPendingCardPlacement("friendly");
      setPendingHeroPower(false);
      setSelectedAttacker(null);
      setBattleMessage(`已交易「${card.name}」，抽取一张替代牌。`);
    }
  };

  const prepareCard = (handCard: BattleSide["hand"][number]) => {
    if (battleEffectLockRef.current) {
      setBattleMessage("战况回放中，请等待行动窗口稳定。");
      return;
    }
    if (!battleView || battleView.status !== "playing" || battleView.currentPlayer !== "player") {
      setBattleMessage("当前不是你的行动窗口。");
      return;
    }
    const card = CARD_BY_ID.get(handCard.cardId);
    if (!card?.preparable) {
      setBattleMessage("这张卡牌不能预备。");
      return;
    }
    if (handCard.costReduction > 0) {
      setBattleMessage(`「${card.name}」已经完成过预备。`);
      return;
    }
    if (battleView.player.mana < 1) {
      setBattleMessage("预备至少需要 1 点剩余能量。");
      return;
    }
    const manaSpent = battleView.player.mana;
    const next = issueCommand({
      type: "prepare-card",
      player: 0,
      cardId: handCard.cardId,
      handIndex: handCard.handIndex,
    });
    if (next) {
      setPendingCard(null);
      setPendingCardPlacement("friendly");
      setPendingHeroPower(false);
      setSelectedAttacker(null);
      setBattleMessage(`已用 ${manaSpent} 点能量预备「${card.name}」，费用永久降低 ${manaSpent + 1} 点。`);
    }
  };

  const chooseDiscover = (cardId: string, choiceIndex: number) => {
    if (battleEffectLockRef.current) {
      setBattleMessage("战况回放中，请等待选择窗口稳定。");
      return;
    }
    if (!battleView || battleView.status !== "discover" || battleView.currentPlayer !== "player") {
      setBattleMessage("当前没有可用的发现选择。");
      return;
    }
    const card = CARD_BY_ID.get(cardId);
    const next = issueCommand({ type: "choose-discover", player: 0, cardId, choiceIndex });
    if (next) setBattleMessage(`已选择「${card?.name ?? "发现卡牌"}」加入手牌。`);
  };

  const chooseOne = (optionIndex: number) => {
    if (battleEffectLockRef.current) {
      setBattleMessage("战况回放中，请等待选择窗口稳定。");
      return;
    }
    if (!battleView || battleView.status !== "choose-one" || battleView.currentPlayer !== "player") {
      setBattleMessage("当前没有可用的抉择。");
      return;
    }
    const next = issueCommand({ type: "choose-one", player: 0, optionIndex });
    if (next) {
      const label = (next as MatchState).events.at(-1)?.data?.optionLabel;
      setBattleMessage(`已选择「${typeof label === "string" ? label : "抉择分支"}」。`);
    }
  };

  const playCardAtTarget = (target: { kind: "unit" | "hero"; side: "player" | "ai"; id?: string }) => {
    if (battleEffectLockRef.current) return;
    if (!pendingCard && !pendingHeroPower) return;
    const card = pendingCard ? CARD_BY_ID.get(pendingCard.cardId) : undefined;
    const normalizedTarget = target.kind === "hero"
      ? { kind: "hero" as const, player: target.side === "player" ? 0 as const : 1 as const }
      : { kind: "unit" as const, entityId: target.id ?? "" };
    const next = pendingHeroPower
      ? issueCommand({ type: "hero-power", player: 0, target: normalizedTarget })
      : issueCommand({
          type: "play-card",
          player: 0,
          cardId: pendingCard?.cardId ?? "",
          handIndex: pendingCard?.handIndex,
          placement: pendingCardPlacement,
          target: normalizedTarget,
        });
    if (next) {
      setPendingCard(null);
      setPendingCardPlacement("friendly");
      setPendingHeroPower(false);
      setBattleMessage(pendingHeroPower
        ? `${battleView?.player.heroPowerName ?? "核心技能"} 已结算。`
        : `已部署「${card?.name ?? "战术卡"}」，目标效果完成结算。`);
    }
  };

  const attackTarget = (target: BattleTarget) => {
    if (battleEffectLockRef.current) return;
    if (!battleView || !selectedAttacker) return;
    const normalizedTarget =
      target.kind === "hero"
        ? { kind: "hero" as const, player: 1 as const }
        : { kind: "unit" as const, entityId: target.id ?? "" };
    const next = selectedAttacker === "hero-0"
      ? issueCommand({ type: "hero-attack", player: 0, target: normalizedTarget })
      : issueCommand({
          type: "attack",
          player: 0,
          attackerId: selectedAttacker,
          target: normalizedTarget,
        });
    if (next) {
      setSelectedAttacker(null);
      setPendingCard(null);
      setPendingHeroPower(false);
      setBattleMessage(target.kind === "hero" ? "攻击已直达敌方核心。" : "单位交战已结算。");
    }
  };

  const selectHeroAttacker = () => {
    if (
      battleEffectLockRef.current ||
      !battleView ||
      (battleView.player.weapon?.attack ?? 0) + battleView.player.heroAttackBonus <= 0
    ) return;
    if (battleView.player.heroHasAttacked) {
      setBattleMessage("英雄本回合已经攻击过。");
      return;
    }
    setPendingCard(null);
    setPendingHeroPower(false);
    setSelectedAttacker((current) => (current === "hero-0" ? null : "hero-0"));
    setBattleMessage("已准备英雄攻击，请选择敌方单位或核心。");
    playSound("select");
  };

  const useHeroPower = () => {
    if (battleEffectLockRef.current) return;
    if (!battleView || battleView.status !== "playing" || battleView.currentPlayer !== "player") {
      setBattleMessage("当前不是你的行动窗口。");
      return;
    }
    if (pendingHeroPower) {
      setPendingHeroPower(false);
      setBattleMessage("已取消核心技能目标选择。");
      return;
    }
    if (battleView.player.heroPowerTarget !== "none") {
      setPendingHeroPower(true);
      setPendingCard(null);
      setSelectedAttacker(null);
      playSound("select");
      setBattleMessage(`${battleView.player.heroPowerName}：请选择${battleView.player.heroPowerTarget === "enemy-unit" ? "敌方单位" : "友方目标"}。`);
      return;
    }
    const next = issueCommand({
      type: "hero-power",
      player: 0,
    });
    if (next) {
      setBattleMessage(`${battleView?.player.heroPowerName ?? "英雄技能"} 已结算。`);
    }
  };

  const endTurn = () => {
    if (battleEffectLockRef.current) return;
    if (!battle || !battleView || battleView.currentPlayer !== "player") return;
    const ended = issueCommand({
      type: "end-turn",
      player: 0,
    });
    if (!ended) return;
    setSelectedAttacker(null);
    setPendingCard(null);
    setPendingHeroPower(false);
    const endedState = ended as MatchState;
    if (endedState.phase === "game-over") return;
    if (!scheduleLocalAiTurn(endedState)) {
      setBattleMessage(onlineMatch ? "指令已同步，等待对手行动…" : "敌方行动窗尚未开启。");
    }
  };

  useEffect(() => {
    endTurnRef.current = endTurn;
  });

  useEffect(() => {
    const timer = window.setTimeout(() => {
      turnTimeoutHandledRef.current = null;
      setBattleTurnClockSeconds(
        battleStatus === "playing" && battleCurrentPlayer === "player"
          ? TURN_TIME_LIMIT_SECONDS
          : null,
      );
    }, 0);
    return () => window.clearTimeout(timer);
  }, [battleStatus, battleCurrentPlayer, battleTurn]);

  useEffect(() => {
    if (
      !hasBattleTurnClock ||
      battleStatus !== "playing" ||
      battleCurrentPlayer !== "player" ||
      battleEffectsLocked
    ) {
      return;
    }
    const timer = window.setInterval(() => {
      setBattleTurnClockSeconds((current) =>
        current === null ? null : Math.max(0, current - 1),
      );
    }, 1000);
    return () => window.clearInterval(timer);
  }, [hasBattleTurnClock, battleStatus, battleCurrentPlayer, battleEffectsLocked]);

  useEffect(() => {
    if (
      battleTurnClockSeconds !== 0 ||
      battleStatus !== "playing" ||
      battleCurrentPlayer !== "player" ||
      battleEffectsLocked ||
      battleTurn === undefined ||
      turnTimeoutHandledRef.current === battleTurn
    ) {
      return;
    }
    turnTimeoutHandledRef.current = battleTurn;
    setBattleTurnClockSeconds(null);
    setBattleMessage("行动时间耗尽，自动结束回合。");
    endTurnRef.current();
  }, [battleTurnClockSeconds, battleStatus, battleCurrentPlayer, battleEffectsLocked, battleTurn]);

  const concedeBattle = () => {
    if (battleEffectLockRef.current || !battle || battleView?.status !== "playing") return;
    const next = issueCommand({ type: "concede", player: 0 });
    if (!next) return;
    setSelectedAttacker(null);
    setPendingCard(null);
    setPendingHeroPower(false);
    setBattleMessage("你已结束本场演算，战报正在归档。");
  };

  const requestOnlineRematch = () => {
    if (pvp.state.role !== "host") return;
    if (pvp.requestRematch()) {
      setBattleMessage("已通知对手，正在重置房间…");
    } else {
      setBattleMessage("联机连接尚未就绪，无法重新开始。");
    }
  };

  const returnToBattleLobby = () => {
    aiTurnGenerationRef.current += 1;
    if (aiTurnTimerRef.current !== null) {
      window.clearTimeout(aiTurnTimerRef.current);
      aiTurnTimerRef.current = null;
    }
    aiReplayFinalStateRef.current = null;
    stopBattleEffects();
    if (onlineMatch) pvp.disconnect();
    setBattle(null);
    setOnlineMatch(false);
    setOnlineOpponent(null);
    setSelectedAttacker(null);
    setPendingCard(null);
    setPendingHeroPower(false);
    setMulliganSelection([]);
    setBattleMessage("已返回战术大厅，可重新选择演算对手或创建联机房间。");
  };

  useEffect(() => {
    if (!battleView || battleView.status !== "finished") return;
    const result = battleView.winner === "player"
      ? "win"
      : battleView.winner === "ai"
        ? "loss"
        : battleView.report.reason === "draw"
          ? "draw"
          : null;
    if (!result) return;
    const key = `${battleView.turn}-${result}`;
    if (recordedBattleRef.current === key) return;
    recordedBattleRef.current = key;
    setBattleMessage(
      result === "win"
        ? "敌方核心已离线，战术演算胜利。"
        : result === "draw"
          ? "双方核心状态已锁定，本场演算平局。"
          : "我方核心失守，演算数据已回收。",
    );
    void postAction("record_match", {
      idempotencyKey: makeId("match"),
      result,
      mode: onlineMatch ? "pvp" : "ai",
      opponent: onlineOpponent ?? (onlineMatch ? "联机对手" : "镜像演算体 K-7"),
      ...(onlineMatch ? { format: pvp.state.format, rankedFormat: pvp.state.rankedFormat } : {}),
      ...(!onlineMatch && aiMatchProofRef.current
        ? { aiProof: { ...aiMatchProofRef.current, commands: [...aiCommandTranscriptRef.current] } }
        : {}),
      ...(onlineMatch && pvpMatchTokenRef.current ? { pvpToken: pvpMatchTokenRef.current } : {}),
      ...(onlineMatch && pvpMatchPlayerRef.current !== null ? { pvpPlayer: pvpMatchPlayerRef.current } : {}),
    }).then((payload) => {
      if (payload) {
      const rewardGold = payload.rewardGold ?? (result === "draw" ? 0 : result === "win" ? 60 : 20);
      setNotice({
        tone: payload.localFallback ? "info" : "success",
        text: result === "draw"
          ? `对局已${payload.localFallback ? "归入本地演示档案" : "归档"}为平局，任务进度已同步；本局无金币奖励。`
          : rewardGold > 0
            ? `对局已${payload.localFallback ? "归入本地演示档案" : "归档"}，获得 ${rewardGold} 金币，任务进度已同步。`
            : "对局已归档；今日演算奖励已达上限，本局仅计入战绩。",
      });
      }
    });
  }, [battleView, onlineMatch, onlineOpponent, postAction, pvp.state.format, pvp.state.rankedFormat]);

  const totalOwned = Object.values(player.collection).reduce((sum, count) => sum + count, 0);
  const uniqueOwned = Object.values(player.collection).filter((count) => count > 0).length;
  const winRate =
    player.stats.matchesPlayed > 0
      ? Math.round((player.stats.wins / player.stats.matchesPlayed) * 100)
      : 0;
  const apprenticePool = apprenticeMatchPoolForFacts({
    packsOpened: player.packPity?.packsOpened ?? 0,
    matchesPlayed: player.stats.matchesPlayed,
    wins: player.stats.wins,
    level: player.progression?.level ?? 1,
  }) === "apprentice";

  return (
    <div className={`game-shell ${section === "battle" && battleView ? "game-shell--battle-focus" : ""}`}>
      <a className="skip-link" href="#main-content">
        跳到主要内容
      </a>

      <aside className={`sidebar ${sidebarOpen ? "sidebar--open" : ""}`} aria-label="主导航">
        <div className="brand">
          <span className="brand__mark" aria-hidden="true">
            <span />
          </span>
          <div>
            <strong>余烬协议</strong>
            <span>EMBER PROTOCOL</span>
          </div>
          <button
            className="icon-button sidebar__close"
            type="button"
            aria-label="关闭导航"
            onClick={() => setSidebarOpen(false)}
          >
            <Icon name="close" />
          </button>
        </div>

        <nav className="sidebar-nav">
          <span className="sidebar-nav__label">战略终端</span>
          {NAV_ITEMS.map((item) => (
            <button
              className={`nav-item ${section === item.id ? "nav-item--active" : ""}`}
              type="button"
              key={item.id}
              onClick={() => switchSection(item.id)}
              aria-current={section === item.id ? "page" : undefined}
            >
              <span className="nav-item__icon">
                <Icon name={item.icon} />
              </span>
              <span className="nav-item__copy">
                <strong>{item.label}</strong>
                <small>{item.eyebrow}</small>
              </span>
              <span className="nav-item__signal" />
            </button>
          ))}
        </nav>

        <div className="sidebar__status">
          <div className="system-status">
            <span className="system-status__pulse" />
            <div>
              <strong>{profileNodeLabel}</strong>
              <span>内容版本 0.1.0 · CN-07</span>
            </div>
          </div>
          <div className="sidebar__clearance">
            <Icon name="shield" />
            <span>
              <small>指挥权限</small>
              <strong>LEVEL 04</strong>
            </span>
          </div>
        </div>
      </aside>

      {sidebarOpen && (
        <button
          className="sidebar-backdrop"
          type="button"
          aria-label="关闭导航"
          onClick={() => setSidebarOpen(false)}
        />
      )}

      <div className="game-workspace">
        <header className="topbar">
          <button
            className="icon-button topbar__menu"
            type="button"
            aria-label="打开导航"
            onClick={() => setSidebarOpen(true)}
          >
            <Icon name="menu" />
          </button>
          <div className="topbar__breadcrumb">
            <span>{NAV_ITEMS.find((item) => item.id === section)?.eyebrow}</span>
            <strong>{NAV_ITEMS.find((item) => item.id === section)?.label}</strong>
          </div>
          <div className="topbar__resources" aria-label="玩家资源">
            <div className="resource-chip resource-chip--gold">
              <Icon name="coin" size={18} />
              <span>
                <small>金币</small>
                <strong>{player.currencies.gold.toLocaleString("zh-CN")}</strong>
              </span>
            </div>
            <div className="resource-chip resource-chip--dust">
              <Icon name="dust" size={18} />
              <span>
                <small>星尘</small>
                <strong>{player.currencies.dust.toLocaleString("zh-CN")}</strong>
              </span>
            </div>
            <button
              className="resource-chip resource-chip--pack"
              type="button"
              onClick={() => switchSection("overview")}
              aria-label={`${player.packsAvailable} 个可开启卡包`}
            >
              <Icon name="pack" size={18} />
              <span>
                <small>档案包</small>
                <strong>{player.packsAvailable}</strong>
              </span>
            </button>
          </div>
          <div className="profile-chip">
            <span className="profile-chip__avatar" aria-hidden="true">
              {player.displayName.slice(0, 1)}
            </span>
            <span className="profile-chip__copy">
              <strong>{player.displayName}</strong>
              <small>{profileStatusLabel}</small>
            </span>
            {identity?.authenticated ? (
              canLinkDevice ? (
                <button className="profile-chip__auth" type="button" onClick={() => void linkDeviceProfile()}>迁移本机档案</button>
              ) : (
                <a className="profile-chip__auth" href="/signout-with-chatgpt?return_to=%2F">退出</a>
              )
            ) : (
              <a className="profile-chip__auth" href="/signin-with-chatgpt?return_to=%2F">绑定账号</a>
            )}
          </div>
        </header>

        {notice && (
          <div className={`notice notice--${notice.tone}`} role="status">
            <Icon name={notice.tone === "success" ? "check" : notice.tone === "warning" ? "shield" : "spark"} />
            <span>{notice.text}</span>
            <button type="button" className="notice__close" onClick={() => setNotice(null)} aria-label="关闭提示">
              <Icon name="close" size={16} />
            </button>
          </div>
        )}

        <main id="main-content" className="main-content" tabIndex={-1}>
          {loading ? (
            <div className="loading-screen" role="status">
              <span className="loading-screen__scanner" />
              <strong>正在接入星图档案…</strong>
              <p>同步收藏、任务与战术记录</p>
            </div>
          ) : (
            <>
              {section === "overview" && (
                <OverviewSection
                  player={player}
                  winRate={winRate}
                  uniqueOwned={uniqueOwned}
                  totalOwned={totalOwned}
                  openedCards={openedCards}
                  apiBusy={apiBusy}
                  onOpenPack={() => void openPack()}
                  onBuyPack={() => void buyPack()}
                  onClaimTask={(task) => void claimTask(task)}
                  onRerollTask={(task) => void rerollTask(task)}
                  onNavigate={switchSection}
                  onStartBattle={startStandardBattle}
                  onOpenTraining={() => setTrainingBriefingOpen(true)}
                  onClaimApprenticeReward={(milestoneId) => void claimApprenticeReward(milestoneId)}
                />
              )}
              {section === "collection" && (
                <CollectionSection
                  cards={filteredCards}
                  collection={player.collection}
                  dust={player.currencies.dust}
                  deckCounts={deckCounts}
                  search={search}
                  faction={factionFilter}
                  type={typeFilter}
                  rarity={rarityFilter}
                  trait={traitFilter}
                  keyword={keywordFilter}
                  minionType={minionTypeFilter}
                  spellSchool={spellSchoolFilter}
                  factions={factions}
                  traitOptions={traitOptions}
                  keywordOptions={keywordOptions}
                  minionTypeOptions={minionTypeOptions}
                  spellSchoolOptions={spellSchoolOptions}
                  onSearch={setSearch}
                  onFaction={setFactionFilter}
                  onType={setTypeFilter}
                  onRarity={setRarityFilter}
                  onTrait={setTraitFilter}
                  onKeyword={setKeywordFilter}
                  onMinionType={setMinionTypeFilter}
                  onSpellSchool={setSpellSchoolFilter}
                  onAdd={addCard}
                  apiBusy={apiBusy}
                  onCraft={(card) => void changeCardDust("craft_card", card)}
                  onDisenchant={(card) => void changeCardDust("disenchant_card", card)}
                  onOpenDeck={() => switchSection("deck")}
                />
              )}
              {section === "deck" && (
                <DeckSection
                  cards={CATALOG.filter((card) => {
                    const definition = CARD_RULE_BY_ID.get(card.id);
                    return definition ? cardAvailableInRankedFormat(definition, deckFormat) : false;
                  })}
                  collection={player.collection}
                  decks={player.decks}
                  editingDeckId={editingDeckId}
                  deckIds={deckIds}
                  deckCounts={deckCounts}
                  name={deckName}
                  format={deckFormat}
                  validation={deckValidation}
                  missingCards={selectedLadderReadyDeckId ? [] : deckMissingCards}
                  playable={deckPlayable}
                  battleReady={deckPlayable && Boolean(editingDeckId || selectedLadderReadyDeckId)}
                  saving={apiBusy === "save_deck"}
                  deleting={apiBusy === "delete_deck"}
                  ladderReady={player.ladderReady}
                  selectedLadderReadyDeckId={selectedLadderReadyDeckId}
                  ladderReadyBusy={apiBusy === "activate_ladder_ready" || apiBusy === "claim_ladder_ready_deck"}
                  onName={setDeckName}
                  onFormat={(format) => {
                    setDeckFormat(format);
                    if (format === "standard") {
                      setDeckIds((ids) => ids.filter((id) => {
                        const definition = CARD_RULE_BY_ID.get(id);
                        return definition ? cardAvailableInRankedFormat(definition, "standard") : false;
                      }));
                    }
                    setSelectedLadderReadyDeckId(null);
                  }}
                  onSelectDeck={selectDeck}
                  onNewDeck={createNewDeck}
                  onAdd={addCard}
                  onRemove={removeCard}
                  onAutoComplete={autoCompleteDeck}
                  onApplyRecipe={applyDeckRecipe}
                  onSave={() => void saveDeck()}
                  onDelete={() => void deleteCurrentDeck()}
                  onImport={importDeck}
                  onReplaceMissing={replaceMissingCard}
                  onBattle={startStandardBattle}
                  onActivateLadderReady={() => void activateLadderReady()}
                  onTrialLadderReady={trialLadderReadyDeck}
                  onClaimLadderReady={(deckId) => void claimLadderReady(deckId)}
                />
              )}
              {section === "battle" && (
                <BattleSection
                  battle={battleView}
                  message={battleMessage}
                  effect={battleEffect}
                  inspectedCard={inspectedCard}
                  onInspectCard={setInspectedCard}
                  onCloseInspector={() => setInspectedCard(null)}
                  selectedAttacker={selectedAttacker}
                  pendingCard={pendingCard}
                  pendingHeroPower={pendingHeroPower}
                  mulliganSelection={mulliganSelection}
                  busy={apiBusy === "record_match"}
                  effectsLocked={battleEffectsLocked}
                  effectCount={battleEffectCount}
                  turnClockSeconds={battleTurnClockSeconds}
                  soundEnabled={soundEnabled}
                  replaySlow={battleReplaySlow}
                  onStart={startStandardBattle}
                  onRematch={requestOnlineRematch}
                  onReturnLobby={returnToBattleLobby}
                  onPlayCard={playCard}
                  onTradeCard={tradeCard}
                  onPrepareCard={prepareCard}
                  onChooseDiscover={chooseDiscover}
                  onChooseOne={chooseOne}
                  onToggleMulligan={toggleMulliganCard}
                  onConfirmMulligan={confirmMulligan}
                  onSelectAttacker={(id) => {
                    setPendingCard(null);
                    setPendingCardPlacement("friendly");
                    setPendingHeroPower(false);
                    setSelectedAttacker((current) => (current === id ? null : id));
                    playSound("select");
                  }}
                  onSelectHeroAttacker={selectHeroAttacker}
                  onCardTarget={playCardAtTarget}
                  onCancelTarget={() => {
                    setPendingCard(null);
                    setPendingCardPlacement("friendly");
                    setPendingHeroPower(false);
                    setSelectedAttacker(null);
                    setBattleMessage("已取消目标选择，可继续行动。");
                  }}
                  onAttack={attackTarget}
                  onHeroPower={useHeroPower}
                  onEndTurn={endTurn}
                  onSkipEffects={skipBattleReplay}
                  onConcede={concedeBattle}
                  onOpenDeck={() => switchSection("deck")}
                  onToggleSound={toggleSound}
                  onToggleReplaySpeed={toggleBattleReplaySpeed}
                  trainingActive={trainingActive}
                  onExitTraining={() => setTrainingActive(false)}
                  pvp={pvp.state}
                  apprenticePool={apprenticePool}
                  aiArchetypes={AI_ARCHETYPES}
                  aiArchetypeId={aiArchetypeId}
                  onAiArchetype={setAiArchetypeId}
                  pvpUrl={pvpUrl}
                  pvpRoomInput={pvpRoomInput}
                  onPvpUrl={setPvpUrl}
                  onPvpRoomInput={setPvpRoomInput}
                  onPvpConnect={() => pvp.connect(pvpUrl)}
                  onPvpCreate={(format, rankedFormat) => pvp.createRoom(format, rankedFormat)}
                  onPvpQueue={(format, rankedFormat) => pvp.queue(format, rankedFormat)}
                  onPvpLeaveQueue={() => pvp.leaveQueue()}
                  onPvpFallbackAi={() => {
                    pvp.disconnect();
                    void startStandardBattle();
                  }}
                  onPvpJoin={() => pvp.joinRoom(pvpRoomInput)}
                  onPvpReady={() => {
                    const validation = validateDeckForFormat(deckIds, pvp.state.rankedFormat);
                    if (!validation.valid) {
                      setNotice({ tone: "warning", text: `当前卡组不能进入${rankedFormatLabel(pvp.state.rankedFormat)}：${validation.errors[0]?.message ?? "卡组无效"}` });
                      return;
                    }
                    const missing = findMissingDeckCards(deckIds, player.collection);
                    if (!selectedLadderReadyDeckId && missing.length > 0) {
                      setNotice({ tone: "warning", text: "当前卡组包含未拥有的卡牌，请先制作或替换。" });
                      return;
                    }
                    pvp.ready(deckIds);
                  }}
                  onPvpDisconnect={() => pvp.disconnect()}
                  online={onlineMatch}
                  opponentName={onlineOpponent}
                />
              )}
              {section === "operations" && (
                <OperationsSection
                  key={`${player.id}-${player.displayName}`}
                  player={player}
                  winRate={winRate}
                  isDemo={isDemo}
                  resetting={apiBusy === "reset_demo"}
                  onResetDemo={() => void resetDemoProfile()}
                  onClaimReward={(level) => void claimReward(level)}
                  rewardBusy={apiBusy === "claim_reward"}
                  onClaimWeeklyPack={() => void claimWeeklyPack()}
                  weeklyPackBusy={apiBusy === "claim_weekly_pack"}
                  onUpdateProfile={(displayName) => void updateProfile(displayName)}
                  profileBusy={apiBusy === "update_profile"}
                  onSendFriendRequest={(friendId) => void sendFriendRequest(friendId)}
                  onAcceptFriendRequest={(friendId) => void acceptFriendRequest(friendId)}
                  onSendChat={(friendId, text) => void sendChatMessage(friendId, text)}
                  onBlockPlayer={(targetId) => void blockPlayer(targetId)}
                  onUnblockPlayer={(targetId) => void unblockPlayer(targetId)}
                  onReportPlayer={(targetId, reason) => void reportPlayer(targetId, reason)}
                  socialBusy={apiBusy === "send_friend_request" || apiBusy === "accept_friend_request" || apiBusy === "send_chat" || apiBusy === "block_player" || apiBusy === "unblock_player" || apiBusy === "report_player"}
                />
              )}
            </>
          )}
        </main>
        {trainingBriefingOpen && (
          <TrainingBriefing
            onClose={() => setTrainingBriefingOpen(false)}
            onStart={startTrainingBattle}
          />
        )}
      </div>
    </div>
  );
}

function TrainingBriefing({
  onClose,
  onStart,
}: {
  onClose: () => void;
  onStart: () => void;
}) {
  const lessons = [
    {
      number: "01",
      title: "守住核心",
      copy: "双方核心拥有 30 点生命。让敌方核心归零，即可赢得对局。",
      accent: "core",
    },
    {
      number: "02",
      title: "规划能量",
      copy: "每回合能量上限增加 1 点并补满。先部署低费单位，避免浪费行动窗口。",
      accent: "mana",
    },
    {
      number: "03",
      title: "建立战线",
      copy: "单位通常要等待一回合才能攻击；嘲讽会保护其他目标，护盾能抵消一次伤害。",
      accent: "board",
    },
    {
      number: "04",
      title: "读懂协议",
      copy: "同名单位可升为二星；部署 2/4 个不同同类单位，会启动更强的特质联动。",
      accent: "trait",
    },
  ] as const;

  return (
    <div className="training-briefing-backdrop" role="presentation" onClick={onClose}>
      <section
        className="training-briefing"
        role="dialog"
        aria-modal="true"
        aria-labelledby="training-briefing-title"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="training-briefing__heading">
          <div>
            <span>CADET BRIEFING / 4 STEPS</span>
            <h2 id="training-briefing-title">三分钟掌握第一场对局</h2>
            <p>训练模式会在战场侧边持续提示下一步，但不会替你做决定。</p>
          </div>
          <button type="button" onClick={onClose} aria-label="关闭新手训练说明">
            <Icon name="close" size={18} />
          </button>
        </div>
        <ol className="training-briefing__lessons">
          {lessons.map((lesson) => (
            <li className={`training-lesson training-lesson--${lesson.accent}`} key={lesson.number}>
              <span>{lesson.number}</span>
              <div><strong>{lesson.title}</strong><p>{lesson.copy}</p></div>
            </li>
          ))}
        </ol>
        <div className="training-briefing__actions">
          <button className="button button--ghost" type="button" onClick={onClose}>稍后再看</button>
          <button className="button button--primary button--large" type="button" onClick={onStart}>
            <Icon name="swords" />进入引导对局
          </button>
        </div>
      </section>
    </div>
  );
}

function OverviewSection({
  player,
  winRate,
  uniqueOwned,
  totalOwned,
  openedCards,
  apiBusy,
  onOpenPack,
  onBuyPack,
  onClaimTask,
  onRerollTask,
  onNavigate,
  onStartBattle,
  onOpenTraining,
  onClaimApprenticeReward,
}: {
  player: PlayerSnapshot;
  winRate: number;
  uniqueOwned: number;
  totalOwned: number;
  openedCards: Array<{ cardId: string; count: number }>;
  apiBusy: string | null;
  onOpenPack: () => void;
  onBuyPack: () => void;
  onClaimTask: (task: PlayerTask) => void;
  onRerollTask: (task: PlayerTask) => void;
  onNavigate: (section: SectionKey) => void;
  onStartBattle: () => void;
  onOpenTraining: () => void;
  onClaimApprenticeReward: (milestoneId: ApprenticeMilestoneId) => void;
}) {
  const [clockNow, setClockNow] = useState(0);
  useEffect(() => {
    const tick = () => setClockNow(Date.now());
    tick();
    const timer = window.setInterval(tick, 1000);
    return () => window.clearInterval(timer);
  }, []);
  const apprenticeFacts = {
    packsOpened: player.packPity?.packsOpened ?? 0,
    matchesPlayed: player.stats.matchesPlayed,
    wins: player.stats.wins,
    level: player.progression?.level ?? 1,
  };
  const claimedApprenticeMilestones = player.apprenticeTrack?.claimedMilestones ?? [];
  const completedApprenticeMilestones = APPRENTICE_MILESTONES.filter((milestone) =>
    apprenticeMilestoneComplete(milestone, apprenticeFacts),
  ).length;
  const settledApprenticeMilestones = APPRENTICE_MILESTONES.filter((milestone) =>
    claimedApprenticeMilestones.includes(milestone.id),
  ).length;
  const apprenticeRouteComplete = apprenticeTrackComplete(apprenticeFacts);
  const startMilestoneAction = (milestoneId: ApprenticeMilestoneId) => {
    if (milestoneId === "decode-first-pack") {
      onOpenPack();
      return;
    }
    if (milestoneId === "reach-level-two") {
      onNavigate("operations");
      return;
    }
    onStartBattle();
  };
  const apprenticeActionLabel = (milestoneId: ApprenticeMilestoneId) => {
    if (milestoneId === "decode-first-pack") return "打开卡包";
    if (milestoneId === "reach-level-two") return "查看任务";
    if (milestoneId === "win-first-match") return "挑战 AI";
    return "开始对战";
  };

  return (
    <section className="screen screen--overview" aria-labelledby="overview-title">
      <SectionHeading
        eyebrow="COMMAND CENTER / 07"
        title="战情总览"
        description="指挥官，星域演算已完成。你的战术资产与今日行动目标如下。"
        action={
          <button className="button button--primary" type="button" onClick={onStartBattle}>
            <Icon name="swords" />
            开始 AI 演算
          </button>
        }
      />

      <section className="training-callout" aria-labelledby="training-callout-title">
        <span className="training-callout__sigil" aria-hidden="true"><Icon name="shield" size={26} /></span>
        <div className="training-callout__copy">
          <span>CADET ROUTE · 随时重练</span>
          <h2 id="training-callout-title">第一次指挥？先完成一场三分钟训练</h2>
          <p>从换牌、能量、部署到攻击，战场会逐步标记你当前应该关注的行动。</p>
        </div>
        <div className="training-callout__route" aria-label="训练路线：换牌、部署、攻击、结束回合">
          <span><i>1</i>换牌</span><b />
          <span><i>2</i>部署</span><b />
          <span><i>3</i>攻击</span><b />
          <span><i>4</i>回合</span>
        </div>
        <button className="button button--accent" type="button" onClick={onOpenTraining}>
          开始新手训练 <Icon name="arrow" />
        </button>
      </section>

      <section className={`apprentice-track ${apprenticeRouteComplete ? "is-complete" : ""}`} aria-labelledby="apprentice-track-title">
        <div className="apprentice-track__header">
          <div>
            <span className="panel__eyebrow">CADET ASCENSION / SERVER VERIFIED</span>
            <h2 id="apprentice-track-title">新兵晋升轨道</h2>
            <p>{apprenticeRouteComplete
              ? "四个成长目标已经完成，快速匹配已自动转入常规水平池；未领取奖励仍可随时补领。"
              : "快速匹配由服务器锁定在新兵保护池；完成四个实战目标后自动毕业，不受奖励是否领取影响。"}</p>
          </div>
          <div className={`apprentice-track__pool ${apprenticeRouteComplete ? "is-standard" : "is-protected"}`}>
            <Icon name={apprenticeRouteComplete ? "check" : "shield"} size={18} />
            <span>
              <small>{apprenticeRouteComplete ? "MATCH POOL · GRADUATED" : "MATCH POOL · PROTECTED"}</small>
              <strong>{apprenticeRouteComplete ? "常规水平匹配" : "新兵专属匹配"}</strong>
            </span>
          </div>
          <div className="apprentice-track__summary">
            <strong>{settledApprenticeMilestones}<i> / {APPRENTICE_MILESTONES.length}</i></strong>
            <span>奖励已领取 · {completedApprenticeMilestones} 项目标达成</span>
          </div>
        </div>
        <ProgressBar
          value={settledApprenticeMilestones}
          max={APPRENTICE_MILESTONES.length}
          label="新兵晋升轨道奖励领取进度"
        />
        <ol className="apprentice-track__steps">
          {APPRENTICE_MILESTONES.map((milestone, index) => {
            const progress = apprenticeMilestoneProgress(milestone, apprenticeFacts);
            const complete = apprenticeMilestoneComplete(milestone, apprenticeFacts);
            const claimed = claimedApprenticeMilestones.includes(milestone.id);
            const rewardLabel = milestone.reward.kind === "gold"
              ? "金币"
              : milestone.reward.kind === "pack"
                ? "档案包"
                : "星尘";
            return (
              <li className={`apprentice-step ${claimed ? "is-claimed" : complete ? "is-ready" : ""}`} key={milestone.id}>
                <span className="apprentice-step__index">{claimed ? <Icon name="check" size={16} /> : String(index + 1).padStart(2, "0")}</span>
                <div className="apprentice-step__body">
                  <span>{complete ? claimed ? "REWARD SECURED" : "OBJECTIVE COMPLETE" : "CADET OBJECTIVE"}</span>
                  <h3>{milestone.title}</h3>
                  <p>{milestone.description}</p>
                  <div className="apprentice-step__progress">
                    <span style={{ width: `${Math.min(100, (progress / milestone.target) * 100)}%` }} />
                  </div>
                  <small>{progress} / {milestone.target} · 奖励 {rewardLabel} × {milestone.reward.amount}</small>
                </div>
                <button
                  className={`button button--small ${complete && !claimed ? "button--accent" : "button--muted"}`}
                  type="button"
                  disabled={claimed || apiBusy === "claim_apprentice_reward"}
                  onClick={() => complete ? onClaimApprenticeReward(milestone.id) : startMilestoneAction(milestone.id)}
                >
                  {claimed ? "已领取" : complete ? "领取奖励" : apprenticeActionLabel(milestone.id)}
                </button>
              </li>
            );
          })}
        </ol>
      </section>

      <div className="overview-hero">
        <div className="overview-hero__copy">
          <span className="eyebrow-tag">
            <i />
            边境信标 · 在线
          </span>
          <h2>
            欢迎归舰，<em>{player.displayName}</em>
          </h2>
          <p>裂隙边缘出现新的能量扰动。完成今日演算，解锁额外档案权限与战术资源。</p>
          <div className="overview-hero__actions">
            <button className="button button--primary" type="button" onClick={onStartBattle}>
              部署战术
              <Icon name="arrow" />
            </button>
            <button className="button button--ghost" type="button" onClick={() => onNavigate("deck")}>
              检查卡组
            </button>
          </div>
        </div>
        <div className="overview-hero__radar" aria-hidden="true">
          <span className="radar__ring radar__ring--one" />
          <span className="radar__ring radar__ring--two" />
          <span className="radar__ring radar__ring--three" />
          <span className="radar__sweep" />
          <span className="radar__target radar__target--one" />
          <span className="radar__target radar__target--two" />
          <span className="radar__core">
            <Icon name="radar" size={30} />
          </span>
        </div>
      </div>

      <div className="metric-grid">
        <article className="metric-card">
          <span className="metric-card__icon metric-card__icon--cyan">
            <Icon name="swords" />
          </span>
          <span className="metric-card__label">演算胜率</span>
          <strong>{winRate}%</strong>
          <small>{player.stats.wins} 胜 · {player.stats.losses} 负</small>
        </article>
        <article className="metric-card">
          <span className="metric-card__icon metric-card__icon--violet">
            <Icon name="cards" />
          </span>
          <span className="metric-card__label">卡牌档案</span>
          <strong>{uniqueOwned}<i> / {CATALOG.length}</i></strong>
          <small>共持有 {totalOwned} 张卡牌</small>
        </article>
        <article className="metric-card">
          <span className="metric-card__icon metric-card__icon--amber">
            <Icon name="layers" />
          </span>
          <span className="metric-card__label">有效卡组</span>
          <strong>{player.decks.length}</strong>
          <small>{player.decks[0]?.name ?? "尚未建立"}</small>
        </article>
        <article className="metric-card">
          <span className="metric-card__icon metric-card__icon--green">
            <Icon name="spark" />
          </span>
          <span className="metric-card__label">今日任务</span>
          <strong>{player.tasks.filter((task) => task.progress >= task.target).length}<i> / {player.tasks.length}</i></strong>
          <small>{player.tasks.some((task) => task.progress >= task.target && !task.claimed) ? "存在可领取奖励" : "继续执行战术"}</small>
        </article>
        <article className="metric-card">
          <span className="metric-card__icon metric-card__icon--violet">
            <Icon name="spark" />
          </span>
          <span className="metric-card__label">奖励轨道</span>
          <strong>Lv.{player.progression?.level ?? 1}</strong>
          <small>{player.progression?.xp ?? 0} XP · 每 1,000 XP 升级</small>
        </article>
      </div>

      <div className="overview-columns">
        <section className="panel missions-panel" aria-labelledby="missions-title">
          <div className="panel__header">
            <div>
              <span className="panel__eyebrow">DAILY DIRECTIVES</span>
              <h2 id="missions-title">今日行动指令</h2>
            </div>
            <span className="panel__counter">{player.tasks.length} 项</span>
          </div>
          <div className="mission-list">
            {player.tasks.map((task) => {
              const ready = task.progress >= task.target;
              return (
                <article className={`mission ${task.claimed ? "mission--claimed" : ""}`} key={task.id}>
                  <span className="mission__status">
                    {task.claimed ? <Icon name="check" /> : <span>{Math.min(task.progress, task.target)}</span>}
                  </span>
                  <div className="mission__body">
                    <div className="mission__heading">
                      <div>
                        <h3>{task.title}</h3>
                        <p>{task.description}</p>
                      </div>
                      <span className="mission__reward">
                        <Icon name="coin" size={15} />
                        {task.rewardGold}
                      </span>
                    </div>
                    <div className="mission__progress-row">
                      <ProgressBar value={task.progress} max={task.target} label={`${task.title}进度`} />
                      <small>{Math.min(task.progress, task.target)} / {task.target}</small>
                    </div>
                  </div>
                  <button
                    className={`button button--small ${ready && !task.claimed ? "button--accent" : "button--muted"}`}
                    type="button"
                    disabled={!ready || task.claimed || apiBusy === "claim_task"}
                    onClick={() => onClaimTask(task)}
                  >
                    {task.claimed ? "已领取" : ready ? "领取" : "进行中"}
                  </button>
                  {!task.claimed && !ready && task.period !== "weekly" && task.progress === 0 && (
                    <button
                      className="button button--small button--muted"
                      type="button"
                      disabled={apiBusy === "reroll_task" || player.taskCycle?.dailyRerollsRemaining === 0}
                      onClick={() => onRerollTask(task)}
                      title="每日可重随 1 个未开始的日常任务"
                    >
                      重随
                    </button>
                  )}
                </article>
              );
            })}
          </div>
        </section>

        <section className="panel pack-panel" aria-labelledby="pack-title">
          <div className="panel__header">
            <div>
              <span className="panel__eyebrow">ARCHIVE DROP</span>
              <h2 id="pack-title">免费档案包</h2>
            </div>
            <span className="pack-panel__timer"><Icon name="clock" size={15} /> {formatUtcResetCountdown("day", clockNow)} 刷新</span>
          </div>
          {openedCards.length > 0 ? (
            <div className="pack-reveal">
              <div className="pack-reveal__cards">
                {openedCards.map((entry, index) => {
                  const card = CARD_BY_ID.get(entry.cardId);
                  return (
                    <div className={`mini-reveal mini-reveal--${card?.rarity ?? "common"}`} key={`${entry.cardId}-${index}`}>
                      {card && <CardArtwork card={card} className="mini-reveal__artwork" />}
                      <span className="mini-reveal__cost">{card?.cost ?? 0}</span>
                      <span className="mini-reveal__copy">
                        <strong>{card?.name ?? entry.cardId}</strong>
                        <small>×{entry.count}</small>
                      </span>
                    </div>
                  );
                })}
              </div>
              <p>新档案已同步至你的收藏。</p>
              <button className="button button--ghost button--wide" type="button" onClick={() => onNavigate("collection")}>
                查看收藏
              </button>
              <button className="button button--outline button--wide" type="button" onClick={onBuyPack} disabled={apiBusy === "buy_pack" || player.currencies.gold < 100}>
                <Icon name="coin" />
                {apiBusy === "buy_pack" ? "购买中…" : "100 金币购买卡包"}
              </button>
            </div>
          ) : (
            <div className="pack-offer">
              <button
                className="pack-object"
                type="button"
                onClick={onOpenPack}
                disabled={apiBusy === "open_pack" || player.packsAvailable <= 0}
                aria-label="开启免费档案包"
              >
                <span className="pack-object__halo" />
                <span className="pack-object__shell">
                  <Icon name="spark" size={36} />
                </span>
                <span className="pack-object__count">× {player.packsAvailable}</span>
              </button>
              <h3>{player.packsAvailable > 0 ? "有一份加密档案等待解锁" : "今日档案已解密"}</h3>
              <p>每份包含 5 张随机卡牌，至少 1 张稀有或更高品质。</p>
              <button
                className="button button--primary button--wide"
                type="button"
                onClick={onOpenPack}
                disabled={apiBusy === "open_pack" || player.packsAvailable <= 0}
              >
                <Icon name="pack" />
                {apiBusy === "open_pack" ? "解密中…" : player.packsAvailable > 0 ? "免费开启" : "明日再来"}
              </button>
              <button
                className="button button--outline button--wide"
                type="button"
                onClick={onBuyPack}
                disabled={apiBusy === "buy_pack" || player.currencies.gold < 100}
              >
                <Icon name="coin" />
                {apiBusy === "buy_pack" ? "购买中…" : "100 金币购买卡包"}
              </button>
            </div>
          )}
        </section>
      </div>

      <RecentMatches matches={player.recentMatches} />
    </section>
  );
}

function RecentMatches({ matches }: { matches: RecentMatch[] }) {
  return (
    <section className="panel recent-panel" aria-labelledby="recent-title">
      <div className="panel__header">
        <div>
          <span className="panel__eyebrow">COMBAT RECORDS</span>
          <h2 id="recent-title">近期演算记录</h2>
        </div>
        <span className="panel__counter">最近 {matches.length} 场</span>
      </div>
      {matches.length === 0 ? (
        <EmptyState icon="swords" title="尚无对局记录">完成第一场 AI 演算后，战报会在这里归档。</EmptyState>
      ) : (
        <div className="match-list">
          {matches.slice(0, 5).map((match) => (
            <article className="match-row" key={match.id}>
              <span className={`match-row__result match-row__result--${match.result}`}>
                {match.result === "win" ? "胜" : match.result === "draw" ? "平" : "负"}
              </span>
              <div className="match-row__opponent">
                <span className="match-row__avatar"><Icon name="bot" /></span>
                <span><strong>{match.opponent}</strong><small>{match.mode === "pvp" ? (match.format === "casual" ? "CASUAL 休闲" : "RANKED 天梯") : "AI 演算"}</small></span>
              </div>
              <span className="match-row__time">{formatTime(match.createdAt)}</span>
              <span className="match-row__reward">
                {match.result === "draw" && match.rewardGold === 0
                  ? "无金币"
                  : <><Icon name="coin" size={15} /> +{match.rewardGold}</>}
              </span>
            </article>
          ))}
        </div>
      )}
    </section>
  );
}

function CollectionSection({
  cards,
  collection,
  dust,
  deckCounts,
  search,
  faction,
  type,
  rarity,
  trait,
  keyword,
  minionType,
  spellSchool,
  factions,
  traitOptions,
  keywordOptions,
  minionTypeOptions,
  spellSchoolOptions,
  onSearch,
  onFaction,
  onType,
  onRarity,
  onTrait,
  onKeyword,
  onMinionType,
  onSpellSchool,
  onAdd,
  apiBusy,
  onCraft,
  onDisenchant,
  onOpenDeck,
}: {
  cards: CatalogCard[];
  collection: Record<string, number>;
  dust: number;
  deckCounts: Map<string, number>;
  search: string;
  faction: string;
  type: string;
  rarity: string;
  trait: string;
  keyword: string;
  minionType: string;
  spellSchool: string;
  factions: string[];
  traitOptions: Array<{ id: Trait; label: string }>;
  keywordOptions: Array<{ id: Keyword; label: string }>;
  minionTypeOptions: Array<{ id: MinionType; label: string }>;
  spellSchoolOptions: Array<{ id: SpellSchool; label: string }>;
  onSearch: (value: string) => void;
  onFaction: (value: string) => void;
  onType: (value: string) => void;
  onRarity: (value: string) => void;
  onTrait: (value: string) => void;
  onKeyword: (value: string) => void;
  onMinionType: (value: string) => void;
  onSpellSchool: (value: string) => void;
  onAdd: (card: CatalogCard) => void;
  apiBusy: string | null;
  onCraft: (card: CatalogCard) => void;
  onDisenchant: (card: CatalogCard) => void;
  onOpenDeck: () => void;
}) {
  const filterSignature = `${search}|${faction}|${type}|${rarity}|${trait}|${keyword}|${minionType}|${spellSchool}`;
  const [pagination, setPagination] = useState({ signature: filterSignature, count: 30 });
  const visibleCount = pagination.signature === filterSignature ? pagination.count : 30;
  const visibleCards = cards.slice(0, visibleCount);

  return (
    <section className="screen screen--collection" aria-labelledby="collection-title">
      <SectionHeading
        eyebrow="TACTICAL ARCHIVE / COLLECTION"
        title="卡牌收藏"
        description="浏览 20 个体系共 1000 张档案，按卡牌类型、随从类型、法术派系、特质与关键词检索，并围绕可查询的类型联动规划牌组。"
        action={
          <button className="button button--outline" type="button" onClick={onOpenDeck}>
            <Icon name="layers" />
            当前卡组 {Array.from(deckCounts.values()).reduce((sum, count) => sum + count, 0)} / 30
          </button>
        }
      />

      <div className="faction-codex" aria-label="20个卡牌体系">
        {(Object.entries(FACTION_DEFINITIONS) as Array<
          [Faction, (typeof FACTION_DEFINITIONS)[Faction]]
        >).map(([name, definition]) => {
          const count = CATALOG.filter((card) => card.faction === name).length;
          return (
            <button
              className={`faction-codex__item faction-codex__item--${definition.tone} ${faction === name ? "is-active" : ""}`}
              type="button"
              onClick={() => onFaction(faction === name ? "全部" : name)}
              aria-pressed={faction === name}
              key={name}
            >
              <span>{definition.sigil}</span>
              <strong>{name}</strong>
              <small>{definition.doctrine}<i>{count} 张</i></small>
            </button>
          );
        })}
      </div>

      <div className="collection-toolbar">
        <label className="search-field">
          <span className="sr-only">搜索卡牌</span>
          <Icon name="search" size={18} />
          <input
            type="search"
            value={search}
            onChange={(event) => onSearch(event.target.value)}
            placeholder="搜索名称或战术描述…"
          />
          {search && (
            <button type="button" onClick={() => onSearch("")} aria-label="清除搜索">
              <Icon name="close" size={15} />
            </button>
          )}
        </label>
        <label className="filter-field">
          <span>阵营</span>
          <select value={faction} onChange={(event) => onFaction(event.target.value)}>
            {factions.map((item) => <option key={item}>{item}</option>)}
          </select>
        </label>
        <label className="filter-field">
          <span>类型</span>
          <select value={type} onChange={(event) => onType(event.target.value)}>
            <option value="全部">全部</option>
            <option value="unit">单位</option>
            <option value="spell">战术</option>
            <option value="weapon">武器</option>
            <option value="hero">英雄</option>
          </select>
        </label>
        <label className="filter-field">
          <span>稀有度</span>
          <select value={rarity} onChange={(event) => onRarity(event.target.value)}>
            <option value="全部">全部</option>
            <option value="common">普通</option>
            <option value="rare">稀有</option>
            <option value="epic">史诗</option>
            <option value="legendary">传说</option>
          </select>
        </label>
        <label className="filter-field">
          <span>随从类型</span>
          <select value={minionType} onChange={(event) => onMinionType(event.target.value)}>
            <option value="全部">全部</option>
            {minionTypeOptions.map((item) => (
              <option value={item.id} key={item.id}>{item.label}</option>
            ))}
          </select>
        </label>
        <label className="filter-field">
          <span>法术派系</span>
          <select value={spellSchool} onChange={(event) => onSpellSchool(event.target.value)}>
            <option value="全部">全部</option>
            {spellSchoolOptions.map((item) => (
              <option value={item.id} key={item.id}>{item.label}</option>
            ))}
          </select>
        </label>
        <label className="filter-field">
          <span>特质</span>
          <select value={trait} onChange={(event) => onTrait(event.target.value)}>
            <option value="全部">全部</option>
            {traitOptions.map((item) => (
              <option value={item.id} key={item.id}>{item.label}</option>
            ))}
          </select>
        </label>
        <label className="filter-field">
          <span>关键词</span>
          <select value={keyword} onChange={(event) => onKeyword(event.target.value)}>
            <option value="全部">全部</option>
            {keywordOptions.map((item) => (
              <option value={item.id} key={item.id}>{item.label}</option>
            ))}
          </select>
        </label>
      </div>

      <div className="collection-summary">
        <span><i className="summary-dot summary-dot--online" /> 显示 {visibleCards.length} / {cards.length} 张档案</span>
        <span>点击卡牌加入当前卡组</span>
      </div>

      {cards.length > 0 ? (
        <>
          <div className="card-grid">
            {visibleCards.map((card) => {
              const owned = collection[card.id] ?? 0;
              const inDeck = deckCounts.get(card.id) ?? 0;
              const rarity = card.rarity === "common" ? "普通" : card.rarity === "rare" ? "稀有" : card.rarity === "epic" ? "史诗" : "传说";
              const craftPrice = craftCost(rarity);
              const dustValue = disenchantValue(rarity);
              return (
                <div className="collection-card-wrap" key={card.id}>
                  <CardTile
                    card={card}
                    owned={owned}
                    countInDeck={inDeck}
                    action={() => onAdd(card)}
                    actionLabel={`将${card.name}加入当前卡组`}
                  />
                  <div className="collection-card-actions">
                    <button
                      className="button button--tiny button--outline"
                      type="button"
                      disabled={apiBusy !== null || dust < craftPrice}
                      onClick={() => onCraft(card)}
                    >
                      制作 · {craftPrice} ✦
                    </button>
                    <button
                      className="button button--tiny button--muted"
                      type="button"
                      disabled={apiBusy !== null || owned <= inDeck}
                      onClick={() => onDisenchant(card)}
                    >
                      分解 · +{dustValue} ✦
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
          {visibleCount < cards.length && (
            <div className="collection-load-more">
              <button
                className="button button--outline"
                type="button"
                onClick={() => setPagination({ signature: filterSignature, count: visibleCount + 30 })}
              >
                再加载 {Math.min(30, cards.length - visibleCount)} 张
              </button>
            </div>
          )}
        </>
      ) : (
        <EmptyState icon="search" title="未找到匹配档案">
          调整搜索词或筛选条件，重新扫描卡牌数据库。
        </EmptyState>
      )}
    </section>
  );
}

function DeckSection({
  cards,
  collection,
  decks,
  editingDeckId,
  deckIds,
  deckCounts,
  name,
  format,
  validation,
  missingCards,
  playable,
  battleReady,
  saving,
  deleting,
  ladderReady,
  selectedLadderReadyDeckId,
  ladderReadyBusy,
  onName,
  onFormat,
  onSelectDeck,
  onNewDeck,
  onAdd,
  onRemove,
  onAutoComplete,
  onApplyRecipe,
  onSave,
  onDelete,
  onImport,
  onReplaceMissing,
  onBattle,
  onActivateLadderReady,
  onTrialLadderReady,
  onClaimLadderReady,
}: {
  cards: CatalogCard[];
  collection: Record<string, number>;
  decks: SavedDeck[];
  editingDeckId: string | null;
  deckIds: string[];
  deckCounts: Map<string, number>;
  name: string;
  format: RankedFormat;
  validation: ValidationView;
  missingCards: MissingDeckCard[];
  playable: boolean;
  battleReady: boolean;
  saving: boolean;
  deleting: boolean;
  ladderReady?: PlayerSnapshot["ladderReady"];
  selectedLadderReadyDeckId: LadderReadyDeckId | null;
  ladderReadyBusy: boolean;
  onName: (name: string) => void;
  onFormat: (format: RankedFormat) => void;
  onSelectDeck: (deckId: string) => void;
  onNewDeck: () => void;
  onAdd: (card: CatalogCard) => void;
  onRemove: (cardId: string) => void;
  onAutoComplete: () => void;
  onApplyRecipe: (recipe: DeckRecipe) => void;
  onSave: () => void;
  onDelete: () => void;
  onImport: (code: string) => boolean;
  onReplaceMissing: (missingCardId: string, replacementCardId: string) => void;
  onBattle: () => void;
  onActivateLadderReady: () => void;
  onTrialLadderReady: (deckId: LadderReadyDeckId) => void;
  onClaimLadderReady: (deckId: LadderReadyDeckId) => void;
}) {
  const [deckCode, setDeckCode] = useState("");
  const [copiedDeckFingerprint, setCopiedDeckFingerprint] = useState<string | null>(null);
  const [claimConfirmation, setClaimConfirmation] = useState<LadderReadyDeckId | null>(null);
  const [recipeFaction, setRecipeFaction] = useState<Faction>(() =>
    factionForDeck(deckIds) ?? "曜光"
  );
  const deckFingerprint = `${format}\u0000${name}\u0000${deckIds.join(",")}`;
  const [clockNow, setClockNow] = useState(0);
  useEffect(() => {
    const tick = () => setClockNow(Date.now());
    tick();
    const interval = window.setInterval(tick, 30_000);
    return () => window.clearInterval(interval);
  }, []);
  const trialActivated = Boolean(ladderReady?.activatedAt && ladderReady.expiresAt);
  const trialExpired = Boolean(ladderReady?.expiresAt && clockNow && Date.parse(ladderReady.expiresAt) <= clockNow);
  const trialClaimed = Boolean(ladderReady?.claimedDeckId);
  const trialPlayable = ladderReadyTrialIsActive(ladderReady, clockNow);
  const uniqueDeckCards = Array.from(deckCounts.entries())
    .map(([id, count]) => ({ card: CARD_BY_ID.get(id), count }))
    .filter((entry): entry is { card: CatalogCard; count: number } => Boolean(entry.card))
    .sort((a, b) => a.card.cost - b.card.cost || a.card.name.localeCompare(b.card.name, "zh-CN"));
  const manaCurve = Array.from({ length: 8 }, (_, cost) => {
    const count = deckIds.filter((id) => {
      const cardCost = CARD_BY_ID.get(id)?.cost ?? 0;
      return cost === 7 ? cardCost >= 7 : cardCost === cost;
    }).length;
    return { cost: cost === 7 ? "7+" : String(cost), count };
  });
  const maxCurve = Math.max(1, ...manaCurve.map((item) => item.count));
  const unitCount = deckIds.filter(
    (id) => CARD_BY_ID.get(id)?.type === "unit",
  ).length;
  const weaponCount = deckIds.filter(
    (id) => CARD_BY_ID.get(id)?.type === "weapon",
  ).length;
  const heroCount = deckIds.filter(
    (id) => CARD_BY_ID.get(id)?.type === "hero",
  ).length;
  const spellCount = deckIds.length - unitCount - weaponCount - heroCount;
  const traitStatuses = getTraitStatuses(
    uniqueDeckCards.map(({ card }) => card),
  );
  const keywordProfile = (Object.keys(KEYWORD_DEFINITIONS) as Keyword[])
    .map((keyword) => ({
      keyword,
      count: deckIds.filter((id) =>
        CARD_BY_ID.get(id)?.keywords.includes(keyword),
      ).length,
    }))
    .filter((item) => item.count > 0);
  const minionTypeProfile = MINION_TYPE_ORDER
    .map((minionType) => ({
      minionType,
      count: deckIds.filter((id) =>
        CARD_BY_ID.get(id)?.minionTypes.includes(minionType),
      ).length,
    }))
    .filter((item) => item.count > 0);
  const spellSchoolProfile = SPELL_SCHOOL_ORDER
    .map((school) => ({
      school,
      count: deckIds.filter((id) => CARD_BY_ID.get(id)?.school === school).length,
    }))
    .filter((item) => item.count > 0);
  const deckFaction = factionForDeck(deckIds);
  const deckHeroPower = getHeroPower(deckFaction);
  const deckSlotsFull = decks.length >= MAX_SAVED_DECKS;
  const missingByCardId = new Map(missingCards.map((item) => [item.cardId, item]));
  const missingTotal = missingCards.reduce((sum, item) => sum + item.missing, 0);
  const deckRecipes = useMemo(
    () => deckRecipesForFaction(recipeFaction),
    [recipeFaction],
  );

  const copyDeckCode = () => {
    const encoded = encodeDeckCode({ format, name, cardIds: deckIds });
    setDeckCode(encoded);
    const clipboard = navigator.clipboard;
    if (!clipboard) return;
    const shareText = formatDeckShareText({ format, name, cardIds: deckIds });
    void clipboard.writeText(shareText)
      .then(() => setCopiedDeckFingerprint(deckFingerprint))
      .catch(() => setCopiedDeckFingerprint(null));
  };

  const importDeckCode = () => {
    if (onImport(deckCode)) setDeckCode("");
  };

  return (
    <section className="screen screen--deck" aria-labelledby="deck-title">
      <SectionHeading
        eyebrow="ARSENAL / DECK FORGE"
        title="卡组工坊"
        description="编排 30 张战术档案；不同单位启动特质，同名双份则用于对局内二星共鸣。"
        action={
          <div className="deck-heading-actions">
            <button className="button button--outline" type="button" disabled={deckIds.length >= 30 || missingCards.length > 0 || Boolean(selectedLadderReadyDeckId)} onClick={onAutoComplete}>
              <Icon name="spark" />
              智能补全
            </button>
            <button className="button button--outline" type="button" disabled={saving || Boolean(selectedLadderReadyDeckId)} onClick={onSave}>
              <Icon name="check" />
              {saving ? "保存中…" : selectedLadderReadyDeckId ? "试玩套牌只读" : "保存卡组"}
            </button>
            <button className="button button--outline button--danger" type="button" disabled={deleting || !editingDeckId || Boolean(selectedLadderReadyDeckId)} onClick={onDelete}>
              <Icon name="trash" />
              {deleting ? "删除中…" : "删除卡组"}
            </button>
            <button className="button button--primary" type="button" disabled={!battleReady} onClick={onBattle} title={playable && !battleReady ? "先保存这份新卡组草稿" : undefined}>
              <Icon name="swords" />
              投入演算
            </button>
          </div>
        }
      />

      <section className="ladder-ready" aria-labelledby="ladder-ready-title">
        <div className="ladder-ready__header">
          <div>
            <span className="panel__eyebrow">LADDER READY / 7-DAY ARMORY</span>
            <h2 id="ladder-ready-title">天梯预备套牌</h2>
            <p>六套完整 30 张卡组可在七天内无限试玩；最终任选一套永久领取，缺少卡牌会自动补齐。</p>
          </div>
          <div className={`ladder-ready__status ${trialClaimed ? "is-claimed" : trialPlayable ? "is-live" : ""}`}>
            <Icon name={trialClaimed ? "check" : "clock"} size={18} />
            <span>
              <small>{trialClaimed ? "领取完成" : trialPlayable ? "试玩剩余" : trialExpired ? "试玩到期" : "尚未启动"}</small>
              <strong>{trialClaimed
                ? getLadderReadyDeck(ladderReady?.claimedDeckId ?? "")?.name ?? "已领取"
                : formatLadderReadyCountdown(ladderReady?.expiresAt, clockNow)}</strong>
            </span>
          </div>
          {!trialActivated && !trialClaimed && (
            <button className="button button--primary" type="button" disabled={ladderReadyBusy} onClick={onActivateLadderReady}>
              <Icon name="spark" />
              {ladderReadyBusy ? "激活中…" : `启动 ${LADDER_READY_TRIAL_DAYS} 日试玩`}
            </button>
          )}
        </div>
        <div className="ladder-ready__rules" aria-label="试玩规则">
          <span><Icon name="check" size={14} /> AI 与在线对战均可使用</span>
          <span><Icon name="clock" size={14} /> 激活后连续计时七天</span>
          <span><Icon name="shield" size={14} /> 每个账号仅能永久领取一套</span>
        </div>
        <div className="ladder-ready__grid">
          {LADDER_READY_DECKS.map((offer) => {
            const definition = FACTION_DEFINITIONS[offer.faction];
            const averageCost = offer.deck.reduce((sum, cardId) => sum + (CARD_BY_ID.get(cardId)?.cost ?? 0), 0) / offer.deck.length;
            const legendaryCount = offer.deck.filter((cardId) => CARD_BY_ID.get(cardId)?.rarity === "legendary").length;
            const isClaimed = ladderReady?.claimedDeckId === offer.id;
            const isSelected = selectedLadderReadyDeckId === offer.id;
            return (
              <article
                className={`ladder-ready-card ${isClaimed ? "is-claimed" : ""} ${isSelected ? "is-selected" : ""}`}
                style={{ "--offer-tone": definition.tone } as CSSProperties}
                key={offer.id}
              >
                <div className="ladder-ready-card__crest"><span>{definition.sigil}</span><small>{offer.faction}</small></div>
                <div className="ladder-ready-card__copy">
                  <span>{offer.style} · {offer.difficulty}</span>
                  <h3>{offer.name}</h3>
                  <p>{offer.description}</p>
                </div>
                <div className="ladder-ready-card__metrics">
                  <span><small>卡牌</small><strong>30</strong></span>
                  <span><small>均费</small><strong>{averageCost.toFixed(1)}</strong></span>
                  <span><small>传说</small><strong>{legendaryCount}</strong></span>
                </div>
                <div className="ladder-ready-card__actions">
                  <button className="button button--outline" type="button" disabled={!trialPlayable || ladderReadyBusy} onClick={() => onTrialLadderReady(offer.id)}>
                    <Icon name="swords" size={15} />{isSelected ? "试玩已载入" : "试玩此套"}
                  </button>
                  <button className="button button--small" type="button" disabled={!trialActivated || trialClaimed || ladderReadyBusy} onClick={() => setClaimConfirmation(offer.id)}>
                    {isClaimed ? "已永久领取" : "永久领取"}
                  </button>
                </div>
              </article>
            );
          })}
        </div>
      </section>

      {claimConfirmation && (() => {
        const offer = getLadderReadyDeck(claimConfirmation);
        if (!offer) return null;
        return (
          <div className="ladder-ready-confirm" role="presentation" onClick={() => setClaimConfirmation(null)}>
            <section role="dialog" aria-modal="true" aria-labelledby="ladder-ready-confirm-title" onClick={(event) => event.stopPropagation()}>
              <span className="ladder-ready-confirm__sigil">{FACTION_DEFINITIONS[offer.faction].sigil}</span>
              <span className="panel__eyebrow">ONE-TIME CLAIM / FINAL CHECK</span>
              <h2 id="ladder-ready-confirm-title">永久领取「{offer.name}」？</h2>
              <p>每个账号只能领取一套。确认后缺少卡牌会补入收藏，此卡组自动保存，其余五套试玩立即关闭。</p>
              <div>
                <button className="button button--ghost" type="button" onClick={() => setClaimConfirmation(null)}>继续试玩</button>
                <button className="button button--primary" type="button" disabled={ladderReadyBusy} onClick={() => { setClaimConfirmation(null); onClaimLadderReady(offer.id); }}>
                  <Icon name="check" />确认永久领取
                </button>
              </div>
            </section>
          </div>
        );
      })()}

      <section className="deck-recipes" aria-labelledby="deck-recipes-title">
        <div className="deck-recipes__header">
          <div>
            <span className="panel__eyebrow">DECK RECIPES / THREE PATHS</span>
            <h2 id="deck-recipes-title">推荐牌组配方</h2>
            <p>每个阵营提供核心、猛禽年与圣甲虫年三套标准配方；可直接套用，再替换收藏中缺少的卡牌。</p>
          </div>
          <label>
            <span>选择阵营</span>
            <select value={recipeFaction} onChange={(event) => setRecipeFaction(event.target.value as Faction)}>
              {FACTION_ORDER.filter((faction) => faction !== "中立").map((faction) => (
                <option value={faction} key={faction}>{FACTION_DEFINITIONS[faction].sigil} {faction} · {FACTION_DEFINITIONS[faction].doctrine}</option>
              ))}
            </select>
          </label>
        </div>
        <div className="deck-recipes__grid">
          {deckRecipes.map((recipe) => {
            const missing = findMissingDeckCards(recipe.cardIds, collection)
              .reduce((total, card) => total + card.missing, 0);
            const averageCost = recipe.cardIds.reduce(
              (total, cardId) => total + (CARD_BY_ID.get(cardId)?.cost ?? 0),
              0,
            ) / recipe.cardIds.length;
            const featured = [...new Set(recipe.cardIds)]
              .map((cardId) => CARD_BY_ID.get(cardId)?.name)
              .filter(Boolean)
              .slice(0, 3)
              .join(" · ");
            return (
              <article className={`deck-recipe deck-recipe--${recipe.kind}`} key={recipe.id}>
                <div className="deck-recipe__set">
                  <span>{FACTION_DEFINITIONS[recipe.faction].sigil}</span>
                  <small>{CARD_SET_DEFINITIONS[recipe.focusSet].label}</small>
                </div>
                <h3>{recipe.name}</h3>
                <p>{recipe.description}</p>
                <div className="deck-recipe__cards">{featured}</div>
                <div className="deck-recipe__metrics">
                  <span><small>卡牌</small><strong>30</strong></span>
                  <span><small>均费</small><strong>{averageCost.toFixed(1)}</strong></span>
                  <span className={missing > 0 ? "is-missing" : "is-owned"}><small>收藏</small><strong>{missing > 0 ? `缺 ${missing}` : "完整"}</strong></span>
                </div>
                <button className="button button--outline" type="button" disabled={deckSlotsFull} onClick={() => onApplyRecipe(recipe)}>
                  <Icon name="layers" size={15} />套用此配方
                </button>
              </article>
            );
          })}
        </div>
      </section>

      <div className="deck-workbench">
        <aside className="panel deck-manifest">
          <label className="deck-format-select">
            <span>卡组环境</span>
            <select value={format} onChange={(event) => onFormat(event.target.value === "wild" ? "wild" : "standard")} disabled={Boolean(selectedLadderReadyDeckId)}>
              <option value="standard">标准 · Core + 2025–2026</option>
              <option value="wild">狂野 · 全部卡牌</option>
            </select>
            <small>{format === "standard" ? "仅使用当前轮换环境的 800 张卡牌。" : "可使用全部 1,000 张卡牌，包括已轮换的 2024 系列。"}</small>
          </label>
          <div className="deck-loadout">
            <label>
              <span>已保存卡组 · {decks.length}/{MAX_SAVED_DECKS}</span>
              <select
                value={editingDeckId ?? ""}
                onChange={(event) => event.target.value ? onSelectDeck(event.target.value) : onNewDeck()}
                aria-label="选择已保存卡组"
              >
                <option value="" disabled={deckSlotsFull}>新建卡组草稿</option>
                {decks.map((deck) => <option value={deck.id} key={deck.id}>{rankedFormatLabel(deck.format ?? "standard")} · {deck.name}</option>)}
              </select>
            </label>
            <button className="button button--outline" type="button" onClick={onNewDeck} disabled={deckSlotsFull} title={deckSlotsFull ? `已使用全部 ${MAX_SAVED_DECKS} 个卡组栏位` : undefined}>
              新建
            </button>
          </div>
          <div className="deck-name-field">
            <span className="deck-name-field__sigil"><Icon name="layers" /></span>
            <label>
              <span>卡组代号</span>
              <input value={name} readOnly={Boolean(selectedLadderReadyDeckId)} onChange={(event) => onName(event.target.value)} maxLength={32} />
            </label>
            <strong className={deckIds.length === 30 ? "is-complete" : ""}>{deckIds.length}<small>/30</small></strong>
          </div>
          <div className="deck-code-tools" aria-label="卡组代码">
            <label><span>卡组代码或完整牌表</span><textarea rows={3} value={deckCode} onChange={(event) => setDeckCode(event.target.value)} placeholder="粘贴完整牌表、ASTRA2 或旧版 ASTRA1 卡组代码" /></label>
            <div><button className="button button--small button--outline" type="button" onClick={importDeckCode} disabled={!deckCode.trim() || deckSlotsFull}>导入为新卡组</button><button className="button button--small button--outline" type="button" onClick={copyDeckCode} disabled={!validation.valid}>{copiedDeckFingerprint === deckFingerprint ? "已复制牌表" : "复制牌表"}</button></div>
            <small>复制内容包含可读牌表与 ASTRA2 代码；整段或仅代码均可导入，缺卡时会提供合法替换建议。</small>
          </div>

          {missingCards.length > 0 && (
            <section className="deck-missing" aria-labelledby="deck-missing-title">
              <div className="deck-missing__heading">
                <div>
                  <span className="panel__eyebrow">MISSING / REPLACEMENTS</span>
                  <strong id="deck-missing-title">缺少 {missingTotal} 张卡牌</strong>
                </div>
                <span>选择建议即可替换一张</span>
              </div>
              {missingCards.map((issue) => {
                const card = CARD_BY_ID.get(issue.cardId);
                const suggestions = suggestDeckReplacements({
                  cardIds: deckIds,
                  missingCardId: issue.cardId,
                  collection,
                  format,
                });
                return (
                  <article className="deck-missing__item" key={issue.cardId}>
                    <div>
                      <strong>{card?.name ?? issue.cardId}</strong>
                      <small>需要 {issue.required} · 已拥有 {issue.owned}</small>
                    </div>
                    <div className="deck-missing__suggestions">
                      {suggestions.length > 0 ? suggestions.map((cardId) => {
                        const suggestion = CARD_BY_ID.get(cardId);
                        return suggestion ? (
                          <button type="button" key={cardId} onClick={() => onReplaceMissing(issue.cardId, cardId)}>
                            <span>{suggestion.cost}</span>{suggestion.name}
                          </button>
                        ) : null;
                      }) : <small>收藏中暂无合法替换；可先制作这张卡。</small>}
                    </div>
                  </article>
                );
              })}
            </section>
          )}

          <div className={`deck-validation ${playable ? "deck-validation--valid" : "deck-validation--invalid"}`} role="status">
            <Icon name={playable ? "check" : "shield"} />
            <div>
              <strong>{playable ? "卡组协议有效" : missingCards.length > 0 ? `仍缺少 ${missingTotal} 张卡牌` : "卡组尚未完成"}</strong>
              <span>{playable ? battleReady ? "可投入 AI 与在线对战" : "规则与收藏校验通过；保存草稿后即可对战。" : missingCards.length > 0 ? "使用建议替换，或前往收藏制作缺少的卡牌。" : validation.errors[0]}</span>
            </div>
          </div>

          <div className="deck-profile" aria-label="卡组结构概览">
            <span><small>单位</small><strong>{unitCount}</strong></span>
            <span><small>战术</small><strong>{spellCount}</strong></span>
            <span><small>武器</small><strong>{weaponCount}</strong></span>
            <span><small>英雄</small><strong>{heroCount}</strong></span>
          </div>

          <div className="deck-hero-preview" aria-label={`阵营英雄技能：${deckHeroPower.name}`}>
            <span className="deck-hero-preview__sigil">✦</span>
            <span className="deck-hero-preview__copy">
              <small>{deckFaction} · 英雄技能</small>
              <strong>{deckHeroPower.name}<i>{deckHeroPower.cost} 能量</i></strong>
              <span>{deckHeroPower.description}</span>
            </span>
          </div>

          <div className="mana-curve" aria-label="能量曲线">
            <div className="mana-curve__heading">
              <span>能量曲线</span>
              <small>平均 {(deckIds.reduce((sum, id) => sum + (CARD_BY_ID.get(id)?.cost ?? 0), 0) / Math.max(1, deckIds.length)).toFixed(1)}</small>
            </div>
            <div className="mana-curve__bars">
              {manaCurve.map((item) => (
                <div className="mana-bar" key={item.cost}>
                  <span className="mana-bar__value">{item.count}</span>
                  <span
                    className="mana-bar__track"
                    style={{ "--bar-size": `${Math.max(6, (item.count / maxCurve) * 100)}%` } as CSSProperties}
                  >
                    <i />
                  </span>
                  <small>{item.cost}</small>
                </div>
              ))}
            </div>
          </div>

          <div className="deck-synergy" aria-label="特质羁绊规划">
            <div className="deck-synergy__heading">
              <span>特质羁绊</span>
              <small>不同单位计数 · 2 / 4 档</small>
            </div>
            <div className="trait-planner">
              {traitStatuses.map((status) => {
                const target = status.nextThreshold ?? status.thresholds[1];
                const description =
                  status.tier > 0
                    ? status.descriptions[status.tier - 1]
                    : `再部署 ${Math.max(0, status.thresholds[0] - status.count)} 个不同单位可启动`;
                return (
                  <div
                    className={`trait-row trait-row--tier-${status.tier}`}
                    title={description}
                    key={status.id}
                  >
                    <span className="trait-row__sigil">{status.sigil}</span>
                    <span className="trait-row__copy">
                      <strong>{status.label}<i>{status.tier > 0 ? ` ${status.tier === 1 ? "Ⅰ" : "Ⅱ"}` : ""}</i></strong>
                      <small>{description}</small>
                      <span className="trait-progress">
                        <i style={{ width: `${Math.min(100, (status.count / target) * 100)}%` }} />
                      </span>
                    </span>
                    <b>{status.count}<i> / {target}</i></b>
                  </div>
                );
              })}
            </div>
            {keywordProfile.length > 0 && (
              <div className="deck-keywords">
                <small>关键词分布</small>
                <div>
                  {keywordProfile.map(({ keyword, count }) => (
                    <span title={KEYWORD_DEFINITIONS[keyword].description} key={keyword}>
                      {KEYWORD_DEFINITIONS[keyword].label} ×{count}
                    </span>
                  ))}
                </div>
              </div>
            )}
            {minionTypeProfile.length > 0 && (
              <div className="deck-keywords">
                <small>随从类型分布</small>
                <div>
                  {minionTypeProfile.map(({ minionType, count }) => (
                    <span title={MINION_TYPE_DEFINITIONS[minionType].description} key={minionType}>
                      {MINION_TYPE_DEFINITIONS[minionType].sigil} {MINION_TYPE_DEFINITIONS[minionType].label} ×{count}
                    </span>
                  ))}
                </div>
              </div>
            )}
            {spellSchoolProfile.length > 0 && (
              <div className="deck-keywords">
                <small>法术派系分布 · {spellSchoolProfile.length} 种</small>
                <div>
                  {spellSchoolProfile.map(({ school, count }) => (
                    <span className="deck-school-chip" key={school}>
                      {SPELL_SCHOOL_LABEL[school]} ×{count}
                    </span>
                  ))}
                </div>
              </div>
            )}
          </div>

          <div className="deck-list">
            <div className="deck-list__heading">
              <span>部署清单</span>
              <small>{uniqueDeckCards.length} 种卡牌</small>
            </div>
            {uniqueDeckCards.length > 0 ? uniqueDeckCards.map(({ card, count }) => {
              const missing = missingByCardId.get(card.id);
              return (
              <div className={`deck-entry ${missing ? "deck-entry--missing" : ""}`} key={card.id}>
                <span className="deck-entry__artwork">
                  <CardArtwork card={card} />
                </span>
                <span className="deck-entry__cost">{card.cost}</span>
                <span className={`deck-entry__rarity deck-entry__rarity--${card.rarity}`} />
                <span className="deck-entry__name"><strong>{card.name}</strong><small>{missing ? `缺少 ${missing.missing} 张` : `${card.faction} · ${TYPE_LABEL[card.type]}${card.minionTypes.length > 0 ? ` · ${card.minionTypes.map((type) => MINION_TYPE_DEFINITIONS[type].label).join("/")}` : card.school ? ` · ${SPELL_SCHOOL_LABEL[card.school]}` : ""}`}</small></span>
                <span className="deck-entry__count">{missing ? `缺${missing.missing}` : `×${count}`}</span>
                <button type="button" onClick={() => onRemove(card.id)} aria-label={`从卡组移除一张${card.name}`}>
                  <Icon name="minus" size={16} />
                </button>
              </div>
            );}) : (
              <EmptyState icon="layers" title="部署清单为空">从右侧档案库选择卡牌。</EmptyState>
            )}
          </div>
        </aside>

        <div className="deck-library">
          <div className="deck-library__header">
            <div>
              <span className="panel__eyebrow">AVAILABLE ARCHIVE</span>
              <h2>可用档案</h2>
            </div>
            <span>点击添加 · 已拥有优先</span>
          </div>
          <div className="deck-card-grid">
            {cards.map((card) => {
              const count = deckCounts.get(card.id) ?? 0;
              const owned = collection[card.id] ?? 0;
              const limit = card.rarity === "legendary" ? 1 : 2;
              const disabled = owned <= count || count >= limit || deckIds.length >= 30;
              return (
                <div className={`deck-card-shell ${disabled ? "deck-card-shell--disabled" : ""}`} key={card.id}>
                  <CardTile
                    card={card}
                    owned={owned}
                    countInDeck={count}
                    compact
                    action={() => onAdd(card)}
                    actionLabel={`将${card.name}加入卡组`}
                  />
                  <button className="deck-card-shell__add" type="button" disabled={disabled} onClick={() => onAdd(card)} aria-label={`添加${card.name}`}>
                    <Icon name="plus" size={16} />
                  </button>
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </section>
  );
}

function SecretTray({
  secrets,
  enemy = false,
}: {
  secrets: BattleSide["secrets"];
  enemy?: boolean;
}) {
  if (secrets.length === 0) return null;
  return (
    <div className={`secret-tray ${enemy ? "secret-tray--enemy" : ""}`} aria-label={enemy ? `敌方有 ${secrets.length} 个奥秘` : `我方有 ${secrets.length} 个奥秘`}>
      <span className="secret-tray__label">✦ {enemy ? "敌方奥秘" : "我方奥秘"}</span>
      <div className="secret-tray__cards">
        {secrets.map((secret) => (
          <span className="secret-chip" key={secret.secretId} title={enemy ? "敌方奥秘，触发前不可见" : secret.description}>
            <strong>{enemy ? "?" : "✦"}</strong>
            <small>{enemy ? "未解密" : secret.name}</small>
          </span>
        ))}
      </div>
    </div>
  );
}

function DeathHistoryTray({
  history,
  enemy = false,
}: {
  history: BattleSide["deathHistory"];
  enemy?: boolean;
}) {
  if (history.length === 0) return null;
  const recent = [...history].reverse().slice(0, 3);
  return (
    <div className={`death-history ${enemy ? "death-history--enemy" : ""}`} aria-label={`${enemy ? "敌方" : "我方"}死亡历史 ${history.length} 个单位`}>
      <span className="death-history__label">☠ {enemy ? "敌方" : "我方"}墓地 · {history.length}</span>
      <div>
        {recent.map((record) => (
          <span title={`第 ${record.diedTurn} 回合死亡`} key={`${record.entityId}-${record.deathOrder}`}>
            {record.name}
          </span>
        ))}
        {history.length > recent.length && <small>+{history.length - recent.length}</small>}
      </div>
    </div>
  );
}

function DiscardHistoryTray({
  history,
  enemy = false,
}: {
  history: BattleSide["discardHistory"];
  enemy?: boolean;
}) {
  if (history.length === 0) return null;
  const recent = [...history].reverse().slice(0, 2);
  return (
    <div className={`discard-history ${enemy ? "discard-history--enemy" : ""}`} aria-label={`${enemy ? "敌方" : "我方"}弃牌历史 ${history.length} 张牌`}>
      <span className="discard-history__label">⌫ 弃牌 · {history.length}</span>
      <div>
        {recent.map((record) => (
          <span title={`第 ${record.discardedTurn} 回合弃掉`} key={`${record.discardId}-${record.discardOrder}`}>
            {record.name}{record.fragment ? `·${record.fragment === "left" ? "左片" : "右片"}` : ""}
          </span>
        ))}
        {history.length > recent.length && <small>+{history.length - recent.length}</small>}
      </div>
    </div>
  );
}

function ZoneHistoryTray({ side, enemy = false }: { side: BattleSide; enemy?: boolean }) {
  if (side.deathHistory.length === 0 && side.discardHistory.length === 0) return null;
  return (
    <div className={`zone-history ${enemy ? "zone-history--enemy" : ""}`}>
      <DeathHistoryTray history={side.deathHistory} enemy={enemy} />
      <DiscardHistoryTray history={side.discardHistory} enemy={enemy} />
    </div>
  );
}

function HeroCore({
  side,
  active,
  enemy,
  enemyLabel,
  canTarget,
  onTarget,
  targetLabel,
  effect,
  impact,
  targetPreview,
}: {
  side: BattleSide;
  active: boolean;
  enemy?: boolean;
  enemyLabel?: string;
  canTarget?: boolean;
  onTarget?: () => void;
  targetLabel?: string;
  effect?: BattleHeroEffect;
  impact?: BattleVisualEffect;
  targetPreview?: string;
}) {
  const effectClass = effect ? `hero-core--${effect}` : "";
  const impactText = battleImpactText(impact);
  const currentSchools = [...new Set(side.spellSchoolsPlayedThisTurn)];
  const lastTurnSchools = [...new Set(side.spellSchoolsPlayedLastTurn)];
  const core = (
    <>
      <span className="hero-core__portrait"><Icon name={enemy ? "bot" : "user"} size={30} /></span>
      <span className="hero-core__mobile-health" aria-label={`${enemy ? "敌方" : "我方"}核心生命 ${side.health}/${side.maxHealth}`}>
        <strong>{side.health}</strong>
        {side.armor > 0 && <small>护甲 {side.armor}</small>}
      </span>
      <span className="hero-core__copy">
        <small>{side.heroName !== "远征指挥官" ? side.heroName : enemy ? enemyLabel ?? "镜像演算体 K-7" : "远征指挥官"}</small>
        <strong>{side.health}<i> / {side.maxHealth}</i></strong>
        <span
          className="hero-core__health-bar"
          role="progressbar"
          aria-label={`${enemy ? "敌方" : "我方"}核心生命 ${side.health}/${side.maxHealth}`}
          aria-valuemin={0}
          aria-valuemax={side.maxHealth}
          aria-valuenow={Math.max(0, side.health)}
        >
          <i style={{ width: `${Math.min(100, Math.max(0, (side.health / Math.max(1, side.maxHealth)) * 100))}%` }} />
        </span>
        {side.armor > 0 && <em>护甲 {side.armor}</em>}
        {side.heraldCount > 0 && (
          <em className="hero-core__herald">
            先驱 {side.heraldCount} · 巨型 ×{Math.min(4, 2 ** Math.floor(side.heraldCount / 2))}
          </em>
        )}
        {(currentSchools.length > 0 || lastTurnSchools.length > 0) && (
          <em className="hero-core__schools" title="完成施放的法术派系历史">
            {currentSchools.length > 0 && `本回合 ${currentSchools.map((school) => SPELL_SCHOOL_LABEL[school]).join("/")}`}
            {currentSchools.length > 0 && lastTurnSchools.length > 0 && " · "}
            {lastTurnSchools.length > 0 && `上回合 ${lastTurnSchools.map((school) => SPELL_SCHOOL_LABEL[school]).join("/")}`}
          </em>
        )}
        {side.weapon && (
          <span className="hero-core__weapon" aria-label={`装备 ${side.weapon.name}，攻击 ${side.weapon.attack}，耐久 ${side.weapon.durability}/${side.weapon.maxDurability}`}>
            ⚔ {side.weapon.name} · {side.weapon.attack}/{side.weapon.durability}
          </span>
        )}
        {side.heroAttackBonus > 0 && (
          <span className="hero-core__weapon" aria-label={`英雄本回合额外获得 ${side.heroAttackBonus} 点攻击`}>
            ⚔ 临时攻击 +{side.heroAttackBonus}
          </span>
        )}
      </span>
      <span className="hero-core__health"><Icon name="shield" size={17} /> CORE</span>
      {active && <span className="hero-core__active">行动中</span>}
      {canTarget && <span className="hero-core__target-hint">选择目标</span>}
      {targetPreview && <span className="hero-core__target-preview">{targetPreview}</span>}
      {impactText && (
        <span className={`hero-core__impact hero-core__impact--${impact?.kind}`} aria-hidden="true">
          {impactText}
        </span>
      )}
    </>
  );
  if (canTarget && onTarget) {
    return (
      <button
        className={`hero-core ${enemy ? "hero-core--enemy" : ""} hero-core--targetable ${active ? "hero-core--active" : ""} ${effectClass}`}
        type="button"
        onClick={onTarget}
        aria-label={targetLabel ?? `选择${enemy ? "敌方" : "我方"}核心，剩余 ${side.health} 点生命`}
      >
        {core}
      </button>
    );
  }
  return <div className={`hero-core ${enemy ? "hero-core--enemy" : ""} ${active ? "hero-core--active" : ""} ${effectClass}`}>{core}</div>;
}

function BoardUnit({
  unit,
  selected,
  targetable,
  onSelect,
  onTarget,
  onInspect,
  effect,
  impact,
  targetPreview,
}: {
  unit: BattleUnit;
  selected?: boolean;
  targetable?: boolean;
  onSelect?: () => void;
  onTarget?: () => void;
  onInspect?: () => void;
  effect?: BattleUnitEffect;
  impact?: BattleVisualEffect;
  targetPreview?: string;
}) {
  const card = CARD_BY_ID.get(unit.cardId);
  const visualCard: CatalogCard =
    card ?? {
      id: unit.cardId,
      name: unit.name,
      cost: 0,
      type: "unit",
      faction: "中立",
      rarity: "common",
      description: "",
      attack: unit.attack,
      health: unit.maxHealth,
      target: "none",
      keywords: unit.keywords,
      traits: [],
      minionTypes: unit.minionTypes,
      stealthActive: false,
    };
  const impactText = battleImpactText(impact);
  const statusText = unit.frozenTurns > 0
    ? `❄ 冻结 ${unit.frozenTurns} 回合`
    : unit.summoningSick
      ? unit.rushOnly
        ? "↗ 突袭窗口"
        : "◌ 休眠"
      : unit.rushOnly
        ? "↗ 突袭：仅可攻击单位"
        : unit.keywords.includes("windfury") && unit.attacksMade > 0
          ? `⚔ 风怒 ${unit.attacksMade}/2`
          : unit.furyStacks > 0
            ? `↯ 激昂 ${unit.furyStacks}/2`
            : undefined;
  return (
    <div className="board-unit-shell">
      <button
        className={`board-unit ${unit.stars === 2 ? "board-unit--star-2" : ""} ${selected ? "board-unit--selected" : ""} ${targetable ? "board-unit--targetable" : ""} ${!unit.canAttack && onSelect ? "board-unit--exhausted" : ""} ${unit.frozenTurns > 0 ? "board-unit--frozen" : ""} ${unit.summoningSick ? "board-unit--summoning-sick" : ""} ${effect ? `board-unit--${effect}` : ""}`}
        type="button"
        onClick={targetable ? onTarget : onSelect}
        disabled={!targetable && (!onSelect || !unit.canAttack)}
        aria-pressed={onSelect ? selected : undefined}
        aria-label={`${unit.name}${unit.minionTypes.length > 0 ? `，${unit.minionTypes.map((type) => MINION_TYPE_DEFINITIONS[type].label).join("、")}` : ""}，${unit.stars} 星，攻击 ${unit.attack}，生命 ${unit.health}${targetable ? "，设为攻击目标" : unit.canAttack ? "，选择攻击" : "，本回合无法攻击"}${statusText ? `，${statusText.replaceAll("❄ ", "").replaceAll("↗ ", "").replaceAll("◌ ", "").replaceAll("↯ ", "")}` : ""}`}
        title={visualCard.description || `${unit.name} · ${unit.attack}/${unit.health}`}
      >
      <div className="board-unit__art">
        <Sigil card={visualCard} />
        <CardArtwork card={visualCard} className="board-unit__artwork" />
        {unit.stars === 2 && <span className="board-unit__stars">★★</span>}
      </div>
      {targetable && <span className="board-unit__target-hint">选择目标</span>}
      {targetPreview && <span className="board-unit__target-preview">{targetPreview}</span>}
      <strong>{unit.name}</strong>
      {(unit.minionTypes.length > 0 || unit.keywords.length > 0) && (
        <div className="board-unit__keywords">
          {unit.minionTypes.slice(0, 2).map((minionType) => (
            <span className="board-unit__minion-type" key={minionType}>
              {MINION_TYPE_DEFINITIONS[minionType].sigil} {MINION_TYPE_DEFINITIONS[minionType].label}
            </span>
          ))}
          {unit.keywords.slice(0, Math.max(0, 3 - unit.minionTypes.length)).map((keyword) => (
            <span key={keyword}>{KEYWORD_DEFINITIONS[keyword]?.label ?? keyword}</span>
          ))}
        </div>
      )}
      {statusText && <span className="board-unit__status">{statusText}</span>}
      <div className="board-unit__stats"><span>⚔ {unit.attack}</span><span>◆ {unit.health}</span></div>
      {unit.spellDamage > 0 && <span className="board-unit__spell-damage" title="法术伤害加成">✦ 法术 +{unit.spellDamage}</span>}
      {(unit.temporaryAttackBonus !== 0 || unit.temporaryHealthBonus !== 0) && (
        <span className="board-unit__temporary" title="回合结束时移除">
          ◇ 临时 {unit.temporaryAttackBonus >= 0 ? "+" : ""}{unit.temporaryAttackBonus}/
          {unit.temporaryHealthBonus >= 0 ? "+" : ""}{unit.temporaryHealthBonus}
        </span>
      )}
      {impactText && (
        <span className={`board-unit__impact board-unit__impact--${impact?.kind}`} aria-hidden="true">
          {impactText}
        </span>
      )}
      {unit.canAttack && onSelect && <span className="board-unit__ready">READY</span>}
      </button>
      {onInspect && (
        <button
          className="board-unit__inspect"
          type="button"
          onClick={(event) => {
            event.stopPropagation();
            onInspect();
          }}
          aria-label={`查看${unit.name}卡牌详情`}
          title={`查看${unit.name}卡牌详情`}
        >
          i
        </button>
      )}
    </div>
  );
}

function BattleEffectLayer({ effect }: { effect: BattleVisualEffect }) {
  const revealCard = effect.cardId ? CARD_BY_ID.get(effect.cardId) : undefined;
  const cardName = revealCard?.name;
  const eventType =
    effect.kind === "turn" && effect.label.includes("超时")
      ? "turn-timed-out"
      : undefined;
  const number =
    typeof effect.amount === "number" &&
    (effect.kind === "damage" || effect.kind === "heal")
      ? `${effect.kind === "damage" ? "−" : "+"}${effect.amount}`
      : null;

  return (
    <div
      className={`battlefield__fx-layer battle-fx--${effect.kind} battle-fx--${effect.targetSide ?? effect.side ?? "neutral"}`}
      data-event-type={eventType}
      aria-hidden="true"
    >
      <span className="battle-fx__vignette" />
      <span className="battle-fx__scan" />
      <span className="battle-fx__ring" />
      <span className="battle-fx__slash" />
      <span className="battle-fx__impact" />
      <span className="battle-fx__particles">
        {Array.from({ length: 8 }, (_, index) => <i key={index} />)}
      </span>
      <span className="battle-fx__banner">
        {revealCard && (
          <span className="battle-fx__card-reveal" aria-hidden="true">
            <CardArtwork card={revealCard} className="battle-fx__card-art" eager />
            <b>{revealCard.cost}</b>
          </span>
        )}
        <span className="battle-fx__copy">
          <small>{cardName ?? "EMBER COMBAT LINK"}</small>
          <strong>{effect.label}</strong>
        </span>
      </span>
      {number && <span className="battle-fx__number">{number}</span>}
    </div>
  );
}

function BattleTraitProtocol({
  label,
  board,
  enemy = false,
}: {
  label: string;
  board: BattleUnit[];
  enemy?: boolean;
}) {
  const cards = board
    .map((unit) => CARD_BY_ID.get(unit.cardId))
    .filter((card): card is CatalogCard => Boolean(card));
  const statuses = getTraitStatuses(cards);
  const active = statuses
    .filter((status) => status.tier > 0)
    .sort((left, right) => right.tier - left.tier || right.count - left.count);
  const visible = active.length > 0
    ? active.slice(0, 4)
    : statuses
        .filter((status) => status.count > 0)
        .sort((left, right) => right.count - left.count)
        .slice(0, 1);

  return (
    <div className={`battle-protocol ${enemy ? "battle-protocol--enemy" : ""}`}>
      <div className="battle-protocol__heading">
        <span>{label}</span>
        <small>{active.length > 0 ? `${active.length} 项启动` : "尚未启动"}</small>
      </div>
      <div className="battle-protocol__traits">
        {visible.length > 0 ? visible.map((status) => {
          const target = status.nextThreshold ?? status.thresholds[1];
          const description = status.tier > 0
            ? status.descriptions[status.tier - 1]
            : `还差 ${Math.max(0, status.thresholds[0] - status.count)} 个不同单位`;
          return (
            <span
              className={`battle-trait battle-trait--tier-${status.tier}`}
              title={description}
              key={status.id}
            >
              <i>{status.sigil}</i>
              <strong>{status.label}</strong>
              <small>{status.count}/{target}</small>
            </span>
          );
        }) : <span className="battle-protocol__empty">部署单位以接通特质协议</span>}
      </div>
    </div>
  );
}

function PvpLobby({
  state,
  apprenticePool,
  url,
  roomInput,
  onUrl,
  onRoomInput,
  onConnect,
  onCreate,
  onQueue,
  onLeaveQueue,
  onFallbackAi,
  onJoin,
  onReady,
  onDisconnect,
}: {
  state: PvpState;
  apprenticePool: boolean;
  url: string;
  roomInput: string;
  onUrl: (value: string) => void;
  onRoomInput: (value: string) => void;
  onConnect: () => void;
  onCreate: (format: PvpFormat, rankedFormat: RankedFormat) => void;
  onQueue: (format: PvpFormat, rankedFormat: RankedFormat) => void;
  onLeaveQueue: () => void;
  onFallbackAi: () => void;
  onJoin: () => void;
  onReady: () => void;
  onDisconnect: () => void;
}) {
  const connected = state.status !== "offline" && state.status !== "error" && state.status !== "connecting";
  const [selectedFormat, setSelectedFormat] = useState<PvpFormat>(state.format);
  const [selectedRankedFormat, setSelectedRankedFormat] = useState<RankedFormat>(state.rankedFormat);
  const protectedPool = state.matchPool ? state.matchPool === "apprentice" : apprenticePool;
  const matchQualityLabel = state.matchQuality === "ideal"
    ? "精确"
    : state.matchQuality === "close"
      ? "接近"
      : state.matchQuality === "expanded"
        ? "扩展"
        : null;
  return (
    <section className="pvp-lobby" aria-label="基础 PVP 联机大厅">
      <div className="pvp-lobby__heading">
        <div>
          <span className="panel__eyebrow">LIVE PVP / ROOM LINK</span>
          <h3>基础联机对战</h3>
          <span className={`pvp-lobby__pool ${protectedPool ? "is-protected" : "is-standard"}`}>
            <Icon name={protectedPool ? "shield" : "radar"} size={13} />
            {protectedPool ? "新兵专属匹配池" : "常规水平匹配池"}
          </span>
          <span className="pvp-lobby__mmr"><Icon name="radar" size={13} />隐藏水平匹配 · 数值不公开</span>
        </div>
        <span className={`pvp-lobby__status pvp-lobby__status--${state.status}`}><i />{state.status === "offline" ? "未连接" : state.status === "connecting" ? "连接中" : state.status === "error" ? "连接异常" : state.status === "queue" ? "匹配中" : state.status === "playing" ? "对战中" : "大厅在线"}</span>
      </div>
      <p>{state.message} 两端使用同一套战斗规则同步出牌、攻击和回合，首手由服务器随机决定。</p>
      {(state.status === "offline" || state.status === "error" || state.status === "connecting") && (
        <div className="pvp-lobby__connect">
          <label><span>房间服务器</span><input value={url} onChange={(event) => onUrl(event.target.value)} placeholder="wss://当前站点/api/pvp" /></label>
          <button className="button button--outline" type="button" disabled={state.status === "connecting"} onClick={onConnect}>{state.status === "connecting" ? "连接中…" : "连接大厅"}</button>
        </div>
      )}
      {connected && (
        <div className="pvp-lobby__room">
      {state.status === "queue" ? (
            <div className={`pvp-lobby__queue ${protectedPool ? "is-protected" : ""}`}>
              <div>
                <span className="panel__eyebrow">SERVER MATCHMAKING · {protectedPool ? "CADET" : "STANDARD"}</span>
                <strong>{protectedPool ? "新兵保护匹配" : `${rankedFormatLabel(state.rankedFormat)} · ${state.format === "casual" ? "休闲匹配" : "天梯匹配"}`}</strong>
                <small>{protectedPool ? "只配对同轨道新玩家，并按隐藏水平从严到宽寻找对手。" : "标准与狂野天梯各有独立隐藏水平；休闲模式跨环境共用隐藏水平。"}</small>
              </div>
              <div className="pvp-lobby__queue-actions">
                {protectedPool && <button className="button button--primary" type="button" onClick={onFallbackAi}>改打 AI 演算</button>}
                <button className="button button--outline" type="button" onClick={onLeaveQueue}>取消匹配</button>
              </div>
            </div>
          ) : !state.roomCode ? (
            <>
              <label><span>匹配模式</span><select value={selectedFormat} onChange={(event) => setSelectedFormat(event.target.value === "casual" ? "casual" : "ranked")} aria-label="选择联机模式"><option value="ranked">Ranked 天梯</option><option value="casual">Casual 休闲</option></select></label>
              <label><span>卡牌环境</span><select value={selectedRankedFormat} onChange={(event) => setSelectedRankedFormat(event.target.value === "wild" ? "wild" : "standard")} aria-label="选择卡牌环境"><option value="standard">Standard 标准</option><option value="wild">Wild 狂野</option></select></label>
              <button className="button button--primary" type="button" onClick={() => onQueue(selectedFormat, selectedRankedFormat)}>快速匹配</button>
              <span className="pvp-lobby__match-rule"><Icon name="radar" size={14} /><span><strong>公平匹配</strong><small>显示段位不参与选人；标准/狂野天梯隐藏分独立，休闲共用。</small></span></span>
              <button className="button button--primary" type="button" onClick={() => onCreate(selectedFormat, selectedRankedFormat)}>创建{rankedFormatLabel(selectedRankedFormat)}{selectedFormat === "casual" ? "休闲" : "天梯"}房间</button>
              <label><span>房间码</span><input value={roomInput} maxLength={4} onChange={(event) => onRoomInput(event.target.value.toUpperCase())} placeholder="A7KQ" /></label>
              <button className="button button--outline" type="button" onClick={onJoin}>加入房间</button>
            </>
          ) : (
            <>
              <div className="pvp-lobby__code"><small>{rankedFormatLabel(state.rankedFormat)} · {state.format === "casual" ? "休闲 Casual" : "天梯 Ranked"} · 房间码{matchQualityLabel ? ` · 匹配质量 ${matchQualityLabel}` : ""}</small><strong>{state.roomCode}</strong><span>{state.peerName ? `对手：${state.peerName}` : "等待对手加入"}</span></div>
              <button className="button button--primary" type="button" disabled={state.localReady || !state.peerName} onClick={onReady}>{state.localReady ? "已准备" : "准备对战"}</button>
              <button className="button button--outline" type="button" onClick={onDisconnect}>离开房间</button>
            </>
          )}
        </div>
      )}
    </section>
  );
}

function BattleSection({
  battle,
  message,
  effect,
  inspectedCard,
  onInspectCard,
  onCloseInspector,
  selectedAttacker,
  pendingCard,
  pendingHeroPower,
  mulliganSelection,
  busy,
  effectsLocked,
  effectCount,
  turnClockSeconds,
  soundEnabled,
  replaySlow,
  onStart,
  onRematch,
  onReturnLobby,
  onPlayCard,
  onTradeCard,
  onPrepareCard,
  onChooseDiscover,
  onChooseOne,
  onToggleMulligan,
  onConfirmMulligan,
  onSelectAttacker,
  onSelectHeroAttacker,
  onCardTarget,
  onCancelTarget,
  onAttack,
  onHeroPower,
  onEndTurn,
  onSkipEffects,
  onConcede,
  onOpenDeck,
  onToggleSound,
  onToggleReplaySpeed,
  trainingActive,
  onExitTraining,
  pvp,
  apprenticePool,
  aiArchetypes,
  aiArchetypeId,
  onAiArchetype,
  pvpUrl,
  pvpRoomInput,
  onPvpUrl,
  onPvpRoomInput,
  onPvpConnect,
  onPvpCreate,
  onPvpQueue,
  onPvpLeaveQueue,
  onPvpFallbackAi,
  onPvpJoin,
  onPvpReady,
  onPvpDisconnect,
  online,
  opponentName,
}: {
  battle: BattleView | null;
  message: string;
  effect: BattleVisualEffect | null;
  inspectedCard: CatalogCard | null;
  onInspectCard: (card: CatalogCard) => void;
  onCloseInspector: () => void;
  selectedAttacker: string | null;
  pendingCard: BattleSide["hand"][number] | null;
  pendingHeroPower: boolean;
  mulliganSelection: number[];
  busy: boolean;
  effectsLocked: boolean;
  effectCount: number;
  turnClockSeconds: number | null;
  soundEnabled: boolean;
  replaySlow: boolean;
  onStart: () => void;
  onRematch: () => void;
  onReturnLobby: () => void;
  onPlayCard: (
    card: BattleSide["hand"][number],
    placement?: "friendly" | "enemy",
  ) => void;
  onTradeCard: (card: BattleSide["hand"][number]) => void;
  onPrepareCard: (card: BattleSide["hand"][number]) => void;
  onChooseDiscover: (cardId: string, choiceIndex: number) => void;
  onChooseOne: (optionIndex: number) => void;
  onToggleMulligan: (index: number) => void;
  onConfirmMulligan: () => void;
  onSelectAttacker: (id: string) => void;
  onSelectHeroAttacker: () => void;
  onCardTarget: (target: { kind: "unit" | "hero"; side: "player" | "ai"; id?: string }) => void;
  onCancelTarget: () => void;
  onAttack: (target: BattleTarget) => void;
  onHeroPower: () => void;
  onEndTurn: () => void;
  onSkipEffects: () => void;
  onConcede: () => void;
  onOpenDeck: () => void;
  onToggleSound: () => void;
  onToggleReplaySpeed: () => void;
  trainingActive: boolean;
  onExitTraining: () => void;
  pvp: PvpState;
  apprenticePool: boolean;
  aiArchetypes: readonly AiArchetype[];
  aiArchetypeId: string;
  onAiArchetype: (id: string) => void;
  pvpUrl: string;
  pvpRoomInput: string;
  onPvpUrl: (value: string) => void;
  onPvpRoomInput: (value: string) => void;
  onPvpConnect: () => void;
  onPvpCreate: (format: PvpFormat, rankedFormat: RankedFormat) => void;
  onPvpQueue: (format: PvpFormat, rankedFormat: RankedFormat) => void;
  onPvpLeaveQueue: () => void;
  onPvpFallbackAi: () => void;
  onPvpJoin: () => void;
  onPvpReady: () => void;
  onPvpDisconnect: () => void;
  online: boolean;
  opponentName: string | null;
}) {
  if (!battle) {
    return (
      <section className="screen screen--battle battle-lobby" aria-labelledby="battle-title">
        <SectionHeading
          eyebrow="SIMULATION CHAMBER / AI"
          title="战术对战"
          description="以当前卡组接入镜像演算体。战斗由确定性规则内核驱动，对局结束后自动归档。"
        />
        <div className="battle-lobby__stage">
          <div className="battle-lobby__grid" aria-hidden="true" />
          <div className="battle-lobby__opponent">
            <span className="battle-lobby__halo" />
            <span className="battle-lobby__bot"><Icon name="bot" size={52} /></span>
            <span className="eyebrow-tag"><i /> AI 节点就绪</span>
            <h2>镜像演算体 K-7</h2>
            <p>自适应基础策略 · 推荐战力 1,200</p>
          </div>
          <div className="battle-lobby__brief">
            <div><span>对战模式</span><strong>标准 1V1</strong></div>
            <div><span>胜利条件</span><strong>摧毁敌方核心</strong></div>
            <div><span>规则版本</span><strong>CORE 0.2 · 特质升阶</strong></div>
          </div>
          <div className="ai-archetype-picker">
            <div className="ai-archetype-picker__copy">
              <span>选择演算对手</span>
              <strong>{aiArchetypes.find((archetype) => archetype.id === aiArchetypeId)?.name ?? "镜像演算体 K-7"}</strong>
              <small>{aiArchetypes.find((archetype) => archetype.id === aiArchetypeId)?.description ?? "自适应基础策略。"}</small>
            </div>
            <label>
              <span>AI 卡组</span>
              <select value={aiArchetypeId} onChange={(event) => onAiArchetype(event.target.value)} aria-label="选择演算对手">
                {aiArchetypes.map((archetype) => <option value={archetype.id} key={archetype.id}>{archetype.name}</option>)}
              </select>
            </label>
          </div>
          <div className="battle-lobby__actions">
            <button className="button button--ghost" type="button" onClick={onOpenDeck}>调整卡组</button>
            <button
              className="sound-toggle"
              type="button"
              onClick={onToggleSound}
              aria-pressed={soundEnabled}
              aria-label={soundEnabled ? "关闭战斗音效" : "开启战斗音效"}
            >
              <span aria-hidden="true">{soundEnabled ? "♪" : "×"}</span>
              {soundEnabled ? "音效开启" : "音效静音"}
            </button>
            <button className="button button--primary button--large" type="button" onClick={onStart}><Icon name="swords" />开始演算</button>
          </div>
          <PvpLobby
            state={pvp}
            apprenticePool={apprenticePool}
            url={pvpUrl}
            roomInput={pvpRoomInput}
            onUrl={onPvpUrl}
            onRoomInput={onPvpRoomInput}
            onConnect={onPvpConnect}
            onCreate={onPvpCreate}
            onQueue={onPvpQueue}
            onLeaveQueue={onPvpLeaveQueue}
            onFallbackAi={onPvpFallbackAi}
            onJoin={onPvpJoin}
            onReady={onPvpReady}
            onDisconnect={onPvpDisconnect}
          />
        </div>
      </section>
    );
  }

  const playerTurn = battle.currentPlayer === "player" && battle.status === "playing";
  const mulliganActive = battle.status === "mulligan";
  const discoverActive = battle.status === "discover" && Boolean(battle.discover);
  const chooseOneActive = battle.status === "choose-one" && Boolean(battle.chooseOne);
  const onlineTransportReady = !online || (
    Boolean(pvp.roomCode) &&
    pvp.status !== "offline" &&
    pvp.status !== "error" &&
    pvp.status !== "connecting"
  );
  const playerCanMulligan = mulliganActive && !battle.mulliganDone && !effectsLocked && onlineTransportReady;
  const playerCanAct = playerTurn && !effectsLocked && onlineTransportReady;
  const playerCanDiscover = discoverActive && battle.currentPlayer === "player" && !effectsLocked && onlineTransportReady;
  const playerCanChooseOne = chooseOneActive && battle.currentPlayer === "player" && !effectsLocked && onlineTransportReady;
  const trainingSteps = [
    {
      label: "确认起手",
      detail: "点击不想保留的牌，再确认起手。",
      done: !mulliganActive,
    },
    {
      label: "使用一张牌",
      detail: "观察费用；若费用差 1，可先使用幸运币，再部署一张牌。",
      done: battle.report.cardsPlayed[0] > 0,
    },
    {
      label: "发动一次攻击",
      detail: "可行动单位会亮起；先选单位，再选目标。",
      done: battle.report.attacks[0] > 0,
    },
    {
      label: "结束一个回合",
      detail: "行动完成后结束回合，能量会在下回合补满。",
      done: battle.log.some((line) => line.includes("我方结束了回合")),
    },
  ];
  const completedTrainingSteps = trainingSteps.filter((step) => step.done).length;
  const pendingDefinition = pendingCard ? CARD_BY_ID.get(pendingCard.cardId) : undefined;
  const pendingRuleCard = pendingCard ? cardRuleForHandSlot(pendingCard) : undefined;
  const targetRule = pendingHeroPower
    ? battle.player.heroPowerTarget
    : pendingRuleCard?.target ?? pendingDefinition?.target ?? "none";
  const pendingEffectsForTarget = [
    ...(pendingRuleCard?.effect ?? []),
    ...(pendingRuleCard?.onPlay ?? []),
    ...(pendingRuleCard?.combo ?? []),
  ];
  const cardCanTarget = (side: "player" | "ai", kind: "unit" | "hero") => {
    if (!pendingDefinition && !pendingHeroPower) return false;
    if (targetRule === "any-character") return true;
    if (targetRule === "enemy-character") return side === "ai";
    if (targetRule === "friendly-character") return side === "player";
    if (targetRule === "enemy-unit") return side === "ai" && kind === "unit";
    if (targetRule === "friendly-unit") return side === "player" && kind === "unit";
    if (targetRule === "any-unit") return kind === "unit";
    return false;
  };
  const effectForUnit = (unitId: string): BattleUnitEffect | undefined => {
    if (!effect) return undefined;
    if (effect.sourceId === unitId && (effect.kind === "summon" || effect.kind === "attack")) {
      return effect.kind;
    }
    if (effect.targetId !== unitId) return undefined;
    if (
      effect.kind === "damage" ||
      effect.kind === "heal" ||
      effect.kind === "buff" ||
      effect.kind === "shield"
    ) {
      return effect.kind;
    }
    return undefined;
  };
  const effectForHero = (side: "player" | "ai"): BattleHeroEffect | undefined => {
    if (!effect || effect.targetKind !== "hero" || effect.targetSide !== side) {
      return undefined;
    }
    if (effect.kind === "damage" || effect.kind === "heal" || effect.kind === "shield") {
      return effect.kind;
    }
    return undefined;
  };
  const impactForUnit = (unitId: string): BattleVisualEffect | undefined => {
    if (!effect || effect.targetKind !== "unit" || effect.targetId !== unitId) {
      return undefined;
    }
    return effect;
  };
  const impactForHero = (side: "player" | "ai"): BattleVisualEffect | undefined => {
    if (!effect || effect.targetKind !== "hero" || effect.targetSide !== side) {
      return undefined;
    }
    return effect;
  };
  const visibleEnemyTaunts = battle.ai.board.filter(
    (unit) => unit.health > 0 && unit.keywords.includes("taunt") && !unit.stealthActive,
  );
  const attackBlockedByTaunt = Boolean(selectedAttacker && visibleEnemyTaunts.length > 0);
  const selectedAttackerUnit = selectedAttacker
    ? battle.player.board.find((unit) => unit.id === selectedAttacker)
    : undefined;
  const traitTierForBoard = (board: BattleUnit[], trait: Trait) => {
    const cards = board
      .map((unit) => CARD_BY_ID.get(unit.cardId))
      .filter((card): card is CatalogCard => Boolean(card));
    return getTraitStatuses(cards).find((status) => status.id === trait)?.tier ?? 0;
  };
  const playerSwiftTier = traitTierForBoard(battle.player.board, "swift");
  const playerBulwarkTier = traitTierForBoard(battle.player.board, "bulwark");
  const playerArcaneTier = traitTierForBoard(battle.player.board, "arcane");
  const enemyBulwarkTier = traitTierForBoard(battle.ai.board, "bulwark");
  const pendingEffects = pendingEffectsForTarget;
  const selectedAttackerCard = selectedAttackerUnit
    ? CARD_BY_ID.get(selectedAttackerUnit.cardId)
    : undefined;
  const selectedAttackerPoisonous = Boolean(selectedAttackerUnit?.keywords.includes("poisonous"));
  const selectedAttackerHasBulwark = Boolean(selectedAttackerCard?.traits.includes("bulwark"));
  const selectedAttackValue = selectedAttacker
    ? selectedAttackerUnit
      ? selectedAttackerUnit.attack + (selectedAttackerCard?.traits.includes("swift") ? playerSwiftTier : 0)
      : (battle.player.weapon?.attack ?? 0) + battle.player.heroAttackBonus
    : 0;
  const rushOnlyAttack = Boolean(selectedAttackerUnit?.rushOnly);
  const enemyHeroTargetable = selectedAttacker
    ? !attackBlockedByTaunt && !rushOnlyAttack
    : cardCanTarget("ai", "hero");
  const enemyUnitTargetable = (unit: BattleUnit) => {
    if (unit.health <= 0) return false;
    if (selectedAttacker) {
      if (unit.stealthActive) return false;
      return !attackBlockedByTaunt || unit.keywords.includes("taunt");
    }
      return cardCanTarget("ai", "unit", unit) && !unit.stealthActive;
  };
  const targetPreviewForPendingUnit = (unit: BattleUnit, side: "player" | "ai"): string | undefined => {
    if (!pendingCard && !pendingHeroPower) return undefined;
    if (pendingHeroPower) {
      const power = battle.player.heroPowerEffect;
      if (power.kind === "damage-enemy-unit" && side === "ai") {
        return unit.keywords.includes("shield") ? "先破护盾" : `预计 −${Math.min(unit.health, power.amount)}`;
      }
      if (power.kind === "heal-friendly-unit" && side === "player") {
        return `预计 +${Math.min(unit.maxHealth - unit.health, power.amount)} 生命`;
      }
      if (power.kind === "heal-friendly-character" && side === "player") {
        return `预计 +${Math.min(unit.maxHealth - unit.health, power.amount)} 生命`;
      }
      return undefined;
    }
    const damage = pendingEffects.reduce(
      (total, effect) => total + (effect.kind === "damage" ? effect.amount : 0),
      0,
    ) + (pendingDefinition?.type === "spell" ? playerArcaneTier : 0);
    const heal = pendingEffects.reduce(
      (total, effect) => total + (effect.kind === "heal" ? effect.amount : 0),
      0,
    );
    const buffAttack = pendingEffects.reduce(
      (total, effect) => total + (effect.kind === "buff" || effect.kind === "temporary-buff" ? effect.attack : 0),
      0,
    );
    const buffHealth = pendingEffects.reduce(
      (total, effect) => total + (effect.kind === "buff" || effect.kind === "temporary-buff" ? effect.health : 0),
      0,
    );
    const hasSilence = pendingEffects.some((effect) => effect.kind === "silence");
    const hasFreeze = pendingEffects.some((effect) => effect.kind === "freeze" || effect.kind === "random-enemy-freeze");
    const hasTransform = pendingEffects.some((effect) => effect.kind === "transform");
    if (side === "ai" && damage > 0) {
      return unit.keywords.includes("shield") ? "先破护盾" : `预计 −${Math.min(unit.health, damage)}`;
    }
    if (side === "player" && heal > 0) {
      return `预计 +${Math.min(unit.maxHealth - unit.health, heal)} 生命`;
    }
    if (side === "player" && (buffAttack !== 0 || buffHealth !== 0)) {
      return `预计 ${buffAttack >= 0 ? "+" : ""}${buffAttack}/${buffHealth >= 0 ? "+" : ""}${buffHealth}`;
    }
    if (side === "ai" && hasTransform) return "预计变形";
    if (side === "ai" && hasSilence) return "预计沉默";
    if (side === "ai" && hasFreeze) return "预计冻结";
    return undefined;
  };
  const targetPreviewForUnit = (unit: BattleUnit, side: "player" | "ai" = "ai"): string | undefined => {
    if (selectedAttacker && side === "ai" && !pendingCard && !pendingHeroPower && enemyUnitTargetable(unit)) {
      const targetCard = CARD_BY_ID.get(unit.cardId);
      const hasShield = unit.keywords.includes("shield");
      const reduction = targetCard?.traits.includes("bulwark") ? enemyBulwarkTier : 0;
      const resolvedDamage = hasShield
        ? 0
        : Math.min(unit.health, Math.max(1, selectedAttackValue - reduction));
      const poisoned = selectedAttackerPoisonous && resolvedDamage > 0;
      const remainingHealth = poisoned ? 0 : Math.max(0, unit.health - resolvedDamage);
      const outcome = hasShield
        ? "先破护盾"
        : remainingHealth > 0
          ? `预计剩 ${remainingHealth}`
          : "预计击破";
      // Combat damage is simultaneous: a defender still gets its strike even
      // when the previewed hit is lethal.  Keep the prediction aligned with
      // the reducer so players can make informed trades before committing.
      const retaliation = selectedAttackerUnit
        ? selectedAttackerUnit.keywords.includes("shield")
          ? 0
          : Math.min(
              selectedAttackerUnit.health,
              Math.max(1, unit.attack - (selectedAttackerHasBulwark ? playerBulwarkTier : 0)),
            )
        : Math.min(battle.player.health, Math.max(0, unit.attack - battle.player.armor));
      return retaliation > 0 ? `${outcome} · 反击 −${retaliation}` : outcome;
    }
    if ((pendingCard || pendingHeroPower) && cardCanTarget(side, "unit")) {
      return targetPreviewForPendingUnit(unit, side);
    }
    return undefined;
  };
  const targetPreviewForHero = (side: "player" | "ai"): string | undefined => {
    if (selectedAttacker && side === "ai" && !pendingCard && !pendingHeroPower && enemyHeroTargetable) {
      const armorAbsorbed = Math.min(battle.ai.armor, selectedAttackValue);
      const healthDamage = Math.min(battle.ai.health, Math.max(0, selectedAttackValue - armorAbsorbed));
      return armorAbsorbed > 0
        ? `预计破甲 ${armorAbsorbed} · −${healthDamage}`
        : `预计 −${healthDamage} 核心`;
    }
    if (!pendingCard && !pendingHeroPower || !cardCanTarget(side, "hero")) return undefined;
    if (pendingHeroPower) {
      const power = battle.player.heroPowerEffect;
      if (power.kind === "damage-enemy-hero" && side === "ai") {
        const armorAbsorbed = Math.min(battle.ai.armor, power.amount);
        return armorAbsorbed > 0
          ? `预计破甲 ${armorAbsorbed} · −${Math.max(0, power.amount - armorAbsorbed)}`
          : `预计 −${Math.min(battle.ai.health, power.amount)} 核心`;
      }
      if ((power.kind === "heal-friendly-hero" || power.kind === "heal-friendly-character") && side === "player") {
        return `预计 +${Math.min(battle.player.maxHealth - battle.player.health, power.amount)} 生命`;
      }
      if (power.kind === "armor" && side === "player") return `预计 +${power.amount} 护甲`;
      return undefined;
    }
    const damage = pendingEffects.reduce(
      (total, effect) => total + (effect.kind === "damage" ? effect.amount : 0),
      0,
    ) + (pendingDefinition?.type === "spell" ? playerArcaneTier : 0);
    if (damage > 0 && side === "ai") {
      const armorAbsorbed = Math.min(battle.ai.armor, damage);
      return armorAbsorbed > 0
        ? `预计破甲 ${armorAbsorbed} · −${Math.max(0, damage - armorAbsorbed)}`
        : `预计 −${Math.min(battle.ai.health, damage)} 核心`;
    }
    const heal = pendingEffects.reduce(
      (total, effect) => total + (effect.kind === "heal" ? effect.amount : 0),
      0,
    );
    if (heal > 0 && side === "player") {
      return `预计 +${Math.min(battle.player.maxHealth - battle.player.health, heal)} 生命`;
    }
    return undefined;
  };
  const targetPromptAttacker = selectedAttackerUnit
    ? `${selectedAttackerUnit.name} · ⚔ ${selectedAttackValue} · ◆ ${selectedAttackerUnit.health}`
    : selectedAttacker
      ? `${battle.player.weapon?.name ?? battle.player.heroName} · ⚔ ${selectedAttackValue}${battle.player.weapon ? ` · ◈ ${battle.player.weapon.durability}` : ""}`
      : undefined;
  const targetPromptPreview = selectedAttacker
    ? selectedAttackerUnit
      ? `有效攻击 ⚔ ${selectedAttackValue} · 目标卡片会显示破盾、击破与反击结果`
      : battle.player.weapon
        ? `武器有效攻击 ⚔ ${selectedAttackValue} · 命中后耐久 −1`
        : `英雄有效攻击 ⚔ ${selectedAttackValue}`
    : undefined;
  return (
    <section className="screen screen--battle battle-room" aria-labelledby="battle-room-title">
      <header className="battle-room__top">
        <div>
          <span className="section-heading__eyebrow">{online ? "LIVE PVP" : "LIVE SIMULATION"} · TURN {battle.turn}</span>
          <h1 id="battle-room-title">战术演算舱</h1>
        </div>
          <div className="battle-room__status">
            <button
              className="sound-toggle sound-toggle--compact"
              type="button"
              onClick={onToggleSound}
              aria-pressed={soundEnabled}
              aria-label={soundEnabled ? "关闭战斗音效" : "开启战斗音效"}
            >
              <span aria-hidden="true">{soundEnabled ? "♪" : "×"}</span>
              {soundEnabled ? "音效" : "静音"}
            </button>
            <button
              className="sound-toggle sound-toggle--compact battle-speed-toggle"
              type="button"
              onClick={onToggleReplaySpeed}
              aria-pressed={replaySlow}
              aria-label={replaySlow ? "切换为标准战斗回放" : "切换为慢速战斗回放"}
              title={replaySlow ? "当前为慢速回放" : "当前为标准回放"}
            >
              <span aria-hidden="true">{replaySlow ? "◷" : "›"}</span>
              {replaySlow ? "慢速" : "标准"}
            </button>
            {playerTurn && turnClockSeconds !== null && (
              <div
                className={`turn-clock ${turnClockSeconds <= 10 ? "turn-clock--urgent" : ""}`}
                role="status"
                aria-label={`本回合剩余 ${turnClockSeconds} 秒`}
              >
                <strong>{turnClockSeconds}</strong>
                <small>行动秒数</small>
              </div>
            )}
            <div
            className={`turn-indicator ${
              battle.status === "finished"
                ? "turn-indicator--finished"
                : mulliganActive
                  ? "turn-indicator--mulligan"
                : discoverActive
                  ? "turn-indicator--discover"
                : chooseOneActive
                  ? "turn-indicator--choose-one"
                : playerTurn
                  ? "turn-indicator--player"
                  : "turn-indicator--ai"
            }`}
          >
            <span />
            {battle.status === "finished" ? "演算结束" : mulliganActive ? "起手换牌" : discoverActive ? "发现选择" : chooseOneActive ? "抉择分支" : playerTurn ? "你的回合" : "敌方回合"}
          </div>
        </div>
      </header>

      <div className="battle-layout">
        <div className={`battlefield ${effect ? `battlefield--fx-${effect.kind}` : ""}`}>
          <div className="battlefield__grid" aria-hidden="true" />
          {effect && <BattleEffectLayer key={effect.id} effect={effect} />}
          <div className="battlefield__enemy-zone">
            <div className="battlefield__side-info">
              <HeroCore
                side={battle.ai}
                enemy
                enemyLabel={opponentName ?? (online ? "联机对手" : "镜像演算体 K-7")}
                active={battle.currentPlayer === "ai"}
                canTarget={enemyHeroTargetable}
                effect={effectForHero("ai")}
                impact={impactForHero("ai")}
                targetPreview={targetPreviewForHero("ai")}
                onTarget={() =>
                  pendingCard || pendingHeroPower
                    ? onCardTarget({ kind: "hero", side: "ai" })
                    : onAttack({ kind: "hero" })
                }
                targetLabel={
                  pendingCard
                    ? `以${pendingDefinition?.name ?? "卡牌"}选择敌方核心`
                    : pendingHeroPower
                      ? `以${battle.player.heroPowerName}选择敌方核心`
                    : "攻击敌方核心"
                }
              />
              <div className="mana-readout mana-readout--enemy" aria-label={`敌方能量 ${battle.ai.mana}/${battle.ai.maxMana}`}>
                <Icon name="spark" size={16} /><strong>{battle.ai.mana}</strong><span>/ {battle.ai.maxMana}</span>
                {battle.ai.overloadLocked > 0 && <small className="mana-readout__overload">当前锁定 {battle.ai.overloadLocked}</small>}
                {battle.ai.overload > 0 && <small className="mana-readout__overload">下回合锁定 {battle.ai.overload}</small>}
              </div>
            </div>
            <div className="enemy-hand" aria-label={`敌方有 ${battle.ai.hand.length} 张手牌`}>
              {battle.ai.hand.map((card, index) => <span className="card-back" key={`${card.instanceId}-${index}`} />)}
              <small>{battle.ai.deckCount} 张牌库</small>
            </div>
            <SecretTray secrets={battle.ai.secrets} enemy />
            <ZoneHistoryTray side={battle.ai} enemy />
            <div
              className="board-row board-row--enemy"
              aria-label={`敌方战场 ${battle.ai.board.length}/${BOARD_SLOT_COUNT}`}
            >
              {battle.ai.board.length > 0 ? battle.ai.board.map((unit) => (
                <BoardUnit
                  key={unit.id}
                  unit={unit}
                  targetable={enemyUnitTargetable(unit)}
                  effect={effectForUnit(unit.id)}
                  impact={impactForUnit(unit.id)}
                  targetPreview={targetPreviewForUnit(unit)}
                  onTarget={() =>
                    pendingCard || pendingHeroPower
                      ? onCardTarget({ kind: "unit", side: "ai", id: unit.id })
                      : onAttack({ kind: "unit", id: unit.id })
                  }
                  onInspect={() => {
                    const card = CARD_BY_ID.get(unit.cardId);
                    if (card) onInspectCard(card);
                  }}
                />
              )) : <span className="board-row__empty">敌方阵地空置</span>}
              {Array.from({ length: Math.max(0, BOARD_SLOT_COUNT - battle.ai.board.length) }, (_, index) => (
                <span className="board-slot" key={`enemy-slot-${index}`} aria-hidden="true"><i /></span>
              ))}
            </div>
          </div>

          <div className="battlefield__divider">
            <span />
            <strong>TURN {battle.turn}</strong>
            <span />
          </div>

          <div className="battlefield__player-zone">
            <div
              className="board-row board-row--player"
              aria-label={`我方战场 ${battle.player.board.length}/${BOARD_SLOT_COUNT}`}
            >
              {battle.player.board.length > 0 ? battle.player.board.map((unit) => (
                <BoardUnit
                  key={unit.id}
                  unit={unit}
                  selected={selectedAttacker === unit.id}
                  targetable={cardCanTarget("player", "unit", unit) && unit.health > 0}
                  effect={effectForUnit(unit.id)}
                  impact={impactForUnit(unit.id)}
                  targetPreview={targetPreviewForUnit(unit, "player")}
                  onSelect={pendingCard || pendingHeroPower || !playerCanAct ? undefined : () => onSelectAttacker(unit.id)}
                  onTarget={() => onCardTarget({ kind: "unit", side: "player", id: unit.id })}
                  onInspect={() => {
                    const card = CARD_BY_ID.get(unit.cardId);
                    if (card) onInspectCard(card);
                  }}
                />
              )) : <span className="board-row__empty">选择手牌，部署你的首个单位</span>}
              {Array.from({ length: Math.max(0, BOARD_SLOT_COUNT - battle.player.board.length) }, (_, index) => (
                <span className="board-slot" key={`player-slot-${index}`} aria-hidden="true"><i /></span>
              ))}
            </div>
            <div className="battlefield__side-info battlefield__side-info--player">
                <HeroCore
                side={battle.player}
                active={playerTurn}
                canTarget={cardCanTarget("player", "hero")}
                effect={effectForHero("player")}
                impact={impactForHero("player")}
                targetPreview={targetPreviewForHero("player")}
                onTarget={() => onCardTarget({ kind: "hero", side: "player" })}
                targetLabel={`以${pendingDefinition?.name ?? (pendingHeroPower ? battle.player.heroPowerName : "卡牌")}选择我方核心`}
              />
              <div className="mana-readout" aria-label={`我方能量 ${battle.player.mana}/${battle.player.maxMana}`}>
                <Icon name="spark" size={16} /><strong>{battle.player.mana}</strong><span>/ {battle.player.maxMana}</span>
                {battle.player.overloadLocked > 0 && <small className="mana-readout__overload">当前锁定 {battle.player.overloadLocked}</small>}
                {battle.player.overload > 0 && <small className="mana-readout__overload">下回合锁定 {battle.player.overload}</small>}
                <div className="mana-pips" aria-hidden="true">
                  {Array.from({ length: battle.player.maxMana }, (_, index) => {
                    const isFilled = index < battle.player.mana;
                    const isLocked = !isFilled && index >= battle.player.maxMana - Math.min(battle.player.overloadLocked, battle.player.maxMana);
                    return <i className={`${isFilled ? "is-filled" : ""} ${isLocked ? "is-locked" : ""}`.trim()} key={index} />;
                  })}
                </div>
              </div>
              {(battle.player.weapon || battle.player.heroAttackBonus > 0) && (
                <button
                  className={`weapon-attack-button ${selectedAttacker === "hero-0" ? "weapon-attack-button--selected" : ""}`}
                  type="button"
                  disabled={!playerCanAct || battle.player.heroHasAttacked}
                  onClick={onSelectHeroAttacker}
                  aria-label={battle.player.heroHasAttacked ? "英雄本回合已经攻击" : `使用 ${battle.player.heroName} 发起英雄攻击`}
                >
                  <span className="weapon-attack-button__icon">⚔</span>
                  <span><strong>{selectedAttacker === "hero-0" ? "选择攻击目标" : "英雄攻击"}</strong><small>{battle.player.weapon ? `${battle.player.weapon.name} · ${battle.player.weapon.attack} 攻击 · ${battle.player.weapon.durability} 耐久` : battle.player.heroName}{battle.player.heroAttackBonus > 0 ? ` · 临时 +${battle.player.heroAttackBonus}` : ""}</small></span>
                </button>
              )}
              <button
                className={`hero-power-button ${battle.player.heroPowerUsed ? "hero-power-button--used" : ""} ${pendingHeroPower ? "hero-power-button--selected" : ""}`}
                type="button"
                disabled={!playerCanAct || battle.player.heroPowerUsed || battle.player.mana < battle.player.heroPowerCost || Boolean(pendingCard)}
                onClick={onHeroPower}
                title={battle.player.heroPowerDescription}
                aria-label={battle.player.heroPowerUsed ? `${battle.player.heroPowerName}本回合已使用` : pendingHeroPower ? `取消${battle.player.heroPowerName}目标选择` : `使用${battle.player.heroPowerName}，消耗 ${battle.player.heroPowerCost} 点能量`}
              >
                <span className="hero-power-button__icon">✦</span>
                <span><strong>{battle.player.heroPowerName}</strong><small>{battle.player.heroPowerUsed ? "本回合已用" : pendingHeroPower ? "选择目标中 · 点击下方目标" : `${battle.player.heroPowerCost} 能量 · ${battle.player.heroPowerDescription}`}</small></span>
              </button>
            </div>
            <SecretTray secrets={battle.player.secrets} />
            <ZoneHistoryTray side={battle.player} />
            <div className="player-hand">
              <span className={`player-hand__count ${battle.player.hand.length >= 10 ? "player-hand__count--full" : ""}`}>
                手牌 {battle.player.hand.length} / 10
              </span>
              {battle.player.hand.map((handCard, handIndex) => {
                const card = CARD_BY_ID.get(handCard.cardId);
                if (!card) return null;
                const fragmentLabel = handCard.fragment === "left" ? "左片" : handCard.fragment === "right" ? "右片" : null;
                const visualCard: CatalogCard = fragmentLabel
                  ? {
                      ...card,
                      name: `${card.name} · ${fragmentLabel}`,
                      description: `破碎${fragmentLabel}：单独使用时只结算这一半的效果；与同组另一片相邻后自动重组。${card.description}`,
                    }
                  : card;
                const effectiveCost = Math.max(0, card.cost - handCard.costReduction);
                const quickdrawActive = Boolean(
                  !mulliganActive && card.quickdraw && handCard.enteredTurn === battle.turn,
                );
                const selectedForMulligan = mulliganSelection.includes(handIndex)
                  || Boolean(handCard.fragmentGroupId && battle.player.hand.some((entry, index) =>
                    entry.fragmentGroupId === handCard.fragmentGroupId && mulliganSelection.includes(index)));
                const enemyUpgradeAvailable = card.type === "unit"
                  && battle.ai.board.some((unit) => unit.cardId === card.id && unit.stars === 1);
                const disabled = mulliganActive
                  ? !playerCanMulligan
                  : !playerCanAct || effectiveCost > battle.player.mana || pendingHeroPower;
                return (
                  <div
                    className={`hand-card ${handCard.fragment ? `hand-card--fragment hand-card--fragment-${handCard.fragment}` : card.shatter ? "hand-card--reassembled" : ""} ${quickdrawActive ? "hand-card--quickdraw" : ""} ${disabled ? "hand-card--disabled" : ""} ${pendingCard?.instanceId === handCard.instanceId || selectedForMulligan ? "hand-card--selected" : ""}`}
                    key={handCard.instanceId}
                  >
                    <CardTile
                      card={visualCard}
                      compact
                      showDescription
                      costOverride={effectiveCost}
                      action={() => mulliganActive ? onToggleMulligan(handIndex) : onPlayCard(handCard)}
                      actionLabel={mulliganActive ? `${selectedForMulligan ? "保留" : "更换"}${card.name}` : `使用${card.name}`}
                      disabled={disabled}
                    />
                    <button
                      className="hand-card__inspect"
                      type="button"
                      onClick={() => onInspectCard(visualCard)}
                      aria-label={`查看${card.name}详情`}
                      title={`查看${card.name}详情`}
                    >
                      i
                    </button>
                    {fragmentLabel && (
                      <span className="hand-card__fragment" aria-label={`${card.name}${fragmentLabel}`}>
                        {handCard.fragment === "left" ? "◀" : "▶"} {fragmentLabel}
                      </span>
                    )}
                    {quickdrawActive && (
                      <span className="hand-card__quickdraw" aria-label={`${card.name}快枪效果已激活`}>
                        ⚡ 快枪就绪
                      </span>
                    )}
                    {!mulliganActive && card.tradeable && (
                      <button
                        className="hand-card__trade"
                        type="button"
                        disabled={!playerCanAct || battle.player.mana < 1}
                        onClick={() => onTradeCard(handCard)}
                        aria-label={`交易${card.name}，消耗 1 点能量`}
                      >
                        <span>↔</span> 交易 · 1
                      </button>
                    )}
                    {!mulliganActive && card.preparable && (
                      handCard.costReduction > 0 ? (
                        <span className="hand-card__prepare is-ready" aria-label={`${card.name}已预备，费用降低 ${handCard.costReduction} 点`}>
                          <span>⌄</span> 已预备 · −{handCard.costReduction}
                        </span>
                      ) : (
                        <button
                          className="hand-card__prepare"
                          type="button"
                          disabled={!playerCanAct || battle.player.mana < 1}
                          onClick={() => onPrepareCard(handCard)}
                          aria-label={`预备${card.name}，花费全部剩余能量并额外降低 1 点费用`}
                        >
                          <span>⌄</span> 预备 · 全部能量
                        </button>
                      )
                    )}
                    {!mulliganActive && card.disguised && (
                      <button
                        className="hand-card__disguise"
                        type="button"
                        disabled={
                          !playerCanAct
                          || effectiveCost > battle.player.mana
                          || Boolean(pendingHeroPower)
                          || (battle.ai.board.length >= 7 && !enemyUpgradeAvailable)
                        }
                        onClick={() => onPlayCard(handCard, "enemy")}
                        aria-label={`将${card.name}伪装部署到敌方战场`}
                      >
                        <span>◫</span> 伪装 · 敌方战场
                      </button>
                    )}
                  </div>
                );
              })}
              {battle.player.hand.length === 0 && <span className="player-hand__empty">手牌为空</span>}
            </div>
            <div className="battle-mobile-dock" aria-label="移动端战斗操作">
              {effectsLocked ? (
                <button className="button button--outline" type="button" onClick={onSkipEffects}>
                  跳过回放
                </button>
              ) : mulliganActive ? (
                <button className="button button--primary" type="button" disabled={!playerCanMulligan} onClick={onConfirmMulligan}>
                  {battle.mulliganDone ? "等待对手" : `确认起手${mulliganSelection.length > 0 ? `（换 ${mulliganSelection.length} 张）` : ""}`}
                </button>
              ) : discoverActive ? (
                <span className="battle-mobile-dock__waiting">请选择一张发现卡牌</span>
              ) : chooseOneActive ? (
                <span className="battle-mobile-dock__waiting">请选择一个战术分支</span>
              ) : battle.status === "playing" ? (
                <>
                  <button className="button button--end-turn" type="button" disabled={!playerCanAct} onClick={onEndTurn}>
                    {playerTurn ? "结束回合" : "等待敌方"}
                  </button>
                  <button className="button button--concede" type="button" disabled={!playerTurn} onClick={onConcede}>
                    投降
                  </button>
                </>
              ) : null}
              {(selectedAttacker || pendingCard || pendingHeroPower) && !effectsLocked && (
                <button className="battle-mobile-dock__cancel" type="button" onClick={onCancelTarget}>
                  取消选择
                </button>
              )}
            </div>
            <span className="deck-counter"><Icon name="cards" size={16} /> 牌库 {battle.player.deckCount}</span>
          </div>
        </div>

        {inspectedCard && (
          <div className="card-inspector-backdrop" role="presentation" onClick={onCloseInspector}>
            <section
              className="card-inspector"
              role="dialog"
              aria-modal="true"
              aria-label={`${inspectedCard.name}卡牌详情`}
              onClick={(event) => event.stopPropagation()}
            >
              <div className="card-inspector__heading">
                <div>
                  <span>TACTICAL ARCHIVE</span>
                  <strong>卡牌详情</strong>
                </div>
                <button type="button" onClick={onCloseInspector} aria-label="关闭卡牌详情">
                  <Icon name="close" size={18} />
                </button>
              </div>
              <div className="card-inspector__card">
                <CardTile card={inspectedCard} showDescription />
              </div>
              <p className="card-inspector__hint">点击空白处或关闭按钮返回战场。</p>
            </section>
          </div>
        )}

        <aside className="battle-console">
          <div className="battle-console__message" role="status">
            <span><Icon name="radar" /></span>
            <p>
              {message}
              {effectsLocked && (
                <small className="battle-console__replay">
                  战况回放中 · 还有 {effectCount} 个效果
                </small>
              )}
            </p>
          </div>
          {trainingActive && (
            <section className={`battle-training ${completedTrainingSteps === trainingSteps.length ? "battle-training--complete" : ""}`} aria-labelledby="battle-training-title">
              <div className="battle-training__heading">
                <div>
                  <span>CADET ROUTE</span>
                  <strong id="battle-training-title">
                    {completedTrainingSteps === trainingSteps.length ? "基础训练完成" : "新手训练进行中"}
                  </strong>
                </div>
                <span>{completedTrainingSteps} / {trainingSteps.length}</span>
              </div>
              <ol>
                {trainingSteps.map((step, index) => {
                  const current = !step.done && trainingSteps.slice(0, index).every((item) => item.done);
                  return (
                    <li className={`${step.done ? "is-done" : ""} ${current ? "is-current" : ""}`} key={step.label}>
                      <span>{step.done ? <Icon name="check" size={12} /> : index + 1}</span>
                      <div><strong>{step.label}</strong>{current && <small>{step.detail}</small>}</div>
                    </li>
                  );
                })}
              </ol>
              <button type="button" onClick={onExitTraining}>
                {completedTrainingSteps === trainingSteps.length ? "完成并继续对局" : "退出引导"}
              </button>
            </section>
          )}
          {mulliganActive && (
            <div className="mulligan-prompt" role="status">
              <div>
                <strong>起手换牌</strong>
                <p>{battle.mulliganDone ? "已确认，等待对手完成起手。" : "点击不想保留的手牌，再确认起手。换掉的牌会回到牌库并抽取替代牌。"}</p>
              </div>
              <button className="button button--primary" type="button" disabled={!playerCanMulligan} onClick={onConfirmMulligan}>
                {battle.mulliganDone ? "等待对手" : `确认起手${mulliganSelection.length > 0 ? `（换 ${mulliganSelection.length} 张）` : ""}`}
              </button>
            </div>
          )}
          {discoverActive && battle.discover && (
            <div className="discover-prompt" role="dialog" aria-label="发现卡牌">
              <div className="discover-prompt__heading">
                <div>
                  <strong>{battle.discover.choices.length > 0 ? "发现一张卡牌" : "对手正在发现"}</strong>
                  <p>{battle.discover.choices.length > 0 ? "从三张候选档案中选择一张加入手牌。" : "候选档案对你隐藏，等待对手完成选择。"}</p>
                </div>
                <span>DISCOVER</span>
              </div>
              {battle.discover.choices.length > 0 ? (
                <div className="discover-prompt__cards">
                  {battle.discover.choices.map((choice, choiceIndex) => {
                    const card = CARD_BY_ID.get(choice.cardId);
                    if (!card) return null;
                    return (
                      <CardTile
                        key={`${choice.cardId}-${choiceIndex}`}
                        card={card}
                        compact
                        costOverride={choice.currentCost}
                        action={() => onChooseDiscover(choice.cardId, choiceIndex)}
                        actionLabel={`选择${card.name}`}
                        disabled={!playerCanDiscover}
                      />
                    );
                  })}
                </div>
              ) : (
                <div className="discover-prompt__waiting">等待对手锁定发现卡牌…</div>
              )}
            </div>
          )}
          {chooseOneActive && battle.chooseOne && (
            <div className="choose-one-prompt" role="dialog" aria-label="抉择分支">
              <div className="choose-one-prompt__heading">
                <div>
                  <strong>{battle.chooseOne.options.length > 0 ? battle.chooseOne.sourceKind === "hero-card" ? `选择灭世灾变 · 还可选 ${battle.chooseOne.remainingChoices}` : "选择一个战术分支" : "对手正在抉择"}</strong>
                  <p>{battle.chooseOne.options.length > 0 ? battle.chooseOne.sourceKind === "hero-card" ? "选择后立即释放；已选灾变不会重复出现。" : "每张牌只能结算其中一个分支，选择后立即生效。" : "等待对手锁定抉择分支…"}</p>
                </div>
                <span>{battle.chooseOne.sourceKind === "hero-card" ? `CATACLYSM ×${battle.chooseOne.remainingChoices}` : "CHOOSE ONE"}</span>
              </div>
              {battle.chooseOne.options.length > 0 ? (
                <div className="choose-one-prompt__options">
                  {battle.chooseOne.options.map((option, index) => (
                    <button
                      className="choose-one-option"
                      type="button"
                      key={`${option.label}-${index}`}
                      disabled={!playerCanChooseOne}
                      onClick={() => onChooseOne(index)}
                    >
                      <span className="choose-one-option__index">{index + 1}</span>
                      <span><strong>{option.label}</strong><small>选择后立即结算</small></span>
                    </button>
                  ))}
                </div>
              ) : (
                <div className="discover-prompt__waiting">等待对手锁定抉择分支…</div>
              )}
            </div>
          )}
          {(selectedAttacker || pendingCard || pendingHeroPower) && (
            <div className="target-prompt" role="status" aria-live="polite">
              <Icon name="swords" />
              <span>
                <strong>
                  {pendingCard
                    ? `${pendingDefinition?.name ?? "卡牌"} · 选择目标`
                    : pendingHeroPower
                      ? `${battle.player.heroPowerName} · 选择目标`
                      : "目标锁定模式"}
                </strong>
                <small>
                  {pendingCard
                    ? "场上可用目标已高亮"
                    : pendingHeroPower
                      ? targetRule === "enemy-unit" ? "敌方单位已高亮" : "友方角色已高亮"
                    : rushOnlyAttack
                      ? "突袭：本回合只能攻击敌方单位"
                      : attackBlockedByTaunt
                        ? "嘲讽生效：必须优先攻击嘲讽单位"
                        : "选择敌方单位或核心"}
                </small>
                {targetPromptAttacker && (
                  <em className="target-prompt__attacker">
                    {targetPromptAttacker}
                  </em>
                )}
                {selectedAttacker && (
                  <em className="target-prompt__preview">
                    {targetPromptPreview}
                  </em>
                )}
              </span>
              <button
                className="target-prompt__cancel"
                type="button"
                onClick={onCancelTarget}
                aria-label={pendingCard ? "取消选择卡牌目标" : pendingHeroPower ? "取消选择核心技能目标" : "取消攻击目标选择"}
              >
                <Icon name="close" size={16} />
              </button>
            </div>
          )}
          <div className="battle-synergies" aria-label="实时特质协议">
            <BattleTraitProtocol label="我方协议" board={battle.player.board} />
            <BattleTraitProtocol label="敌方协议" board={battle.ai.board} enemy />
          </div>
          <div className="battle-log">
            <div className="battle-log__heading"><span>战斗日志</span><small>EVENT STREAM</small></div>
            <ol>
              {battle.log.length > 0 ? battle.log.map((line, index) => (
                <li key={`${line}-${index}`}><span>{String(index + 1).padStart(2, "0")}</span><p>{line}</p></li>
              )) : <li><span>01</span><p>战术链路已建立，等待首个行动。</p></li>}
            </ol>
          </div>
          {battle.status === "finished" ? (
            (() => {
              const resultTone = battle.winner === "player" ? "win" : battle.winner === null ? "draw" : "loss";
              const reasonLabel = battle.report.reason === "concede"
                ? battle.winner === "player" ? "敌方已投降" : "你已投降"
                : battle.report.reason === "fatigue"
                  ? "疲劳损伤结束对局"
                  : battle.report.reason === "draw"
                    ? battle.player.health <= 0 && battle.ai.health <= 0
                      ? "双方核心同时失守"
                      : "达到对局回合上限"
                    : battle.winner === "player"
                      ? "敌方核心生命归零"
                      : "我方核心生命归零";
              const resultTitle = battle.winner === "player" ? "演算胜利" : battle.winner === null ? "战术平局" : "核心失守";
              const resultMessage = busy
                ? "正在归档战报与奖励…"
                : battle.winner === "player"
                  ? "获得 60 金币，任务进度已更新。"
                  : battle.winner === null
                    ? "本场没有胜负，战术日志已保留。"
                    : "获得 20 金币，战术日志已保留。";
              const coreLabel = (side: BattleSide) => `${side.health} / ${side.maxHealth}${side.armor > 0 ? ` · 护甲 ${side.armor}` : ""}`;
              const statItems = [
                { label: "使用卡牌", value: `${battle.report.cardsPlayed[0]} · ${battle.report.cardsPlayed[1]}` },
                { label: "发动攻击", value: `${battle.report.attacks[0]} · ${battle.report.attacks[1]}` },
                { label: "造成伤害", value: `${battle.report.damage[0]} · ${battle.report.damage[1]}` },
                { label: "单位阵亡", value: `${battle.report.unitsDied[0]} · ${battle.report.unitsDied[1]}` },
              ];
              return (
                <div className={`battle-result battle-result--${resultTone}`}>
                  <span className="battle-result__sigil"><Icon name={battle.winner === "player" ? "spark" : "shield"} size={30} /></span>
                  <small>SIMULATION COMPLETE · TURN {battle.turn}</small>
                  <h2>{resultTitle}</h2>
                  <p className="battle-result__reason">{reasonLabel}</p>
                  <div className="battle-result__cores" aria-label="双方核心结算">
                    <div>
                      <span>我方核心</span>
                      <strong>{coreLabel(battle.player)}</strong>
                    </div>
                    <i>VS</i>
                    <div>
                      <span>{opponentName ?? (online ? "联机对手" : "镜像演算体 K-7")}</span>
                      <strong>{coreLabel(battle.ai)}</strong>
                    </div>
                  </div>
                  <div className="battle-result__stats" aria-label="本场对局统计">
                    <span className="battle-result__stats-caption">我方 · 敌方</span>
                    {statItems.map((item) => (
                      <div key={item.label}>
                        <span>{item.label}</span>
                        <strong>{item.value}</strong>
                      </div>
                    ))}
                  </div>
                  <p>{resultMessage}</p>
                  <div className="battle-result__actions">
                    {online ? (
                      <button
                        className="button button--primary button--wide"
                        type="button"
                        disabled={pvp.role !== "host" || pvp.status === "connecting" || pvp.status === "offline"}
                        onClick={onRematch}
                      >
                        {pvp.role === "host" ? "再来一局" : "等待房主重新开始"}
                      </button>
                    ) : (
                      <button className="button button--primary button--wide" type="button" disabled={busy} onClick={onStart}>再次演算</button>
                    )}
                    <button className="button button--outline button--wide" type="button" onClick={onReturnLobby}>返回战术大厅</button>
                  </div>
                </div>
              );
            })()
          ) : effectsLocked ? (
            <div className="battle-actions battle-actions--replay">
              <span className="battle-actions__waiting">正在逐条播放战斗事件</span>
              <button className="button button--outline" type="button" onClick={onSkipEffects}>
                跳过回放
              </button>
            </div>
          ) : mulliganActive ? (
            <div className="battle-actions battle-actions--mulligan">
              <button className="button button--end-turn" type="button" disabled={!playerCanMulligan} onClick={onConfirmMulligan}>
                <span>{battle.mulliganDone ? "等待对手" : "确认起手"}</span>
                <Icon name="check" />
              </button>
            </div>
          ) : discoverActive ? (
            <div className="battle-actions battle-actions--mulligan">
              <span className="battle-actions__waiting">请选择一张候选卡牌</span>
            </div>
          ) : chooseOneActive ? (
            <div className="battle-actions battle-actions--mulligan">
              <span className="battle-actions__waiting">请选择一个战术分支</span>
            </div>
          ) : (
            <div className="battle-actions">
              <button className="button button--end-turn" type="button" disabled={!playerCanAct} onClick={onEndTurn}>
                <span>{effectsLocked ? "战况回放" : playerTurn ? "结束回合" : "等待敌方"}</span>
                <Icon name="arrow" />
              </button>
              <button className="button button--concede" type="button" disabled={!playerTurn || effectsLocked} onClick={onConcede}>
                投降
              </button>
            </div>
          )}
        </aside>
      </div>
    </section>
  );
}

function OperationsSection({
  player,
  winRate,
  isDemo,
  resetting,
  onResetDemo,
  onClaimReward,
  rewardBusy,
  onClaimWeeklyPack,
  weeklyPackBusy,
  onUpdateProfile,
  profileBusy,
  onSendFriendRequest,
  onAcceptFriendRequest,
  onSendChat,
  onBlockPlayer,
  onUnblockPlayer,
  onReportPlayer,
  socialBusy,
}: {
  player: PlayerSnapshot;
  winRate: number;
  isDemo: boolean;
  resetting: boolean;
  onResetDemo: () => void;
  onClaimReward: (level: number) => void;
  rewardBusy: boolean;
  onClaimWeeklyPack: () => void;
  weeklyPackBusy: boolean;
  onUpdateProfile: (displayName: string) => void;
  profileBusy: boolean;
  onSendFriendRequest: (friendId: string) => void;
  onAcceptFriendRequest: (friendId: string) => void;
  onSendChat: (friendId: string, text: string) => void;
  onBlockPlayer: (targetId: string) => void;
  onUnblockPlayer: (targetId: string) => void;
  onReportPlayer: (targetId: string, reason: string) => void;
  socialBusy: boolean;
}) {
  const [profileName, setProfileName] = useState(player.displayName);
  const [clockNow, setClockNow] = useState(0);
  const [friendId, setFriendId] = useState("");
  const [selectedFriendId, setSelectedFriendId] = useState<string | null>(null);
  const [chatText, setChatText] = useState("");
  const [reportReason, setReportReason] = useState("");
  const acceptedFriends = (player.friends ?? []).filter((friend) => friend.status === "accepted");
  const selectedFriend = acceptedFriends.find((friend) => friend.id === selectedFriendId) ?? null;
  const selectedBlocked = Boolean(selectedFriend && (player.blockedPlayerIds ?? []).includes(selectedFriend.id));
  const selectedMessages = selectedFriend
    ? (player.chatMessages ?? [])
      .filter((message) => (message.senderId === player.id && message.recipientId === selectedFriend.id) || (message.senderId === selectedFriend.id && message.recipientId === player.id))
      .sort((a, b) => a.createdAt.localeCompare(b.createdAt))
    : [];
  useEffect(() => {
    const tick = () => setClockNow(Date.now());
    tick();
    const timer = window.setInterval(tick, 1000);
    return () => window.clearInterval(timer);
  }, []);
  const completedTasks = player.tasks.filter((task) => task.claimed).length;
  const readyTasks = player.tasks.filter((task) => !task.claimed && task.progress >= task.target).length;
  const uniqueOwned = Object.values(player.collection).filter((count) => count > 0).length;
  const fallbackSeasonKey = new Date().toISOString().slice(0, 7);
  const rankedLadders = normalizeRankedLadders(player.rankedLadders, player.ladder, fallbackSeasonKey);
  const rewardSourceFormat = highestRankedFormat(rankedLadders);
  const ladder = rankedLadders[rewardSourceFormat];
  const ladderProgress = ladder.rankProgress
    ?? ladderProgressForRating(ladder.rating ?? LADDER_START_RATING);
  const ladderLabel = ladderLabelForProgress(ladderProgress);
  const rankedRewards = normalizeRankedRewardState(player.rankedRewards);
  const currentSeasonKey = ladder.seasonKey ?? fallbackSeasonKey;
  const seasonCardBackEarned = rankedRewards.earnedCardBackSeasons.includes(currentSeasonKey);
  const eternalScarabProgress = eternalScarabLegendProgress(rankedRewards);
  const eternalScarabEarned = eternalScarabCardBackEarned(rankedRewards);
  const projectedSeasonReward = rankedSeasonRewardForPeak(
    ladder.seasonBestProgress ?? ladderProgress,
  );
  const nextFirstTimeReward = RANKED_FIRST_TIME_REWARD_LEVELS.find(
    (level) => !rankedRewards.claimedFirstTimeFloors.includes(level.floor),
  );
  const latestSeasonChest = rankedRewards.seasonChests.at(-1) ?? null;
  const metrics = [
    { label: "累计对局", value: player.stats.matchesPlayed.toLocaleString("zh-CN"), delta: `${player.stats.wins} 胜`, icon: "swords" as IconName },
    { label: "个人胜率", value: `${winRate}%`, delta: `${player.stats.losses} 负`, icon: "user" as IconName },
    { label: "待领取任务", value: readyTasks.toString(), delta: `${completedTasks} 已领取`, icon: "check" as IconName },
    { label: "收藏完成度", value: `${Math.round((uniqueOwned / CATALOG.length) * 100)}%`, delta: `${uniqueOwned} / ${CATALOG.length}`, icon: "cards" as IconName },
  ];
  return (
    <section className="screen screen--operations" aria-labelledby="operations-title">
      <SectionHeading
        eyebrow="LIVE OPS / INTERNAL BETA"
        title="运营观测台"
        description="个人运营面板：任务、奖励、赛季和社交状态均由服务端规则结算。"
        action={<span className="live-badge"><i /> UTC 日界线倒计时 {formatUtcResetCountdown("day", clockNow)}</span>}
      />

      <div className="ops-metrics">
        {metrics.map((metric) => (
          <article className="ops-metric" key={metric.label}>
            <span className="ops-metric__icon"><Icon name={metric.icon} /></span>
            <div><small>{metric.label}</small><strong>{metric.value}</strong></div>
            <span className="ops-metric__delta">{metric.delta}</span>
          </article>
        ))}
      </div>

      <section className="panel ops-account-panel" aria-labelledby="progression-title">
        <div className="panel__header">
          <div><span className="panel__eyebrow">PLAYER PROGRESSION</span><h2 id="progression-title">账号与奖励轨道</h2></div>
          <span className="panel__counter">Lv.{player.progression?.level ?? 1}</span>
        </div>
          <div className="ops-account-grid">
          <div className="ops-account-profile"><span>公开昵称</span><label className="ops-profile-editor"><input value={profileName} maxLength={24} onChange={(event) => setProfileName(event.target.value)} aria-label="公开昵称" /><button className="button button--tiny button--accent" type="button" disabled={profileBusy || !profileName.trim()} onClick={() => onUpdateProfile(profileName)}>{profileBusy ? "保存中…" : "保存"}</button></label><small>{isDemo ? "本地演示账号" : "服务器持久化账号"}</small></div>
          <div><span>奖励经验</span><strong>{(player.progression?.xp ?? 0).toLocaleString("zh-CN")} XP</strong><small>每 1,000 XP 提升 1 级</small></div>
          <div><span>日常重随</span><strong>{player.taskCycle?.dailyRerollsRemaining ?? 0} 次</strong><small>每日 UTC 00:00 刷新</small></div>
          <div><span>卡包商店</span><strong>{player.taskCycle?.packsBoughtToday ?? 0} / 10</strong><small>100 金币 / 个，日限购 10 个</small></div>
          <div><span>传奇保底</span><strong>{Math.min(player.packPity?.packsSinceLegendary ?? 0, 39)} / 40</strong><small>第 40 包首槽必出传说，出货后重置</small></div>
          <div><span>演算奖励</span><strong>{player.taskCycle?.aiRewardsToday ?? 0} / 20</strong><small>每日最多 20 场 AI 奖励，防止刷资源</small></div>
          {(["standard", "wild"] as const).map((format) => {
            const snapshot = rankedLadders[format];
            const progress = snapshot.rankProgress ?? ladderProgressForRating(snapshot.rating);
            const label = ladderLabelForProgress(progress);
            const stars = Math.min(2, Math.max(0, snapshot.stars));
            return <div key={format}><span>{rankedFormatLabel(format)}天梯</span><strong>{label} · {label === "传说" ? "LEGEND" : `${"★".repeat(stars)}${"☆".repeat(3 - stars)}`}</strong><small>{snapshot.wins} 胜 · 星级倍率 ×{Math.min(11, Math.max(1, snapshot.starBonus))}{(snapshot.winStreak ?? 0) >= 3 && progress < LADDER_DIAMOND_FIVE_PROGRESS ? ` · ${snapshot.winStreak} 连胜` : ""} · 独立段位与隐藏水平。</small></div>;
          })}
          <div><span>赛季</span><strong>{currentSeasonKey}</strong><small>两条天梯分别重置；赛季宝箱只按两者最高成绩发放一份。</small></div>
          <div><span>玩家 UID</span><strong className="ops-player-id">{player.id}</strong><small>用于好友邀请与客服核验；资产绑定稳定身份而非邮箱</small></div>
        </div>
        <div className="ops-weekly-gift">
              <div><span className="panel__eyebrow">WEEKLY SHOP GIFT</span><strong>每周免费卡包</strong><small>每周可领取 1 次，距离 UTC 周一刷新还有 {formatUtcResetCountdown("week", clockNow)}。</small></div>
          <button className="button button--accent" type="button" disabled={weeklyPackBusy || player.taskCycle?.weeklyFreePackClaimed === true} onClick={onClaimWeeklyPack}>
            {weeklyPackBusy ? "领取中…" : player.taskCycle?.weeklyFreePackClaimed ? "本周已领取" : "领取卡包"}
          </button>
        </div>
      </section>

      <section className="panel ranked-rewards-panel" aria-labelledby="ranked-rewards-title">
        <div className="panel__header">
          <div><span className="panel__eyebrow">RANKED REWARDS</span><h2 id="ranked-rewards-title">赛季天梯奖励</h2></div>
          <span className="panel__counter">自动结算 · 防重复</span>
        </div>
        <div className="ranked-rewards-grid">
          <article className="ranked-reward-card">
            <span><Icon name="pack" size={17} />赛季宝箱</span>
            <strong>{rankedFormatLabel(rewardSourceFormat)} · {ladderLabel}</strong>
            <small>按标准与狂野中的最高段位累计：{describeRankedRewardBundle(projectedSeasonReward)}。下月首次登录只结算一份。</small>
          </article>
          <article className={`ranked-reward-card ${seasonCardBackEarned ? "is-earned" : ""}`}>
            <span><Icon name="cards" size={17} />赛季卡背</span>
            <strong>{seasonCardBackEarned ? "本赛季已解锁" : `${Math.min(5, totalRankedWins(rankedLadders))} / 5 胜`}</strong>
            <small>{seasonCardBackEarned ? `${currentSeasonKey} 卡背已永久收藏。` : "任意段位赢得 5 场 Ranked 后即时并永久解锁。"}</small>
          </article>
          <article className={`ranked-reward-card ${nextFirstTimeReward ? "" : "is-earned"}`}>
            <span><Icon name="spark" size={17} />首次段位奖励</span>
            <strong>{rankedRewards.claimedFirstTimeFloors.length} / {RANKED_FIRST_TIME_REWARD_LEVELS.length}</strong>
            <small>{nextFirstTimeReward ? `下一档 ${nextFirstTimeReward.label}：${describeRankedRewardBundle(nextFirstTimeReward.reward)}。` : "全部保护段的一次性奖励均已领取。"}</small>
          </article>
          <article className={`ranked-reward-card ${eternalScarabEarned ? "is-earned" : ""}`}>
            <span><Icon name="shield" size={17} />跨赛季传说成就</span>
            <strong>{eternalScarabEarned ? `${ETERNAL_SCARAB_CARD_BACK_NAME}已解锁` : `${eternalScarabProgress} / ${ETERNAL_SCARAB_LEGEND_SEASON_TARGET} 赛季`}</strong>
            <small>在 2026 圣甲虫之年的六个不同赛季达到传说；标准与狂野同月只计一次，历史宝箱会自动回填。</small>
          </article>
        </div>
        <div className="ranked-rewards-history">
          <span>最近赛季结算</span>
          <strong>{latestSeasonChest ? `${latestSeasonChest.seasonKey} · ${rankedFormatLabel(latestSeasonChest.sourceFormat)} · ${latestSeasonChest.peakLabel}` : "尚无已结算赛季"}</strong>
          <small>{latestSeasonChest ? describeRankedRewardBundle(latestSeasonChest) : "达到青铜 5 后，赛季结束即可获得首个奖励宝箱。"}</small>
        </div>
      </section>

      <section className="panel reward-track-panel" aria-labelledby="reward-track-title">
        <div className="panel__header">
          <div><span className="panel__eyebrow">FREE REWARD TRACK</span><h2 id="reward-track-title">奖励轨道</h2></div>
          <span className="panel__counter">{player.progression?.xp ?? 0} XP</span>
        </div>
        <div className="reward-track-list">
          {REWARD_TRACK.map((reward) => {
            const unlocked = (player.progression?.level ?? 1) >= reward.level;
            const claimed = player.rewardTrack?.claimedLevels.includes(reward.level) ?? false;
            return (
              <article className={`reward-track-item ${claimed ? "is-claimed" : unlocked ? "is-ready" : "is-locked"}`} key={reward.level}>
                <span className="reward-track-item__level">{reward.level}</span>
                <div><strong>{reward.title}</strong><small>{reward.kind === "gold" ? "金币" : reward.kind === "pack" ? "档案包" : "星尘"} × {reward.amount}</small></div>
                <button
                  className="button button--small button--accent"
                  type="button"
                  disabled={!unlocked || claimed || rewardBusy}
                  onClick={() => onClaimReward(reward.level)}
                >
                  {claimed ? "已领取" : unlocked ? "领取" : `Lv.${reward.level}`}
                </button>
              </article>
            );
          })}
        </div>
      </section>

      <section className="panel ops-rules-panel" aria-labelledby="live-rules-title">
        <div className="panel__header">
          <div><span className="panel__eyebrow">LIVE RULES</span><h2 id="live-rules-title">当前运营规则</h2></div>
          <span className="panel__counter">服务端结算</span>
        </div>
        <div className="ops-rules-list">
          <div><Icon name="check" size={16} /><span>标准卡组固定 30 张；同名普通/稀有/史诗最多 2 张，传说最多 1 张，且只能使用 1 个非中立体系。</span></div>
          <div><Icon name="check" size={16} /><span>对局使用 1–10 法力、7 个战场位、10 张手牌上限、护甲/嘲讽/奥秘/发现/抉择/疲劳与第 90 回合平局规则。</span></div>
          <div><Icon name="check" size={16} /><span>每回合行动窗口 75 秒；超时由服务端自动结束回合，PVP 客户端只提交指令，不拥有结算权。</span></div>
          <div><Icon name="check" size={16} /><span>每日 3 个日常任务，周一 UTC 00:00 刷新 1 个周常任务</span></div>
          <div><Icon name="check" size={16} /><span>日常任务仅可在未开始前重随 1 次，任务奖励领取具备幂等保护</span></div>
          <div><Icon name="check" size={16} /><span>胜利 +60 金币、失败 +20 金币；AI 每日最多 20 场发放对战金币与 XP，卡包 +50 XP</span></div>
          <div><Icon name="check" size={16} /><span>联机战报必须匹配服务器对局快照、参赛身份和唯一对局凭证</span></div>
          <div><Icon name="check" size={16} /><span>联机分为 Ranked 天梯与 Casual 休闲：仅 Ranked 影响赛季段位；白银至白金段位连续胜利会获得额外星级进度，失败会重置连胜。</span></div>
          <div><Icon name="check" size={16} /><span>每周商店提供 1 个免费卡包，按周一 UTC 00:00 刷新并由服务端幂等结算</span></div>
          <div><Icon name="check" size={16} /><span>卡包首槽保底稀有；连续 39 包未出传说时，第 40 包首槽强制传说，服务端维护计数。</span></div>
          <div><Icon name="check" size={16} /><span>好友请求每日最多 20 次，聊天每分钟最多 20 条；屏蔽、举报和好友关系由服务端保存，幂等重试不会重复发放或重复发送。</span></div>
        </div>
      </section>

      <section className="panel social-panel" aria-labelledby="social-title">
        <div className="panel__header">
          <div><span className="panel__eyebrow">BATTLETAG SOCIAL</span><h2 id="social-title">好友与社交</h2></div>
          <span className="panel__counter">{player.friends?.filter((friend) => friend.status === "accepted").length ?? 0} 位好友</span>
        </div>
        <div className="social-add-row">
          <label><span>好友 UID</span><input value={friendId} onChange={(event) => setFriendId(event.target.value)} placeholder="输入 player-…" /></label>
          <button className="button button--accent" type="button" disabled={socialBusy || !friendId.trim()} onClick={() => { onSendFriendRequest(friendId.trim()); setFriendId(""); }}>发送请求</button>
        </div>
        <div className="social-list">
          {(player.friends ?? []).length > 0 ? (player.friends ?? []).map((friend) => (
            <div className={`social-row ${friend.id === selectedFriendId ? "social-row--selected" : ""}`} key={friend.id}>
              <span className="social-row__avatar">{friend.displayName.slice(0, 1)}</span>
              <div><strong>{friend.displayName}</strong><small>{friend.id}</small></div>
              {friend.status === "accepted" ? <button className="button button--tiny button--outline social-row__open" type="button" aria-pressed={friend.id === selectedFriendId} onClick={() => setSelectedFriendId(friend.id)}>{friend.id === selectedFriendId ? "聊天中" : "聊天"}</button> : friend.direction === "incoming" ? <button className="button button--tiny button--accent" type="button" disabled={socialBusy} onClick={() => onAcceptFriendRequest(friend.id)}>接受</button> : <span className="status-pill status-pill--watch">待确认</span>}
            </div>
          )) : <p className="social-empty">还没有好友。把你的玩家 UID 分享给队友，即可发送请求。</p>}
        </div>
        {selectedFriend && (
          <div className="social-chat" aria-label={`与 ${selectedFriend.displayName} 的聊天`}>
            <div className="social-chat__header">
              <div><span className="panel__eyebrow">PRIVATE CHANNEL</span><strong>{selectedFriend.displayName}</strong><small>{selectedBlocked ? "已屏蔽：消息不会发送" : "仅限互为好友的玩家"}</small></div>
              <button className="button button--tiny button--outline" type="button" onClick={() => setSelectedFriendId(null)}>关闭</button>
            </div>
            <div className="social-chat__messages" aria-live="polite">
              {selectedMessages.length > 0 ? selectedMessages.map((message) => (
                <div className={`social-message ${message.senderId === player.id ? "social-message--self" : ""}`} key={message.id}>
                  <span>{message.text}</span><small>{formatTime(message.createdAt)}</small>
                </div>
              )) : <p className="social-empty">还没有消息。用一句话打个招呼吧。</p>}
            </div>
            <div className="social-chat__composer">
              <input value={chatText} maxLength={240} disabled={socialBusy || selectedBlocked} onChange={(event) => setChatText(event.target.value)} onKeyDown={(event) => { if (event.key === "Enter" && chatText.trim() && !selectedBlocked && !socialBusy) { onSendChat(selectedFriend.id, chatText.trim()); setChatText(""); } }} placeholder={selectedBlocked ? "解除屏蔽后才能发送" : "输入消息，回车发送"} aria-label="聊天消息" />
              <button className="button button--accent" type="button" disabled={socialBusy || selectedBlocked || !chatText.trim()} onClick={() => { onSendChat(selectedFriend.id, chatText.trim()); setChatText(""); }}>发送</button>
            </div>
            <div className="social-chat__tools">
              <button className="button button--tiny button--outline" type="button" disabled={socialBusy} onClick={() => selectedBlocked ? onUnblockPlayer(selectedFriend.id) : onBlockPlayer(selectedFriend.id)}>{selectedBlocked ? "解除屏蔽" : "屏蔽玩家"}</button>
              <label className="social-report"><span>举报原因</span><input value={reportReason} maxLength={200} disabled={socialBusy} onChange={(event) => setReportReason(event.target.value)} placeholder="辱骂、广告或作弊" /><button className="button button--tiny button--danger" type="button" disabled={socialBusy || reportReason.trim().length < 2} onClick={() => { onReportPlayer(selectedFriend.id, reportReason.trim()); setReportReason(""); }}>提交举报</button></label>
            </div>
          </div>
        )}
      </section>

      <div className="ops-grid">
        <section className="panel health-panel">
          <div className="panel__header">
            <div><span className="panel__eyebrow">MATCH HEALTH</span><h2>对局健康度</h2></div>
            <span className="panel__counter">过去 7 日</span>
          </div>
          <div className="health-chart" aria-label="过去七日对局量趋势图">
            {[52, 68, 61, 78, 72, 86, 93].map((height, index) => (
              <div className="health-chart__column" key={index}>
                <span style={{ "--chart-height": `${height}%` } as CSSProperties}><i /></span>
                <small>{["一", "二", "三", "四", "五", "六", "日"][index]}</small>
              </div>
            ))}
          </div>
          <div className="health-summary">
            <span><i className="summary-dot summary-dot--cyan" /> 完成对局 92.4%</span>
            <span><i className="summary-dot summary-dot--violet" /> 中途退出 7.6%</span>
          </div>
        </section>

        <section className="panel balance-panel">
          <div className="panel__header">
            <div><span className="panel__eyebrow">FACTION BALANCE</span><h2>阵营胜率</h2></div>
            <span className="panel__counter">目标 48–52%</span>
          </div>
          <div className="balance-ledger" aria-label="20个体系胜率">
            {FACTION_BALANCE.map((item) => (
              <div className="balance-ledger__row" key={item.faction}>
                <span className="balance-ledger__faction">
                  <i style={{ backgroundColor: item.color }} />
                  {item.faction}
                </span>
                <span className="balance-ledger__track">
                  <i
                    style={{
                      "--balance-rate": `${item.winRate}%`,
                      "--balance-color": item.color,
                    } as CSSProperties}
                  />
                </span>
                <strong>{item.winRate}%</strong>
              </div>
            ))}
          </div>
          <p className="balance-note"><Icon name="check" size={16} /> 当前阵营差值处于一期平衡阈值内</p>
        </section>
      </div>

      <section className="panel usage-panel">
        <div className="panel__header">
          <div><span className="panel__eyebrow">CARD TELEMETRY</span><h2>核心卡牌表现</h2></div>
          <span className="panel__counter">标准 AI 模式</span>
        </div>
        <div className="table-scroll">
          <table className="data-table">
            <thead><tr><th>卡牌</th><th>阵营</th><th>使用率</th><th>携带胜率</th><th>7 日趋势</th><th>状态</th></tr></thead>
            <tbody>
              {CARD_USAGE.map((card, index) => (
                <tr key={card.name}>
                  <td><span className={`table-card-icon table-card-icon--${index % 2 ? "amber" : "cyan"}`}><Icon name={index % 2 ? "swords" : "shield"} size={17} /></span><strong>{card.name}</strong></td>
                  <td>{card.faction}</td>
                  <td><span className="usage-meter"><i style={{ "--usage-width": `${card.usage}%` } as CSSProperties} /></span>{card.usage}%</td>
                  <td>{card.winRate}%</td>
                  <td className={card.trend.startsWith("+") ? "is-positive" : "is-negative"}>{card.trend}</td>
                  <td><span className={`status-pill ${Math.abs(card.winRate - 50) > 4 ? "status-pill--watch" : ""}`}>{Math.abs(card.winRate - 50) > 4 ? "观察" : "稳定"}</span></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <div className="ops-grid ops-grid--bottom">
        <RecentMatches matches={player.recentMatches} />
        <section className="panel audit-panel">
          <div className="panel__header">
            <div><span className="panel__eyebrow">LOCAL PROFILE</span><h2>当前档案摘要</h2></div>
            <span className="panel__counter">只读</span>
          </div>
          <dl className="audit-list">
            <div><dt>玩家标识</dt><dd>{player.id}</dd></div>
            <div><dt>档案邮箱</dt><dd>{player.email}</dd></div>
            <div><dt>已完成对局</dt><dd>{player.stats.matchesPlayed}</dd></div>
            <div><dt>个人胜率</dt><dd>{winRate}%</dd></div>
            <div><dt>资产更新时间</dt><dd>{formatTime(player.updatedAt)}</dd></div>
          </dl>
          <div className="audit-note"><Icon name="shield" /><p><strong>资产保护启用</strong><span>奖励、开包与卡组保存均使用幂等业务键。</span></p></div>
          {isDemo && (
            <button className="button button--outline audit-reset" type="button" disabled={resetting} onClick={onResetDemo}>
              <Icon name="clock" size={15} />
              {resetting ? "重置中…" : "重置演示档案"}
            </button>
          )}
        </section>
      </div>
    </section>
  );
}

export default GameApp;
