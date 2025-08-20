package middleware

import (
	"net"
	"net/http"
	"strings"
)

func CIDRAllowlist(cidrs []string) func(http.Handler) http.Handler {
	var nets []*net.IPNet
	for _, c := range cidrs {
		if _, ipnet, err := net.ParseCIDR(strings.TrimSpace(c)); err == nil {
			nets = append(nets, ipnet)
		}
	}
	if len(nets) == 0 {
		return func(next http.Handler) http.Handler { return next }
	}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			host := r.RemoteAddr
			if idx := strings.LastIndex(host, ":"); idx >= 0 {
				host = host[:idx]
			}
			ip := net.ParseIP(host)
			allowed := false
			for _, n := range nets {
				if n.Contains(ip) {
					allowed = true
					break
				}
			}
			if !allowed {
				http.Error(w, "forbidden", http.StatusForbidden)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}
