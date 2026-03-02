> Part of the [cc-cli-skill](../SKILL.md) skill.

# Build an API-Compatible Bridge Server

## Goal

Build an HTTP server that wraps `claude -p` and exposes an Anthropic-compatible API endpoint.
This lets existing apps and SDKs use Claude through a local bridge without changing code --
just point `base_url` at localhost. The bridge translates standard `/v1/messages` requests
into CLI invocations and returns responses in the Anthropic SDK response format.

## Architecture Overview

```
Your App (Anthropic SDK)
    |
    |  POST /v1/messages
    v
CC-Bridge (HTTP Server)
    |
    |  spawn("claude", ["-p", ...])
    v
Claude CLI (Official, Authenticated)
    |
    |  Anthropic API call
    v
Anthropic Backend
    |
    |  Response
    v
    Back up the chain
```

Why this pattern works:

- **Uses authenticated CLI credentials** -- no API key management needed. The bridge
  delegates authentication entirely to the local CLI session. Anyone who has run
  `claude auth login` can use the bridge immediately.
- **100% SDK compatible** -- zero code changes in your app. The Anthropic Python,
  TypeScript, and Go SDKs all accept a `base_url` parameter. Point it at
  `http://localhost:8321` and everything works.
- **Local-only** -- no external dependencies beyond the CLI itself. The bridge runs
  on localhost, spawns CLI processes, and returns results. No cloud infrastructure,
  no API gateway, no key rotation.

## CC-Bridge Reference Implementation

