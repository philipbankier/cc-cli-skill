> Part of the [cc-cli-skill](../SKILL.md) skill.

# Print Mode Flag Reference & State Machine

Complete flag reference for Claude CLI `-p` (print/non-interactive) mode.
Consolidated from 31 tested flag combinations.

---

## 1. Flag Inventory

| Flag | Category | Default | Description |
|------|----------|---------|-------------|
| `-p, --print` | Core | - | Enable print (non-interactive) mode |
| `--output-format` | Output | `text` | Output format: `text`, `json`, `stream-json` |
| `--input-format` | Input | `text` | Input format: `text`, `stream-json` |
| `--verbose` | Output | `false` | Required for `stream-json` output |
| `--include-partial-messages` | Streaming | `false` | Emit token-level chunks in stream-json |
| `--replay-user-messages` | Streaming | `false` | Echo user input back in stream for tracking |
| `--model` | Model | `sonnet` | Model: `haiku`, `sonnet`, `opus` (or full ID) |
| `--fallback-model` | Model | - | Auto-fallback model on overload |
| `--max-budget-usd` | Budget | none | Spending limit in USD |
| `--max-turns` | Budget | none | Maximum conversation turns |
| `--session-id` | Session | auto | Use a specific session UUID |
| `--no-session-persistence` | Session | `false` | Ephemeral mode (no disk storage) |
| `--continue, -c` | Session | - | Resume the most recent conversation |
| `--resume, -r` | Session | - | Resume by session ID or name |
| `--fork-session` | Session | `false` | Branch from an existing session |
| `--permission-mode` | Permissions | `default` | Mode: `default`, `acceptEdits`, `dontAsk`, `bypassPermissions`, `delegate`, `plan` |
| `--dangerously-skip-permissions` | Permissions | `false` | Equivalent to `bypassPermissions` |
| `--allowedTools` | Tools | - | Pattern-based tool allowlist (repeatable) |
| `--disallowedTools` | Tools | - | Explicit tool denylist (repeatable) |
| `--tools` | Tools | all | Restrict available tools (comma-separated, or `""` for none) |
| `--strict-mcp-config` | Tools | `false` | Only use MCP servers specified in config |
| `--mcp-config` | Tools | - | MCP server configuration file path |
| `--system-prompt` | Prompt | - | REPLACE the default system prompt entirely |
| `--append-system-prompt` | Prompt | - | ADD to the default system prompt |
| `--system-prompt-file` | Prompt | - | Replace system prompt from file |
| `--append-system-prompt-file` | Prompt | - | Append system prompt from file |
| `--agent` | Persona | - | Select a named agent persona |
| `--agents` | Persona | - | Define custom agents inline (JSON) |
| `--json-schema` | Structured | - | JSON Schema for validated structured output |
| `--add-dir` | Context | - | Add additional directory to context |

---

## 2. Output Format Matrix

### `text` (default)

Raw text output with no metadata. Best for simple shell scripts and piping.

```bash
claude -p "Hello"
# Output: Hello! How can I help you today?
```

Characteristics:
- No JSON wrapping, no metadata
- Stderr may contain progress indicators (redirect with `2>/dev/null`)
- Exit code 0 on success, non-zero on error
- Output goes directly to stdout for piping

### `json`

Single JSON object containing the response and full metadata.

```bash
claude -p "Hello" --output-format json
```

Response fields:
- `type`: `"result"`
- `subtype`: `"success"` or `"error_max_budget_usd"`
- `is_error`: boolean
- `duration_ms`: total wall-clock time
- `duration_api_ms`: time spent in API calls
- `num_turns`: number of conversation turns
- `result`: the text response content
- `session_id`: UUID for session continuation
- `total_cost_usd`: cumulative cost tracking
- `usage`: `{ input_tokens, output_tokens, cache_creation_input_tokens, cache_read_input_tokens }`
- `modelUsage`: per-model token breakdown (keyed by model ID)
- `structured_output`: populated when `--json-schema` is used (parsed object, not string)

### `stream-json` (REQUIRES `--verbose`)

NDJSON (newline-delimited JSON) events, one object per line.

```bash
claude -p "Hello" --output-format stream-json --verbose
```

Event sequence:
1. `{"type":"system","subtype":"init",...}` -- session initialization with config
2. `{"type":"stream_event","event":{"type":"message_start",...}}` -- response begins
3. `{"type":"stream_event","event":{"type":"content_block_start",...}}` -- content block opens
4. `{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"..."}}}` -- text chunks
5. `{"type":"stream_event","event":{"type":"content_block_stop"}}` -- content block closes
6. `{"type":"stream_event","event":{"type":"message_stop"}}` -- message ends
7. `{"type":"assistant","message":{...}}` -- complete assembled message
8. `{"type":"result","subtype":"success",...}` -- final metrics (same fields as JSON format)

