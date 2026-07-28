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
  CARD_CATALOG,
  DEFAULT_OPPONENT_DECK,
  DEFAULT_STARTER_DECK,
  applyCommand,
  battleEventsToEffects,
  createMatch,
  runAiTurn,
  validateDeck,
  type BattleEffectKind,
  type BattleCommand,
  type CardDefinition,
  type CardTargetRule,
  type MatchState,
  type BattleVisualEffect,
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

type CatalogCard = {
  id: string;
  name: string;
  cost: number;
  type: "unit" | "spell";
  faction: string;
  rarity: string;
  description: string;
  attack?: number;
  health?: number;
  target: CardTargetRule;
  keywords: string[];
};

type PlayerTask = {
  id: string;
  title: string;
  description: string;
  progress: number;
  target: number;
  rewardGold: number;
  claimed: boolean;
};

type SavedDeck = {
  id: string;
  name: string;
  cardIds: string[];
  updatedAt: string;
};

type RecentMatch = {
  id: string;
  result: "win" | "loss";
  mode: string;
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
  collection: Record<string, number>;
  decks: SavedDeck[];
  activeDeckId: string | null;
  tasks: PlayerTask[];
  recentMatches: RecentMatch[];
  stats: { wins: number; losses: number; matchesPlayed: number };
  updatedAt: string;
};

type GamePayload = {
  ok: true;
  identity?: { email: string; displayName: string; isDemo: boolean };
  player: PlayerSnapshot;
  openedCards?: Array<{ cardId: string; count: number }>;
  claimedTaskId?: string;
  rewardGold?: number;
  savedDeck?: SavedDeck;
  localFallback?: boolean;
};

type BattleUnit = {
  id: string;
  cardId: string;
  name: string;
  attack: number;
  health: number;
  maxHealth: number;
  canAttack: boolean;
};

type BattleSide = {
  health: number;
  maxHealth: number;
  mana: number;
  maxMana: number;
  deckCount: number;
  hand: Array<{ instanceId: string; cardId: string }>;
  board: BattleUnit[];
};

type BattleView = {
  status: "playing" | "finished";
  winner: "player" | "ai" | null;
  currentPlayer: "player" | "ai";
  turn: number;
  player: BattleSide;
  ai: BattleSide;
  log: string[];
};

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
  { name: "棱镜守卫", faction: "星穹", usage: 68, winRate: 54.8, trend: "+3.2%" },
  { name: "焰脊先锋", faction: "烬火", usage: 61, winRate: 52.6, trend: "+1.7%" },
  { name: "相位跃迁", faction: "星穹", usage: 49, winRate: 51.9, trend: "−0.4%" },
  { name: "熔芯过载", faction: "烬火", usage: 46, winRate: 49.3, trend: "−2.1%" },
];

const TYPE_LABEL: Record<string, string> = {
  unit: "单位",
  minion: "单位",
  spell: "战术",
};

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
    type: rawType === "spell" ? "spell" : "unit",
    faction: asString(raw.faction ?? raw.camp, "中立"),
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
    target: asString(raw.target, "none") as CardTargetRule,
    keywords: Array.isArray(raw.keywords) ? raw.keywords.map(String) : [],
  };
}

const CATALOG: CatalogCard[] = rawCatalog.map(cardFromRaw);
const CARD_BY_ID = new Map(CATALOG.map((card) => [card.id, card]));

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

