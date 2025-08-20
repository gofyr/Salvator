package middleware

import (
	"net/http"

	"github.com/gofyr/server_monitor/server/internal/config"
)

func ClientKey(expected string) func(http.Handler) http.Handler {
	if expected == "" {
		return func(next http.Handler) http.Handler { return next }
	}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.Header.Get("X-Client-Key") != expected {
				http.Error(w, "forbidden", http.StatusForbidden)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// HashedClientKey validates X-Client-Key against bcrypt hash in cfg.ClientKeyHash
func HashedClientKey(cfg *config.Config) func(http.Handler) http.Handler {
	if cfg.ClientKeyHash == "" && cfg.ClientKey == "" {
		return func(next http.Handler) http.Handler { return next }
	}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			k := r.Header.Get("X-Client-Key")
			if k == "" {
				http.Error(w, "forbidden", http.StatusForbidden)
				return
			}
			if cfg.ClientKeyHash != "" {
				if !config.CheckPassword(cfg.ClientKeyHash, k) {
					http.Error(w, "forbidden", http.StatusForbidden)
					return
				}
				next.ServeHTTP(w, r)
				return
			}
			if cfg.ClientKey != "" && k == cfg.ClientKey {
				next.ServeHTTP(w, r)
				return
			}
			http.Error(w, "forbidden", http.StatusForbidden)
		})
	}
}
