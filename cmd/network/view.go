package main

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/charmbracelet/lipgloss"
)

// Match status-go color palette exactly.
var (
	titleStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("#C79FD7")).Bold(true)
	subtleStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("#737373"))
	warnStyle    = lipgloss.NewStyle().Foreground(lipgloss.Color("#FFD75F"))
	dangerStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("#FF5F5F")).Bold(true)
	okStyle      = lipgloss.NewStyle().Foreground(lipgloss.Color("#A5D6A7"))
	lineStyle    = lipgloss.NewStyle().Foreground(lipgloss.Color("#404040"))
	primaryStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("#BD93F9"))

	tabNames = []string{"Overview", "Traffic", "Connections", "Devices", "WiFi"}
)

const (
	iconOverview = "⇅"
	iconTraffic  = "◈"
	iconConns    = "◎"
	iconDevices  = "◧"
	iconWifi     = "◉"
)

var tabIcons = []string{iconOverview, iconTraffic, iconConns, iconDevices, iconWifi}

// ==================== Layout Primitives ====================

// cardHeader renders "icon title  ╌╌╌╌╌" matching status-go style.
func cardHeader(icon, title string, width int) string {
	titleText := icon + " " + title
	lineLen := max(width-lipgloss.Width(titleText)-2, 0)
	header := titleStyle.Render(titleText)
	if lineLen > 0 {
		header += "  " + lineStyle.Render(strings.Repeat("╌", lineLen))
	}
	return header
}

// progressBar renders a 16-char bar using █░ (matching status-go).
func progressBar(percent float64) string {
	total := 16
	if percent < 0 { percent = 0 }
	if percent > 100 { percent = 100 }
	filled := int(percent / 100 * float64(total))
	var b strings.Builder
	for i := range total {
		if i < filled {
			b.WriteString("█")
		} else {
			b.WriteString("░")
		}
	}
	return colorizePercent(percent, b.String())
}

func colorizePercent(percent float64, s string) string {
	switch {
	case percent >= 85: return dangerStyle.Render(s)
	case percent >= 60: return warnStyle.Render(s)
	default:            return okStyle.Render(s)
	}
}

func miniBar5(value, maxVal float64) string {
	if maxVal <= 0 { maxVal = 1 }
	pct := value / maxVal
	if pct > 1 { pct = 1 }
	filled := int(pct * 5)
	bar := strings.Repeat("▮", filled) + strings.Repeat("▯", 5-filled)
	if pct > 0.8 { return dangerStyle.Render(bar) }
	if pct > 0.5 { return warnStyle.Render(bar) }
	return okStyle.Render(bar)
}

// sparkline renders a sparkline graph matching status-go style.
func sparkline(history []float64, width int) string {
	blocks := []rune{'▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'}

	data := make([]float64, 0, width)
	if len(history) > 0 {
		start := 0
		if len(history) > width { start = len(history) - width }
		data = append(data, history[start:]...)
	}
	for len(data) < width {
		data = append([]float64{0}, data...)
	}
	if len(data) > width { data = data[len(data)-width:] }

	maxVal := 0.1
	for _, v := range data { if v > maxVal { maxVal = v } }

	var current float64
	if len(data) > 0 { current = data[len(data)-1] }

	var b strings.Builder
	for _, v := range data {
		level := max(int((v/maxVal)*float64(len(blocks)-1)), 0)
		if level >= len(blocks) { level = len(blocks) - 1 }
		b.WriteRune(blocks[level])
	}

	result := b.String()
	if current > 8 { return dangerStyle.Render(result) }
	if current > 3 { return warnStyle.Render(result) }
	return okStyle.Render(result)
}

func sparklineSignal(history []float64, width int) string {
	blocks := []rune{'▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'}
	data := history
	if len(data) > width { data = data[len(data)-width:] }

	var b strings.Builder
	for _, v := range data {
		// Map RSSI -100..-30 to 0..7
		norm := (v + 100) / 70.0
		if norm < 0 { norm = 0 }
		if norm > 1 { norm = 1 }
		idx := int(norm * 7)
		if idx > 7 { idx = 7 }
		b.WriteRune(blocks[idx])
	}
	return okStyle.Render(b.String())
}

