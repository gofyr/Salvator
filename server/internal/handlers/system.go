package handlers

import (
	"encoding/json"
	"net/http"
	"os/exec"
	"strings"

	"context"
	"time"

	"github.com/coreos/go-systemd/v22/dbus"
	"github.com/shirou/gopsutil/v3/process"
)

type Proc struct {
	PID      int32   `json:"pid"`
	Name     string  `json:"name"`
	CPU      float64 `json:"cpu"`
	Memory   uint64  `json:"memory"`
	Username string  `json:"username"`
}

func ProcessesHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		pids, _ := process.Pids()
		list := make([]Proc, 0, len(pids))
		for _, pid := range pids {
			p, err := process.NewProcess(pid)
			if err != nil {
				continue
			}
			name, _ := p.Name()
			cpu, _ := p.CPUPercent()
			memInfo, _ := p.MemoryInfo()
			user, _ := p.Username()
			var mem uint64
			if memInfo != nil {
				mem = memInfo.RSS
			}
			list = append(list, Proc{PID: pid, Name: name, CPU: cpu, Memory: mem, Username: user})
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(list)
	}
}

type Service struct {
	Name   string `json:"name"`
	Active string `json:"active"`
	Sub    string `json:"sub"`
}

func ServicesHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
		defer cancel()
		conn, err := dbus.NewWithContext(ctx)
		if err != nil {
			http.Error(w, "systemd unavailable", http.StatusServiceUnavailable)
			return
		}
		units, err := conn.ListUnitsContext(ctx)
		if err != nil {
			http.Error(w, "systemd list error", http.StatusInternalServerError)
			return
		}
		out := make([]Service, 0, len(units))
		for _, u := range units {
			if strings.HasSuffix(u.Name, ".service") {
				out = append(out, Service{Name: u.Name, Active: u.ActiveState, Sub: u.SubState})
			}
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(out)
	}
}

type Container struct {
	ID    string `json:"id"`
	Image string `json:"image"`
	Name  string `json:"name"`
	State string `json:"state"`
}

func ContainersHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()
		bins := []string{"docker", "podman"}
		var out []Container
		for _, bin := range bins {
			cmd := exec.CommandContext(ctx, bin, "ps", "--format", "{{.ID}}\t{{.Image}}\t{{.Names}}\t{{.Status}}")
			b, err := cmd.Output()
			if err != nil || len(b) == 0 {
				continue
			}
			lines := strings.Split(strings.TrimSpace(string(b)), "\n")
			out = make([]Container, 0, len(lines))
			for _, ln := range lines {
				if ln == "" {
					continue
				}
				parts := strings.Split(ln, "\t")
				if len(parts) >= 4 {
					out = append(out, Container{ID: parts[0], Image: parts[1], Name: parts[2], State: parts[3]})
				}
			}
			break
		}
		w.Header().Set("Content-Type", "application/json")
		if out == nil {
			out = []Container{}
		}
		json.NewEncoder(w).Encode(out)
	}
}

type Login struct {
	User  string `json:"user"`
	TTY   string `json:"tty"`
	Host  string `json:"host"`
	Since string `json:"since"`
}

func LoginsHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// use "who" for simplicity
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()
		cmd := exec.CommandContext(ctx, "who")
		b, err := cmd.Output()
		if err != nil {
			w.Header().Set("Content-Type", "application/json")
			w.Write([]byte("[]"))
			return
		}
		lines := strings.Split(strings.TrimSpace(string(b)), "\n")
		out := make([]Login, 0, len(lines))
		for _, ln := range lines {
			if ln == "" {
				continue
			}
			fields := strings.Fields(ln)
			l := Login{}
			if len(fields) > 0 {
				l.User = fields[0]
			}
			if len(fields) > 1 {
				l.TTY = fields[1]
			}
			if len(fields) > 2 {
				l.Since = strings.Join(fields[2:], " ")
			}
			out = append(out, l)
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(out)
	}
}
