# Sub-agents

Sub-agent definitions are standalone JSON files, not merged into `settings.json`.
Copy individual files to your project's `.claude/` directory to use them.

Sub-agents cannot be installed via `make build` since they are separate config files, not settings.json fragments.
