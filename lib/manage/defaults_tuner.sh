#!/bin/bash
# macOS Defaults Tuner
# Curated power-user defaults with current state detection, toggle, and reset.

set -euo pipefail

# ============================================================================
# Backup directory for original values
# ============================================================================

readonly DEFAULTS_BACKUP_DIR="${HOME}/.config/mole/defaults_backup"

ensure_backup_dir() {
    mkdir -p "$DEFAULTS_BACKUP_DIR" 2>/dev/null || true
}

# ============================================================================
# Defaults definitions
# Each entry: id|domain|key|on_value|off_value|description|restart_target
#   on_value  = the "power user" setting
#   off_value = the Apple default ("delete" means remove the key)
#   restart_target = process to kill after change (empty = none, "logout" = requires logout)
# ============================================================================

declare -a DEFAULTS_CATALOG=()

register_defaults() {
    # Grouped by display category for clean list output
    DEFAULTS_CATALOG=(
        # Finder
        "show_hidden|com.apple.finder|AppleShowAllFiles|true|false|Show hidden files in Finder|Finder|Finder"
        "show_extensions|NSGlobalDomain|AppleShowAllExtensions|true|false|Always show file extensions|Finder|Finder"
        "finder_path_bar|com.apple.finder|ShowPathbar|true|false|Show path bar in Finder|Finder|Finder"
        "finder_status_bar|com.apple.finder|ShowStatusBar|true|false|Show status bar in Finder|Finder|Finder"
        # Desktop
        "no_ds_network|com.apple.desktopservices|DSDontWriteNetworkStores|true|false|No .DS_Store on network volumes||Desktop"
        "no_ds_usb|com.apple.desktopservices|DSDontWriteUSBStores|true|false|No .DS_Store on USB drives||Desktop"
        # Input
        "key_repeat_speed|NSGlobalDomain|KeyRepeat|2|6|Faster key repeat rate|logout|Input"
        "key_repeat_enable|NSGlobalDomain|ApplePressAndHoldEnabled|false|true|Enable key repeat (disable accent popup)|logout|Input"
        "no_smart_quotes|NSGlobalDomain|NSAutomaticQuoteSubstitutionEnabled|false|true|Disable smart quotes||Input"
        "no_autocorrect|NSGlobalDomain|NSAutomaticSpellingCorrectionEnabled|false|true|Disable auto-correct||Input"
        "no_smart_dashes|NSGlobalDomain|NSAutomaticDashSubstitutionEnabled|false|true|Disable smart dashes||Input"
        # Dialogs
        "expand_save_dialog|NSGlobalDomain|NSNavPanelExpandedStateForSaveMode|true|false|Expand save dialog by default||Dialogs"
        "expand_save_dialog2|NSGlobalDomain|NSNavPanelExpandedStateForSaveMode2|true|false|Expand save dialog (secondary)||Dialogs"
        "expand_print_dialog|NSGlobalDomain|PMPrintingExpandedStateForPrint|true|false|Expand print dialog by default||Dialogs"
        "expand_print_dialog2|NSGlobalDomain|PMPrintingExpandedStateForPrint2|true|false|Expand print dialog (secondary)||Dialogs"
        # Dock
        "dock_autohide_delay|com.apple.dock|autohide-delay|0|delete|Instant Dock autohide (no delay)|Dock|Dock"
        "dock_anim_speed|com.apple.dock|autohide-time-modifier|0.2|delete|Faster Dock show animation|Dock|Dock"
        # System
        "no_crash_dialog|com.apple.CrashReporter|DialogType|none|crashlog|Disable crash reporter dialog||System"
        "screenshot_format|com.apple.screencapture|type|png|png|Screenshot format (png)||System"
    )
}

# ============================================================================
# State detection
# ============================================================================

get_current_value() {
    local domain="$1"
    local key="$2"
    defaults read "$domain" "$key" 2>/dev/null || echo "__UNSET__"
}