---

## 3. Flag Combinations -- The State Machine

31 tested combinations organized by category.

### Basic Output

#### Combination 1: Text Output (Default)
**Command:** `claude -p "What is 2+2?"`
**Output:** Plain text answer on stdout.
**Notes:** Simplest form. No metadata. Ideal for `$(...)` substitution and pipes.

#### Combination 2: JSON Output
**Command:** `claude -p "What is 2+2?" --output-format json`
**Output:** Single JSON object with `result`, `usage`, `session_id`, timing, and cost fields.
**Notes:** Parse with `jq`. The `result` field contains the text response. Cost tracking via `total_cost_usd`.

#### Combination 3: Stream-JSON Output
**Command:** `claude -p "What is 2+2?" --output-format stream-json --verbose`
**Output:** NDJSON event stream ending with a `result` event.
**Notes:** MUST include `--verbose` or output fails silently. Each line is independently parseable JSON.

### Streaming Controls

#### Combination 4: Verbose with Text Output
**Command:** `claude -p "What is 2+2?" --verbose`
**Output:** Text output plus additional metadata on stderr.
**Notes:** Adds system info and timing to stderr. Stdout remains plain text. Useful for debugging.

#### Combination 5: Partial Messages (Token-Level Streaming)
**Command:** `claude -p "What is 2+2?" --output-format stream-json --verbose --include-partial-messages`
**Output:** NDJSON with additional `content_block_delta` events for each token.
**Notes:** Higher event volume. Each delta contains a small text fragment. Needed for real-time UIs.

#### Combination 6: Replay User Messages
**Command:** `claude -p "What is 2+2?" --output-format stream-json --verbose --replay-user-messages`
**Output:** NDJSON with user message events echoed back in the stream.
**Notes:** Adds `{"type":"user",...}` events. Useful when you need to correlate request/response in logs.

#### Combination 7: Full Streaming (All Options)
**Command:** `claude -p "What is 2+2?" --output-format stream-json --verbose --include-partial-messages --replay-user-messages`
**Output:** Maximum-detail NDJSON stream with user echoes, token deltas, and full metadata.
**Notes:** Highest bandwidth. The "holy trinity" for full observability. Best for building rich streaming UIs.

### Session Management

#### Combination 8: Named Session
**Command:** `claude -p "Remember: the project is Alpha" --session-id "550e8400-e29b-41d4-a716-446655440000"`
**Output:** Normal response. Session persisted under the given UUID.
**Notes:** Must be a valid UUID format. Enables multi-turn conversations across separate invocations.

#### Combination 9: Ephemeral (No Persistence)
**Command:** `claude -p "What is 2+2?" --no-session-persistence`
**Output:** Normal response. No session written to disk.
**Notes:** No session ID returned in JSON output. Cannot be resumed. Good for stateless CI pipelines.

#### Combination 10: Continue Most Recent
**Command:** `claude -p "What was the project name?" --continue`
**Output:** Response with context from the most recent prior session.
**Notes:** Picks up the last session automatically. Fails if no prior sessions exist.

#### Combination 11: Resume Specific Session
**Command:** `claude -p "What was the project name?" --resume "550e8400-e29b-41d4-a716-446655440000"`
**Output:** Response with full context from the specified session.
**Notes:** Can use session ID (UUID) or session name. The session must exist on disk.

#### Combination 12: Fork Session
**Command:** `claude -p "Take a different approach" --session-id "550e8400-e29b-41d4-a716-446655440000" --fork-session`
**Output:** Response using context from the source session, saved to a new branched session.
**Notes:** Original session is untouched. New session branches from the source. Useful for exploring alternatives.

### Model Selection

#### Combination 13: Specific Model (Short Name)
**Command:** `claude -p "What is 2+2?" --model haiku`
**Output:** Response from the specified model.
**Notes:** Short names: `haiku`, `sonnet`, `opus`. Resolves to latest version of that model family.

#### Combination 14: Model with Fallback
**Command:** `claude -p "Analyze this codebase" --model opus --fallback-model sonnet`
**Output:** Response from opus, or sonnet if opus is overloaded/unavailable.
**Notes:** Fallback triggers on capacity errors, not on content errors. Transparent to caller.

#### Combination 15: Full Model ID
**Command:** `claude -p "What is 2+2?" --model claude-sonnet-4-20250514`
**Output:** Response from the exact model version specified.
**Notes:** Use for reproducibility. Full IDs pin to a specific model snapshot.