func signalBar(rssi int) string {
	if rssi == 0 { return subtleStyle.Render("-----") }
	bars := 0
	switch {
	case rssi > -45: bars = 5
	case rssi > -55: bars = 4
	case rssi > -65: bars = 3
	case rssi > -75: bars = 2
	case rssi > -85: bars = 1
	}
	return okStyle.Render(strings.Repeat("▮", bars)) + subtleStyle.Render(strings.Repeat("▯", 5-bars))
}

func colorSignal(rssi int) string {
	if rssi == 0 { return "" }
	label := fmt.Sprintf("%d dBm", rssi)
	switch {
	case rssi > -50: return okStyle.Render(label)
	case rssi > -60: return okStyle.Render(label)
	case rssi > -70: return warnStyle.Render(label)
	default:         return dangerStyle.Render(label)
	}
}

func formatRate(mb float64) string {
	if mb < 0.001 { return subtleStyle.Render("0 MB/s") }
	if mb < 1 { return fmt.Sprintf("%.0f KB/s", mb*1024) }
	if mb < 10 { return fmt.Sprintf("%.2f MB/s", mb) }
	return fmt.Sprintf("%.0f MB/s", mb)
}

func truncate(s string, maxLen int) string {
	if len(s) <= maxLen { return s }
	return s[:maxLen-1] + "~"
}

// ==================== Tab Bar ====================

func renderTabs(active int, width int) string {
	var tabs []string
	for i, name := range tabNames {
		num := fmt.Sprintf("%d", i+1)
		label := num + " " + name
		if i == active {
			tabs = append(tabs, titleStyle.Render(label))
		} else {
			tabs = append(tabs, subtleStyle.Render(label))
		}
	}
	bar := "  " + strings.Join(tabs, subtleStyle.Render("  "))
	return bar
}

// ==================== Header ====================

func renderHeader(snap NetworkSnapshot, width int) string {
	title := titleStyle.Render("Mole Network")

	var parts []string
	if snap.Wifi.Connected {
		parts = append(parts, signalBar(snap.Wifi.SignalDBm)+" "+colorSignal(snap.Wifi.SignalDBm))
	}
	if snap.VPNActive {
		parts = append(parts, okStyle.Render("VPN"))
	}
	if snap.ExternalIP != "" {
		parts = append(parts, subtleStyle.Render(snap.ExternalIP))
	}

	info := strings.Join(parts, subtleStyle.Render(" · "))
	gap := width - lipgloss.Width(title) - lipgloss.Width(info) - 4
	if gap < 1 { gap = 1 }
	return "  " + title + strings.Repeat(" ", gap) + info
}

// ==================== Tab 1: Overview ====================

func renderOverview(snap NetworkSnapshot, rxHist, txHist []float64, width int) string {
	cw := width - 4
	if cw < 40 { cw = 40 }
	var sb strings.Builder

	// Interfaces card
	sb.WriteString(cardHeader(iconOverview, "Interfaces", cw) + "\n")
	for _, iface := range snap.Interfaces {
		dot := subtleStyle.Render("●")
		if iface.RxRateMBs+iface.TxRateMBs > 0.01 { dot = okStyle.Render("●") }
		rate := ""
		if iface.RxRateMBs > 0 || iface.TxRateMBs > 0 {
			rate = subtleStyle.Render(fmt.Sprintf("  %s/%s", formatRate(iface.RxRateMBs), formatRate(iface.TxRateMBs)))
		}
		sb.WriteString(fmt.Sprintf("%s %-8s %-16s %-18s %s%s\n",
			dot, iface.Name, iface.IP, iface.MAC, subtleStyle.Render(iface.Type), rate))
	}

	// Wi-Fi card
	if snap.Wifi.Connected {
		sb.WriteString("\n" + cardHeader(iconWifi, "Wi-Fi", cw) + "\n")
		ssid := snap.Wifi.SSID
		if ssid == "" { ssid = subtleStyle.Render("(redacted)") }
		sb.WriteString(fmt.Sprintf("SSID   %s\n", ssid))
		sb.WriteString(fmt.Sprintf("Signal %s  %s  %s\n", signalBar(snap.Wifi.SignalDBm), colorSignal(snap.Wifi.SignalDBm), snap.Wifi.Quality))
		sb.WriteString(fmt.Sprintf("Chan   %s  %s\n", snap.Wifi.Channel, primaryStyle.Render(snap.Wifi.Band)))
		sb.WriteString(fmt.Sprintf("Mode   %s  %s\n", snap.Wifi.PHYMode, snap.Wifi.Security))
		if snap.Wifi.TxRate > 0 {
			sb.WriteString(fmt.Sprintf("Rate   %d Mbps  SNR %d dB\n", snap.Wifi.TxRate, snap.Wifi.SNR))
		}
	}

	// Traffic card
	graphW := min(cw-22, 16)
	if graphW < 5 { graphW = 5 }
	sb.WriteString("\n" + cardHeader(iconTraffic, "Traffic", cw) + "\n")
	sb.WriteString(fmt.Sprintf("Down   %s  %s\n", sparkline(rxHist, graphW), formatRate(snap.TrafficRx)))
	sb.WriteString(fmt.Sprintf("Up     %s  %s\n", sparkline(txHist, graphW), formatRate(snap.TrafficTx)))

	// Connectivity card
	sb.WriteString("\n" + cardHeader("◎", "Connectivity", cw) + "\n")
	if snap.ExternalIP != "" {
		sb.WriteString(fmt.Sprintf("ExtIP  %s\n", snap.ExternalIP))
	}
	if snap.VPNActive {
		sb.WriteString(fmt.Sprintf("VPN    %s\n", okStyle.Render("Active")))
	}
	dnsLabel := okStyle.Render("OK")
	if !snap.DNSOk { dnsLabel = dangerStyle.Render("FAIL") }
	sb.WriteString(fmt.Sprintf("DNS    %s\n", dnsLabel))
	if snap.GatewayIP != "" {
		latency := subtleStyle.Render("unreachable")
		if snap.GatewayMs > 0 { latency = fmt.Sprintf("%.1fms", snap.GatewayMs) }
		sb.WriteString(fmt.Sprintf("GW     %s  %s\n", snap.GatewayIP, latency))
	}
	if snap.InternetMs > 0 {
		sb.WriteString(fmt.Sprintf("Ping   %.1fms\n", snap.InternetMs))
	}

	return sb.String()
}

