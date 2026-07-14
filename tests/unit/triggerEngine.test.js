import test from "node:test";
import assert from "node:assert/strict";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { MockCoyoteAdapter } from "../../src/core/device/mockCoyoteAdapter.js";
import { LogService } from "../../src/core/log/logService.js";
import { SafetyController } from "../../src/core/safety/safetyController.js";
import { TriggerEngine } from "../../src/core/trigger/triggerEngine.js";

test("trigger engine clamps activation and calls device", async () => {
  const config = {
    enabled: true,
    cooldownSeconds: 10,
    maxTriggersPerSession: 5,
    maxIntensity: 30,
    maxDurationMs: 1000,
    coyote: { channel: "both", pattern: "constant" },
    triggers: {
      MANUAL_TEST: {
        intensityRange: [80, 80],
        durationRangeMs: [5000, 5000]
      }
    }
  };
  const adapter = new MockCoyoteAdapter();
  await adapter.connect();
  const safetyController = new SafetyController(config, adapter);
  const logService = new LogService(join(tmpdir(), "oc-writing-focus-test-trigger.jsonl"));
  const sessionManager = {
    markTriggered() {},
    getSnapshot() {
      return { triggerCount: 0 };
    }
  };
  const engine = new TriggerEngine({
    config,
    adapter,
    safetyController,
    logService,
    sessionManager,
    rng: () => 0
  });

  const result = await engine.handle({ type: "MANUAL_TEST", source: "manual" });
  assert.equal(result.triggered, true);
  assert.equal(result.activation.intensity, 30);
  assert.equal(result.activation.durationMs, 1000);
  assert.equal(adapter.calls.length, 1);
});
