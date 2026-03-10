#!/bin/bash
# Network Diagnostics Module
# Comprehensive local network visibility inspired by Sniffnet.
# Covers: interfaces, LAN devices, active connections, open ports, Wi-Fi info.

set -uo pipefail

# ============================================================================
# Common MAC OUI vendor lookup (top 30 manufacturers, offline)
# ============================================================================

lookup_mac_vendor() {
    local mac="$1"
    # Normalize: uppercase, first 3 octets
    local oui
    oui=$(echo "$mac" | tr '[:lower:]' '[:upper:]' | cut -d: -f1-3 | tr -d ':')

    case "$oui" in
        # Apple
        F4D488|3C22FB|A4B197|28CF|A860B6|D0*) echo "Apple" ;;
        # Samsung
        00166C|8CC8CD|7811DC|B47443) echo "Samsung" ;;
        # Google/Nest
        F4F5D8|A47733|546009|F8*) echo "Google" ;;
        # Amazon
        F0272D|747548|6854FD|40B4CD) echo "Amazon" ;;
        # AVM (Fritz!Box)
        04B4FE|3C4E47|2C3AFD|C80E14|244E7B) echo "AVM Fritz" ;;
        # Sonos
        B8E937|949F3E|347E5C) echo "Sonos" ;;
        # TP-Link
        50C7BF|6466B3|300D43) echo "TP-Link" ;;
        # Intel
        001517|3C970E|8086F2) echo "Intel" ;;
        # Raspberry Pi
        B827EB|D83ADD|DC26|E45F01) echo "Raspberry Pi" ;;
        # Philips Hue
        001788|ECBA) echo "Philips Hue" ;;
        # Microsoft
        001DD8|0050F2|7C1E52) echo "Microsoft" ;;
        # Broadcom
        0010*|2053*) echo "Broadcom" ;;
        # Broadcast
        FFFFFF) echo "Broadcast" ;;
        # Multicast
        0100*) echo "Multicast" ;;
        # Private/random MAC (locally administered bit set)
        *)
            # Check if bit 1 of first octet is set (locally administered = randomized)
            local first_byte
            first_byte=$(echo "$oui" | cut -c1-2)
            local first_dec
            first_dec=$(printf '%d' "0x${first_byte}" 2>/dev/null || echo 0)
            if (( (first_dec & 2) != 0 )); then
                echo "Private MAC"
            else
                echo ""
            fi
            ;;
    esac
}

# ============================================================================
# Network Interfaces
# ============================================================================

show_interfaces() {
    echo -e "${BLUE}${ICON_ARROW}${NC} Network Interfaces"
    echo ""

    # Active interfaces with IPs
    local found=0
    while IFS= read -r line; do
        local iface ip
        iface=$(echo "$line" | awk -F: '{print $1}' | tr -d '[:space:]')
        ip=$(ipconfig getifaddr "$iface" 2>/dev/null || echo "")
        [[ -z "$ip" ]] && continue

        local mac
        mac=$(ifconfig "$iface" 2>/dev/null | grep ether | awk '{print $2}' || echo "")

        # Interface type
        local iface_type="Ethernet"
        [[ "$iface" == "en0" ]] && iface_type="Wi-Fi"
        [[ "$iface" == "utun"* ]] && iface_type="VPN"
        [[ "$iface" == "bridge"* ]] && iface_type="Bridge"
        [[ "$iface" == "lo"* ]] && iface_type="Loopback"

        printf "  ${GREEN}${ICON_SOLID}${NC} %-8s  %-16s  %-18s  %s\n" "$iface" "$ip" "${mac:-n/a}" "$iface_type"
        found=$((found + 1))
    done < <(ifconfig -l 2>/dev/null | tr ' ' '\n' | while read -r ifc; do echo "$ifc:"; done)

    # VPN interfaces
    while IFS= read -r line; do
        local iface ip
        iface=$(echo "$line" | awk '{print $1}' | tr -d ':')
        [[ "$iface" == utun* ]] || continue
        ip=$(ifconfig "$iface" 2>/dev/null | grep "inet " | awk '{print $2}' | head -1 || echo "")
        [[ -z "$ip" ]] && continue

        printf "  ${CYAN}${ICON_SOLID}${NC} %-8s  %-16s  %-18s  %s\n" "$iface" "$ip" "" "VPN tunnel"
        found=$((found + 1))
    done < <(ifconfig 2>/dev/null | grep "^utun")

    [[ $found -eq 0 ]] && echo -e "  ${YELLOW}No active interfaces${NC}"
}

# ============================================================================
# Wi-Fi Details
# ============================================================================

