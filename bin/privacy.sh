#!/bin/bash
# Mole Privacy Data Cleanup
# Scan and clean macOS tracking/analytics data.
# Usage: mo privacy [--scan] [--clean] [--dry-run]

set -euo pipefail

export LC_ALL=C
export LANG=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/core/common.sh"
source "$SCRIPT_DIR/lib/clean/privacy.sh"

cleanup_all() {
    stop_inline_spinner 2>/dev/null || true
    cleanup_temp_files
}

handle_interrupt() {
    cleanup_all
    exit 130
}

show_privacy_help() {
    echo ""
    echo -e "${PURPLE_BOLD}Privacy Data Cleanup${NC}"
    echo ""
    echo "  Scan and remove macOS tracking and analytics data."
    echo "  Targets stable Apple data paths that are safe to clean."
    echo ""
    echo -e "${BLUE}Usage:${NC}"
    echo "  mo privacy             Scan and prompt to clean"
    echo "  mo privacy --scan      Scan only (show sizes)"
    echo "  mo privacy --clean     Clean immediately"
    echo "  mo privacy --dry-run   Preview what would be cleaned"
    echo ""
    echo -e "${BLUE}Data cleaned:${NC}"
    echo "  Quarantine DB          Download tracking history"
    echo "  Recent Items           File/server access history"
    echo "  Siri Analytics         Siri usage database"
    echo "  CoreDuet Knowledge     App usage tracking"
    echo "  Spotlight Suggestions  Search suggestion cache"
    echo "  Diagnostic Reports     User-level crash reports"
    echo "  Find My Cache          Location service cache"
    echo "  QuickLook Cache        Thumbnail preview cache"
    echo "  Biome Data             System analytics"
    echo ""
    echo -e "${BLUE}Safety:${NC}"
    echo "  All targets are user-level data in ~/Library."
    echo "  No system files or application data is touched."
    echo "  Data regenerates naturally through normal macOS use."
    echo ""
}

main() {
    trap cleanup_all EXIT
    trap handle_interrupt INT TERM

    local mode="prompt"

    for arg in "$@"; do
        case "$arg" in
            --scan | -s)
                mode="scan"
                ;;
            --clean | -c)
                mode="clean"
                ;;
            --help | -h)
                show_privacy_help
                exit 0
                ;;
            --dry-run | -n)
                export MOLE_DRY_RUN=1
                ;;
            *)
                echo "Unknown option: $arg"
                echo "Use 'mo privacy --help' for usage."
                exit 1
                ;;
        esac
    done

    if [[ -t 1 ]]; then
        clear
    fi

    echo ""
    echo -e "${PURPLE_BOLD}Privacy Data Cleanup${NC}"
    echo ""

    case "$mode" in
        scan)
            scan_privacy_data
            ;;
        clean)
            if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
                echo -e "${YELLOW}${ICON_DRY_RUN} DRY RUN MODE${NC} - no files will be deleted"
                echo ""
            fi
            clean_privacy_data
            ;;
        prompt)
            # Scan first
            scan_privacy_data
            echo ""

            if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
                echo -e "${YELLOW}${ICON_DRY_RUN} DRY RUN MODE${NC}"
                echo ""
                clean_privacy_data
            else
                echo -ne "${PURPLE}${ICON_ARROW}${NC} Clean all privacy data? ${GRAY}Enter confirm / Q cancel${NC}: "
                local key
                IFS= read -r -s -n1 key || key=""
                echo ""

                case "$key" in
                    "" | $'\n' | $'\r')
                        echo ""
                        clean_privacy_data
                        ;;
                    *)
                        echo -e "  ${GRAY}Cancelled${NC}"
                        ;;
                esac
            fi
            ;;
    esac

    echo ""
}

main "$@"
