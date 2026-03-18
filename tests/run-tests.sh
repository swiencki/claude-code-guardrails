#!/usr/bin/env bash
#
# Test suite for the guardrails Makefile
#
# Usage: ./tests/run-tests.sh  (or: make test)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAKE="make -C $REPO_ROOT --no-print-directory"
PASSED=0
FAILED=0
ERRORS=()

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# --- Helpers ---

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
    if [ -f "$1" ]; then pass "$2"; else fail "$2" "file not found: $1"; fi
}

assert_file_not_exists() {
    if [ ! -f "$1" ]; then pass "$2"; else fail "$2" "file should not exist: $1"; fi
}

assert_json_has_key() {
    local file="$1" key="$2" name="$3"
    if jq -e "$key" "$file" &>/dev/null; then pass "$name"; else fail "$name" "key $key not found"; fi
}

assert_json_missing_key() {
    local file="$1" key="$2" name="$3"
    if jq -e "$key" "$file" &>/dev/null; then fail "$name" "key $key should not exist"; else pass "$name"; fi
}

assert_json_value() {
    local file="$1" query="$2" expected="$3" name="$4"
    local actual
    actual=$(jq -r "$query" "$file")
    if [ "$actual" = "$expected" ]; then pass "$name"; else fail "$name" "expected '$expected', got '$actual'"; fi
}

assert_exit_code() {
    local expected="$1" name="$2"
    shift 2
    if "$@" &>/dev/null; then actual=0; else actual=$?; fi
    if [ "$actual" -eq "$expected" ]; then pass "$name"; else fail "$name" "expected exit $expected, got $actual"; fi
}

assert_output_contains() {
    local pattern="$1" name="$2"
    shift 2
    local output
    output=$("$@" 2>&1) || true
    if echo "$output" | grep -q "$pattern"; then pass "$name"; else fail "$name" "output missing '$pattern'"; fi
}

# --- Tests ---

echo "=== CLI Options ==="

assert_exit_code 0 "make help exits 0" $MAKE help
assert_exit_code 0 "make list exits 0" $MAKE list
assert_output_contains "Usage:" "help shows usage" $MAKE help
assert_output_contains "azure-safety.json" "list shows hook fragments" $MAKE list
assert_output_contains "standard-dev.json" "list shows permission presets" $MAKE list

echo ""
echo "=== Dry Run ==="

DRY_TARGET="$TMPDIR/dry-run"
mkdir -p "$DRY_TARGET"
$MAKE dry-run TARGET="$DRY_TARGET" &>/dev/null
assert_file_not_exists "$DRY_TARGET/.claude/settings.json" "dry-run does not write file"
assert_output_contains "Would write to" "dry-run shows target path" $MAKE dry-run TARGET="$DRY_TARGET"

echo ""
echo "=== Build All ==="

ALL_TARGET="$TMPDIR/build-all"
mkdir -p "$ALL_TARGET"
$MAKE build TARGET="$ALL_TARGET" &>/dev/null
OUTPUT="$ALL_TARGET/.claude/settings.json"

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
$MAKE hooks TARGET="$HOOKS_TARGET" &>/dev/null
OUTPUT="$HOOKS_TARGET/.claude/settings.json"

assert_file_exists "$OUTPUT" "settings.json created"
assert_json_has_key "$OUTPUT" '.hooks.PreToolUse' "has hooks"
assert_json_missing_key "$OUTPUT" '.permissions' "no permissions key"

echo ""
echo "=== Permissions Only ==="

PERMS_TARGET="$TMPDIR/perms-only"
mkdir -p "$PERMS_TARGET"
$MAKE permissions TARGET="$PERMS_TARGET" &>/dev/null
OUTPUT="$PERMS_TARGET/.claude/settings.json"

assert_file_exists "$OUTPUT" "settings.json created"
assert_json_has_key "$OUTPUT" '.permissions' "has permissions"
assert_json_missing_key "$OUTPUT" '.hooks' "no hooks key"

echo ""
echo "=== Hook Consolidation ==="

CONSOL_TARGET="$TMPDIR/consolidation"
mkdir -p "$CONSOL_TARGET"
$MAKE build TARGET="$CONSOL_TARGET" &>/dev/null
OUTPUT="$CONSOL_TARGET/.claude/settings.json"