// ==================== Tab 2: Traffic ====================

func renderTraffic(snap NetworkSnapshot, rxHist, txHist []float64, width int) string {
	cw := width - 4
	if cw < 40 { cw = 40 }
	var sb strings.Builder

	// Per-interface rates
	sb.WriteString(cardHeader(iconTraffic, "Interface Rates", cw) + "\n")
	for _, iface := range snap.Interfaces {
		bar := miniBar5(iface.RxRateMBs+iface.TxRateMBs, 10.0)
		sb.WriteString(fmt.Sprintf("%-8s %s  Rx %-12s Tx %s\n",
			iface.Name, bar, formatRate(iface.RxRateMBs), formatRate(iface.TxRateMBs)))
	}

	// Bandwidth sparklines
	graphW := min(cw-22, 40)
	if graphW < 5 { graphW = 5 }
	sb.WriteString("\n" + cardHeader(iconOverview, "Bandwidth", cw) + "\n")
	sb.WriteString(fmt.Sprintf("Down   %s  %s\n", sparkline(rxHist, graphW), formatRate(snap.TrafficRx)))
	sb.WriteString(fmt.Sprintf("Up     %s  %s\n", sparkline(txHist, graphW), formatRate(snap.TrafficTx)))

	// Top talkers
	sb.WriteString("\n" + cardHeader("❊", "Top Talkers", cw) + "\n")
	procs := aggregateProcessTraffic(snap.Connections)
	sb.WriteString(subtleStyle.Render(fmt.Sprintf("%-16s %5s  %s", "PROCESS", "CONNS", "REMOTE IPs")) + "\n")
	for i, p := range procs {
		if i >= 10 { break }
		ips := strings.Join(p.IPs, ", ")
		if len(ips) > 38 { ips = ips[:35] + "..." }
		sb.WriteString(fmt.Sprintf("%-16s %5d  %s\n", truncate(p.Name, 16), p.Conns, subtleStyle.Render(ips)))
	}

	return sb.String()
}

// ==================== Tab 3: Connections ====================