function makeId(prefix: string) {
  if (typeof crypto !== "undefined" && "randomUUID" in crypto) {
    return `${prefix}-${crypto.randomUUID()}`;
  }
  return `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

function makeDemoPlayer(identity?: {
  displayName: string;
  email: string;
}): PlayerSnapshot {
  const collection = Object.fromEntries(CATALOG.map((card) => [card.id, 2]));
  const deck: SavedDeck = {
    id: "demo-starter",
    name: "星火远征队",
    cardIds: [...STARTER_IDS],
    updatedAt: new Date().toISOString(),
  };
  return {
    id: "local-commander",
    email: identity?.email ?? "commander@aether.local",
    displayName: identity?.displayName ?? "旅者 071",
    currencies: { gold: 1280, dust: 360 },
    packsAvailable: 1,
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
        claimed: false,
      },
      {
        id: "daily-play",
        title: "能量调度",
        description: "在对战中使用 8 张卡牌",
        progress: 5,
        target: 8,
        rewardGold: 80,
        claimed: false,
      },
      {
        id: "collection",
        title: "档案扩容",
        description: "收藏 24 张不同卡牌",
        progress: Math.min(CATALOG.length, 24),
        target: 24,
        rewardGold: 150,
        claimed: false,
      },
    ],
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
  if (action === "open_pack") {
    const seed = current.stats.matchesPlayed + current.packsAvailable + current.currencies.gold;
    const pulls = Array.from({ length: 5 }, (_, index) => {
      const card = CATALOG[(seed + index * 7) % Math.max(CATALOG.length, 1)];
      return card?.id ?? STARTER_IDS[index % Math.max(STARTER_IDS.length, 1)] ?? "";
    }).filter(Boolean);
    const openedMap = new Map<string, number>();
    pulls.forEach((id) => openedMap.set(id, (openedMap.get(id) ?? 0) + 1));
    const collection = { ...current.collection };
    openedMap.forEach((count, id) => {
      collection[id] = (collection[id] ?? 0) + count;
    });
    const player = {
      ...current,
      packsAvailable: Math.max(0, current.packsAvailable - 1),
      collection,
      updatedAt: now,
    };
    return {
      ok: true,
      player,
      openedCards: Array.from(openedMap, ([cardId, count]) => ({ cardId, count })),
      localFallback: true,
    };
  }

  if (action === "save_deck") {
    const deckInput = (body.deck ?? {}) as Record<string, unknown>;
    const id = asString(deckInput.id, current.activeDeckId ?? makeId("local-deck"));
    const savedDeck: SavedDeck = {
      id,
      name: asString(deckInput.name, "未命名卡组"),
      cardIds: Array.isArray(deckInput.cardIds) ? deckInput.cardIds.map(String) : [],
      updatedAt: now,
    };
    const existing = current.decks.findIndex((deck) => deck.id === id);
    const decks = [...current.decks];
    if (existing >= 0) decks[existing] = savedDeck;
    else decks.push(savedDeck);
    const player = { ...current, decks, activeDeckId: id, updatedAt: now };
    return { ok: true, player, savedDeck, localFallback: true };
  }

  if (action === "claim_task") {
    const taskId = asString(body.taskId);
    const task = current.tasks.find((item) => item.id === taskId);
    const rewardGold = task?.rewardGold ?? 0;
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
    const result = body.result === "win" ? "win" : "loss";
    const rewardGold = result === "win" ? 60 : 20;
    const match: RecentMatch = {
      id: makeId("local-match"),
      result,
      mode: asString(body.mode, "ai"),
      opponent: asString(body.opponent, "镜像演算体 K-7"),
      rewardGold,
      createdAt: now,
    };
    const tasks = current.tasks.map((task) => {
      const tracksBattle =
        task.id.includes("battle") ||
        task.description.includes("对战") ||
        task.description.includes("演算");
      return tracksBattle && !task.claimed
        ? { ...task, progress: Math.min(task.target, task.progress + 1) }
        : task;
    });
    const player = {
      ...current,
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

function normalizeHand(value: unknown): BattleSide["hand"] {
  if (!Array.isArray(value)) return [];
  return value.map((entry, index) => {
    if (typeof entry === "string") return { instanceId: `${entry}-${index}`, cardId: entry };
    const item = (entry ?? {}) as Record<string, unknown>;
    return {
      instanceId: asString(item.instanceId ?? item.uid ?? item.id, `hand-${index}`),
      cardId: asString(item.cardId ?? item.definitionId ?? item.id),
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
    const hasAttacked = Boolean(item.hasAttacked);
    const summonedTurn = asNumber(item.summonedTurn, -1);
    return {
      id: asString(item.entityId ?? item.instanceId ?? item.uid ?? item.id, `unit-${index}`),
      cardId,
      name: asString(item.name, card?.name ?? "未知单位"),
      attack: asNumber(item.attack ?? item.power, card?.attack ?? 0),
      health,
      maxHealth: asNumber(item.maxHealth, card?.health ?? health),
      canAttack:
        typeof item.canAttack === "boolean"
          ? item.canAttack
          : !hasAttacked && (summonedTurn !== turn || keywords.includes("charge")),
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
    mana: asNumber(side.mana ?? side.energy ?? side.currentMana),
    maxMana: asNumber(side.maxMana ?? side.maxEnergy, 1),
    deckCount: Array.isArray(side.deck)
      ? side.deck.length
      : asNumber(side.deckCount ?? side.remainingDeck),
    hand: normalizeHand(side.hand),
    board: normalizeBoard(side.board ?? side.units, turn),
  });
  const statusRaw = asString(raw.status ?? raw.phase, "playing").toLowerCase();
  const winnerValue = raw.winner ?? raw.winnerId;
  const winnerRaw = asString(winnerValue).toLowerCase();
  const currentValue = raw.currentPlayer ?? raw.activePlayer ?? raw.activeSide;
  const currentRaw = asString(currentValue, "player").toLowerCase();
  const events = raw.log ?? raw.logs ?? raw.events;
  const log = Array.isArray(events)
    ? events
        .slice(-12)
        .map((event) =>
          typeof event === "string"
            ? event
            : asString(
                (event as Record<string, unknown>)?.message ??
                  (event as Record<string, unknown>)?.text ??
                  (event as Record<string, unknown>)?.type,
                "战场状态已更新",
              ),
        )
    : [];
  return {
    status:
      statusRaw === "finished" ||
      statusRaw === "ended" ||
      statusRaw === "game-over" ||
      winnerValue === 0 ||
      winnerValue === 1 ||
      Boolean(winnerRaw)
        ? "finished"
        : "playing",
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
  const type = card.type === "spell" ? "spell" : "unit";
  return (
    <div className={`card-sigil card-sigil--${type}`} aria-hidden="true">
      <span className="card-sigil__orbit card-sigil__orbit--outer" />
      <span className="card-sigil__orbit card-sigil__orbit--inner" />
      <span className="card-sigil__glyph">{type === "unit" ? "◇" : "✦"}</span>
    </div>
  );
}

function CardArtwork({
  card,
  className = "",
}: {
  card: Pick<CatalogCard, "id" | "name">;
  className?: string;
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
      loading="lazy"
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
  action,
  actionLabel,
  disabled = false,
}: {
  card: CatalogCard;
  owned?: number;
  countInDeck?: number;
  compact?: boolean;
  action?: () => void;
  actionLabel?: string;
  disabled?: boolean;
}) {
  const content = (
    <>
      <div className="game-card__visual">
        <Sigil card={card} />
        <CardArtwork card={card} className="game-card__artwork" />
        <span className="game-card__cost" aria-label={`${card.cost} 点能量`}>
          {card.cost}
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
        </div>
        <h3>{card.name}</h3>
        {!compact && <p>{card.description}</p>}
        <div className="game-card__footer">
          {card.type === "unit" ? (
            <div className="game-card__stats" aria-label={`攻击 ${card.attack ?? 0}，生命 ${card.health ?? 0}`}>
              <span className="game-card__attack">⚔ {card.attack ?? 0}</span>
              <span className="game-card__health">◆ {card.health ?? 0}</span>
            </div>
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
        className={`game-card ${compact ? "game-card--compact" : ""}`}
        type="button"
        onClick={action}
        disabled={disabled}
        aria-label={actionLabel ?? card.name}
      >
        {content}
      </button>
    );
  }
  return <article className={`game-card ${compact ? "game-card--compact" : ""}`}>{content}</article>;
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
  const [isDemo, setIsDemo] = useState(!identity?.authenticated);
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
  const [deckName, setDeckName] = useState("星火远征队");
  const [deckIds, setDeckIds] = useState<string[]>(() => [...STARTER_IDS]);
  const [battle, setBattle] = useState<unknown>(null);
  const [selectedAttacker, setSelectedAttacker] = useState<string | null>(null);
  const [pendingCard, setPendingCard] = useState<BattleSide["hand"][number] | null>(null);
  const [battleMessage, setBattleMessage] = useState("准备部署你的战术卡组。");
  const [battleEffect, setBattleEffect] = useState<BattleVisualEffect | null>(null);
  const [battleEffectsLocked, setBattleEffectsLocked] = useState(false);
  const recordedBattleRef = useRef<string | null>(null);
  const sectionRef = useRef<SectionKey>("overview");
  const battleEffectQueueRef = useRef<BattleVisualEffect[]>([]);
  const battleEffectTimerRef = useRef<number | null>(null);
  const battleEffectDrainingRef = useRef(false);
  const battleEffectLockRef = useRef(false);
  const battleEffectSequenceRef = useRef(0);
  const aiTurnTimerRef = useRef<number | null>(null);
  const { soundEnabled, unlockAudio, playSound, toggleSound } = useBattleAudio();

  const stopBattleEffects = useCallback(() => {
    if (battleEffectTimerRef.current !== null) {
      window.clearTimeout(battleEffectTimerRef.current);
      battleEffectTimerRef.current = null;
    }
    battleEffectQueueRef.current = [];
    battleEffectDrainingRef.current = false;
    battleEffectLockRef.current = false;
    setBattleEffect(null);
    setBattleEffectsLocked(false);
  }, []);

  const drainBattleEffects = useCallback(() => {
    if (battleEffectDrainingRef.current) return;
    battleEffectDrainingRef.current = true;

    const playNext = () => {
      const next = battleEffectQueueRef.current.shift();
      if (!next) {
        battleEffectDrainingRef.current = false;
        battleEffectTimerRef.current = null;
        if (battleEffectLockRef.current) {
          battleEffectLockRef.current = false;
          setBattleEffectsLocked(false);
        }
        setBattleEffect(null);
        return;
      }

      setBattleEffect(next);
      playSound(next.kind);
      battleEffectTimerRef.current = window.setTimeout(playNext, 480);
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
      const maxEffects = options.maxEffects ?? 8;
      const playlist =
        effects.length <= maxEffects
          ? [...effects]
          : [
              ...effects.slice(0, Math.max(1, maxEffects - 2)),
              ...effects.slice(-2),
            ];
      const capacity = Math.max(0, 12 - battleEffectQueueRef.current.length);
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

      if (options.lock) {
        battleEffectLockRef.current = true;
        setBattleEffectsLocked(true);
      }
      drainBattleEffects();
    },
    [drainBattleEffects, stopBattleEffects],
  );

  useEffect(
    () => () => {
      if (battleEffectTimerRef.current !== null) {
        window.clearTimeout(battleEffectTimerRef.current);
      }
      if (aiTurnTimerRef.current !== null) {
        window.clearTimeout(aiTurnTimerRef.current);
      }
    },
    [],
  );

  const activeDeck = useMemo(
    () =>
      player.decks.find((deck) => deck.id === player.activeDeckId) ??
      player.decks[0] ??
      null,
    [player.activeDeckId, player.decks],
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
        setIsDemo(Boolean(payload.identity?.isDemo));
        const firstDeck =
          payload.player.decks.find((deck) => deck.id === payload.player.activeDeckId) ??
          payload.player.decks[0];
        if (firstDeck) {
          setDeckIds([...firstDeck.cardIds]);
          setDeckName(firstDeck.name);
        }
      } catch {
        if (!active) return;
        setIsDemo(true);
        setNotice({
          tone: "warning",
          text: "云端指挥链暂不可用，已切换到本地演示档案。你的本次操作不会丢失页面状态。",
        });
      } finally {
        if (active) setLoading(false);
      }
    }
    void hydrate();
    return () => {
      active = false;
    };
  }, []);

  const postAction = useCallback(
    async (
      action: string,
      body: Record<string, unknown>,
    ): Promise<GamePayload | null> => {
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
        return payload;
      } catch (error) {
        if (allowLocalFallback) {
          const localPayload = applyLocalAction(player, action, body);
          setPlayer(localPayload.player);
          setIsDemo(true);
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
    [player],
  );

  const deckCounts = useMemo(() => {
    const counts = new Map<string, number>();
    deckIds.forEach((id) => counts.set(id, (counts.get(id) ?? 0) + 1));
    return counts;
  }, [deckIds]);

  const deckValidation = useMemo(() => {
    try {
      const raw = (validateDeck as unknown as (ids: string[]) => unknown)(deckIds);
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
  }, [deckIds]);

  const factions = useMemo(
    () => ["全部", ...Array.from(new Set(CATALOG.map((card) => card.faction)))],
    [],
  );

  const filteredCards = useMemo(() => {
    const needle = search.trim().toLocaleLowerCase("zh-CN");
    return CATALOG.filter((card) => {
      const matchesSearch =
        !needle ||
        card.name.toLocaleLowerCase("zh-CN").includes(needle) ||
        card.description.toLocaleLowerCase("zh-CN").includes(needle);
      return (
        matchesSearch &&
        (factionFilter === "全部" || card.faction === factionFilter) &&
        (typeFilter === "全部" || card.type === typeFilter) &&
        (rarityFilter === "全部" || card.rarity === rarityFilter)
      );
    });
  }, [factionFilter, rarityFilter, search, typeFilter]);

  const battleView = useMemo(() => battleFromRaw(battle), [battle]);

  const switchSection = (next: SectionKey) => {
    sectionRef.current = next;
    if (next !== "battle") {
      stopBattleEffects();
    }
    setSection(next);
    setSidebarOpen(false);
  };

  const addCard = (card: CatalogCard) => {
    const owned = player.collection[card.id] ?? 0;
    const current = deckCounts.get(card.id) ?? 0;
    const limit = card.rarity === "legendary" ? 1 : 2;
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
    setDeckIds((ids) => {
      const index = ids.lastIndexOf(cardId);
      if (index < 0) return ids;
      return [...ids.slice(0, index), ...ids.slice(index + 1)];
    });
  };

  const saveDeck = async () => {
    if (!deckValidation.valid) {
      setNotice({ tone: "warning", text: deckValidation.errors[0] ?? "请先修正卡组规则错误。" });
      return;
    }
    const payload = await postAction("save_deck", {
      idempotencyKey: makeId("deck"),
      deck: {
        id: activeDeck?.id,
        name: deckName.trim() || "未命名卡组",
        cardIds: deckIds,
      },
    });
    if (payload) {
      setNotice({
        tone: payload.localFallback ? "info" : "success",
        text: payload.localFallback
          ? "云端暂不可用，卡组已保存到本地演示档案。"
          : "卡组已加密保存，可立即投入演算。",
      });
    }
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

  const startBattle = () => {
    if (!deckValidation.valid) {
      switchSection("deck");
      setNotice({ tone: "warning", text: `无法部署：${deckValidation.errors[0]}` });
      return;
    }
    try {
      if (aiTurnTimerRef.current !== null) {
        window.clearTimeout(aiTurnTimerRef.current);
        aiTurnTimerRef.current = null;
      }
      unlockAudio();
      const next = createMatch({
        decks: [[...deckIds], [...DEFAULT_OPPONENT_DECK]],
      });
      setBattle(unwrapTransition(next));
      setSelectedAttacker(null);
      setPendingCard(null);
      setBattleMessage("战术链路建立。由你先手，选择一张手牌部署。");
      recordedBattleRef.current = null;
      sectionRef.current = "battle";
      setSection("battle");
      battleEffectSequenceRef.current += 1;
      const effectId = battleEffectSequenceRef.current;
      showBattleEffects(
        [
          {
            id: `start-${effectId}`,
            kind: "start",
            side: "player",
            label: "战术链路建立",
          },
          {
            id: `turn-${effectId}`,
            kind: "turn",
            side: "player",
            targetSide: "player",
            label: "你的回合",
          },
        ],
        { reset: true },
      );
    } catch (error) {
      setNotice({
        tone: "warning",
        text: error instanceof Error ? `无法开始对战：${error.message}` : "战斗引擎暂不可用。",
      });
    }
  };

  const issueCommand = (command: BattleCommand) => {
    if (!battle) return null;
    try {
      const previous = battle as MatchState;
      const previousEventCount = previous.events.length;
      const result = applyCommand(battle as MatchState, command);
      if (!result.accepted) {
        setBattleMessage(result.error?.message ?? "该战术指令当前不可执行。");
        playSound("error");
        return null;
      }
      const next = unwrapTransition(result) as MatchState;
      setBattle(next);
      showBattleEffects(
        battleEventsToEffects(next.events.slice(previousEventCount)),
      );
      return next;
    } catch (error) {
      setBattleMessage(error instanceof Error ? error.message : "该战术指令当前不可执行。");
      playSound("error");
      return null;
    }
  };

  const playCard = (handCard: BattleSide["hand"][number]) => {
    if (battleEffectLockRef.current) {
      setBattleMessage("战况回放中，请等待行动窗口稳定。");
      return;
    }
    if (!battleView || battleView.status !== "playing" || battleView.currentPlayer !== "player") {
      setBattleMessage("当前不是你的行动窗口。");
      return;
    }
    const card = CARD_BY_ID.get(handCard.cardId);
    if (card && card.cost > battleView.player.mana) {
      setBattleMessage(`能量不足：部署「${card.name}」需要 ${card.cost} 点能量。`);
      return;
    }
    if (card && card.target !== "none") {
      setPendingCard(handCard);
      setSelectedAttacker(null);
      playSound("select");
      setBattleMessage(
        card.target.startsWith("enemy")
          ? `请选择「${card.name}」的敌方目标。`
          : card.target.startsWith("friendly")
            ? `请选择「${card.name}」的友方目标。`
            : `请选择「${card.name}」的目标。`,
      );
      return;
    }
    const next = issueCommand({
      type: "play-card",
      player: 0,
      cardId: handCard.cardId,
    });
    if (next) setBattleMessage(`已部署「${card?.name ?? "战术卡"}」。`);
  };

  const playCardAtTarget = (target: { kind: "unit" | "hero"; side: "player" | "ai"; id?: string }) => {
    if (battleEffectLockRef.current) return;
    if (!pendingCard) return;
    const card = CARD_BY_ID.get(pendingCard.cardId);
    const next = issueCommand({
      type: "play-card",
      player: 0,
      cardId: pendingCard.cardId,
      target:
        target.kind === "hero"
          ? { kind: "hero", player: target.side === "player" ? 0 : 1 }
          : { kind: "unit", entityId: target.id ?? "" },
    });
    if (next) {
      setPendingCard(null);
      setBattleMessage(`已部署「${card?.name ?? "战术卡"}」，目标效果完成结算。`);
    }
  };

  const attackTarget = (target: BattleTarget) => {
    if (battleEffectLockRef.current) return;
    if (!battleView || !selectedAttacker) return;
    const next = issueCommand({
      type: "attack",
      player: 0,
      attackerId: selectedAttacker,
      target:
        target.kind === "hero"
          ? { kind: "hero", player: 1 }
          : { kind: "unit", entityId: target.id ?? "" },
    });
    if (next) {
      setSelectedAttacker(null);
      setPendingCard(null);
      setBattleMessage(target.kind === "hero" ? "攻击已直达敌方核心。" : "单位交战已结算。");
    }
  };

  const endTurn = () => {
    if (battleEffectLockRef.current) return;
    if (!battle || !battleView || battleView.currentPlayer !== "player") return;
    if (aiTurnTimerRef.current !== null) {
      window.clearTimeout(aiTurnTimerRef.current);
      aiTurnTimerRef.current = null;
    }
    const ended = issueCommand({
      type: "end-turn",
      player: 0,
    });
    if (!ended) return;
    setSelectedAttacker(null);
    setPendingCard(null);
    setBattleMessage("演算体正在规划反制路线…");
    if ((ended as MatchState).phase === "game-over") return;

    aiTurnTimerRef.current = window.setTimeout(() => {
      aiTurnTimerRef.current = null;
      try {
        const beforeAiEvents = (ended as MatchState).events.length;
        const result = runAiTurn(ended as MatchState, 1);
        const next = unwrapTransition(result) as MatchState;
        setBattle(next);
        if (sectionRef.current === "battle") {
          showBattleEffects(
            battleEventsToEffects(next.events.slice(beforeAiEvents)),
            { lock: true, maxEffects: 5 },
          );
        }
        setBattleMessage(
          next.phase === "game-over"
            ? "敌方行动完成，正在结算演算结果。"
            : "敌方行动已结束，新的能量窗口已开启。",
        );
      } catch (error) {
        setBattleMessage(error instanceof Error ? error.message : "AI 回合演算异常。");
        playSound("error");
      }
    }, 620);
  };

  useEffect(() => {
    if (!battleView || battleView.status !== "finished" || !battleView.winner) return;
    const result = battleView.winner === "player" ? "win" : "loss";
    const key = `${battleView.turn}-${result}`;
    if (recordedBattleRef.current === key) return;
    recordedBattleRef.current = key;
    setBattleMessage(result === "win" ? "敌方核心已离线，战术演算胜利。" : "我方核心失守，演算数据已回收。");
    void postAction("record_match", {
      idempotencyKey: makeId("match"),
      result,
      mode: "ai",
      opponent: "镜像演算体 K-7",
    }).then((payload) => {
      if (payload) {
        setNotice({
          tone: payload.localFallback ? "info" : "success",
          text: `对局已${payload.localFallback ? "归入本地演示档案" : "归档"}，获得 ${result === "win" ? 60 : 20} 金币，任务进度已同步。`,
        });
      }
    });
  }, [battleView, postAction]);

  const totalOwned = Object.values(player.collection).reduce((sum, count) => sum + count, 0);
  const uniqueOwned = Object.values(player.collection).filter((count) => count > 0).length;
  const winRate =
    player.stats.matchesPlayed > 0
      ? Math.round((player.stats.wins / player.stats.matchesPlayed) * 100)
      : 0;

  return (
    <div className="game-shell">
      <a className="skip-link" href="#main-content">
        跳到主要内容
      </a>

      <aside className={`sidebar ${sidebarOpen ? "sidebar--open" : ""}`} aria-label="主导航">
        <div className="brand">
          <span className="brand__mark" aria-hidden="true">
            <span />
          </span>
          <div>
            <strong>星骸协议</strong>
            <span>ASTRA PROTOCOL</span>
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
              <strong>{isDemo ? "演示节点在线" : "云端节点在线"}</strong>
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
              <small>{isDemo ? "本地演示档案" : "已同步指挥官"}</small>
            </span>
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
                  onClaimTask={(task) => void claimTask(task)}
                  onNavigate={switchSection}
                  onStartBattle={startBattle}
                />
              )}
              {section === "collection" && (
                <CollectionSection
                  cards={filteredCards}
                  collection={player.collection}
                  deckCounts={deckCounts}
                  search={search}
                  faction={factionFilter}
                  type={typeFilter}
                  rarity={rarityFilter}
                  factions={factions}
                  onSearch={setSearch}
                  onFaction={setFactionFilter}
                  onType={setTypeFilter}
                  onRarity={setRarityFilter}
                  onAdd={addCard}
                  onOpenDeck={() => switchSection("deck")}
                />
              )}
              {section === "deck" && (
                <DeckSection
                  cards={CATALOG}
                  collection={player.collection}
                  deckIds={deckIds}
                  deckCounts={deckCounts}
                  name={deckName}
                  validation={deckValidation}
                  saving={apiBusy === "save_deck"}
                  onName={setDeckName}
                  onAdd={addCard}
                  onRemove={removeCard}
                  onSave={() => void saveDeck()}
                  onBattle={startBattle}
                />
              )}
              {section === "battle" && (
                <BattleSection
                  battle={battleView}
                  message={battleMessage}
                  effect={battleEffect}
                  selectedAttacker={selectedAttacker}
                  pendingCard={pendingCard}
                  busy={apiBusy === "record_match"}
                  effectsLocked={battleEffectsLocked}
                  soundEnabled={soundEnabled}
                  onStart={startBattle}
                  onPlayCard={playCard}
                  onSelectAttacker={(id) => {
                    setPendingCard(null);
                    setSelectedAttacker((current) => (current === id ? null : id));
                    playSound("select");
                  }}
                  onCardTarget={playCardAtTarget}
                  onCancelTarget={() => setPendingCard(null)}
                  onAttack={attackTarget}
                  onEndTurn={endTurn}
                  onOpenDeck={() => switchSection("deck")}
                  onToggleSound={toggleSound}
                />
              )}
              {section === "operations" && (
                <OperationsSection player={player} winRate={winRate} />
              )}
            </>
          )}
        </main>
      </div>
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
  onClaimTask,
  onNavigate,
  onStartBattle,
}: {
  player: PlayerSnapshot;
  winRate: number;
  uniqueOwned: number;
  totalOwned: number;
  openedCards: Array<{ cardId: string; count: number }>;
  apiBusy: string | null;
  onOpenPack: () => void;
  onClaimTask: (task: PlayerTask) => void;
  onNavigate: (section: SectionKey) => void;
  onStartBattle: () => void;
}) {
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
            <span className="pack-panel__timer"><Icon name="clock" size={15} /> 04:00 刷新</span>
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
                {match.result === "win" ? "胜" : "负"}
              </span>
              <div className="match-row__opponent">
                <span className="match-row__avatar"><Icon name="bot" /></span>
                <span><strong>{match.opponent}</strong><small>{match.mode.toUpperCase()} 演算</small></span>
              </div>
              <span className="match-row__time">{formatTime(match.createdAt)}</span>
              <span className="match-row__reward"><Icon name="coin" size={15} /> +{match.rewardGold}</span>
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
  deckCounts,
  search,
  faction,
  type,
  rarity,
  factions,
  onSearch,
  onFaction,
  onType,
  onRarity,
  onAdd,
  onOpenDeck,
}: {
  cards: CatalogCard[];
  collection: Record<string, number>;
  deckCounts: Map<string, number>;
  search: string;
  faction: string;
  type: string;
  rarity: string;
  factions: string[];
  onSearch: (value: string) => void;
  onFaction: (value: string) => void;
  onType: (value: string) => void;
  onRarity: (value: string) => void;
  onAdd: (card: CatalogCard) => void;
  onOpenDeck: () => void;
}) {
  return (
    <section className="screen screen--collection" aria-labelledby="collection-title">
      <SectionHeading
        eyebrow="TACTICAL ARCHIVE / COLLECTION"
        title="卡牌收藏"
        description="检索已解密的战术档案，按阵营、类型与稀有度筛选，并直接加入当前卡组。"
        action={
          <button className="button button--outline" type="button" onClick={onOpenDeck}>
            <Icon name="layers" />
            当前卡组 {Array.from(deckCounts.values()).reduce((sum, count) => sum + count, 0)} / 30
          </button>
        }
      />

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
      </div>

      <div className="collection-summary">
        <span><i className="summary-dot summary-dot--online" /> 显示 {cards.length} 张档案</span>
        <span>点击卡牌加入当前卡组</span>
      </div>

      {cards.length > 0 ? (
        <div className="card-grid">
          {cards.map((card) => (
            <CardTile
              key={card.id}
              card={card}
              owned={collection[card.id] ?? 0}
              countInDeck={deckCounts.get(card.id) ?? 0}
              action={() => onAdd(card)}
              actionLabel={`将${card.name}加入当前卡组`}
            />
          ))}
        </div>
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
  deckIds,
  deckCounts,
  name,
  validation,
  saving,
  onName,
  onAdd,
  onRemove,
  onSave,
  onBattle,
}: {
  cards: CatalogCard[];
  collection: Record<string, number>;
  deckIds: string[];
  deckCounts: Map<string, number>;
  name: string;
  validation: ValidationView;
  saving: boolean;
  onName: (name: string) => void;
  onAdd: (card: CatalogCard) => void;
  onRemove: (cardId: string) => void;
  onSave: () => void;
  onBattle: () => void;
}) {
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

  return (
    <section className="screen screen--deck" aria-labelledby="deck-title">
      <SectionHeading
        eyebrow="ARSENAL / DECK FORGE"
        title="卡组工坊"
        description="编排 30 张战术档案。普通卡最多 2 张，传说卡最多 1 张。"
        action={
          <div className="deck-heading-actions">
            <button className="button button--outline" type="button" disabled={saving} onClick={onSave}>
              <Icon name="check" />
              {saving ? "保存中…" : "保存卡组"}
            </button>
            <button className="button button--primary" type="button" disabled={!validation.valid} onClick={onBattle}>
              <Icon name="swords" />
              投入演算
            </button>
          </div>
        }
      />

      <div className="deck-workbench">
        <aside className="panel deck-manifest">
          <div className="deck-name-field">
            <span className="deck-name-field__sigil"><Icon name="layers" /></span>
            <label>
              <span>卡组代号</span>
              <input value={name} onChange={(event) => onName(event.target.value)} maxLength={32} />
            </label>
            <strong className={deckIds.length === 30 ? "is-complete" : ""}>{deckIds.length}<small>/30</small></strong>
          </div>

          <div className={`deck-validation ${validation.valid ? "deck-validation--valid" : "deck-validation--invalid"}`} role="status">
            <Icon name={validation.valid ? "check" : "shield"} />
            <div>
              <strong>{validation.valid ? "卡组协议有效" : "卡组尚未完成"}</strong>
              <span>{validation.valid ? "可投入 AI 战术演算" : validation.errors[0]}</span>
            </div>
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

          <div className="deck-list">
            <div className="deck-list__heading">
              <span>部署清单</span>
              <small>{uniqueDeckCards.length} 种卡牌</small>
            </div>
            {uniqueDeckCards.length > 0 ? uniqueDeckCards.map(({ card, count }) => (
              <div className="deck-entry" key={card.id}>
                <span className="deck-entry__artwork">
                  <CardArtwork card={card} />
                </span>
                <span className="deck-entry__cost">{card.cost}</span>
                <span className={`deck-entry__rarity deck-entry__rarity--${card.rarity}`} />
                <span className="deck-entry__name"><strong>{card.name}</strong><small>{card.faction} · {TYPE_LABEL[card.type]}</small></span>
                <span className="deck-entry__count">×{count}</span>
                <button type="button" onClick={() => onRemove(card.id)} aria-label={`从卡组移除一张${card.name}`}>
                  <Icon name="minus" size={16} />
                </button>
              </div>
            )) : (
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

function HeroCore({
  side,
  active,
  enemy,
  canTarget,
  onTarget,
  targetLabel,
  effect,
}: {
  side: BattleSide;
  active: boolean;
  enemy?: boolean;
  canTarget?: boolean;
  onTarget?: () => void;
  targetLabel?: string;
  effect?: BattleHeroEffect;
}) {
  const effectClass = effect ? `hero-core--${effect}` : "";
  const core = (
    <>
      <span className="hero-core__portrait"><Icon name={enemy ? "bot" : "user"} size={30} /></span>
      <span className="hero-core__copy">
        <small>{enemy ? "镜像演算体 K-7" : "远征指挥官"}</small>
        <strong>{side.health}<i> / {side.maxHealth}</i></strong>
      </span>
      <span className="hero-core__health"><Icon name="shield" size={17} /> CORE</span>
      {active && <span className="hero-core__active">行动中</span>}
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
  effect,
}: {
  unit: BattleUnit;
  selected?: boolean;
  targetable?: boolean;
  onSelect?: () => void;
  onTarget?: () => void;
  effect?: BattleUnitEffect;
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
      keywords: [],
    };
  return (
    <button
      className={`board-unit ${selected ? "board-unit--selected" : ""} ${targetable ? "board-unit--targetable" : ""} ${!unit.canAttack && onSelect ? "board-unit--exhausted" : ""} ${effect ? `board-unit--${effect}` : ""}`}
      type="button"
      onClick={targetable ? onTarget : onSelect}
      disabled={!targetable && (!onSelect || !unit.canAttack)}
      aria-pressed={onSelect ? selected : undefined}
      aria-label={`${unit.name}，攻击 ${unit.attack}，生命 ${unit.health}${targetable ? "，设为攻击目标" : unit.canAttack ? "，选择攻击" : "，本回合无法攻击"}`}
    >
      <div className="board-unit__art">
        <Sigil card={visualCard} />
        <CardArtwork card={visualCard} className="board-unit__artwork" />
      </div>
      <strong>{unit.name}</strong>
      <div className="board-unit__stats"><span>⚔ {unit.attack}</span><span>◆ {unit.health}</span></div>
      {unit.canAttack && onSelect && <span className="board-unit__ready">READY</span>}
    </button>
  );
}

function BattleEffectLayer({ effect }: { effect: BattleVisualEffect }) {
  const cardName = effect.cardId ? CARD_BY_ID.get(effect.cardId)?.name : undefined;
  const number =
    typeof effect.amount === "number" &&
    (effect.kind === "damage" || effect.kind === "heal")
      ? `${effect.kind === "damage" ? "−" : "+"}${effect.amount}`
      : null;

  return (
    <div
      className={`battlefield__fx-layer battle-fx--${effect.kind} battle-fx--${effect.targetSide ?? effect.side ?? "neutral"}`}
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
        <small>{cardName ?? "ASTRA COMBAT LINK"}</small>
        <strong>{effect.label}</strong>
      </span>
      {number && <span className="battle-fx__number">{number}</span>}
    </div>
  );
}

function BattleSection({
  battle,
  message,
  effect,
  selectedAttacker,
  pendingCard,
  busy,
  effectsLocked,
  soundEnabled,
  onStart,
  onPlayCard,
  onSelectAttacker,
  onCardTarget,
  onCancelTarget,
  onAttack,
  onEndTurn,
  onOpenDeck,
  onToggleSound,
}: {
  battle: BattleView | null;
  message: string;
  effect: BattleVisualEffect | null;
  selectedAttacker: string | null;
  pendingCard: BattleSide["hand"][number] | null;
  busy: boolean;
  effectsLocked: boolean;
  soundEnabled: boolean;
  onStart: () => void;
  onPlayCard: (card: BattleSide["hand"][number]) => void;
  onSelectAttacker: (id: string) => void;
  onCardTarget: (target: { kind: "unit" | "hero"; side: "player" | "ai"; id?: string }) => void;
  onCancelTarget: () => void;
  onAttack: (target: BattleTarget) => void;
  onEndTurn: () => void;
  onOpenDeck: () => void;
  onToggleSound: () => void;
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
            <div><span>规则版本</span><strong>CORE 0.1</strong></div>
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
        </div>
      </section>
    );
  }

  const playerTurn = battle.currentPlayer === "player" && battle.status === "playing";
  const playerCanAct = playerTurn && !effectsLocked;
  const pendingDefinition = pendingCard ? CARD_BY_ID.get(pendingCard.cardId) : undefined;
  const targetRule = pendingDefinition?.target ?? "none";
  const cardCanTarget = (side: "player" | "ai", kind: "unit" | "hero") => {
    if (!pendingDefinition) return false;
    if (targetRule === "any-character") return true;
    if (targetRule === "enemy-character") return side === "ai";
    if (targetRule === "friendly-character") return side === "player";
    if (targetRule === "enemy-unit") return side === "ai" && kind === "unit";
    if (targetRule === "friendly-unit") return side === "player" && kind === "unit";
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
  const enemyHeroTargetable = Boolean(selectedAttacker) || cardCanTarget("ai", "hero");
  const enemyUnitTargetable = Boolean(selectedAttacker) || cardCanTarget("ai", "unit");
  return (
    <section className="screen screen--battle battle-room" aria-labelledby="battle-room-title">
      <header className="battle-room__top">
        <div>
          <span className="section-heading__eyebrow">LIVE SIMULATION · TURN {battle.turn}</span>
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
          <div
            className={`turn-indicator ${
              battle.status === "finished"
                ? "turn-indicator--finished"
                : playerTurn
                  ? "turn-indicator--player"
                  : "turn-indicator--ai"
            }`}
          >
            <span />
            {battle.status === "finished" ? "演算结束" : playerTurn ? "你的回合" : "敌方回合"}
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
                active={battle.currentPlayer === "ai"}
                canTarget={enemyHeroTargetable}
                effect={effectForHero("ai")}
                onTarget={() =>
                  pendingCard
                    ? onCardTarget({ kind: "hero", side: "ai" })
                    : onAttack({ kind: "hero" })
                }
                targetLabel={
                  pendingCard
                    ? `以${pendingDefinition?.name ?? "卡牌"}选择敌方核心`
                    : "攻击敌方核心"
                }
              />
              <div className="mana-readout mana-readout--enemy" aria-label={`敌方能量 ${battle.ai.mana}/${battle.ai.maxMana}`}>
                <Icon name="spark" size={16} /><strong>{battle.ai.mana}</strong><span>/ {battle.ai.maxMana}</span>
              </div>
            </div>
            <div className="enemy-hand" aria-label={`敌方有 ${battle.ai.hand.length} 张手牌`}>
              {battle.ai.hand.map((card, index) => <span className="card-back" key={`${card.instanceId}-${index}`} />)}
              <small>{battle.ai.deckCount} 张牌库</small>
            </div>
            <div className="board-row board-row--enemy">
              {battle.ai.board.length > 0 ? battle.ai.board.map((unit) => (
                <BoardUnit
                  key={unit.id}
                  unit={unit}
                  targetable={enemyUnitTargetable}
                  effect={effectForUnit(unit.id)}
                  onTarget={() =>
                    pendingCard
                      ? onCardTarget({ kind: "unit", side: "ai", id: unit.id })
                      : onAttack({ kind: "unit", id: unit.id })
                  }
                />
              )) : <span className="board-row__empty">敌方阵地空置</span>}
            </div>
          </div>

          <div className="battlefield__divider">
            <span />
            <strong>TURN {battle.turn}</strong>
            <span />
          </div>

          <div className="battlefield__player-zone">
            <div className="board-row board-row--player">
              {battle.player.board.length > 0 ? battle.player.board.map((unit) => (
                <BoardUnit
                  key={unit.id}
                  unit={unit}
                  selected={selectedAttacker === unit.id}
                  targetable={cardCanTarget("player", "unit")}
                  effect={effectForUnit(unit.id)}
                  onSelect={pendingCard || !playerCanAct ? undefined : () => onSelectAttacker(unit.id)}
                  onTarget={() => onCardTarget({ kind: "unit", side: "player", id: unit.id })}
                />
              )) : <span className="board-row__empty">选择手牌，部署你的首个单位</span>}
            </div>
            <div className="battlefield__side-info battlefield__side-info--player">
              <HeroCore
                side={battle.player}
                active={playerTurn}
                canTarget={cardCanTarget("player", "hero")}
                effect={effectForHero("player")}
                onTarget={() => onCardTarget({ kind: "hero", side: "player" })}
                targetLabel={`以${pendingDefinition?.name ?? "卡牌"}选择我方核心`}
              />
              <div className="mana-readout" aria-label={`我方能量 ${battle.player.mana}/${battle.player.maxMana}`}>
                <Icon name="spark" size={16} /><strong>{battle.player.mana}</strong><span>/ {battle.player.maxMana}</span>
                <div className="mana-pips" aria-hidden="true">
                  {Array.from({ length: battle.player.maxMana }, (_, index) => <i className={index < battle.player.mana ? "is-filled" : ""} key={index} />)}
                </div>
              </div>
            </div>
            <div className="player-hand">
              {battle.player.hand.map((handCard) => {
                const card = CARD_BY_ID.get(handCard.cardId);
                if (!card) return null;
                const disabled = !playerCanAct || card.cost > battle.player.mana;
                return (
                  <div
                    className={`hand-card ${disabled ? "hand-card--disabled" : ""} ${pendingCard?.instanceId === handCard.instanceId ? "hand-card--selected" : ""}`}
                    key={handCard.instanceId}
                  >
                    <CardTile
                      card={card}
                      compact
                      action={() => onPlayCard(handCard)}
                      actionLabel={`使用${card.name}`}
                      disabled={disabled}
                    />
                  </div>
                );
              })}
              {battle.player.hand.length === 0 && <span className="player-hand__empty">手牌为空</span>}
            </div>
            <span className="deck-counter"><Icon name="cards" size={16} /> 牌库 {battle.player.deckCount}</span>
          </div>
        </div>

        <aside className="battle-console">
          <div className="battle-console__message" role="status">
            <span><Icon name="radar" /></span>
            <p>{message}</p>
          </div>
          {(selectedAttacker || pendingCard) && (
            <div className="target-prompt">
              <Icon name="swords" />
              <span>
                <strong>{pendingCard ? `${pendingDefinition?.name ?? "卡牌"} · 选择目标` : "目标锁定模式"}</strong>
                <small>{pendingCard ? "场上可用目标已高亮" : "选择敌方单位或核心"}</small>
              </span>
              {pendingCard && (
                <button type="button" onClick={onCancelTarget} aria-label="取消选择卡牌目标">
                  <Icon name="close" size={16} />
                </button>
              )}
            </div>
          )}
          <div className="battle-log">
            <div className="battle-log__heading"><span>战斗日志</span><small>EVENT STREAM</small></div>
            <ol>
              {battle.log.length > 0 ? battle.log.map((line, index) => (
                <li key={`${line}-${index}`}><span>{String(index + 1).padStart(2, "0")}</span><p>{line}</p></li>
              )) : <li><span>01</span><p>战术链路已建立，等待首个行动。</p></li>}
            </ol>
          </div>
          {battle.status === "finished" ? (
            <div className={`battle-result battle-result--${battle.winner === "player" ? "win" : "loss"}`}>
              <span className="battle-result__sigil"><Icon name={battle.winner === "player" ? "spark" : "shield"} size={30} /></span>
              <small>SIMULATION COMPLETE</small>
              <h2>{battle.winner === "player" ? "演算胜利" : "核心失守"}</h2>
              <p>{busy ? "正在归档战报与奖励…" : battle.winner === "player" ? "获得 60 金币，任务进度已更新。" : "获得 20 金币，战术日志已保留。"}</p>
              <button className="button button--primary button--wide" type="button" onClick={onStart}>再次演算</button>
            </div>
          ) : (
            <button className="button button--end-turn" type="button" disabled={!playerCanAct} onClick={onEndTurn}>
              <span>{effectsLocked ? "战况回放" : playerTurn ? "结束回合" : "等待敌方"}</span>
              <Icon name="arrow" />
            </button>
          )}
        </aside>
      </div>
    </section>
  );
}

function OperationsSection({ player, winRate }: { player: PlayerSnapshot; winRate: number }) {
  const metrics = [
    { label: "内测活跃指挥官", value: "486", delta: "+12.4%", icon: "user" as IconName },
    { label: "今日完成对局", value: "1,284", delta: "+8.1%", icon: "swords" as IconName },
    { label: "平均回合数", value: "8.6", delta: "−0.3", icon: "clock" as IconName },
    { label: "规则异常率", value: "0.04%", delta: "稳定", icon: "shield" as IconName },
  ];
  return (
    <section className="screen screen--operations" aria-labelledby="operations-title">
      <SectionHeading
        eyebrow="LIVE OPS / INTERNAL BETA"
        title="运营观测台"
        description="一期内测数据快照。玩家资产及对局查询为只读，敏感调整必须经补偿单审计。"
        action={<span className="live-badge"><i /> 数据每 5 分钟刷新</span>}
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
          <div className="balance-rings">
            <div className="balance-ring balance-ring--cyan"><span><strong>51.8%</strong><small>星穹</small></span></div>
            <div className="balance-ring balance-ring--amber"><span><strong>48.2%</strong><small>烬火</small></span></div>
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
            <div><dt>已完成对局</dt><dd>{player.stats.matchesPlayed}</dd></div>
            <div><dt>个人胜率</dt><dd>{winRate}%</dd></div>
            <div><dt>资产更新时间</dt><dd>{formatTime(player.updatedAt)}</dd></div>
          </dl>
          <div className="audit-note"><Icon name="shield" /><p><strong>资产保护启用</strong><span>奖励、开包与卡组保存均使用幂等业务键。</span></p></div>
        </section>
      </div>
    </section>
  );
}

export default GameApp;
