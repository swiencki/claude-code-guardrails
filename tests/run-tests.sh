#!/usr/bin/env bash
#
# Test runner - executes all test files and aggregates results
#
# Usage:
#   ./tests/run-tests.sh           # run all tests
#   ./tests/run-tests.sh cli       # run a specific test file
#   ./tests/run-tests.sh cli merge # run multiple test files
#
# Or via make:
#   make test

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_FILES=(cli layers merge hooks hook-behavior sub-agents overwrite remove profiles show repo)
TOTAL_PASSED=0
TOTAL_FAILED=0
ALL_ERRORS=()

# If specific test files are requested, use those
if [ $# -gt 0 ]; then
    TEST_FILES=("$@")
fi

for test_file in "${TEST_FILES[@]}"; do
    script="$TESTS_DIR/${test_file}.sh"
    if [ ! -f "$script" ]; then
        echo "Error: test file not found: $script" >&2
        exit 1
    fi

    # Run test file, capture output
    output=$(bash "$script" 2>&1) || true

    # Print test output (everything except the results line)
    echo "$output" | grep -v "^[0-9]" | grep -v "^ERROR:" || true

    # Parse results from last numeric line
    results=$(echo "$output" | grep "^[0-9]" | tail -1)
    if [ -n "$results" ]; then
        passed=$(echo "$results" | awk '{print $1}')
        failed=$(echo "$results" | awk '{print $2}')
        TOTAL_PASSED=$((TOTAL_PASSED + passed))
        TOTAL_FAILED=$((TOTAL_FAILED + failed))
    fi

    # Collect errors
    while IFS= read -r line; do
        ALL_ERRORS+=("${line#ERROR:}")
    done < <(echo "$output" | grep "^ERROR:" || true)

    echo ""
done

echo "================================"
echo "  Results: $TOTAL_PASSED passed, $TOTAL_FAILED failed"
echo "================================"

if [ $TOTAL_FAILED -gt 0 ]; then
    echo ""
    echo "Failures:"
    for err in "${ALL_ERRORS[@]}"; do
        echo "  - $err"
    done
    exit 1
fi
