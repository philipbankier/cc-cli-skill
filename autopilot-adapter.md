---
name: cc-cli-skill
triggers:
  - keyword: claude -p
  - keyword: print mode
  - keyword: cc-bridge
  - keyword: bridge server
  - keyword: claude cli
  - keyword: headless
  - keyword: automation
  - keyword: api wrapper
  - keyword: programmatic claude
  - event_type: agent.cli_invocation
dependencies:
  - claude-code
---

# CC-CLI-Skill: Claude Code Print Mode & API Bridge

This skill teaches how to use `claude -p` (print mode) for programmatic automation and how to build API-compatible bridge servers using CC-Bridge.

## Quick Reference

| Task | Command / Pattern |
|------|-------------------|
| One-shot query | `claude -p "prompt"` |
| JSON output | `claude -p "prompt" --output-format json` |
| Stream tokens | `claude -p "prompt" --output-format stream-json --verbose --include-partial-messages` |
| Structured output | `claude -p "prompt" --output-format json --json-schema '{...}'` |
| Stateless mode | `claude -p "prompt" --no-session-persistence` |
| Full automation | `claude -p "prompt" --dangerously-skip-permissions --no-session-persistence --output-format json` |
| Point SDK at bridge | `Anthropic(api_key="dummy", base_url="http://localhost:8321")` |

## Key Flags

| Flag | Purpose |
|------|---------|
| `--output-format json` | Structured JSON response with metadata |
| `--output-format stream-json` | NDJSON event stream (requires `--verbose`) |
| `--no-session-persistence` | Stateless/ephemeral mode |
| `--dangerously-skip-permissions` | Skip all permission prompts |
| `--allowedTools` | Auto-approve specific tools |
| `--max-budget-usd` | Cost cap |
| `--json-schema` | Validated structured output |
| `--model` | Select model: haiku, sonnet, opus |
| `--append-system-prompt` | Add to system prompt (preserves defaults) |

## Critical Gotchas

1. `stream-json` output **requires** `--verbose` — without it, you get an error
2. `--system-prompt` **replaces** the default — use `--append-system-prompt` to add to it
3. Sampling params (temperature, top_p, max_tokens) are **not available** via CLI

## Full Skill

For comprehensive guides and reference, load the cc-cli-skill skill folder:

- **Entry point:** `cc-cli-skill/SKILL.md` — overview, decision routing, quick-start recipes
- **Guides:** `cc-cli-skill/guides/automate-cli.md`, `build-bridge.md`, `integrate-sdk.md`
- **Reference:** `cc-cli-skill/reference/print-mode-flags.md`, `streaming-events.md`, `json-schemas.md`, `code-snippets.md`
