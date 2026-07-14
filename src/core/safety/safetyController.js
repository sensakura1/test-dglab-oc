import { clamp } from "../utils/clamp.js";

export class SafetyController {
  constructor(config, adapter = null) {
    this.config = config;
    this.adapter = adapter;
    this.locked = false;
    this.lockReason = null;
  }

  async emergencyStop() {
    this.lock("emergency_stop");
    if (this.adapter) {
      await this.adapter.stop();
    }
  }

  lock(reason = "locked") {
    this.locked = true;
    this.lockReason = reason;
  }

  unlock() {
    this.locked = false;
    this.lockReason = null;
  }

  isLocked() {
    return this.locked;
  }

  clampActivation(input) {
    return {
      ...input,
      intensity: clamp(input.intensity, 0, this.config.maxIntensity),
      durationMs: clamp(input.durationMs, 1, this.config.maxDurationMs)
    };
  }
}
