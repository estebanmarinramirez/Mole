#!/bin/bash
# Mole macOS Defaults Tuner
# Toggle power-user macOS settings with automatic backup.
# Usage: mo defaults [--list] [--all] [--reset] [--dry-run]

set -euo pipefail

export LC_ALL=C
export LANG=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/core/common.sh"
source "$SCRIPT_DIR/lib/manage/defaults_tuner.sh"

cleanup_all() {
    stop_inline_spinner 2>/dev/null || true
    cleanup_temp_files
}

handle_interrupt() {
    cleanup_all
    exit 130
}

show_defaults_help() {
    echo ""
    echo -e "${PURPLE_BOLD}macOS Defaults Tuner${NC}"
    echo ""
    echo "  Toggle curated power-user macOS settings."
    echo "  Original values are backed up before any change."
    echo ""
    echo -e "${BLUE}Usage:${NC}"
    echo "  mo defaults            Interactive toggle menu"
    echo "  mo defaults --list     Show all settings and current state"
    echo "  mo defaults --all      Enable all power-user settings"
    echo "  mo defaults --reset    Restore all original values"
    echo "  mo defaults --dry-run  Preview changes without applying"
    echo ""
    echo -e "${BLUE}Settings include:${NC}"
    echo "  Finder       Hidden files, extensions, path bar, status bar"
    echo "  Dock         Autohide delay, animation speed"
    echo "  Input        Key repeat, disable autocorrect/smart quotes"
    echo "  Dialogs      Expand save/print dialogs by default"
    echo "  Desktop      No .DS_Store on network/USB drives"
    echo "  System       Crash reporter, screenshot format"
    echo ""
    echo -e "${BLUE}Backup:${NC}"
    echo "  Original values saved to ~/.config/mole/defaults_backup/"
    echo "  Use --reset to restore all backed-up values at any time."
    echo ""
}

main() {
    trap cleanup_all EXIT
    trap handle_interrupt INT TERM

    local mode="interactive"

    for arg in "$@"; do
        case "$arg" in
            --list | -l)
                mode="list"
                ;;
            --all | -a)
                mode="all"
                ;;
            --reset | -r)
                mode="reset"
                ;;
            --help | -h)
                show_defaults_help
                exit 0
                ;;
            --dry-run | -n)
                export MOLE_DRY_RUN=1
                ;;
            *)
                echo "Unknown option: $arg"
                echo "Use 'mo defaults --help' for usage."
                exit 1
                ;;
        esac
    done

    if [[ -t 1 ]]; then
        clear
    fi

    echo ""
    echo -e "${PURPLE_BOLD}macOS Defaults Tuner${NC}"
    echo ""

    if [[ "${MOLE_DRY_RUN:-0}" == "1" && "$mode" != "list" ]]; then
        echo -e "${YELLOW}${ICON_DRY_RUN} DRY RUN MODE${NC} - no changes will be made"
        echo ""
    fi

    case "$mode" in
        list)
            list_defaults
            ;;
        all)
            enable_all
            ;;
        reset)
            reset_defaults
            ;;
        interactive)
            # Show current state first
            list_defaults
            echo ""

            echo -ne "${PURPLE}${ICON_ARROW}${NC} Toggle individual settings? ${GRAY}Enter confirm / Q cancel${NC}: "
            local key
            IFS= read -r -s -n1 key || key=""
            echo ""

            case "$key" in
                "" | $'\n' | $'\r')
                    interactive_toggle
                    ;;
                *)
                    echo -e "  ${GRAY}Cancelled${NC}"
                    ;;
            esac
            ;;
    esac

    echo ""
}

main "$@"
