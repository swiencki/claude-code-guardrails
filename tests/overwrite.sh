#!/usr/bin/env bash
# Tests: overwrite=1 flag (replace vs merge)
# shellcheck source=tests/helpers.sh
source "$(dirname "$0")/helpers.sh"

echo "=== Overwrite ==="

# shellcheck disable=SC2086 # $MAKE intentionally word-splits
{

# Default (merge) preserves existing custom hooks
MERGE_TARGET="$TEST_TMPDIR/merge-keeps"
mkdir -p "$MERGE_TARGET/.claude"
cat > "$MERGE_TARGET/.claude/settings.json" <<'EXISTING'
{
  "model": "claude-opus-4-6[1m]",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "echo custom-hook",
            "statusMessage": "custom hook"
          }
        ]
      }
    ]
  }
}
EXISTING

$MAKE build target="$MERGE_TARGET" layers=hooks &>/dev/null
OUTPUT="$MERGE_TARGET/.claude/settings.json"

# Merge should keep the custom hook alongside the new ones
BASH_HOOK_COUNT=$(jq '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks | length' "$OUTPUT")
if [ "$BASH_HOOK_COUNT" -gt 22 ]; then
    pass "merge: custom hook preserved alongside new hooks ($BASH_HOOK_COUNT total)"
else
    fail "merge: custom hook preserved alongside new hooks" "expected > 22, got $BASH_HOOK_COUNT"
fi
assert_json_value "$OUTPUT" '.model' 'claude-opus-4-6[1m]' "merge: preserves model"

# Overwrite replaces existing hooks
OW_TARGET="$TEST_TMPDIR/overwrite-replaces"
mkdir -p "$OW_TARGET/.claude"
cat > "$OW_TARGET/.claude/settings.json" <<'EXISTING'
{
  "model": "claude-opus-4-6[1m]",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "echo custom-hook",
            "statusMessage": "custom hook"
          }
        ]
      }
    ]
  }
}
EXISTING

$MAKE build target="$OW_TARGET" layers=hooks overwrite=1 &>/dev/null
OUTPUT="$OW_TARGET/.claude/settings.json"

# Overwrite should have exactly 22 hooks (custom one gone)
BASH_HOOK_COUNT=$(jq '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks | length' "$OUTPUT")
if [ "$BASH_HOOK_COUNT" -eq 22 ]; then
    pass "overwrite: custom hook replaced (exactly 22 hooks)"
else
    fail "overwrite: custom hook replaced" "expected 22, got $BASH_HOOK_COUNT"
fi
assert_json_value "$OUTPUT" '.model' 'claude-opus-4-6[1m]' "overwrite: preserves model"

# Overwrite preserves non-guardrail settings
OW_PRESERVE="$TEST_TMPDIR/overwrite-preserve"
mkdir -p "$OW_PRESERVE/.claude"
cat > "$OW_PRESERVE/.claude/settings.json" <<'EXISTING'
{
  "model": "claude-opus-4-6[1m]",
  "alwaysThinkingEnabled": true,
  "enabledPlugins": {
    "jira@ai-helpers": true
  },
  "hooks": {
    "PreToolUse": [{"matcher": "Bash", "hooks": []}]
  },
  "permissions": {
    "allow": ["SomeCustomTool"],
    "deny": []
  }
}
EXISTING

$MAKE build target="$OW_PRESERVE" overwrite=1 &>/dev/null
OUTPUT="$OW_PRESERVE/.claude/settings.json"

assert_json_value "$OUTPUT" '.model' 'claude-opus-4-6[1m]' "overwrite: preserves model"
assert_json_value "$OUTPUT" '.alwaysThinkingEnabled' 'true' "overwrite: preserves alwaysThinkingEnabled"
assert_json_value "$OUTPUT" '.enabledPlugins["jira@ai-helpers"]' 'true' "overwrite: preserves enabledPlugins"
assert_json_has_key "$OUTPUT" '.hooks.PreToolUse' "overwrite: has fresh hooks"
assert_json_has_key "$OUTPUT" '.permissions' "overwrite: has fresh permissions"

# Custom permissions should be gone after overwrite
CUSTOM_ALLOW=$(jq '[.permissions.allow[] | select(. == "SomeCustomTool")] | length' "$OUTPUT")
if [ "$CUSTOM_ALLOW" -eq 0 ]; then
    pass "overwrite: custom permission removed"
else
    fail "overwrite: custom permission removed" "SomeCustomTool still present"
fi

# Overwrite with single layer only strips that layer
OW_SINGLE="$TEST_TMPDIR/overwrite-single"
mkdir -p "$OW_SINGLE/.claude"
cat > "$OW_SINGLE/.claude/settings.json" <<'EXISTING'
{
  "hooks": {
    "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "echo old"}]}]
  },
  "permissions": {
    "allow": ["CustomTool"],
    "deny": ["CustomDeny"]
  }
}
EXISTING

$MAKE build target="$OW_SINGLE" layers=hooks overwrite=1 &>/dev/null
OUTPUT="$OW_SINGLE/.claude/settings.json"

assert_json_has_key "$OUTPUT" '.hooks.PreToolUse' "overwrite single: has fresh hooks"
# Permissions should be untouched since we only overwrote hooks
assert_json_value "$OUTPUT" '.permissions.allow | length' '1' "overwrite single: existing permissions.allow untouched"

}

print_results
