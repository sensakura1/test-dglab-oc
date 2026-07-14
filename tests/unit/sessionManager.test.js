import test from "node:test";
import assert from "node:assert/strict";
import { SessionManager } from "../../src/core/session/sessionManager.js";

test("generates focus left once after grace period", () => {
  let now = 0;
  const session = new SessionManager({
    leaveGraceSeconds: 5,
    distractionGraceSeconds: 3,
    idleGraceSeconds: 10
  }, () => now);
  session.start();
  session.updateScope({ scope: "unknown" });
  now = 6000;
  const events = session.updateScope({ scope: "unknown" });
  assert.equal(events.length, 1);
  assert.equal(events[0].type, "FOCUS_LEFT");
  assert.equal(session.updateScope({ scope: "unknown" }).length, 0);
});

test("resets left state after returning to writing", () => {
  let now = 0;
  const session = new SessionManager({
    leaveGraceSeconds: 5,
    distractionGraceSeconds: 3,
    idleGraceSeconds: 10
  }, () => now);
  session.start();
  session.updateScope({ scope: "unknown" });
  now = 6000;
  assert.equal(session.updateScope({ scope: "unknown" }).length, 1);
  session.updateScope({ scope: "writing", ruleName: "OC" });
  now = 12000;
  session.updateScope({ scope: "unknown" });
  now = 18000;
  assert.equal(session.updateScope({ scope: "unknown" }).length, 1);
});
