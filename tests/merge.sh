#!/usr/bin/env bash
# Tests: merging into existing settings, idempotency

source "$(dirname "$0")/helpers.sh"

echo "=== Merge ==="

# Merge all layers into existing settings
MERGE_TARGET="$TEST_TMPDIR/merge-existing"
mkdir -p "$MERGE_TARGET/.claude"
cat > "$MERGE_TARGET/.claude/settings.json" <<'EXISTING'
{
  "model": "claude-opus-4-6[1m]",
  "alwaysThinkingEnabled": true,
  "enabledPlugins": {
    "jira@ai-helpers": true
  }
}
EXISTING

$MAKE build TARGET="$MERGE_TARGET" &>/dev/null
OUTPUT="$MERGE_TARGET/.claude/settings.json"

assert_json_value "$OUTPUT" '.model' 'claude-opus-4-6[1m]' "preserves model"
assert_json_value "$OUTPUT" '.alwaysThinkingEnabled' 'true' "preserves alwaysThinkingEnabled"
assert_json_value "$OUTPUT" '.enabledPlugins["jira@ai-helpers"]' 'true' "preserves enabledPlugins"
assert_json_has_key "$OUTPUT" '.hooks.PreToolUse' "adds hooks"
assert_json_has_key "$OUTPUT" '.permissions' "adds permissions"

# Merge single layer - should not touch other settings
MERGE_HOOKS_TARGET="$TEST_TMPDIR/merge-hooks-only"
mkdir -p "$MERGE_HOOKS_TARGET/.claude"
cat > "$MERGE_HOOKS_TARGET/.claude/settings.json" <<'EXISTING'
{
  "model": "claude-opus-4-6[1m]",
  "permissions": {
    "allow": ["Read"],
    "deny": ["Bash(rm *)"]
  }
}
EXISTING

$MAKE build TARGET="$MERGE_HOOKS_TARGET" LAYERS=hooks &>/dev/null
OUTPUT="$MERGE_HOOKS_TARGET/.claude/settings.json"

assert_json_value "$OUTPUT" '.model' 'claude-opus-4-6[1m]' "single layer: preserves model"
assert_json_has_key "$OUTPUT" '.hooks.PreToolUse' "single layer: adds hooks"
assert_json_value "$OUTPUT" '.permissions.allow | length' '1' "single layer: existing allow untouched"
assert_json_value "$OUTPUT" '.permissions.deny | length' '1' "single layer: existing deny untouched"

# Idempotency - running twice should produce same result
IDEM_TARGET="$TEST_TMPDIR/idempotent"
mkdir -p "$IDEM_TARGET"
$MAKE build TARGET="$IDEM_TARGET" &>/dev/null
FIRST_COUNT=$(jq '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks | length' "$IDEM_TARGET/.claude/settings.json")

$MAKE build TARGET="$IDEM_TARGET" &>/dev/null
SECOND_COUNT=$(jq '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks | length' "$IDEM_TARGET/.claude/settings.json")

if [ "$FIRST_COUNT" -eq "$SECOND_COUNT" ]; then
    pass "idempotent: no duplicates after two runs ($FIRST_COUNT both times)"
else
    fail "idempotent: no duplicates after two runs" "first: $FIRST_COUNT, second: $SECOND_COUNT"
fi

print_results
