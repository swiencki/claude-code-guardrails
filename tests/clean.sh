#!/usr/bin/env bash
# Tests: make clean

source "$(dirname "$0")/helpers.sh"

echo "=== Clean ==="

$MAKE build &>/dev/null
assert_file_exists "$REPO_ROOT/.claude/settings.json" "settings.json exists before clean"

$MAKE clean &>/dev/null
assert_file_not_exists "$REPO_ROOT/.claude/settings.json" "settings.json removed after clean"

print_results
