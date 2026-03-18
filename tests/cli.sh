#!/usr/bin/env bash
# Tests: CLI options, help, list, dry-run

source "$(dirname "$0")/helpers.sh"

echo "=== CLI ==="

assert_exit_code 0 "make help exits 0" $MAKE help
assert_exit_code 0 "make list exits 0" $MAKE list
assert_output_contains "Usage:" "help shows usage" $MAKE help
assert_output_contains "LAYERS" "help documents LAYERS" $MAKE help
assert_output_contains "azure-safety.json" "list shows hook fragments" $MAKE list
assert_output_contains "standard-dev.json" "list shows permission presets" $MAKE list

DRY_TARGET="$TEST_TMPDIR/dry-run"
mkdir -p "$DRY_TARGET"
$MAKE dry-run TARGET="$DRY_TARGET" &>/dev/null
assert_file_not_exists "$DRY_TARGET/.claude/settings.json" "dry-run does not write file"
assert_output_contains "Would write to" "dry-run shows target path" $MAKE dry-run TARGET="$DRY_TARGET"

assert_exit_code 2 "nonexistent target exits non-zero" $MAKE build TARGET=/tmp/does-not-exist-at-all
assert_exit_code 2 "invalid layer exits non-zero" $MAKE build TARGET="$TEST_TMPDIR/invalid-layer" LAYERS=bogus
assert_output_contains "$HOME/.claude/settings.json" "TARGET=user resolves to home dir" $MAKE dry-run TARGET=user

print_results