### Budget & Limits

#### Combination 16: Cost Cap
**Command:** `claude -p "Analyze this large file" --max-budget-usd 0.50`
**Output:** Normal response if within budget. Truncated with `subtype: "error_max_budget_usd"` if exceeded.
**Notes:** Check `total_cost_usd` in JSON output. Budget applies across all turns in a session invocation.

#### Combination 17: Turn Limit
**Command:** `claude -p "Refactor this module" --max-turns 3`
**Output:** Response limited to 3 agentic turns (tool uses count as turns).
**Notes:** Prevents runaway tool loops. After the limit, Claude returns its best answer so far.

### Permissions

#### Combination 18: Plan Mode
**Command:** `claude -p "How would you refactor auth.ts?" --permission-mode plan`
**Output:** Claude describes what it would do but does not execute any tools.
**Notes:** Read-only analysis. No file modifications, no Bash execution. Safe for review workflows.

#### Combination 19: Skip All Permissions
**Command:** `claude -p "Fix the linting errors" --dangerously-skip-permissions`
**Output:** Claude executes all tool calls without permission prompts.
**Notes:** Equivalent to `--permission-mode bypassPermissions`. Use only in trusted CI environments. Named "dangerously" for a reason.

#### Combination 20: Allowed Tools (Pattern-Based)
**Command:** `claude -p "Run the tests" --allowedTools "Bash(npm test:*)" --allowedTools "Read"`
**Output:** Claude can only use Bash for commands matching `npm test:*` and the Read tool.
**Notes:** Repeatable flag. Patterns use glob syntax for Bash commands. Other tools are denied by default when this flag is set.

### Tool Configuration

#### Combination 21: No Tools (Pure LLM)
**Command:** `claude -p "Explain recursion" --tools ""`
**Output:** Pure language model response. No file reads, no Bash, no tool calls.
**Notes:** Empty string disables ALL tools including MCP servers. Fastest response time. Use for pure Q&A.

#### Combination 22: Specific Tools Only
**Command:** `claude -p "Read and summarize main.ts" --tools "Bash,Read,Write"`
**Output:** Claude can only use the listed tools.
**Notes:** Comma-separated list. Tool names are case-sensitive. Unlisted tools are unavailable.

#### Combination 23: Deny Specific Tools
**Command:** `claude -p "Analyze the code" --disallowedTools "Write,Edit"`
**Output:** Claude can use all tools EXCEPT Write and Edit.
**Notes:** Opposite of allowedTools. Good for read-only analysis where you want tool access but no modifications.

#### Combination 24: Strict MCP Configuration
**Command:** `claude -p "Query the database" --mcp-config ./mcp.json --strict-mcp-config`
**Output:** Only MCP servers defined in the config file are available.
**Notes:** Ignores globally configured MCP servers. Ensures reproducible tool environments. Config file must be valid JSON.

### System Prompts

#### Combination 25: Replace System Prompt
**Command:** `claude -p "Review this PR" --system-prompt "You are a senior code reviewer. Focus on security issues."`
**Output:** Response shaped entirely by the custom system prompt.
**Notes:** REPLACES the entire default Claude Code system prompt. You lose all built-in behaviors (tool usage instructions, safety guidelines). Use with caution.

#### Combination 26: Append to System Prompt
**Command:** `claude -p "Summarize this file" --append-system-prompt "Always respond in valid JSON with keys: summary, issues, suggestions"`
**Output:** Response follows both default behaviors and the appended instructions.
**Notes:** ADDS to the default system prompt. Preserves all built-in tool instructions and behaviors. Preferred over `--system-prompt` in most cases.

#### Combination 27: Replace System Prompt from File
**Command:** `claude -p "Review this code" --system-prompt-file ./prompts/reviewer.txt`
**Output:** Response shaped by the file contents as system prompt.
**Notes:** Same as `--system-prompt` but reads from a file. Easier for long prompts. File must exist and be readable.

#### Combination 28: Append System Prompt from File
**Command:** `claude -p "Analyze this module" --append-system-prompt-file ./prompts/extra-rules.txt`
**Output:** Default system prompt plus file contents appended.
**Notes:** Same as `--append-system-prompt` but reads from a file. Good for shared prompt fragments across scripts.

### Structured Output

#### Combination 29: JSON Schema with Text Output
**Command:** `claude -p "List 3 colors" --json-schema '{"type":"object","properties":{"colors":{"type":"array","items":{"type":"string"}}},"required":["colors"]}'`
**Output:** Text output containing validated JSON matching the schema.
**Notes:** Output is the raw JSON string (not wrapped). Schema validation happens before output. Malformed responses are retried internally.

