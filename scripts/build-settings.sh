#!/usr/bin/env bash
#
# Merges guardrail layer fragments into a Claude Code settings.json
#
# Usage:
#   ./scripts/build-settings.sh                                  # install all layers
#   ./scripts/build-settings.sh --profile go-dev                 # install a profile
#   ./scripts/build-settings.sh --profile infra-dev --dry-run    # preview a profile
#   ./scripts/build-settings.sh --layers hooks                   # advanced: install hooks only
#   ./scripts/build-settings.sh --remove --layers hooks          # remove hooks from settings
#   ./scripts/build-settings.sh --target ~/my-project            # install all to a project
#   ./scripts/build-settings.sh --dry-run                        # preview without writing
#   ./scripts/build-settings.sh --list-profiles                  # list available profiles
#   ./scripts/build-settings.sh --list                           # list available fragments
#
# The script merges guardrail fragments into the target settings.json while
# preserving any existing settings (model, plugins, etc.).
# Sub-agents are copied as individual files to .claude/agents/.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAYERS_DIR="$REPO_ROOT/layers"

# Defaults
TARGET="user"
LAYERS=""
PROFILE=""
DRY_RUN=false
OVERWRITE=false
SKIP_CONFIRM=false
INIT_REPO=false
ACTION="build"
PROFILES_DIR="$REPO_ROOT/profiles"
BASE_PROFILE="default"

# Available layers (mapped to directory names)
declare -A LAYER_DIRS=(
    [hooks]="2-hooks"
    [permissions]="3-permissions"
    [sub-agents]="4-sub-agents"
)

# Layers that merge into settings.json
SETTINGS_LAYERS="hooks permissions"

# Hook event types supported by Claude Code settings.json
HOOK_EVENTS="PreToolUse PostToolUse"

if ! command -v jq &>/dev/null; then
    echo "Error: jq is required." >&2
    echo "  Fedora/RHEL: sudo dnf install jq" >&2
    echo "  Ubuntu/Debian: sudo apt install jq" >&2
    echo "  macOS: brew install jq" >&2
    exit 1
fi

usage() {
    cat <<'USAGE'
Usage: build-settings.sh [OPTIONS]

Options:
  --target <location>     Where to install settings (default: user)
                             user      - ~/.claude/settings.json (all projects)
                             project   - this repo's .claude/settings.json
                             <path>    - a specific project directory
  --profile <name>        Build from a profile (recommended)
  --layers <list>         Advanced: comma-separated layers to install/remove
                             hooks         - PreToolUse/PostToolUse hook guardrails
                             permissions   - tool allow/deny rules
                             sub-agents    - scoped agent definitions (.claude/agents/)
                           Combine: --layers hooks,permissions
  --replace               Replace generated layers instead of merging them
  --overwrite             Deprecated alias for --replace
  --remove                Remove selected layers from target settings.json
  --dry-run               Preview the merged output without writing
  --list                  List available fragments per layer
  --show <fragment>       Show the full contents of a fragment (e.g. aws/safety.json)
  --show-profile <name>   Show a profile and the fragments it will apply
  --filter <query>        With --show-profile, show JSON for matching effective fragments
  --list-profiles         List available profiles
  --help, -h              Show this help

Examples:
  # Install a profile to user-level settings
  ./scripts/build-settings.sh --profile go-dev --target user

  # Preview a profile without writing
  ./scripts/build-settings.sh --profile infra-dev --dry-run

  # Remove hooks from user settings
  ./scripts/build-settings.sh --remove --layers hooks --target user

  # Advanced: install only hooks and permissions to a specific project
  ./scripts/build-settings.sh --layers hooks,permissions --target ~/my-project

  # Replace previously generated layers instead of merging
  ./scripts/build-settings.sh --profile go-dev --replace

  # Show the contents of a specific fragment
  ./scripts/build-settings.sh --show aws/safety.json

  # Show a profile and the fragments it applies
  ./scripts/build-settings.sh --show-profile go-dev

  # Show matching fragment JSON within a profile
  ./scripts/build-settings.sh --show-profile default --filter git/safety.json

  # List available profiles
  ./scripts/build-settings.sh --list-profiles
USAGE
}

resolve_target_dir() {
    case "$TARGET" in
        user)
            echo "$HOME/.claude"
            ;;
        project)
            echo "$REPO_ROOT/.claude"
            ;;
        *)
            if [ ! -d "$TARGET" ]; then
                echo "Error: target directory does not exist: $TARGET" >&2
                exit 1
            fi
            echo "$TARGET/.claude"
            ;;
    esac
}

