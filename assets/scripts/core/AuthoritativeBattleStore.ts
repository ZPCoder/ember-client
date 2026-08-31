export interface VersionedSnapshot {
  readonly matchId: string;
  readonly stateVersion: number;
}

export interface OrderedPvpEvent {
  readonly matchId: string;
  readonly cursor: number;
  readonly stateVersion: number;
  readonly eventId: string;
}

export type SnapshotListener<TSnapshot extends VersionedSnapshot> = (
  snapshot: Readonly<TSnapshot>,
) => void;

export type EventListener<TEvent extends OrderedPvpEvent> = (
  event: Readonly<TEvent>,
) => void;

export interface ApplyBatch<TSnapshot extends VersionedSnapshot, TEvent extends OrderedPvpEvent> {
  readonly snapshot?: Readonly<TSnapshot>;
  readonly events?: readonly Readonly<TEvent>[];
}

export interface ApplyBatchResult {
  readonly snapshotApplied: boolean;
  readonly appliedEventCount: number;
  readonly stateVersion: number;
  readonly cursor: number;
}

/**
 * Presentation cache for server-authoritative PVP.
 *
 * It cannot reduce versions, skips repeated event IDs/cursors and never exposes
 * a mutation API. A reconnect may resend an overlap; applying it is idempotent.
 */
export class AuthoritativeBattleStore<
  TSnapshot extends VersionedSnapshot,
  TEvent extends OrderedPvpEvent,
> {
  readonly #snapshotListeners = new Set<SnapshotListener<TSnapshot>>();
  readonly #eventListeners = new Set<EventListener<TEvent>>();
  readonly #seenEventIds = new Set<string>();
  #snapshot: Readonly<TSnapshot> | null = null;
  #matchId: string | null = null;
  #stateVersion = -1;
  #eventStateVersion = -1;
  #cursor = 0;

  get snapshot(): Readonly<TSnapshot> | null {
    return this.#snapshot;
  }

  get stateVersion(): number {
    return this.#stateVersion;
  }

  get cursor(): number {
    return this.#cursor;
  }

  subscribeSnapshot(listener: SnapshotListener<TSnapshot>): () => void {
    this.#snapshotListeners.add(listener);
    if (this.#snapshot) {
      listener(this.#snapshot);
    }
    return () => this.#snapshotListeners.delete(listener);
  }

  subscribeEvent(listener: EventListener<TEvent>): () => void {
    this.#eventListeners.add(listener);
    return () => this.#eventListeners.delete(listener);
  }

  applyBatch(batch: ApplyBatch<TSnapshot, TEvent>): ApplyBatchResult {
    const matchId = batch.snapshot?.matchId ?? batch.events?.[0]?.matchId;
    if (this.#matchId && matchId && this.#matchId !== matchId) {
      throw new Error("match-id-mismatch");
    }
    if (!this.#matchId && matchId) {
      this.#matchId = matchId;
    }

    const orderedEvents = [...(batch.events ?? [])].sort(
      (left, right) => left.cursor - right.cursor,
    );
    let appliedEventCount = 0;
    for (const event of orderedEvents) {
      if (matchId && event.matchId !== matchId) {
        throw new Error("event-match-id-mismatch");
      }
      if (
        event.cursor <= this.#cursor ||
        event.stateVersion < this.#stateVersion ||
        event.stateVersion < this.#eventStateVersion ||
        this.#seenEventIds.has(event.eventId)
      ) {
        continue;
      }
      this.#cursor = event.cursor;
      this.#eventStateVersion = event.stateVersion;
      this.#seenEventIds.add(event.eventId);
      for (const listener of this.#eventListeners) {
        listener(event);
      }
      appliedEventCount += 1;
    }

    let snapshotApplied = false;
    if (
      batch.snapshot &&
      batch.snapshot.stateVersion > this.#stateVersion &&
      batch.snapshot.stateVersion >= this.#eventStateVersion
    ) {
      this.#snapshot = deepFreezeClone(batch.snapshot);
      this.#stateVersion = batch.snapshot.stateVersion;
      snapshotApplied = true;
      for (const listener of this.#snapshotListeners) {
        listener(this.#snapshot);
      }
    }

    return {
      snapshotApplied,
      appliedEventCount,
      stateVersion: this.#stateVersion,
      cursor: this.#cursor,
    };
  }

  resetForMatchTransition(): void {
    this.#snapshot = null;
    this.#matchId = null;
    this.#stateVersion = -1;
    this.#eventStateVersion = -1;
    this.#cursor = 0;
    this.#seenEventIds.clear();
  }
}

function deepFreezeClone<T>(value: Readonly<T>): Readonly<T> {
  const clone = cloneValue(value) as T;
  return deepFreeze(clone);
}

function cloneValue(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(cloneValue);
  }
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>).map(([key, child]) => [key, cloneValue(child)]),
    );
  }
  return value;
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