is_power_user_value() {
    local current="$1"
    local on_value="$2"
    local off_value="$3"

    # Normalize boolean comparisons
    local current_norm
    current_norm=$(echo "$current" | tr '[:upper:]' '[:lower:]')
    local on_norm
    on_norm=$(echo "$on_value" | tr '[:upper:]' '[:lower:]')

    # Map macOS defaults output (0/1) to true/false
    [[ "$current_norm" == "1" ]] && current_norm="true"
    [[ "$current_norm" == "0" ]] && current_norm="false"
    [[ "$on_norm" == "1" ]] && on_norm="true"
    [[ "$on_norm" == "0" ]] && on_norm="false"

    [[ "$current_norm" == "$on_norm" ]]
}

# ============================================================================
# Backup and restore
# ============================================================================

backup_value() {
    local id="$1"
    local domain="$2"
    local key="$3"

    ensure_backup_dir
    local backup_file="${DEFAULTS_BACKUP_DIR}/${id}"

    # Only backup if we haven't already
    if [[ ! -f "$backup_file" ]]; then
        local current
        current=$(get_current_value "$domain" "$key")
        echo "$current" > "$backup_file"
    fi
}

get_backup_value() {
    local id="$1"
    local backup_file="${DEFAULTS_BACKUP_DIR}/${id}"
    if [[ -f "$backup_file" ]]; then
        cat "$backup_file"
    else
        echo ""
    fi
}

# ============================================================================
# Toggle a default
# ============================================================================

apply_default() {
    local domain="$1"
    local key="$2"
    local value="$3"

    if [[ "$value" == "delete" ]]; then
        defaults delete "$domain" "$key" 2>/dev/null || true
    elif [[ "$value" == "true" || "$value" == "false" ]]; then
        defaults write "$domain" "$key" -bool "$value"
    elif [[ "$value" =~ ^[0-9]+$ ]]; then
        defaults write "$domain" "$key" -int "$value"
    elif [[ "$value" =~ ^[0-9]*\.[0-9]+$ ]]; then
        defaults write "$domain" "$key" -float "$value"
    else
        defaults write "$domain" "$key" -string "$value"
    fi
}

restart_target() {
    local target="$1"
    [[ -z "$target" ]] && return

    case "$target" in
        "Finder")
            killall Finder 2>/dev/null || true
            ;;
        "Dock")
            killall Dock 2>/dev/null || true
            ;;
        "SystemUIServer")
            killall SystemUIServer 2>/dev/null || true
            ;;
        "logout")
            # Don't restart anything, just inform
            ;;
    esac
}

toggle_default() {
    local id="$1"
    local domain="$2"
    local key="$3"
    local on_value="$4"
    local off_value="$5"
    local description="$6"
    local restart="$7"

    local current
    current=$(get_current_value "$domain" "$key")

    # Backup current before changing
    backup_value "$id" "$domain" "$key"

    local new_value
    if is_power_user_value "$current" "$on_value" "$off_value"; then
        # Currently ON -> turn OFF (restore to Apple default)
        new_value="$off_value"
    else
        # Currently OFF -> turn ON (power user)
        new_value="$on_value"
    fi

    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        echo -e "  ${GRAY}${ICON_DRY_RUN} [DRY RUN] Would set ${domain} ${key} = ${new_value}${NC}"
        return
    fi

    apply_default "$domain" "$key" "$new_value"

    # Show result
    if is_power_user_value "$new_value" "$on_value" "$off_value"; then
        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} ${description}: ${GREEN}ON${NC}"
    else
        echo -e "  ${GRAY}${ICON_EMPTY}${NC} ${description}: ${GRAY}off${NC}"
    fi

    # Restart affected process
    if [[ -n "$restart" && "$restart" != "logout" ]]; then
        restart_target "$restart"
    elif [[ "$restart" == "logout" ]]; then
        echo -e "    ${GRAY}Takes effect on next login${NC}"
    fi
}

# ============================================================================
# List mode
# ============================================================================