validate_layers() {
    local input="$1"
    IFS=',' read -ra requested <<< "$input"
    for layer in "${requested[@]}"; do
        layer=$(echo "$layer" | xargs) # trim whitespace
        if [ -z "${LAYER_DIRS[$layer]+x}" ]; then
            echo "Error: unknown layer '$layer'" >&2
            echo "Available layers: ${!LAYER_DIRS[*]}" >&2
            exit 1
        fi
    done
}

layer_enabled() {
    local layer="$1"
    if [ -z "$LAYERS" ]; then
        return 0 # all layers enabled by default
    fi
    echo "$LAYERS" | tr ',' '\n' | grep -qx "$layer"
}

# Check if any settings.json layers are enabled
settings_layers_enabled() {
    for layer in $SETTINGS_LAYERS; do
        if layer_enabled "$layer"; then
            return 0
        fi
    done
    return 1
}

list_fragments() {
    local dir desc rel

    echo "Available layers and fragments:"
    echo ""

    for layer in hooks permissions sub-agents; do
        dir="$LAYERS_DIR/${LAYER_DIRS[$layer]}"
        echo "  $layer (layers/${LAYER_DIRS[$layer]}/):"
        while IFS= read -r f; do
            rel="${f#"$dir"/}"
            desc=$(jq -r '.description // "No description"' "$f")
            echo "    $rel: $desc"
        done < <(find "$dir" -name '*.json' -type f | sort)
        echo ""
    done
}

