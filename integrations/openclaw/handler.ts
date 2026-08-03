import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

const WILHELM_ALERT_JS = "/ABSOLUTE/PATH/TO/wilhelm/bin/wilhelm-alert.js";

export default async function handler(event: { type: string; action?: string }) {
  if (event.type !== "command" || event.action !== "stop") {
    return;
  }

  try {
    await execFileAsync("node", [WILHELM_ALERT_JS, "--source", "openclaw"]);
  } catch (err) {
    console.error("[wilhelm-alert] failed:", err);
  }
}
