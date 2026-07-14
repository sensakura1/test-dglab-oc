import { ConfigService } from "../core/config/configService.js";
import { createCoyoteAdapter } from "../core/device/coyoteAdapter.js";
import { LogService } from "../core/log/logService.js";
import { InputActivityMonitor } from "../core/monitor/inputActivityMonitor.js";
import { ManualWindowMonitor } from "../core/monitor/windowMonitor.js";
import { SafetyController } from "../core/safety/safetyController.js";
import { ScopeMatcher } from "../core/scope/scopeMatcher.js";
import { SessionManager } from "../core/session/sessionManager.js";
import { TriggerEngine } from "../core/trigger/triggerEngine.js";
import { nowIso } from "../core/utils/time.js";

export class AppController {
  constructor(options = {}) {
    this.configService = options.configService ?? new ConfigService(options.configPath);
    this.logService = options.logService ?? new LogService(options.logPath);
    this.scopeMatcher = options.scopeMatcher ?? new ScopeMatcher();
    this.windowMonitor = options.windowMonitor ?? new ManualWindowMonitor();
    this.inputMonitor = options.inputMonitor ?? new InputActivityMonitor(options.clock);
    this.clock = options.clock ?? (() => Date.now());
    this.config = null;
    this.adapter = null;
    this.safetyController = null;
    this.sessionManager = null;
    this.triggerEngine = null;
  }

  async init() {
    this.config = await this.configService.load();
    this.adapter = createCoyoteAdapter(this.config);
    this.safetyController = new SafetyController(this.config, this.adapter);
    this.sessionManager = new SessionManager(this.config, this.clock);
    this.triggerEngine = new TriggerEngine({
      config: this.config,
      adapter: this.adapter,
      safetyController: this.safetyController,
      logService: this.logService,
      sessionManager: this.sessionManager,
      clock: this.clock
    });
    await this.adapter.connect();
    await this.logService.info("app_initialized", { deviceMode: this.config.deviceMode });
  }

  async startFocus() {
    this.config.enabled = true;
    this.sessionManager.start();
    this.inputMonitor.start();
    await this.logService.info("focus_started");
  }

  async pauseFocus() {
    this.sessionManager.pause();
    await this.logService.info("focus_paused");
  }

  async stopFocus() {
    this.sessionManager.stop();
    this.inputMonitor.stop();
    await this.logService.info("focus_stopped");
  }

  async updateWindow(info) {
    this.windowMonitor.setCurrentWindow(info);
    const match = this.scopeMatcher.match(await this.windowMonitor.getCurrentWindow(), this.config);
    const events = this.sessionManager.updateScope(match);
    const results = [];
    for (const event of events) {
      results.push(await this.triggerEngine.handle(event));
    }
    return { match, events, results };
  }

  async updateIdle() {
    const events = this.sessionManager.updateIdle(this.inputMonitor.getIdleSeconds());
    const results = [];
    for (const event of events) {
      results.push(await this.triggerEngine.handle(event));
    }
    return { events, results };
  }

  markInputActivity() {
    this.inputMonitor.markActivity();
  }

  async manualTest(type = "MANUAL_TEST") {
    return this.triggerEngine.handle({
      type,
      source: "manual",
      occurredAt: nowIso()
    });
  }

  async emergencyStop() {
    await this.safetyController.emergencyStop();
    await this.logService.warn("emergency_stop");
  }

  getSnapshot() {
    return {
      config: this.config,
      session: this.sessionManager.getSnapshot(),
      safetyLocked: this.safetyController.isLocked()
    };
  }
}
