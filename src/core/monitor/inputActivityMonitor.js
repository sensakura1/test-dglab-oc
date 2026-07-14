export class InputActivityMonitor {
  constructor(clock = () => Date.now()) {
    this.clock = clock;
    this.running = false;
    this.lastActivityMs = this.clock();
  }

  start() {
    this.running = true;
    this.lastActivityMs = this.clock();
  }

  stop() {
    this.running = false;
  }

  markActivity() {
    if (this.running) this.lastActivityMs = this.clock();
  }

  getIdleSeconds() {
    if (!this.running) return 0;
    return Math.floor((this.clock() - this.lastActivityMs) / 1000);
  }
}
