---
name: cc-cli-skill
description: Build and manage projects using Claude CLI print mode (claude -p) and the CC-Bridge API wrapper. Use when building automation, CI/CD pipelines, API bridges, or programmatic Claude integrations.
---

# CC-CLI-Skill

## Overview

Claude Code ships with a **print mode** (`claude -p`) designed for non-interactive, programmatic use.
Instead of launching the interactive TUI, print mode accepts a prompt as an argument or via stdin,
processes it, writes the response to stdout, and exits. This makes it the foundation for scripting,
automation, CI/CD pipelines, and any workflow where a human is not sitting at the terminal.

Basic invocation:

```bash
claude -p "Your prompt here"
echo "Your prompt" | claude -p
claude -p "Summarize this file" < src/main.py
```

**CC-Bridge** is a lightweight Go HTTP server that wraps `claude -p` behind an
Anthropic-compatible REST API. It accepts standard `/v1/messages` requests on localhost,
translates them into `claude -p` invocations, and returns responses in the Anthropic SDK
response format. This lets you point any Anthropic SDK client (Python, TypeScript, Go) at
your local machine and get Claude Code capabilities through a familiar API interface.

**When to use this skill:**

- Calling Claude from shell scripts, Makefiles, or CI/CD pipelines
- Building HTTP API wrappers or bridge servers around the CLI
- Integrating with Anthropic SDKs by pointing `base_url` at a local bridge
- Batch processing files, repos, or datasets through Claude
- Embedding Claude in larger automation workflows

**Prerequisites:**

- Claude Code CLI installed: `npm install -g @anthropic-ai/claude-code`
- Authenticated: verify with `claude auth status`
- For CC-Bridge: Go 1.21+ and the compiled `ccbridge` binary

---

## Decision Router

### What are you trying to do?

### "I want to call Claude programmatically from scripts or CI/CD"
-> Read [guides/automate-cli.md](guides/automate-cli.md)
Key flags: `-p`, `--output-format`, `--allowedTools`, `--max-budget-usd`

### "I want to expose Claude as an HTTP API endpoint or build a bridge server"
-> Read [guides/build-bridge.md](guides/build-bridge.md)
Architecture: Go HTTP server wrapping `claude -p`, Anthropic-compatible `/v1/messages`

### "I want to use the Anthropic Python/TypeScript SDK with Claude Code"
-> Read [guides/integrate-sdk.md](guides/integrate-sdk.md)
Pattern: instantiate SDK client with `base_url` pointed at localhost bridge

### "What flags are available? What output formats exist? How does session management work?"
-> Read [reference/print-mode-flags.md](reference/print-mode-flags.md)
Complete flag matrix with 31+ tested combinations and their interactions

### "How does streaming work? What are the SSE event types?"
-> Read [reference/streaming-events.md](reference/streaming-events.md)
SSE event types, `stream-json` NDJSON format, partial message handling

### "What does the JSON output look like? How do I validate response schemas?"
-> Read [reference/json-schemas.md](reference/json-schemas.md)
Output format shapes for `text`, `json`, and `stream-json` modes, plus `--json-schema` usage

### "Give me copy-paste code examples in Python, Bash, Go, or JavaScript"
-> Read [reference/code-snippets.md](reference/code-snippets.md)
Ready-to-run patterns for every common integration scenario

---

## Quick Start Recipes

These four recipes cover roughly 80% of use cases. You should not need to load any
reference files for these patterns.

### Recipe 1: Simple CLI Automation

```bash
# One-shot query with plain text output
response=$(claude -p "Summarize this code" < main.py)
echo "$response"

# JSON output for programmatic parsing
result=$(claude -p "What language is this file written in?" \
  --output-format json \
  < main.py)
echo "$result" | jq -r '.result'

# Pipe content through Claude in a shell pipeline
cat error.log | claude -p "Extract the root cause of this error"

# Process multiple files in a loop
for f in src/*.py; do
  claude -p "List all function names in this file" \
    --output-format json \
    --no-session-persistence \
    < "$f" | jq -r '.result'
done
```

### Recipe 2: Structured Output with JSON Schema

```bash
# Extract structured data using --json-schema
claude -p "Extract the function names from this code" \
  --output-format json \
  --json-schema '{
    "type": "object",
    "properties": {
      "functions": {
        "type": "array",
        "items": { "type": "string" }
      }
    },
    "required": ["functions"]
  }' \
  < main.py | jq '.structured_output'

# The structured data lives in .structured_output, not .result
# .result still contains the free-text response
```

### Recipe 3: Real-Time Streaming

```bash
# Stream responses as NDJSON events (verbose flag is REQUIRED)
claude -p "Explain this codebase" \
  --output-format stream-json \
  --verbose \
  --include-partial-messages | \
  while read -r line; do
    text=$(echo "$line" | jq -r 'select(.type=="assistant") | .message.content // empty')
    [ -n "$text" ] && echo -n "$text"
  done

# Simpler: stream text tokens only
claude -p "Write a haiku about code" \
  --output-format stream-json \
  --verbose \
  --include-partial-messages | \
  jq --unbuffered -r 'select(.type=="assistant") | .message.content // empty'
```

