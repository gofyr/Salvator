package config

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"errors"
	"math/big"
	"net"
	"os"
	"path/filepath"
	"strings"
	"time"

	"golang.org/x/crypto/bcrypt"
	"gopkg.in/yaml.v3"
)

type Config struct {
	ListenAddress   string `yaml:"listen_address"`
	DataDir         string `yaml:"data_dir"`
	TLSCertPath     string `yaml:"tls_cert_path"`
	TLSKeyPath      string `yaml:"tls_key_path"`
	ClientCAPath    string `yaml:"client_ca_path"`
	RequireClientCA bool   `yaml:"require_client_ca"`

	Username     string `yaml:"username"`
	PasswordHash string `yaml:"password_hash"`

	JWTSecret  string        `yaml:"jwt_secret"`
	AccessTTL  time.Duration `yaml:"access_ttl"`
	RefreshTTL time.Duration `yaml:"refresh_ttl"`

	// Optional network hardening
	AllowedCIDRs []string `yaml:"allowed_cidrs"`

	// Client key: prefer hash; plaintext is deprecated
	ClientKey     string `yaml:"client_key"`
	ClientKeyHash string `yaml:"client_key_hash"`

	// Path to loaded config file (not serialized)
	ConfigFile string `yaml:"-"`
}

func defaultConfig() *Config {
	return &Config{
		ListenAddress: ":8443",
		DataDir:       "./data",
		TLSCertPath:   "./data/server.crt",
		TLSKeyPath:    "./data/server.key",
		Username:      "admin",
		JWTSecret:     "",
		AccessTTL:     15 * time.Minute,
		RefreshTTL:    7 * 24 * time.Hour,
		ClientKey:     "",
		ClientKeyHash: "",
	}
}

func Load(path string) (*Config, error) {
	cfg := defaultConfig()
	if path != "" {
		b, err := os.ReadFile(path)
		if err != nil {
			return nil, err
		}
		if err := yaml.Unmarshal(b, cfg); err != nil {
			return nil, err
		}
		cfg.ConfigFile = path
	}

	applyEnvOverrides(cfg)

	// Ensure directories
	if err := os.MkdirAll(cfg.DataDir, 0o700); err != nil {
		return nil, err
	}
	if cfg.TLSCertPath == "" {
		cfg.TLSCertPath = filepath.Join(cfg.DataDir, "server.crt")
	}
	if cfg.TLSKeyPath == "" {
		cfg.TLSKeyPath = filepath.Join(cfg.DataDir, "server.key")
	}
	if cfg.JWTSecret == "" {
		secret, err := randomHex(32)
		if err != nil {
			return nil, err
		}
		cfg.JWTSecret = secret
	}
	if cfg.PasswordHash == "" {
		// Default credentials for first boot; recommend overriding via env or config
		if h, err := HashPassword("admin"); err == nil {
			cfg.PasswordHash = h
		}
	}
	// Derive client key hash if only plaintext provided
	if cfg.ClientKeyHash == "" && cfg.ClientKey != "" {
		if h, err := HashPassword(cfg.ClientKey); err == nil {
			cfg.ClientKeyHash = h
		}
	}
	return cfg, nil
}

// Save persists the configuration back to the original file path.
func Save(cfg *Config) error {
	if strings.TrimSpace(cfg.ConfigFile) == "" {
		return errors.New("no config file path set")
	}
	out, err := yaml.Marshal(cfg)
	if err != nil {
		return err
	}
	tmp := cfg.ConfigFile + ".tmp"
	if err := os.WriteFile(tmp, out, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, cfg.ConfigFile)
}

