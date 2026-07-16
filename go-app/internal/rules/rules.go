package rules

import "strings"

type Result string

const (
	Unknown   Result = "无法识别"
	Blacklist Result = "黑名单"
	Whitelist Result = "白名单"
	Unmatched Result = "未匹配"
)

func Classify(display string, whitelist, blacklist []string) Result {
	normalized := strings.ToLower(strings.TrimSpace(display))
	if normalized == "" || normalized == "unknown" {
		return Unknown
	}
	if equalsAny(normalized, blacklist) {
		return Blacklist
	}
	if equalsAny(normalized, whitelist) {
		return Whitelist
	}
	return Unmatched
}

func Split(text string) []string {
	return strings.FieldsFunc(text, func(r rune) bool {
		return r == ';' || r == '；' || r == '\n' || r == '\r'
	})
}

func equalsAny(display string, values []string) bool {
	for _, value := range values {
		value = strings.ToLower(strings.TrimSpace(value))
		if value != "" && display == value {
			return true
		}
	}
	return false
}
