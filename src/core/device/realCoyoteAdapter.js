export class RealCoyoteAdapter {
  constructor(config) {
    this.config = config;
    this.connected = false;
    this.lastError = undefined;
    this.ws = null;
  }

  async connect() {
    if (this.config.transport === "http") {
      this.connected = true;
      return;
    }
    if (typeof WebSocket === "undefined") {
      throw new Error("WebSocket is not available in this Node runtime");
    }
    this.ws = new WebSocket(this.config.endpoint);
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error("WebSocket connection timeout")), 5000);
      this.ws.addEventListener("open", () => {
        clearTimeout(timeout);
        this.connected = true;
        resolve();
      }, { once: true });
      this.ws.addEventListener("error", () => {
        clearTimeout(timeout);
        reject(new Error("WebSocket connection failed"));
      }, { once: true });
    });
  }

  async disconnect() {
    if (this.ws) this.ws.close();
    this.connected = false;
  }

  async activate(options) {
    if (!this.connected) throw new Error("Coyote device is not connected");
    const payload = {
      action: "activate",
      token: this.config.pairingToken,
      ...options
    };
    await this.#send(payload);
  }

  async stop() {
    if (!this.connected) throw new Error("Coyote device is not connected");
    const payload = {
      action: "stop",
      token: this.config.pairingToken
    };
    await this.#send(payload);
  }

  async getStatus() {
    return {
      connected: this.connected,
      lastError: this.lastError
    };
  }

  async #send(payload) {
    try {
      if (this.config.transport === "http") {
        const response = await fetch(this.config.endpoint, {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify(payload)
        });
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        return;
      }
      if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
        throw new Error("WebSocket is not open");
      }
      this.ws.send(JSON.stringify(payload));
      await new Promise((resolve) => setTimeout(resolve, 100));
    } catch (error) {
      this.lastError = error.message;
      throw error;
    }
  }
}