show_fragment() {
    local query="$1"
    local matches=()

    # Search all layer directories for matching fragments
    while IFS= read -r f; do
        local rel="${f#"$LAYERS_DIR"/}"
        # Match against the relative path (e.g. "aws/safety.json" matches "2-hooks/aws/safety.json")
        if [[ "$rel" == *"$query"* ]]; then
            matches+=("$f")
        fi
    done < <(find "$LAYERS_DIR" -name '*.json' -type f | sort)

    if [ ${#matches[@]} -eq 0 ]; then
        echo "No fragment matching '$query' found." >&2
        echo "" >&2
        echo "Run --list to see available fragments." >&2
        exit 1
    fi

    for file in "${matches[@]}"; do
        local rel="${file#"$LAYERS_DIR"/}"
        local desc
        desc=$(jq -r '.description // "No description"' "$file")

        echo "Fragment: $rel"
        echo "Description: $desc"
        echo ""
        jq '.' "$file"
        if [ ${#matches[@]} -gt 1 ]; then
            echo ""
            echo "---"
            echo ""
        fi
    done
}

profile_effective_fragments() {
    local name="$1"
    local layer="$2"

    while IFS= read -r chain_profile; do
        local chain_profile_file
        chain_profile_file=$(resolve_profile "$chain_profile")
        jq -r --arg layer "$layer" --arg source "$chain_profile" '
            .fragments[$layer] // [] | .[] | "\($source)|\(.)"
        ' "$chain_profile_file"
    done < <(
        if [ "$name" != "$BASE_PROFILE" ]; then
            printf '%s\n' "$BASE_PROFILE"
        fi
        printf '%s\n' "$name"
    )
}

resolve_profile_fragment_file() {
    local fragment="$1"
    local layer

    for layer in hooks permissions sub-agents; do
        local dir="$LAYERS_DIR/${LAYER_DIRS[$layer]}"
        if [ -f "$dir/$fragment" ]; then
            printf '%s\n' "$dir/$fragment"
            return 0
        fi
    done

    return 1
}

show_profile() {
    local name="$1"
    local filter="${2:-}"
    local profile_file
    profile_file=$(resolve_profile "$name")

    local desc use
    desc=$(jq -r '.description // "No description"' "$profile_file")
    use=$(jq -r '.intendedUse // ""' "$profile_file")

    echo "Profile: $name"
    echo "Description: $desc"
    if [ -n "$use" ]; then
        echo "Intended use: $use"
    fi
    echo ""
    echo "Effective fragments:"
    echo ""

    local layer found
    for layer in hooks permissions sub-agents; do
        echo "  $layer:"
        found=false
        while IFS='|' read -r source_profile fragment; do
            [ -n "$fragment" ] || continue
            found=true
            printf '    - %s (from %s)\n' "$fragment" "$source_profile"
        done < <(profile_effective_fragments "$name" "$layer")
        if [ "$found" = false ]; then
            echo "    - none"
        fi
        echo ""
    done

    if [ -n "$filter" ]; then
        local matches=()
        local layer_match
        for layer_match in hooks permissions sub-agents; do
            while IFS='|' read -r source_profile fragment; do
                [ -n "$fragment" ] || continue
                if [[ "$fragment" == *"$filter"* ]]; then
                    matches+=("$source_profile|$fragment")
                fi
            done < <(profile_effective_fragments "$name" "$layer_match")
        done

        if [ ${#matches[@]} -eq 0 ]; then
            echo "No profile fragment matching '$filter' found in profile '$name'." >&2
            exit 1
        fi

        echo "Matching fragment details:"
        echo ""

        local index=0
        local source_profile fragment full_path desc
        for match in "${matches[@]}"; do
            IFS='|' read -r source_profile fragment <<< "$match"
            full_path=$(resolve_profile_fragment_file "$fragment") || {
                echo "Could not resolve fragment file for '$fragment'" >&2
                exit 1
            }
            desc=$(jq -r '.description // "No description"' "$full_path")

            echo "Fragment: $fragment"
            echo "Source: $source_profile"
            echo "Description: $desc"
            echo ""
            jq '.' "$full_path"

            index=$((index + 1))
            if [ "$index" -lt "${#matches[@]}" ]; then
                echo ""
                echo "---"
                echo ""
            fi
        done
    fi
}

list_profiles() {
    echo "Available profiles:"
    echo ""
    for f in "$PROFILES_DIR"/*.json; do
        [ -f "$f" ] || continue
        local name desc use
        name=$(basename "$f" .json)
        desc=$(jq -r '.description // "No description"' "$f")
        use=$(jq -r '.intendedUse // ""' "$f")
        printf "  %-20s %s\n" "$name" "$desc"
        if [ -n "$use" ]; then
            printf "  %-20s %s\n" "" "$use"
        fi
        echo ""
    done
}

show_diff() {
    local output="$1" new_content="$2"
    local old_content='{}'
    if [ -f "$output" ]; then
        old_content=$(jq '.' "$output")
    fi
    local new_formatted
    new_formatted=$(echo "$new_content" | jq '.')

    if [ "$old_content" = "$new_formatted" ]; then
        echo "# No changes to: $output"
        return
    fi

    echo "# Changes to: $output"
    diff --color=auto -u \
        <(echo "$old_content") \
        <(echo "$new_formatted") \
        --label "current" --label "proposed" \
    || true  # diff exits 1 when files differ
}

resolve_profile() {
    local name="$1"
    local profile_file="$PROFILES_DIR/${name}.json"

    if [ ! -f "$profile_file" ]; then
        echo "Error: profile '$name' not found at $profile_file" >&2
        echo "Run --list-profiles to see available profiles." >&2
        exit 1
    fi

    echo "$profile_file"
}

profile_chain() {
    local name="$1"

    if [ "$name" != "$BASE_PROFILE" ]; then
        resolve_profile "$BASE_PROFILE"
    fi
    resolve_profile "$name"
}

profile_layers() {
    local name="$1"

    while IFS= read -r profile_file; do
        jq -r '.layers // [] | .[]' "$profile_file"
    done < <(profile_chain "$name") | awk 'NF && !seen[$0]++'
}

# Collect fragment files for a profile's layer
# Returns newline-separated absolute paths
profile_fragments() {
    local profile_name="$1"
    local layer="$2"
    local dir="$LAYERS_DIR/${LAYER_DIRS[$layer]}"

    while IFS= read -r profile_file; do
        jq -r --arg layer "$layer" '.fragments[$layer] // [] | .[]' "$profile_file"
    done < <(profile_chain "$profile_name") | while IFS= read -r frag; do
        local full="$dir/$frag"
        if [ ! -f "$full" ]; then
            echo "Warning: fragment '$frag' not found in $layer layer" >&2
            continue
        fi
        echo "$full"
    done | awk 'NF && !seen[$0]++'
}

merge_hooks() {
    local dir="$LAYERS_DIR/${LAYER_DIRS[hooks]}"
    local result='{"hooks":{}}'

    for event in $HOOK_EVENTS; do
        result=$(echo "$result" | jq --arg ev "$event" '.hooks[$ev] = []')
    done

    if [ -n "$PROFILE" ]; then
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            for event in $HOOK_EVENTS; do
                local entries
                entries=$(jq --arg ev "$event" '.hooks[$ev] // []' "$f")
                result=$(echo "$result" | jq --arg ev "$event" --argjson new "$entries" '.hooks[$ev] += $new')
            done
        done < <(profile_fragments "$PROFILE" "hooks")
    else
        while IFS= read -r f; do
            for event in $HOOK_EVENTS; do
                local entries
                entries=$(jq --arg ev "$event" '.hooks[$ev] // []' "$f")
                result=$(echo "$result" | jq --arg ev "$event" --argjson new "$entries" '.hooks[$ev] += $new')
            done
        done < <(find "$dir" -name '*.json' -type f | sort)
    fi

    # Consolidate entries by matcher for each event type, drop empty events
    result=$(echo "$result" | jq '
        .hooks = (
            .hooks | to_entries | map(
                .value = (
                    .value
                    | group_by(.matcher)
                    | map({
                        matcher: .[0].matcher,
                        hooks: ([.[].hooks[]] | unique_by(.command))
                    })
                )
            ) | map(select(.value | length > 0)) | from_entries
        )
    ')

    echo "$result"
}

merge_permissions() {
    local dir="$LAYERS_DIR/${LAYER_DIRS[permissions]}"
    local result='{"permissions":{"allow":[],"deny":[]}}'

    if [ -n "$PROFILE" ]; then
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            local perms
            perms=$(jq '{allow: (.permissions.allow // []), deny: (.permissions.deny // [])}' "$f")
            result=$(echo "$result" | jq --argjson new "$perms" '
                .permissions.allow = (.permissions.allow + $new.allow | unique) |
                .permissions.deny = (.permissions.deny + $new.deny | unique)
            ')
        done < <(profile_fragments "$PROFILE" "permissions")
    else
        while IFS= read -r f; do
            local perms
            perms=$(jq '{allow: (.permissions.allow // []), deny: (.permissions.deny // [])}' "$f")
            result=$(echo "$result" | jq --argjson new "$perms" '
                .permissions.allow = (.permissions.allow + $new.allow | unique) |
                .permissions.deny = (.permissions.deny + $new.deny | unique)
            ')
        done < <(find "$dir" -name '*.json' -type f | sort)
    fi

    echo "$result"
}

install_sub_agents() {
    local src_dir="$LAYERS_DIR/${LAYER_DIRS[sub-agents]}"
    local dest_dir="$1/agents"
    local count=0
    local files=()

    if [ -n "$PROFILE" ]; then
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            files+=("$f")
        done < <(profile_fragments "$PROFILE" "sub-agents")
    else
        for f in "$src_dir"/*.json; do
            [ -f "$f" ] || continue
            files+=("$f")
        done
    fi

    if $DRY_RUN; then
        echo ""
        echo "Sub-agents (would copy to $dest_dir/):"
        for f in "${files[@]}"; do
            local name desc
            name=$(basename "$f")
            desc=$(jq -r '.description // "No description"' "$f")
            echo "  $name: $desc"
            count=$((count + 1))
        done
        if [ "$count" -eq 0 ]; then
            echo "  (none)"
        fi
        return
    fi

    mkdir -p "$dest_dir"

    # When using a profile, remove agents not in the profile's list
    if [ -n "$PROFILE" ] && [ -d "$dest_dir" ]; then
        local wanted=()
        for f in "${files[@]}"; do
            wanted+=("$(basename "$f")")
        done
        for existing in "$dest_dir"/*.json; do
            [ -f "$existing" ] || continue
            local ename
            ename=$(basename "$existing")
            local found=false
            for w in "${wanted[@]}"; do
                if [ "$w" = "$ename" ]; then found=true; break; fi
            done
            if ! $found; then
                rm "$existing"
            fi
        done
    fi

    for f in "${files[@]}"; do
        cp "$f" "$dest_dir/"
        count=$((count + 1))
    done

    echo "Sub-agents:"
    for f in "$dest_dir"/*.json; do
        [ -f "$f" ] || continue
        local name desc
        name=$(basename "$f")
        desc=$(jq -r '.description // "No description"' "$f")
        echo "  $name: $desc"
    done
    echo "  Installed $count agent(s) to $dest_dir/"
    echo ""
}

remove_sub_agents() {
    local dest_dir="$1/agents"
    local src_dir="$LAYERS_DIR/${LAYER_DIRS[sub-agents]}"

    if $DRY_RUN; then
        echo "Would remove sub-agents from $dest_dir/"
        return
    fi

    if [ ! -d "$dest_dir" ]; then
        echo "No agents directory at $dest_dir"
        return
    fi

    local count=0
    for f in "$src_dir"/*.json; do
        [ -f "$f" ] || continue
        local name
        name=$(basename "$f")
        if [ -f "$dest_dir/$name" ]; then
            rm "$dest_dir/$name"
            count=$((count + 1))
        fi
    done

    # Remove agents dir if empty
    if [ -d "$dest_dir" ] && [ -z "$(ls -A "$dest_dir")" ]; then
        rmdir "$dest_dir"
    fi

    echo "Removed $count sub-agent(s) from $dest_dir/"
}

do_remove() {
    local output="$1"
    local target_dir="$2"

    if ! settings_layers_enabled && ! layer_enabled sub-agents; then
        return
    fi

    # Build remove summary
    local removing=""
    if layer_enabled hooks; then removing+="hooks, "; fi
    if layer_enabled permissions; then removing+="permissions, "; fi
    if layer_enabled sub-agents; then removing+="sub-agents, "; fi
    removing="${removing%, }"

    if $DRY_RUN; then
        if settings_layers_enabled && [ -f "$output" ]; then
            local current
            current=$(cat "$output")
            if layer_enabled hooks; then current=$(echo "$current" | jq 'del(.hooks)'); fi
            if layer_enabled permissions; then current=$(echo "$current" | jq 'del(.permissions)'); fi
            show_diff "$output" "$current"
        fi
        if layer_enabled sub-agents; then
            echo "Would remove sub-agents from $target_dir/agents/"
        fi
        return
    fi

    if settings_layers_enabled && [ -f "$output" ]; then
        local preview
        preview=$(cat "$output")
        if layer_enabled hooks; then preview=$(echo "$preview" | jq 'del(.hooks)'); fi
        if layer_enabled permissions; then preview=$(echo "$preview" | jq 'del(.permissions)'); fi
        show_diff "$output" "$preview"
        echo ""
    fi

    if ! $SKIP_CONFIRM; then
        printf "This will remove %s from %s. Continue? [y/N] " "$removing" "$output"
        read -r ans
        if [ "$ans" != "y" ] && [ "$ans" != "Y" ]; then
            echo "Aborted."
            exit 1
        fi
    fi

    if layer_enabled sub-agents; then
        remove_sub_agents "$target_dir"
    fi

    if settings_layers_enabled; then
        if [ ! -f "$output" ]; then
            echo "Nothing to remove: $output does not exist" >&2
            exit 1
        fi
        local current
        current=$(cat "$output")
        if layer_enabled hooks; then current=$(echo "$current" | jq 'del(.hooks)'); fi
        if layer_enabled permissions; then current=$(echo "$current" | jq 'del(.permissions)'); fi
        echo "$current" | jq '.' > "$output"
        echo "Removed layers from: $output"
    fi
    echo ""
}

# Parse args
while [ $# -gt 0 ]; do
    case "$1" in
        --target)
            TARGET="${2:?--target requires a value (user, project, or a path)}"
            shift 2
            ;;
        --layers)
            LAYERS="${2:?--layers requires a comma-separated list (e.g. hooks,permissions)}"
            validate_layers "$LAYERS"
            shift 2
            ;;
        --remove)
            ACTION="remove"
            shift
            ;;
        --replace|--overwrite)
            OVERWRITE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --yes)
            SKIP_CONFIRM=true
            shift
            ;;
        --init)
            INIT_REPO=true
            shift
            ;;
        --list)
            list_fragments
            exit 0
            ;;
        --show)
            show_fragment "${2:?--show requires a fragment name (e.g. aws/safety.json)}"
            exit 0
            ;;
        --show-profile)
            show_profile_name="${2:?--show-profile requires a profile name (e.g. default, go-dev)}"
            shift 2
            show_profile_filter=""
            if [ "${1:-}" = "--filter" ]; then
                show_profile_filter="${2:?--filter requires a fragment query}"
                shift 2
            fi
            show_profile "$show_profile_name" "$show_profile_filter"
            exit 0
            ;;
        --profile)
            PROFILE="${2:?--profile requires a name (e.g. go-dev, infra-dev)}"
            shift 2
            ;;
        --list-profiles)
            list_profiles
            exit 0
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

# If a profile is set, derive layers from it
if [ -n "$PROFILE" ]; then
    if [ -n "$LAYERS" ]; then
        echo "Error: --profile and --layers cannot be used together." >&2
        echo "Profiles define their own layers." >&2
        exit 1
    fi
    resolve_profile "$PROFILE" >/dev/null
    LAYERS=$(profile_layers "$PROFILE" | paste -sd, -)
fi

TARGET_DIR=$(resolve_target_dir)
OUTPUT="$TARGET_DIR/settings.json"

if [ "$ACTION" = "remove" ]; then
    do_remove "$OUTPUT" "$TARGET_DIR"
    exit 0
fi

# Build settings.json layers
if ! settings_layers_enabled && ! layer_enabled sub-agents; then
    exit 0
fi

generated='{}'

if layer_enabled hooks; then
    hooks_result=$(merge_hooks)
    generated=$(echo "$generated" | jq --argjson h "$hooks_result" '. + $h')
fi

if layer_enabled permissions; then
    perms_result=$(merge_permissions)
    generated=$(echo "$generated" | jq --argjson p "$perms_result" '. + $p')
fi

# Merge or overwrite existing settings
if [ -f "$OUTPUT" ]; then
    existing=$(cat "$OUTPUT")

    if $OVERWRITE; then
        # Strip only the selected layers from existing, then overlay generated
        base="$existing"
        if layer_enabled hooks; then
            base=$(echo "$base" | jq 'del(.hooks)')
        fi
        if layer_enabled permissions; then
            base=$(echo "$base" | jq 'del(.permissions)')
        fi
        final=$(echo "$base" | jq --argjson gen "$generated" '. + $gen')
    else
        # Merge: append hooks/permissions to existing
        final=$(echo "$existing" | jq --argjson gen "$generated" '
            # Merge hooks: combine arrays per event type, consolidate by matcher
            (if $gen.hooks then
                reduce ($gen.hooks | to_entries[]) as $entry (
                    .;
                    ($entry.key) as $event |
                    ($entry.value // []) as $new_hooks |
                    (.hooks[$event] // []) as $old_hooks |
                    .hooks[$event] = (
                        $old_hooks + $new_hooks
                        | group_by(.matcher)
                        | map({
                            matcher: .[0].matcher,
                            hooks: [.[].hooks[]] | unique_by(.command)
                        })
                    )
                )
            else . end) |

            # Merge permissions: union allow/deny arrays
            (if $gen.permissions then
                .permissions.allow = ((.permissions.allow // []) + ($gen.permissions.allow // []) | unique) |
                .permissions.deny = ((.permissions.deny // []) + ($gen.permissions.deny // []) | unique)
            else . end)
        ')
    fi
else
    final="$generated"
fi

# Format
final=$(echo "$final" | jq '.')

action_verb="merge"
if $OVERWRITE; then action_verb="overwrite"; fi
if $INIT_REPO; then action_verb="initialize"; fi

summary_target="$OUTPUT"
if $DRY_RUN; then summary_target="$OUTPUT (dry-run)"; fi

summary_scope="default build"
if [ -n "$PROFILE" ]; then
    summary_scope="profile:$PROFILE"
elif [ -n "$LAYERS" ]; then
    summary_scope="advanced layers:$LAYERS"
fi

summary_mode="merged"
if $OVERWRITE; then summary_mode="replaced"; fi
if $INIT_REPO; then summary_mode="$summary_mode + repo init"; fi

agents_count=0
agent_names="none"
if layer_enabled sub-agents; then
    if [ -n "$PROFILE" ]; then
        profile_agents=()
        while IFS= read -r agent_file; do
            [ -n "$agent_file" ] || continue
            profile_agents+=("$(basename "$agent_file" .json)")
        done < <(profile_fragments "$PROFILE" "sub-agents")

        agents_count="${#profile_agents[@]}"
        if [ "$agents_count" -gt 0 ]; then
            agent_names=$(printf '%s\n' "${profile_agents[@]}" | jq -R . | jq -s -r 'join(", ")')
        else
            agent_names="none"
        fi
    else
        src_dir="$LAYERS_DIR/${LAYER_DIRS[sub-agents]}"
        agent_names=$(find "$src_dir" -name '*.json' -type f -exec basename {} .json \; | sort | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
        if [ -n "$agent_names" ]; then
            agents_count=$(printf '%s\n' "$agent_names" | awk -F', ' '{print NF}')
        fi
    fi
    if [ -n "$agent_names" ]; then
        :
    else
        agents_count=0
        agent_names="none"
    fi
fi

print_build_summary() {
    echo "Summary:"
    printf '  target: %s\n' "$summary_target"
    printf '  scope:  %s\n' "$summary_scope"
    printf '  mode:   %s\n' "$summary_mode"
    if settings_layers_enabled; then
        hooks_count=$(echo "$final" | jq '[.hooks? // {} | to_entries[]? | .value[]? | .hooks[]?] | length')
        allow_count=$(echo "$final" | jq '.permissions.allow // [] | length')
        deny_count=$(echo "$final" | jq '.permissions.deny // [] | length')
        printf '  hooks:  %s\n' "$hooks_count"
        printf '  perms:  allow=%s deny=%s\n' "$allow_count" "$deny_count"
    fi
    if layer_enabled sub-agents; then
        printf '  agents: %s' "$agents_count"
        if [ "$agent_names" != "none" ]; then
            printf ' (%s)' "$agent_names"
        fi
        printf '\n'
    fi
    if $INIT_REPO; then
        case "$TARGET" in
            user) claude_md_target="$HOME/CLAUDE.md" ;;
            project) claude_md_target="$REPO_ROOT/CLAUDE.md" ;;
            *) claude_md_target="$TARGET/CLAUDE.md" ;;
        esac
        printf '  CLAUDE.md: %s\n' "$claude_md_target"
    fi
    echo ""
}

print_scope_message() {
    case "$TARGET" in
        user)
            if [ -n "$PROFILE" ]; then
                if [ "$PROFILE" = "$BASE_PROFILE" ]; then
                    echo "This will apply the default guardrails baseline to all projects."
                else
                    printf "This will apply the %s guardrails profile to all projects.\n" "$PROFILE"
                fi
            else
                echo "This will apply guardrails to all projects."
            fi
            ;;
        project)
            if [ -n "$PROFILE" ]; then
                if [ "$PROFILE" = "$BASE_PROFILE" ]; then
                    echo "This will apply the default guardrails baseline to this project."
                else
                    printf "This will apply the %s guardrails profile to this project.\n" "$PROFILE"
                fi
            fi
            ;;
        *)
            if [ -n "$PROFILE" ]; then
                if [ "$PROFILE" = "$BASE_PROFILE" ]; then
                    printf "This will apply the default guardrails baseline to %s.\n" "$TARGET"
                else
                    printf "This will apply the %s guardrails profile to %s.\n" "$PROFILE" "$TARGET"
                fi
            fi
            ;;
    esac
}

print_reload_notice() {
    if [ -n "$PROFILE" ]; then
        echo "Claude Code may need a reload to pick up the updated profile settings."
        echo "Reload Claude Code before starting your next session."
        echo ""
    fi
}

if $DRY_RUN; then
    print_build_summary
    if layer_enabled sub-agents; then
        install_sub_agents "$TARGET_DIR"
    fi
    if settings_layers_enabled; then
        show_diff "$OUTPUT" "$final"
    fi
    if $INIT_REPO; then
        echo "# Would copy CLAUDE.md to $claude_md_target"
    fi
else
    print_build_summary
    if settings_layers_enabled; then
        show_diff "$OUTPUT" "$final"
        echo ""
    fi
    if ! $SKIP_CONFIRM; then
        print_scope_message
        printf "This will %s guardrails into %s. Continue? [y/N] " "$action_verb" "$OUTPUT"
        read -r ans
        if [ "$ans" != "y" ] && [ "$ans" != "Y" ]; then
            echo "Aborted."
            exit 1
        fi
    fi
    if layer_enabled sub-agents; then
        install_sub_agents "$TARGET_DIR"
    fi
    if settings_layers_enabled; then
        mkdir -p "$(dirname "$OUTPUT")"
        echo "$final" > "$OUTPUT"
        echo "Written to: $OUTPUT"
    fi
    if $INIT_REPO; then
        if cp -n "$REPO_ROOT/layers/1-claude-md/CLAUDE.md" "$claude_md_target" 2>/dev/null; then
            echo "Copied CLAUDE.md to $claude_md_target"
        else
            echo "CLAUDE.md already exists, skipped"
        fi
    fi
    print_reload_notice
    echo ""
fi