show_wifi_info() {
    echo ""
    echo -e "${BLUE}${ICON_ARROW}${NC} Wi-Fi Details"
    echo ""

    # Use system_profiler (works on all macOS versions)
    local wifi_info
    wifi_info=$(system_profiler SPAirPortDataType 2>/dev/null || echo "")
    if [[ -z "$wifi_info" ]]; then
        echo -e "  ${GRAY}Wi-Fi information unavailable${NC}"
        return
    fi

    # Check if connected
    local current_network
    current_network=$(echo "$wifi_info" | grep -A30 "Current Network Information:" || echo "")
    if [[ -z "$current_network" ]]; then
        echo -e "  ${GRAY}Wi-Fi not connected${NC}"
        return
    fi

    local ssid channel security phy_mode
    ssid=$(echo "$current_network" | head -2 | tail -1 | sed 's/^[[:space:]]*//' | sed 's/:$//' || true)
    channel=$(echo "$current_network" | grep "Channel:" 2>/dev/null | awk '{print $2}' | head -1 || true)
    security=$(echo "$current_network" | grep "Security:" 2>/dev/null | awk '{$1=""; print $0}' | sed 's/^ //' | head -1 || true)
    phy_mode=$(echo "$current_network" | grep "PHY Mode:" 2>/dev/null | awk '{$1=""; $2=""; print $0}' | sed 's/^ //' | head -1 || true)

    # Signal strength (wdutil requires sudo, skip if not available)
    local rssi="" noise="" txrate=""

    # Signal quality indicator
    local signal_quality="Unknown"
    local signal_color="${GRAY}"
    if [[ -n "$rssi" && "$rssi" =~ ^-?[0-9]+$ ]]; then
        if [[ $rssi -gt -50 ]]; then
            signal_quality="Excellent"
            signal_color="${GREEN}"
        elif [[ $rssi -gt -60 ]]; then
            signal_quality="Good"
            signal_color="${GREEN}"
        elif [[ $rssi -gt -70 ]]; then
            signal_quality="Fair"
            signal_color="${YELLOW}"
        else
            signal_quality="Weak"
            signal_color="${RED}"
        fi
    fi

    echo -e "  SSID:        ${GREEN}${ssid:-n/a}${NC}"
    if [[ -n "$rssi" ]]; then
        echo -e "  Signal:      ${signal_color}${signal_quality}${NC} (${rssi} dBm${noise:+, noise ${noise} dBm})"
    fi
    echo -e "  Channel:     ${channel:-n/a}"
    echo -e "  Security:    ${security:-n/a}"
    [[ -n "$phy_mode" ]] && echo -e "  PHY Mode:    ${phy_mode}"
    [[ -n "$txrate" ]] && echo -e "  Tx Rate:     ${txrate} Mbps"
}

# ============================================================================
# LAN Device Discovery (ARP + nmap)
# ============================================================================

