import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import { normalizeLegacyFlutterSave } from "./legacy-save.ts";

const ACKNOWLEDGEMENT = "I_UNDERSTAND_DEV_ONLY";

async function main(): Promise<void> {
  if (process.env.EMBER_MIGRATION_OPERATOR_ACK !== ACKNOWLEDGEMENT) {
    throw new Error("operator acknowledgement is required; this tool is for named test users only");
  }
  const inputPath = process.argv[2];
  if (!inputPath) {
    throw new Error("usage: cli.ts <local-flutter-save.json>");
  }
  const raw = await readFile(resolve(inputPath), "utf8");
  const normalized = normalizeLegacyFlutterSave(JSON.parse(raw));
  process.stdout.write(`${JSON.stringify(normalized, null, 2)}\n`);
}

void main().catch((error: unknown) => {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
});
