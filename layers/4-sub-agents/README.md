# Sub-agents

Agent definitions are copied to `.claude/agents/` in the target project.

Unlike hooks and permissions (which merge into `settings.json`), each sub-agent
is a standalone JSON file. The build script copies them as-is.

Add new agents by creating a JSON file in this directory with:
- `name` - agent identifier
- `description` - what the agent does (also used for auto-delegation)
- `prompt` - system prompt for the agent
- `tools` - allowed tools list
- `permissions` - allow/deny rules scoped to this agent
