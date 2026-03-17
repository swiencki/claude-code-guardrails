# Guardrails

## File Protection
- Never modify files under `infrastructure/` without explicit confirmation
- Never edit `.env`, `credentials.json`, or any file containing secrets
- Do not delete any files without asking first

## Code Quality
- Always run `make test` before suggesting a commit
- Use the project's existing patterns - do not introduce new frameworks or libraries
- Keep changes minimal - only modify what was requested

## Git Safety
- Never force push to any branch
- Never amend published commits
- Always create new commits rather than amending existing ones
- Do not push to remote unless explicitly asked

## Security
- Never hardcode API keys, tokens, or passwords
- Never log sensitive data (passwords, tokens, PII)
- Always validate user input at system boundaries
