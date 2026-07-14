import { nowIso } from "../utils/time.js";

export class MockCoyoteAdapter {
  constructor() {
    this.connected = false;
    this.calls = [];
  }

  async connect() {
    this.connected = true;
  }

  async disconnect() {
    this.connected = false;
  }

  async activate(options) {
    if (!this.connected) throw new Error("Mock device is not connected");
    this.calls.push({
      type: "activate",
      at: nowIso(),
      options
    });
  }

  async stop() {
    this.calls.push({
      type: "stop",
      at: nowIso()
    });
  }

  async getStatus() {
    return {
      connected: this.connected,
      lastError: undefined
    };
  }
}
