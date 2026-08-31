export const FACTION_IDS = [
  "radiance",
  "undertide",
  "neutral",
  "ember",
  "astral",
  "verdant",
  "stormforge",
  "frost",
  "sandsea",
  "bloodmoon",
  "leyline",
  "dusk",
  "cloudfall",
  "magnet",
  "crystal",
  "dream",
  "rift",
  "timesand",
  "gloomwood",
  "firmament",
] as const;

export type FactionId = (typeof FACTION_IDS)[number];
export type HeroFormId = FactionId | "hero-card-transformed";

export const HERO_FORM_IDS: readonly HeroFormId[] = Object.freeze([
  ...FACTION_IDS,
  "hero-card-transformed",
]);

export const FACTION_DISPLAY_NAMES = [
  "曜光", "幽潮", "中立", "烬火", "星穹", "苍林", "雷铸", "霜境", "砂海", "赤月",
  "灵脉", "暮影", "云瀑", "磁风", "晶核", "梦境", "裂星", "时砂", "幽森", "天穹",
] as const;
