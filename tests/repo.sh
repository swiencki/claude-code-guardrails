#!/usr/bin/env bash
# Tests: make repo (init with CLAUDE.md)
# shellcheck source=tests/helpers.sh
source "$(dirname "$0")/helpers.sh"

echo "=== Repo ==="

# shellcheck disable=SC2086 # $MAKE intentionally word-splits
{

# Repo creates settings.json and copies CLAUDE.md
REPO_TARGET="$TEST_TMPDIR/repo-init"
mkdir -p "$REPO_TARGET"
$MAKE repo target="$REPO_TARGET" &>/dev/null

assert_file_exists "$REPO_TARGET/.claude/settings.json" "repo: settings.json created"
assert_file_exists "$REPO_TARGET/CLAUDE.md" "repo: CLAUDE.md copied"
assert_json_has_key "$REPO_TARGET/.claude/settings.json" '.hooks' "repo: has hooks"

# Repo with profile
REPO_PROFILE="$TEST_TMPDIR/repo-profile"
mkdir -p "$REPO_PROFILE"
$MAKE repo target="$REPO_PROFILE" profile=go-dev &>/dev/null

assert_file_exists "$REPO_PROFILE/.claude/settings.json" "repo profile: settings.json created"
assert_file_exists "$REPO_PROFILE/CLAUDE.md" "repo profile: CLAUDE.md copied"
assert_json_count "$REPO_PROFILE/.claude/settings.json" \
    '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks | length' \
    -eq 10 "repo profile: has 10 Bash hooks (go-dev)"

# Repo does not overwrite existing CLAUDE.md
REPO_EXISTING="$TEST_TMPDIR/repo-existing"
mkdir -p "$REPO_EXISTING"
echo "existing content" > "$REPO_EXISTING/CLAUDE.md"
$MAKE repo target="$REPO_EXISTING" &>/dev/null

CONTENT=$(cat "$REPO_EXISTING/CLAUDE.md")
if [ "$CONTENT" = "existing content" ]; then
    pass "repo: does not overwrite existing CLAUDE.md"
else
    fail "repo: does not overwrite existing CLAUDE.md" "content was changed"
fi

# Dry run does not copy CLAUDE.md
REPO_DRY="$TEST_TMPDIR/repo-dry"
mkdir -p "$REPO_DRY"
$MAKE repo target="$REPO_DRY" dry=1 &>/dev/null
assert_file_not_exists "$REPO_DRY/CLAUDE.md" "repo dry: CLAUDE.md not copied"

# Prompt says "initialize"
REPO_PROMPT="$TEST_TMPDIR/repo-prompt"
mkdir -p "$REPO_PROMPT"
NOMAKE="make -C $REPO_ROOT --no-print-directory"
PROMPT_OUTPUT=$(echo "n" | $NOMAKE repo target="$REPO_PROMPT" 2>&1 || true)
if echo "$PROMPT_OUTPUT" | grep -q "initialize"; then
    pass "repo: prompt says initialize"
else
    fail "repo: prompt says initialize" "expected 'initialize' in prompt"
fi

}

print_results
