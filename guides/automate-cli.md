> Part of the [cc-cli-skill](../SKILL.md) skill.

# Automate with Claude CLI Print Mode

## Goal

Use `claude -p` to integrate Claude into scripts, CI/CD pipelines, and automated workflows.
Print mode makes Claude non-interactive: it reads input, produces output, and exits.
This is the primary interface for machine-to-machine usage of Claude Code,
enabling you to embed Claude as a step in any automated pipeline
without requiring human interaction or a terminal session.

## Prerequisites

- **Claude Code CLI installed:**
  ```bash
  npm install -g @anthropic-ai/claude-code
  ```
- **Authenticated** (API key or OAuth configured):
  ```bash
  claude auth status
  # Should show: Authenticated
  ```
- **Verify print mode works:**
  ```bash
  echo "Hello" | claude -p --output-format json
  ```
  You should receive a JSON object containing a `result` field with Claude's response.

## Basic Invocations

```bash
# Direct prompt
claude -p "What is 2+2?"

# Piped input
cat README.md | claude -p "Summarize this"

# File as context
claude -p "Review this code" < src/main.py

# Multi-line prompt with heredoc
claude -p <<'EOF'
Review this function for bugs:
function add(a, b) { return a + b; }
EOF
```

Key behaviors in print mode:
- Claude reads stdin if available and appends it to the prompt.
- Output goes to stdout; progress/errors go to stderr.
- Exit code is 0 on success, non-zero on failure.
- No interactive confirmation prompts are shown.

## Output Formats

### Text (default)

Raw text output, best for simple piping and human-readable results:

```bash
claude -p "Generate a commit message for these changes" < <(git diff --staged)
```

### JSON

Structured output with metadata. Parse with `jq`:

```bash
result=$(claude -p "Analyze this" --output-format json < data.csv)
echo "$result" | jq -r '.result'           # text response
echo "$result" | jq '.total_cost_usd'      # cost tracking
echo "$result" | jq -r '.session_id'       # for session continuation
```

The JSON envelope includes `result`, `session_id`, `total_cost_usd`, `model`, and other metadata fields useful for logging and orchestration.

### Stream-JSON

Real-time NDJSON events for streaming processing (requires `--verbose`):

```bash
claude -p "Explain this codebase" \
  --output-format stream-json \
  --verbose \
  --include-partial-messages | \
  while read -r line; do
    text=$(echo "$line" | jq -r 'select(.type=="assistant") | .message.content // empty')
    [ -n "$text" ] && echo -n "$text"
  done
```

Each line is a self-contained JSON object. Event types include `assistant`, `tool_use`, `tool_result`, and `system`. Use stream-json when you need to display progress or process output incrementally.

## Structured Output with JSON Schema

Force Claude to produce validated structured data by providing a JSON schema:

```bash
# Extract entities
claude -p "Extract all person names and emails from this text" \
  --output-format json \
  --json-schema '{
    "type": "object",
    "properties": {
      "contacts": {
        "type": "array",
        "items": {
          "type": "object",
          "properties": {
            "name": {"type": "string"},
            "email": {"type": "string"}
          },
          "required": ["name", "email"]
        }
      }
    },
    "required": ["contacts"]
  }' < email.txt | jq '.structured_output'
```

**Important:** `structured_output` is a SEPARATE field from `result`. The free-text response still appears in `result`, while the schema-validated data is in `structured_output`. Always read `structured_output` when using `--json-schema`.

## Tool Control Patterns

Control which tools Claude can use during automation:

```bash
# Read-only analysis (no file modifications)
claude -p "Analyze this codebase" \
  --tools "Bash,Read,Glob,Grep" \
  --dangerously-skip-permissions

# Full agentic mode (read, write, execute)
claude -p "Fix the failing tests in src/" \
  --tools "Bash,Read,Write,Edit,Glob,Grep" \
  --dangerously-skip-permissions

# No tools at all (pure LLM, no file access)
claude -p "Explain the concept of dependency injection" \
  --tools ""

# Auto-approve specific patterns
claude -p "Run the test suite" \
  --allowedTools "Bash(npm test:*)" \
  --allowedTools "Read"

# Deny specific tools
claude -p "Review this code" \
  --disallowedTools "Write,Edit,Bash"
```

**Tool allowlist pattern syntax:**
- `"Bash"` -- allow all bash commands
- `"Bash(npm test:*)"` -- allow only bash commands matching the pattern
- `"Read"` -- allow file reading
- Prefix matching: `"Bash(npm*)"` matches `npm test`, `npm run`, etc.

Use `--dangerously-skip-permissions` only in trusted environments (CI/CD, containers). It bypasses all tool permission prompts.

## Session Management

