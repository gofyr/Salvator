package middleware

import (
	"crypto/x509"
	"os"
)

func LoadCAPool(path string) (*x509.CertPool, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(b) {
		return nil, os.ErrInvalid
	}
	return pool, nil
}
