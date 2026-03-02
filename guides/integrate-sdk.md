> Part of the [cc-cli-skill](../SKILL.md) skill.

# Integrate Existing SDKs with CC-Bridge

## 1. How It Works

CC-Bridge implements the same HTTP API as `api.anthropic.com`. Existing Anthropic SDKs work with a single change: point `base_url` at your local bridge. No code changes beyond that. The SDK sends requests to the bridge, which wraps them into `claude -p` calls.

The bridge translates between the Messages API format and CLI invocations transparently. Responses are converted back into proper API response objects, including streaming via Server-Sent Events.

**Prerequisites:** CC-Bridge running locally (see [build-bridge.md](build-bridge.md))

## 2. Python SDK Integration

```bash
pip install anthropic
```

### Non-Streaming

```python
import anthropic

client = anthropic.Anthropic(
    api_key="dummy",  # Bridge doesn't validate keys
    base_url="http://localhost:8321"
)

message = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=1024,
    messages=[{"role": "user", "content": "Hello!"}]
)
print(message.content[0].text)
```

### Streaming

```python
with client.messages.stream(
    model="claude-sonnet-4-20250514",
    max_tokens=1024,
    messages=[{"role": "user", "content": "Explain recursion"}]
) as stream:
    for text in stream.text_stream:
        print(text, end="", flush=True)
print()
```

### Tool Use

```python
message = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=1024,
    tools=[{
        "name": "get_weather",
        "description": "Get weather for a city",
        "input_schema": {
            "type": "object",
            "properties": {"city": {"type": "string"}},
            "required": ["city"]
        }
    }],
    messages=[{"role": "user", "content": "Weather in Tokyo?"}]
)
for block in message.content:
    if block.type == "tool_use":
        print(f"Tool: {block.name}, Input: {block.input}")
```

### Structured Output

```python
message = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=1024,
    messages=[{"role": "user", "content": "Extract name and email from: John at john@example.com"}],
    output_format={
        "type": "json_schema",
        "schema": {
            "type": "object",
            "properties": {"name": {"type": "string"}, "email": {"type": "string"}},
            "required": ["name", "email"]
        }
    }
)
```

## 3. TypeScript/JavaScript SDK Integration

```bash
npm install @anthropic-ai/sdk
```

### Non-Streaming

```typescript
import Anthropic from '@anthropic-ai/sdk';

const client = new Anthropic({
  apiKey: 'dummy',
  baseURL: 'http://localhost:8321',
});

const message = await client.messages.create({
  model: 'claude-sonnet-4-20250514',
  max_tokens: 1024,
  messages: [{ role: 'user', content: 'Hello!' }],
});
console.log(message.content[0].text);
```

### Streaming

```typescript
const stream = client.messages.stream({
  model: 'claude-sonnet-4-20250514',
  max_tokens: 1024,
  messages: [{ role: 'user', content: 'Explain async/await' }],
});
for await (const event of stream) {
  if (event.type === 'content_block_delta' && event.delta.type === 'text_delta') {
    process.stdout.write(event.delta.text);
  }
}
```

### Tool Use

```typescript
const message = await client.messages.create({
  model: 'claude-sonnet-4-20250514',
  max_tokens: 1024,
  tools: [{
    name: 'get_weather',
    description: 'Get weather for a city',
    input_schema: {
      type: 'object',
      properties: { city: { type: 'string' } },
      required: ['city'],
    },
  }],
  messages: [{ role: 'user', content: 'Weather in London?' }],
});
```

## 4. curl Integration

```bash
# Non-streaming
curl -s -X POST http://localhost:8321/v1/messages \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-20250514",
    "max_tokens": 1024,
    "messages": [{"role": "user", "content": "Hello!"}]
  }' | jq '.content[0].text'

# Streaming
curl -N -X POST http://localhost:8321/v1/messages \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-20250514",
    "max_tokens": 1024,
    "stream": true,
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

## 5. What Works and What Doesn't

### Full Support

| Feature | Status |
|---------|--------|
| Messages (non-streaming) | Works |
| Streaming (SSE) | Works |
| System prompts | Works |
| Tool use (full cycle) | Works |
| Vision (images) | Works |
| Documents (PDF) | Works |
| Structured output | Works |
| All models (opus/sonnet/haiku) | Works |

### Accepted but Ignored (CLI Limitation)

| Parameter | Effect |
|-----------|--------|
| `temperature` | Ignored -- Claude uses defaults |
| `top_p` | Ignored |
| `top_k` | Ignored |
| `max_tokens` | Ignored |
| `stop_sequences` | Ignored |

### Not Available

| Feature | Reason |
|---------|--------|
| Extended thinking (native) | Simulated via prompt engineering |
| Prompt caching | Requires beta headers |
| Batch API | Different endpoint |

## 6. Environment-Based Switching

Switch between bridge and direct API using environment variables:

```python
import os
import anthropic

base_url = os.environ.get("ANTHROPIC_BASE_URL", "https://api.anthropic.com")
api_key = os.environ.get("ANTHROPIC_API_KEY", "dummy")

client = anthropic.Anthropic(api_key=api_key, base_url=base_url)
```

```bash
# Use bridge
ANTHROPIC_BASE_URL=http://localhost:8321 python app.py

# Use direct API
ANTHROPIC_API_KEY=sk-ant-... python app.py
```

This pattern lets you develop against the bridge locally and deploy against the real API without changing code.

## 7. Multi-Client Setup

Run multiple bridge instances for different configurations:

```bash
# Instance 1: Default (port 8321)
./ccbridge --port 8321 &

# Instance 2: Different port
./ccbridge --port 8322 &
```

Note: Each request spawns a CLI process. Under heavy load, consider:

- Limiting concurrent requests
- Using haiku for high-throughput, low-cost tasks
- Using opus only for complex reasoning tasks
