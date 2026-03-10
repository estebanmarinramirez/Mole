package main

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/charmbracelet/lipgloss"
)

var (
	titleStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("#C79FD7")).Bold(true)
	subtleStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("#555555"))
	accentStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("#7EC8E3"))
	greenStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("#95E06C"))
	yellowStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("#F0C674"))
	redStyle     = lipgloss.NewStyle().Foreground(lipgloss.Color("#E06C75"))
	dimStyle     = lipgloss.NewStyle().Foreground(lipgloss.Color("#666666"))
	headerStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("#B0B0B0")).Bold(true)
	activeTab    = lipgloss.NewStyle().Foreground(lipgloss.Color("#C79FD7")).Bold(true).Underline(true)
	inactiveTab  = lipgloss.NewStyle().Foreground(lipgloss.Color("#888888"))

	tabNames = []string{"Overview", "Traffic", "Connections", "Devices", "WiFi"}
	tabKeys  = []string{"1", "2", "3", "4", "5"}
)

// renderTabs renders the tab bar.
func renderTabs(active int, width int) string {
	var tabs []string
	for i, name := range tabNames {
		label := fmt.Sprintf(" %s %s ", tabKeys[i], name)
		if i == active {
			tabs = append(tabs, activeTab.Render(label))
		} else {
			tabs = append(tabs, inactiveTab.Render(label))
		}
	}
	bar := strings.Join(tabs, dimStyle.Render(" | "))
	return bar + "\n" + dimStyle.Render(strings.Repeat("─", min(width, 80)))
}

// renderHeader shows the title bar with key metrics.
func renderHeader(snap NetworkSnapshot, width int) string {
	title := titleStyle.Render("Network Dashboard")
	var parts []string
	if snap.Wifi.Connected {
		parts = append(parts, fmt.Sprintf("Wi-Fi %s", snap.Wifi.Quality))
	}
	parts = append(parts, fmt.Sprintf("%d conns", len(snap.Connections)))
	parts = append(parts, fmt.Sprintf("%d devices", len(snap.LANDevices)))
	if snap.VPNActive {
		parts = append(parts, greenStyle.Render("VPN"))
	}
	info := dimStyle.Render(strings.Join(parts, " | "))

	gap := width - lipgloss.Width(title) - lipgloss.Width(info) - 2
	if gap < 1 { gap = 1 }
	return title + strings.Repeat(" ", gap) + info
}

// ==================== Tab 1: Overview ====================

