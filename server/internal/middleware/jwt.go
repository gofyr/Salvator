package middleware

import (
	"context"
	"net/http"
	"strings"

	"github.com/gofyr/server_monitor/server/internal/auth"
)

type ctxKey string

const userKey ctxKey = "user"

func JWTAuth(jwtManager *auth.JWTManager) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			authz := r.Header.Get("Authorization")
			if !strings.HasPrefix(strings.ToLower(authz), "bearer ") {
				http.Error(w, "unauthorized", http.StatusUnauthorized)
				return
			}
			token := strings.TrimSpace(authz[len("Bearer "):])
			claims, err := jwtManager.Verify(token)
			if err != nil || claims.TokenUse != "access" {
				http.Error(w, "unauthorized", http.StatusUnauthorized)
				return
			}
			ctx := context.WithValue(r.Context(), userKey, claims.Username)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

func UsernameFromContext(r *http.Request) string {
	v := r.Context().Value(userKey)
	s, _ := v.(string)
	return s
}
