package main

import (
	"crypto/tls"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/gorilla/mux"

	"github.com/gofyr/server_monitor/server/internal/auth"
	"github.com/gofyr/server_monitor/server/internal/config"
	"github.com/gofyr/server_monitor/server/internal/handlers"
	"github.com/gofyr/server_monitor/server/internal/middleware"
)

func main() {
	cfgPath := flag.String("config", "", "Path to server config file (yaml)")
	genCert := flag.Bool("gen-cert", false, "Generate self-signed TLS certificate in data dir and exit")
	hashSecret := flag.String("hash", "", "Print bcrypt hash of the provided secret and exit")
	flag.Parse()

	if *hashSecret != "" {
		h, err := config.HashPassword(*hashSecret)
		if err != nil {
			log.Fatalf("hash error: %v", err)
		}
		fmt.Println(h)
		return
	}

	cfg, err := config.Load(*cfgPath)
	if err != nil {
		log.Fatalf("failed to load config: %v", err)
	}

	if *genCert {
		if err := config.EnsureSelfSignedCert(cfg); err != nil {
			log.Fatalf("failed to generate cert: %v", err)
		}
		fmt.Println("Self-signed certificate generated at:")
		fmt.Println("  cert:", cfg.TLSCertPath)
		fmt.Println("  key:", cfg.TLSKeyPath)
		return
	}

	jwtManager, err := auth.NewJWTManager(cfg)
	if err != nil {
		log.Fatalf("failed to init auth: %v", err)
	}

	r := mux.NewRouter()
	r.Use(middleware.SecurityHeaders())
	r.Use(middleware.RequestID())
	r.Use(middleware.Recover())
	if len(cfg.AllowedCIDRs) > 0 {
		r.Use(middleware.CIDRAllowlist(cfg.AllowedCIDRs))
	}

	api := r.PathPrefix("/api").Subrouter()
	// Require client key header if configured (supports hash)
	api.Use(middleware.HashedClientKey(cfg))

	// Auth endpoints
	api.HandleFunc("/auth/login", handlers.LoginHandler(jwtManager, cfg)).Methods(http.MethodPost)
	api.HandleFunc("/auth/refresh", handlers.RefreshHandler(jwtManager)).Methods(http.MethodPost)

	// Protected endpoints
	protected := api.NewRoute().Subrouter()
	protected.Use(middleware.JWTAuth(jwtManager))
	protected.HandleFunc("/me", handlers.MeHandler(cfg)).Methods(http.MethodGet)
	protected.HandleFunc("/metrics", handlers.MetricsHandler()).Methods(http.MethodGet)
	protected.HandleFunc("/metrics/stream", handlers.MetricsSSEHandler()).Methods(http.MethodGet)
	protected.HandleFunc("/processes", handlers.ProcessesHandler()).Methods(http.MethodGet)
	protected.HandleFunc("/services", handlers.ServicesHandler()).Methods(http.MethodGet)
	protected.HandleFunc("/containers", handlers.ContainersHandler()).Methods(http.MethodGet)
	protected.HandleFunc("/logins", handlers.LoginsHandler()).Methods(http.MethodGet)
	protected.HandleFunc("/auth/change_credentials", handlers.ChangeCredentialsHandler(jwtManager, cfg)).Methods(http.MethodPost)

	// Health
	r.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusOK) }).Methods(http.MethodGet)

	tlsConf := &tls.Config{MinVersion: tls.VersionTLS12}
	// Optional mTLS
	if cfg.RequireClientCA && cfg.ClientCAPath != "" {
		caPool, err := middleware.LoadCAPool(cfg.ClientCAPath)
		if err != nil {
			log.Fatalf("failed to load client CA: %v", err)
		}
		tlsConf.ClientCAs = caPool
		tlsConf.ClientAuth = tls.RequireAndVerifyClientCert
	}

	srv := &http.Server{
		Addr:              cfg.ListenAddress,
		Handler:           r,
		ReadTimeout:       10 * time.Second,
		ReadHeaderTimeout: 5 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
		TLSConfig:         tlsConf,
	}

	// Ensure certs exist
	if _, err := os.Stat(cfg.TLSCertPath); os.IsNotExist(err) {
		if err := config.EnsureSelfSignedCert(cfg); err != nil {
			log.Fatalf("failed to ensure TLS cert: %v", err)
		}
	}

	log.Printf("server starting on %s", cfg.ListenAddress)
	if err := srv.ListenAndServeTLS(cfg.TLSCertPath, cfg.TLSKeyPath); err != nil && err != http.ErrServerClosed {
		log.Fatalf("server error: %v", err)
	}
}
