#!/usr/bin/env bash
# Tests: make clean
# shellcheck source=tests/helpers.sh
source "$(dirname "$0")/helpers.sh"

echo "=== Clean ==="

# shellcheck disable=SC2086 # $MAKE intentionally word-splits
{
$MAKE build &>/dev/null
assert_file_exists "$REPO_ROOT/.claude/settings.json" "settings.json exists before clean"

$MAKE clean &>/dev/null
assert_file_not_exists "$REPO_ROOT/.claude/settings.json" "settings.json removed after clean"
}

print_results
