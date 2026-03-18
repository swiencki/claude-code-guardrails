#!/usr/bin/env bash
#
# Merges guardrail layer fragments into a Claude Code settings.json
#
# Usage:
#   ./scripts/build-settings.sh                                  # install all layers
#   ./scripts/build-settings.sh --layers hooks                   # install hooks only
#   ./scripts/build-settings.sh --layers hooks,permissions       # install hooks and permissions
#   ./scripts/build-settings.sh --layers hooks --target user     # install hooks to user settings
#   ./scripts/build-settings.sh --remove --layers hooks          # remove hooks from settings
#   ./scripts/build-settings.sh --target ~/my-project            # install all to a project
#   ./scripts/build-settings.sh --dry-run                        # preview without writing
#   ./scripts/build-settings.sh --profile go-dev                  # install a profile
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
TARGET="project"
LAYERS=""
PROFILE=""
DRY_RUN=false
OVERWRITE=false
SKIP_CONFIRM=false
INIT_REPO=false
ACTION="build"
PROFILES_DIR="$REPO_ROOT/profiles"

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
  --target <location>     Where to install settings (default: project)
                            user      - ~/.claude/settings.json (all projects)
                            project   - this repo's .claude/settings.json
                            <path>    - a specific project directory
  --layers <list>         Comma-separated layers to install/remove (default: all)
                            hooks         - PreToolUse/PostToolUse hook guardrails
                            permissions   - tool allow/deny rules
                            sub-agents    - scoped agent definitions (.claude/agents/)
                          Combine: --layers hooks,permissions
  --remove                Remove selected layers from target settings.json
  --dry-run               Preview the merged output without writing
  --list                  List available fragments per layer
  --show <fragment>       Show the full contents of a fragment (e.g. aws/safety.json)
  --profile <name>        Build from a profile (e.g. go-dev, infra-dev)
  --list-profiles         List available profiles
  --help, -h              Show this help

Examples:
  # Install all guardrails to user-level settings
  ./scripts/build-settings.sh --target user

  # Install only hooks
  ./scripts/build-settings.sh --layers hooks

  # Install sub-agents to a project
  ./scripts/build-settings.sh --layers sub-agents --target ~/my-project

  # Remove hooks from user settings
  ./scripts/build-settings.sh --remove --layers hooks --target user

  # Install hooks and permissions to a specific project
  ./scripts/build-settings.sh --layers hooks,permissions --target ~/my-project

  # Preview what hooks would look like
  ./scripts/build-settings.sh --layers hooks --dry-run

  # Show the contents of a specific fragment
  ./scripts/build-settings.sh --show aws/safety.json

  # Install a profile
  ./scripts/build-settings.sh --profile go-dev --target ~/my-project

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

# Collect fragment files for a profile's layer
# Returns newline-separated absolute paths
profile_fragments() {
    local profile_file="$1"
    local layer="$2"
    local dir="$LAYERS_DIR/${LAYER_DIRS[$layer]}"

    jq -r --arg layer "$layer" '.fragments[$layer] // [] | .[]' "$profile_file" | while IFS= read -r frag; do
        local full="$dir/$frag"
        if [ ! -f "$full" ]; then
            echo "Warning: fragment '$frag' not found in $layer layer" >&2
            continue
        fi
        echo "$full"
    done
}

merge_hooks() {
    local dir="$LAYERS_DIR/${LAYER_DIRS[hooks]}"
    local result='{"hooks":{}}'

    for event in $HOOK_EVENTS; do
        result=$(echo "$result" | jq --arg ev "$event" '.hooks[$ev] = []')
    done

    if [ -n "$PROFILE" ]; then
        local profile_file
        profile_file=$(resolve_profile "$PROFILE")
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            for event in $HOOK_EVENTS; do
                local entries
                entries=$(jq --arg ev "$event" '.hooks[$ev] // []' "$f")
                result=$(echo "$result" | jq --arg ev "$event" --argjson new "$entries" '.hooks[$ev] += $new')
            done
        done < <(profile_fragments "$profile_file" "hooks")
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
                        hooks: [.[].hooks[]]
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
        local profile_file
        profile_file=$(resolve_profile "$PROFILE")
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            local perms
            perms=$(jq '{allow: (.permissions.allow // []), deny: (.permissions.deny // [])}' "$f")
            result=$(echo "$result" | jq --argjson new "$perms" '
                .permissions.allow = (.permissions.allow + $new.allow | unique) |
                .permissions.deny = (.permissions.deny + $new.deny | unique)
            ')
        done < <(profile_fragments "$profile_file" "permissions")
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
        local profile_file
        profile_file=$(resolve_profile "$PROFILE")
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            files+=("$f")
        done < <(profile_fragments "$profile_file" "sub-agents")
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
            echo "# Would write to: $output"
            echo "$current" | jq '.'
        fi
        if layer_enabled sub-agents; then
            echo "Would remove sub-agents from $target_dir/agents/"
        fi
        return
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
        --overwrite)
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
    local_profile=$(resolve_profile "$PROFILE")
    LAYERS=$(jq -r '.layers // [] | join(",")' "$local_profile")
    echo "Profile: $PROFILE"
    jq -r '.description // ""' "$local_profile"
    echo ""
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

# Build summary
summary=""
if layer_enabled hooks; then
    for event in $HOOK_EVENTS; do
        hook_line=$(echo "$final" | jq -r --arg ev "$event" '.hooks[$ev][]? | "  [\($ev)/\(.matcher)] \(.hooks | length) hook(s)"')
        if [ -n "$hook_line" ]; then
            summary+="Hooks:
$hook_line
"
        fi
    done
fi

if layer_enabled permissions; then
    perm_line=$(echo "$final" | jq -r '.permissions // {} | "  allow: \(.allow // [] | length) rules, deny: \(.deny // [] | length) rules"')
    summary+="Permissions:
$perm_line
"
fi

if layer_enabled sub-agents; then
    src_dir="$LAYERS_DIR/${LAYER_DIRS[sub-agents]}"
    agent_names=""
    if [ -n "$PROFILE" ]; then
        pf=$(resolve_profile "$PROFILE")
        agent_names=$(jq -r '.fragments["sub-agents"] // [] | .[] | rtrimstr(".json")' "$pf" | paste -sd ", " -)
    else
        agent_names=$(find "$src_dir" -name '*.json' -type f -exec basename {} .json \; | sort | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
    fi
    if [ -n "$agent_names" ]; then
        summary+="Agents:   $agent_names
"
    fi
fi

if [ -n "$PROFILE" ]; then
    summary="Profile:  $PROFILE
$summary"
fi

if $INIT_REPO; then
    case "$TARGET" in
        user) claude_md_target="$HOME/CLAUDE.md" ;;
        project) claude_md_target="$REPO_ROOT/CLAUDE.md" ;;
        *) claude_md_target="$TARGET/CLAUDE.md" ;;
    esac
    summary+="CLAUDE.md: $claude_md_target
"
fi

action_verb="merge"
if $OVERWRITE; then action_verb="overwrite"; fi
if $INIT_REPO; then action_verb="initialize"; fi

if $DRY_RUN; then
    echo "$summary"
    if layer_enabled sub-agents; then
        install_sub_agents "$TARGET_DIR"
    fi
    if settings_layers_enabled; then
        echo "# Would write to: $OUTPUT"
        echo "$final"
    fi
    if $INIT_REPO; then
        echo "# Would copy CLAUDE.md to $claude_md_target"
    fi
else
    echo "$summary"
    if ! $SKIP_CONFIRM; then
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
fi