The reference implementation ([github.com/ranaroussi/cc-bridge](https://github.com/ranaroussi/cc-bridge)) is a Go server with these files:

| File | Role |
|------|------|
| `main.go` | HTTP server entry point, flag parsing, graceful shutdown |
| `handler.go` | Request routing, `/v1/messages` endpoint |
| `cli.go` | Claude CLI subprocess execution |
| `mapper.go` | API parameters to CLI flags translation |
| `streaming.go` | SSE streaming response handling |
| `types.go` | Request/response type definitions |

The server compiles to a single binary with no runtime dependencies beyond the Claude CLI.

## Request Flow Step-by-Step

When a POST hits `/v1/messages`:

1. **Parse request** -- Decode JSON body into an AnthropicRequest struct. Validate that
   `model` and `messages` fields are present.

2. **Map model name** -- Translate full model identifiers to CLI short names:
   - `claude-sonnet-4-20250514` -> `sonnet`
   - `claude-3-5-haiku-*` -> `haiku`
   - `claude-opus-4-*` -> `opus`
   - Short names pass through unchanged.

3. **Build CLI command** -- Base flags always include:
   ```
   claude -p --no-session-persistence --dangerously-skip-permissions --output-format json
   ```

4. **Map optional parameters:**
   - System prompt -> `--append-system-prompt`
   - Tools -> `--allowedTools` with tool names mapped (`bash_20250124` -> `Bash`, `text_editor_20250728` -> `Edit`)
   - JSON schema -> `--json-schema`
   - Streaming requested -> switch to `--output-format stream-json --verbose --include-partial-messages`

5. **Build prompt** -- Flatten the messages array into a single prompt string for stdin.
   Each message is formatted with its role and content, preserving conversation structure.

6. **Execute CLI** -- `exec.CommandContext` with stdin pipe, capture stdout. Apply timeout
   from configuration.

7. **Parse response** -- JSON decode the CLI stdout output into a CLIResponse struct.

8. **Transform** -- Map CLIResponse fields to the Anthropic API response format,
   including usage statistics, stop reason, and content blocks.

9. **Return** -- Send JSON response with `Content-Type: application/json`.

## Parameter Mapping Reference

API parameter to CLI flag translations:

| API Parameter | CLI Flag | Notes |
|---|---|---|
| `model` | `--model` | Mapped: `claude-sonnet-4-*` -> `sonnet` |
| `messages` | stdin (prompt) | Flattened to text |
| `system` | `--append-system-prompt` | System message content |
| `stream` | `--output-format stream-json` | Plus `--verbose --include-partial-messages` |
| `tools` | Tool definitions | Mapped to `--allowedTools` |
| `tool_choice` | `--json-schema` (for `any`/`tool`) | Forces structured output |
| `max_tokens` | (ignored) | CLI limitation -- no flag exists |
| `temperature` | (ignored) | CLI limitation |
| `top_p` | (ignored) | CLI limitation |
| `top_k` | (ignored) | CLI limitation |
| `stop_sequences` | (ignored) | CLI limitation |
| `metadata` | (ignored) | Not applicable |

Tool name mapping:

| API Tool Name | CLI Tool Name |
|---|---|
| `bash_20250124` | `Bash` |
| `text_editor_20250728` | `Edit` |
| `computer_*` | Not supported |

## Non-Streaming Implementation

```go
// Simplified -- actual implementation has error handling
func handleNonStreaming(req AnthropicRequest) AnthropicResponse {
    // Build CLI args
    args := []string{"-p",
        "--no-session-persistence",
        "--dangerously-skip-permissions",
        "--output-format", "json",
        "--model", mapModel(req.Model),
    }
    if req.System != "" {
        args = append(args, "--append-system-prompt", req.System)
    }

    // Execute
    cmd := exec.CommandContext(ctx, "claude", args...)
    cmd.Stdin = strings.NewReader(buildPrompt(req.Messages))
    output, err := cmd.Output()

    // Parse CLI response
    var cliResp CLIResponse
    json.Unmarshal(output, &cliResp)

    // Transform to API format
    return AnthropicResponse{
        ID:         "msg_" + generateID(),
        Type:       "message",
        Role:       "assistant",
        Content:    []ContentBlock{{Type: "text", Text: cliResp.Result}},
        Model:      req.Model,
        StopReason: "end_turn",
        Usage: Usage{
            InputTokens:  cliResp.Usage.InputTokens,
            OutputTokens: cliResp.Usage.OutputTokens,
        },
    }
}
```

Key points:
- `buildPrompt` flattens the messages array into a single string with role prefixes.
- `mapModel` converts full model identifiers to CLI short names.
- The generated `msg_` ID is a UUID since the CLI does not return a message ID.
- Usage tokens are passed through from the CLI response.

## Streaming Implementation

For streaming, the bridge:
1. Sets `--output-format stream-json --verbose --include-partial-messages`
2. Reads stdout line-by-line as NDJSON events
3. Transforms CLI events into Anthropic SSE events

SSE event lifecycle the bridge must produce:

```
event: message_start
data: {"type":"message_start","message":{"id":"msg_...","type":"message","role":"assistant","model":"...","usage":{"input_tokens":N}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"chunk"}}
[... repeated for each chunk ...]

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":N}}

event: message_stop
data: {"type":"message_stop"}
```

Key implementation details:

- **Response headers:** Set `Content-Type: text/event-stream`, `Cache-Control: no-cache`,
  `Connection: keep-alive` before sending any events.
- **Flushing:** Use `http.Flusher` to send each event immediately rather than buffering.
- **Chunking:** Split text into approximately 50-character pieces for smooth streaming.
  The CLI may emit large text blocks at once, so the bridge must chunk them into deltas.
- **Tool use responses:** Collect the full response first, then emit `tool_use` content
  blocks. Tool use cannot be streamed incrementally because the full JSON input must be valid.
- **CLI output parsing:** Handle `[{"type":"tool_use","id":"...","name":"...","input":{...}}]`
  format in CLI output and transform each entry into a separate content block.

## Tool Use Emulation

CC-Bridge supports the full tool use cycle:

1. Client sends a request with a `tools` array containing tool definitions.
2. Bridge maps API tool definitions to CLI tool names via `--allowedTools`.
3. CLI executes the request and returns `tool_use` blocks in its response.
4. Bridge transforms the CLI output to Anthropic `tool_use` format:
   ```json
   {"type": "tool_use", "id": "toolu_...", "name": "get_weather", "input": {"city": "London"}}
   ```
5. Client receives the tool use block and executes the tool locally.
6. Client sends the `tool_result` back in a follow-up request.
7. Bridge includes the tool results in the next CLI invocation prompt.
8. CLI produces the final text response incorporating the tool output.

Each tool use round-trip is a separate HTTP request. The bridge is stateless --
it does not maintain conversation state between requests. The client is responsible
for accumulating the full message history and sending it with each request.

## Vision and Document Support

For `image` or `document` content blocks in the messages array:

1. Extract the base64-encoded data from the content block.
2. Decode and write to a temporary file (e.g., `/tmp/cc-bridge-img-xxx.png`).
3. Pass the temp directory to the CLI via `--add-dir /tmp/cc-bridge-img-xxx/`.
4. Include a reference in the prompt text: "See the attached image."
5. Clean up temporary files after the response is returned.

Supported formats:
- **Images:** JPEG, PNG, GIF, WebP
- **Documents:** PDF

Temp files should be written to a unique directory per request to avoid collisions
in concurrent scenarios. Use `os.MkdirTemp` for isolation.

## Configuration

```bash
# CLI flags
./ccbridge --port 8321 --host 127.0.0.1

# Environment variables
CC_BRIDGE_PORT=8321                    # Server port (default: 8321)
CC_BRIDGE_HOST=0.0.0.0                 # Bind address (default: 0.0.0.0)
CC_BRIDGE_DEBUG=true                   # Enable debug logging
CLAUDE_CLI_PATH=/usr/local/bin/claude  # Custom CLI path
CLAUDE_CLI_TIMEOUT=30m                 # Execution timeout
```

CLI flags take precedence over environment variables. The default bind address is
`0.0.0.0` (all interfaces), but for local development `127.0.0.1` is recommended
to avoid exposing the bridge to the network.

Debug mode logs the full CLI command, stdin content, stdout output, and timing
for every request. Disable in production.

## Building Your Own Bridge

Progressive implementation path:

### Step 1: Minimum Viable Bridge (non-streaming only)

- Single endpoint: `POST /v1/messages`
- Parse `model` and `messages` from the request body
- Execute `claude -p --output-format json --no-session-persistence --dangerously-skip-permissions`
- Pass the flattened messages as stdin
- Parse CLI JSON output and transform to Anthropic response format
- Return with `Content-Type: application/json`

This is enough to work with the Anthropic SDK for basic request/response flows.

### Step 2: Add Streaming

- Check the `stream` field in the request body
- If true, switch to `--output-format stream-json --verbose --include-partial-messages`
- Set SSE response headers
- Read CLI stdout line-by-line and emit SSE events
- Produce the full event lifecycle: `message_start`, `content_block_start`, deltas, stops

### Step 3: Add Tool Support

- Parse the `tools` array from the request
- Map API tool names to CLI tool names
- Add `--allowedTools` flags to the CLI command
- Handle `tool_use` content blocks in CLI output
- Transform to Anthropic `tool_use` response format

### Step 4: Add Vision

- Detect `image` and `document` content blocks in messages
- Decode base64 data and write to temporary files
- Pass temp directories via `--add-dir`
- Clean up after response

### Step 5: Production Hardening

- Graceful shutdown with SIGTERM/SIGINT handling
- Per-request timeout via `context.WithTimeout`
- Structured debug logging (request ID, duration, CLI exit code)
- Health check endpoint (`GET /health`)
- Request validation with descriptive error responses

## Limitations

- **Latency overhead:** ~100-200ms per request from CLI process spawning. Each request
  starts a new `claude` process. There is no connection pooling or keep-alive.
- **Single-user:** No multi-tenant support. The bridge uses whatever CLI credentials
  are configured on the host.
- **Stateless:** Each request is independent. The bridge does not maintain conversation
  state -- the client must send full message history each time.
- **No sampling parameters:** Temperature, top_p, top_k, and max_tokens are ignored.
  The CLI does not expose flags for these settings.
- **No extended thinking:** Native extended thinking is not available through the CLI.
  Can be approximated via prompt engineering but is not equivalent.
- **No prompt caching:** The Anthropic prompt caching feature is not available through
  the CLI bridge path.
- **No batch API:** The bridge handles requests synchronously one at a time. There is
  no batch endpoint.