#### Combination 30: JSON Schema with JSON Output
**Command:** `claude -p "List 3 colors" --output-format json --json-schema '{"type":"object","properties":{"colors":{"type":"array","items":{"type":"string"}}},"required":["colors"]}'`
**Output:** JSON result object where `structured_output` contains the parsed schema-validated object.
**Notes:** The `structured_output` field is a parsed object (not a string). The `result` field contains the raw text. Use `structured_output` for programmatic access.

### Advanced

#### Combination 31: Bidirectional Streaming
**Command:** `claude -p --input-format stream-json --output-format stream-json --verbose`
**Output:** Full duplex NDJSON. Send events on stdin, receive events on stdout.
**Notes:** Input events follow the same schema as output. Enables building interactive wrappers around Claude. Stdin must provide properly formatted NDJSON events. Most advanced integration pattern.

---

## 4. Critical Discovery: stream-json Requires verbose

This is the single most important gotcha in print mode flag usage.

**The problem:** Using `--output-format stream-json` without `--verbose` produces no streaming output or errors silently. This is not documented prominently and is easy to miss.

**The fix:** Always pair them:
```bash
# WRONG -- silent failure or error
claude -p "Hello" --output-format stream-json

# CORRECT -- minimum viable streaming
claude -p "Hello" --output-format stream-json --verbose

# BETTER -- token-level granularity
claude -p "Hello" --output-format stream-json --verbose --include-partial-messages

# BEST -- full observability ("holy trinity")
claude -p "Hello" --output-format stream-json --verbose --include-partial-messages --replay-user-messages
```

The `--verbose` flag is what activates the streaming pipeline. Without it, the stream-json formatter has no events to serialize.

---

## 5. Flag Compatibility Matrix

### Requirements (flag A requires flag B)

| Flag A | Requires | Reason |
|--------|----------|--------|
| `--output-format stream-json` | `--verbose` | Streaming pipeline needs verbose event generation |
| `--input-format stream-json` | `--output-format stream-json` | Bidirectional mode requires streaming output |
| `--input-format stream-json` | `--verbose` | Implied by stream-json output requirement |
| `--include-partial-messages` | `--output-format stream-json --verbose` | Token deltas only meaningful in streaming |
| `--replay-user-messages` | `--output-format stream-json --verbose` | User echoes only meaningful in streaming |
| `--fork-session` | `--session-id` or `--resume` | Must specify which session to fork from |

### Conflicts (flag A and flag B are mutually exclusive)

| Flag A | Conflicts With | Reason |
|--------|----------------|--------|
| `--continue` | `--session-id` | Continue auto-selects the most recent session |
| `--system-prompt` | `--system-prompt-file` | Both set the same value; use one or the other |
| `--append-system-prompt` | `--append-system-prompt-file` | Both set the same value; use one or the other |
| `--no-session-persistence` | `--continue` / `--resume` | Ephemeral sessions cannot be resumed |

### Interactions (flags that modify each other's behavior)

| Combination | Effect |
|-------------|--------|
| `--tools ""` + `--mcp-config` | Empty tools disables ALL tools including MCP unless `--strict-mcp-config` is also used |
| `--json-schema` + `--output-format json` | Schema result appears in `structured_output` field (parsed object) |
| `--json-schema` + `--output-format text` | Schema result printed as raw JSON text string |
| `--allowedTools` + `--disallowedTools` | Both applied; deny takes precedence over allow |
| `--max-budget-usd` + `--output-format json` | Budget exceeded returns `subtype: "error_max_budget_usd"` instead of `"success"` |

---

## 6. Cost Reference

Approximate costs per simple single-turn prompt (as of early 2025):

| Model | Typical Cost | Use Case |
|-------|-------------|----------|
| Haiku | ~$0.017-0.025 | High-volume, simple tasks, classification |
| Sonnet | ~$0.12-0.15 | General purpose, code generation, analysis |
| Opus | ~$0.30-0.60 | Complex reasoning, large refactors |

Key cost factors:
- System context overhead: ~35k tokens from built-in system prompt and tool definitions
- Using `--system-prompt` (replace) can reduce context overhead vs the default prompt
- Using `--tools ""` eliminates tool definition tokens from context
- Session continuation adds prior conversation tokens to input
- Cache hits reduce cost: `cache_read_input_tokens` are cheaper than `input_tokens`

Cost management:
- Set `--max-budget-usd` to enforce hard caps per invocation
- Track costs via `total_cost_usd` in JSON output format
- Use `modelUsage` in JSON output for per-model breakdowns in fallback scenarios
- Haiku for high-volume pipelines, Sonnet for balanced workloads, Opus for critical tasks
