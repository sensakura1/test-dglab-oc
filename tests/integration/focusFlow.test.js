import test from "node:test";
import assert from "node:assert/strict";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { AppController } from "../../src/main/appController.js";
import { ConfigService } from "../../src/core/config/configService.js";
import { LogService } from "../../src/core/log/logService.js";

test("app controller handles distraction flow with mock device", async () => {
  let now = 0;
  const configService = new ConfigService(join(tmpdir(), "oc-writing-focus-runtime-config.json"));
  await configService.save({
    enabled: false,
    deviceMode: "mock",
    sessionMinutes: 45,
    leaveGraceSeconds: 300,
    distractionGraceSeconds: 1,
    idleGraceSeconds: 600,
    cooldownSeconds: 0,
    maxTriggersPerSession: 5,
    maxIntensity: 60,
    maxDurationMs: 5000,
    distractionScope: [{ name: "视频网站", titleKeywords: ["视频"] }]
  });
  const app = new AppController({
    configService,
    logService: new LogService(join(tmpdir(), "oc-writing-focus-test-flow.jsonl")),
    clock: () => now
  });
  await app.init();
  await app.startFocus();
  await app.updateWindow({ processName: "chrome.exe", title: "视频" });
  now = 1500;
  const result = await app.updateWindow({ processName: "chrome.exe", title: "视频" });
  assert.equal(result.events[0].type, "DISTRACTION_DETECTED");
  assert.equal(result.results[0].triggered, true);
});
