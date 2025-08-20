package handlers

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/gofyr/server_monitor/server/internal/auth"
	"github.com/gofyr/server_monitor/server/internal/config"
)

type refreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

func RefreshHandler(jwtManager *auth.JWTManager) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req refreshRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, "bad request", http.StatusBadRequest)
			return
		}
		claims, err := jwtManager.Verify(req.RefreshToken)
		if err != nil || claims.TokenUse != "refresh" {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		access, refresh, err := jwtManager.IssuePair(claims.Username)
		if err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(tokenResponse{AccessToken: access, RefreshToken: refresh})
	}
}

type meResponse struct {
	Username     string `json:"username"`
	DefaultCreds bool   `json:"default_creds"`
}

func MeHandler(cfg *config.Config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		isDefault := cfg.Username == "admin" && strings.TrimSpace(cfg.PasswordHash) == ""
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(meResponse{Username: cfg.Username, DefaultCreds: isDefault})
	}
}

type changeCredsRequest struct {
	Username    string `json:"username"`
	NewPassword string `json:"new_password"`
}

func ChangeCredentialsHandler(jwtManager *auth.JWTManager, cfg *config.Config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req changeCredsRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, "bad request", http.StatusBadRequest)
			return
		}
		if strings.TrimSpace(req.Username) == "" || strings.TrimSpace(req.NewPassword) == "" {
			http.Error(w, "invalid input", http.StatusBadRequest)
			return
		}
		hash, err := config.HashPassword(req.NewPassword)
		if err != nil {
			http.Error(w, "hash error", http.StatusInternalServerError)
			return
		}
		cfg.Username = req.Username
		cfg.PasswordHash = hash
		_ = config.Save(cfg)
		w.WriteHeader(http.StatusNoContent)
	}
}
