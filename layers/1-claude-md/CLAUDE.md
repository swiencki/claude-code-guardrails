# Guardrails

## Git
- Never push to remote unless explicitly asked
- Never force push to any branch
- Never amend published commits
- Always create new commits rather than amending existing ones
- Ask before any destructive git operation (reset, clean, checkout .)

## Files
- Never modify infrastructure, deploy, or CI/CD pipeline files without confirmation
- Never edit or read files containing secrets (.env, credentials, keys, tokens)
- Do not delete files without asking first
- Keep changes minimal - only modify what was requested

## Code
- Use the project's existing patterns and conventions
- Do not introduce new frameworks, libraries, or abstractions unless asked
- Run tests before suggesting a commit
- Never hardcode API keys, tokens, or passwords
- Never log sensitive data (passwords, tokens, PII)
- Validate user input at system boundaries

## Communication
- Ask before taking actions that are hard to reverse
- When uncertain about scope, clarify before making changes
- State what you're about to do before doing it
