package main

import (
	"context"
	"fmt"
	"os/exec"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	psnet "github.com/shirou/gopsutil/v4/net"
)

// Collector gathers network metrics with caching for slow calls.
type Collector struct {
	mu sync.Mutex

	// Fast metrics (1-2s).
	prevNet   map[string]psnet.IOCountersStat
	lastNetAt time.Time

	// Traffic history ring buffers.
	rxBuf *RingBuf
	txBuf *RingBuf

	// Wi-Fi signal history.
	signalBuf *RingBuf
	snrBuf    *RingBuf

	// Slow caches.
	cachedWifi      WifiInfo
	cachedNearby    []NearbyNetwork
	lastWifiAt      time.Time
	cachedExtIP     string
	cachedVPN       bool
	lastExtAt       time.Time
	cachedDevices   []LANDevice
	lastDevicesAt   time.Time
	cachedGateway   string
	lastGatewayAt   time.Time

	// DNS reverse cache.
	dnsCache     map[string]string
	dnsCacheMu   sync.RWMutex
}

// RingBuf is a fixed-size circular buffer.
type RingBuf struct {
	data  []float64
	idx   int
	size  int
	cap   int
}

func NewRingBuf(capacity int) *RingBuf {
	return &RingBuf{data: make([]float64, capacity), cap: capacity}
}

func (r *RingBuf) Add(v float64) {
	r.data[r.idx] = v
	r.idx = (r.idx + 1) % r.cap
	if r.size < r.cap {
		r.size++
	}
}

func (r *RingBuf) Slice() []float64 {
	if r.size == 0 {
		return nil
	}
	res := make([]float64, r.size)
	if r.size < r.cap {
		copy(res, r.data[:r.size])
	} else {
		copy(res, r.data[r.idx:])
		copy(res[r.cap-r.idx:], r.data[:r.idx])
	}
	return res
}

func NewCollector() *Collector {
	return &Collector{
		prevNet:  make(map[string]psnet.IOCountersStat),
		rxBuf:    NewRingBuf(120),
		txBuf:    NewRingBuf(120),
		signalBuf: NewRingBuf(60),
		snrBuf:    NewRingBuf(60),
		dnsCache: make(map[string]string),
	}
}

// Collect performs one snapshot collection. Slow items are cached.
func (c *Collector) Collect() NetworkSnapshot {
	now := time.Now()
	var snap NetworkSnapshot
	var wg sync.WaitGroup

	// --- Fast metrics (every tick) ---
	wg.Add(1)
	go func() {
		defer wg.Done()
		snap.Interfaces = c.collectInterfaces(now)
		var totalRx, totalTx float64
		for _, iface := range snap.Interfaces {
			totalRx += iface.RxRateMBs
			totalTx += iface.TxRateMBs
		}
		snap.TrafficRx = totalRx
		snap.TrafficTx = totalTx
		c.rxBuf.Add(totalRx)
		c.txBuf.Add(totalTx)
	}()

	wg.Add(1)
	go func() {
		defer wg.Done()
		snap.Connections = c.collectConnections()
		snap.Listeners = c.collectListeners()
	}()

	// --- Medium metrics (5-10s cache) ---
	wg.Add(1)
	go func() {
		defer wg.Done()
		c.mu.Lock()
		if now.Sub(c.lastWifiAt) > 10*time.Second {
			c.mu.Unlock()
			wifi, nearby := collectWifiInfo()
			c.mu.Lock()
			c.cachedWifi = wifi
			c.cachedNearby = nearby
			c.lastWifiAt = now
			if wifi.SignalDBm != 0 {
				c.signalBuf.Add(float64(wifi.SignalDBm))
				c.snrBuf.Add(float64(wifi.SNR))
			}
		}
		snap.Wifi = c.cachedWifi
		snap.NearbyNets = c.cachedNearby
		c.mu.Unlock()
	}()

	wg.Add(1)
	go func() {
		defer wg.Done()
		c.mu.Lock()
		if now.Sub(c.lastDevicesAt) > 5*time.Second {
			c.mu.Unlock()
			devices := c.collectDevices()
			c.mu.Lock()
			c.cachedDevices = devices
			c.lastDevicesAt = now
		}
		snap.LANDevices = c.cachedDevices
		c.mu.Unlock()
	}()

	// --- Slow metrics (30s cache) ---
	wg.Add(1)
	go func() {
		defer wg.Done()
		c.mu.Lock()
		if now.Sub(c.lastExtAt) > 30*time.Second {
			c.mu.Unlock()
			extIP, vpn := collectExternalInfo()
			c.mu.Lock()
			c.cachedExtIP = extIP
			c.cachedVPN = vpn
			c.lastExtAt = now
		}
		snap.ExternalIP = c.cachedExtIP
		snap.VPNActive = c.cachedVPN
		c.mu.Unlock()
	}()

	wg.Add(1)
	go func() {
		defer wg.Done()
		snap.DNSOk = checkDNS()
		gw, gwMs := c.getGatewayLatency()
		snap.GatewayIP = gw
		snap.GatewayMs = gwMs
		snap.InternetMs = pingHost("8.8.8.8")
	}()

	wg.Wait()
	return snap
}

