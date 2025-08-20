package handlers

import (
	"encoding/json"
	"net/http"

	"github.com/gofyr/server_monitor/server/internal/auth"
	"github.com/gofyr/server_monitor/server/internal/config"
)

type loginRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

type tokenResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
}

func LoginHandler(jwtManager *auth.JWTManager, cfg *config.Config) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req loginRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, "bad request", http.StatusBadRequest)
			return
		}
		if req.Username != cfg.Username || !config.CheckPassword(cfg.PasswordHash, req.Password) {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		access, refresh, err := jwtManager.IssuePair(req.Username)
		if err != nil {
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(tokenResponse{AccessToken: access, RefreshToken: refresh})
	}
}