func renderOverview(snap NetworkSnapshot, rxHist, txHist []float64, width int) string {
	var sb strings.Builder

	// Interfaces
	sb.WriteString(sectionHeader("Interfaces"))
	for _, iface := range snap.Interfaces {
		marker := dimStyle.Render("●")
		if iface.RxRateMBs+iface.TxRateMBs > 0.01 {
			marker = greenStyle.Render("●")
		}
		line := fmt.Sprintf("  %s %-8s %-16s %-18s %s",
			marker, iface.Name, iface.IP, iface.MAC, dimStyle.Render(iface.Type))
		if iface.RxRateMBs > 0 || iface.TxRateMBs > 0 {
			line += dimStyle.Render(fmt.Sprintf("  %.2f/%.2f MB/s", iface.RxRateMBs, iface.TxRateMBs))
		}
		sb.WriteString(line + "\n")
	}

	// Wi-Fi
	if snap.Wifi.Connected {
		sb.WriteString(sectionHeader("Wi-Fi"))
		ssid := snap.Wifi.SSID
		if ssid == "" { ssid = "(hidden)" }
		sb.WriteString(fmt.Sprintf("  SSID       %s\n", ssid))
		sb.WriteString(fmt.Sprintf("  Signal     %s %s\n", signalBar(snap.Wifi.SignalDBm), colorizeSignal(snap.Wifi.SignalDBm)))
		sb.WriteString(fmt.Sprintf("  Channel    %s\n", snap.Wifi.Channel))
		sb.WriteString(fmt.Sprintf("  Security   %s\n", snap.Wifi.Security))
		sb.WriteString(fmt.Sprintf("  PHY        %s\n", snap.Wifi.PHYMode))
		if snap.Wifi.TxRate > 0 {
			sb.WriteString(fmt.Sprintf("  Tx Rate    %d Mbps\n", snap.Wifi.TxRate))
		}
		if snap.Wifi.SNR != 0 {
			sb.WriteString(fmt.Sprintf("  SNR        %d dB\n", snap.Wifi.SNR))
		}
	}

	// Traffic sparklines
	sb.WriteString(sectionHeader("Traffic"))
	rxSpark := sparkline(rxHist, 30)
	txSpark := sparkline(txHist, 30)
	sb.WriteString(fmt.Sprintf("  Down  %s  %s\n", rxSpark, formatRate(snap.TrafficRx)))
	sb.WriteString(fmt.Sprintf("  Up    %s  %s\n", txSpark, formatRate(snap.TrafficTx)))

	// External
	sb.WriteString(sectionHeader("Connectivity"))
	if snap.ExternalIP != "" {
		sb.WriteString(fmt.Sprintf("  External   %s\n", snap.ExternalIP))
	} else {
		sb.WriteString(fmt.Sprintf("  External   %s\n", dimStyle.Render("checking...")))
	}
	if snap.VPNActive {
		sb.WriteString(fmt.Sprintf("  VPN        %s\n", greenStyle.Render("Active")))
	}
	dnsLabel := greenStyle.Render("OK")
	if !snap.DNSOk { dnsLabel = redStyle.Render("FAIL") }
	sb.WriteString(fmt.Sprintf("  DNS        %s\n", dnsLabel))
	if snap.GatewayIP != "" {
		sb.WriteString(fmt.Sprintf("  Gateway    %s (%.1fms)\n", snap.GatewayIP, snap.GatewayMs))
	}
	if snap.InternetMs > 0 {
		sb.WriteString(fmt.Sprintf("  Internet   %.1fms\n", snap.InternetMs))
	}

	return sb.String()
}

// ==================== Tab 2: Traffic ====================

func renderTraffic(snap NetworkSnapshot, rxHist, txHist []float64, width int) string {
	var sb strings.Builder

	// Per-interface live rates
	sb.WriteString(sectionHeader("Interface Rates"))
	for _, iface := range snap.Interfaces {
		rx := formatRate(iface.RxRateMBs)
		tx := formatRate(iface.TxRateMBs)
		bar := miniBar(iface.RxRateMBs + iface.TxRateMBs, 10.0)
		sb.WriteString(fmt.Sprintf("  %-8s %s  Rx %s  Tx %s\n", iface.Name, bar, rx, tx))
	}

	// Total sparklines (large)
	sb.WriteString(sectionHeader("Total Bandwidth"))
	rxSpark := sparkline(rxHist, min(width-25, 60))
	txSpark := sparkline(txHist, min(width-25, 60))
	sb.WriteString(fmt.Sprintf("  Down  %s  %s\n", rxSpark, formatRate(snap.TrafficRx)))
	sb.WriteString(fmt.Sprintf("  Up    %s  %s\n", txSpark, formatRate(snap.TrafficTx)))

	// Top talkers
	sb.WriteString(sectionHeader("Top Talkers"))
	procs := aggregateProcessTraffic(snap.Connections)
	sb.WriteString(fmt.Sprintf("  %s\n", dimStyle.Render(fmt.Sprintf("%-18s %5s  %s", "PROCESS", "CONNS", "REMOTE IPs"))))
	for i, p := range procs {
		if i >= 10 { break }
		ips := strings.Join(p.IPs, ", ")
		if len(ips) > 40 {
			ips = ips[:37] + "..."
		}
		sb.WriteString(fmt.Sprintf("  %-18s %5d  %s\n", truncate(p.Name, 18), p.Conns, ips))
	}

	return sb.String()
}

