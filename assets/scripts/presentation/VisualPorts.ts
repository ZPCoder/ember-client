import type { Node, Vec3 } from "cc";

import type { PvpEventEnvelopePort, RedactedMatchSnapshotPort } from "../core/ProtocolPort";

export type HeroAnimationName =
  | "idle"
  | "hit"
  | "attack"
  | "ability"
  | "victory"
  | "defeat";

export interface HeroAnimationPort {
  play(hero: Node, animation: HeroAnimationName): Promise<void>;
  stop(hero: Node): void;
}

export interface BattleCameraPort {
  establish(player: 0 | 1): Promise<void>;
  focus(position: Readonly<Vec3>, durationSeconds?: number): Promise<void>;
  shake(intensity: number, durationSeconds: number): Promise<void>;
  restore(): Promise<void>;
}

export type BattleVfxName =
  | "card-play"
  | "attack-trail"
  | "damage"
  | "heal"
  | "death"
  | "hero-transform"
  | "victory";

export interface BattleVfxPort {
  play(name: BattleVfxName, at: Readonly<Vec3>): Promise<void>;
  releaseUnused(): void;
}

export interface BattlePresentationPort {
  presentSnapshot(snapshot: Readonly<RedactedMatchSnapshotPort>): void;
  enqueueEvent(event: Readonly<PvpEventEnvelopePort>): void;
  reset(): void;
}
