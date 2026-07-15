import test from "node:test";
import assert from "node:assert/strict";
import { RealCoyoteAdapter } from "../../src/core/device/realCoyoteAdapter.js";

test("real adapter sends DG-Lab Socket V2 control messages", async () => {
  const previousWebSocket = globalThis.WebSocket;
  class FakeWebSocket {
    static OPEN = 1;

    constructor() {
      this.readyState = FakeWebSocket.OPEN;
      this.sent = [];
    }

    addEventListener(event, callback) {
      if (event === "open") callback();
    }

    send(message) {
      this.sent.push(message);
    }

    close() {}
  }

  globalThis.WebSocket = FakeWebSocket;
  try {
    const adapter = new RealCoyoteAdapter({
      transport: "socket",
      endpoint: "ws://127.0.0.1:5678",
      clientId: "client-id",
      targetId: "target-id"
    });
    await adapter.connect();
    await adapter.activate({ intensityA: 12, intensityB: 24 });
    await adapter.stop();

    assert.deepEqual(adapter.ws.sent.map((message) => JSON.parse(message)), [
      { type: "msg", clientId: "client-id", targetId: "target-id", message: "strength-1+2+12" },
      { type: "msg", clientId: "client-id", targetId: "target-id", message: "strength-2+2+24" },
      { type: "msg", clientId: "client-id", targetId: "target-id", message: "clear-1" },
      { type: "msg", clientId: "client-id", targetId: "target-id", message: "clear-2" },
      { type: "msg", clientId: "client-id", targetId: "target-id", message: "strength-1+2+0" },
      { type: "msg", clientId: "client-id", targetId: "target-id", message: "strength-2+2+0" }
    ]);
  } finally {
    globalThis.WebSocket = previousWebSocket;
  }
});