list_defaults() {
    register_defaults

    local category=""
    local on_count=0
    local off_count=0

    for entry in "${DEFAULTS_CATALOG[@]}"; do
        IFS='|' read -r id domain key on_value off_value description restart new_category <<< "$entry"

        local current
        current=$(get_current_value "$domain" "$key")

        local status_str
        if is_power_user_value "$current" "$on_value" "$off_value"; then
            status_str="${GREEN}ON${NC}"
            on_count=$((on_count + 1))
        elif [[ "$current" == "__UNSET__" ]]; then
            status_str="${GRAY}default${NC}"
            off_count=$((off_count + 1))
        else
            status_str="${GRAY}off${NC}"
            off_count=$((off_count + 1))
        fi

        if [[ "$new_category" != "$category" ]]; then
            [[ -n "$category" ]] && echo ""
            echo -e "${BLUE}${ICON_ARROW}${NC} $new_category"
            category="$new_category"
        fi

        printf "  %-6b  %s\n" "$status_str" "$description"
    done

    echo ""
    echo -e "${BLUE}${ICON_ARROW}${NC} Summary"
    echo -e "  ${GREEN}${on_count}${NC} power-user settings active, ${GRAY}${off_count} at default${NC}"
}

# ============================================================================
# Interactive toggle mode
# ============================================================================

