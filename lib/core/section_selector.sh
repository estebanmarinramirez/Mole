#!/bin/bash
# Mole - Interactive Section Selector for Clean.
# Presents a checklist of cleanup sections and lets the user choose.

if [[ -n "${MOLE_SECTION_SELECTOR_LOADED:-}" ]]; then
    return 0
fi
readonly MOLE_SECTION_SELECTOR_LOADED=1

# All available cleanup sections.
# Format: "key|label|default_on"
# default_on: 1 = selected by default, 0 = not selected
readonly -a CLEAN_SECTIONS=(
    "system|System (crash reports, logs)|1"
    "user|User essentials (caches, trash, metadata)|1"
    "app_caches|App caches (sandboxed + standard)|1"
    "browsers|Browsers (Safari, Chrome, Edge, Firefox)|1"
    "cloud|Cloud and Office (Dropbox, OneDrive, MS Office)|1"
    "dev|Developer tools (npm, pip, Go, Python, Xcode)|1"
    "apps|Applications (user GUI apps)|1"
    "virt|Virtualization (Docker, VMware, Parallels)|1"
    "support|Application Support (logs, caches)|1"
    "orphans|Orphaned data (removed apps)|1"
    "silicon|Apple Silicon updates|1"
    "backups|Device backups (iOS/iPadOS)|1"
    "timemachine|Time Machine|1"
    "large|Large files scan|1"
    "sysdata|System Data clues|1"
    "projects|Project artifacts|1"
)

# Present interactive section selector.
# Sets the global SELECTED_SECTIONS array.
# Returns 0 if user confirms, 1 if user cancels.
select_clean_sections() {
    # Initialize selection state (all on by default).
    local -a selected=()
    local -a keys=()
    local -a labels=()
    local i

    for i in "${!CLEAN_SECTIONS[@]}"; do
        local entry="${CLEAN_SECTIONS[$i]}"
        local key="${entry%%|*}"
        local rest="${entry#*|}"
        local label="${rest%%|*}"
        local default_on="${rest##*|}"

        keys+=("$key")
        labels+=("$label")
        selected+=("$default_on")
    done

    local total=${#keys[@]}
    local cursor=0
    local done=false

    # Save cursor state and prepare screen.
    printf '\033[?25l'  # Hide cursor

    while [[ "$done" == "false" ]]; do
        # Render the menu.
        printf '\033[2J\033[H'  # Clear screen
        echo ""
        echo -e "${PURPLE_BOLD}Select Sections to Clean${NC}"
        echo -e "${GRAY}Space=toggle  A=all  N=none  Enter=confirm  Q=cancel${NC}"
        echo ""

        for i in "${!keys[@]}"; do
            local marker="  "
            if [[ $i -eq $cursor ]]; then
                marker="${BLUE}>${NC} "
            fi

            local check
            if [[ "${selected[$i]}" == "1" ]]; then
                check="${GREEN}[x]${NC}"
            else
                check="${GRAY}[ ]${NC}"
            fi

            local label_color="$NC"
            if [[ $i -eq $cursor ]]; then
                label_color="${BLUE}"
            fi

            echo -e "  ${marker}${check} ${label_color}${labels[$i]}${NC}"
        done

        echo ""
        local sel_count=0
        for s in "${selected[@]}"; do
            [[ "$s" == "1" ]] && sel_count=$((sel_count + 1))
        done
        echo -e "  ${GRAY}$sel_count of $total selected${NC}"

        # Read a single keypress.
        local key_input=""
        IFS= read -rsn1 key_input

        # Handle escape sequences (arrow keys).
        if [[ "$key_input" == $'\033' ]]; then
            local seq1="" seq2=""
            IFS= read -rsn1 -t 0.1 seq1
            IFS= read -rsn1 -t 0.1 seq2
            case "${seq1}${seq2}" in
                "[A") # Up arrow
                    cursor=$(( (cursor - 1 + total) % total ))
                    ;;
                "[B") # Down arrow
                    cursor=$(( (cursor + 1) % total ))
                    ;;
            esac
            continue
        fi

        case "$key_input" in
            " ") # Space: toggle current
                if [[ "${selected[$cursor]}" == "1" ]]; then
                    selected[$cursor]="0"
                else
                    selected[$cursor]="1"
                fi
                ;;
            "j"|"J") # Vim down
                cursor=$(( (cursor + 1) % total ))
                ;;
            "k"|"K") # Vim up
                cursor=$(( (cursor - 1 + total) % total ))
                ;;
            "a"|"A") # Select all
                for i in "${!selected[@]}"; do
                    selected[$i]="1"
                done
                ;;
            "n"|"N") # Select none
                for i in "${!selected[@]}"; do
                    selected[$i]="0"
                done
                ;;
            "q"|"Q") # Cancel
                printf '\033[?25h'  # Show cursor
                return 1
                ;;
            "") # Enter: confirm
                done=true
                ;;
        esac
    done

    printf '\033[?25h'  # Show cursor

    # Export selected sections.
    SELECTED_SECTIONS=()
    for i in "${!keys[@]}"; do
        if [[ "${selected[$i]}" == "1" ]]; then
            SELECTED_SECTIONS+=("${keys[$i]}")
        fi
    done

    return 0
}

# Check if a section key is in the selected set.
# Usage: is_section_selected "dev"
is_section_selected() {
    local key="$1"

    # If no selection mode, everything is selected.
    if [[ "${MOLE_SELECT_MODE:-}" != "1" ]]; then
        return 0
    fi

    local s
    for s in "${SELECTED_SECTIONS[@]+"${SELECTED_SECTIONS[@]}"}"; do
        [[ "$s" == "$key" ]] && return 0
    done
    return 1
}
