#!/bin/bash
# Security Audit Module
# Ported from security-scan.sh with Mole conventions.
# Checks: malware IoC, persistence mechanisms, network, users, environment.

set -euo pipefail

# Counters
SECURITY_PASS_COUNT=0
SECURITY_WARN_COUNT=0
SECURITY_FAIL_COUNT=0

sec_pass() {
    SECURITY_PASS_COUNT=$((SECURITY_PASS_COUNT + 1))
    echo -e "  ${GREEN}${ICON_SUCCESS}${NC} $1"
}

sec_warn() {
    SECURITY_WARN_COUNT=$((SECURITY_WARN_COUNT + 1))
    echo -e "  ${GRAY}${ICON_WARNING}${NC} ${YELLOW}$1${NC}"
}

sec_fail() {
    SECURITY_FAIL_COUNT=$((SECURITY_FAIL_COUNT + 1))
    echo -e "  ${RED}${ICON_ERROR}${NC} ${RED}$1${NC}"
}

sec_info() {
    echo -e "  ${GRAY}${ICON_INFO}${NC} ${GRAY}$1${NC}"
}

# ============================================================================
# Section 1: System Integrity (extends Mole's existing checks)
# ============================================================================

check_stealth_mode() {
    if command -v is_whitelisted > /dev/null && is_whitelisted "check_stealth_mode"; then return; fi

    local stealth_output
    stealth_output=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode 2>/dev/null || echo "")
    if echo "$stealth_output" | grep -q "enabled"; then
        sec_pass "Stealth Mode    Invisible on network"
    else
        sec_info "Stealth Mode    Off (visible to network scans)"
    fi
}

# ============================================================================
# Section 2: Malware Indicators of Compromise
# ============================================================================

check_malware_markers() {
    if command -v is_whitelisted > /dev/null && is_whitelisted "check_malware_markers"; then return; fi

    local -a markers=(
        "$HOME/.pwd"
        "$HOME/.chost"
        "$HOME/.botid"
        "$HOME/.username"
        "$HOME/.lastaction"
        "$HOME/.uninstalled"
    )

    local marker_found=0
    for f in "${markers[@]}"; do
        if [[ -f "$f" ]]; then
            sec_fail "Malware marker found: $f"
            marker_found=1
        fi
    done
    [[ $marker_found -eq 0 ]] && sec_pass "No malware marker files"
}

check_socks_proxy() {
    if command -v is_whitelisted > /dev/null && is_whitelisted "check_socks_proxy"; then return; fi

    if [[ -f /tmp/socks ]]; then
        sec_fail "SOCKS proxy binary found: /tmp/socks"
    else
        sec_pass "No SOCKS proxy binary"
    fi
}

check_c2_connections() {
    if command -v is_whitelisted > /dev/null && is_whitelisted "check_c2_connections"; then return; fi

    local c2_output
    c2_output=$(run_with_timeout 5 lsof -i -nP 2>/dev/null | grep "62.60.131.230\|something0x" || true)
    if [[ -n "$c2_output" ]]; then
        sec_fail "C2 connection detected"
        debug_log "C2 connection details: $c2_output"
    else
        sec_pass "No C2 connections"
    fi
}

check_malware_strings_in_daemons() {
    if command -v is_whitelisted > /dev/null && is_whitelisted "check_malware_daemons"; then return; fi

    local malware_output
    malware_output=$(grep -rl "xxxblyat\|something0x\|73087\|joinsystem" /Library/LaunchDaemons/ 2>/dev/null || true)
    if [[ -n "$malware_output" ]]; then
        sec_fail "Malware strings found in LaunchDaemons"
        debug_log "Affected files: $malware_output"
    else
        sec_pass "No malware strings in LaunchDaemons"
    fi
}

