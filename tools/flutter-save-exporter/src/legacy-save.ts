export type RankedFormat = "standard" | "wild";

export interface LegacyDeckV1 {
  readonly slot: number;
  readonly name: string;
  readonly format: RankedFormat;
  readonly cardIds: readonly string[];
  readonly deckCode?: string;
}

export interface LegacyFlutterSaveV1 {
  /** Must remain structurally compatible with the generated protocol type. */
  readonly schemaVersion: 1;
  readonly commanderName: string;
  readonly collection: Readonly<Record<string, number>>;
  readonly gold: number;
  readonly dust: number;
  readonly packs: Readonly<Record<string, number>>;
  readonly decks: readonly LegacyDeckV1[];
  readonly format: RankedFormat;
  readonly record: {
    readonly wins: number;
    readonly losses: number;
    readonly draws: number;
  };
}

const MAX_DURABLE_ASSET = 1_000_000_000;
const MAX_COLLECTION_QUANTITY = 999;
const MAX_PACK_QUANTITY = 1_000_000;
const MAX_DECK_SLOTS = 27;
const MAX_CARDS_PER_DECK = 60;

export function normalizeLegacyFlutterSave(input: unknown): LegacyFlutterSaveV1 {
  const source = expectRecord(input, "save");
  const commanderName = expectTrimmedString(
    source.commanderName ?? source.commander_name ?? source.playerName,
    "commanderName",
    64,
  );
  const collection = normalizeAssetMap(source.collection, "collection", 1_000, MAX_COLLECTION_QUANTITY);
  const packs = normalizeAssetMap(source.packs ?? source.cardPacks ?? {}, "packs", 100, MAX_PACK_QUANTITY);
  const decks = normalizeDecks(source.decks ?? source.deckSlots ?? []);
  const recordSource = expectRecord(source.record ?? source.stats ?? {}, "record");

  return deepFreeze({
    schemaVersion: 1,
    commanderName,
    collection,
    gold: expectNonNegativeInteger(source.gold ?? source.coins ?? 0, "gold"),
    dust: expectNonNegativeInteger(source.dust ?? source.arcaneDust ?? 0, "dust"),
    packs,
    decks,
    format: normalizeFormat(source.format ?? source.selectedFormat ?? "standard"),
    record: {
      wins: expectNonNegativeInteger(recordSource.wins ?? 0, "record.wins"),
      losses: expectNonNegativeInteger(recordSource.losses ?? 0, "record.losses"),
      draws: expectNonNegativeInteger(recordSource.draws ?? 0, "record.draws"),
    },
  });
}

function normalizeDecks(input: unknown): readonly LegacyDeckV1[] {
  if (!Array.isArray(input) || input.length > MAX_DECK_SLOTS) {
    throw new Error("decks must be an array with at most 27 entries");
  }
  const usedSlots = new Set<number>();
  return input.map((raw, index) => {
    const source = expectRecord(raw, `decks[${index}]`);
    const slot = expectNonNegativeInteger(source.slot ?? index, `decks[${index}].slot`);
    if (slot >= MAX_DECK_SLOTS || usedSlots.has(slot)) {
      throw new Error(`decks[${index}].slot must be unique and between 0 and 26`);
    }
    usedSlots.add(slot);
    if (!Array.isArray(source.cardIds) || source.cardIds.length > MAX_CARDS_PER_DECK) {
      throw new Error(`decks[${index}].cardIds must contain at most 60 cards`);
    }
    const cardIds = source.cardIds.map((cardId, cardIndex) =>
      expectTrimmedString(cardId, `decks[${index}].cardIds[${cardIndex}]`, 128),
    );
    const deckCode = source.deckCode === undefined
      ? undefined
      : expectTrimmedString(source.deckCode, `decks[${index}].deckCode`, 8192);
    return deepFreeze({
      slot,
      name: expectTrimmedString(source.name ?? `Deck ${slot + 1}`, `decks[${index}].name`, 64),
      format: normalizeFormat(source.format ?? "standard"),
      cardIds,
      ...(deckCode ? { deckCode } : {}),
    });
  });
}

function normalizeAssetMap(
  input: unknown,
  field: string,
  maxKeys: number,
  maxValue: number,
): Readonly<Record<string, number>> {
  const source = expectRecord(input ?? {}, field);
  const entries = Object.entries(source);
  if (entries.length > maxKeys) {
    throw new Error(`${field} contains too many entries`);
  }
  const normalized: Record<string, number> = {};
  for (const [rawId, rawAmount] of entries) {
    const id = expectTrimmedString(rawId, `${field}.id`, 128);
    normalized[id] = expectNonNegativeInteger(rawAmount, `${field}.${id}`, maxValue);
  }
  return deepFreeze(normalized);
}

function normalizeFormat(input: unknown): RankedFormat {
  if (input !== "standard" && input !== "wild") {
    throw new Error("format must be standard or wild");
  }
  return input;
}

function expectRecord(input: unknown, field: string): Record<string, unknown> {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new Error(`${field} must be an object`);
  }
  return input as Record<string, unknown>;
}

function expectTrimmedString(input: unknown, field: string, maxLength: number): string {
  if (typeof input !== "string" || !input.trim() || input.length > maxLength) {
    throw new Error(`${field} must be a non-empty string up to ${maxLength} characters`);
  }
  return input.trim();
}

function expectNonNegativeInteger(
  input: unknown,
  field: string,
  maximum = MAX_DURABLE_ASSET,
): number {
  if (
    typeof input !== "number" ||
    !Number.isSafeInteger(input) ||
    input < 0 ||
    input > maximum
  ) {
    throw new Error(`${field} must be a non-negative safe integer no greater than ${maximum}`);
  }
  return input;
}

function deepFreeze<T>(value: T): Readonly<T> {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const child of Object.values(value as Record<string, unknown>)) {
      deepFreeze(child);
    }
  }
  return value;
}
