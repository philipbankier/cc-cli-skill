> Part of the [cc-cli-skill](../SKILL.md) skill.

# Streaming Events Reference

## 1. SSE Protocol Overview

Server-Sent Events (SSE) is the streaming format used by the Anthropic Messages API. Each event consists of an `event:` line naming the type, a `data:` line carrying the JSON payload, and a trailing blank line as delimiter:

```
event: message_start
data: {"type":"message_start","message":{...}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

```

Key transport details:
- Content-Type: `text/event-stream`
- Connection: keep-alive
- Cache-Control: no-cache
- The client must read the stream incrementally; buffering the entire response defeats the purpose
- A lone blank line with no preceding `event:`/`data:` is a keep-alive heartbeat and should be ignored

## 2. Event Lifecycle

The complete event sequence for a single API response:

```
message_start           <- Response begins (metadata, model, usage)
  content_block_start   <- First content block begins (index 0)
    content_block_delta <- Text chunk (repeated many times)
    content_block_delta <- More text...
  content_block_stop    <- Block complete
  [content_block_start] <- Additional blocks (tool_use, etc.)
    [content_block_delta]
  [content_block_stop]
message_delta           <- Response ending (stop_reason, final usage)
message_stop            <- Done
```

Rules:
- `content_block_start` and `content_block_stop` always appear in matched pairs
- Blocks are numbered sequentially starting from index 0
- Multiple content blocks may appear in a single message (e.g., text followed by tool_use)
- `message_delta` always precedes `message_stop`
- If the stream is interrupted before `message_stop`, the response is incomplete

## 3. Event Type Reference

### message_start

Emitted once at the beginning of every response. Contains the full message object skeleton with empty content.

```json
{
  "type": "message_start",
  "message": {
    "id": "msg_01XFDUDYJgAACzvnptvVoYEL",
    "type": "message",
    "role": "assistant",
    "content": [],
    "model": "claude-sonnet-4-20250514",
    "stop_reason": null,
    "stop_sequence": null,
    "usage": { "input_tokens": 25, "output_tokens": 1 }
  }
}
```

Fields of note:
- `usage.input_tokens` is final here; output tokens accumulate via `message_delta`
- `stop_reason` is always `null` at this stage

### content_block_start

Signals a new content block. The `index` field identifies it for subsequent deltas and the stop event.

For **text** blocks:
```json
{
  "type": "content_block_start",
  "index": 0,
  "content_block": { "type": "text", "text": "" }
}
```

For **tool_use** blocks:
```json
{
  "type": "content_block_start",
  "index": 1,
  "content_block": {
    "type": "tool_use",
    "id": "toolu_01T1x1fJ34qAmk2tNTrN7Up6",
    "name": "get_weather",
    "input": {}
  }
}
```

### content_block_delta

Carries incremental content for the block identified by `index`. This is the most frequently emitted event.

For **text** content:
```json
{
  "type": "content_block_delta",
  "index": 0,
  "delta": { "type": "text_delta", "text": "Hello" }
}
```

For **tool input** JSON (accumulated fragments that concatenate into valid JSON):
```json
{
  "type": "content_block_delta",
  "index": 1,
  "delta": { "type": "input_json_delta", "partial_json": "{\"city\":" }
}
```

### content_block_stop

Marks the end of a content block. No further deltas will reference this index.

```json
{ "type": "content_block_stop", "index": 0 }
```

### message_delta

Carries final metadata for the response, including the stop reason and cumulative output token count.

```json
{
  "type": "message_delta",
  "delta": { "stop_reason": "end_turn", "stop_sequence": null },
  "usage": { "output_tokens": 15 }
}
```

Common `stop_reason` values: `"end_turn"`, `"tool_use"`, `"max_tokens"`, `"stop_sequence"`.

### message_stop

Terminal event. The stream is complete; close the connection.

```json
{ "type": "message_stop" }
```

## 4. Tool Use Streaming

When Claude decides to call a tool, the stream contains a `tool_use` content block whose JSON input arrives incrementally:

