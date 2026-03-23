#!/usr/bin/env bash
# Tests: make show profile=... / fragment=...
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

# Profile view shows effective fragments, including inherited default fragments
assert_output_contains "Profile: go-dev" "show profile: displays profile name" \
    $MAKE show profile=go-dev
assert_output_contains "Effective fragments:" "show profile: displays effective fragments heading" \
    $MAKE show profile=go-dev
assert_output_contains "git/force-push.json (from default)" "show profile: includes inherited default fragment" \
    $MAKE show profile=go-dev
assert_output_contains "packages/publish.json (from go-dev)" "show profile: includes profile-specific fragment" \
    $MAKE show profile=go-dev

# Profile filter shows JSON for matching effective fragments
assert_output_contains "Matching fragment details:" "show profile filter: prints matching fragment section" \
    $MAKE show profile=default fragment=git
assert_output_contains "Fragment: git/force-push.json" "show profile filter: includes first matching fragment" \
    $MAKE show profile=default fragment=git
assert_output_contains '"hooks"' "show profile filter: prints fragment JSON" \
    $MAKE show profile=default fragment=git/force-push.json
assert_output_contains "Fragment: git/force-push.json" "show profile typo alias: fragement works" \
    $MAKE show profile=default fragement=git/force-push.json

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

# Requires at least one selector
assert_exit_code 2 "show no selector: exits non-zero" \
    $MAKE show
assert_exit_code 2 "show filtered profile no match: exits non-zero" \
    $MAKE show profile=default fragment=aws/safety.json

}

print_results
