#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage:
  scripts/probe-fragment.sh [--fragment <path> | --profile <name>] [--tool Bash] [--event PreToolUse] [--matcher Bash] [--hook 0] (--command <shell command> | --input <tool-input-json>) [--expect allow|deny|ask]

Examples:
  make probe tool=Bash command='git push --force origin main'
  make probe fragment=git/safety.json tool=Bash command='git push --force origin main'
  make probe profile=infra-dev tool=Bash command='git push --force origin main'
  make probe fragment=reviewer.json tool=Bash command='git status'
EOF
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAYERS_DIR="$REPO_ROOT/layers"

fragment=""
profile=""
tool="Bash"
event="PreToolUse"
matcher=""
hook_index=""
command_input=""
tool_input_json=""
expect=""

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    COLOR_RED=$'\033[31m'
    COLOR_GREEN=$'\033[32m'
    COLOR_YELLOW=$'\033[33m'
    COLOR_RESET=$'\033[0m'
else
    COLOR_RED=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_RESET=""
fi

color_blocked() { printf '%sBLOCKED%s' "$COLOR_RED" "$COLOR_RESET"; }
color_passed() { printf '%sPASSED%s' "$COLOR_GREEN" "$COLOR_RESET"; }
color_allow() { printf '%sALLOW%s' "$COLOR_GREEN" "$COLOR_RESET"; }
color_deny() { printf '%sDENY%s' "$COLOR_RED" "$COLOR_RESET"; }
color_ask() { printf '%sASK%s' "$COLOR_YELLOW" "$COLOR_RESET"; }

color_outcome() {
    case "$1" in
        allow) color_allow ;;
        deny) color_deny ;;
        ask) color_ask ;;
        *) printf '%s' "$1" ;;
    esac
}

while [ $# -gt 0 ]; do
    case "$1" in
        --fragment) fragment="${2:-}"; shift 2 ;;
        --profile) profile="${2:-}"; shift 2 ;;
        --tool) tool="${2:-}"; shift 2 ;;
        --event) event="${2:-}"; shift 2 ;;
        --matcher) matcher="${2:-}"; shift 2 ;;
        --hook) hook_index="${2:-}"; shift 2 ;;
        --command) command_input="${2:-}"; shift 2 ;;
        --input) tool_input_json="${2:-}"; shift 2 ;;
        --expect) expect="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [ -n "$fragment" ] && [ -n "$profile" ]; then
    echo "Provide either --fragment or --profile, not both" >&2
    usage
    exit 1
fi

if [ -n "$command_input" ] && [ -n "$tool_input_json" ]; then
    echo "Provide either --command or --input, not both" >&2
    usage
    exit 1
fi

if [ -z "$command_input" ] && [ -z "$tool_input_json" ]; then
    echo "Provide either --command or --input" >&2
    usage
    exit 1
fi

case "$expect" in
    ""|allow|deny|ask) ;;
    *)
        echo "Invalid --expect value: $expect" >&2
        usage
        exit 1
        ;;
esac

resolve_fragment_path() {
    local query="$1"

    if [ -f "$query" ]; then
        printf '%s\n' "$query"
        return
    fi

    if [ -f "$LAYERS_DIR/$query" ]; then
        printf '%s\n' "$LAYERS_DIR/$query"
        return
    fi

    local matches=()
    while IFS= read -r f; do
        matches+=("$f")
    done < <(find "$LAYERS_DIR" -name '*.json' -type f | sort | grep -F "/$query"$'\n\|/'"$query"'$' || true)

    if [ "${#matches[@]}" -eq 1 ]; then
        printf '%s\n' "${matches[0]}"
        return
    fi

    if [ "${#matches[@]}" -gt 1 ]; then
        echo "Fragment path is ambiguous: $query" >&2
        printf 'Matches:\n' >&2
        printf '  %s\n' "${matches[@]#$LAYERS_DIR/}" >&2
        exit 1
    fi

    echo "Fragment not found: $query" >&2
    exit 1
}

relative_path() {
    local path="$1"
    if [[ "$path" == "$LAYERS_DIR/"* ]]; then
        printf '%s\n' "${path#"$LAYERS_DIR"/}"
    elif [[ "$path" == "$REPO_ROOT/"* ]]; then
        printf '%s\n' "${path#"$REPO_ROOT"/}"
    else
        printf '%s\n' "$path"
    fi
}

