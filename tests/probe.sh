#!/usr/bin/env bash
source "$(dirname "$0")/helpers.sh"

echo "=== Probe ==="

assert_exit_code 2 "probe: requires command or input" \
    $MAKE probe

assert_output_contains "Mode: default build" "probe: defaults to probing merged build output" \
    $MAKE probe tool=Bash command="git push --force origin main"

assert_output_contains "Decision: DENY" "probe: default build denies git push --force" \
    $MAKE probe tool=Bash command="git push --force origin main"

assert_output_contains "Decision: DENY" "probe: hook fragment denies git push --force" \
    $MAKE probe fragment=git/safety.json tool=Bash command="git push --force origin main"

assert_output_contains "Decision: ALLOW" "probe: hook fragment allows normal git push" \
    $MAKE probe fragment=git/safety.json tool=Bash command="git push origin main"

assert_output_contains "Effective permission outcome: DENY" "probe: permissions fragment denies git push --force" \
    $MAKE probe fragment=presets/standard-dev.json tool=Bash command="git push --force origin main"

assert_output_contains "Profile: infra-dev" "probe: profile mode identifies selected profile" \
    $MAKE probe profile=infra-dev tool=Bash command="git push --force origin main"

assert_output_contains "Decision: DENY" "probe: profile denies git push --force" \
    $MAKE probe profile=infra-dev tool=Bash command="git push --force origin main"

assert_output_contains "Effective permission outcome: ALLOW" "probe: profile allows make test" \
    $MAKE probe profile=go-dev tool=Bash command="make test"

assert_output_contains "Effective permission outcome: ALLOW" "probe: permissions fragment allows make test" \
    $MAKE probe fragment=presets/standard-dev.json tool=Bash command="make test"

assert_output_contains "Tool access:" "probe: sub-agent denies unavailable tool" \
    $MAKE probe fragment=reviewer.json tool=Bash command="git status"

assert_output_contains "ALLOW: \`Read\` is present in \`4-sub-agents/reviewer.json\`." "probe: sub-agent allows configured tool" \
    $MAKE probe fragment=reviewer.json tool=Read input='{"file_path":"README.md"}'

assert_output_contains "Overall hook outcome: DENY" "probe: can scope to one hook in a fragment" \
    $MAKE probe fragment=git/safety.json tool=Bash hook=1 input='{"command":"git reset --hard HEAD~1"}'

assert_exit_code 0 "probe: expect passes on matching result" \
    $MAKE probe fragment=presets/standard-dev.json tool=Bash command="make test" expect=allow

assert_exit_code 2 "probe: expect fails on mismatched result" \
    $MAKE probe fragment=presets/standard-dev.json tool=Bash command="make test" expect=deny

assert_output_contains "Fragment path is ambiguous" "probe: rejects ambiguous fragment names" \
    $MAKE probe fragment=safety.json tool=Bash command="git status"

assert_exit_code 2 "probe: rejects fragment with profile together" \
    $MAKE probe fragment=git/safety.json profile=go-dev tool=Bash command="git status"

print_results