show_lan_devices() {
    echo ""
    echo -e "${BLUE}${ICON_ARROW}${NC} Local Network Devices"
    echo ""

    local local_ip
    local_ip=$(ipconfig getifaddr en0 2>/dev/null || echo "")
    if [[ -z "$local_ip" ]]; then
        echo -e "  ${GRAY}No active Wi-Fi interface${NC}"
        return
    fi

    local subnet
    subnet=$(echo "$local_ip" | sed 's/\.[0-9]*$/.0\/24/')

    # Phase 1: ARP table (instant, shows cached + recently seen devices)
    local -a devices=()
    local device_count=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" == *"incomplete"* ]] && continue
        [[ "$line" == *"ff:ff:ff:ff:ff:ff"* ]] && continue
        [[ "$line" == *"01:00:5e"* ]] && continue

        local ip mac
        ip=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        mac=$(echo "$line" | grep -oE '([0-9a-f]{1,2}:){5}[0-9a-f]{1,2}' | head -1)

        [[ -z "$ip" || -z "$mac" ]] && continue

        local vendor hostname
        vendor=$(lookup_mac_vendor "$mac")
        hostname=""

        # Try reverse DNS
        hostname=$(host "$ip" 2>/dev/null | grep "domain name pointer" | awk '{print $NF}' | sed 's/\.$//' | head -1 || echo "")

        # Mark self
        local self_marker=""
        [[ "$ip" == "$local_ip" ]] && self_marker=" ${CYAN}(this Mac)${NC}"

        # Mark gateway
        local gw
        gw=$(route -n get default 2>/dev/null | grep gateway | awk '{print $2}' || echo "")
        [[ "$ip" == "$gw" ]] && self_marker=" ${PURPLE}(gateway)${NC}"

        local display_name="${hostname:-$ip}"
        local vendor_str=""
        [[ -n "$vendor" ]] && vendor_str="${GRAY}${vendor}${NC}"

        printf "  ${GREEN}${ICON_LIST}${NC} %-16s  %-18s  %-14b%b\n" "$ip" "$mac" "$vendor_str" "$self_marker"
        if [[ -n "$hostname" && "$hostname" != "$ip" ]]; then
            echo -e "    ${GRAY}${ICON_SUBLIST} ${hostname}${NC}"
        fi

        device_count=$((device_count + 1))
    done < <(arp -a 2>/dev/null)

    echo ""
    echo -e "  ${GRAY}Found ${device_count} devices in ARP cache${NC}"

    # Phase 2: Deep scan with nmap (if available)
    if command -v nmap > /dev/null 2>&1; then
        echo ""
        echo -e "${BLUE}${ICON_ARROW}${NC} Deep Network Scan (nmap)"
        echo ""

        if [[ -t 1 ]]; then
            MOLE_SPINNER_PREFIX="  " start_inline_spinner "Scanning $subnet (host discovery + service detection)..."
        fi

        # -sn: ping scan (host discovery), -sV: service detection on common ports
        # --open: only show open ports
        local nmap_output
        nmap_output=$(run_with_timeout 60 nmap -sn "$subnet" 2>/dev/null || echo "")

        if [[ -t 1 ]]; then
            stop_inline_spinner
        fi

        if [[ -n "$nmap_output" ]]; then
            local nmap_hosts=0
            local nmap_hidden=0

            while IFS= read -r report_line; do
                local host_ip host_mac host_vendor host_latency
                host_ip=$(echo "$report_line" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
                [[ -z "$host_ip" ]] && continue

                # Get the lines after this report for MAC and latency
                local host_block
                host_block=$(echo "$nmap_output" | grep -A3 "Nmap scan report for.*$host_ip")

                host_mac=$(echo "$host_block" | grep "MAC Address:" | grep -oE '([0-9A-F]{2}:){5}[0-9A-F]{2}' || echo "")
                host_vendor=$(echo "$host_block" | grep "MAC Address:" | sed 's/.*(\(.*\))/\1/' || echo "")
                host_latency=$(echo "$host_block" | grep "Host is up" | grep -oE '[0-9.]+s' | head -1 || echo "")

                # Check if this device was NOT in the ARP cache (hidden device)
                local in_arp
                in_arp=$(arp -a 2>/dev/null | grep "$host_ip" | grep -v incomplete || echo "")
                local hidden_tag=""
                if [[ -z "$in_arp" && "$host_ip" != "$local_ip" ]]; then
                    hidden_tag=" ${RED}[hidden]${NC}"
                    nmap_hidden=$((nmap_hidden + 1))
                fi

                local vendor_display=""
                [[ -n "$host_vendor" && "$host_vendor" != "$host_ip" ]] && vendor_display="${GRAY}${host_vendor}${NC}"
                [[ -z "$vendor_display" && -n "$host_mac" ]] && vendor_display="${GRAY}$(lookup_mac_vendor "$host_mac")${NC}"

                printf "  ${ICON_LIST} %-16s  %-18s  %-20b%b\n" "$host_ip" "${host_mac:-local}" "$vendor_display" "$hidden_tag"

                if [[ -n "$host_latency" ]]; then
                    echo -e "    ${GRAY}${ICON_SUBLIST} latency: ${host_latency}${NC}"
                fi

                nmap_hosts=$((nmap_hosts + 1))
            done < <(echo "$nmap_output" | grep "Nmap scan report")

            echo ""
            echo -e "  ${GRAY}nmap found ${nmap_hosts} hosts${NC}"
            if [[ $nmap_hidden -gt 0 ]]; then
                echo -e "  ${RED}${nmap_hidden} hidden devices${NC} (not in ARP cache, possibly stealth)"
            fi
        fi
    else
        echo ""
        echo -e "  ${GRAY}Install nmap for deep scan: brew install nmap${NC}"
    fi
}

# ============================================================================
# Active Connections Summary
# ============================================================================

show_active_connections() {
    echo ""
    echo -e "${BLUE}${ICON_ARROW}${NC} Active Connections"
    echo ""

    local lsof_output
    lsof_output=$(lsof -iTCP -sTCP:ESTABLISHED -P -n 2>/dev/null || echo "")
    if [[ -z "$lsof_output" ]]; then
        echo -e "  ${GRAY}No active TCP connections${NC}"
        return
    fi

    # Aggregate by process using awk (Bash 3.2 compatible -- no associative arrays)
    local aggregated
    aggregated=$(echo "$lsof_output" | awk '
        NR == 1 { next }
        {
            proc = $1
            # Extract remote IP from field 9
            split($9, parts, "->")
            if (length(parts) < 2) next
            split(parts[2], addr, ":")
            ip = addr[1]
            if (ip == "127.0.0.1" || ip == "::1") next

            counts[proc]++
            total++
            if (!(proc in ips_seen) || index(ips_seen[proc], ip) == 0) {
                if (ips_seen[proc] != "") ips_seen[proc] = ips_seen[proc] ","
                ips_seen[proc] = ips_seen[proc] ip
            }
        }
        END {
            for (p in counts) {
                print counts[p] "|" p "|" ips_seen[p]
            }
            print "TOTAL|" total+0
        }
    ' 2>/dev/null | sort -t'|' -k1 -nr)

    printf "  ${GRAY}%-20s  %5s  %s${NC}\n" "PROCESS" "CONNS" "REMOTE IPs"
    echo -e "  ${GRAY}$(printf '%.0s-' {1..65})${NC}"

    local shown=0
    local total_connections=0
    local proc_count=0
    while IFS='|' read -r count proc ips; do
        if [[ "$count" == "TOTAL" ]]; then
            total_connections="$proc"
            continue
        fi
        [[ -z "$proc" ]] && continue

        # Show first 3 IPs
        local display_ips
        display_ips=$(echo "$ips" | tr ',' '\n' | head -3 | tr '\n' ', ' | sed 's/,$//')
        local ip_count
        ip_count=$(echo "$ips" | tr ',' '\n' | wc -l | tr -d ' ')
        [[ $ip_count -gt 3 ]] && display_ips="${display_ips} +$((ip_count - 3)) more"

        printf "  %-20s  %5s  %s\n" "$proc" "$count" "$display_ips"
        shown=$((shown + 1))
        proc_count=$((proc_count + 1))
        [[ $shown -ge 15 ]] && break
    done <<< "$aggregated"

    echo ""
    echo -e "  ${GRAY}Total: ${total_connections} connections across ${proc_count} processes${NC}"
}

# ============================================================================
# Listening Ports
# ============================================================================

show_listening_ports() {
    echo ""
    echo -e "${BLUE}${ICON_ARROW}${NC} Listening Ports"
    echo ""

    local listen_output
    listen_output=$(lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null || echo "")
    if [[ -z "$listen_output" ]]; then
        echo -e "  ${GRAY}No listening ports${NC}"
        return
    fi

    printf "  ${GRAY}%-16s  %6s  %s${NC}\n" "PROCESS" "PORT" "ADDRESS"
    echo -e "  ${GRAY}$(printf '%.0s-' {1..50})${NC}"

    # Deduplicate using awk (Bash 3.2 compatible)
    echo "$listen_output" | awk '
        NR == 1 { next }
        {
            proc = $1
            name = $9
            # Extract port from last colon
            n = split(name, parts, ":")
            port = parts[n]
            addr = parts[1]

            key = proc ":" port
            if (!(key in seen)) {
                seen[key] = 1
                addr_display = "localhost"
                if (addr == "*") addr_display = "all interfaces"
                printf "  %-16s  %6s  %s\n", proc, port, addr_display
            }
        }
    '
}

# ============================================================================
# DNS Leak / External IP Check
# ============================================================================

show_external_info() {
    echo ""
    echo -e "${BLUE}${ICON_ARROW}${NC} External Connectivity"
    echo ""

    # External IP (via DNS - fast, no HTTP)
    local external_ip
    external_ip=$(run_with_timeout 5 dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null || echo "")
    if [[ -n "$external_ip" ]]; then
        echo -e "  External IP:   ${GREEN}${external_ip}${NC}"

        # Check if going through VPN
        if ifconfig -l 2>/dev/null | grep -q "utun"; then
            echo -e "  VPN:           ${CYAN}Active${NC} (traffic routed through VPN)"
        else
            echo -e "  VPN:           ${GRAY}Not detected${NC}"
        fi
    else
        echo -e "  External IP:   ${YELLOW}Could not determine${NC}"
    fi

    # DNS resolver check
    local dns_test
    dns_test=$(run_with_timeout 5 dig +short google.com 2>/dev/null || echo "")
    if [[ -n "$dns_test" ]]; then
        echo -e "  DNS:           ${GREEN}Resolving${NC}"
    else
        echo -e "  DNS:           ${RED}Not resolving${NC}"
    fi

    # Latency to common endpoints
    local gw_latency
    local gw
    gw=$(route -n get default 2>/dev/null | grep gateway | awk '{print $2}' || echo "")
    if [[ -n "$gw" ]]; then
        gw_latency=$(ping -c 1 -W 2 "$gw" 2>/dev/null | grep "time=" | grep -oE 'time=[0-9.]+' | cut -d= -f2 || echo "")
        if [[ -n "$gw_latency" ]]; then
            echo -e "  Gateway ping:  ${GREEN}${gw_latency} ms${NC} ($gw)"
        fi
    fi

    local inet_latency
    inet_latency=$(run_with_timeout 5 ping -c 1 -W 2 8.8.8.8 2>/dev/null | grep "time=" | grep -oE 'time=[0-9.]+' | cut -d= -f2 || echo "")
    if [[ -n "$inet_latency" ]]; then
        echo -e "  Internet ping: ${GREEN}${inet_latency} ms${NC} (8.8.8.8)"
    else
        echo -e "  Internet ping: ${RED}Unreachable${NC}"
    fi
}

# ============================================================================
# Port Scan of a Specific Host
# ============================================================================

scan_host() {
    local target_ip="$1"

    if ! command -v nmap > /dev/null 2>&1; then
        echo -e "  ${GRAY}nmap required for host scanning (brew install nmap)${NC}"
        return
    fi

    echo ""
    echo -e "${BLUE}${ICON_ARROW}${NC} Scanning Host: ${target_ip}"
    echo ""

    if [[ -t 1 ]]; then
        MOLE_SPINNER_PREFIX="  " start_inline_spinner "Scanning ${target_ip} (service detection)..."
    fi

    local scan_output
    scan_output=$(run_with_timeout 60 nmap -sV --open -T4 "$target_ip" 2>/dev/null || echo "")

    if [[ -t 1 ]]; then
        stop_inline_spinner
    fi

    if [[ -z "$scan_output" ]]; then
        echo -e "  ${YELLOW}Host did not respond to scan${NC}"
        return
    fi

    # Parse open ports
    local ports_found=0
    while IFS= read -r line; do
        if echo "$line" | grep -qE '^[0-9]+/'; then
            local port proto state service version
            port=$(echo "$line" | awk '{print $1}')
            state=$(echo "$line" | awk '{print $2}')
            service=$(echo "$line" | awk '{print $3}')
            version=$(echo "$line" | awk '{$1=$2=$3=""; print $0}' | sed 's/^ *//')

            printf "  ${GREEN}${ICON_LIST}${NC} %-12s  %-8s  %-14s  %s\n" "$port" "$state" "$service" "$version"
            ports_found=$((ports_found + 1))
        fi
    done <<< "$scan_output"

    if [[ $ports_found -eq 0 ]]; then
        echo -e "  ${GRAY}No open ports detected${NC}"
    else
        echo ""
        echo -e "  ${GRAY}Found ${ports_found} open ports${NC}"
    fi

    # OS detection hint (from MAC)
    local target_mac
    target_mac=$(arp -a 2>/dev/null | grep "$target_ip" | grep -oE '([0-9a-f]{1,2}:){5}[0-9a-f]{1,2}' || echo "")
    if [[ -n "$target_mac" ]]; then
        local vendor
        vendor=$(lookup_mac_vendor "$target_mac")
        [[ -n "$vendor" ]] && echo -e "  ${GRAY}Vendor: ${vendor} (${target_mac})${NC}"
    fi
}

# ============================================================================
# Full Network Report
# ============================================================================

network_full_report() {
    show_interfaces
    show_wifi_info
    show_lan_devices
    show_active_connections
    show_listening_ports
    show_external_info
}

# ============================================================================
# Summary
# ============================================================================

show_network_summary() {
    local iface_count
    iface_count=$(ifconfig -l 2>/dev/null | tr ' ' '\n' | while read -r ifc; do
        ipconfig getifaddr "$ifc" 2>/dev/null && echo "$ifc"
    done | wc -l | tr -d ' ')

    local arp_count
    arp_count=$(arp -a 2>/dev/null | grep -v "incomplete\|ff:ff:ff:ff\|01:00:5e" | wc -l | tr -d ' ')

    local conn_count
    conn_count=$(lsof -iTCP -sTCP:ESTABLISHED -P -n 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')

    local listen_count
    listen_count=$(lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null | tail -n +2 | awk '{print $1":"$9}' | sort -u | wc -l | tr -d ' ')

    local -a details=()
    details+=("Active interfaces: ${iface_count}")
    details+=("LAN devices (ARP): ${arp_count}")
    details+=("TCP connections: ${conn_count}")
    details+=("Listening ports: ${listen_count}")

    print_summary_block "Network Diagnostics Complete" "${details[@]}"
}
