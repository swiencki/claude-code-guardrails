#!/usr/bin/env bash
source "$(dirname "$0")/helpers.sh"

echo "=== Probe Workflow ==="

assert_output_contains "Decision: DENY" "workflow: default build denies force push" \
    $MAKE probe tool=Bash command="git push --force origin main"

assert_output_contains "Mode: default build" "workflow: default build mode is explicit" \
    $MAKE probe tool=Bash command="git push --force origin main"

assert_output_contains "Profile: infra-dev" "workflow: profile probe identifies profile" \
    $MAKE probe profile=infra-dev tool=Bash command="git push --force origin main"

assert_output_contains "Hook checks" "workflow: fragment probe explains hook decisions" \
    $MAKE probe fragment=git/safety.json tool=Bash command="git push --force origin main"

assert_output_contains "BLOCKED: Checking for git force push" "workflow: fragment probe shows blocking rule" \
    $MAKE probe fragment=git/safety.json tool=Bash command="git push --force origin main"

assert_output_contains "Denied by:" "workflow: default build shows denial summary" \
    $MAKE probe tool=Bash command="git push --force origin main"

assert_output_contains "2-hooks/git/safety.json" "workflow: default build shows denying hook source" \
    $MAKE probe tool=Bash command="git push --force origin main"

assert_output_contains "Effective permission outcome: ALLOW" "workflow: profile probe shows permission allow" \
    $MAKE probe profile=go-dev tool=Bash command="make test"

print_results
