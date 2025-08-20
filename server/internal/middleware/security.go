package middleware

import (
	"net/http"
)

func SecurityHeaders() func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("X-Content-Type-Options", "nosniff")
			w.Header().Set("X-Frame-Options", "DENY")
			w.Header().Set("Referrer-Policy", "no-referrer")
			w.Header().Set("Content-Security-Policy", "default-src 'none'")
			w.Header().Set("Strict-Transport-Security", "max-age=63072000; includeSubDomains; preload")
			next.ServeHTTP(w, r)
		})
	}
}
