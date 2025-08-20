package auth

import (
	"errors"
	"time"

	"github.com/gofyr/server_monitor/server/internal/config"
	jwt "github.com/golang-jwt/jwt/v5"
)

type JWTManager struct {
	secret     []byte
	accessTTL  time.Duration
	refreshTTL time.Duration
}

func NewJWTManager(cfg *config.Config) (*JWTManager, error) {
	if cfg.JWTSecret == "" {
		return nil, errors.New("jwt secret required")
	}
	return &JWTManager{secret: []byte(cfg.JWTSecret), accessTTL: cfg.AccessTTL, refreshTTL: cfg.RefreshTTL}, nil
}

type Claims struct {
	Username string `json:"username"`
	TokenUse string `json:"token_use"`
	jwt.RegisteredClaims
}

func (m *JWTManager) Sign(username string, tokenUse string, ttl time.Duration) (string, error) {
	now := time.Now()
	claims := &Claims{
		Username: username,
		TokenUse: tokenUse,
		RegisteredClaims: jwt.RegisteredClaims{
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(ttl)),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(m.secret)
}

func (m *JWTManager) Verify(tokenString string) (*Claims, error) {
	parsed, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
		return m.secret, nil
	})
	if err != nil {
		return nil, err
	}
	claims, ok := parsed.Claims.(*Claims)
	if !ok || !parsed.Valid {
		return nil, errors.New("invalid token")
	}
	return claims, nil
}

func (m *JWTManager) IssuePair(username string) (access string, refresh string, err error) {
	access, err = m.Sign(username, "access", m.accessTTL)
	if err != nil {
		return
	}
	refresh, err = m.Sign(username, "refresh", m.refreshTTL)
	return
}
