#!/bin/bash
# Mole Login Items Manager
# View, manage, and clean orphaned macOS startup items.
# Usage: mo login [--list] [--orphans] [--dry-run] [--debug]

set -euo pipefail

# Fix locale
export LC_ALL=C
export LANG=C

# Load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/core/common.sh"
source "$SCRIPT_DIR/lib/manage/login_items.sh"

cleanup_all() {
    stop_inline_spinner 2>/dev/null || true
    cleanup_temp_files
}

handle_interrupt() {
    cleanup_all
    exit 130
}

show_login_help() {
    echo ""
    echo -e "${PURPLE_BOLD}Login Items Manager${NC}"
    echo ""
    echo "  View and manage macOS startup items, LaunchAgents, and LaunchDaemons."
    echo "  Detect orphaned agents from uninstalled applications."
    echo ""
    echo -e "${BLUE}Usage:${NC}"
    echo "  mo login               Interactive agent manager"
    echo "  mo login --list        List all startup items"
    echo "  mo login --orphans     Show orphaned agents only"
    echo "  mo login --dry-run     Preview changes without applying"
    echo ""
    echo -e "${BLUE}Sources scanned:${NC}"
    echo "  Login Items            System Preferences login items"
    echo "  User LaunchAgents      ~/Library/LaunchAgents/"
    echo "  System LaunchAgents    /Library/LaunchAgents/"
    echo "  System LaunchDaemons   /Library/LaunchDaemons/"
    echo ""
    echo -e "${BLUE}Orphan detection:${NC}"
    echo "  Checks if the binary referenced by each agent still exists."
    echo "  Also verifies parent .app bundle in /Applications."
    echo ""
}

main() {
    # Register cleanup handlers
    trap cleanup_all EXIT
    trap handle_interrupt INT TERM

    local mode="interactive"

    for arg in "$@"; do
        case "$arg" in
            --list | -l)
                mode="list"
                ;;
            --orphans | -o)
                mode="orphans"
                ;;
            --help | -h)
                show_login_help
                exit 0
                ;;
            --dry-run | -n)
                export MOLE_DRY_RUN=1
                ;;
            *)
                echo "Unknown option: $arg"
                echo "Use 'mo login --help' for usage."
                exit 1
                ;;
        esac
    done

    if [[ -t 1 ]]; then
        clear
    fi

    echo ""
    echo -e "${PURPLE_BOLD}Login Items Manager${NC}"
    echo ""

    case "$mode" in
        list)
            list_all_items "false"
            ;;
        orphans)
            list_all_items "true"
            ;;
        interactive)
            # Show overview first
            list_all_items "false"
            echo ""

            echo -ne "${PURPLE}${ICON_ARROW}${NC} Manage user LaunchAgents? ${GRAY}Enter confirm / Q cancel${NC}: "
            local key
            IFS= read -r -s -n1 key || key=""
            echo ""

            case "$key" in
                "" | $'\n' | $'\r')
                    interactive_manage
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