BASH_MATCHER_COUNT=$(jq '[.hooks.PreToolUse[] | select(.matcher == "Bash")] | length' "$OUTPUT")
if [ "$BASH_MATCHER_COUNT" -eq 1 ]; then
    pass "Bash hooks consolidated under single matcher"
else
    fail "Bash hooks consolidated under single matcher" "found $BASH_MATCHER_COUNT, expected 1"
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

$MAKE build TARGET="$MERGE_TARGET" &>/dev/null
OUTPUT="$MERGE_TARGET/.claude/settings.json"

assert_json_value "$OUTPUT" '.model' 'claude-opus-4-6[1m]' "preserves model"
assert_json_value "$OUTPUT" '.alwaysThinkingEnabled' 'true' "preserves alwaysThinkingEnabled"
assert_json_value "$OUTPUT" '.enabledPlugins["jira@ai-helpers"]' 'true' "preserves enabledPlugins"
assert_json_has_key "$OUTPUT" '.hooks.PreToolUse' "adds hooks"
assert_json_has_key "$OUTPUT" '.permissions' "adds permissions"

echo ""
echo "=== Idempotency ==="

IDEM_TARGET="$TMPDIR/idempotent"
mkdir -p "$IDEM_TARGET"
$MAKE build TARGET="$IDEM_TARGET" &>/dev/null
FIRST_COUNT=$(jq '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks | length' "$IDEM_TARGET/.claude/settings.json")

$MAKE build TARGET="$IDEM_TARGET" &>/dev/null
SECOND_COUNT=$(jq '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks | length' "$IDEM_TARGET/.claude/settings.json")

if [ "$FIRST_COUNT" -eq "$SECOND_COUNT" ]; then
    pass "running twice does not duplicate hooks ($FIRST_COUNT both times)"
else
    fail "running twice does not duplicate hooks" "first: $FIRST_COUNT, second: $SECOND_COUNT"
fi

echo ""
echo "=== Specific Hook Content ==="

CONTENT_TARGET="$TMPDIR/content"
mkdir -p "$CONTENT_TARGET"
$MAKE build TARGET="$CONTENT_TARGET" &>/dev/null
OUTPUT="$CONTENT_TARGET/.claude/settings.json"

assert_output_contains "force" "contains force push hook" jq -r '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].statusMessage' "$OUTPUT"
assert_output_contains "Complete" "contains az --mode Complete hook" jq -r '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].statusMessage' "$OUTPUT"
assert_output_contains "secret" "contains secret protection hook" jq -r '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].statusMessage' "$OUTPUT"

WRITE_COUNT=$(jq '[.hooks.PreToolUse[] | select(.matcher == "Write")] | length' "$OUTPUT")
if [ "$WRITE_COUNT" -eq 1 ]; then pass "Write matcher present"; else fail "Write matcher present" "found $WRITE_COUNT"; fi

EDIT_COUNT=$(jq '[.hooks.PreToolUse[] | select(.matcher == "Edit")] | length' "$OUTPUT")
if [ "$EDIT_COUNT" -eq 1 ]; then pass "Edit matcher present"; else fail "Edit matcher present" "found $EDIT_COUNT"; fi

echo ""
echo "=== Invalid Target ==="

assert_exit_code 2 "nonexistent target exits non-zero" $MAKE build TARGET=/tmp/does-not-exist-at-all

echo ""
echo "=== Valid JSON Output ==="

VALID_TARGET="$TMPDIR/valid-json"
mkdir -p "$VALID_TARGET"
$MAKE build TARGET="$VALID_TARGET" &>/dev/null
OUTPUT="$VALID_TARGET/.claude/settings.json"

if jq empty "$OUTPUT" 2>/dev/null; then pass "output is valid JSON"; else fail "output is valid JSON" "jq parse failed"; fi

echo ""
echo "=== User Target Path ==="

assert_output_contains "$HOME/.claude/settings.json" "--target user resolves to home dir" $MAKE dry-run TARGET=user

echo ""
echo "=== Clean ==="

CLEAN_TARGET="$TMPDIR/clean-test"
mkdir -p "$CLEAN_TARGET/.claude"
echo '{}' > "$CLEAN_TARGET/.claude/settings.json"
# clean only removes the repo's own .claude/settings.json, so test that
$MAKE build &>/dev/null
assert_file_exists "$REPO_ROOT/.claude/settings.json" "settings.json exists before clean"
$MAKE clean &>/dev/null
assert_file_not_exists "$REPO_ROOT/.claude/settings.json" "settings.json removed after clean"

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