func renderConnections(snap NetworkSnapshot, filter string, sortCol int, width int) string {
	cw := width - 4
	if cw < 40 { cw = 40 }
	var sb strings.Builder

	filtered := snap.Connections
	if filter != "" {
		var f []ConnectionInfo
		for _, c := range filtered {
			if strings.Contains(strings.ToLower(c.Process), strings.ToLower(filter)) ||
				strings.Contains(c.RemoteIP, filter) ||
				strings.Contains(c.Hostname, filter) {
				f = append(f, c)
			}
		}
		filtered = f
	}

	sb.WriteString(cardHeader(iconConns, fmt.Sprintf("TCP Connections (%d)", len(filtered)), cw) + "\n")
	if filter != "" {
		sb.WriteString(primaryStyle.Render("Filter: "+filter) + "\n")
	}
	sb.WriteString(subtleStyle.Render("[/] filter  [s] sort  [esc] clear") + "\n\n")

	sb.WriteString(subtleStyle.Render(fmt.Sprintf("%-14s %5s %-22s %5s  %s",
		"PROCESS", "PID", "REMOTE", "PORT", "HOSTNAME")) + "\n")

	maxShow := 22
	for i, c := range filtered {
		if i >= maxShow { break }
		host := c.Hostname
		if host == "" { host = subtleStyle.Render("-") }
		if len(host) > 22 { host = host[:19] + "..." }
		sb.WriteString(fmt.Sprintf("%-14s %5d %-22s %5d  %s\n",
			truncate(c.Process, 14), c.PID, c.RemoteIP, c.RemotePort, host))
	}

	if len(filtered) > maxShow {
		sb.WriteString(subtleStyle.Render(fmt.Sprintf("... and %d more", len(filtered)-maxShow)) + "\n")
	}

	// Listeners
	sb.WriteString("\n" + cardHeader("◪", fmt.Sprintf("Listening Ports (%d)", len(snap.Listeners)), cw) + "\n")
	sb.WriteString(subtleStyle.Render(fmt.Sprintf("%-14s %6s  %s", "PROCESS", "PORT", "ADDRESS")) + "\n")
	for i, l := range snap.Listeners {
		if i >= 12 { break }
		portStyle := subtleStyle
		if l.Port < 1024 { portStyle = warnStyle }
		sb.WriteString(fmt.Sprintf("%-14s %s  %s\n",
			truncate(l.Process, 14), portStyle.Render(fmt.Sprintf("%6d", l.Port)), l.Addr))
	}

	return sb.String()
}

// ==================== Tab 4: Devices ====================

func renderDevices(snap NetworkSnapshot, width int) string {
	cw := width - 4
	if cw < 40 { cw = 40 }
	var sb strings.Builder

	sb.WriteString(cardHeader(iconDevices, fmt.Sprintf("LAN Devices (%d)", len(snap.LANDevices)), cw) + "\n")
	sb.WriteString(subtleStyle.Render(fmt.Sprintf("%-16s %-18s %-12s %s",
		"IP", "MAC", "VENDOR", "HOST")) + "\n")

	for _, d := range snap.LANDevices {
		vendor := d.Vendor
		if vendor == "" { vendor = subtleStyle.Render("-") }
		host := d.Hostname
		if host == "" { host = subtleStyle.Render("-") }
		if len(host) > 24 { host = host[:21] + "..." }

		badges := ""
		if d.IsGateway { badges += warnStyle.Render(" GW") }
		if d.IsSelf    { badges += primaryStyle.Render(" ME") }
		if d.IsHidden  { badges += dangerStyle.Render(" HIDDEN") }

		sb.WriteString(fmt.Sprintf("%-16s %-18s %-12s %s%s\n",
			d.IP, d.MAC, truncate(vendor, 12), host, badges))
	}

	if len(snap.LANDevices) == 0 {
		sb.WriteString(subtleStyle.Render("Scanning...") + "\n")
	}

	return sb.String()
}

// ==================== Tab 5: WiFi Analysis ====================

