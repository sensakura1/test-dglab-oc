package device

import (
	"fmt"
	"net"
	"net/url"
	"strings"
)

func SecureEndpoint(text, kind string) (*url.URL, error) {
	value, err := url.Parse(strings.TrimSpace(text))
	if err != nil || value.Hostname() == "" || value.User != nil || value.RawQuery != "" || value.Fragment != "" {
		return nil, fmt.Errorf("网络地址无效，且不得包含凭据、查询参数或片段")
	}
	secureScheme, plainScheme := "https", "http"
	if kind == "socket" {
		secureScheme, plainScheme = "wss", "ws"
	}
	if value.Scheme == secureScheme {
		return value, nil
	}
	if value.Scheme != plainScheme {
		return nil, fmt.Errorf("远程地址必须使用 %s", strings.ToUpper(secureScheme))
	}
	host := value.Hostname()
	if strings.EqualFold(host, "localhost") {
		return value, nil
	}
	ip := net.ParseIP(host)
	if ip == nil || !(ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast()) {
		return nil, fmt.Errorf("明文 %s 仅允许回环、私有或链路本地 IP", strings.ToUpper(plainScheme))
	}
	return value, nil
}