collect_profile_files() {
    local profile_file="$1"
    local layer="$2"
    local base=""

    case "$layer" in
        hooks) base="$LAYERS_DIR/2-hooks" ;;
        permissions) base="$LAYERS_DIR/3-permissions" ;;
        sub-agents) base="$LAYERS_DIR/4-sub-agents" ;;
        *)
            echo "Unknown layer: $layer" >&2
            exit 1
            ;;
    esac

    jq -r --arg layer "$layer" '.fragments[$layer] // [] | .[]' "$profile_file" | while IFS= read -r item; do
        [ -n "$item" ] || continue
        printf '%s/%s\n' "$base" "$item"
    done
}

hook_files=()
permission_files=()
tool_files=()

if [ -n "$profile" ]; then
    profile_file="$REPO_ROOT/profiles/${profile}.json"
    [ -f "$profile_file" ] || {
        echo "Profile not found: $profile" >&2
        exit 1
    }

    while IFS= read -r file; do hook_files+=("$file"); done < <(collect_profile_files "$profile_file" hooks)
    while IFS= read -r file; do permission_files+=("$file"); done < <(collect_profile_files "$profile_file" permissions)

    fragment_path="$profile_file"
    fragment_rel="profile:$profile"
    description=$(jq -r '.description // "No description"' "$profile_file")
elif [ -n "$fragment" ]; then
    fragment_path=$(resolve_fragment_path "$fragment")
    fragment_rel="${fragment_path#"$LAYERS_DIR"/}"
    description=$(jq -r '.description // "No description"' "$fragment_path")

    if jq -e 'has("hooks")' "$fragment_path" >/dev/null; then
        hook_files+=("$fragment_path")
    fi
    if jq -e 'has("permissions")' "$fragment_path" >/dev/null; then
        permission_files+=("$fragment_path")
    fi
    if jq -e 'has("tools")' "$fragment_path" >/dev/null; then
        tool_files+=("$fragment_path")
    fi
else
    while IFS= read -r file; do hook_files+=("$file"); done < <(find "$LAYERS_DIR/2-hooks" -name '*.json' -type f | sort)
    while IFS= read -r file; do permission_files+=("$file"); done < <(find "$LAYERS_DIR/3-permissions" -name '*.json' -type f | sort)

    fragment_path=""
    fragment_rel="build:default"
    description="Merged default settings produced by build-settings.sh"
fi

if [ -n "$tool_input_json" ]; then
    tool_input=$(printf '%s\n' "$tool_input_json" | jq -ec '.')
else
    tool_input=$(jq -cn --arg command "$command_input" '{command: $command}')
fi

print_header() {
    printf 'Target: %s\n' "$fragment_rel"
    printf 'Description: %s\n' "$description"
    if [ -n "$profile" ]; then
        printf 'Profile: %s\n' "$profile"
    elif [ -z "$fragment" ]; then
        printf 'Mode: default build\n'
    fi
    printf 'Tool: %s\n' "$tool"
    printf 'Input: %s\n' "$tool_input"
}

matches_pattern() {
    local value="$1" pattern="$2"
    case "$value" in
        $pattern) return 0 ;;
        *) return 1 ;;
    esac
}

evaluate_permissions() {
    local final="none"
    local matched=""
    local matched_source=""
    local command=""
    local match_count=0

    command=$(printf '%s\n' "$tool_input" | jq -r '.command // ""')
    local candidates=("$tool")
    if [ -n "$command" ]; then
        candidates+=("$tool($command)")
    fi

    local file source category rule candidate
    for file in "${permission_files[@]}"; do
        source=$(relative_path "$file")
        for category in deny ask allow; do
            while IFS= read -r rule; do
                [ -n "$rule" ] || continue
                for candidate in "${candidates[@]}"; do
                    if matches_pattern "$candidate" "$rule"; then
                        printf 'permissions_match_%s_category=%s\n' "$match_count" "$category"
                        printf 'permissions_match_%s_rule=%s\n' "$match_count" "$rule"
                        printf 'permissions_match_%s_source=%s\n' "$match_count" "$source"
                        match_count=$((match_count + 1))
                        if [ "$final" = "none" ]; then
                            final="$category"
                            matched="$rule"
                            matched_source="$source"
                        fi
                        break
                    fi
                done
            done < <(jq -r ".permissions.${category}[]? // empty" "$file")
        done
    done

    if [ "$final" != "none" ]; then
        printf 'permissions_result=%s\n' "$final"
        printf 'permissions_match=%s\n' "$matched"
        printf 'permissions_match_source=%s\n' "$matched_source"
    else
        printf 'permissions_result=none\n'
    fi
}

