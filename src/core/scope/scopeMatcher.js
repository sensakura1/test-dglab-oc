const UNKNOWN_MATCH = Object.freeze({ scope: "unknown" });

export class ScopeMatcher {
  match(info, config) {
    return (
      this.#matchRules(info, config.pauseScope, "pause") ??
      this.#matchRules(info, config.ignoreScope, "ignore") ??
      this.#matchRules(info, config.distractionScope, "distraction") ??
      this.#matchRules(info, config.writingScope, "writing") ??
      UNKNOWN_MATCH
    );
  }

  #matchRules(info, rules = [], scope) {
    for (const rule of rules) {
      if (rule?.enabled === false) continue;
      if (matchesRule(info, rule)) {
        return { scope, ruleName: rule.name };
      }
    }
    return null;
  }
}

export function matchesRule(info, rule) {
  const processMatch = rule.process ? equalsIgnoreCase(info.processName, rule.process) : false;
  const titleMatch = hasKeyword(info.title, rule.titleKeywords);
  const urlMatch = hasKeyword(info.url, rule.urlKeywords);
  return processMatch || titleMatch || urlMatch;
}

function equalsIgnoreCase(left = "", right = "") {
  return String(left).toLowerCase() === String(right).toLowerCase();
}

function hasKeyword(value, keywords) {
  if (!value || !Array.isArray(keywords) || keywords.length === 0) return false;
  const normalized = String(value).toLowerCase();
  return keywords.some((keyword) => normalized.includes(String(keyword).toLowerCase()));
}
