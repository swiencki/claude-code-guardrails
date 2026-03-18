#!/usr/bin/env bash
#
# Merges hook and permission layer fragments into a Claude Code settings.json
#
# Usage:
#   ./scripts/build-settings.sh                          # merge all, output to repo .claude/settings.json
#   ./scripts/build-settings.sh --target user             # install to ~/.claude/settings.json
#   ./scripts/build-settings.sh --target /path/to/project  # install to project's .claude/settings.json
#   ./scripts/build-settings.sh --hooks-only              # merge only hooks
#   ./scripts/build-settings.sh --permissions-only        # merge only permissions
#   ./scripts/build-settings.sh --list                    # list available fragments
#   ./scripts/build-settings.sh --dry-run                 # preview without writing
#
# The script merges guardrail fragments into the target settings.json while
# preserving any existing settings (model, plugins, etc.).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_DIR="$REPO_ROOT/layers/2-hooks"
PERMS_DIR="$REPO_ROOT/layers/3-permissions"

# Defaults
TARGET="project"
MODE="all"
DRY_RUN=false

if ! command -v jq &>/dev/null; then
    echo "Error: jq is required." >&2
    echo "  Fedora/RHEL: sudo dnf install jq" >&2
    echo "  Ubuntu/Debian: sudo apt install jq" >&2
    echo "  macOS: brew install jq" >&2
    exit 1
fi

usage() {
    cat <<'USAGE'
Usage: build-settings.sh [OPTIONS]

Options:
  --target <location>     Where to install settings (default: project)
                            user      - ~/.claude/settings.json (all projects)
                            project   - this repo's .claude/settings.json
                            <path>    - a specific project directory
  --hooks-only            Only merge hooks (skip permissions)
  --permissions-only      Only merge permissions (skip hooks)
  --dry-run               Preview the merged output without writing
  --list                  List available hook and permission fragments
  --help, -h              Show this help

Examples:
  # Install guardrails to your user-level settings
  ./scripts/build-settings.sh --target user

  # Preview what would be generated
  ./scripts/build-settings.sh --dry-run

  # Install hooks only to another project
  ./scripts/build-settings.sh --target ~/my-project --hooks-only
USAGE
}

resolve_output() {
    case "$TARGET" in
        user)
            echo "$HOME/.claude/settings.json"
            ;;
        project)
            echo "$REPO_ROOT/.claude/settings.json"
            ;;
        *)
            # Treat as a path to a project directory
            local dir="$TARGET"
            if [ ! -d "$dir" ]; then
                echo "Error: target directory does not exist: $dir" >&2
                exit 1
            fi
            echo "$dir/.claude/settings.json"
            ;;
    esac
}

list_fragments() {
    echo "Available hook fragments (layers/2-hooks/):"
    for f in "$HOOKS_DIR"/*.json; do
        [ -f "$f" ] || continue
        desc=$(jq -r '.description // "No description"' "$f")
        echo "  $(basename "$f"): $desc"
    done
    echo ""
    echo "Available permission presets (layers/3-permissions/):"
    for f in "$PERMS_DIR"/*.json; do
        [ -f "$f" ] || continue
        desc=$(jq -r '.description // "No description"' "$f")
        echo "  $(basename "$f"): $desc"
    done
}

merge_hooks() {
    local result='{"hooks":{"PreToolUse":[]}}'

    for f in "$HOOKS_DIR"/*.json; do
        [ -f "$f" ] || continue
        local entries
        entries=$(jq '.hooks.PreToolUse // []' "$f")
        result=$(echo "$result" | jq --argjson new "$entries" '.hooks.PreToolUse += $new')
    done

    # Consolidate entries by matcher: merge hooks arrays for same matcher
    result=$(echo "$result" | jq '
        .hooks.PreToolUse = (
            .hooks.PreToolUse
            | group_by(.matcher)
            | map({
                matcher: .[0].matcher,
                hooks: [.[].hooks[]]
            })
        )
    ')

    echo "$result"
}

merge_permissions() {
    local result='{"permissions":{"allow":[],"deny":[]}}'

    for f in "$PERMS_DIR"/*.json; do
        [ -f "$f" ] || continue
        local perms
        perms=$(jq '{allow: (.permissions.allow // []), deny: (.permissions.deny // [])}' "$f")
        result=$(echo "$result" | jq --argjson new "$perms" '
            .permissions.allow = (.permissions.allow + $new.allow | unique) |
            .permissions.deny = (.permissions.deny + $new.deny | unique)
        ')
    done

    echo "$result"
}

# Parse args
while [ $# -gt 0 ]; do
    case "$1" in
        --target)
            TARGET="${2:?--target requires a value (user, project, or a path)}"
            shift 2
            ;;
        --hooks-only)
            MODE="hooks"
            shift
            ;;
        --permissions-only)
            MODE="permissions"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --list)
            list_fragments
            exit 0
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

OUTPUT=$(resolve_output)

# Build the guardrail portion
case "$MODE" in
    hooks)
        generated=$(merge_hooks)
        ;;
    permissions)
        generated=$(merge_permissions)
        ;;
    all)
        hooks=$(merge_hooks)
        perms=$(merge_permissions)
        generated=$(echo "$hooks" | jq --argjson perms "$(echo "$perms" | jq '.permissions')" \
            '. + {permissions: $perms}')
        ;;
esac

# Merge into existing settings if the file already exists
if [ -f "$OUTPUT" ]; then
    existing=$(cat "$OUTPUT")
    # Deep merge: existing settings are the base, generated guardrails overlay
    # Existing non-guardrail keys (model, plugins, etc.) are preserved
    merged=$(echo "$existing" | jq --argjson gen "$generated" '
        # Merge hooks: combine PreToolUse arrays, consolidate by matcher
        (if $gen.hooks then
            ($gen.hooks.PreToolUse // []) as $new_hooks |
            (.hooks.PreToolUse // []) as $old_hooks |
            ($old_hooks + $new_hooks
                | group_by(.matcher)
                | map({
                    matcher: .[0].matcher,
                    hooks: [.[].hooks[]] | unique_by(.command)
                })
            ) as $combined |
            .hooks.PreToolUse = $combined
        else . end) |

        # Merge permissions: union allow/deny arrays
        (if $gen.permissions then
            .permissions.allow = ((.permissions.allow // []) + ($gen.permissions.allow // []) | unique) |
            .permissions.deny = ((.permissions.deny // []) + ($gen.permissions.deny // []) | unique)
        else . end)
    ')
    final="$merged"
else
    final="$generated"
fi

# Format
final=$(echo "$final" | jq '.')

if $DRY_RUN; then
    echo "# Would write to: $OUTPUT"
    echo "$final"
    echo ""
    echo "# Summary:"
else
    mkdir -p "$(dirname "$OUTPUT")"
    echo "$final" > "$OUTPUT"
    echo "Written to: $OUTPUT"
    echo ""
fi

echo "Hooks:"
echo "$final" | jq -r '.hooks.PreToolUse[]? | "  [\(.matcher)] \(.hooks | length) hook(s)"'
echo ""
echo "Permissions:"
echo "$final" | jq -r '.permissions // {} | "  allow: \(.allow // [] | length) rules, deny: \(.deny // [] | length) rules"'

if ! $DRY_RUN && [ -f "$OUTPUT" ]; then
    echo ""
    echo "Existing settings preserved (model, plugins, etc.)"
fi
