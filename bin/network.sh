#!/bin/bash
# Mole Network Diagnostics
# Comprehensive local network visibility.
# Usage: mo network [--scan <ip>] [--quick] [--debug]

set -uo pipefail

export LC_ALL=C
export LANG=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/core/common.sh"
source "$SCRIPT_DIR/lib/check/network.sh"
set +e  # Network diagnostics uses many grep pipes that may return non-zero

cleanup_all() {
    stop_inline_spinner 2>/dev/null || true
    cleanup_temp_files
}

handle_interrupt() {
    cleanup_all
    exit 130
}

show_network_help() {
    echo ""
    echo -e "${PURPLE_BOLD}Network Diagnostics${NC}"
    echo ""
    echo "  Comprehensive view of your local network, devices,"
    echo "  connections, and external connectivity."
    echo ""
    echo -e "${BLUE}Usage:${NC}"
    echo "  mo network               Full network report"
    echo "  mo network --ui          Interactive dashboard (TUI)"
    echo "  mo network --quick       Interfaces + Wi-Fi + LAN devices only"
    echo "  mo network --scan <ip>   Deep scan a specific host"
    echo "  mo network --connections Active connections by process"
    echo "  mo network --ports       Show listening ports"
    echo "  mo network --devices     LAN device discovery only"
    echo ""
    echo -e "${BLUE}Sections:${NC}"
    echo "  Interfaces       Active adapters with IPs and MACs"
    echo "  Wi-Fi            SSID, signal strength, channel, security"
    echo "  LAN Devices      ARP cache + nmap host discovery"
    echo "  Hidden Devices   Stealth hosts found by nmap but not in ARP"
    echo "  Connections      TCP connections grouped by process"
    echo "  Listening Ports  Services accepting connections"
    echo "  External         Public IP, VPN status, DNS, latency"
    echo ""
    echo -e "${BLUE}Requirements:${NC}"
    echo "  nmap             For deep scan/hidden devices (brew install nmap)"
    echo "  All other checks use built-in macOS tools"
    echo ""
}

main() {
    trap cleanup_all EXIT
    trap handle_interrupt INT TERM

    local mode="full"
    local scan_target=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --quick | -q)
                mode="quick"
                shift
                ;;
            --ui | -u)
                mode="ui"
                shift
                ;;
            --scan | -s)
                mode="scan"
                shift
                if [[ $# -gt 0 ]]; then
                    scan_target="$1"
                    shift
                else
                    echo "Error: --scan requires an IP address"
                    exit 1
                fi
                ;;
            --connections | -c)
                mode="connections"
                shift
                ;;
            --ports | -p)
                mode="ports"
                shift
                ;;
            --devices | -d)
                mode="devices"
                shift
                ;;
            --help | -h)
                show_network_help
                exit 0
                ;;
            --debug)
                export MO_DEBUG=1
                shift
                ;;
            *)
                # Check if it's an IP address (for scan shorthand: mo network 192.168.1.1)
                if [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    mode="scan"
                    scan_target="$1"
                    shift
                else
                    echo "Unknown option: $1"
                    echo "Use 'mo network --help' for usage."
                    exit 1
                fi
                ;;
        esac
    done

    if [[ -t 1 ]]; then
        clear
    fi

    echo ""
    echo -e "${PURPLE_BOLD}Network Diagnostics${NC}  $(date '+%Y-%m-%d %H:%M')"
    echo ""

    case "$mode" in
        full)
            network_full_report
            echo ""
            show_network_summary
            ;;
        ui)
            local GO_BIN="$SCRIPT_DIR/bin/network-go"
            if [[ -x "$GO_BIN" ]]; then
                exec "$GO_BIN" "$@"
            else
                echo "Network dashboard binary not found."
                echo "Build from source: cd cmd/network && go build -o ../../bin/network-go ."
                exit 1
            fi
            ;;
        quick)
            show_interfaces
            show_wifi_info
            show_lan_devices
            ;;
        scan)
            show_interfaces
            scan_host "$scan_target"
            ;;
        connections)
            show_active_connections
            ;;
        ports)
            show_listening_ports
            ;;
        devices)
            show_lan_devices
            ;;
    esac

    echo ""
}

main "$@"