func applyEnvOverrides(cfg *Config) {
	if v := os.Getenv("SERVER_MONITOR_LISTEN"); v != "" {
		cfg.ListenAddress = v
	}
	if v := os.Getenv("SERVER_MONITOR_DATA_DIR"); v != "" {
		cfg.DataDir = v
	}
	if v := os.Getenv("SERVER_MONITOR_TLS_CERT"); v != "" {
		cfg.TLSCertPath = v
	}
	if v := os.Getenv("SERVER_MONITOR_TLS_KEY"); v != "" {
		cfg.TLSKeyPath = v
	}
	if v := os.Getenv("SERVER_MONITOR_CLIENT_CA"); v != "" {
		cfg.ClientCAPath = v
	}
	if v := os.Getenv("SERVER_MONITOR_REQUIRE_CLIENT_CA"); v != "" {
		cfg.RequireClientCA = v == "1" || strings.EqualFold(v, "true")
	}
	if v := os.Getenv("SERVER_MONITOR_USERNAME"); v != "" {
		cfg.Username = v
	}
	if v := os.Getenv("SERVER_MONITOR_PASSWORD"); v != "" {
		if h, err := HashPassword(v); err == nil {
			cfg.PasswordHash = h
		}
	}
	if v := os.Getenv("SERVER_MONITOR_JWT_SECRET"); v != "" {
		cfg.JWTSecret = v
	}
	if v := os.Getenv("SERVER_MONITOR_ACCESS_TTL"); v != "" {
		if d, err := time.ParseDuration(v); err == nil {
			cfg.AccessTTL = d
		}
	}
	if v := os.Getenv("SERVER_MONITOR_REFRESH_TTL"); v != "" {
		if d, err := time.ParseDuration(v); err == nil {
			cfg.RefreshTTL = d
		}
	}
	if v := os.Getenv("SERVER_MONITOR_ALLOWED_CIDRS"); v != "" {
		parts := strings.Split(v, ",")
		out := make([]string, 0, len(parts))
		for _, p := range parts {
			p = strings.TrimSpace(p)
			if p != "" {
				out = append(out, p)
			}
		}
		if len(out) > 0 {
			cfg.AllowedCIDRs = out
		}
	}
	if v := os.Getenv("SERVER_MONITOR_CLIENT_KEY"); v != "" {
		if h, err := HashPassword(v); err == nil {
			cfg.ClientKeyHash = h
		}
	}
}

func randomHex(n int) (string, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	const hexdigits = "0123456789abcdef"
	out := make([]byte, 2*len(b))
	for i, by := range b {
		out[2*i] = hexdigits[by>>4]
		out[2*i+1] = hexdigits[by&0x0f]
	}
	return string(out), nil
}

// EnsureSelfSignedCert generates a self-signed certificate if cert or key missing
func EnsureSelfSignedCert(cfg *Config) error {
	if fileExists(cfg.TLSCertPath) && fileExists(cfg.TLSKeyPath) {
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(cfg.TLSCertPath), 0o700); err != nil {
		return err
	}

	priv, err := rsa.GenerateKey(rand.Reader, 4096)
	if err != nil {
		return err
	}
	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		return err
	}
	tmpl := &x509.Certificate{
		SerialNumber:          serial,
		Subject:               pkix.Name{CommonName: "server-monitor"},
		NotBefore:             time.Now().Add(-5 * time.Minute),
		NotAfter:              time.Now().Add(3650 * 24 * time.Hour),
		KeyUsage:              x509.KeyUsageKeyEncipherment | x509.KeyUsageDigitalSignature,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
		DNSNames:              []string{"localhost"},
		IPAddresses:           []net.IP{net.ParseIP("127.0.0.1"), net.ParseIP("::1")},
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &priv.PublicKey, priv)
	if err != nil {
		return err
	}
	certOut, err := os.Create(cfg.TLSCertPath)
	if err != nil {
		return err
	}
	defer certOut.Close()
	if err := pem.Encode(certOut, &pem.Block{Type: "CERTIFICATE", Bytes: der}); err != nil {
		return err
	}
	keyOut, err := os.OpenFile(cfg.TLSKeyPath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o600)
	if err != nil {
		return err
	}
	defer keyOut.Close()
	if err := pem.Encode(keyOut, &pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(priv)}); err != nil {
		return err
	}
	return nil
}

func fileExists(path string) bool {
	st, err := os.Stat(path)
	return err == nil && !st.IsDir()
}

func HashPassword(plain string) (string, error) {
	if plain == "" {
		return "", errors.New("empty password")
	}
	b, err := bcrypt.GenerateFromPassword([]byte(plain), bcrypt.DefaultCost)
	return string(b), err
}

func CheckPassword(hash, plain string) bool {
	if hash == "" || plain == "" {
		return false
	}
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(plain)) == nil
}

// MaskSecret keeps only suffix characters
func MaskSecret(s string, keep int) string {
	if len(s) <= keep {
		return strings.Repeat("*", len(s))
	}
	return strings.Repeat("*", len(s)-keep) + s[len(s)-keep:]
}
