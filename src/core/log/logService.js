import { appendFile, mkdir, readFile } from "node:fs/promises";
import { dirname } from "node:path";
import { nowIso } from "../utils/time.js";
import { sanitizeLogData } from "./privacySanitizer.js";

export class LogService {
  constructor(logPath = "logs/app-dev.jsonl") {
    this.logPath = logPath;
  }

  async info(event, data = {}) {
    await this.#write("info", event, data);
  }

  async warn(event, data = {}) {
    await this.#write("warn", event, data);
  }

  async error(event, data = {}) {
    await this.#write("error", event, data);
  }

  async listRecent(limit = 20) {
    try {
      const raw = await readFile(this.logPath, "utf8");
      return raw
        .trim()
        .split(/\r?\n/)
        .filter(Boolean)
        .slice(-limit)
        .map((line) => JSON.parse(line));
    } catch (error) {
      if (error.code === "ENOENT") return [];
      throw error;
    }
  }

  async #write(level, event, data) {
    await mkdir(dirname(this.logPath), { recursive: true });
    const entry = {
      time: nowIso(),
      level,
      event,
      ...sanitizeLogData(data)
    };
    await appendFile(this.logPath, `${JSON.stringify(entry)}\n`, "utf8");
  }
}