// ==================== Tab 3: Connections ====================

func renderConnections(snap NetworkSnapshot, filter string, sortCol int, width int) string {
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

	sb.WriteString(sectionHeader(fmt.Sprintf("TCP Connections (%d)", len(filtered))))
	if filter != "" {
		sb.WriteString(fmt.Sprintf("  Filter: %s\n", accentStyle.Render(filter)))
	}
	sb.WriteString(dimStyle.Render("  [/] filter  [s] sort  [esc] clear"))
	sb.WriteString("\n\n")

	// Header
	sb.WriteString(fmt.Sprintf("  %s\n",
		dimStyle.Render(fmt.Sprintf("%-14s %5s %-22s %5s  %s", "PROCESS", "PID", "REMOTE", "PORT", "HOSTNAME"))))
	sb.WriteString(dimStyle.Render("  " + strings.Repeat("─", min(width-4, 76))))
	sb.WriteString("\n")

	maxShow := 25
	for i, c := range filtered {
		if i >= maxShow { break }
		host := c.Hostname
		if host == "" { host = dimStyle.Render("-") }
		if len(host) > 24 { host = host[:21] + "..." }
		sb.WriteString(fmt.Sprintf("  %-14s %5d %-22s %5d  %s\n",
			truncate(c.Process, 14), c.PID, c.RemoteIP, c.RemotePort, host))
	}

	if len(filtered) > maxShow {
		sb.WriteString(dimStyle.Render(fmt.Sprintf("  ... and %d more\n", len(filtered)-maxShow)))
	}

	// Listeners
	sb.WriteString("\n")
	sb.WriteString(sectionHeader(fmt.Sprintf("Listening Ports (%d)", len(snap.Listeners))))
	sb.WriteString(fmt.Sprintf("  %s\n", dimStyle.Render(fmt.Sprintf("%-14s %6s  %s", "PROCESS", "PORT", "ADDRESS"))))
	for i, l := range snap.Listeners {
		if i >= 15 { break }
		sb.WriteString(fmt.Sprintf("  %-14s %6d  %s\n", truncate(l.Process, 14), l.Port, l.Addr))
	}

	return sb.String()
}

// ==================== Tab 4: Devices ====================

func renderDevices(snap NetworkSnapshot, width int) string {
	var sb strings.Builder

	sb.WriteString(sectionHeader(fmt.Sprintf("LAN Devices (%d)", len(snap.LANDevices))))
	sb.WriteString(fmt.Sprintf("  %s\n",
		dimStyle.Render(fmt.Sprintf("%-16s %-18s %-14s %s", "IP", "MAC", "VENDOR", "HOST"))))
	sb.WriteString(dimStyle.Render("  " + strings.Repeat("─", min(width-4, 76))))
	sb.WriteString("\n")

	for _, d := range snap.LANDevices {
		vendor := d.Vendor
		if vendor == "" { vendor = dimStyle.Render("-") }
		host := d.Hostname
		if host == "" { host = dimStyle.Render("-") }
		if len(host) > 22 { host = host[:19] + "..." }

		badges := ""
		if d.IsGateway { badges += yellowStyle.Render(" [GW]") }
		if d.IsSelf { badges += accentStyle.Render(" [ME]") }
		if d.IsHidden { badges += redStyle.Render(" [HIDDEN]") }

		sb.WriteString(fmt.Sprintf("  %-16s %-18s %-14s %s%s\n",
			d.IP, d.MAC, truncate(vendor, 14), host, badges))
	}

	if len(snap.LANDevices) == 0 {
		sb.WriteString(dimStyle.Render("  Scanning...") + "\n")
	}

	return sb.String()
}

// ==================== Tab 5: WiFi Analysis ====================

