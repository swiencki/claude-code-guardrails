# Claude Code Guardrails

Composable guardrails for Claude Code.

This repo gives you a practical way to:

- install a ready-made profile such as `go-dev` or `infra-dev`
- merge hooks, permissions, and sub-agents into Claude settings
- probe "would this be allowed?" before you rely on a rule
- extend the system with your own fragments

If you only read one section, read [Quick start](#quick-start).

## Quick start

Prerequisites:

- [Claude Code](https://claude.com/claude-code)
- `jq`
- `make`
- `shellcheck` if you want to run the full test suite locally

```bash
# See available profiles
make profiles

# Preview a profile
make build profile=go-dev dry=1

# Install a profile to user-level settings (~/.claude/settings.json)
make build profile=go-dev

# Or install to one repo and copy the CLAUDE.md template
make repo profile=infra-dev target=~/my-project
```

## Common workflows

### Install guardrails for all projects

```bash
make build profile=go-dev
```

This writes to `~/.claude/settings.json`.

### Install guardrails for one repo

```bash
make build profile=infra-dev target=~/my-project
```

Or, if you also want a starter `CLAUDE.md` in that repo:

```bash
make repo profile=infra-dev target=~/my-project
```

### Preview before writing

```bash
make build profile=go-dev dry=1
```

### Replace instead of merge

By default, builds merge with existing settings.

```bash
make build profile=go-dev overwrite=1
```

### Remove installed layers

```bash
make remove layers=hooks
make remove layers=permissions
make remove layers=hooks,permissions
```

## Probe guardrails before you trust them

Use `make probe` to answer "would this be allowed?" with a readable explanation.

### Probe the default merged build

This matches the same default scope as `make build`.

```bash
make probe tool=Bash command='git push --force origin main'
```

### Probe a specific profile

```bash
make probe profile=infra-dev tool=Bash command='git push --force origin main'
```

### Probe one fragment for debugging

```bash
make probe fragment=git/safety.json tool=Bash command='git push --force origin main'
```

Typical output:

```text
Target: 2-hooks/git/safety.json
Description: Blocks destructive git operations: force push, hard reset, clean, checkout ., restore .
Tool: Bash
Input: {"command":"git push --force origin main"}

Decision: DENY

Hook checks (2 matched):
  1. BLOCKED: Checking for git force push
  2. PASSED: Checking for destructive git commands
  Overall hook outcome: DENY

Permissions:
  - No matching permission rules.
```

Use:

- no selector for "what would my default build do?"
- `profile=` for normal workflow checks
- `fragment=` for rule debugging

## Choose a profile

Profiles are curated bundles of fragments for common workflows.

| Profile | Best for | Includes |
|---|---|---|
| `go-dev` | Go app and backend development | git safety, security hooks, package publish protection, standard dev permissions, reviewer/explorer agents |
| `python-dev` | Python development | git safety, security hooks, standard dev permissions, reviewer/docs-reviewer agents |
| `infra-dev` | Terraform, Kubernetes, Azure/AWS, release work | git, cloud, CI/CD, security, kubernetes, terraform, standard dev permissions, readonly/release agents |
| `readonly-review` | Audits, review, repo exploration | minimal hooks, read-only permissions, reviewer/docs-reviewer/explorer agents |

See all profile names with:

```bash
make profiles
```

## Mental model

You usually only need four concepts:

- **Profiles**: the normal entrypoint; a profile picks a useful set of fragments
- **Hooks**: hard safety rules; great for catching dangerous patterns like `--force`
- **Permissions**: simple allow/deny/ask rules; great for routine command policy
- **Sub-agents**: scoped agent definitions copied into `.claude/agents/`

There is also a `CLAUDE.md` template layer for soft guidance, but the day-to-day workflow is mostly profile -> build -> probe.

## Hooks vs permissions

Use **hooks** when the rule must be hard to bypass.

Examples:

- block `git push --force`
- block `az deployment ... --mode Complete`
- block `terraform destroy`

Use **permissions** when the rule is simple and predictable.

Examples:

- auto-allow `git status`
- auto-allow `git diff`
- ask before a specific tool or command family

In practice, strong setups use both:

- permissions for smooth, low-friction defaults
- hooks for the dangerous edge cases

## Extend the guardrails

### Add a hook

Create a JSON file under `layers/2-hooks/`.

Hook commands receive tool input as JSON on stdin. For Bash hooks, read `.tool_input.command`:

```json
{
  "description": "Block dangerous pattern",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "jq -e '.tool_input.command // \"\" | test(\"dangerous-pattern\") | not' >/dev/null",
            "statusMessage": "Checking for dangerous pattern"
          }
        ]
      }
    ]
  }
}
```

Then run:

```bash
make test
make probe fragment=path/to/your.json tool=Bash command='some command'
```

### Add a permission preset

Create a JSON file under `layers/3-permissions/` with `permissions.allow` and `permissions.deny`.

### Add a sub-agent

Create a JSON file under `layers/4-sub-agents/` with:

- `name`
- `description`
- `prompt`
- `tools`
- `permissions`

### Add project guidance

Copy `layers/1-claude-md/CLAUDE.md` into your repo and customize it.

## Repository layout

```text
profiles/              curated workflow bundles
layers/1-claude-md/    CLAUDE.md templates
layers/2-hooks/        hook fragments
layers/3-permissions/  permission fragments
layers/4-sub-agents/   sub-agent definitions
scripts/               build + probe helpers
tests/                 shell test suite
Makefile               main user entrypoint
```

## Testing

```bash
make test
./tests/run-tests.sh probe
./tests/run-tests.sh probe-workflow
./tests/run-tests.sh hook-behavior
```

See [tests/README.md](tests/README.md) for the full test inventory.

## Contributing

The happy path for changes is:

1. edit fragments or scripts
2. run `make test`
3. use `make probe` to sanity-check behavior
4. send the PR

## License

MIT