interactive_toggle() {
    register_defaults

    local -a items=()
    local -a states=()

    # Build item list with current states
    for entry in "${DEFAULTS_CATALOG[@]}"; do
        IFS='|' read -r id domain key on_value off_value description restart <<< "$entry"
        local current
        current=$(get_current_value "$domain" "$key")

        local state_tag
        if is_power_user_value "$current" "$on_value" "$off_value"; then
            state_tag="[ON]"
            states+=("on")
        else
            state_tag="[off]"
            states+=("off")
        fi

        items+=("${description}  ${state_tag}")
    done

    # Use paginated menu
    source "$SCRIPT_DIR/lib/ui/menu_paginated.sh"

    MOLE_SELECTION_RESULT=""
    paginated_multi_select "Toggle Settings (Space to select, Enter to apply)" "${items[@]}"
    local exit_code=$?

    if [[ $exit_code -ne 0 || -z "$MOLE_SELECTION_RESULT" ]]; then
        echo ""
        echo -e "  ${GRAY}No changes made${NC}"
        return
    fi

    # Process selections
    IFS=',' read -r -a selected_indices <<< "$MOLE_SELECTION_RESULT"

    echo ""
    echo -e "${BLUE}${ICON_ARROW}${NC} Applying changes..."
    echo ""

    local changed_count=0
    local needs_logout=false
    local -a restart_targets=()

    for idx in "${selected_indices[@]}"; do
        if [[ "$idx" =~ ^[0-9]+$ && $idx -ge 0 && $idx -lt ${#DEFAULTS_CATALOG[@]} ]]; then
            local entry="${DEFAULTS_CATALOG[$idx]}"
            IFS='|' read -r id domain key on_value off_value description restart <<< "$entry"

            toggle_default "$id" "$domain" "$key" "$on_value" "$off_value" "$description" "$restart"
            changed_count=$((changed_count + 1))

            [[ "$restart" == "logout" ]] && needs_logout=true
            if [[ -n "$restart" && "$restart" != "logout" ]]; then
                # Track unique restart targets
                local already_tracked=false
                for t in "${restart_targets[@]:-}"; do
                    [[ "$t" == "$restart" ]] && already_tracked=true
                done
                [[ "$already_tracked" == "false" ]] && restart_targets+=("$restart")
            fi
        fi
    done

    echo ""
    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        echo -e "${GRAY}Dry run: ${changed_count} settings would change${NC}"
    else
        echo -e "${GREEN}${changed_count} settings changed${NC}"
        if [[ $needs_logout == true ]]; then
            echo -e "${YELLOW}Some changes require logout/login to take effect${NC}"
        fi
    fi
}

# ============================================================================
# Reset mode
# ============================================================================

reset_defaults() {
    register_defaults

    echo -e "${BLUE}${ICON_ARROW}${NC} Resetting to original values..."
    echo ""

    local reset_count=0
    local -a restart_targets=()

    for entry in "${DEFAULTS_CATALOG[@]}"; do
        IFS='|' read -r id domain key on_value off_value description restart <<< "$entry"

        local backup_val
        backup_val=$(get_backup_value "$id")

        if [[ -n "$backup_val" ]]; then
            # Restore from backup
            if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
                echo -e "  ${GRAY}${ICON_DRY_RUN} [DRY RUN] Would restore: ${description}${NC}"
            else
                if [[ "$backup_val" == "__UNSET__" ]]; then
                    defaults delete "$domain" "$key" 2>/dev/null || true
                else
                    apply_default "$domain" "$key" "$backup_val"
                fi
                echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Restored: ${description}"

                if [[ -n "$restart" && "$restart" != "logout" ]]; then
                    local already=false
                    for t in "${restart_targets[@]:-}"; do
                        [[ "$t" == "$restart" ]] && already=true
                    done
                    [[ "$already" == "false" ]] && restart_targets+=("$restart")
                fi
            fi
            reset_count=$((reset_count + 1))
        else
            # No backup: restore to off_value (Apple default)
            local current
            current=$(get_current_value "$domain" "$key")
            if is_power_user_value "$current" "$on_value" "$off_value"; then
                if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
                    echo -e "  ${GRAY}${ICON_DRY_RUN} [DRY RUN] Would reset: ${description}${NC}"
                else
                    apply_default "$domain" "$key" "$off_value"
                    echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Reset: ${description}"

                    if [[ -n "$restart" && "$restart" != "logout" ]]; then
                        local already=false
                        for t in "${restart_targets[@]:-}"; do
                            [[ "$t" == "$restart" ]] && already=true
                        done
                        [[ "$already" == "false" ]] && restart_targets+=("$restart")
                    fi
                fi
                reset_count=$((reset_count + 1))
            fi
        fi
    done

    echo ""
    if [[ $reset_count -eq 0 ]]; then
        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} All settings already at defaults"
    elif [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
        echo -e "${GREEN}${reset_count} settings restored${NC}"

        # Restart affected processes
        for target in "${restart_targets[@]:-}"; do
            [[ -n "$target" ]] && restart_target "$target"
        done
    fi
}

# ============================================================================
# Enable all power-user defaults at once
# ============================================================================

enable_all() {
    register_defaults

    echo -e "${BLUE}${ICON_ARROW}${NC} Enabling all power-user settings..."
    echo ""

    local changed_count=0
    local skipped_count=0
    local needs_logout=false
    local -a restart_targets=()

    for entry in "${DEFAULTS_CATALOG[@]}"; do
        IFS='|' read -r id domain key on_value off_value description restart <<< "$entry"

        local current
        current=$(get_current_value "$domain" "$key")

        if is_power_user_value "$current" "$on_value" "$off_value"; then
            skipped_count=$((skipped_count + 1))
            continue
        fi

        backup_value "$id" "$domain" "$key"

        if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
            echo -e "  ${GRAY}${ICON_DRY_RUN} [DRY RUN] Would enable: ${description}${NC}"
        else
            apply_default "$domain" "$key" "$on_value"
            echo -e "  ${GREEN}${ICON_SUCCESS}${NC} ${description}"

            [[ "$restart" == "logout" ]] && needs_logout=true
            if [[ -n "$restart" && "$restart" != "logout" ]]; then
                local already=false
                for t in "${restart_targets[@]:-}"; do
                    [[ "$t" == "$restart" ]] && already=true
                done
                [[ "$already" == "false" ]] && restart_targets+=("$restart")
            fi
        fi
        changed_count=$((changed_count + 1))
    done

    echo ""
    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        echo -e "${GRAY}Dry run: ${changed_count} settings would change (${skipped_count} already active)${NC}"
    else
        echo -e "${GREEN}${changed_count} settings enabled${NC} (${skipped_count} already active)"

        # Restart affected processes
        for target in "${restart_targets[@]:-}"; do
            [[ -n "$target" ]] && restart_target "$target"
        done

        if [[ $needs_logout == true ]]; then
            echo -e "${YELLOW}Some changes require logout/login to take effect${NC}"
        fi
    fi
}