func (c *Collector) TrafficHistory() (rx, tx []float64) {
	return c.rxBuf.Slice(), c.txBuf.Slice()
}

func (c *Collector) SignalHistory() (dbm, snr []float64) {
	return c.signalBuf.Slice(), c.snrBuf.Slice()
}

// --- Interface collection with rate calculation ---

func isNoise(name string) bool {
	for _, p := range []string{"lo", "awdl", "llw", "bridge", "gif", "stf", "xhc", "anpi", "ap"} {
		if strings.HasPrefix(strings.ToLower(name), p) {
			return true
		}
	}
	return false
}

func (c *Collector) collectInterfaces(now time.Time) []InterfaceInfo {
	stats, err := psnet.IOCounters(true)
	if err != nil {
		return nil
	}

	ifAddrs := make(map[string]string)
	ifMACs := make(map[string]string)
	ifaces, _ := psnet.Interfaces()
	for _, iface := range ifaces {
		for _, addr := range iface.Addrs {
			if strings.Contains(addr.Addr, ".") && !strings.HasPrefix(addr.Addr, "127.") {
				ip := strings.Split(addr.Addr, "/")[0]
				ifAddrs[iface.Name] = ip
				break
			}
		}
		if iface.HardwareAddr != "" {
			ifMACs[iface.Name] = iface.HardwareAddr
		}
	}

	elapsed := now.Sub(c.lastNetAt).Seconds()
	if elapsed <= 0 {
		elapsed = 1
	}

	var result []InterfaceInfo
	for _, cur := range stats {
		if isNoise(cur.Name) {
			continue
		}
		ip := ifAddrs[cur.Name]
		if ip == "" && !strings.HasPrefix(cur.Name, "utun") {
			continue
		}

		var rx, tx float64
		if !c.lastNetAt.IsZero() {
			if prev, ok := c.prevNet[cur.Name]; ok {
				rx = float64(cur.BytesRecv-prev.BytesRecv) / 1024.0 / 1024.0 / elapsed
				tx = float64(cur.BytesSent-prev.BytesSent) / 1024.0 / 1024.0 / elapsed
				if rx < 0 { rx = 0 }
				if tx < 0 { tx = 0 }
			}
		}

		ifType := "Ethernet"
		if cur.Name == "en0" { ifType = "Wi-Fi" }
		if strings.HasPrefix(cur.Name, "utun") {
			ifType = "VPN"
			if ip == "" {
				ip = getUtunIP(cur.Name)
			}
		}
		if strings.HasPrefix(cur.Name, "en1") { ifType = "Ethernet" }

		result = append(result, InterfaceInfo{
			Name: cur.Name, IP: ip, MAC: ifMACs[cur.Name],
			Type: ifType, RxRateMBs: rx, TxRateMBs: tx,
		})
	}

	c.lastNetAt = now
	for _, s := range stats {
		c.prevNet[s.Name] = s
	}

	sort.Slice(result, func(i, j int) bool {
		return result[i].RxRateMBs+result[i].TxRateMBs > result[j].RxRateMBs+result[j].TxRateMBs
	})
	return result
}

