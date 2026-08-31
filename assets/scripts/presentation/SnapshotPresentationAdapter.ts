import { Node, Vec3 } from "cc";

import type { PvpEventEnvelopePort, RedactedMatchSnapshotPort } from "../core/ProtocolPort";
import type { BattlePresentationPort } from "./VisualPorts";

/**
 * Vertical-slice adapter. Production adapters may animate more fields, but the
 * event queue remains presentation-only and never computes a rule outcome.
 */
export class SnapshotPresentationAdapter implements BattlePresentationPort {
  readonly #root: Node;
  readonly #eventQueue: Readonly<PvpEventEnvelopePort>[] = [];
  #renderedVersion = -1;
  #draining = false;

  constructor(root: Node) {
    this.#root = root;
  }

  presentSnapshot(snapshot: Readonly<RedactedMatchSnapshotPort>): void {
    if (snapshot.stateVersion <= this.#renderedVersion) {
      return;
    }
    this.#renderedVersion = snapshot.stateVersion;
    // Store only public presentation metadata on the node. No rule state is
    // inferred or changed by the 3D scene.
    this.#root.name = `Battlefield-v${snapshot.stateVersion}`;
    this.#root.setPosition(Vec3.ZERO);
  }

  enqueueEvent(event: Readonly<PvpEventEnvelopePort>): void {
    this.#eventQueue.push(event);
    void this.#drain();
  }

  reset(): void {
    this.#eventQueue.splice(0);
    this.#renderedVersion = -1;
  }

  async #drain(): Promise<void> {
    if (this.#draining) {
      return;
    }
    this.#draining = true;
    // A production presenter dispatches to shared animation/camera/VFX ports.
    // Yielding keeps the queue ordered while letting the renderer draw.
    try {
      while (this.#eventQueue.length > 0) {
        this.#eventQueue.shift();
        await Promise.resolve();
      }
    } finally {
      this.#draining = false;
    }
  }
}
