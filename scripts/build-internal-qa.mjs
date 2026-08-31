import { spawn } from "node:child_process";

const expectedTarget = process.argv[2];
if (!new Set(["windows", "macos"]).has(expectedTarget)) {
  throw new Error("internal QA target must be windows or macos");
}
if (
  process.env.EMBER_ENVIRONMENT !== "internal-qa" ||
  process.env.EMBER_IDENTITY_PROVIDER !== "internal-qa" ||
  process.env.EMBER_PUBLIC_DISTRIBUTION !== "false"
) {
  throw new Error("internal desktop QA identity gate failed closed");
}
const executable = process.env.COCOS_CREATOR_CLI;
if (!executable) {
  throw new Error("COCOS_CREATOR_CLI must point to a licensed Cocos Creator 3.8.8 executable");
}

const platform = expectedTarget === "windows" ? "windows" : "mac";
const child = spawn(executable, [
  "--project", process.cwd(),
  "--build", `platform=${platform};debug=true;name=ember-internal-qa`,
], { stdio: "inherit", env: process.env });

child.on("exit", (code) => {
  process.exitCode = code ?? 1;
});