```bash
# Stateless (recommended for automation) -- no disk storage
claude -p "Analyze this" --no-session-persistence < data.txt

# Named session for multi-turn workflows
SESSION=$(claude -p "Start analyzing this project" --output-format json | jq -r '.session_id')
echo "Now check for security issues" | claude -p --resume "$SESSION" --output-format json

# Continue most recent session
claude -p --continue "What was I saying?"

# Fork session (branch from existing without modifying it)
claude -p --resume "$SESSION" --fork-session "Try a different approach"
```

**Best practices:**
- Use `--no-session-persistence` for CI/CD and one-shot tasks. This avoids writing session data to disk and keeps runs hermetic.
- Use `--session-id` or `--resume` for multi-step workflows where context matters across invocations.
- Capture `session_id` from JSON output to resume later. Without it, you cannot return to a session.
- Forking lets you explore alternative paths without losing the original conversation.

## System Prompt Customization

```bash
# APPEND to default system prompt (recommended -- preserves Claude Code behaviors)
claude -p "Review this PR" \
  --append-system-prompt "You are a senior code reviewer. Focus on security and performance." \
  < <(git diff main...HEAD)

# REPLACE system prompt entirely (loses Claude Code defaults)
claude -p "What is 2+2?" \
  --system-prompt "You are a math tutor. Show your work step by step."

# From file
claude -p "Analyze this" \
  --append-system-prompt-file ./review-prompt.txt \
  < code.py
```

**Important:** `--system-prompt` REPLACES the entire default system prompt. You lose Claude Code's built-in tool instructions and behaviors. Use `--append-system-prompt` to ADD your instructions while keeping the defaults intact. This distinction matters when you need Claude to use tools like Bash, Read, or Edit.

## Budget and Safety

```bash
# Cost cap (stops if exceeded)
claude -p "Analyze this large codebase" \
  --max-budget-usd 1.00 \
  --output-format json

# Turn limit
claude -p "Fix bugs iteratively" \
  --max-turns 5

# Model fallback (if primary is overloaded)
claude -p "Quick analysis" \
  --model opus \
  --fallback-model sonnet

# Combine for production safety
claude -p "Deploy review" \
  --model sonnet \
  --fallback-model haiku \
  --max-budget-usd 0.50 \
  --max-turns 3 \
  --no-session-persistence
```

Always set `--max-budget-usd` in automated pipelines to prevent runaway costs. Pair it with `--max-turns` to bound execution time. The `--fallback-model` flag provides resilience when your primary model is rate-limited or unavailable.

## CI/CD Integration Patterns

### GitHub Actions

```yaml
name: Claude Code Review
on: pull_request
jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - run: npm install -g @anthropic-ai/claude-code
      - run: |
          git diff origin/main...HEAD | claude -p \
            --append-system-prompt "Review this diff for bugs and security issues. Output as markdown." \
            --model sonnet \
            --max-budget-usd 0.50 \
            --no-session-persistence \
            --tools "" \
            > review.md
      - uses: actions/upload-artifact@v4
        with:
          name: code-review
          path: review.md
```

### Pre-commit Hook

```bash
#!/bin/bash
# .git/hooks/pre-commit
staged=$(git diff --cached --name-only)
if [ -n "$staged" ]; then
  git diff --cached | claude -p \
    --append-system-prompt "Check for obvious bugs, security issues, or leaked secrets. Reply OK if clean, or describe issues found." \
    --model haiku \
    --max-budget-usd 0.05 \
    --no-session-persistence \
    --tools ""
fi
```

Set `--tools ""` in CI/CD to ensure Claude operates as a pure LLM without filesystem or command access, unless your workflow explicitly requires tool use.

## MCP Server Configuration

```bash
# Use specific MCP servers
claude -p "Query the database" \
  --mcp-config ./mcp-servers.json

# Strict mode -- only use specified MCP servers, ignore defaults
claude -p "Query the database" \
  --mcp-config ./mcp-servers.json \
  --strict-mcp-config
```

The `--mcp-config` flag points to a JSON file defining MCP server connections. Use `--strict-mcp-config` to prevent Claude from loading any MCP servers not listed in your config, giving you full control over available integrations.

## Troubleshooting

Common issues and solutions:

- **"stream-json requires --verbose"**: Add the `--verbose` flag when using `--output-format stream-json`.
- **Authentication error**: Run `claude auth login` or verify with `claude auth status`.
- **Timeout**: Set the `CLAUDE_CLI_TIMEOUT=30m` environment variable for long-running tasks.
- **Rate limiting**: Use `--fallback-model` to switch models automatically, or add delays between calls in batch scripts.
- **Empty output with stream-json**: Ensure `--verbose` is set. Without it, stream-json produces no output.
- **Tools not working**: Check that your `--tools` flag is not restricting the tools Claude needs. Use `--tools ""` only when you want pure LLM mode.
- **Session not found**: The session may have been ephemeral or cleaned up. Use `--no-session-persistence` for stateless workflows to avoid depending on session storage.
- **JSON parse errors**: Ensure you are reading the correct field (`result` for text, `structured_output` for schema-validated data).