func renderWifi(snap NetworkSnapshot, sigHist, snrHist []float64, width int) string {
	var sb strings.Builder

	if !snap.Wifi.Connected {
		sb.WriteString(sectionHeader("Wi-Fi"))
		sb.WriteString(dimStyle.Render("  Not connected to a Wi-Fi network") + "\n")
		return sb.String()
	}

	// Current connection
	sb.WriteString(sectionHeader("Current Connection"))
	ssid := snap.Wifi.SSID
	if ssid == "" { ssid = "(hidden SSID)" }
	sb.WriteString(fmt.Sprintf("  Network    %s\n", accentStyle.Render(ssid)))
	sb.WriteString(fmt.Sprintf("  Signal     %s %s\n", signalBar(snap.Wifi.SignalDBm), colorizeSignal(snap.Wifi.SignalDBm)))
	sb.WriteString(fmt.Sprintf("  Channel    %s\n", snap.Wifi.Channel))
	sb.WriteString(fmt.Sprintf("  Band       %s\n", snap.Wifi.Band))
	sb.WriteString(fmt.Sprintf("  Security   %s\n", snap.Wifi.Security))
	sb.WriteString(fmt.Sprintf("  PHY Mode   %s\n", snap.Wifi.PHYMode))
	if snap.Wifi.TxRate > 0 {
		sb.WriteString(fmt.Sprintf("  Tx Rate    %d Mbps\n", snap.Wifi.TxRate))
	}
	if snap.Wifi.SNR != 0 {
		sb.WriteString(fmt.Sprintf("  SNR        %d dB (%s)\n", snap.Wifi.SNR, snrLabel(snap.Wifi.SNR)))
	}

	// Signal history
	if len(sigHist) > 0 {
		sb.WriteString(sectionHeader("Signal History"))
		sigSpark := sparklineInverted(sigHist, min(width-20, 50))
		sb.WriteString(fmt.Sprintf("  RSSI   %s  %d dBm\n", sigSpark, snap.Wifi.SignalDBm))
	}

	// Channel utilization map
	sb.WriteString(sectionHeader("Channel Map"))
	chMap := buildChannelMap(snap.Wifi, snap.NearbyNets)
	for _, line := range chMap {
		sb.WriteString("  " + line + "\n")
	}

	// Nearby networks
	if len(snap.NearbyNets) > 0 {
		sb.WriteString(sectionHeader(fmt.Sprintf("Nearby Networks (%d)", len(snap.NearbyNets))))
		sb.WriteString(fmt.Sprintf("  %s\n",
			dimStyle.Render(fmt.Sprintf("%-20s %-12s %-10s %s", "SSID", "CHANNEL", "SECURITY", "SIGNAL"))))
		for i, n := range snap.NearbyNets {
			if i >= 15 { break }
			sig := colorizeSignal(n.SignalDBm)
			name := n.SSID
			if name == "<redacted>" { name = dimStyle.Render("(hidden)") }
			sb.WriteString(fmt.Sprintf("  %-20s %-12s %-10s %s\n",
				truncate(name, 20), n.Channel, truncate(n.Security, 10), sig))
		}
	}

	return sb.String()
}

// ==================== Helpers ====================

func sectionHeader(title string) string {
	return "\n" + headerStyle.Render("  "+title) + "\n\n"
}

func signalBar(rssi int) string {
	if rssi == 0 { return dimStyle.Render("-----") }
	bars := 0
	switch {
	case rssi > -45: bars = 5
	case rssi > -55: bars = 4
	case rssi > -65: bars = 3
	case rssi > -75: bars = 2
	case rssi > -85: bars = 1
	}
	filled := strings.Repeat("▮", bars)
	empty := strings.Repeat("▯", 5-bars)
	return filled + empty
}

func colorizeSignal(rssi int) string {
	if rssi == 0 { return "" }
	label := fmt.Sprintf("%d dBm", rssi)
	switch {
	case rssi > -50: return greenStyle.Render(label + " Excellent")
	case rssi > -60: return greenStyle.Render(label + " Good")
	case rssi > -70: return yellowStyle.Render(label + " Fair")
	default:         return redStyle.Render(label + " Weak")
	}
}

