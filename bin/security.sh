#!/bin/bash
# Mole Security Audit
# Comprehensive macOS security scan ported from security-scan.sh.
# Usage: mo security [--full] [--dry-run] [--debug]
#   --full:    Include Lynis audit and nmap network scan (slower)
#   --dry-run: Preview what checks would run
#   --debug:   Show detailed findings

set -euo pipefail

# Fix locale issues
export LC_ALL=C
export LANG=C

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/core/common.sh"
source "$SCRIPT_DIR/lib/core/sudo.sh"
source "$SCRIPT_DIR/lib/check/all.sh"
source "$SCRIPT_DIR/lib/check/security.sh"

FULL_MODE=false

cleanup_all() {
    stop_inline_spinner 2>/dev/null || true
    stop_sudo_session
    cleanup_temp_files
}

handle_interrupt() {
    cleanup_all
    exit 130
}

show_security_help() {
    echo ""
    echo -e "${PURPLE_BOLD}Security Audit${NC}"
    echo ""
    echo "  Comprehensive macOS security scan covering malware indicators,"
    echo "  persistence mechanisms, network configuration, user accounts,"
    echo "  and environment variables."
    echo ""
    echo -e "${BLUE}Usage:${NC}"
    echo "  mo security              Run standard security audit"
    echo "  mo security --full       Include Lynis + nmap scans"
    echo "  mo security --debug      Show detailed findings"
    echo ""
    echo -e "${BLUE}Checks performed:${NC}"
    echo "  Malware IoC        Marker files, SOCKS proxy, C2 connections"
    echo "  Persistence        LaunchDaemons, crontab, recently modified"
    echo "  Network            DNS, proxy, /etc/hosts, network shares"
    echo "  Users              System accounts, SSH authorized_keys"
    echo "  Environment        DYLD injection, proxy variables"
    echo "  System Integrity   SIP, Gatekeeper, Firewall, FileVault, Stealth"
    echo ""
    echo -e "${BLUE}Full mode (--full):${NC}"
    echo "  Lynis              Professional UNIX security audit"
    echo "  nmap               Local network device scan"
    echo ""
}

main() {
    # Register cleanup handlers
    trap cleanup_all EXIT
    trap handle_interrupt INT TERM

    # Parse arguments
    for arg in "$@"; do
        case "$arg" in
            --full | -f)
                FULL_MODE=true
                ;;
            --help | -h)
                show_security_help
                exit 0
                ;;
            --dry-run | -n)
                export MOLE_DRY_RUN=1
                ;;
            *)
                echo "Unknown option: $arg"
                echo "Use 'mo security --help' for usage."
                exit 1
                ;;
        esac
    done

    if [[ -t 1 ]]; then
        clear
    fi

    echo ""
    echo -e "${PURPLE_BOLD}Security Audit${NC}  $(date '+%Y-%m-%d %H:%M')"
    echo ""

    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        echo -e "${YELLOW}${ICON_DRY_RUN} DRY RUN MODE${NC} - showing what checks would run"
        echo ""
        echo "  Standard checks: Malware IoC, Persistence, Network, Users, Environment"
        echo "  System integrity: SIP, Gatekeeper, Firewall, FileVault, Stealth Mode"
        if [[ "$FULL_MODE" == "true" ]]; then
            echo "  Professional tools: Lynis audit, nmap network scan"
        fi
        echo ""
        exit 0
    fi

    # System Integrity (reuse Mole's existing checks + stealth mode)
    echo -e "${BLUE}${ICON_ARROW}${NC} System Integrity"
    check_filevault
    check_firewall
    check_gatekeeper
    check_sip
    check_stealth_mode

    echo ""

    # Malware checks
    check_all_malware

    echo ""

    # Persistence checks
    check_all_persistence

    echo ""

    # Network checks
    check_all_network

    echo ""

    # User account checks
    check_all_users

    echo ""

    # Environment checks
    check_all_environment

    # Full mode: professional tools
    if [[ "$FULL_MODE" == "true" ]]; then
        # Ensure sudo for Lynis
        if ! has_sudo_session; then
            echo ""
            if ! ensure_sudo_session "Lynis audit requires admin access"; then
                echo -e "${YELLOW}Skipping Lynis (requires admin access)${NC}"
            fi
        fi
        echo ""
        check_all_professional
    fi

    # Summary
    show_security_summary

    echo ""
}

main "$@"
