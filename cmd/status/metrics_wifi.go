package main

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"time"
)

// collectWifi gathers Wi-Fi connection details from system_profiler and ARP cache.
func collectWifi() WifiStatus {
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	// Get Wi-Fi info from system_profiler.
	out, err := runCmd(ctx, "system_profiler", "SPAirPortDataType")
	if err != nil || out == "" {
		return WifiStatus{Connected: false}
	}

	// Find the "Status: Connected" line to confirm Wi-Fi is active.
	if !strings.Contains(out, "Status: Connected") {
		return WifiStatus{Connected: false}
	}

	// Find the first "Current Network Information:" section.
	idx := strings.Index(out, "Current Network Information:")
	if idx < 0 {
		return WifiStatus{Connected: false}
	}

	// Extract the section (up to "Other Local Wi-Fi Networks:" or end).
	section := out[idx:]
	if endIdx := strings.Index(section, "Other Local Wi-Fi Networks:"); endIdx > 0 {
		section = section[:endIdx]
	}

	wifi := WifiStatus{Connected: true}
	lines := strings.Split(section, "\n")

	// SSID is the line after "Current Network Information:"
	// It may show as "<redacted>" for privacy, which is fine.
	if len(lines) > 1 {
		ssid := strings.TrimSpace(lines[1])
		ssid = strings.TrimSuffix(ssid, ":")
		if ssid == "<redacted>" {
			// Use networksetup which doesn't censor the SSID.
			ssid = getSSIDViaNetworkSetup()
		}
		wifi.SSID = ssid
	}

	// Parse key: value fields from the section.
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "Channel:") {
			wifi.Channel = strings.TrimSpace(strings.TrimPrefix(trimmed, "Channel:"))
		} else if strings.HasPrefix(trimmed, "Security:") {
			wifi.Security = strings.TrimSpace(strings.TrimPrefix(trimmed, "Security:"))
		} else if strings.HasPrefix(trimmed, "PHY Mode:") {
			wifi.PHYMode = strings.TrimSpace(strings.TrimPrefix(trimmed, "PHY Mode:"))
		} else if strings.HasPrefix(trimmed, "Signal / Noise:") {
			parseSignalNoise(trimmed, &wifi)
		} else if strings.HasPrefix(trimmed, "Transmit Rate:") {
			// Not stored yet, but available.
		}
	}

	// Get LAN device count from ARP cache.
	wifi.LANDevices = countLANDevices()

	// Set signal quality label based on RSSI.
	if wifi.SignalDBm != 0 {
		wifi.SignalLabel = signalQualityLabel(wifi.SignalDBm)
	}

	return wifi
}

// getSSIDViaNetworkSetup uses networksetup to get the SSID when system_profiler redacts it.
func getSSIDViaNetworkSetup() string {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	out, err := runCmd(ctx, "networksetup", "-getairportnetwork", "en0")
	if err != nil {
		return ""
	}
	// Output: "Current Wi-Fi Network: MyNetwork"
	if idx := strings.Index(out, ":"); idx >= 0 {
		return strings.TrimSpace(out[idx+1:])
	}
	return ""
}

// parseSignalNoise extracts RSSI and noise from "Signal / Noise: -77 dBm / -92 dBm".
func parseSignalNoise(line string, wifi *WifiStatus) {
	parts := strings.SplitN(line, ":", 2)
	if len(parts) < 2 {
		return
	}
	vals := strings.Split(parts[1], "/")
	if len(vals) >= 1 {
		rssi := strings.TrimSpace(vals[0])
		rssi = strings.TrimSuffix(rssi, " dBm")
		rssi = strings.TrimSpace(rssi)
		if v, err := strconv.Atoi(rssi); err == nil {
			wifi.SignalDBm = v
		}
	}
	if len(vals) >= 2 {
		noise := strings.TrimSpace(vals[1])
		noise = strings.TrimSuffix(noise, " dBm")
		noise = strings.TrimSpace(noise)
		if v, err := strconv.Atoi(noise); err == nil {
			wifi.NoiseDBm = v
		}
	}
}

// signalQualityLabel returns a human label for the RSSI value.
func signalQualityLabel(rssi int) string {
	switch {
	case rssi > -50:
		return "Excellent"
	case rssi > -60:
		return "Good"
	case rssi > -70:
		return "Fair"
	default:
		return "Weak"
	}
}

// countLANDevices counts active devices from the ARP cache.
func countLANDevices() int {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	out, err := runCmd(ctx, "arp", "-a")
	if err != nil {
		return 0
	}

	count := 0
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		// Skip incomplete, broadcast, and multicast entries.
		if strings.Contains(line, "incomplete") ||
			strings.Contains(line, "ff:ff:ff:ff:ff:ff") ||
			strings.Contains(line, "01:00:5e") {
			continue
		}
		// Must contain a MAC address (5+ colons).
		if colonCount(line) >= 5 {
			count++
		}
	}
	return count
}

// colonCount returns the number of colons in a string (cheap MAC heuristic).
func colonCount(s string) int {
	n := 0
	for _, c := range s {
		if c == ':' {
			n++
		}
	}
	return n
}

// wifiSignalBar returns a mini bar representation of Wi-Fi signal strength.
func wifiSignalBar(rssi int) string {
	// Map RSSI (-100 to -30) to 0-5 bars.
	bars := 0
	switch {
	case rssi > -45:
		bars = 5
	case rssi > -55:
		bars = 4
	case rssi > -65:
		bars = 3
	case rssi > -75:
		bars = 2
	case rssi > -85:
		bars = 1
	}
	return fmt.Sprintf("%s (%d dBm)", strings.Repeat("▮", bars)+strings.Repeat("▯", 5-bars), rssi)
}
