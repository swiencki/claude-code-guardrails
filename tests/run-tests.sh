#!/usr/bin/env bash
#
# Test suite for build-settings.sh
#
# Usage: ./tests/run-tests.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/build-settings.sh"
PASSED=0
FAILED=0
ERRORS=()

# Create a temp directory for all test artifacts
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# --- Test helpers ---

pass() {
    PASSED=$((PASSED + 1))
    echo "  PASS: $1"
}

fail() {
    FAILED=$((FAILED + 1))
    ERRORS+=("$1: $2")
    echo "  FAIL: $1 - $2"
}

assert_file_exists() {
    if [ -f "$1" ]; then
        pass "$2"
    else
        fail "$2" "file not found: $1"
    fi
}

assert_file_not_exists() {
    if [ ! -f "$1" ]; then
        pass "$2"
    else
        fail "$2" "file should not exist: $1"
    fi
}

assert_json_has_key() {
    local file="$1" key="$2" name="$3"
    if jq -e "$key" "$file" &>/dev/null; then
        pass "$name"
    else
        fail "$name" "key $key not found in $file"
    fi
}

assert_json_missing_key() {
    local file="$1" key="$2" name="$3"
    if jq -e "$key" "$file" &>/dev/null; then
        fail "$name" "key $key should not be in $file"
    else
        pass "$name"
    fi
}

assert_json_value() {
    local file="$1" query="$2" expected="$3" name="$4"
    local actual
    actual=$(jq -r "$query" "$file")
    if [ "$actual" = "$expected" ]; then
        pass "$name"
    else
        fail "$name" "expected '$expected', got '$actual'"
    fi
}

assert_exit_code() {
    local expected="$1" name="$2"
    shift 2
    local actual
    if "$@" &>/dev/null; then
        actual=0
    else
        actual=$?
    fi
    if [ "$actual" -eq "$expected" ]; then
        pass "$name"
    else
        fail "$name" "expected exit code $expected, got $actual"
    fi
}

assert_output_contains() {
    local pattern="$1" name="$2"
    shift 2
    local output
    output=$("$@" 2>&1) || true
    if echo "$output" | grep -q "$pattern"; then
        pass "$name"
    else
        fail "$name" "output does not contain '$pattern'"
    fi
}

# --- Tests ---

echo "=== CLI Options ==="

assert_exit_code 0 "--help exits 0" "$SCRIPT" --help
assert_exit_code 0 "-h exits 0" "$SCRIPT" -h
assert_exit_code 0 "--list exits 0" "$SCRIPT" --list
assert_exit_code 1 "unknown option exits 1" "$SCRIPT" --bogus
assert_output_contains "Usage:" "--help shows usage" "$SCRIPT" --help
assert_output_contains "azure-safety.json" "--list shows hook fragments" "$SCRIPT" --list
assert_output_contains "standard-dev.json" "--list shows permission presets" "$SCRIPT" --list

echo ""
echo "=== Dry Run ==="

DRY_TARGET="$TMPDIR/dry-run-project"
mkdir -p "$DRY_TARGET"
"$SCRIPT" --dry-run --target "$DRY_TARGET" &>/dev/null
assert_file_not_exists "$DRY_TARGET/.claude/settings.json" "dry-run does not write file"
assert_output_contains "Would write to" "dry-run shows target path" "$SCRIPT" --dry-run --target "$DRY_TARGET"

echo ""
echo "=== Build All (project target) ==="

PROJECT_TARGET="$TMPDIR/project-all"
mkdir -p "$PROJECT_TARGET"
"$SCRIPT" --target "$PROJECT_TARGET" &>/dev/null
OUTPUT="$PROJECT_TARGET/.claude/settings.json"

assert_file_exists "$OUTPUT" "settings.json created"
assert_json_has_key "$OUTPUT" '.hooks' "has hooks key"
assert_json_has_key "$OUTPUT" '.hooks.PreToolUse' "has PreToolUse key"
assert_json_has_key "$OUTPUT" '.permissions' "has permissions key"
assert_json_has_key "$OUTPUT" '.permissions.allow' "has permissions.allow"
assert_json_has_key "$OUTPUT" '.permissions.deny' "has permissions.deny"

echo ""
echo "=== Hooks Only ==="

HOOKS_TARGET="$TMPDIR/hooks-only"
mkdir -p "$HOOKS_TARGET"
"$SCRIPT" --target "$HOOKS_TARGET" --hooks-only &>/dev/null
OUTPUT="$HOOKS_TARGET/.claude/settings.json"

assert_file_exists "$OUTPUT" "settings.json created"
assert_json_has_key "$OUTPUT" '.hooks.PreToolUse' "has hooks"
assert_json_missing_key "$OUTPUT" '.permissions' "no permissions key"

echo ""
echo "=== Permissions Only ==="

PERMS_TARGET="$TMPDIR/perms-only"
mkdir -p "$PERMS_TARGET"
"$SCRIPT" --target "$PERMS_TARGET" --permissions-only &>/dev/null
OUTPUT="$PERMS_TARGET/.claude/settings.json"

assert_file_exists "$OUTPUT" "settings.json created"
assert_json_has_key "$OUTPUT" '.permissions' "has permissions"
assert_json_missing_key "$OUTPUT" '.hooks' "no hooks key"

echo ""
echo "=== Hook Consolidation ==="

