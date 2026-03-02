# cc-cli-skill

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Claude Code Skill](https://img.shields.io/badge/Claude%20Code-skill-blue)](https://docs.anthropic.com/en/docs/claude-code)

**Teach your AI agent to automate Claude Code — from one-shot scripts to multi-agent orchestration.**

Claude Code's interactive TUI is great for humans, but agents and scripts need programmatic access. The `claude -p` print mode has 30+ flags with non-obvious interactions — `stream-json` silently fails without `--verbose`, `--system-prompt` replaces defaults instead of appending, and structured output lands in `.structured_output` not `.result`. This skill packages the flag matrix, the gotchas, and production-ready patterns so your agent doesn't have to discover them by trial and error.

## What is a "Skill"?

A **skill** is a structured knowledge package that AI agents load on demand. Think of it as documentation optimized for AI consumption — with a decision router, copy-paste recipes, and cross-linked references — though humans can read it too.

- Entry point: `SKILL.md` (YAML frontmatter with `name` and `description`)
- Agents load the skill when they encounter relevant tasks (CLI automation, API bridges, etc.)
- The skill's decision router directs agents to the right guide for each situation

Works with Claude Code, Cursor, and any agent framework that supports custom skills.

## Why cc-cli-skill?

1. **`claude -p` is underdocumented** — 30+ flags with non-obvious interactions. This skill maps the flag matrix with 31 tested combinations so your agent gets it right the first time.

2. **No native HTTP API for Claude Code** — [CC-Bridge](https://github.com/ranaroussi/cc-bridge) turns `claude -p` into an Anthropic-compatible REST endpoint, but setup patterns are scattered. This skill consolidates them.

3. **Agents need recipes, not man pages** — LLMs work better with decision routers and copy-paste patterns than with exhaustive reference docs. This skill is structured for agent consumption.

## The Three Pillars

| Pillar | What it does | Guide |
|--------|-------------|-------|
| **CLI Automation** | Use `claude -p` for scripting, CI/CD, batch processing | [`guides/automate-cli.md`](guides/automate-cli.md) |
| **CC-Bridge** | Wrap `claude -p` as an Anthropic-compatible HTTP API | [`guides/build-bridge.md`](guides/build-bridge.md) |
| **SDK Integration** | Point Anthropic Python/JS/Go SDKs at a local bridge | [`guides/integrate-sdk.md`](guides/integrate-sdk.md) |

## What You Can Build — Just Ask

Once the skill is installed, you use it by talking to Claude Code (or your agent) in plain English. The agent loads the skill, routes to the right guide, and builds what you describe. No need to read flag documentation yourself.

**"Build me a chatbot that uses my Claude Max subscription as the LLM backend"**
→ The agent sets up a CC-Bridge server on localhost and wires up a chat interface using the Anthropic Python SDK pointing at it. Your existing $20/month Claude subscription powers the app — no extra API costs.

**"Summarize every markdown file in this repo and save the results to a JSON file"**
→ The agent writes a shell script that pipes each file through `claude -p` with structured JSON output and aggregates the results — runs in seconds.

**"Add an AI code review step to our GitHub Actions pipeline"**
→ The agent writes a workflow that calls `claude -p` on each PR diff, outputs structured findings as JSON, and posts them as PR comments.

**"Build a tool that gets multiple AI perspectives on any topic and synthesizes them"**
→ The agent writes a parallel orchestration script — 5 debaters running simultaneously, each with their own persona, synthesized by a moderator. (See the included [debate engine example](examples/debate-engine/WALKTHROUGH.md).)

**"I have a Python app using the Anthropic SDK — make it work with my local Claude Code auth instead of an API key"**
→ The agent sets up CC-Bridge and changes one line in your existing code: `base_url="http://localhost:8321"`. Everything else stays the same.

## Under the Hood

What the agent generates and uses — raw `claude -p` patterns for reference:

```bash
# One-shot CLI call
claude -p "Summarize this code" < main.py

# Structured JSON output with schema validation
claude -p "Extract function names" \
  --output-format json \
  --json-schema '{"type":"object","properties":{"functions":{"type":"array","items":{"type":"string"}}},"required":["functions"]}' \
  < main.py | jq '.structured_output'

# Real-time streaming
claude -p "Explain this" \
  --output-format stream-json \
  --verbose \
  --include-partial-messages

# Python SDK via CC-Bridge (zero code changes from direct API usage)
import anthropic
client = anthropic.Anthropic(api_key="dummy", base_url="http://localhost:8321")
msg = client.messages.create(
    model="sonnet", max_tokens=1024,
    messages=[{"role": "user", "content": "Hello!"}]
)
```

## Flagship Example: Multi-Perspective Debate Engine

The debate engine spawns 5 AI "debaters" in parallel — Optimist, Skeptic, Historian, Futurist, and Practitioner — each with their own persona and JSON schema. A Moderator then synthesizes the arguments into a balanced analysis. Available in both Bash (zero dependencies beyond `jq`) and Python (via CC-Bridge SDK).

```bash
# Structured JSON output
./examples/debate-engine/debate.sh "Should AI replace teachers?"

# Streaming moderator synthesis
./examples/debate-engine/debate.sh --stream "Should AI replace teachers?"
```

**Sample verdict** (from `examples/debate-engine/sample-output/ai-teachers.json`):

> AI should not replace teachers but should be systematically integrated into education as a powerful tool that handles personalized practice, immediate feedback, and administrative tasks. Human teachers should be repositioned as learning architects, mentors, and community builders — roles that become more important, not less, in an AI-augmented world.

**Techniques demonstrated:**
- Parallel agent execution with `&` + `wait`
- Structured output via `--json-schema`
- Streaming with NDJSON parsing
- System prompts for agent personas (`--append-system-prompt`)
- Cost tracking across all calls

See the full annotated walkthrough: [`examples/debate-engine/WALKTHROUGH.md`](examples/debate-engine/WALKTHROUGH.md)

## Installation

**Prerequisites:**
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code): `npm install -g @anthropic-ai/claude-code`
- Authenticated: `claude auth status` should show authenticated
- For Bash examples: [`jq`](https://jqlang.github.io/jq/) (JSON processor)
- For Python examples: `pip install anthropic`
- For CC-Bridge: Go 1.21+ and the compiled `ccbridge` binary (see [`guides/build-bridge.md`](guides/build-bridge.md))

**Option 1: Add as a Claude Code skill (recommended)**

```bash
# Add to your project's skill directory
git clone https://github.com/philipbankier/cc-cli-skill.git .claude/skills/cc-cli-skill
```

Your agent will automatically discover and use the skill when it encounters relevant tasks.

**Option 2: Clone standalone**

```bash
git clone https://github.com/philipbankier/cc-cli-skill.git
```

## Project Structure

```
cc-cli-skill/
├── SKILL.md                          # Entry point — decision routing, quick recipes
├── guides/
│   ├── automate-cli.md               # CLI automation, CI/CD, scripting
│   ├── build-bridge.md               # CC-Bridge architecture & implementation
│   └── integrate-sdk.md              # Python/JS/Go SDK integration
├── reference/
│   ├── print-mode-flags.md           # Complete flag reference (31 tested combinations)
│   ├── streaming-events.md           # SSE events, NDJSON, stream consumers
│   ├── json-schemas.md               # Output shapes, error formats, usage tracking
│   └── code-snippets.md              # Bash, Python, JS, Go, CI/CD patterns
├── examples/
│   └── debate-engine/
│       ├── debate.sh                 # Bash version (zero dependencies beyond jq)
│       ├── debate.py                 # Python version (CC-Bridge + Anthropic SDK)
│       ├── WALKTHROUGH.md            # Annotated deep-dive
│       └── sample-output/
│           └── ai-teachers.json      # Full sample output
├── autopilot-adapter.md              # autopilot-hq triggers & dependencies
├── CONTRIBUTING.md
├── LICENSE
└── .gitignore
```

## Contributing

Contributions welcome! See [`CONTRIBUTING.md`](CONTRIBUTING.md) for guidelines.

Most valuable contributions: new multi-agent examples, flag documentation updates as Claude CLI evolves, and code snippets in additional languages.

## Disclaimer

> **This is an independent community project and is not affiliated with, endorsed by, or approved by Anthropic.** Use at your own risk.

A few things to be aware of:

- **Terms of Service** — Using `claude -p` for automation and CC-Bridge for local API serving may be subject to Anthropic's [Usage Policy](https://www.anthropic.com/legal/aup) and [Claude Code terms](https://www.anthropic.com/legal/claude-code-terms). Review these before deploying in production or commercial contexts.

- **CC-Bridge specifically** — The bridge proxies Claude Code's CLI authentication to serve API requests from other apps. This is a community pattern, not an officially supported Anthropic integration. Anthropic may change the CLI interface or auth model at any time.

- **`unset CLAUDECODE`** — The nested-call workaround bypasses a guard Anthropic intentionally put in place. Use it only in sandboxed, controlled environments.

- **No stability guarantees** — The `claude -p` CLI interface is undocumented and can change between Claude Code versions without notice.

## Sources & Credits

- [CC-Bridge](https://github.com/ranaroussi/cc-bridge) by Ran Aroussi — Go server wrapping `claude -p` as an Anthropic-compatible API
- [Print Mode State Machine](https://gist.github.com/danialhasan/abbf1d7e721475717e5d07cee3244509) by Danial Hasan — Comprehensive CLI flag testing
- Original idea by [@dhasandev](https://x.com/dhasandev)
- [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code) by Anthropic

## License

MIT — see [`LICENSE`](LICENSE).
