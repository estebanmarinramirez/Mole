package main

import (
	"context"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

// collectWifiInfo gathers Wi-Fi and nearby network details from system_profiler.
func collectWifiInfo() (WifiInfo, []NearbyNetwork) {
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	out, err := exec.CommandContext(ctx, "system_profiler", "SPAirPortDataType").Output()
	if err != nil || len(out) == 0 {
		return WifiInfo{Connected: false}, nil
	}
	text := string(out)

	if !strings.Contains(text, "Status: Connected") {
		return WifiInfo{Connected: false}, nil
	}

	wifi := parseCurrentNetwork(text)
	nearby := parseNearbyNetworks(text)
	return wifi, nearby
}

func parseCurrentNetwork(text string) WifiInfo {
	idx := strings.Index(text, "Current Network Information:")
	if idx < 0 {
		return WifiInfo{Connected: false}
	}

	section := text[idx:]
	// Limit to current network section.
	if end := strings.Index(section, "Other Local Wi-Fi Networks:"); end > 0 {
		section = section[:end]
	}

	wifi := WifiInfo{Connected: true}
	lines := strings.Split(section, "\n")

	// SSID is the first indented line after the header.
	if len(lines) > 1 {
		ssid := strings.TrimSpace(lines[1])
		ssid = strings.TrimSuffix(ssid, ":")
		if ssid != "<redacted>" && ssid != "" {
			wifi.SSID = ssid
		} else {
			wifi.SSID = getSSID()
		}
	}

	for _, line := range lines {
		t := strings.TrimSpace(line)
		switch {
		case strings.HasPrefix(t, "Channel:"):
			wifi.Channel = strings.TrimSpace(strings.TrimPrefix(t, "Channel:"))
			if strings.Contains(wifi.Channel, "5GHz") {
				wifi.Band = "5GHz"
			} else if strings.Contains(wifi.Channel, "2GHz") {
				wifi.Band = "2.4GHz"
			}
		case strings.HasPrefix(t, "Security:"):
			wifi.Security = strings.TrimSpace(strings.TrimPrefix(t, "Security:"))
		case strings.HasPrefix(t, "PHY Mode:"):
			wifi.PHYMode = strings.TrimSpace(strings.TrimPrefix(t, "PHY Mode:"))
		case strings.HasPrefix(t, "Signal / Noise:"):
			parseSignal(t, &wifi)
		case strings.HasPrefix(t, "Transmit Rate:"):
			v, _ := strconv.Atoi(strings.TrimSpace(strings.TrimPrefix(t, "Transmit Rate:")))
			wifi.TxRate = v
		case strings.HasPrefix(t, "BSSID:"):
			wifi.BSSID = strings.TrimSpace(strings.TrimPrefix(t, "BSSID:"))
		}
	}

	if wifi.SignalDBm != 0 && wifi.NoiseDBm != 0 {
		wifi.SNR = wifi.SignalDBm - wifi.NoiseDBm
	}
	wifi.Quality = signalLabel(wifi.SignalDBm)
	return wifi
}

func parseSignal(line string, wifi *WifiInfo) {
	parts := strings.SplitN(line, ":", 2)
	if len(parts) < 2 { return }
	vals := strings.Split(parts[1], "/")
	if len(vals) >= 1 {
		s := strings.TrimSpace(vals[0])
		s = strings.TrimSuffix(s, " dBm")
		s = strings.TrimSpace(s)
		if v, err := strconv.Atoi(s); err == nil {
			wifi.SignalDBm = v
		}
	}
	if len(vals) >= 2 {
		s := strings.TrimSpace(vals[1])
		s = strings.TrimSuffix(s, " dBm")
		s = strings.TrimSpace(s)
		if v, err := strconv.Atoi(s); err == nil {
			wifi.NoiseDBm = v
		}
	}
}

func parseNearbyNetworks(text string) []NearbyNetwork {
	idx := strings.Index(text, "Other Local Wi-Fi Networks:")
	if idx < 0 { return nil }

	section := text[idx+len("Other Local Wi-Fi Networks:"):]
	// End at next major section or interface.
	for _, marker := range []string{"Wi-Fi:", "Interfaces:", "Software Versions:"} {
		if end := strings.Index(section, marker); end > 0 {
			section = section[:end]
		}
	}

	var nets []NearbyNetwork
	var current *NearbyNetwork
	lines := strings.Split(section, "\n")

	for _, line := range lines {
		t := strings.TrimSpace(line)
		if t == "" { continue }

		// Network names are less indented than their properties.
		indent := len(line) - len(strings.TrimLeft(line, " "))
		if indent <= 16 && strings.HasSuffix(t, ":") && !strings.Contains(t, ": ") {
			// New network entry.
			if current != nil {
				nets = append(nets, *current)
			}
			ssid := strings.TrimSuffix(t, ":")
			current = &NearbyNetwork{SSID: ssid}
			continue
		}

		if current == nil { continue }

		switch {
		case strings.HasPrefix(t, "Channel:"):
			current.Channel = strings.TrimSpace(strings.TrimPrefix(t, "Channel:"))
			if strings.Contains(current.Channel, "5GHz") {
				current.Band = "5GHz"
			} else if strings.Contains(current.Channel, "2GHz") {
				current.Band = "2.4GHz"
			}
		case strings.HasPrefix(t, "PHY Mode:"):
			current.PHYMode = strings.TrimSpace(strings.TrimPrefix(t, "PHY Mode:"))
		case strings.HasPrefix(t, "Security:"):
			current.Security = strings.TrimSpace(strings.TrimPrefix(t, "Security:"))
		case strings.HasPrefix(t, "Signal / Noise:"):
			parts := strings.SplitN(t, ":", 2)
			if len(parts) >= 2 {
				vals := strings.Split(parts[1], "/")
				if len(vals) >= 1 {
					s := strings.TrimSpace(vals[0])
					s = strings.TrimSuffix(s, " dBm")
					s = strings.TrimSpace(s)
					if v, err := strconv.Atoi(s); err == nil {
						current.SignalDBm = v
					}
				}
			}
		}
	}
	if current != nil && current.Channel != "" {
		nets = append(nets, *current)
	}

	// Filter out parse artifacts.
	var cleaned []NearbyNetwork
	for _, n := range nets {
		if n.Channel == "" || n.SignalDBm == 0 { continue }
		if strings.HasPrefix(n.SSID, "awdl") { continue }
		if strings.Contains(n.SSID, "Current Network") { continue }
		cleaned = append(cleaned, n)
	}
	return cleaned
}

func getSSID() string {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, "networksetup", "-getairportnetwork", "en0").Output()
	if err != nil { return "" }
	s := string(out)
	if idx := strings.Index(s, ":"); idx >= 0 {
		v := strings.TrimSpace(s[idx+1:])
		if !strings.Contains(v, "not associated") {
			return v
		}
	}
	return ""
}

func signalLabel(rssi int) string {
	if rssi == 0 { return "" }
	switch {
	case rssi > -50:  return "Excellent"
	case rssi > -60:  return "Good"
	case rssi > -70:  return "Fair"
	default:          return "Weak"
	}
}
