package main

// NetworkSnapshot holds all collected data for one refresh cycle.
type NetworkSnapshot struct {
	Interfaces  []InterfaceInfo  `json:"interfaces"`
	Wifi        WifiInfo         `json:"wifi"`
	NearbyNets  []NearbyNetwork  `json:"nearby_nets"`
	LANDevices  []LANDevice      `json:"lan_devices"`
	Connections []ConnectionInfo `json:"connections"`
	Listeners   []ListenerInfo   `json:"listeners"`
	TrafficRx   float64          `json:"traffic_rx_mbs"` // Total Rx MB/s
	TrafficTx   float64          `json:"traffic_tx_mbs"` // Total Tx MB/s
	ExternalIP  string           `json:"external_ip"`
	VPNActive   bool             `json:"vpn_active"`
	DNSOk       bool             `json:"dns_ok"`
	GatewayIP   string           `json:"gateway_ip"`
	GatewayMs   float64          `json:"gateway_ms"`
	InternetMs  float64          `json:"internet_ms"`
}

// InterfaceInfo represents a network interface.
type InterfaceInfo struct {
	Name      string  `json:"name"`
	IP        string  `json:"ip"`
	MAC       string  `json:"mac"`
	Type      string  `json:"type"` // Wi-Fi, Ethernet, VPN, Loopback
	RxRateMBs float64 `json:"rx_rate_mbs"`
	TxRateMBs float64 `json:"tx_rate_mbs"`
}

// WifiInfo holds current Wi-Fi connection details.
type WifiInfo struct {
	Connected bool    `json:"connected"`
	SSID      string  `json:"ssid"`
	Channel   string  `json:"channel"`
	Band      string  `json:"band"`     // 5GHz, 2.4GHz
	Security  string  `json:"security"` // WPA2, WPA3, etc.
	PHYMode   string  `json:"phy_mode"` // 802.11ax, etc.
	SignalDBm int     `json:"signal_dbm"`
	NoiseDBm  int     `json:"noise_dbm"`
	TxRate    int     `json:"tx_rate"`
	SNR       int     `json:"snr"` // Signal-to-noise ratio
	Quality   string  `json:"quality"`
	BSSID     string  `json:"bssid"`
}

// NearbyNetwork represents a detected Wi-Fi network.
type NearbyNetwork struct {
	SSID      string `json:"ssid"`
	Channel   string `json:"channel"`
	Band      string `json:"band"`
	PHYMode   string `json:"phy_mode"`
	Security  string `json:"security"`
	SignalDBm int    `json:"signal_dbm"`
}

// LANDevice represents a device on the local network.
type LANDevice struct {
	IP       string `json:"ip"`
	MAC      string `json:"mac"`
	Vendor   string `json:"vendor"`
	Hostname string `json:"hostname"`
	IsGateway bool  `json:"is_gateway"`
	IsSelf    bool  `json:"is_self"`
	IsHidden  bool  `json:"is_hidden"` // Found by nmap but not in ARP
	Latency  string `json:"latency"`
}

// ConnectionInfo represents an active TCP connection.
type ConnectionInfo struct {
	Process   string `json:"process"`
	PID       int    `json:"pid"`
	LocalAddr string `json:"local_addr"`
	LocalPort int    `json:"local_port"`
	RemoteIP  string `json:"remote_ip"`
	RemotePort int   `json:"remote_port"`
	State     string `json:"state"`
	Hostname  string `json:"hostname"` // Reverse DNS
}

// ListenerInfo represents a listening port.
type ListenerInfo struct {
	Process string `json:"process"`
	PID     int    `json:"pid"`
	Port    int    `json:"port"`
	Addr    string `json:"addr"`
}

// TrafficHistory holds sparkline data.
type TrafficHistory struct {
	RxHistory []float64
	TxHistory []float64
}

// ProcessTraffic aggregates traffic by process.
type ProcessTraffic struct {
	Name  string
	Conns int
	IPs   []string
}

// SignalHistory holds Wi-Fi signal readings over time.
type SignalHistory struct {
	DBmHistory []float64
	SNRHistory []float64
}