1. A text content block may appear first (Claude's preamble before the call)
2. A `tool_use` content block streams the function name and input JSON
3. After the client executes the tool and sends a `tool_result` message, a **new** stream begins with the final response

Example event sequence for a tool call:

```
content_block_start  -> {"type":"tool_use","id":"toolu_01...","name":"get_weather","input":{}}
content_block_delta  -> {"type":"input_json_delta","partial_json":"{\"city\":"}
content_block_delta  -> {"type":"input_json_delta","partial_json":"\"London\"}"}
content_block_stop   -> index 1
message_delta        -> stop_reason: "tool_use"
message_stop
```

To reconstruct the full tool input, concatenate all `partial_json` strings from deltas sharing the same block index, then `JSON.parse` the result.

The `stop_reason` of `"tool_use"` signals the client to execute the tool, build a `tool_result` content block, and POST a new messages request to continue the conversation.

## 5. CLI stream-json Events

When using `claude -p --output-format stream-json --verbose`, the CLI produces **NDJSON** (one JSON object per line) with its own wrapper types:

**Init event** (first line):
```json
{"type":"system","subtype":"init","session_id":"abc123","tools":[...]}
```

**Assistant message events** (content as it builds):
```json
{"type":"assistant","message":{"id":"msg_01...","content":[{"type":"text","text":"partial..."}]}}
```

**Result event** (final line):
```json
{"type":"result","subtype":"success","duration_ms":1234,"total_cost_usd":0.012,"usage":{"input_tokens":25,"output_tokens":80}}
```

Key differences from raw SSE:
- CLI events are **NDJSON** (newline-delimited JSON), not SSE format
- Each line is a self-contained JSON object; there are no `event:` / `data:` prefixes
- The bridge must transform between NDJSON (CLI side) and SSE (browser side)

With `--include-partial-messages`, intermediate `assistant` events are emitted as tokens arrive, giving you real-time streaming. Without it, you only receive the final `assistant` event and the `result`.

## 6. Consuming Streams

### Bash

```bash
claude -p "Hello" --output-format stream-json --verbose --include-partial-messages | \
  while read -r line; do
    text=$(echo "$line" | jq -r 'select(.type=="assistant") | .message.content[-1].text // empty')
    [ -n "$text" ] && printf "%s" "$text"
  done
```

### Python

```python
import subprocess, json

proc = subprocess.Popen(
    ["claude", "-p", "--output-format", "stream-json", "--verbose",
     "--include-partial-messages", "Hello"],
    stdout=subprocess.PIPE, text=True
)
for line in proc.stdout:
    line = line.strip()
    if not line:
        continue
    event = json.loads(line)
    if event.get("type") == "assistant":
        content = event.get("message", {}).get("content", [])
        if content and content[-1].get("type") == "text":
            print(content[-1]["text"], end="", flush=True)
```

### JavaScript / Node.js

```javascript
import { spawn } from 'child_process';

const proc = spawn('claude', [
  '-p', '--output-format', 'stream-json',
  '--verbose', '--include-partial-messages', 'Hello'
]);

let buffer = '';
proc.stdout.on('data', (chunk) => {
  buffer += chunk.toString();
  const lines = buffer.split('\n');
  buffer = lines.pop();          // keep incomplete trailing line
  for (const line of lines) {
    if (!line.trim()) continue;
    const event = JSON.parse(line);
    if (event.type === 'assistant') {
      const content = event.message?.content;
      if (content?.length) process.stdout.write(content.at(-1).text || '');
    }
  }
});
```

### Go

```go
scanner := bufio.NewScanner(cmd.Stdout)
for scanner.Scan() {
    var event map[string]interface{}
    if err := json.Unmarshal(scanner.Bytes(), &event); err != nil {
        continue
    }
    if event["type"] == "assistant" {
        msg, _ := event["message"].(map[string]interface{})
        content, _ := msg["content"].([]interface{})
        if len(content) > 0 {
            block, _ := content[len(content)-1].(map[string]interface{})
            if text, ok := block["text"].(string); ok {
                fmt.Print(text)
            }
        }
    }
}
```
