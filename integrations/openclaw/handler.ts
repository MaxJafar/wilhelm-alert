import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

const WILHELM_ALERT_BIN = "/ABSOLUTE/PATH/TO/wilhelm/bin/wilhelm-alert";

export default async function handler(event: { type: string; action?: string }) {
  if (event.type !== "command" || event.action !== "stop") {
    return;
  }

  try {
    await execFileAsync(WILHELM_ALERT_BIN);
  } catch (err) {
    console.error("[wilhelm-alert] failed:", err);
  }
}