evaluate_tools() {
    [ "${#tool_files[@]}" -gt 0 ] || return

    local tool_file="${tool_files[0]}"
    if ! jq -e 'has("tools")' "$tool_file" >/dev/null; then
        return
    fi

    local tool_result="deny"
    if jq -e --arg tool "$tool" 'any(.tools[]?; . == $tool)' "$tool_file" >/dev/null; then
        tool_result="allow"
    fi

    printf 'tools_result=%s\n' "$tool_result"
    printf 'tools_source=%s\n' "$(relative_path "$tool_file")"
}

evaluate_hooks() {
    [ "${#hook_files[@]}" -gt 0 ] || return

    local has_event=false
    local file
    for file in "${hook_files[@]}"; do
        if jq -e --arg event "$event" '.hooks[$event]?' "$file" >/dev/null; then
            has_event=true
            break
        fi
    done

    if ! $has_event; then
        return
    fi

    local selected_hooks hook_count hook_cmd status matcher_value index result hook_result
    selected_hooks='[]'
    for file in "${hook_files[@]}"; do
        local source entries
        source=$(relative_path "$file")
        entries=$(jq -c \
            --arg event "$event" \
            --arg matcher "${matcher:-$tool}" \
            --arg source "$source" \
            '[ (.hooks[$event] // [])[]
               | select(.matcher == $matcher)
               | .hooks[]
               | . + {__matcher: $matcher, __source: $source} ]' \
            "$file")
        selected_hooks=$(jq -cn --argjson current "$selected_hooks" --argjson new "$entries" '$current + $new')
    done

    hook_count=$(printf '%s\n' "$selected_hooks" | jq 'length')
    printf 'hooks_matched=%s\n' "$hook_count"

    if [ "$hook_count" -eq 0 ]; then
        printf 'hooks_result=none\n'
        return
    fi

    if [ -n "$hook_index" ]; then
        selected_hooks=$(printf '%s\n' "$selected_hooks" | jq --argjson hook "$hook_index" '[.[ $hook ]]')
        hook_count=$(printf '%s\n' "$selected_hooks" | jq 'length')
        [ "$hook_count" -eq 1 ] || {
            echo "Hook not found for matcher=${matcher:-$tool} hook=$hook_index" >&2
            exit 1
        }
        printf 'hooks_scoped_to=%s\n' "$hook_index"
    fi

    result="allow"
    while IFS= read -r index; do
        hook_cmd=$(printf '%s\n' "$selected_hooks" | jq -r ".[$index].command")
        status=$(printf '%s\n' "$selected_hooks" | jq -r ".[$index].statusMessage // \"Evaluating hook\"")
        matcher_value=$(printf '%s\n' "$selected_hooks" | jq -r ".[$index].__matcher")
        local source_value
        source_value=$(printf '%s\n' "$selected_hooks" | jq -r ".[$index].__source")

        if printf '%s\n' "$(printf '%s\n' "$tool_input" | jq -c '{tool_input: .}')" | bash -c "$hook_cmd" >/dev/null 2>&1; then
            hook_result="allow"
        else
            hook_result="deny"
            result="deny"
        fi

        printf 'hook_%s_matcher=%s\n' "$index" "$matcher_value"
        printf 'hook_%s_source=%s\n' "$index" "$source_value"
        printf 'hook_%s_status=%s\n' "$index" "$status"
        printf 'hook_%s_result=%s\n' "$index" "$hook_result"
    done < <(seq 0 $((hook_count - 1)))

    printf 'hooks_result=%s\n' "$result"
}

final_result() {
    local tools_result hooks_result permissions_result

    tools_result=$(evaluate_tools)
    hooks_result=$(evaluate_hooks)
    permissions_result=$(evaluate_permissions)

    printf '%s' "$tools_result"
    [ -n "$tools_result" ] && printf '\n'
    printf '%s' "$hooks_result"
    [ -n "$hooks_result" ] && printf '\n'
    printf '%s' "$permissions_result"
}

detail_value() {
    local key="$1"
    printf '%s\n' "$details" | sed -n "s/^${key}=//p" | head -1
}

print_tools_section() {
    local tool_result tool_source
    tool_result=$(detail_value "tools_result")
    [ -n "$tool_result" ] || return 0
    tool_source=$(detail_value "tools_source")

    echo ""
    echo "Tool access:"
    if [ "$tool_result" = "allow" ]; then
        printf '  - %s: `%s` is present in `%s`.\n' "$(color_allow)" "$tool" "$tool_source"
    else
        printf '  - %s: `%s` is not present in `%s`.\n' "$(color_deny)" "$tool" "$tool_source"
    fi
}

