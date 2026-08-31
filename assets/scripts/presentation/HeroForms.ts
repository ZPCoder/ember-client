import { Color } from "cc";

import {
  FACTION_DISPLAY_NAMES,
  FACTION_IDS,
  type HeroFormId,
} from "./FactionCatalog";

export type { FactionId, HeroFormId } from "./FactionCatalog";

export interface HeroFormDefinition {
  readonly id: HeroFormId;
  readonly displayName: string;
  readonly primary: Readonly<Color>;
  readonly secondary: Readonly<Color>;
  readonly headModule: "crown" | "crest" | "horns" | "halo" | "visor";
  readonly armorModule: "robes" | "plate" | "mantle" | "carapace";
  readonly weaponModule: "staff" | "blade" | "hammer" | "orb" | "bow";
}

const palette: readonly (readonly [number, number, number])[] = [
  [246, 211, 100], [55, 132, 166], [142, 151, 163], [239, 91, 50], [112, 82, 210],
  [71, 169, 94], [56, 183, 220], [154, 218, 239], [222, 161, 71], [175, 42, 68],
  [89, 205, 159], [94, 69, 134], [108, 190, 232], [205, 62, 160], [85, 218, 204],
  [167, 116, 224], [92, 76, 195], [212, 170, 83], [49, 124, 81], [141, 184, 230],
];

const headModules = ["crown", "crest", "horns", "halo", "visor"] as const;
const armorModules = ["robes", "plate", "mantle", "carapace"] as const;
const weaponModules = ["staff", "blade", "hammer", "orb", "bow"] as const;

export const HERO_FORMS: readonly HeroFormDefinition[] = Object.freeze([
  ...FACTION_IDS.map((id, index) => {
    const [red, green, blue] = palette[index] ?? [128, 128, 128];
    return Object.freeze({
      id,
      displayName: FACTION_DISPLAY_NAMES[index] ?? id,
      primary: new Color(red, green, blue, 255),
      secondary: new Color(
        Math.min(255, red + 36),
        Math.min(255, green + 36),
        Math.min(255, blue + 36),
        255,
      ),
      headModule: headModules[index % headModules.length] ?? "crown",
      armorModule: armorModules[index % armorModules.length] ?? "plate",
      weaponModule: weaponModules[index % weaponModules.length] ?? "staff",
    });
  }),
  Object.freeze({
    id: "hero-card-transformed" as const,
    displayName: "英雄牌变身形态",
    primary: new Color(255, 89, 34, 255),
    secondary: new Color(103, 39, 190, 255),
    headModule: "halo" as const,
    armorModule: "plate" as const,
    weaponModule: "blade" as const,
  }),
]);

export function findHeroForm(id: HeroFormId): HeroFormDefinition {
  const form = HERO_FORMS.find((candidate) => candidate.id === id);
  if (!form) {
    throw new Error(`unknown-hero-form:${id}`);
  }
  return form;
}
