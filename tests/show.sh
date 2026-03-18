#!/usr/bin/env bash
# Tests: make show fragment=...
# shellcheck source=tests/helpers.sh
source "$(dirname "$0")/helpers.sh"

echo "=== Show ==="

# shellcheck disable=SC2086 # $MAKE intentionally word-splits
{

# Single fragment
assert_output_contains "Blocks destructive AWS" "show single: displays description" \
    $MAKE show fragment=aws/safety.json
assert_output_contains '"hooks"' "show single: displays JSON" \
    $MAKE show fragment=aws/safety.json

# Multiple fragments (directory match)
assert_output_contains "protected-merge" "show directory: shows first gh fragment" \
    $MAKE show fragment=gh/
assert_output_contains "workflow-dispatch" "show directory: shows second gh fragment" \
    $MAKE show fragment=gh/
assert_output_contains "release-publish" "show directory: shows third gh fragment" \
    $MAKE show fragment=gh/

# Partial match across categories
assert_output_contains "Fragment:" "show partial: matches fragments" \
    $MAKE show fragment=safety

# No match
assert_exit_code 2 "show no match: exits non-zero" \
    $MAKE show fragment=nonexistent-fragment-xyz

}

print_results
