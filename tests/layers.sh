#!/usr/bin/env bash
# Tests: layer selection (all, single, multiple)
# shellcheck source=tests/helpers.sh
source "$(dirname "$0")/helpers.sh"

echo "=== Layers ==="

# All layers (default)
OUTPUT=$(build_to "all-layers")
assert_file_exists "$OUTPUT" "build all: settings.json created"
assert_json_has_key "$OUTPUT" '.hooks' "build all: has hooks"
assert_json_has_key "$OUTPUT" '.hooks.PreToolUse' "build all: has PreToolUse"
assert_json_has_key "$OUTPUT" '.permissions' "build all: has permissions"
assert_json_has_key "$OUTPUT" '.permissions.allow' "build all: has allow"
assert_json_has_key "$OUTPUT" '.permissions.deny' "build all: has deny"

# Single layer: hooks
OUTPUT=$(build_to "hooks-only" layers=hooks)
assert_file_exists "$OUTPUT" "hooks only: settings.json created"
assert_json_has_key "$OUTPUT" '.hooks.PreToolUse' "hooks only: has hooks"
assert_json_missing_key "$OUTPUT" '.permissions' "hooks only: no permissions"

# Single layer: permissions
OUTPUT=$(build_to "perms-only" layers=permissions)
assert_file_exists "$OUTPUT" "permissions only: settings.json created"
assert_json_has_key "$OUTPUT" '.permissions' "permissions only: has permissions"
assert_json_missing_key "$OUTPUT" '.hooks' "permissions only: no hooks"

# Multiple layers
OUTPUT=$(build_to "hooks-perms" layers=hooks,permissions)
assert_file_exists "$OUTPUT" "hooks+permissions: settings.json created"
assert_json_has_key "$OUTPUT" '.hooks.PreToolUse' "hooks+permissions: has hooks"
assert_json_has_key "$OUTPUT" '.permissions' "hooks+permissions: has permissions"

print_results
