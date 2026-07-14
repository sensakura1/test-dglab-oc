import test from "node:test";
import assert from "node:assert/strict";
import { ScopeMatcher } from "../../src/core/scope/scopeMatcher.js";

test("matches distraction before writing", () => {
  const matcher = new ScopeMatcher();
  const result = matcher.match(
    { processName: "chrome.exe", title: "OC 视频资料", url: "https://bilibili.com/video" },
    {
      pauseScope: [],
      ignoreScope: [],
      distractionScope: [{ name: "视频网站", urlKeywords: ["bilibili.com"] }],
      writingScope: [{ name: "OC 文档", titleKeywords: ["OC"] }]
    }
  );
  assert.equal(result.scope, "distraction");
  assert.equal(result.ruleName, "视频网站");
});

test("matches writing scope by process name case-insensitively", () => {
  const matcher = new ScopeMatcher();
  const result = matcher.match(
    { processName: "obsidian.exe", title: "角色设定" },
    {
      pauseScope: [],
      ignoreScope: [],
      distractionScope: [],
      writingScope: [{ name: "Obsidian", process: "Obsidian.exe" }]
    }
  );
  assert.equal(result.scope, "writing");
});