func renderWifi(snap NetworkSnapshot, sigHist, snrHist []float64, width int) string {
	cw := width - 4
	if cw < 40 { cw = 40 }
	var sb strings.Builder

	if !snap.Wifi.Connected {
		sb.WriteString(cardHeader(iconWifi, "Wi-Fi", cw) + "\n")
		sb.WriteString(subtleStyle.Render("Not connected") + "\n")
		return sb.String()
	}

	// Current connection
	sb.WriteString(cardHeader(iconWifi, "Connection", cw) + "\n")
	ssid := snap.Wifi.SSID
	if ssid == "" { ssid = subtleStyle.Render("(redacted)") }
	sb.WriteString(fmt.Sprintf("Net    %s\n", primaryStyle.Render(ssid)))
	sb.WriteString(fmt.Sprintf("Signal %s  %s\n", signalBar(snap.Wifi.SignalDBm), colorSignal(snap.Wifi.SignalDBm)))
	sb.WriteString(fmt.Sprintf("Chan   %s\n", snap.Wifi.Channel))
	sb.WriteString(fmt.Sprintf("Band   %s  Mode %s\n", primaryStyle.Render(snap.Wifi.Band), snap.Wifi.PHYMode))
	sb.WriteString(fmt.Sprintf("Sec    %s\n", snap.Wifi.Security))
	if snap.Wifi.TxRate > 0 {
		sb.WriteString(fmt.Sprintf("Rate   %d Mbps\n", snap.Wifi.TxRate))
	}
	if snap.Wifi.SNR != 0 {
		snrLabel := "Poor"
		switch {
		case snap.Wifi.SNR > 40: snrLabel = "Excellent"
		case snap.Wifi.SNR > 25: snrLabel = "Good"
		case snap.Wifi.SNR > 15: snrLabel = "Fair"
		}
		sb.WriteString(fmt.Sprintf("SNR    %d dB (%s)\n", snap.Wifi.SNR, snrLabel))
	}

	// Signal history
	if len(sigHist) > 0 {
		graphW := min(cw-15, 40)
		if graphW < 5 { graphW = 5 }
		sb.WriteString("\n" + cardHeader("◈", "Signal History", cw) + "\n")
		sb.WriteString(fmt.Sprintf("RSSI   %s  %s\n", sparklineSignal(sigHist, graphW), colorSignal(snap.Wifi.SignalDBm)))
	}

	// Channel map
	sb.WriteString("\n" + cardHeader("◎", "Channel Map", cw) + "\n")
	chLines := buildChannelMap(snap.Wifi, snap.NearbyNets)
	for _, line := range chLines {
		sb.WriteString(line + "\n")
	}

	// Nearby networks
	if len(snap.NearbyNets) > 0 {
		sb.WriteString("\n" + cardHeader("◧", fmt.Sprintf("Nearby (%d)", len(snap.NearbyNets)), cw) + "\n")
		sb.WriteString(subtleStyle.Render(fmt.Sprintf("%-18s %-14s %-12s %s",
			"SSID", "CHANNEL", "SECURITY", "SIGNAL")) + "\n")
		for i, n := range snap.NearbyNets {
			if i >= 12 { break }
			name := n.SSID
			if name == "<redacted>" { name = subtleStyle.Render("(hidden)") }
			sb.WriteString(fmt.Sprintf("%-18s %-14s %-12s %s\n",
				truncate(name, 18), n.Channel, truncate(n.Security, 12), colorSignal(n.SignalDBm)))
		}
	}

	return sb.String()
}

// ==================== Channel Map ====================

func buildChannelMap(current WifiInfo, nearby []NearbyNetwork) []string {
	ch24 := make(map[int]int)
	ch5  := make(map[int]int)

	addCh := func(ch string) {
		parts := strings.Fields(ch)
		if len(parts) == 0 { return }
		num, err := strconv.Atoi(parts[0])
		if err != nil { return }
		if num <= 14 { ch24[num]++ } else { ch5[num]++ }
	}

	addCh(current.Channel)
	for _, n := range nearby { addCh(n.Channel) }

	var lines []string

	if len(ch24) > 0 {
		line := subtleStyle.Render("2.4G ") + " "
		for ch := 1; ch <= 13; ch++ {
			cnt := ch24[ch]
			label := fmt.Sprintf("%2d", ch)
			switch {
			case cnt == 0: line += subtleStyle.Render(label) + " "
			case cnt == 1: line += okStyle.Render(label) + " "
			default:       line += dangerStyle.Render(label) + " "
			}
		}
		lines = append(lines, line)
	}

	if len(ch5) > 0 {
		line := subtleStyle.Render("5GHz ") + " "
		channels5 := []int{36, 40, 44, 48, 52, 56, 60, 64, 100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 149, 153, 157, 161, 165}
		for _, ch := range channels5 {
			cnt := ch5[ch]
			label := fmt.Sprintf("%3d", ch)
			switch {
			case cnt == 0: line += subtleStyle.Render(label) + " "
			case cnt == 1: line += okStyle.Render(label) + " "
			default:       line += warnStyle.Render(label) + " "
			}
		}
		lines = append(lines, line)
	}

	if len(lines) == 0 {
		lines = append(lines, subtleStyle.Render("No channel data"))
	}
	return lines
}

func min(a, b int) int {
	if a < b { return a }
	return b
}