func snrLabel(snr int) string {
	switch {
	case snr > 40: return "Excellent"
	case snr > 25: return "Good"
	case snr > 15: return "Fair"
	default:       return "Poor"
	}
}

func sparkline(history []float64, width int) string {
	if len(history) == 0 { return strings.Repeat("▁", width) }
	chars := []rune{'▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'}
	maxVal := 0.001
	for _, v := range history { if v > maxVal { maxVal = v } }

	// Take last `width` values.
	data := history
	if len(data) > width { data = data[len(data)-width:] }

	var sb strings.Builder
	for _, v := range data {
		idx := int(v / maxVal * 7)
		if idx > 7 { idx = 7 }
		if idx < 0 { idx = 0 }
		sb.WriteRune(chars[idx])
	}
	// Pad if needed.
	for sb.Len() < width { sb.WriteRune(chars[0]) }
	return accentStyle.Render(sb.String())
}

func sparklineInverted(history []float64, width int) string {
	// For RSSI: values are negative, closer to 0 is better.
	if len(history) == 0 { return strings.Repeat("▁", width) }
	chars := []rune{'▁', '▂', '▃', '▄', '▅', '▆', '▇', '█'}

	data := history
	if len(data) > width { data = data[len(data)-width:] }

	// Map -100..-30 to 0..7
	var sb strings.Builder
	for _, v := range data {
		normalized := (v + 100) / 70.0 // -100->0, -30->1
		if normalized < 0 { normalized = 0 }
		if normalized > 1 { normalized = 1 }
		idx := int(normalized * 7)
		if idx > 7 { idx = 7 }
		sb.WriteRune(chars[idx])
	}
	return accentStyle.Render(sb.String())
}

func miniBar(value, maxVal float64) string {
	if maxVal <= 0 { maxVal = 1 }
	pct := value / maxVal
	if pct > 1 { pct = 1 }
	filled := int(pct * 10)
	return accentStyle.Render(strings.Repeat("▮", filled) + strings.Repeat("▯", 10-filled))
}

func formatRate(mb float64) string {
	if mb < 0.001 { return dimStyle.Render("0 B/s") }
	if mb < 1 { return fmt.Sprintf("%.0f KB/s", mb*1024) }
	return fmt.Sprintf("%.2f MB/s", mb)
}

func truncate(s string, maxLen int) string {
	if len(s) <= maxLen { return s }
	return s[:maxLen-1] + "~"
}

func buildChannelMap(current WifiInfo, nearby []NearbyNetwork) []string {
	// Show 2.4GHz and 5GHz channel utilization.
	ch24 := make(map[int]int) // channel -> count
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
		line24 := "2.4GHz: "
		for ch := 1; ch <= 13; ch++ {
			cnt := ch24[ch]
			label := fmt.Sprintf("%2d", ch)
			if cnt == 0 {
				line24 += dimStyle.Render(label) + " "
			} else if cnt == 1 {
				line24 += greenStyle.Render(label) + " "
			} else {
				line24 += redStyle.Render(label) + " "
			}
		}
		lines = append(lines, line24)
	}

	if len(ch5) > 0 {
		line5 := "5GHz:   "
		for _, ch := range []int{36, 40, 44, 48, 52, 56, 60, 64, 100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 149, 153, 157, 161, 165} {
			cnt := ch5[ch]
			label := fmt.Sprintf("%3d", ch)
			if cnt == 0 {
				line5 += dimStyle.Render(label) + " "
			} else if cnt == 1 {
				line5 += greenStyle.Render(label) + " "
			} else {
				line5 += yellowStyle.Render(label) + " "
			}
		}
		lines = append(lines, line5)
	}

	if len(lines) == 0 {
		lines = append(lines, dimStyle.Render("No channel data available"))
	}
	return lines
}

func min(a, b int) int {
	if a < b { return a }
	return b
}
