> Part of the [cc-cli-skill](../SKILL.md) skill.

# JSON Schemas and Output Shapes

Reference for all JSON response formats used by Claude CLI print mode and the Anthropic API.

## 1. CLI JSON Output (Non-Streaming)

When using `--output-format json`, the CLI returns:

```json
{
  "type": "result",
  "subtype": "success",
  "is_error": false,
  "duration_ms": 1234,
  "duration_api_ms": 5678,
  "num_turns": 1,
  "result": "The text response from Claude",
  "session_id": "abc123-def456-...",
  "total_cost_usd": 0.0123,
  "usage": {
    "input_tokens": 150,
    "output_tokens": 50,
    "cache_creation_input_tokens": 0,
    "cache_read_input_tokens": 1000
  },
  "modelUsage": {
    "claude-sonnet-4-20250514": {
      "inputTokens": 150,
      "outputTokens": 50,
      "cacheCreationInputTokens": 0,
      "cacheReadInputTokens": 1000
    }
  },
  "permission_denials": [],
  "structured_output": null
}
```

When `subtype` is `"error_max_budget_usd"`, the budget was exceeded.

## 2. Anthropic API Response (What Bridges Produce)

The standard API response format:

```json
{
  "id": "msg_01XFDUDYJgAACzvnptvVoYEL",
  "type": "message",
  "role": "assistant",
  "content": [
    {"type": "text", "text": "Hello! How can I help you?"}
  ],
  "model": "claude-sonnet-4-20250514",
  "stop_reason": "end_turn",
  "stop_sequence": null,
  "usage": {
    "input_tokens": 25,
    "output_tokens": 15
  }
}
```

`stop_reason` values: `"end_turn"`, `"max_tokens"`, `"stop_sequence"`, `"tool_use"`

## 3. Structured Output with --json-schema

When `--json-schema` is provided, the CLI validates output against the schema.

In JSON output mode, the validated data appears in `structured_output`:

```json
{
  "type": "result",
  "result": "The functions in this file are: add, subtract, multiply",
  "structured_output": {
    "functions": ["add", "subtract", "multiply"]
  }
}
```

Important: `result` still contains the text response. `structured_output` is the validated JSON.

Example schema:

```json
{
  "type": "object",
  "properties": {
    "functions": {"type": "array", "items": {"type": "string"}},
    "classes": {"type": "array", "items": {"type": "string"}}
  },
  "required": ["functions", "classes"]
}
```

## 4. Content Block Types

Content blocks appear in the `content` array of API responses:

### Text Block

```json
{"type": "text", "text": "Hello! How can I help you?"}
```

### Tool Use Block

Returned when Claude wants to call a tool:

```json
{
  "type": "tool_use",
  "id": "toolu_01A09q90qw90lq917835lq9",
  "name": "get_weather",
  "input": {"city": "London", "unit": "celsius"}
}
```

### Tool Result Block

Sent by the client with tool output:

```json
{
  "type": "tool_result",
  "tool_use_id": "toolu_01A09q90qw90lq917835lq9",
  "content": "The weather in London is 15°C and cloudy."
}
```

### Thinking Block (Extended Thinking)

When extended thinking is enabled (simulated in CC-Bridge):

```json
{
  "type": "thinking",
  "thinking": "Let me work through this step by step...\n1. First, I need to..."
}
```

## 5. Error Response Shapes

### CLI Error

```json
{
  "type": "result",
  "subtype": "error",
  "is_error": true,
  "result": "Error message here"
}
```

### API Error (What Bridges Return)

```json
{
  "type": "error",
  "error": {
    "type": "invalid_request_error",
    "message": "model is required"
  }
}
```

Error types: `"invalid_request_error"`, `"authentication_error"`, `"rate_limit_error"`, `"api_error"`, `"overloaded_error"`

## 6. Usage Tracking

### CLI Usage

```json
"usage": {
  "input_tokens": 150,
  "output_tokens": 50,
  "cache_creation_input_tokens": 0,
  "cache_read_input_tokens": 1000
}
```

Note: ~35k tokens of system context are included in input_tokens (Claude Code's default system prompt).

### API Usage

```json
"usage": {
  "input_tokens": 25,
  "output_tokens": 15
}
```

Bridge estimates these from CLI output. May not be exact.

### Cost Tracking (CLI only)

```json
"total_cost_usd": 0.0123
```

Available in CLI JSON output. Not part of the standard API response.
