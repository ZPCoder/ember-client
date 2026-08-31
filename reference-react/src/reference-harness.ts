export interface ReferenceFixture {
  readonly seed: string | number;
  readonly commands: readonly Readonly<Record<string, unknown>>[];
  readonly snapshot: Readonly<Record<string, unknown>>;
  readonly events: readonly Readonly<Record<string, unknown>>[];
}

export interface ReferenceResult {
  readonly commandCount: number;
  readonly finalStateHash: string;
}

export function evaluateReferenceFixture(fixture: Readonly<ReferenceFixture>): ReferenceResult {
  return Object.freeze({
    commandCount: fixture.commands.length,
    finalStateHash: fnv1a64(stableStringify({
      seed: fixture.seed,
      commands: fixture.commands,
      snapshot: fixture.snapshot,
      events: fixture.events,
    })),
  });
}

export function stableStringify(value: unknown): string {
  if (value === null || typeof value !== "object") {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map(stableStringify).join(",")}]`;
  }
  const record = value as Record<string, unknown>;
  return `{${Object.keys(record)
    .sort()
    .map((key) => `${JSON.stringify(key)}:${stableStringify(record[key])}`)
    .join(",")}}`;
}

function fnv1a64(value: string): string {
  let hash = 0xcbf29ce484222325n;
  const prime = 0x100000001b3n;
  for (const byte of new TextEncoder().encode(value)) {
    hash ^= BigInt(byte);
    hash = BigInt.asUintN(64, hash * prime);
  }
  return hash.toString(16).padStart(16, "0");
}
