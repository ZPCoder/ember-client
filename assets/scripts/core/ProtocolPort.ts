/**
 * The smallest structural surface the renderer consumes.
 *
 * This is intentionally not a copy of the generated protocol schema. The
 * compatibility pipeline asserts that @zpcoder/ember-protocol's generated
 * BattleCommand, RedactedMatchSnapshot and PvpEventEnvelope satisfy these
 * consumer ports before recording a release tuple.
 */
export type PlayerId = 0 | 1;

export type JsonPrimitive = string | number | boolean | null;
export type JsonValue =
  | JsonPrimitive
  | readonly JsonValue[]
  | { readonly [key: string]: JsonValue };

export interface BattleCommandPort {
  readonly type: string;
  readonly player: PlayerId;
  readonly commandId?: string;
  readonly expectedVersion?: number;
  readonly [key: string]: JsonValue | undefined;
}

export interface RedactedMatchSnapshotPort {
  readonly protocolVersion: string;
  readonly matchId: string;
  readonly stateVersion: number;
  readonly viewer: PlayerId;
  readonly state: Readonly<Record<string, JsonValue>>;
}

export interface PvpEventEnvelopePort {
  readonly protocolVersion: string;
  readonly matchId: string;
  readonly cursor: number;
  readonly stateVersion: number;
  readonly eventId: string;
  readonly event: Readonly<Record<string, JsonValue>>;
}

export interface CommandSink<TCommand extends BattleCommandPort = BattleCommandPort> {
  send(command: Readonly<TCommand>): Promise<void>;
}