check_osascript_processes() {
    if command -v is_whitelisted > /dev/null && is_whitelisted "check_osascript"; then return; fi

    local osascript_output
    osascript_output=$(ps aux 2>/dev/null | grep "[o]sascript" || true)
    if [[ -n "$osascript_output" ]]; then
        sec_warn "osascript process running"
        debug_log "osascript details: $osascript_output"
    else
        sec_pass "No osascript processes"
    fi
}

check_all_malware() {
    echo -e "${BLUE}${ICON_ARROW}${NC} Malware Indicators"
    check_malware_markers
    check_socks_proxy
    check_c2_connections
    check_malware_strings_in_daemons
    check_osascript_processes
}

# ============================================================================
# Section 3: Persistence Mechanisms
# ============================================================================

check_suspicious_daemons() {
    if command -v is_whitelisted > /dev/null && is_whitelisted "check_suspicious_daemons"; then return; fi

    local suspicious
    suspicious=$(ls /Library/LaunchDaemons/ 2>/dev/null | grep -v "com.apple\|com.docker\|homebrew\|org.openvpn\|org.wireshark\|com.hyperion" || true)
    if [[ -n "$suspicious" ]]; then
        local count
        count=$(echo "$suspicious" | wc -l | tr -d ' ')
        sec_warn "Non-standard LaunchDaemons: $count entries"
        debug_log "Non-standard LaunchDaemons: $suspicious"
    else
        sec_pass "LaunchDaemons    Only known entries"
    fi
}

check_recent_daemons() {
    if command -v is_whitelisted > /dev/null && is_whitelisted "check_recent_daemons"; then return; fi

    local recent
    recent=$(find /Library/LaunchDaemons -mtime -7 -type f 2>/dev/null || true)
    if [[ -n "$recent" ]]; then
        local count
        count=$(echo "$recent" | wc -l | tr -d ' ')
        sec_warn "Recently modified LaunchDaemons (7d): $count files"
        debug_log "Recent daemon files: $recent"
    else
        sec_pass "No recently modified LaunchDaemons"
    fi
}

check_crontab() {
    if command -v is_whitelisted > /dev/null && is_whitelisted "check_crontab"; then return; fi

    local cron
    cron=$(crontab -l 2>/dev/null || true)
    if [[ -n "$cron" ]]; then
        local count
        count=$(echo "$cron" | wc -l | tr -d ' ')
        sec_warn "Crontab entries found: $count"
        debug_log "Crontab contents: $cron"
    else
        sec_pass "No crontab entries"
    fi
}

check_all_persistence() {
    echo -e "${BLUE}${ICON_ARROW}${NC} Persistence Mechanisms"
    check_suspicious_daemons
    check_recent_daemons
    check_crontab
}

# ============================================================================
# Section 4: Network Security
# ============================================================================

check_dns_servers() {
    if command -v is_whitelisted > /dev/null && is_whitelisted "check_dns"; then return; fi

    local dns_servers
    dns_servers=$(scutil --dns 2>/dev/null | grep "nameserver\[[0-9]*\]" | awk '{print $NF}' | sort -u | head -5 || true)
    if [[ -n "$dns_servers" ]]; then
        local dns_list
        dns_list=$(echo "$dns_servers" | tr '\n' ', ' | sed 's/,$//')
        sec_info "DNS servers: $dns_list"
    else
        sec_warn "No DNS servers configured"
    fi
}

check_proxy_config() {
    if command -v is_whitelisted > /dev/null && is_whitelisted "check_proxy"; then return; fi

    local proxy_web proxy_socks
    proxy_web=$(networksetup -getwebproxy Wi-Fi 2>/dev/null | grep "Enabled: Yes" || true)
    proxy_socks=$(networksetup -getsocksfirewallproxy Wi-Fi 2>/dev/null | grep "Enabled: Yes" || true)
    if [[ -n "$proxy_web" ]] || [[ -n "$proxy_socks" ]]; then
        sec_warn "Proxy configured on Wi-Fi"
    else
        sec_pass "No proxy configured"
    fi
}

