import { nowIso } from "../utils/time.js";

const STATE_EVENTS = {
  LEFT: "FOCUS_LEFT",
  DISTRACTED: "DISTRACTION_DETECTED",
  IDLE: "IDLE_TOO_LONG"
};

export class SessionManager {
  constructor(config, clock = () => Date.now()) {
    this.config = config;
    this.clock = clock;
    this.state = "STOPPED";
    this.startedAtMs = null;
    this.paused = false;
    this.scopeSinceMs = null;
    this.currentScope = "unknown";
    this.currentRuleName = undefined;
    this.firedStates = new Set();
    this.triggerCount = 0;
  }

  start() {
    this.state = "WRITING";
    this.startedAtMs = this.clock();
    this.paused = false;
    this.scopeSinceMs = this.clock();
    this.firedStates.clear();
    this.triggerCount = 0;
  }

  pause() {
    if (this.state !== "STOPPED") {
      this.paused = true;
      this.state = "PAUSED";
    }
  }

  resume() {
    if (this.state === "PAUSED") {
      this.paused = false;
      this.state = "WRITING";
      this.scopeSinceMs = this.clock();
    }
  }

  stop() {
    this.state = "STOPPED";
    this.startedAtMs = null;
    this.paused = false;
    this.scopeSinceMs = null;
    this.currentScope = "unknown";
    this.currentRuleName = undefined;
    this.firedStates.clear();
  }

  updateScope(match) {
    if (this.state === "STOPPED" || this.paused) return [];
    const nextScope = match.scope;
    if (nextScope === "pause") {
      this.pause();
      return [];
    }
    if (nextScope === "ignore") return [];

    if (nextScope !== this.currentScope || match.ruleName !== this.currentRuleName) {
      this.currentScope = nextScope;
      this.currentRuleName = match.ruleName;
      this.scopeSinceMs = this.clock();
      if (nextScope === "writing") {
        this.state = "WRITING";
        this.firedStates.delete("LEFT");
        this.firedStates.delete("DISTRACTED");
      } else if (nextScope === "distraction") {
        this.state = "DISTRACTED";
      } else {
        this.state = "LEFT";
      }
    }

    return this.#eventsForCurrentScope();
  }

  updateIdle(idleSeconds) {
    if (this.state === "STOPPED" || this.paused) return [];
    if (idleSeconds < this.config.idleGraceSeconds) {
      this.firedStates.delete("IDLE");
      return [];
    }
    if (this.firedStates.has("IDLE")) return [];
    this.firedStates.add("IDLE");
    return [this.#event("IDLE_TOO_LONG", "input", idleSeconds)];
  }

  markTriggered() {
    this.triggerCount += 1;
  }

  getSnapshot() {
    return {
      state: this.state,
      startedAtMs: this.startedAtMs,
      paused: this.paused,
      currentScope: this.currentScope,
      currentRuleName: this.currentRuleName,
      triggerCount: this.triggerCount
    };
  }

  #eventsForCurrentScope() {
    const elapsedSeconds = Math.floor((this.clock() - this.scopeSinceMs) / 1000);
    if (this.currentScope === "writing") return [];

    if (this.currentScope === "distraction") {
      if (elapsedSeconds < this.config.distractionGraceSeconds || this.firedStates.has("DISTRACTED")) return [];
      this.firedStates.add("DISTRACTED");
      return [this.#event(STATE_EVENTS.DISTRACTED, "window", elapsedSeconds)];
    }

    if (elapsedSeconds < this.config.leaveGraceSeconds || this.firedStates.has("LEFT")) return [];
    this.firedStates.add("LEFT");
    return [this.#event(STATE_EVENTS.LEFT, "window", elapsedSeconds)];
  }

  #event(type, source, elapsedSeconds) {
    return {
      type,
      source,
      occurredAt: nowIso(),
      ruleName: this.currentRuleName,
      elapsedSeconds
    };
  }
}
