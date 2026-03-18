#!/usr/bin/env bash
# Tests: hook consolidation and specific hook content

source "$(dirname "$0")/helpers.sh"

echo "=== Hooks ==="

OUTPUT=$(build_to "hooks-check")

# Consolidation - Bash hooks from multiple fragments under one matcher
assert_json_count "$OUTPUT" \
    '[.hooks.PreToolUse[] | select(.matcher == "Bash")] | length' \
    -eq 1 \
    "Bash hooks consolidated under single matcher"

assert_json_count "$OUTPUT" \
    '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks | length' \
    -ge 4 \
    "at least 4 Bash hooks merged"

# Specific guardrails are present
assert_output_contains "force" "git force push hook present" \
    jq -r '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].statusMessage' "$OUTPUT"
assert_output_contains "Complete" "az --mode Complete hook present" \
    jq -r '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].statusMessage' "$OUTPUT"
assert_output_contains "secret" "secret protection hook present" \
    jq -r '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[].statusMessage' "$OUTPUT"

# Write and Edit matchers exist
assert_json_count "$OUTPUT" \
    '[.hooks.PreToolUse[] | select(.matcher == "Write")] | length' \
    -eq 1 \
    "Write matcher present"

assert_json_count "$OUTPUT" \
    '[.hooks.PreToolUse[] | select(.matcher == "Edit")] | length' \
    -eq 1 \
    "Edit matcher present"

# Valid JSON
if jq empty "$OUTPUT" 2>/dev/null; then pass "output is valid JSON"; else fail "output is valid JSON" "jq parse failed"; fi

print_results