print_denied_by_section() {
    [ "$result" = "deny" ] || return 0

    local printed=false
    local permissions_result
    permissions_result=$(detail_value "permissions_result")

    echo ""
    echo "Denied by:"

    while IFS= read -r index; do
        local hook_result source status
        hook_result=$(detail_value "hook_${index}_result")
        [ "$hook_result" = "deny" ] || continue
        source=$(detail_value "hook_${index}_source")
        status=$(detail_value "hook_${index}_status")
        printf '  - hook in `%s`: %s\n' "$source" "$status"
        printed=true
    done < <(printf '%s\n' "$details" | sed -n 's/^hook_\([0-9]\+\)_status=.*/\1/p' | sort -n)

    if [ "$permissions_result" != "none" ]; then
        while IFS= read -r index; do
            local category rule source
            category=$(detail_value "permissions_match_${index}_category")
            [ "$category" = "deny" ] || continue
            rule=$(detail_value "permissions_match_${index}_rule")
            source=$(detail_value "permissions_match_${index}_source")
            printf '  - permission in `%s`: `%s`\n' "$source" "$rule"
            printed=true
        done < <(printf '%s\n' "$details" | sed -n 's/^permissions_match_\([0-9]\+\)_category=.*/\1/p' | sort -n | uniq)
    fi

    if ! $printed; then
        echo "  - No specific denying rule captured."
    fi
}

print_hooks_section() {
    local hooks_result hooks_matched hooks_scoped_to
    hooks_result=$(detail_value "hooks_result")
    [ -n "$hooks_result" ] || return 0

    echo ""
    if [ "$hooks_result" = "none" ]; then
        echo "Hook checks:"
        echo "  - No matching hooks for this tool/event."
        return
    fi

    hooks_matched=$(detail_value "hooks_matched")
    hooks_scoped_to=$(detail_value "hooks_scoped_to")

    if [ -n "$hooks_scoped_to" ]; then
        printf 'Hook checks (scoped to hook %s):\n' "$hooks_scoped_to"
    else
        printf 'Hook checks (%s matched):\n' "$hooks_matched"
    fi

    while IFS= read -r index; do
        local status hook_result source
        status=$(detail_value "hook_${index}_status")
        hook_result=$(detail_value "hook_${index}_result")
        source=$(detail_value "hook_${index}_source")

        if [ "$hook_result" = "deny" ]; then
            printf '  %s. %s: %s [%s]\n' "$((index + 1))" "$(color_blocked)" "$status" "$source"
        else
            printf '  %s. %s: %s [%s]\n' "$((index + 1))" "$(color_passed)" "$status" "$source"
        fi
    done < <(printf '%s\n' "$details" | sed -n 's/^hook_\([0-9]\+\)_status=.*/\1/p' | sort -n)

    printf '  Overall hook outcome: %s\n' "$(color_outcome "$hooks_result")"
}

print_permissions_section() {
    local permissions_result permissions_match permissions_match_source
    permissions_result=$(detail_value "permissions_result")
    [ -n "$permissions_result" ] || return 0

    echo ""
    echo "Permissions:"
    if [ "$permissions_result" = "none" ]; then
        echo "  - No matching permission rules."
        return
    fi

    while IFS= read -r index; do
        local category rule source
        category=$(detail_value "permissions_match_${index}_category")
        rule=$(detail_value "permissions_match_${index}_rule")
        source=$(detail_value "permissions_match_${index}_source")
        printf '  - matched %s rule in `%s`: `%s`\n' "$(color_outcome "$category")" "$source" "$rule"
    done < <(printf '%s\n' "$details" | sed -n 's/^permissions_match_\([0-9]\+\)_category=.*/\1/p' | sort -n | uniq)

    permissions_match=$(detail_value "permissions_match")
    permissions_match_source=$(detail_value "permissions_match_source")
    printf '  Effective permission outcome: %s' "$(color_outcome "$permissions_result")"
    if [ -n "$permissions_match" ]; then
        printf ' (first decisive match: `%s` in `%s`)' "$permissions_match" "$permissions_match_source"
    fi
    printf '\n'
}

print_header
details=$(final_result)

result="allow"
if printf '%s\n' "$details" | grep -q '^tools_result=deny$'; then
    result="deny"
elif printf '%s\n' "$details" | grep -q '^hooks_result=deny$'; then
    result="deny"
elif printf '%s\n' "$details" | grep -q '^permissions_result=deny$'; then
    result="deny"
elif printf '%s\n' "$details" | grep -q '^permissions_result=ask$'; then
    result="ask"
fi

echo ""
printf 'Decision: %s\n' "$(color_outcome "$result")"
print_denied_by_section
print_tools_section
print_hooks_section
print_permissions_section

if [ -n "$expect" ] && [ "$result" != "$expect" ]; then
    printf 'expected=%s\n' "$expect" >&2
    echo "Fragment result did not match expectation" >&2
    exit 1
fi
