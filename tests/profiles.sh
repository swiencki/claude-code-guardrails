#!/usr/bin/env bash
# Tests: profile resolution and build
# shellcheck source=tests/helpers.sh
source "$(dirname "$0")/helpers.sh"

echo "=== Profiles ==="

# list-profiles works
assert_output_contains "go-dev" "list-profiles shows go-dev" \
    $MAKE profiles

assert_output_contains "infra-dev" "list-profiles shows infra-dev" \
    $MAKE profiles

assert_output_contains "readonly-review" "list-profiles shows readonly-review" \
    $MAKE profiles

assert_output_contains "python-dev" "list-profiles shows python-dev" \
    $MAKE profiles

# invalid profile fails
assert_exit_code 2 "invalid profile exits non-zero" \
    $MAKE build profile=nonexistent dry=1

# profile + layers conflict fails
assert_exit_code 2 "profile + layers conflict exits non-zero" \
    $MAKE build profile=go-dev layers=hooks dry=1

# go-dev profile builds
GO_OUTPUT=$(build_to "profile-go-dev" profile=go-dev overwrite=1)
assert_file_exists "$GO_OUTPUT" "go-dev: settings.json created"
assert_json_has_key "$GO_OUTPUT" '.hooks' "go-dev: has hooks"
assert_json_has_key "$GO_OUTPUT" '.permissions' "go-dev: has permissions"
assert_json_count "$GO_OUTPUT" \
    '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks | length' \
    -eq 10 "go-dev: has 10 Bash hooks"

# go-dev sub-agents
GO_AGENTS="$TEST_TMPDIR/profile-go-dev/.claude/agents"
assert_file_exists "$GO_AGENTS/reviewer.json" "go-dev: reviewer agent copied"
assert_file_exists "$GO_AGENTS/readonly-explorer.json" "go-dev: readonly-explorer agent copied"
assert_file_not_exists "$GO_AGENTS/docs-reviewer.json" "go-dev: docs-reviewer not included"
assert_file_not_exists "$GO_AGENTS/release-reviewer.json" "go-dev: release-reviewer not included"

# infra-dev profile builds
INFRA_OUTPUT=$(build_to "profile-infra-dev" profile=infra-dev overwrite=1)
assert_file_exists "$INFRA_OUTPUT" "infra-dev: settings.json created"
assert_json_count "$INFRA_OUTPUT" \
    '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks | length' \
    -eq 21 "infra-dev: has 21 Bash hooks"
INFRA_AGENTS="$TEST_TMPDIR/profile-infra-dev/.claude/agents"
assert_file_exists "$INFRA_AGENTS/readonly-explorer.json" "infra-dev: readonly-explorer agent copied"
assert_file_exists "$INFRA_AGENTS/release-reviewer.json" "infra-dev: release-reviewer agent copied"

# readonly-review profile builds
RO_OUTPUT=$(build_to "profile-readonly" profile=readonly-review overwrite=1)
assert_file_exists "$RO_OUTPUT" "readonly-review: settings.json created"
assert_json_has_key "$RO_OUTPUT" '.hooks' "readonly-review: has hooks (secret scanning)"
assert_json_count "$RO_OUTPUT" \
    '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks | length' \
    -eq 1 "readonly-review: has 1 Bash hook (secrets only)"
assert_json_count "$RO_OUTPUT" \
    '.permissions.deny | length' \
    -gt 0 "readonly-review: has deny rules"
RO_AGENTS="$TEST_TMPDIR/profile-readonly/.claude/agents"
assert_file_exists "$RO_AGENTS/reviewer.json" "readonly-review: reviewer agent copied"
assert_file_exists "$RO_AGENTS/docs-reviewer.json" "readonly-review: docs-reviewer agent copied"
assert_file_exists "$RO_AGENTS/readonly-explorer.json" "readonly-review: readonly-explorer agent copied"

# python-dev profile builds
PY_OUTPUT=$(build_to "profile-python-dev" profile=python-dev overwrite=1)
assert_file_exists "$PY_OUTPUT" "python-dev: settings.json created"
assert_json_has_key "$PY_OUTPUT" '.hooks' "python-dev: has hooks"
PY_AGENTS="$TEST_TMPDIR/profile-python-dev/.claude/agents"
assert_file_exists "$PY_AGENTS/reviewer.json" "python-dev: reviewer agent copied"
assert_file_exists "$PY_AGENTS/docs-reviewer.json" "python-dev: docs-reviewer agent copied"

print_results
