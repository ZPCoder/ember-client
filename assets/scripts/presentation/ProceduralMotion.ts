import { Camera, Node, Vec3, tween } from "cc";

import type {
  BattleCameraPort,
  BattleVfxName,
  BattleVfxPort,
  HeroAnimationName,
  HeroAnimationPort,
} from "./VisualPorts";

export class SharedHeroAnimator implements HeroAnimationPort {
  async play(hero: Node, animation: HeroAnimationName): Promise<void> {
    const start = hero.position.clone();
    const sequence = animation === "attack"
      ? tween(hero).by(0.12, { position: new Vec3(0, 0, 0.55) }).to(0.2, { position: start })
      : animation === "hit"
        ? tween(hero).by(0.06, { position: new Vec3(-0.12, 0, 0) }).to(0.16, { position: start })
        : animation === "victory"
          ? tween(hero).by(0.22, { position: new Vec3(0, 0.35, 0) }).to(0.3, { position: start })
          : animation === "defeat"
            ? tween(hero).by(0.4, { eulerAngles: new Vec3(0, 0, 72) })
            : tween(hero).by(0.16, { scale: new Vec3(0.05, 0.05, 0.05) })
              .by(0.16, { scale: new Vec3(-0.05, -0.05, -0.05) });
    await new Promise<void>((resolve) => sequence.call(() => resolve()).start());
  }

  stop(hero: Node): void {
    tween(hero).stop();
  }
}

export class ProceduralBattleCamera implements BattleCameraPort {
  readonly #camera: Camera;
  readonly #homePosition: Vec3;

  constructor(camera: Camera) {
    this.#camera = camera;
    this.#homePosition = camera.node.position.clone();
  }

  async establish(player: 0 | 1): Promise<void> {
    const yaw = player === 0 ? 0 : 180;
    await this.#move(this.#homePosition, new Vec3(48, yaw, 0), 0.45);
  }

  async focus(position: Readonly<Vec3>, durationSeconds = 0.25): Promise<void> {
    const target = new Vec3(position.x, Math.max(position.y + 4.2, 4.2), position.z + 5.2);
    await this.#move(target, this.#camera.node.eulerAngles, durationSeconds);
  }

  async shake(intensity: number, durationSeconds: number): Promise<void> {
    const origin = this.#camera.node.position.clone();
    await new Promise<void>((resolve) =>
      tween(this.#camera.node)
        .by(durationSeconds / 2, { position: new Vec3(intensity, 0, 0) })
        .to(durationSeconds / 2, { position: origin })
        .call(() => resolve())
        .start(),
    );
  }

  async restore(): Promise<void> {
    await this.#move(this.#homePosition, new Vec3(48, 0, 0), 0.35);
  }

  async #move(position: Readonly<Vec3>, rotation: Readonly<Vec3>, duration: number): Promise<void> {
    await new Promise<void>((resolve) =>
      tween(this.#camera.node)
        .to(duration, {
          position: new Vec3(position.x, position.y, position.z),
          eulerAngles: new Vec3(rotation.x, rotation.y, rotation.z),
        })
        .call(() => resolve())
        .start(),
    );
  }
}

export class ProceduralBattleVfx implements BattleVfxPort {
  readonly #root: Node;
  readonly #pool: Node[] = [];

  constructor(root: Node) {
    this.#root = root;
  }

  async play(name: BattleVfxName, at: Readonly<Vec3>): Promise<void> {
    const marker = this.#pool.pop() ?? new Node("PooledVfxMarker");
    marker.name = `Vfx-${name}`;
    marker.setPosition(at);
    marker.setScale(0.1, 0.1, 0.1);
    this.#root.addChild(marker);
    await new Promise<void>((resolve) =>
      tween(marker)
        .to(0.18, { scale: new Vec3(1, 1, 1) })
        .to(0.18, { scale: new Vec3(0.01, 0.01, 0.01) })
        .call(() => resolve())
        .start(),
    );
    marker.removeFromParent();
    this.#pool.push(marker);
  }

  releaseUnused(): void {
    for (const node of this.#pool.splice(0)) {
      node.destroy();
    }
  }
}