# Verify that Bash hooks from multiple fragments are merged under one matcher
ALL_TARGET="$TMPDIR/consolidation"
mkdir -p "$ALL_TARGET"
"$SCRIPT" --target "$ALL_TARGET" &>/dev/null
OUTPUT="$ALL_TARGET/.claude/settings.json"

BASH_MATCHER_COUNT=$(jq '[.hooks.PreToolUse[] | select(.matcher == "Bash")] | length' "$OUTPUT")
if [ "$BASH_MATCHER_COUNT" -eq 1 ]; then
    pass "Bash hooks consolidated under single matcher"
else
    fail "Bash hooks consolidated under single matcher" "found $BASH_MATCHER_COUNT Bash matchers, expected 1"
fi

BASH_HOOK_COUNT=$(jq '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks | length' "$OUTPUT")
if [ "$BASH_HOOK_COUNT" -ge 4 ]; then
    pass "multiple Bash hooks merged ($BASH_HOOK_COUNT total)"
else
    fail "multiple Bash hooks merged" "only $BASH_HOOK_COUNT hooks, expected at least 4"
fi

echo ""
echo "=== Merge With Existing Settings ==="

MERGE_TARGET="$TMPDIR/merge-existing"
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

"$SCRIPT" --target "$MERGE_TARGET" &>/dev/null
OUTPUT="$MERGE_TARGET/.claude/settings.json"

assert_json_value "$OUTPUT" '.model' 'claude-opus-4-6[1m]' "preserves model"
assert_json_value "$OUTPUT" '.alwaysThinkingEnabled' 'true' "preserves alwaysThinkingEnabled"
assert_json_value "$OUTPUT" '.enabledPlugins["jira@ai-helpers"]' 'true' "preserves enabledPlugins"
assert_json_has_key "$OUTPUT" '.hooks.PreToolUse' "adds hooks"
assert_json_has_key "$OUTPUT" '.permissions' "adds permissions"

echo ""
echo "=== Merge Does Not Duplicate Hooks ==="

# Run the build twice and verify hooks aren't duplicated
DEDUP_TARGET="$TMPDIR/dedup"
mkdir -p "$DEDUP_TARGET"
"$SCRIPT" --target "$DEDUP_TARGET" &>/dev/null
FIRST_COUNT=$(jq '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks | length' "$DEDUP_TARGET/.claude/settings.json")

"$SCRIPT" --target "$DEDUP_TARGET" &>/dev/null
SECOND_COUNT=$(jq '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks | length' "$DEDUP_TARGET/.claude/settings.json")

if [ "$FIRST_COUNT" -eq "$SECOND_COUNT" ]; then
    pass "running twice does not duplicate hooks ($FIRST_COUNT both times)"
else
    fail "running twice does not duplicate hooks" "first run: $FIRST_COUNT, second run: $SECOND_COUNT"
fi

echo ""
echo "=== Specific Hook Content ==="

CONTENT_TARGET="$TMPDIR/content-check"
mkdir -p "$CONTENT_TARGET"
"$SCRIPT" --target "$CONTENT_TARGET" &>/dev/null
OUTPUT="$CONTENT_TARGET/.claude/settings.json"

# Check that specific guardrails are present
assert_output_contains "force" "contains force push hook" jq -r '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].statusMessage' "$OUTPUT"
assert_output_contains "Complete" "contains az --mode Complete hook" jq -r '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].statusMessage' "$OUTPUT"
assert_output_contains "secret" "contains secret protection hook" jq -r '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].statusMessage' "$OUTPUT"

# Check Write matcher exists
WRITE_COUNT=$(jq '[.hooks.PreToolUse[] | select(.matcher == "Write")] | length' "$OUTPUT")
if [ "$WRITE_COUNT" -eq 1 ]; then
    pass "Write matcher present"
else
    fail "Write matcher present" "found $WRITE_COUNT Write matchers"
fi

# Check Edit matcher exists
EDIT_COUNT=$(jq '[.hooks.PreToolUse[] | select(.matcher == "Edit")] | length' "$OUTPUT")
if [ "$EDIT_COUNT" -eq 1 ]; then
    pass "Edit matcher present"
else
    fail "Edit matcher present" "found $EDIT_COUNT Edit matchers"
fi

echo ""
echo "=== Invalid Target ==="

assert_exit_code 1 "nonexistent target exits 1" "$SCRIPT" --target /tmp/does-not-exist-at-all

echo ""
echo "=== Valid JSON Output ==="

VALID_TARGET="$TMPDIR/valid-json"
mkdir -p "$VALID_TARGET"
"$SCRIPT" --target "$VALID_TARGET" &>/dev/null
OUTPUT="$VALID_TARGET/.claude/settings.json"

if jq empty "$OUTPUT" 2>/dev/null; then
    pass "output is valid JSON"
else
    fail "output is valid JSON" "jq failed to parse $OUTPUT"
fi

echo ""
echo "=== User Target Path ==="

# Verify --target user resolves to ~/.claude/settings.json (dry-run only)
assert_output_contains "$HOME/.claude/settings.json" "--target user resolves to home dir" "$SCRIPT" --dry-run --target user

# --- Summary ---

echo ""
echo "================================"
echo "  Results: $PASSED passed, $FAILED failed"
echo "================================"

if [ $FAILED -gt 0 ]; then
    echo ""
    echo "Failures:"
    for err in "${ERRORS[@]}"; do
        echo "  - $err"
    done
    exit 1
fi
