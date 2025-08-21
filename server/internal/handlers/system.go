package handlers

import (
	"encoding/json"
	"net/http"
	"os/exec"
	"strconv"
	"strings"
	"syscall"

	"context"
	"time"

	"github.com/coreos/go-systemd/v22/dbus"
	"github.com/shirou/gopsutil/v3/cpu"
	"github.com/shirou/gopsutil/v3/disk"
	"github.com/shirou/gopsutil/v3/load"
	"github.com/shirou/gopsutil/v3/mem"
	gnet "github.com/shirou/gopsutil/v3/net"
	"github.com/shirou/gopsutil/v3/process"
)

type Proc struct {
	PID      int32   `json:"pid"`
	Name     string  `json:"name"`
	CPU      float64 `json:"cpu"`
	Memory   uint64  `json:"memory"`
	Username string  `json:"username"`
}

type DiskMount struct {
	Device     string  `json:"device"`
	Mountpoint string  `json:"mountpoint"`
	Fstype     string  `json:"fstype"`
	Total      uint64  `json:"total"`
	Used       uint64  `json:"used"`
	Free       uint64  `json:"free"`
	UsedPct    float64 `json:"used_percent"`
}

type DiskIO struct {
	Name       string `json:"name"`
	ReadBytes  uint64 `json:"read_bytes"`
	WriteBytes uint64 `json:"write_bytes"`
	Reads      uint64 `json:"reads"`
	Writes     uint64 `json:"writes"`
}

type DiskDetail struct {
	Mounts []DiskMount `json:"mounts"`
	IO     []DiskIO    `json:"io"`
}

func DiskDetailHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		parts, _ := disk.Partitions(false)
		mounts := make([]DiskMount, 0, len(parts))
		for _, p := range parts {
			if u, err := disk.Usage(p.Mountpoint); err == nil {
				mounts = append(mounts, DiskMount{
					Device:     p.Device,
					Mountpoint: p.Mountpoint,
					Fstype:     p.Fstype,
					Total:      u.Total,
					Used:       u.Used,
					Free:       u.Free,
					UsedPct:    u.UsedPercent,
				})
			}
		}
		ioStats, _ := disk.IOCounters()
		ios := make([]DiskIO, 0, len(ioStats))
		for name, st := range ioStats {
			ios = append(ios, DiskIO{
				Name:       name,
				ReadBytes:  st.ReadBytes,
				WriteBytes: st.WriteBytes,
				Reads:      st.ReadCount,
				Writes:     st.WriteCount,
			})
		}
		out := DiskDetail{Mounts: mounts, IO: ios}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(out)
	}
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

type MemDetail struct {
	Total       uint64  `json:"total"`
	Used        uint64  `json:"used"`
	Free        uint64  `json:"free"`
	Available   uint64  `json:"available"`
	Buffers     uint64  `json:"buffers"`
	Cached      uint64  `json:"cached"`
	UsedPercent float64 `json:"used_percent"`
	SwapTotal   uint64  `json:"swap_total"`
	SwapUsed    uint64  `json:"swap_used"`
}

type SystemDetail struct {
	PerCPU []float64 `json:"per_cpu"`
	Load1  float64   `json:"load1"`
	Load5  float64   `json:"load5"`
	Load15 float64   `json:"load15"`
	Memory MemDetail `json:"memory"`
}

func SystemDetailHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		per, _ := cpu.Percent(200*time.Millisecond, true)
		l, _ := load.Avg()
		vm, _ := mem.VirtualMemory()
		sm, _ := mem.SwapMemory()
		m := MemDetail{}
		if vm != nil {
			m.Total = vm.Total
			m.Used = vm.Used
			m.Free = vm.Free
			m.Available = vm.Available
			m.Buffers = vm.Buffers
			m.Cached = vm.Cached
			m.UsedPercent = vm.UsedPercent
		}
		if sm != nil {
			m.SwapTotal = sm.Total
			m.SwapUsed = sm.Used
		}
		out := SystemDetail{
			PerCPU: per,
			Memory: m,
		}
		if l != nil {
			out.Load1, out.Load5, out.Load15 = l.Load1, l.Load5, l.Load15
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(out)
	}
}

type Listener struct {
	Protocol     string `json:"protocol"`
	LocalAddress string `json:"local_address"`
	LocalPort    uint32 `json:"local_port"`
	PID          int32  `json:"pid"`
	Process      string `json:"process"`
}

type IFace struct {
	Name        string `json:"name"`
	BytesRecv   uint64 `json:"bytes_recv"`
	BytesSent   uint64 `json:"bytes_sent"`
	PacketsRecv uint64 `json:"packets_recv"`
	PacketsSent uint64 `json:"packets_sent"`
	ErrIn       uint64 `json:"err_in"`
	ErrOut      uint64 `json:"err_out"`
}

type NetworkDetail struct {
	Listeners   []Listener `json:"listeners"`
	Interfaces  []IFace    `json:"interfaces"`
	Connections []Conn     `json:"connections"`
}

func NetworkDetailHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		conns, _ := gnet.Connections("inet")
		listeners := make([]Listener, 0)
		established := make([]Conn, 0)
		for _, c := range conns {
			if c.Status == "LISTEN" || c.Status == "ESTABLISHED" {
				name := ""
				if c.Pid > 0 {
					if p, err := process.NewProcess(c.Pid); err == nil {
						if n, err2 := p.Name(); err2 == nil {
							name = n
						}
					}
				}
				if c.Status == "LISTEN" {
					var proto string
					switch c.Type {
					case syscall.SOCK_STREAM:
						proto = "tcp"
					case syscall.SOCK_DGRAM:
						proto = "udp"
					default:
						proto = strconv.FormatUint(uint64(c.Type), 10)
					}
					listeners = append(listeners, Listener{
						Protocol:     proto,
						LocalAddress: c.Laddr.IP,
						LocalPort:    c.Laddr.Port,
						PID:          c.Pid,
						Process:      name,
					})
				} else if c.Status == "ESTABLISHED" {
					var protoE string
					switch c.Type {
					case syscall.SOCK_STREAM:
						protoE = "tcp"
					case syscall.SOCK_DGRAM:
						protoE = "udp"
					default:
						protoE = strconv.FormatUint(uint64(c.Type), 10)
					}
					established = append(established, Conn{
						Protocol:  protoE,
						LaddrIP:   c.Laddr.IP,
						LaddrPort: c.Laddr.Port,
						RaddrIP:   c.Raddr.IP,
						RaddrPort: c.Raddr.Port,
						PID:       c.Pid,
						Process:   name,
						Status:    c.Status,
					})
				}
			}
		}
		ifaceStats, _ := gnet.IOCounters(true)
		ifs := make([]IFace, 0, len(ifaceStats))
		for _, s := range ifaceStats {
			ifs = append(ifs, IFace{
				Name:        s.Name,
				BytesRecv:   s.BytesRecv,
				BytesSent:   s.BytesSent,
				PacketsRecv: s.PacketsRecv,
				PacketsSent: s.PacketsSent,
				ErrIn:       s.Errin,
				ErrOut:      s.Errout,
			})
		}
		out := NetworkDetail{Listeners: listeners, Interfaces: ifs, Connections: established}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(out)
	}
}

type Conn struct {
	Protocol  string `json:"protocol"`
	LaddrIP   string `json:"laddr_ip"`
	LaddrPort uint32 `json:"laddr_port"`
	RaddrIP   string `json:"raddr_ip"`
	RaddrPort uint32 `json:"raddr_port"`
	PID       int32  `json:"pid"`
	Process   string `json:"process"`
	Status    string `json:"status"`
}
