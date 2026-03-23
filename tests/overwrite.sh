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

# Confirmation tests run outside the brace group since they test non-zero exits
NOMAKE="make -C $REPO_ROOT --no-print-directory"

# Build without yes=1 prompts for confirmation (piping 'n' should abort)
BUILD_CONFIRM="$TEST_TMPDIR/build-confirm"
mkdir -p "$BUILD_CONFIRM"
CONFIRM_OUTPUT=$(echo "n" | $NOMAKE build target="$BUILD_CONFIRM" 2>&1 || true)
if echo "$CONFIRM_OUTPUT" | grep -q "Aborted"; then
    pass "build confirm: aborts on 'n'"
else
    fail "build confirm: aborts on 'n'" "expected 'Aborted' in output"
fi

# Piping 'y' should proceed
BUILD_CONFIRM_YES="$TEST_TMPDIR/build-confirm-yes"
mkdir -p "$BUILD_CONFIRM_YES"
echo "y" | $NOMAKE build target="$BUILD_CONFIRM_YES" &>/dev/null
if [ -f "$BUILD_CONFIRM_YES/.claude/settings.json" ]; then
    HOOK_COUNT=$(jq '.hooks.PreToolUse | length' "$BUILD_CONFIRM_YES/.claude/settings.json" 2>/dev/null)
    if [ "$HOOK_COUNT" -gt 0 ]; then
        pass "build confirm: proceeds on 'y'"
    else
        fail "build confirm: proceeds on 'y'" "hooks not written"
    fi
else
    fail "build confirm: proceeds on 'y'" "settings.json missing"
fi

# dry=1 should skip confirmation
BUILD_DRY_SKIP="$TEST_TMPDIR/build-dry-skip"
mkdir -p "$BUILD_DRY_SKIP"
DRY_OUTPUT=$($NOMAKE build target="$BUILD_DRY_SKIP" dry=1 2>&1)
if echo "$DRY_OUTPUT" | grep -q "Continue?"; then
    fail "build dry: skips confirm" "prompt still shown with dry=1"
else
    pass "build dry: skips confirm"
fi

# yes=1 should skip confirmation
BUILD_YES_SKIP="$TEST_TMPDIR/build-yes-skip"
mkdir -p "$BUILD_YES_SKIP"
$NOMAKE build target="$BUILD_YES_SKIP" yes=1 &>/dev/null
if [ -f "$BUILD_YES_SKIP/.claude/settings.json" ]; then
    pass "build yes=1: skips confirm"
else
    fail "build yes=1: skips confirm" "settings.json missing"
fi

# Prompt text says "merge" for normal build
MERGE_PROMPT="$TEST_TMPDIR/prompt-merge"
mkdir -p "$MERGE_PROMPT"
MERGE_TEXT=$(echo "n" | $NOMAKE build target="$MERGE_PROMPT" 2>&1 || true)
if echo "$MERGE_TEXT" | grep -q "will merge"; then
    pass "prompt: says 'merge' for normal build"
else
    fail "prompt: says 'merge' for normal build" "expected 'will merge'"
fi

# User-level default profile says it applies the baseline to all projects
DEFAULT_PROMPT_TEXT=$(echo "n" | $NOMAKE build target=user profile=default 2>&1 || true)
if echo "$DEFAULT_PROMPT_TEXT" | grep -q "apply the default guardrails baseline to all projects"; then
    pass "prompt: says default baseline applies to all projects"
else
    fail "prompt: says default baseline applies to all projects" "expected default baseline all-projects message"
fi

# User-level named profile says it applies that profile to all projects
GO_DEV_PROMPT_TEXT=$(echo "n" | $NOMAKE build target=user profile=go-dev 2>&1 || true)
if echo "$GO_DEV_PROMPT_TEXT" | grep -q "apply the go-dev guardrails profile to all projects"; then
    pass "prompt: says named profile applies to all projects"
else
    fail "prompt: says named profile applies to all projects" "expected named profile all-projects message"
fi

# Successful profile apply reminds the user to reload Claude Code
RELOAD_NOTICE_TARGET="$TEST_TMPDIR/reload-notice"
mkdir -p "$RELOAD_NOTICE_TARGET"
RELOAD_NOTICE_OUTPUT=$($NOMAKE build target="$RELOAD_NOTICE_TARGET" profile=go-dev yes=1 2>&1)
if echo "$RELOAD_NOTICE_OUTPUT" | grep -q "Claude Code may need a reload"; then
    pass "prompt: profile apply shows reload notice"
else
    fail "prompt: profile apply shows reload notice" "expected reload notice after profile apply"
fi

# Low-level layer builds do not show the profile reload notice
NO_RELOAD_NOTICE_TARGET="$TEST_TMPDIR/no-reload-notice"
mkdir -p "$NO_RELOAD_NOTICE_TARGET"
NO_RELOAD_NOTICE_OUTPUT=$($NOMAKE build target="$NO_RELOAD_NOTICE_TARGET" layers=hooks yes=1 2>&1)
if echo "$NO_RELOAD_NOTICE_OUTPUT" | grep -q "Claude Code may need a reload"; then
    fail "prompt: layer build skips reload notice" "unexpected reload notice for non-profile build"
else
    pass "prompt: layer build skips reload notice"
fi

# Prompt text says "overwrite" for overwrite build
OW_PROMPT="$TEST_TMPDIR/prompt-overwrite"
mkdir -p "$OW_PROMPT"
OW_TEXT=$(echo "n" | $NOMAKE build target="$OW_PROMPT" overwrite=1 2>&1 || true)
if echo "$OW_TEXT" | grep -q "will overwrite"; then
    pass "prompt: says 'overwrite' for overwrite build"
else
    fail "prompt: says 'overwrite' for overwrite build" "expected 'will overwrite'"
fi

# Prompt text says "remove" for remove
RM_PROMPT="$TEST_TMPDIR/prompt-remove"
mkdir -p "$RM_PROMPT/.claude"
echo '{"hooks":{"PreToolUse":[]}}' > "$RM_PROMPT/.claude/settings.json"
RM_TEXT=$(echo "n" | $NOMAKE remove target="$RM_PROMPT" layers=hooks 2>&1 || true)
if echo "$RM_TEXT" | grep -q "will remove hooks"; then
    pass "prompt: says 'remove hooks' for remove"
else
    fail "prompt: says 'remove hooks' for remove" "expected 'will remove hooks'"
fi

print_results
