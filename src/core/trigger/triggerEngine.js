import { randomIntInRange } from "../utils/randomRange.js";

export class TriggerEngine {
  constructor({ config, adapter, safetyController, logService, sessionManager, clock = () => Date.now(), rng = Math.random }) {
    this.config = config;
    this.adapter = adapter;
    this.safetyController = safetyController;
    this.logService = logService;
    this.sessionManager = sessionManager;
    this.clock = clock;
    this.rng = rng;
    this.lastGlobalTriggerMs = 0;
    this.lastEventTriggerMs = new Map();
  }

  async handle(event) {
    const decision = await this.canTrigger(event);
    if (!decision.allowed) {
      await this.logService.info("trigger_skipped", { type: event.type, reason: decision.reason, rule: event.ruleName });
      return { triggered: false, reason: decision.reason };
    }

    const activation = this.safetyController.clampActivation(this.#buildActivation(event));
    await this.adapter.activate(activation);

    const now = this.clock();
    this.lastGlobalTriggerMs = now;
    this.lastEventTriggerMs.set(event.type, now);
    this.sessionManager?.markTriggered();

    await this.logService.info("triggered", {
      type: event.type,
      rule: event.ruleName,
      intensity: activation.intensity,
      durationMs: activation.durationMs
    });

    return { triggered: true, activation };
  }

  async canTrigger(event) {
    if (!this.config.enabled && event.type !== "MANUAL_TEST") {
      return { allowed: false, reason: "focus_not_enabled" };
    }
    if (this.safetyController.isLocked()) {
      return { allowed: false, reason: "safety_locked" };
    }
    const status = await this.adapter.getStatus();
    if (!status.connected) {
      return { allowed: false, reason: "device_not_connected" };
    }
    const snapshot = this.sessionManager?.getSnapshot();
    if (snapshot && snapshot.triggerCount >= this.config.maxTriggersPerSession) {
      return { allowed: false, reason: "max_triggers_reached" };
    }
    const now = this.clock();
    if (this.#secondsSince(this.lastGlobalTriggerMs, now) < this.config.cooldownSeconds) {
      return { allowed: false, reason: "global_cooldown" };
    }
    const lastEvent = this.lastEventTriggerMs.get(event.type) ?? 0;
    if (this.#secondsSince(lastEvent, now) < this.config.cooldownSeconds) {
      return { allowed: false, reason: "event_cooldown" };
    }
    return { allowed: true };
  }

  #buildActivation(event) {
    const profile = this.config.triggers[event.type] ?? this.config.triggers.MANUAL_TEST;
    return {
      intensity: randomIntInRange(profile.intensityRange, this.rng),
      durationMs: randomIntInRange(profile.durationRangeMs, this.rng),
      channel: this.config.coyote.channel,
      pattern: this.config.coyote.pattern
    };
  }

  #secondsSince(startMs, nowMs) {
    if (!startMs) return Number.POSITIVE_INFINITY;
    return Math.floor((nowMs - startMs) / 1000);
  }
}
