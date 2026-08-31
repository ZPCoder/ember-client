import { _decorator, Component } from "cc";

import { AuthoritativeBattleStore } from "../core/AuthoritativeBattleStore";
import type {
  BattleCommandPort,
  CommandSink,
  PvpEventEnvelopePort,
  RedactedMatchSnapshotPort,
} from "../core/ProtocolPort";
import type { BattlePresentationPort } from "./VisualPorts";

const { ccclass } = _decorator;

@ccclass("AuthoritativeBattleView")
export class AuthoritativeBattleView extends Component {
  readonly #store = new AuthoritativeBattleStore<
    RedactedMatchSnapshotPort,
    PvpEventEnvelopePort
  >();
  #commandSink: CommandSink | null = null;
  #presentation: BattlePresentationPort | null = null;
  #unsubscribeSnapshot: (() => void) | null = null;
  #unsubscribeEvent: (() => void) | null = null;

  bind(commandSink: CommandSink, presentation: BattlePresentationPort): void {
    this.unbind();
    this.#commandSink = commandSink;
    this.#presentation = presentation;
    this.#unsubscribeSnapshot = this.#store.subscribeSnapshot((snapshot) => {
      presentation.presentSnapshot(snapshot);
    });
    this.#unsubscribeEvent = this.#store.subscribeEvent((event) => {
      presentation.enqueueEvent(event);
    });
  }

  /** Network adapters are the only callers allowed to apply formal PVP state. */
  receiveAuthoritativeBatch(
    snapshot: Readonly<RedactedMatchSnapshotPort> | undefined,
    events: readonly Readonly<PvpEventEnvelopePort>[],
  ): void {
    this.#store.applyBatch({ snapshot, events });
  }

  /** UI gestures only emit a protocol command; no snapshot or assets mutate here. */
  async submitPlayerCommand(command: Readonly<BattleCommandPort>): Promise<void> {
    if (!this.#commandSink) {
      throw new Error("battle-command-sink-not-bound");
    }
    await this.#commandSink.send(Object.freeze({ ...command }));
  }

  transitionToMatch(): void {
    this.#store.resetForMatchTransition();
    this.#presentation?.reset();
  }

  unbind(): void {
    this.#unsubscribeSnapshot?.();
    this.#unsubscribeEvent?.();
    this.#unsubscribeSnapshot = null;
    this.#unsubscribeEvent = null;
    this.#commandSink = null;
    this.#presentation = null;
  }

  protected override onDestroy(): void {
    this.unbind();
  }
}