### Recipe 4: CC-Bridge + Python SDK

```bash
# Terminal 1: Start the bridge server
./ccbridge --port 8321

# Terminal 2: Use the standard Anthropic Python SDK
python3 -c "
import anthropic

client = anthropic.Anthropic(
    api_key='dummy',
    base_url='http://localhost:8321'
)

msg = client.messages.create(
    model='sonnet',
    max_tokens=1024,
    messages=[{'role': 'user', 'content': 'Hello from the SDK!'}]
)
print(msg.content[0].text)
"
```

The bridge translates the SDK request into a `claude -p` call behind the scenes.
The `api_key` can be any non-empty string since auth is handled by your local CLI session.

---

## Core Concepts

### Print Mode vs Interactive Mode

The `-p` (or `--print`) flag switches Claude Code from its interactive TUI into a
non-interactive pipeline mode. In print mode:

- Input comes from the argument string and/or stdin
- Output goes to stdout (format controlled by `--output-format`)
- The process exits after producing a response (no REPL loop)
- No user confirmation prompts appear (tools require explicit permission flags)

This is the single most important flag for automation.

### Output Format Spectrum

Three output formats, each building on the last:

| Format | Flag | Shape | Use When |
|---|---|---|---|
| `text` | `--output-format text` (default) | Raw text string | Simple scripts, human-readable output |
| `json` | `--output-format json` | JSON object with `.result`, `.cost_usd`, `.session_id`, etc. | Parsing metadata, structured workflows |
| `stream-json` | `--output-format stream-json` | NDJSON (one JSON object per line) | Real-time streaming, progress tracking |

### Session Management

By default, `claude -p` persists sessions to disk. For automation:

- **Stateless** (recommended for scripts): `--no-session-persistence` discards the session after exit
- **Multi-turn**: `--session-id <id>` resumes a named session across invocations
- **Continue last**: `--continue` picks up the most recent session

### Permission Modes

Print mode needs explicit permission configuration since there is no human to click "Allow":

- `--dangerously-skip-permissions` — allows all tool use without confirmation (sandboxed environments only)
- `--permission-mode plan` — allows read operations, prompts for writes
- `--allowedTools "tool1,tool2"` — whitelist specific tools by name

### The Bridge Pattern

The full request flow when using CC-Bridge:

```
Your App (SDK client)
  -> HTTP POST /v1/messages
    -> CC-Bridge (Go server on localhost)
      -> spawns: claude -p "..." --output-format json
        -> Anthropic API (remote)
        <- response
      <- stdout captured
    <- HTTP JSON response (Anthropic format)
  <- SDK message object
```

This lets any Anthropic SDK client work with Claude Code without modification.

---

## Critical Gotchas

Things that will bite you if you do not know about them:

1. **`stream-json` requires `--verbose`** — Without the `--verbose` flag, `stream-json` output
   will error or produce no events. Always pair them together.

2. **`--include-partial-messages` for token-level streaming** — Without this flag, you only
   get complete messages. Add it when you need incremental text delivery.

3. **`--no-session-persistence` for stateless automation** — Without this, every `claude -p`
   call writes a session file to disk. In CI or batch processing, sessions accumulate and
   waste disk space. Always include this flag for fire-and-forget invocations.

4. **`--system-prompt` replaces the default** — This flag fully overrides Claude's built-in
   system prompt. If you want to add instructions without losing defaults, use
   `--append-system-prompt` instead.

5. **`--dangerously-skip-permissions` has real security implications** — It allows Claude to
   execute arbitrary tool calls (file writes, shell commands) without confirmation. Only use
   in sandboxed or controlled environments where you trust the prompt source.

6. **Model name aliases work** — You can pass short names like `sonnet`, `opus`, or `haiku`
   instead of full model identifiers like `claude-sonnet-4-20250514`.

7. **No sampling parameter control via CLI** — Temperature, top_p, top_k, and max_tokens for
   the model response are not configurable through CLI flags. Claude uses its defaults.
   The `--max-budget-usd` flag controls spend, not generation length.

8. **`--json-schema` creates a separate field** — When you use `--json-schema`, the validated
   structured data appears in `.structured_output` in the JSON response. The `.result` field
   still contains the free-text response. Check both fields.

---

## File Map

Load these files only when the decision router points you to them:

| File | Description | Load When |
|---|---|---|
| `guides/automate-cli.md` | End-to-end guide for CLI automation and scripting | Building shell scripts, CI/CD pipelines, batch jobs |
| `guides/build-bridge.md` | Architecture and setup guide for CC-Bridge server | Exposing Claude as an HTTP API endpoint |
| `guides/integrate-sdk.md` | SDK integration patterns (Python, TypeScript, Go) | Connecting Anthropic SDKs to local bridge |
| `reference/print-mode-flags.md` | Complete flag reference with 31+ tested combinations | Need to know exact flag syntax or interactions |
| `reference/streaming-events.md` | SSE and stream-json event type documentation | Implementing real-time streaming consumers |
| `reference/json-schemas.md` | JSON output shapes and schema validation patterns | Parsing responses or defining structured output |
| `reference/code-snippets.md` | Copy-paste code examples in Bash, Python, Go, JS | Need a working starting point in a specific language |
