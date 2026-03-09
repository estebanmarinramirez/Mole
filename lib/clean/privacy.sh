#!/bin/bash
# Privacy Data Cleanup Module
# Cleans macOS tracking/analytics data from stable Apple paths.

set -euo pipefail

# ============================================================================
# Privacy targets
# Each entry: id|path|description|type
#   type: "file" = single file, "dir" = directory, "glob" = wildcard pattern
# ============================================================================

declare -a PRIVACY_TARGETS=()

register_privacy_targets() {
    PRIVACY_TARGETS=(
        "quarantine|${HOME}/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2|Download quarantine history|file"
        "recent_items|${HOME}/Library/Application Support/com.apple.sharedfilelist|Recent items lists|dir"
        "siri_analytics|${HOME}/Library/Assistant/SiriAnalytics.db|Siri analytics database|file"
        "knowledge_store|${HOME}/Library/CoreDuet/Knowledge/knowledgeC.db|App usage tracking (Knowledge)|file"
        "knowledge_wal|${HOME}/Library/CoreDuet/Knowledge/knowledgeC.db-wal|Knowledge WAL journal|file"
        "knowledge_shm|${HOME}/Library/CoreDuet/Knowledge/knowledgeC.db-shm|Knowledge SHM journal|file"
        "spotlight_suggestions|${HOME}/Library/Suggestions|Spotlight suggestion cache|dir"
        "diag_reports_user|${HOME}/Library/DiagnosticReports|User diagnostic reports|dir"
        "findmy_cache|${HOME}/Library/Caches/com.apple.findmy|Find My cache|dir"
        "findmy_fmip|${HOME}/Library/Caches/com.apple.findmy.fmipcore|Find My device cache|dir"
        "recentservers|${HOME}/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.RecentServers.sfl2|Recent network servers|file"
        "recentsearches|${HOME}/Library/Application Support/com.apple.spotlight/com.apple.spotlight.Shortcuts|Spotlight search shortcuts|file"
        "quicklook_cache|${HOME}/Library/Caches/com.apple.QuickLookDaemon|QuickLook thumbnail cache|dir"
        "quicklook_thumb|${HOME}/Library/Caches/com.apple.QuickLook.thumbnailcache|QuickLook metadata cache|dir"
        "biome_data|${HOME}/Library/Biome|Biome analytics data|dir"
    )
}

# ============================================================================
# Size calculation
# ============================================================================

get_target_size() {
    local path="$1"
    local type="$2"

    if [[ ! -e "$path" ]]; then
        echo "0"
        return
    fi

    case "$type" in
        file)
            stat -f %z "$path" 2>/dev/null || echo "0"
            ;;
        dir)
            du -sk "$path" 2>/dev/null | awk '{print $1 * 1024}' || echo "0"
            ;;
    esac
}

format_size() {
    local bytes="$1"
    if [[ "$bytes" -ge 1073741824 ]]; then
        echo "$(echo "scale=1; $bytes / 1073741824" | bc) GB"
    elif [[ "$bytes" -ge 1048576 ]]; then
        echo "$(echo "scale=1; $bytes / 1048576" | bc) MB"
    elif [[ "$bytes" -ge 1024 ]]; then
        echo "$(echo "scale=0; $bytes / 1024" | bc) KB"
    else
        echo "${bytes} B"
    fi
}

# ============================================================================
# Scan mode
# ============================================================================

scan_privacy_data() {
    register_privacy_targets

    local total_size=0
    local found_count=0
    local missing_count=0

    echo -e "${BLUE}${ICON_ARROW}${NC} Privacy Data Scan"
    echo ""

    for entry in "${PRIVACY_TARGETS[@]}"; do
        IFS='|' read -r id path description type <<< "$entry"

        if [[ ! -e "$path" ]]; then
            missing_count=$((missing_count + 1))
            continue
        fi

        local size
        size=$(get_target_size "$path" "$type")
        local size_str
        size_str=$(format_size "$size")

        total_size=$((total_size + size))
        found_count=$((found_count + 1))

        printf "  ${GRAY}${ICON_LIST}${NC} %-42s %10s\n" "$description" "$size_str"
    done

    echo ""
    echo -e "${BLUE}${ICON_ARROW}${NC} Summary"

    local total_str
    total_str=$(format_size "$total_size")
    echo -e "  Found: ${found_count} trackable items (${total_str} total)"
    echo -e "  Not present: ${missing_count} items"
}

# ============================================================================
# Clean mode
# ============================================================================

clean_privacy_data() {
    register_privacy_targets

    local cleaned_count=0
    local cleaned_size=0
    local skipped_count=0
    local error_count=0

    echo -e "${BLUE}${ICON_ARROW}${NC} Cleaning Privacy Data"
    echo ""

    for entry in "${PRIVACY_TARGETS[@]}"; do
        IFS='|' read -r id path description type <<< "$entry"

        # Check whitelist
        if command -v is_whitelisted > /dev/null && is_whitelisted "privacy_${id}"; then
            skipped_count=$((skipped_count + 1))
            continue
        fi

        if [[ ! -e "$path" ]]; then
            continue
        fi

        local size
        size=$(get_target_size "$path" "$type")
        local size_str
        size_str=$(format_size "$size")

        if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
            echo -e "  ${GRAY}${ICON_DRY_RUN} [DRY RUN] Would clean: ${description} (${size_str})${NC}"
            cleaned_count=$((cleaned_count + 1))
            cleaned_size=$((cleaned_size + size))
            continue
        fi

        # Clean based on type
        local success=false
        case "$type" in
            file)
                if rm -f "$path" 2>/dev/null; then
                    success=true
                fi
                ;;
            dir)
                if rm -rf "$path" 2>/dev/null; then
                    success=true
                fi
                ;;
        esac

        if [[ "$success" == "true" ]]; then
            echo -e "  ${GREEN}${ICON_SUCCESS}${NC} ${description} (${size_str})"
            cleaned_count=$((cleaned_count + 1))
            cleaned_size=$((cleaned_size + size))
        else
            echo -e "  ${YELLOW}${ICON_WARNING}${NC} ${description} (permission denied)"
            error_count=$((error_count + 1))
        fi
    done

    echo ""
    local total_str
    total_str=$(format_size "$cleaned_size")

    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        echo -e "${GRAY}Dry run: ${cleaned_count} items (${total_str}) would be cleaned${NC}"
    else
        echo -e "${GREEN}Cleaned ${cleaned_count} items${NC} (${total_str} freed)"
        if [[ $error_count -gt 0 ]]; then
            echo -e "${YELLOW}${error_count} items could not be cleaned (permission denied)${NC}"
        fi
        if [[ $skipped_count -gt 0 ]]; then
            echo -e "${GRAY}${skipped_count} items skipped (whitelisted)${NC}"
        fi
    fi
}
