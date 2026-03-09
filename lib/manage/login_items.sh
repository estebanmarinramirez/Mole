#!/bin/bash
# Login Items & LaunchAgent Manager
# Discovery, orphan detection, and management of macOS startup items.

set -euo pipefail

# ============================================================================
# Constants
# ============================================================================

readonly LOGIN_USER_AGENTS_DIR="$HOME/Library/LaunchAgents"
readonly LOGIN_SYSTEM_AGENTS_DIR="/Library/LaunchAgents"
readonly LOGIN_SYSTEM_DAEMONS_DIR="/Library/LaunchDaemons"

# ============================================================================
# Discovery: Login Items (via osascript)
# ============================================================================

discover_login_items() {
    # Returns: name|type|status|source|program_path
    if ! command -v osascript > /dev/null 2>&1; then
        return
    fi

    local raw_items
    raw_items=$(osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null || echo "")
    [[ -z "$raw_items" || "$raw_items" == "missing value" ]] && return

    IFS=',' read -ra items_array <<< "$raw_items"
    for entry in "${items_array[@]}"; do
        local trimmed
        trimmed=$(echo "$entry" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        [[ -z "$trimmed" ]] && continue
        echo "${trimmed}|login_item|active|Login Items|"
    done
}

# ============================================================================
# Discovery: LaunchAgents & LaunchDaemons (via plist parsing)
# ============================================================================

get_agent_label() {
    local plist="$1"
    /usr/libexec/PlistBuddy -c "Print :Label" "$plist" 2>/dev/null || basename "$plist" .plist
}

get_agent_program() {
    local plist="$1"
    # Try Program key first
    local program
    program=$(/usr/libexec/PlistBuddy -c "Print :Program" "$plist" 2>/dev/null || echo "")
    if [[ -n "$program" ]]; then
        echo "$program"
        return
    fi

    # Try ProgramArguments[0]
    program=$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" "$plist" 2>/dev/null || echo "")
    echo "$program"
}

get_agent_status() {
    local label="$1"
    # Check if loaded via launchctl
    if launchctl list 2>/dev/null | grep -q "$label"; then
        echo "loaded"
    else
        echo "unloaded"
    fi
}

is_agent_disabled() {
    local plist="$1"
    local disabled
    disabled=$(/usr/libexec/PlistBuddy -c "Print :Disabled" "$plist" 2>/dev/null || echo "")
    [[ "$disabled" == "true" ]]
}

discover_agents() {
    local dir="$1"
    local source_type="$2"  # "User Agent" or "System Agent" or "System Daemon"

    [[ -d "$dir" ]] || return

    while IFS= read -r plist; do
        [[ -f "$plist" ]] || continue
        [[ "$plist" == *.plist ]] || continue

        local label program status
        label=$(get_agent_label "$plist")
        program=$(get_agent_program "$plist")
        status=$(get_agent_status "$label")

        if is_agent_disabled "$plist"; then
            status="disabled"
        fi

        # name|type|status|source|program_path|plist_path
        echo "${label}|agent|${status}|${source_type}|${program}|${plist}"
    done < <(command find "$dir" -maxdepth 1 -name "*.plist" -type f 2>/dev/null || true)
}

# ============================================================================
# Orphan Detection
# ============================================================================

is_agent_orphaned() {
    local program="$1"
    local label="$2"

    # Skip Apple services -- never orphaned
    [[ "$label" == com.apple.* ]] && return 1

    # No program path = can't determine
    [[ -z "$program" ]] && return 1

    # Expand ~ in program path
    local expanded="${program/#\~/$HOME}"

    # Check if the binary exists
    if [[ -x "$expanded" ]]; then
        return 1
    fi

    # Check if it's an app reference
    if [[ "$expanded" == *".app"* ]]; then
        local app_path
        app_path=$(echo "$expanded" | sed 's|\(.*\.app\)/.*|\1|')
        if [[ -d "$app_path" ]]; then
            return 1
        fi
    fi

    # Check common app locations by label
    local bundle_prefix
    bundle_prefix=$(echo "$label" | sed 's/\.[^.]*$//')
    for search_dir in "/Applications" "$HOME/Applications"; do
        if [[ -d "$search_dir" ]]; then
            local found
            found=$(command find "$search_dir" -maxdepth 2 -name "*.app" -type d 2>/dev/null | head -5)
            while IFS= read -r app; do
                [[ -z "$app" ]] && continue
                local app_bundle
                app_bundle=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Contents/Info.plist" 2>/dev/null || echo "")
                if [[ -n "$app_bundle" && "$label" == "$app_bundle"* ]]; then
                    return 1
                fi
            done <<< "$found"
        fi
    done

    return 0
}

# ============================================================================
# Display Formatting
# ============================================================================

format_item_display() {
    local name="$1"
    local status="$2"
    local source="$3"
    local is_orphan="$4"

    # Status indicator
    local status_str
    case "$status" in
        loaded)   status_str="${GREEN}loaded${NC}" ;;
        unloaded) status_str="${GRAY}unloaded${NC}" ;;
        disabled) status_str="${YELLOW}disabled${NC}" ;;
        active)   status_str="${GREEN}active${NC}" ;;
        *)        status_str="${GRAY}${status}${NC}" ;;
    esac

    # Source indicator
    local source_str
    case "$source" in
        "User Agent")    source_str="${CYAN}User${NC}" ;;
        "System Agent")  source_str="${BLUE}System${NC}" ;;
        "System Daemon") source_str="${PURPLE}Daemon${NC}" ;;
        "Login Items")   source_str="${GREEN}Login${NC}" ;;
        *)               source_str="${GRAY}${source}${NC}" ;;
    esac

    # Orphan marker
    local orphan_str=""
    if [[ "$is_orphan" == "true" ]]; then
        orphan_str=" ${RED}[orphan]${NC}"
    fi

    # Terminal width aware formatting
    local tw
    tw=$(tput cols 2>/dev/null || echo 80)
    [[ "$tw" =~ ^[0-9]+$ ]] || tw=80

    # Truncate long names
    local max_name=$((tw - 40))
    [[ $max_name -lt 20 ]] && max_name=20
    [[ $max_name -gt 50 ]] && max_name=50

    local display_name="$name"
    if [[ ${#display_name} -gt $max_name ]]; then
        display_name="${display_name:0:$((max_name - 3))}..."
    fi

    printf "  %-*s  %-10b  %-8b%b\n" "$max_name" "$display_name" "$status_str" "$source_str" "$orphan_str"
}

# ============================================================================
# Main Discovery (combines all sources)
# ============================================================================

discover_all_items() {
    local -a all_items=()

    # Login Items
    while IFS= read -r item; do
        [[ -n "$item" ]] && all_items+=("$item")
    done < <(discover_login_items)

    # User LaunchAgents
    while IFS= read -r item; do
        [[ -n "$item" ]] && all_items+=("$item")
    done < <(discover_agents "$LOGIN_USER_AGENTS_DIR" "User Agent")

    # System LaunchAgents
    while IFS= read -r item; do
        [[ -n "$item" ]] && all_items+=("$item")
    done < <(discover_agents "$LOGIN_SYSTEM_AGENTS_DIR" "System Agent")

    # System LaunchDaemons (read-only display)
    while IFS= read -r item; do
        [[ -n "$item" ]] && all_items+=("$item")
    done < <(discover_agents "$LOGIN_SYSTEM_DAEMONS_DIR" "System Daemon")

    printf '%s\n' "${all_items[@]}"
}

# ============================================================================
# List Mode (non-interactive)
# ============================================================================

list_all_items() {
    local show_orphans_only="${1:-false}"

    if [[ -t 1 ]]; then
        MOLE_SPINNER_PREFIX="" start_inline_spinner "Scanning startup items..."
    fi

    local -a items=()
    while IFS= read -r item; do
        [[ -n "$item" ]] && items+=("$item")
    done < <(discover_all_items)

    if [[ -t 1 ]]; then
        stop_inline_spinner
    fi

    if [[ ${#items[@]} -eq 0 ]]; then
        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} No startup items found"
        return
    fi

    local total_count=${#items[@]}
    local orphan_count=0
    local loaded_count=0
    local user_count=0
    local system_count=0

    echo ""

    # Categorize and display
    local -a login_items=()
    local -a user_agents=()
    local -a system_agents=()
    local -a system_daemons=()
    local -a orphan_items=()

    for item in "${items[@]}"; do
        IFS='|' read -r name type status source program plist <<< "$item"

        # Check orphan status for agents
        local is_orphan="false"
        if [[ "$type" == "agent" && -n "$program" ]]; then
            if is_agent_orphaned "$program" "$name"; then
                is_orphan="true"
                orphan_count=$((orphan_count + 1))
                orphan_items+=("$item")
            fi
        fi

        [[ "$status" == "loaded" || "$status" == "active" ]] && loaded_count=$((loaded_count + 1))

        case "$source" in
            "Login Items")   login_items+=("${item}|${is_orphan}") ;;
            "User Agent")    user_agents+=("${item}|${is_orphan}"); user_count=$((user_count + 1)) ;;
            "System Agent")  system_agents+=("${item}|${is_orphan}"); system_count=$((system_count + 1)) ;;
            "System Daemon") system_daemons+=("${item}|${is_orphan}"); system_count=$((system_count + 1)) ;;
        esac
    done

    # If orphans-only mode, just show orphans
    if [[ "$show_orphans_only" == "true" ]]; then
        echo -e "${BLUE}${ICON_ARROW}${NC} Orphaned Agents (no matching application)"
        echo ""
        if [[ ${#orphan_items[@]} -eq 0 ]]; then
            echo -e "  ${GREEN}${ICON_SUCCESS}${NC} No orphaned agents found"
        else
            for item in "${orphan_items[@]}"; do
                IFS='|' read -r name _ status source program _ <<< "$item"
                format_item_display "$name" "$status" "$source" "true"
                if [[ -n "$program" ]]; then
                    echo -e "    ${GRAY}${ICON_SUBLIST} ${program}${NC}"
                fi
            done
        fi
        echo ""
        echo -e "${GRAY}Found ${orphan_count} orphaned agents out of ${total_count} total items${NC}"
        return
    fi

    # Full listing by category
    if [[ ${#login_items[@]} -gt 0 ]]; then
        echo -e "${BLUE}${ICON_ARROW}${NC} Login Items"
        for entry in "${login_items[@]}"; do
            IFS='|' read -r name _ status source _ _ is_orphan <<< "$entry"
            format_item_display "$name" "$status" "$source" "${is_orphan:-false}"
        done
        echo ""
    fi

    if [[ ${#user_agents[@]} -gt 0 ]]; then
        echo -e "${BLUE}${ICON_ARROW}${NC} User LaunchAgents (~/Library/LaunchAgents)"
        for entry in "${user_agents[@]}"; do
            IFS='|' read -r name _ status source program plist is_orphan <<< "$entry"
            format_item_display "$name" "$status" "$source" "${is_orphan:-false}"
        done
        echo ""
    fi

    if [[ ${#system_agents[@]} -gt 0 ]]; then
        echo -e "${BLUE}${ICON_ARROW}${NC} System LaunchAgents ($LOGIN_SYSTEM_AGENTS_DIR)"
        for entry in "${system_agents[@]}"; do
            IFS='|' read -r name _ status source program plist is_orphan <<< "$entry"
            format_item_display "$name" "$status" "$source" "${is_orphan:-false}"
        done
        echo ""
    fi

    if [[ ${#system_daemons[@]} -gt 0 ]]; then
        echo -e "${BLUE}${ICON_ARROW}${NC} System LaunchDaemons ($LOGIN_SYSTEM_DAEMONS_DIR)"
        for entry in "${system_daemons[@]}"; do
            IFS='|' read -r name _ status source program plist is_orphan <<< "$entry"
            format_item_display "$name" "$status" "$source" "${is_orphan:-false}"
        done
        echo ""
    fi

    # Summary
    echo -e "${BLUE}${ICON_ARROW}${NC} Summary"
    echo -e "  Total: ${total_count} items (${loaded_count} active)"
    echo -e "  User agents: ${user_count}, System: ${system_count}, Login items: ${#login_items[@]}"
    if [[ $orphan_count -gt 0 ]]; then
        echo -e "  ${YELLOW}Orphaned: ${orphan_count} (run ${NC}mo login --orphans${YELLOW} for details)${NC}"
    else
        echo -e "  ${GREEN}No orphaned agents${NC}"
    fi
}

# ============================================================================
# Interactive Management
# ============================================================================

interactive_manage() {
    source "$SCRIPT_DIR/lib/ui/menu_paginated.sh"

    if [[ -t 1 ]]; then
        MOLE_SPINNER_PREFIX="" start_inline_spinner "Scanning startup items..."
    fi

    # Discover user-manageable items only (user agents)
    local -a manageable_items=()
    while IFS= read -r item; do
        [[ -n "$item" ]] && manageable_items+=("$item")
    done < <(discover_agents "$LOGIN_USER_AGENTS_DIR" "User Agent")

    if [[ -t 1 ]]; then
        stop_inline_spinner
    fi

    if [[ ${#manageable_items[@]} -eq 0 ]]; then
        echo ""
        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} No user LaunchAgents to manage"
        echo -e "  ${GRAY}User LaunchAgents are in ~/Library/LaunchAgents/${NC}"
        echo ""
        return
    fi

    # Build menu options
    local -a menu_options=()
    local -a pre_selected=()
    local idx=0

    for item in "${manageable_items[@]}"; do
        IFS='|' read -r name _ status source program plist <<< "$item"

        local is_orphan="false"
        if [[ -n "$program" ]] && is_agent_orphaned "$program" "$name"; then
            is_orphan="true"
        fi

        local status_tag=""
        case "$status" in
            loaded)   status_tag="[loaded]" ;;
            unloaded) status_tag="[unloaded]" ;;
            disabled) status_tag="[disabled]" ;;
        esac

        local orphan_tag=""
        [[ "$is_orphan" == "true" ]] && orphan_tag=" [orphan]"

        menu_options+=("${name}  ${status_tag}${orphan_tag}")

        # Pre-select orphans
        if [[ "$is_orphan" == "true" ]]; then
            pre_selected+=("$idx")
        fi

        idx=$((idx + 1))
    done

    # Set pre-selection for orphans
    if [[ ${#pre_selected[@]} -gt 0 ]]; then
        local pre_csv
        pre_csv=$(IFS=','; echo "${pre_selected[*]}")
        export MOLE_MENU_PRESELECTED="$pre_csv"
    fi

    # Run menu
    MOLE_SELECTION_RESULT=""
    paginated_multi_select "Disable LaunchAgents (Space to select, Enter to confirm)" "${menu_options[@]}"
    local exit_code=$?

    unset MOLE_MENU_PRESELECTED

    if [[ $exit_code -ne 0 || -z "$MOLE_SELECTION_RESULT" ]]; then
        echo ""
        echo -e "  ${GRAY}No changes made${NC}"
        return
    fi

    # Process selections
    IFS=',' read -r -a selected_indices <<< "$MOLE_SELECTION_RESULT"

    echo ""
    echo -e "${BLUE}${ICON_ARROW}${NC} Disabling selected agents..."
    echo ""

    local disabled_count=0
    for idx in "${selected_indices[@]}"; do
        if [[ "$idx" =~ ^[0-9]+$ && $idx -ge 0 && $idx -lt ${#manageable_items[@]} ]]; then
            local item="${manageable_items[$idx]}"
            IFS='|' read -r name _ status _ _ plist <<< "$item"
            local label
            label=$(get_agent_label "$plist")

            if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
                echo -e "  ${GRAY}${ICON_DRY_RUN} [DRY RUN] Would disable: ${name}${NC}"
                disabled_count=$((disabled_count + 1))
                continue
            fi

            # Unload the agent
            if launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || \
               launchctl unload "$plist" 2>/dev/null; then
                # Mark as disabled in plist
                /usr/libexec/PlistBuddy -c "Add :Disabled bool true" "$plist" 2>/dev/null || \
                /usr/libexec/PlistBuddy -c "Set :Disabled true" "$plist" 2>/dev/null || true
                echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Disabled: ${name}"
                disabled_count=$((disabled_count + 1))
            else
                echo -e "  ${RED}${ICON_ERROR}${NC} Failed to disable: ${name}"
            fi
        fi
    done

    echo ""
    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        echo -e "${GRAY}Dry run: ${disabled_count} agents would be disabled${NC}"
    else
        echo -e "${GREEN}${disabled_count} agents disabled${NC}"
        if [[ $disabled_count -gt 0 ]]; then
            echo -e "${GRAY}Changes take effect on next login${NC}"
        fi
    fi
}
