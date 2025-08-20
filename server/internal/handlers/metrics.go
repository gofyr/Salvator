package handlers

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/shirou/gopsutil/v3/cpu"
	"github.com/shirou/gopsutil/v3/disk"
	"github.com/shirou/gopsutil/v3/host"
	"github.com/shirou/gopsutil/v3/load"
	"github.com/shirou/gopsutil/v3/mem"
	"github.com/shirou/gopsutil/v3/net"
)

type Metrics struct {
	CPUPercent     float64            `json:"cpu_percent"`
	Load1          float64            `json:"load1"`
	Load5          float64            `json:"load5"`
	Load15         float64            `json:"load15"`
	MemoryUsed     uint64             `json:"memory_used"`
	MemoryTotal    uint64             `json:"memory_total"`
	SwapUsed       uint64             `json:"swap_used"`
	SwapTotal      uint64             `json:"swap_total"`
	DiskUsage      map[string]float64 `json:"disk_usage"`
	NetBytesIn     uint64             `json:"net_bytes_in"`
	NetBytesOut    uint64             `json:"net_bytes_out"`
	DiskReadBytes  uint64             `json:"disk_read_bytes"`
	DiskWriteBytes uint64             `json:"disk_write_bytes"`
	BootTime       uint64             `json:"boot_time"`
	Uptime         uint64             `json:"uptime"`
}

func readMetrics() (*Metrics, error) {
	var m Metrics
	cpuPercents, _ := cpu.Percent(200*time.Millisecond, false)
	if len(cpuPercents) > 0 {
		m.CPUPercent = cpuPercents[0]
	}
	if l, err := load.Avg(); err == nil {
		m.Load1, m.Load5, m.Load15 = l.Load1, l.Load5, l.Load15
	}
	if vm, err := mem.VirtualMemory(); err == nil {
		m.MemoryUsed, m.MemoryTotal = vm.Used, vm.Total
	}
	if sm, err := mem.SwapMemory(); err == nil {
		m.SwapUsed, m.SwapTotal = sm.Used, sm.Total
	}
	m.DiskUsage = map[string]float64{}
	if parts, err := disk.Partitions(false); err == nil {
		for _, p := range parts {
			if u, err := disk.Usage(p.Mountpoint); err == nil {
				m.DiskUsage[p.Mountpoint] = u.UsedPercent
			}
		}
	}
	if ios, err := net.IOCounters(false); err == nil && len(ios) > 0 {
		m.NetBytesIn, m.NetBytesOut = ios[0].BytesRecv, ios[0].BytesSent
	}
	if dio, err := disk.IOCounters(); err == nil {
		var r, w uint64
		for _, st := range dio {
			r += st.ReadBytes
			w += st.WriteBytes
		}
		m.DiskReadBytes = r
		m.DiskWriteBytes = w
	}
	if hi, err := host.Info(); err == nil {
		m.BootTime = hi.BootTime
		m.Uptime = hi.Uptime
	}
	return &m, nil
}

func MetricsHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		m, err := readMetrics()
		if err != nil {
			http.Error(w, fmt.Sprintf("metrics error: %v", err), http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(m)
	}
}

func MetricsSSEHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("Cache-Control", "no-cache")
		w.Header().Set("Connection", "keep-alive")
		ticker := time.NewTicker(2 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-r.Context().Done():
				return
			case <-ticker.C:
				m, err := readMetrics()
				if err != nil {
					return
				}
				b, _ := json.Marshal(m)
				fmt.Fprintf(w, "data: %s\n\n", string(b))
				if f, ok := w.(http.Flusher); ok {
					f.Flush()
				}
			}
		}
	}
}
