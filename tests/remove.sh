#!/usr/bin/env bash
# Tests: make remove
# shellcheck source=tests/helpers.sh
source "$(dirname "$0")/helpers.sh"

echo "=== Remove ==="

# shellcheck disable=SC2086 # $MAKE intentionally word-splits
{
# Build all, then remove hooks
REMOVE_TARGET="$TEST_TMPDIR/remove-hooks"
mkdir -p "$REMOVE_TARGET"
$MAKE build TARGET="$REMOVE_TARGET" &>/dev/null
$MAKE remove TARGET="$REMOVE_TARGET" LAYERS=hooks &>/dev/null
OUTPUT="$REMOVE_TARGET/.claude/settings.json"

assert_json_missing_key "$OUTPUT" '.hooks' "remove hooks: hooks key removed"
assert_json_has_key "$OUTPUT" '.permissions' "remove hooks: permissions preserved"

# Build all, then remove permissions
REMOVE_TARGET2="$TEST_TMPDIR/remove-perms"
mkdir -p "$REMOVE_TARGET2"
$MAKE build TARGET="$REMOVE_TARGET2" &>/dev/null
$MAKE remove TARGET="$REMOVE_TARGET2" LAYERS=permissions &>/dev/null
OUTPUT="$REMOVE_TARGET2/.claude/settings.json"

assert_json_has_key "$OUTPUT" '.hooks' "remove permissions: hooks preserved"
assert_json_missing_key "$OUTPUT" '.permissions' "remove permissions: permissions key removed"

# Build all, remove all
REMOVE_TARGET3="$TEST_TMPDIR/remove-all"
mkdir -p "$REMOVE_TARGET3"
$MAKE build TARGET="$REMOVE_TARGET3" &>/dev/null
$MAKE remove TARGET="$REMOVE_TARGET3" &>/dev/null
OUTPUT="$REMOVE_TARGET3/.claude/settings.json"

assert_json_missing_key "$OUTPUT" '.hooks' "remove all: hooks removed"
assert_json_missing_key "$OUTPUT" '.permissions' "remove all: permissions removed"

# Remove preserves other settings
REMOVE_TARGET4="$TEST_TMPDIR/remove-preserve"
mkdir -p "$REMOVE_TARGET4/.claude"
cat > "$REMOVE_TARGET4/.claude/settings.json" <<'EXISTING'
{
  "model": "claude-opus-4-6[1m]",
  "hooks": {
    "PreToolUse": [{"matcher": "Bash", "hooks": []}]
  },
  "permissions": {
    "allow": ["Read"],
    "deny": []
  }
}
EXISTING

$MAKE remove TARGET="$REMOVE_TARGET4" LAYERS=hooks &>/dev/null
OUTPUT="$REMOVE_TARGET4/.claude/settings.json"

assert_json_value "$OUTPUT" '.model' 'claude-opus-4-6[1m]' "remove preserves model"
assert_json_missing_key "$OUTPUT" '.hooks' "remove clears hooks"
assert_json_has_key "$OUTPUT" '.permissions' "remove keeps permissions"
}

print_results
