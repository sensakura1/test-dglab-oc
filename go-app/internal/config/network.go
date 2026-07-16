package config

import "net"

func PreferredLocalIPv4() string {
	connections, err := net.Interfaces()
	if err != nil {
		return "127.0.0.1"
	}
	for _, connection := range connections {
		if connection.Flags&net.FlagUp == 0 || connection.Flags&net.FlagLoopback != 0 {
			continue
		}
		addresses, _ := connection.Addrs()
		for _, address := range addresses {
			ip, _, _ := net.ParseCIDR(address.String())
			if ip != nil && ip.To4() != nil && ip.IsPrivate() {
				return ip.String()
			}
		}
	}
	return "127.0.0.1"
}
