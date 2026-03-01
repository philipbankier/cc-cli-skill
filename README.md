# cc-cli

AI agent skill for Claude CLI print mode (`claude -p`) and CC-Bridge API wrapper.

## What This Skill Does

Teaches AI agents (Claude Code, OpenClaw, or any agent supporting standardized skills) how to:

- **Automate with CLI** — Use `claude -p` for scripting, CI/CD, and batch processing
- **Build API bridges** — Wrap `claude -p` as an Anthropic-compatible HTTP endpoint
- **Integrate SDKs** — Point existing Anthropic Python/JS SDKs at a local bridge

## Structure

```
cc-cli/
├── SKILL.md                  # Entry point — overview, decision routing, quick recipes
├── guides/
│   ├── automate-cli.md       # CLI automation, CI/CD, scripting
│   ├── build-bridge.md       # CC-Bridge architecture & implementation
│   └── integrate-sdk.md      # Python/JS SDK integration
├── reference/
│   ├── print-mode-flags.md   # Complete flag reference (31 tested combinations)
│   ├── streaming-events.md   # SSE events, NDJSON, stream consumers
│   ├── json-schemas.md       # Output shapes, error formats, usage tracking
│   └── code-snippets.md      # Bash, Python, JS, Go, CI/CD patterns
└── autopilot-adapter.md      # autopilot-hq triggers/dependencies adapter
```

## Quick Start

```bash
# Simple CLI automation
claude -p "Summarize this code" < main.py

# JSON output for parsing
claude -p "Analyze this" --output-format json < data.csv | jq '.result'

# Real-time streaming
claude -p "Explain this" --output-format stream-json --verbose --include-partial-messages

# Point Python SDK at a CC-Bridge
import anthropic
client = anthropic.Anthropic(api_key="dummy", base_url="http://localhost:8321")
```

## Sources

- [CC-Bridge](https://github.com/ranaroussi/cc-bridge) by Ran Aroussi — Go server wrapping `claude -p`
- [Print Mode State Machine](https://gist.github.com/danialhasan/abbf1d7e721475717e5d07cee3244509) by Danial Hasan — Comprehensive CLI flag testing
- Original idea by [@dhasandev](https://x.com/dhasandev)

## Formats

- **Claude Code format** — `SKILL.md` with standard YAML frontmatter (`name`, `description`)
- **autopilot-hq format** — `autopilot-adapter.md` with triggers and dependencies