check_hosts_file() {
    if command -v is_whitelisted > /dev/null && is_whitelisted "check_hosts"; then return; fi

    local hosts_extra
    hosts_extra=$(grep -v "^#\|^$\|localhost\|broadcasthost\|::1" /etc/hosts 2>/dev/null || true)
    if [[ -n "$hosts_extra" ]]; then
        local non_sinkhole
        non_sinkhole=$(echo "$hosts_extra" | grep -v "^0.0.0.0" || true)
        if [[ -z "$non_sinkhole" ]]; then
            local count
            count=$(echo "$hosts_extra" | wc -l | tr -d ' ')
            sec_pass "/etc/hosts       $count C2 domains sinkholed"
        else
            sec_warn "/etc/hosts has non-sinkhole entries"
            debug_log "Suspicious hosts entries: $non_sinkhole"
        fi
    else
        sec_pass "/etc/hosts       Clean"
    fi
}

check_network_shares() {
    if command -v is_whitelisted > /dev/null && is_whitelisted "check_shares"; then return; fi

    local shares
    shares=$(mount 2>/dev/null | grep -E "smbfs|nfs|afp" || true)
    if [[ -n "$shares" ]]; then
        local count
        count=$(echo "$shares" | wc -l | tr -d ' ')
        sec_warn "Network shares mounted: $count"
        debug_log "Shares: $shares"
    else
        sec_pass "No network shares mounted"
    fi
}

check_all_network() {
    echo -e "${BLUE}${ICON_ARROW}${NC} Network Security"
    check_dns_servers
    check_proxy_config
    check_hosts_file
    check_network_shares
}

# ============================================================================
# Section 5: User Accounts
# ============================================================================

check_system_users() {
    if command -v is_whitelisted > /dev/null && is_whitelisted "check_users"; then return; fi

    local users
    users=$(dscl . -list /Users 2>/dev/null | grep -v "^_" | sort)
    local expected_users
    expected_users=$(printf 'daemon\n%s\nnobody\nroot' "$(whoami)")
    if [[ "$users" == "$expected_users" ]]; then
        sec_pass "User accounts   Standard set only"
    else
        local extra
        extra=$(comm -23 <(echo "$users") <(echo "$expected_users") | tr '\n' ', ' | sed 's/,$//')
        if [[ -n "$extra" ]]; then
            sec_warn "Non-standard user accounts: $extra"
        else
            sec_pass "User accounts   Standard set only"
        fi
    fi
}

check_ssh_authorized_keys() {
    if command -v is_whitelisted > /dev/null && is_whitelisted "check_ssh"; then return; fi

    if [[ -f "$HOME/.ssh/authorized_keys" ]]; then
        local count
        count=$(grep -c "^ssh-\|^ecdsa-" "$HOME/.ssh/authorized_keys" 2>/dev/null || echo "0")
        sec_warn "SSH authorized_keys: $count keys"
    else
        sec_pass "No SSH authorized_keys"
    fi
}

check_all_users() {
    echo -e "${BLUE}${ICON_ARROW}${NC} User Accounts"
    check_system_users
    check_ssh_authorized_keys
}

# ============================================================================
# Section 6: Environment Variables
# ============================================================================

check_dyld_injection() {
    if command -v is_whitelisted > /dev/null && is_whitelisted "check_dyld"; then return; fi

    local dyld
    dyld=$(env 2>/dev/null | grep "DYLD" || true)
    if [[ -n "$dyld" ]]; then
        sec_fail "DYLD injection variables set"
        debug_log "DYLD variables: $dyld"
    else
        sec_pass "No DYLD injection variables"
    fi
}

check_proxy_env() {
    if command -v is_whitelisted > /dev/null && is_whitelisted "check_proxy_env"; then return; fi

    local proxy_env
    proxy_env=$(env 2>/dev/null | grep -i "proxy\|socks" | grep -v "MOLE\|npm_config" || true)
    if [[ -n "$proxy_env" ]]; then
        local count
        count=$(echo "$proxy_env" | wc -l | tr -d ' ')
        sec_warn "Proxy environment variables: $count"
        debug_log "Proxy env: $proxy_env"
    else
        sec_pass "No proxy environment variables"
    fi
}

