#!/bin/bash
# Active Project Detection for safe cache cleaning.
# Prevents cleaning caches in projects being actively worked on.
set -euo pipefail

if [[ -n "${MOLE_ACTIVE_PROJECT_LOADED:-}" ]]; then
    return 0
fi
readonly MOLE_ACTIVE_PROJECT_LOADED=1

# Check whether a project directory is currently active (being worked on).
# A project is considered active if:
#   1. Git reports uncommitted changes (dirty working tree) - fastest check
#   2. Source files were modified within the last 2 hours
#   3. Any running process has the project dir as its cwd
# Returns 0 (true) if active, 1 (false) if safe to clean.
is_active_project() {
    local project_dir="$1"
    [[ -d "$project_dir" ]] || return 1

    # Resolve to absolute path for reliable comparisons.
    local abs_dir
    abs_dir=$(cd "$project_dir" 2>/dev/null && pwd) || abs_dir="$project_dir"

    # Check 1 (fastest): Uncommitted git changes (dirty working tree).
    if [[ -d "$abs_dir/.git" ]]; then
        local git_status
        git_status=$(git -C "$abs_dir" status --porcelain 2>/dev/null | head -1)
        if [[ -n "$git_status" ]]; then
            debug_log "Active project (uncommitted changes): $abs_dir"
            return 0
        fi
    fi

    # Check 2: Recent source file modifications (last 2 hours).
    # Only checks common source extensions to avoid false positives from logs.
    # Prunes heavy dirs to keep it fast.
    local recent_mod
    recent_mod=$(find "$abs_dir" -maxdepth 4 \
        \( -name "node_modules" -o -name ".git" -o -name "venv" -o -name ".venv" \
           -o -name "__pycache__" -o -name ".next" -o -name "target" -o -name "build" \) -prune -o \
        \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.jsx" -o -name "*.tsx" \
           -o -name "*.go" -o -name "*.rs" -o -name "*.rb" -o -name "*.dart" \
           -o -name "*.swift" -o -name "*.java" -o -name "*.kt" -o -name "*.c" -o -name "*.cpp" \
           -o -name "*.sh" -o -name "*.toml" -o -name "*.yaml" -o -name "*.yml" \) \
        -mmin -120 -print -quit 2>/dev/null || true)
    if [[ -n "$recent_mod" ]]; then
        debug_log "Active project (recent edits): $abs_dir"
        return 0
    fi

    # Check 3: Any process has its cwd inside this project.
    # Much faster than lsof +D; just checks /dev/fd/cwd per PID.
    local pid_cwd
    while IFS= read -r pid_cwd; do
        if [[ "$pid_cwd" == "$abs_dir"* ]]; then
            debug_log "Active project (process cwd): $abs_dir"
            return 0
        fi
    done < <(lsof -d cwd -Fn 2>/dev/null | grep '^n' | sed 's/^n//' | sort -u)

    return 1
}

# Resolve the project root from a cache directory path.
# Walks up from the cache dir looking for project indicators.
get_project_root() {
    local cache_dir="$1"
    local dir
    dir=$(dirname "$cache_dir")

    # Walk up max 6 levels looking for a project root.
    local i
    for i in 1 2 3 4 5 6; do
        if mole_purge_is_project_root "$dir"; then
            printf '%s\n' "$dir"
            return 0
        fi
        local parent
        parent=$(dirname "$dir")
        [[ "$parent" == "$dir" ]] && break
        dir="$parent"
    done

    # Fallback: use the parent of the cache dir.
    dirname "$cache_dir"
}
