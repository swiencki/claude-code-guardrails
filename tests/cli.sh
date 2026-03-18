#!/usr/bin/env bash
# Tests: CLI options, help, list, dry-run
# shellcheck source=tests/helpers.sh
source "$(dirname "$0")/helpers.sh"

echo "=== CLI ==="

# shellcheck disable=SC2086 # $MAKE intentionally word-splits
{
assert_exit_code 0 "make help exits 0" $MAKE help
assert_exit_code 0 "make list exits 0" $MAKE list
assert_output_contains "Usage:" "help shows usage" $MAKE help
assert_output_contains "LAYERS" "help documents LAYERS" $MAKE help
assert_output_contains "DRY_RUN" "help documents DRY_RUN" $MAKE help
assert_output_contains "azure-safety.json" "list shows hook fragments" $MAKE list
assert_output_contains "standard-dev.json" "list shows permission presets" $MAKE list

# DRY_RUN on build
DRY_TARGET="$TEST_TMPDIR/dry-run"
mkdir -p "$DRY_TARGET"
$MAKE build TARGET="$DRY_TARGET" DRY_RUN=1 &>/dev/null
assert_file_not_exists "$DRY_TARGET/.claude/settings.json" "dry-run build does not write file"
assert_output_contains "Would write to" "dry-run build shows target path" $MAKE build TARGET="$DRY_TARGET" DRY_RUN=1

# DRY_RUN on remove
DRY_REMOVE_TARGET="$TEST_TMPDIR/dry-run-remove"
mkdir -p "$DRY_REMOVE_TARGET/.claude"
echo '{"hooks":{"PreToolUse":[]},"permissions":{"allow":[],"deny":[]}}' > "$DRY_REMOVE_TARGET/.claude/settings.json"
$MAKE remove TARGET="$DRY_REMOVE_TARGET" LAYERS=hooks DRY_RUN=1 &>/dev/null
assert_json_has_key "$DRY_REMOVE_TARGET/.claude/settings.json" '.hooks' "dry-run remove does not modify file"
assert_output_contains "Would write to" "dry-run remove shows target path" $MAKE remove TARGET="$DRY_REMOVE_TARGET" LAYERS=hooks DRY_RUN=1

assert_exit_code 2 "nonexistent target exits non-zero" $MAKE build TARGET=/tmp/does-not-exist-at-all
assert_exit_code 2 "invalid layer exits non-zero" $MAKE build TARGET="$TEST_TMPDIR/invalid-layer" LAYERS=bogus
assert_output_contains "$HOME/.claude/settings.json" "TARGET=user resolves to home dir" $MAKE build TARGET=user DRY_RUN=1
}

print_results
