# Tests

Run with `make test` or `./tests/run-tests.sh`.

## Test files

| File | Tests | What it covers |
|---|---|---|
| `cli.sh` | 24 | `make help`, `make help-advanced`, profile-first help text, replace summary, dry-run, error handling, target resolution |
| `layers.sh` | 10 | Building all layers, hooks-only, permissions-only, combined |
| `merge.sh` | 9 | Preserves existing settings (model, plugins), idempotent merges |
| `hooks.sh` | 9 | Hook consolidation by matcher, correct count, specific hooks present |
| `hook-behavior.sh` | 68 | Every hook fragment block/allow tested with real tool input JSON |
| `probe.sh` | 18 | Generic probing for default build, fragments, and full profiles across hooks, permissions, and sub-agent fragments |
| `probe-workflow.sh` | 8 | User-facing `make probe` workflows for default build, profile, fragment debugging, and denial-source summaries |
| `sub-agents.sh` | 18 | Agent file copy, remove, dry-run, combined with other layers |
| `overwrite.sh` | 19 | Merge vs overwrite, settings preservation, confirmation prompts |
| `remove.sh` | 9 | Remove hooks, permissions, both, preserves unrelated settings |
| `profiles.sh` | 40 | All 5 profiles build correctly, default-profile inheritance, agent selection, stale agent cleanup |
| `show.sh` | 17 | Profile effective-fragment output, filtered profile fragment JSON, inherited defaults, single fragment, directory match, partial match, typo alias support, and usage errors |
| `repo.sh` | 8 | CLAUDE.md copy, profile support, existing file preservation, dry-run |

## How it works

- `helpers.sh` provides shared utilities (`pass`, `fail`, `assert_*`, `build_to`)
- `run-tests.sh` runs each test file, aggregates pass/fail counts
- `$MAKE` is set to `make -C $REPO_ROOT --no-print-directory yes=1` so tests skip confirmation prompts
- Each test file creates temp dirs in `$TEST_TMPDIR` (cleaned up on exit)

## Running specific tests

```bash
./tests/run-tests.sh cli              # one file
./tests/run-tests.sh hooks merge      # multiple files
./tests/run-tests.sh hook-behavior    # all 68 hook block/allow tests
./tests/run-tests.sh probe-workflow   # human-readable probe workflow checks
```

## Adding tests

1. Create a new file in `tests/` following the pattern:
   ```bash
   #!/usr/bin/env bash
   source "$(dirname "$0")/helpers.sh"
   echo "=== My Tests ==="
   # your tests here
   print_results
   ```
2. Add the filename (without `.sh`) to `TEST_FILES` in `run-tests.sh`
3. Use `$MAKE` for commands that need `yes=1`, or `NOMAKE` for testing prompts directly
