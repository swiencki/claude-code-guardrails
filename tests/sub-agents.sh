#!/usr/bin/env bash
# Tests: sub-agents layer (file copy to .claude/agents/)
# shellcheck source=tests/helpers.sh
source "$(dirname "$0")/helpers.sh"

echo "=== Sub-agents ==="

# shellcheck disable=SC2086 # $MAKE intentionally word-splits
{

# Build sub-agents only
SA_TARGET="$TEST_TMPDIR/sub-agents-only"
mkdir -p "$SA_TARGET"
$MAKE build target="$SA_TARGET" layers=sub-agents &>/dev/null

assert_file_exists "$SA_TARGET/.claude/agents/reviewer.json" "reviewer.json copied"
assert_file_not_exists "$SA_TARGET/.claude/settings.json" "no settings.json when only sub-agents"

# Verify agent file content
assert_json_value "$SA_TARGET/.claude/agents/reviewer.json" '.name' 'reviewer' "agent has correct name"
assert_json_has_key "$SA_TARGET/.claude/agents/reviewer.json" '.tools' "agent has tools"
assert_json_has_key "$SA_TARGET/.claude/agents/reviewer.json" '.permissions' "agent has permissions"

# Build all layers includes sub-agents
ALL_TARGET="$TEST_TMPDIR/all-with-agents"
mkdir -p "$ALL_TARGET"
$MAKE build target="$ALL_TARGET" &>/dev/null

assert_file_exists "$ALL_TARGET/.claude/settings.json" "settings.json created"
assert_file_exists "$ALL_TARGET/.claude/agents/reviewer.json" "reviewer.json copied with all layers"

# Sub-agents + hooks together
COMBO_TARGET="$TEST_TMPDIR/combo"
mkdir -p "$COMBO_TARGET"
$MAKE build target="$COMBO_TARGET" layers=hooks,sub-agents &>/dev/null

assert_file_exists "$COMBO_TARGET/.claude/settings.json" "settings.json created"
assert_json_has_key "$COMBO_TARGET/.claude/settings.json" '.hooks' "has hooks"
assert_json_missing_key "$COMBO_TARGET/.claude/settings.json" '.permissions' "no permissions"
assert_file_exists "$COMBO_TARGET/.claude/agents/reviewer.json" "reviewer.json copied"

# Dry run does not copy agents
DRY_TARGET="$TEST_TMPDIR/dry-agents"
mkdir -p "$DRY_TARGET"
$MAKE build target="$DRY_TARGET" layers=sub-agents dry=1 &>/dev/null

if [ ! -d "$DRY_TARGET/.claude/agents" ]; then
    pass "dry-run does not create agents dir"
else
    fail "dry-run does not create agents dir" "agents dir exists"
fi

# Remove sub-agents
RM_TARGET="$TEST_TMPDIR/remove-agents"
mkdir -p "$RM_TARGET"
$MAKE build target="$RM_TARGET" layers=sub-agents &>/dev/null
assert_file_exists "$RM_TARGET/.claude/agents/reviewer.json" "agent exists before remove"

$MAKE remove target="$RM_TARGET" layers=sub-agents &>/dev/null
assert_file_not_exists "$RM_TARGET/.claude/agents/reviewer.json" "agent removed"

# Remove sub-agents preserves settings.json
RM_PRESERVE="$TEST_TMPDIR/remove-agents-preserve"
mkdir -p "$RM_PRESERVE"
$MAKE build target="$RM_PRESERVE" &>/dev/null
assert_file_exists "$RM_PRESERVE/.claude/settings.json" "settings.json before remove"
assert_file_exists "$RM_PRESERVE/.claude/agents/reviewer.json" "agent before remove"

$MAKE remove target="$RM_PRESERVE" layers=sub-agents &>/dev/null
assert_file_exists "$RM_PRESERVE/.claude/settings.json" "settings.json preserved after agent remove"
assert_file_not_exists "$RM_PRESERVE/.claude/agents/reviewer.json" "agent removed"

}

print_results
