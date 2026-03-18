#!/usr/bin/env bash
# Shared test helpers - sourced by each test file

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC2034 # MAKE is used by test files that source this
MAKE="make -C $REPO_ROOT --no-print-directory yes=1"

# Per-test temp directory
TEST_TMPDIR=$(mktemp -d)
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# Counters (exported so run-tests.sh can aggregate)
PASSED=0
FAILED=0
ERRORS=()

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

assert_json_count() {
    local file="$1" query="$2" op="$3" expected="$4" name="$5"
    local actual
    actual=$(jq -r "$query" "$file")
    if [ -z "$actual" ]; then
        fail "$name" "query returned empty"
        return
    fi
    if test "$actual" "$op" "$expected"; then pass "$name"; else fail "$name" "got $actual (expected $op $expected)"; fi
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

# Build into a fresh temp dir, return the settings.json path
build_to() {
    local dir="$TEST_TMPDIR/$1"
    shift
    mkdir -p "$dir"
    $MAKE build target="$dir" "$@" &>/dev/null
    echo "$dir/.claude/settings.json"
}

# Print results for this test file and return pass/fail counts
print_results() {
    echo "$PASSED $FAILED"
    if [ ${#ERRORS[@]} -gt 0 ]; then
        for err in "${ERRORS[@]}"; do
            echo "ERROR:$err"
        done
    fi
}
