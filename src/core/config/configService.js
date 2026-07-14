import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import { DEFAULT_CONFIG, SAFE_DEFAULT_CONFIG } from "./defaultConfig.js";
import { normalizeRange } from "../utils/clamp.js";

const EVENT_TYPES = [
  "FOCUS_LEFT",
  "DISTRACTION_DETECTED",
  "IDLE_TOO_LONG",
  "SESSION_TIMEOUT",
  "MANUAL_TEST"
];

export class ConfigService {
  constructor(configPath = "config/config.json") {
    this.configPath = configPath;
  }

  async load() {
    try {
      const raw = await readFile(this.configPath, "utf8");
      const parsed = JSON.parse(raw);
      const merged = this.mergeDefaults(parsed);
      const validation = this.validate(merged);
      return validation.valid ? merged : this.resetToSafeDefaults();
    } catch (error) {
      if (error.code === "ENOENT") {
        const config = this.mergeDefaults({});
        await this.save(config);
        return config;
      }
      return this.resetToSafeDefaults();
    }
  }

  async save(config) {
    const merged = this.mergeDefaults(config);
    const validation = this.validate(merged);
    if (!validation.valid) {
      const message = validation.errors.join("; ");
      throw new Error(`Invalid config: ${message}`);
    }
    await mkdir(dirname(this.configPath), { recursive: true });
    await writeFile(this.configPath, `${JSON.stringify(merged, null, 2)}\n`, "utf8");
  }

  mergeDefaults(config) {
    const merged = {
      ...DEFAULT_CONFIG,
      ...config,
      privacy: {
        ...DEFAULT_CONFIG.privacy,
        ...(config?.privacy ?? {})
      },
      coyote: {
        ...DEFAULT_CONFIG.coyote,
        ...(config?.coyote ?? {})
      },
      triggers: {
        ...DEFAULT_CONFIG.triggers,
        ...(config?.triggers ?? {})
      },
      writingScope: Array.isArray(config?.writingScope) ? config.writingScope : DEFAULT_CONFIG.writingScope,
      distractionScope: Array.isArray(config?.distractionScope) ? config.distractionScope : DEFAULT_CONFIG.distractionScope,
      ignoreScope: Array.isArray(config?.ignoreScope) ? config.ignoreScope : DEFAULT_CONFIG.ignoreScope,
      pauseScope: Array.isArray(config?.pauseScope) ? config.pauseScope : DEFAULT_CONFIG.pauseScope
    };

    for (const eventType of EVENT_TYPES) {
      const profile = merged.triggers[eventType] ?? DEFAULT_CONFIG.triggers[eventType];
      merged.triggers[eventType] = {
        intensityRange: normalizeRange(profile.intensityRange, DEFAULT_CONFIG.triggers[eventType].intensityRange, 0, merged.maxIntensity),
        durationRangeMs: normalizeRange(profile.durationRangeMs, DEFAULT_CONFIG.triggers[eventType].durationRangeMs, 1, merged.maxDurationMs)
      };
    }

    return merged;
  }

  validate(config) {
    const errors = [];
    if (!["mock", "real"].includes(config.deviceMode)) errors.push("deviceMode must be mock or real");
    if (!Number.isFinite(config.maxIntensity) || config.maxIntensity < 0 || config.maxIntensity > 100) {
      errors.push("maxIntensity must be between 0 and 100");
    }
    if (!Number.isFinite(config.maxDurationMs) || config.maxDurationMs <= 0) {
      errors.push("maxDurationMs must be greater than 0");
    }
    for (const key of ["sessionMinutes", "leaveGraceSeconds", "distractionGraceSeconds", "idleGraceSeconds", "cooldownSeconds", "maxTriggersPerSession"]) {
      if (!Number.isFinite(config[key]) || config[key] < 0) errors.push(`${key} must be a non-negative number`);
    }
    if (config.deviceMode === "real" && !config.coyote?.endpoint) {
      errors.push("real device mode requires coyote.endpoint");
    }
    return { valid: errors.length === 0, errors };
  }

  async resetToSafeDefaults() {
    const config = structuredClone(SAFE_DEFAULT_CONFIG);
    await this.save(config);
    return config;
  }
}