check_all_environment() {
    echo -e "${BLUE}${ICON_ARROW}${NC} Environment"
    check_dyld_injection
    check_proxy_env
}

# ============================================================================
# Full Mode: Professional Tools (Lynis + nmap)
# ============================================================================

run_lynis_audit() {
    if ! command -v lynis > /dev/null 2>&1; then
        sec_info "Lynis not installed (brew install lynis)"
        return
    fi

    if [[ -t 1 ]]; then
        MOLE_SPINNER_PREFIX="  " start_inline_spinner "Running Lynis audit (1-2 min)..."
    fi

    local lynis_output
    lynis_output=$(run_with_timeout 180 sudo lynis audit system --quick --no-colors 2>/dev/null || true)

    if [[ -t 1 ]]; then
        stop_inline_spinner
    fi

    local hardening_index
    hardening_index=$(echo "$lynis_output" | grep "Hardening index" | awk '{print $NF}' || echo "N/A")
    sec_info "Hardening Index: ${hardening_index:-N/A}"

    local lynis_warnings
    lynis_warnings=$(echo "$lynis_output" | grep -c "Warning" || echo "0")
    if [[ "$lynis_warnings" -gt 0 ]]; then
        sec_warn "Lynis found $lynis_warnings warnings"
    else
        sec_pass "Lynis: no warnings"
    fi
}

run_network_scan() {
    if ! command -v nmap > /dev/null 2>&1; then
        sec_info "nmap not installed (brew install nmap)"
        return
    fi

    local local_ip
    local_ip=$(ipconfig getifaddr en0 2>/dev/null || echo "")
    if [[ -z "$local_ip" ]]; then
        sec_info "No active Wi-Fi interface for network scan"
        return
    fi

    sec_info "Your IP: $local_ip"
    local subnet
    subnet=$(echo "$local_ip" | sed 's/\.[0-9]*$/.0\/24/')

    if [[ -t 1 ]]; then
        MOLE_SPINNER_PREFIX="  " start_inline_spinner "Scanning $subnet..."
    fi

    local devices
    devices=$(run_with_timeout 30 nmap -sn "$subnet" 2>/dev/null | grep "Nmap scan report" | wc -l | tr -d ' ' || echo "0")

    if [[ -t 1 ]]; then
        stop_inline_spinner
    fi

    sec_info "Found $devices devices on local network"
}

check_all_professional() {
    echo -e "${BLUE}${ICON_ARROW}${NC} Professional Tools"
    run_lynis_audit
    echo ""
    echo -e "${BLUE}${ICON_ARROW}${NC} Local Network Scan"
    run_network_scan
}

# ============================================================================
# Summary
# ============================================================================

show_security_summary() {
    local total=$((SECURITY_PASS_COUNT + SECURITY_WARN_COUNT + SECURITY_FAIL_COUNT))
    local summary_title

    if [[ $SECURITY_FAIL_COUNT -gt 0 ]]; then
        summary_title="Security Audit Complete - ${SECURITY_FAIL_COUNT} Critical Issues"
    elif [[ $SECURITY_WARN_COUNT -gt 0 ]]; then
        summary_title="Security Audit Complete - ${SECURITY_WARN_COUNT} Warnings"
    else
        summary_title="Security Audit Complete - All Clear"
    fi

    local -a details=()
    details+=("${GREEN}${SECURITY_PASS_COUNT}${NC} passed, ${YELLOW}${SECURITY_WARN_COUNT}${NC} warnings, ${RED}${SECURITY_FAIL_COUNT}${NC} critical")
    details+=("Total checks: $total")

    if [[ $SECURITY_FAIL_COUNT -gt 0 ]]; then
        details+=("Run with ${YELLOW}--debug${NC} for detailed findings")
    fi

    print_summary_block "$summary_title" "${details[@]}"
}