func getUtunIP(name string) string {
	ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, "ifconfig", name).Output()
	if err != nil { return "" }
	for _, line := range strings.Split(string(out), "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "inet ") {
			parts := strings.Fields(line)
			if len(parts) >= 2 { return parts[1] }
		}
	}
	return ""
}

// --- Connection collection ---

var lsofLineRe = regexp.MustCompile(`^(\S+)\s+(\d+)\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(.+)$`)

func (c *Collector) collectConnections() []ConnectionInfo {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, "lsof", "-iTCP", "-sTCP:ESTABLISHED", "-P", "-n").Output()
	if err != nil { return nil }

	var result []ConnectionInfo
	for _, line := range strings.Split(string(out), "\n") {
		if strings.HasPrefix(line, "COMMAND") || line == "" { continue }
		fields := strings.Fields(line)
		if len(fields) < 9 { continue }

		proc := fields[0]
		pid, _ := strconv.Atoi(fields[1])
		nameCol := fields[8]

		// Parse "10.8.0.8:57782->149.154.167.51:443"
		parts := strings.SplitN(nameCol, "->", 2)
		if len(parts) != 2 { continue }

		localParts := splitHostPort(parts[0])
		remoteParts := splitHostPort(parts[1])
		if remoteParts.ip == "127.0.0.1" || remoteParts.ip == "::1" { continue }

		hostname := c.reverseDNS(remoteParts.ip)

		result = append(result, ConnectionInfo{
			Process: proc, PID: pid,
			LocalAddr: localParts.ip, LocalPort: localParts.port,
			RemoteIP: remoteParts.ip, RemotePort: remoteParts.port,
			State: "ESTABLISHED", Hostname: hostname,
		})
	}
	return result
}

func (c *Collector) collectListeners() []ListenerInfo {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, "lsof", "-iTCP", "-sTCP:LISTEN", "-P", "-n").Output()
	if err != nil { return nil }

	seen := make(map[string]bool)
	var result []ListenerInfo
	for _, line := range strings.Split(string(out), "\n") {
		if strings.HasPrefix(line, "COMMAND") || line == "" { continue }
		fields := strings.Fields(line)
		if len(fields) < 9 { continue }

		proc := fields[0]
		pid, _ := strconv.Atoi(fields[1])
		nameCol := fields[8]
		hp := splitHostPort(nameCol)
		key := fmt.Sprintf("%s:%d", proc, hp.port)
		if seen[key] { continue }
		seen[key] = true

		addr := "localhost"
		if strings.HasPrefix(nameCol, "*:") { addr = "all" }

		result = append(result, ListenerInfo{Process: proc, PID: pid, Port: hp.port, Addr: addr})
	}
	return result
}

type hostPort struct {
	ip   string
	port int
}

func splitHostPort(s string) hostPort {
	idx := strings.LastIndex(s, ":")
	if idx < 0 { return hostPort{ip: s} }
	ip := s[:idx]
	port, _ := strconv.Atoi(s[idx+1:])
	return hostPort{ip: ip, port: port}
}

// --- Reverse DNS with caching ---

func (c *Collector) reverseDNS(ip string) string {
	c.dnsCacheMu.RLock()
	if v, ok := c.dnsCache[ip]; ok {
		c.dnsCacheMu.RUnlock()
		return v
	}
	c.dnsCacheMu.RUnlock()

	// Non-blocking DNS lookup.
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		out, err := exec.CommandContext(ctx, "host", ip).Output()
		hostname := ""
		if err == nil {
			for _, line := range strings.Split(string(out), "\n") {
				if strings.Contains(line, "domain name pointer") {
					parts := strings.Fields(line)
					if len(parts) > 0 {
						hostname = strings.TrimSuffix(parts[len(parts)-1], ".")
					}
				}
			}
		}
		c.dnsCacheMu.Lock()
		c.dnsCache[ip] = hostname
		c.dnsCacheMu.Unlock()
	}()

	return ""
}

