#!/usr/bin/env bash
#
# Merges hook and permission layer fragments into .claude/settings.json
#
# Usage:
#   ./scripts/build-settings.sh                    # merge all layers
#   ./scripts/build-settings.sh --hooks-only       # merge only hooks
#   ./scripts/build-settings.sh --permissions-only  # merge only permissions
#   ./scripts/build-settings.sh --list             # list available fragments
#
# Each fragment in layers/2-hooks/ defines hooks under .hooks.PreToolUse[]
# Each fragment in layers/3-permissions/ defines .permissions.allow[] and .permissions.deny[]
# The script deep-merges all fragments into a single .claude/settings.json

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_DIR="$REPO_ROOT/layers/2-hooks"
PERMS_DIR="$REPO_ROOT/layers/3-permissions"
OUTPUT="$REPO_ROOT/.claude/settings.json"

if ! command -v jq &>/dev/null; then
    echo "Error: jq is required. Install it with: sudo dnf install jq" >&2
    exit 1
fi

list_fragments() {
    echo "Available hook fragments:"
    for f in "$HOOKS_DIR"/*.json; do
        [ -f "$f" ] || continue
        desc=$(jq -r '.description // "No description"' "$f")
        echo "  $(basename "$f"): $desc"
    done
    echo ""
    echo "Available permission presets:"
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
        # Extract PreToolUse entries and append them
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
MODE="all"
case "${1:-}" in
    --hooks-only)     MODE="hooks" ;;
    --permissions-only) MODE="permissions" ;;
    --list)           list_fragments; exit 0 ;;
    --help|-h)
        echo "Usage: $0 [--hooks-only|--permissions-only|--list|--help]"
        exit 0
        ;;
esac

# Build
mkdir -p "$(dirname "$OUTPUT")"

case "$MODE" in
    hooks)
        merge_hooks | jq '.' > "$OUTPUT"
        ;;
    permissions)
        merge_permissions | jq '.' > "$OUTPUT"
        ;;
    all)
        hooks=$(merge_hooks)
        perms=$(merge_permissions)
        echo "$hooks" | jq --argjson perms "$(echo "$perms" | jq '.permissions')" \
            '. + {permissions: $perms}' > "$OUTPUT"
        ;;
esac

echo "Generated $OUTPUT"
echo ""
echo "Hooks:"
jq -r '.hooks.PreToolUse[]? | "  [\(.matcher)] \(.hooks | length) hook(s)"' "$OUTPUT"
echo ""
echo "Permissions:"
jq -r '.permissions // {} | "  allow: \(.allow // [] | length) rules, deny: \(.deny // [] | length) rules"' "$OUTPUT"
