export const CLIENT_BUDGETS = Object.freeze({
  creatorVersion: "3.8.8",
  browserBaseline: "webgl2",
  webGpu: "optional-enhancement",
  compressedBootBytes: 15 * 1024 * 1024,
  firstInteractionMillisecondsAt20Mbps: 8_000,
  targetFramesPerSecond: 60,
  minimumFramesPerSecond: 30,
  peakMemoryBytes: 800 * 1024 * 1024,
  referenceWidth: 1920,
  referenceHeight: 1080,
} as const);

export interface PerformanceSample {
  readonly framesPerSecond: number;
  readonly peakMemoryBytes: number;
  readonly compressedBootBytes: number;
  readonly firstInteractionMilliseconds: number;
}

export function evaluatePerformance(sample: Readonly<PerformanceSample>): readonly string[] {
  const failures: string[] = [];
  if (sample.framesPerSecond < CLIENT_BUDGETS.minimumFramesPerSecond) {
    failures.push("fps-below-hard-floor");
  }
  if (sample.peakMemoryBytes > CLIENT_BUDGETS.peakMemoryBytes) {
    failures.push("peak-memory-over-budget");
  }
  if (sample.compressedBootBytes > CLIENT_BUDGETS.compressedBootBytes) {
    failures.push("compressed-boot-over-budget");
  }
  if (
    sample.firstInteractionMilliseconds >
    CLIENT_BUDGETS.firstInteractionMillisecondsAt20Mbps
  ) {
    failures.push("first-interaction-over-budget");
  }
  return Object.freeze(failures);
}