// --- Device collection ---

func (c *Collector) collectDevices() []LANDevice {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, "arp", "-a").Output()
	if err != nil { return nil }

	gw := c.getGateway()
	selfIP := getSelfIP()
	macRe := regexp.MustCompile(`([0-9a-f]{1,2}:){5}[0-9a-f]{1,2}`)
	ipRe := regexp.MustCompile(`[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+`)

	var result []LANDevice
	for _, line := range strings.Split(string(out), "\n") {
		if strings.Contains(line, "incomplete") { continue }
		if strings.Contains(line, "ff:ff:ff:ff:ff:ff") { continue }
		if strings.Contains(line, "01:00:5e") { continue }

		ip := ipRe.FindString(line)
		mac := macRe.FindString(line)
		if ip == "" || mac == "" { continue }

		vendor := lookupVendor(mac)
		hostname := c.reverseDNS(ip)

		d := LANDevice{
			IP: ip, MAC: mac, Vendor: vendor, Hostname: hostname,
			IsGateway: ip == gw, IsSelf: ip == selfIP,
		}
		result = append(result, d)
	}
	return result
}

func (c *Collector) getGateway() string {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.cachedGateway != "" { return c.cachedGateway }
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, "route", "-n", "get", "default").Output()
	if err != nil { return "" }
	for _, line := range strings.Split(string(out), "\n") {
		if strings.Contains(line, "gateway") {
			parts := strings.Fields(line)
			if len(parts) >= 2 {
				c.cachedGateway = parts[1]
				return parts[1]
			}
		}
	}
	return ""
}

func (c *Collector) getGatewayLatency() (string, float64) {
	gw := c.getGateway()
	if gw == "" { return "", 0 }
	ms := pingHost(gw)
	return gw, ms
}

func getSelfIP() string {
	ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, "ipconfig", "getifaddr", "en0").Output()
	if err != nil { return "" }
	return strings.TrimSpace(string(out))
}

// --- External info ---

func collectExternalInfo() (string, bool) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, "dig", "+short", "myip.opendns.com", "@resolver1.opendns.com").Output()
	extIP := ""
	if err == nil { extIP = strings.TrimSpace(string(out)) }

	// Check VPN.
	ifaces, _ := psnet.Interfaces()
	vpn := false
	for _, iface := range ifaces {
		if strings.HasPrefix(iface.Name, "utun") {
			for _, addr := range iface.Addrs {
				if strings.Contains(addr.Addr, ".") {
					vpn = true
				}
			}
		}
	}
	return extIP, vpn
}

func checkDNS() bool {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, "dig", "+short", "google.com").Output()
	return err == nil && len(strings.TrimSpace(string(out))) > 0
}

func pingHost(host string) float64 {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, "ping", "-c", "1", "-W", "2", host).Output()
	if err != nil { return 0 }
	re := regexp.MustCompile(`time=([0-9.]+)`)
	m := re.FindStringSubmatch(string(out))
	if len(m) >= 2 {
		v, _ := strconv.ParseFloat(m[1], 64)
		return v
	}
	return 0
}

// --- Process traffic aggregation ---

func aggregateProcessTraffic(conns []ConnectionInfo) []ProcessTraffic {
	m := make(map[string]*ProcessTraffic)
	for _, c := range conns {
		p, ok := m[c.Process]
		if !ok {
			p = &ProcessTraffic{Name: c.Process}
			m[c.Process] = p
		}
		p.Conns++
		found := false
		for _, ip := range p.IPs {
			if ip == c.RemoteIP { found = true; break }
		}
		if !found { p.IPs = append(p.IPs, c.RemoteIP) }
	}
	var result []ProcessTraffic
	for _, p := range m { result = append(result, *p) }
	sort.Slice(result, func(i, j int) bool { return result[i].Conns > result[j].Conns })
	return result
}
