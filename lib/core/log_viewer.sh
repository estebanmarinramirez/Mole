#!/bin/bash
# Mole - Operations Log Viewer.
# Shows grouped summary of the last clean/purge/uninstall session.

if [[ -n "${MOLE_LOG_VIEWER_LOADED:-}" ]]; then
    return 0
fi
readonly MOLE_LOG_VIEWER_LOADED=1

# Extract all log lines for a given session (between its start marker and the next).
# Args: $1 = log file, $2 = session start line number
_extract_session_lines() {
    local log_file="$1"
    local start_line="$2"
    local total_lines
    total_lines=$(wc -l < "$log_file" | tr -d ' ')

    # Find next session marker after start_line.
    local end_line="$total_lines"
    local next_session
    next_session=$(tail -n +"$((start_line + 1))" "$log_file" | grep -n 'session started' | head -1 | cut -d: -f1 || true)
    if [[ -n "$next_session" ]]; then
        end_line=$((start_line + next_session - 1))
    fi

    sed -n "${start_line},${end_line}p" "$log_file"
}

# Show the last operations session for a given command.
# Usage: show_operations_log [command] [--all]
# Finds the most recent session that actually removed files.
show_operations_log() {
    local target_command="${1:-clean}"
    local show_all="${2:-}"
    local log_file="${HOME}/.config/mole/operations.log"

    if [[ ! -f "$log_file" ]]; then
        echo -e "${YELLOW}No operations log found.${NC}"
        echo -e "${GRAY}Run mo $target_command to create one.${NC}"
        return 0
    fi

    # Find all session start line numbers (newest last).
    local -a session_line_nums=()
    local match
    while IFS= read -r match; do
        local linenum
        linenum=$(echo "$match" | cut -d: -f1)
        session_line_nums+=("$linenum")
    done < <(grep -n "$target_command session started" "$log_file" || true)

    if [[ ${#session_line_nums[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No $target_command sessions found in log.${NC}"
        return 0
    fi

    # Find the most recent session that has REMOVED entries.
    local chosen_line=""
    local session_lines_tmp
    session_lines_tmp=$(mktemp)
    local i
    for (( i=${#session_line_nums[@]}-1; i>=0; i-- )); do
        _extract_session_lines "$log_file" "${session_line_nums[$i]}" > "$session_lines_tmp"
        if grep -q 'REMOVED' "$session_lines_tmp" 2>/dev/null; then
            chosen_line="${session_line_nums[$i]}"
            break
        fi
    done

    # Fallback: use the absolute last session.
    if [[ -z "$chosen_line" ]]; then
        chosen_line="${session_line_nums[${#session_line_nums[@]}-1]}"
        _extract_session_lines "$log_file" "$chosen_line" > "$session_lines_tmp"
    fi

    # Extract session timestamp for display.
    local session_header
    session_header=$(grep 'session started' "$session_lines_tmp" | head -1 || true)
    local session_ts
    session_ts=$(echo "$session_header" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}' || true)
    [[ -z "$session_ts" ]] && session_ts="unknown"

    # Count operations.
    local removed_count skipped_count failed_count
    removed_count=$(grep -c 'REMOVED' "$session_lines_tmp" || true)
    skipped_count=$(grep -c 'SKIPPED' "$session_lines_tmp" || true)
    failed_count=$(grep -c 'FAILED' "$session_lines_tmp" || true)

    # Header.
    echo ""
    echo -e "${PURPLE_BOLD}Last Clean Session${NC}"
    echo -e "${GRAY}$session_ts${NC}"
    echo ""

    # Summary line.
    local summary=""
    if [[ $removed_count -gt 0 ]]; then
        summary="${GREEN}${removed_count} removed${NC}"
    fi
    if [[ $skipped_count -gt 0 ]]; then
        [[ -n "$summary" ]] && summary="${summary}, "
        summary="${summary}${BLUE}${skipped_count} protected${NC}"
    fi
    if [[ $failed_count -gt 0 ]]; then
        [[ -n "$summary" ]] && summary="${summary}, "
        summary="${summary}${YELLOW}${failed_count} failed${NC}"
    fi
    echo -e "  $summary"
    echo ""

    if [[ $removed_count -eq 0 ]]; then
        echo -e "  ${GREEN}No files were removed in this session.${NC}"
        rm -f "$session_lines_tmp"
        return 0
    fi

    # Extract just REMOVED paths.
    local tmp_removed
    tmp_removed=$(mktemp)
    grep 'REMOVED' "$session_lines_tmp" | sed 's/.*REMOVED //' > "$tmp_removed"

    # ----- Developer project caches -----
    local dev_count
    dev_count=$(grep -c 'Developer/' "$tmp_removed" || true)

    if [[ $dev_count -gt 0 ]]; then
        echo -e "  ${BLUE}Developer Projects${NC} ($dev_count files)"

        local prev_project=""
        while IFS= read -r project_root; do
            [[ -z "$project_root" ]] && continue
            [[ "$project_root" == "$prev_project" ]] && continue
            prev_project="$project_root"

            # Count files and total size.
            local proj_files proj_size
            proj_files=$(grep -cF "$project_root" "$tmp_removed" 2>/dev/null || true)
            proj_size=$(grep -F "$project_root" "$tmp_removed" | grep -oE '[0-9]+KB' | sed 's/KB//' | awk '{s+=$1} END {print s+0}' || true)
            [[ -z "$proj_size" ]] && proj_size=0

            local size_human="${proj_size}KB"
            if [[ $proj_size -ge 1024 ]]; then
                size_human="$((proj_size / 1024))MB"
            fi

            local display
            display=$(echo "$project_root" | sed "s|$HOME/|~/|")
            echo -e "    ${GREEN}$display${NC} ${GRAY}($proj_files files, $size_human)${NC}"
        done < <(grep 'Developer/' "$tmp_removed" | sed 's/ (.*//' | \
            sed "s|\($HOME/Developer/[^/]*/[^/]*/[^/]*/[^/]*/[^/]*\)/.*|\1|" | \
            sed "s|\($HOME/Developer/[^/]*/[^/]*/[^/]*/[^/]*\)/.*|\1|" | \
            sort -u || true)
        echo ""
    fi

    # ----- System caches -----
    local sys_lines_tmp
    sys_lines_tmp=$(mktemp)
    grep -v 'Developer/' "$tmp_removed" > "$sys_lines_tmp" || true
    local sys_count
    sys_count=$(wc -l < "$sys_lines_tmp" | tr -d ' ')

    if [[ "$sys_count" -gt 0 ]]; then
        echo -e "  ${BLUE}System Caches${NC} ($sys_count files)"

        local category
        while IFS= read -r category; do
            [[ -z "$category" ]] && continue

            local cat_count cat_size
            cat_count=$(grep -cF "$category" "$sys_lines_tmp" 2>/dev/null || true)
            cat_size=$(grep -F "$category" "$sys_lines_tmp" | grep -oE '[0-9]+KB' | sed 's/KB//' | awk '{s+=$1} END {print s+0}' || true)
            [[ -z "$cat_size" ]] && cat_size=0

            local size_human="${cat_size}KB"
            if [[ $cat_size -ge 1024 ]]; then
                size_human="$((cat_size / 1024))MB"
            fi

            local display_cat
            display_cat=$(echo "$category" | sed "s|$HOME/|~/|")
            echo -e "    ${GREEN}$display_cat${NC} ${GRAY}($cat_count files, $size_human)${NC}"
        done < <(sed 's/ (.*//' "$sys_lines_tmp" | \
            sed "s|^\($HOME/\.[^/]*\)/.*|\1|" | \
            sed "s|^\($HOME/Library/Application Support/[^/]*\)/.*|\1|" | \
            sed "s|^\($HOME/Library/Containers/[^/]*\)/.*|\1|" | \
            sed "s|^\($HOME/Library/[^/]*\)/.*|\1|" | \
            sed "s|^\(/private/var/[^/]*/[^/]*\)/.*|\1|" | \
            sed "s|^\(/Library/[^/]*/[^/]*\)/.*|\1|" | \
            sort -u || true)
        echo ""
    fi

    # Full list if --all requested.
    if [[ "$show_all" == "--all" || "$show_all" == "-a" ]]; then
        echo -e "  ${BLUE}Full Path List${NC}"
        while IFS= read -r line; do
            local path detail
            path=$(echo "$line" | sed 's/ (.*//' | sed "s|$HOME/|~/|")
            detail=$(echo "$line" | grep -oE '\([^)]*\)' || true)
            echo -e "    ${GRAY}$path${NC} ${GREEN}$detail${NC}"
        done < "$tmp_removed"
        echo ""
    fi

    echo -e "  ${GRAY}Full log: ~/.config/mole/operations.log${NC}"
    echo ""

    rm -f "$session_lines_tmp" "$tmp_removed" "$sys_lines_tmp"
}
