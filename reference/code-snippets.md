> Part of the [cc-cli](../SKILL.md) skill.

# Code Snippets

Ready-to-use patterns for Claude CLI print mode and CC-Bridge integration.

## Bash Patterns

### Simple Query
```bash
claude -p "What is dependency injection?"
```

### JSON Output with jq Parsing
```bash
result=$(claude -p "Summarize this file" --output-format json < README.md)
echo "$result" | jq -r '.result'
echo "Cost: $(echo "$result" | jq '.total_cost_usd')"
echo "Session: $(echo "$result" | jq -r '.session_id')"
```

### Real-Time Streaming
```bash
claude -p "Explain this codebase" \
  --output-format stream-json \
  --verbose \
  --include-partial-messages | \
  while read -r line; do
    text=$(echo "$line" | jq -r 'select(.type=="assistant") | .message.content[-1].text // empty')
    [ -n "$text" ] && printf "%s" "$text"
  done
echo  # newline at end
```

### Multi-Step Session Workflow
```bash
# Step 1: Start analysis, capture session
SESSION=$(claude -p "Analyze the architecture of this project" \
  --output-format json \
  < <(find src -name "*.ts" -exec head -20 {} +) | jq -r '.session_id')

# Step 2: Follow up in same session
claude -p --resume "$SESSION" "Now suggest improvements" --output-format json | jq -r '.result'

# Step 3: Fork for alternative exploration
claude -p --resume "$SESSION" --fork-session "What if we used microservices instead?" --output-format json | jq -r '.result'
```

### Automated Code Review
```bash
git diff main...HEAD | claude -p \
  --append-system-prompt "You are a senior code reviewer. Flag bugs, security issues, and style problems. Be concise." \
  --model sonnet \
  --max-budget-usd 0.50 \
  --no-session-persistence \
  --tools ""
```

### Batch Processing Files
```bash
for file in src/*.py; do
  echo "--- Reviewing: $file ---"
  claude -p "Review this Python file for bugs" \
    --model haiku \
    --max-budget-usd 0.05 \
    --no-session-persistence \
    --tools "" \
    < "$file"
  echo
done
```

### Structured Data Extraction
```bash
claude -p "Extract all TODO comments with file and line number" \
  --output-format json \
  --json-schema '{
    "type": "object",
    "properties": {
      "todos": {
        "type": "array",
        "items": {
          "type": "object",
          "properties": {
            "file": {"type": "string"},
            "line": {"type": "integer"},
            "text": {"type": "string"}
          },
          "required": ["file", "line", "text"]
        }
      }
    },
    "required": ["todos"]
  }' \
  --tools "Bash,Read,Glob,Grep" \
  --dangerously-skip-permissions \
  --no-session-persistence | jq '.structured_output'
```

### Generate Commit Message
```bash
msg=$(git diff --staged | claude -p \
  --append-system-prompt "Generate a concise conventional commit message (type: description). No explanation, just the message." \
  --model haiku \
  --no-session-persistence \
  --tools "")
git commit -m "$msg"
```

## Python Patterns

### subprocess with JSON Output
```python
import subprocess
import json

def claude_query(prompt: str, model: str = "sonnet") -> dict:
    result = subprocess.run(
        ["claude", "-p", "--output-format", "json",
         "--no-session-persistence", "--model", model, prompt],
        capture_output=True, text=True, check=True
    )
    return json.loads(result.stdout)

response = claude_query("What is 2+2?")
print(response["result"])
print(f"Cost: ${response['total_cost_usd']:.4f}")
```

### Streaming with subprocess
```python
import subprocess
import json
import sys

proc = subprocess.Popen(
    ["claude", "-p", "--output-format", "stream-json", "--verbose",
     "--include-partial-messages", "--no-session-persistence",
     "Explain quantum computing"],
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
            sys.stdout.write(content[-1]["text"])
            sys.stdout.flush()
print()
```

### Anthropic SDK via CC-Bridge
```python
import anthropic

# Point SDK at local CC-Bridge (must be running on port 8321)
client = anthropic.Anthropic(
    api_key="dummy",  # Not validated by bridge
    base_url="http://localhost:8321"
)

# Non-streaming
message = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=1024,
    messages=[{"role": "user", "content": "Hello!"}]
)
print(message.content[0].text)

# Streaming
with client.messages.stream(
    model="claude-sonnet-4-20250514",
    max_tokens=1024,
    messages=[{"role": "user", "content": "Explain recursion"}]
) as stream:
    for text in stream.text_stream:
        print(text, end="", flush=True)
print()
```

### Structured Output
```python
import subprocess
import json

schema = json.dumps({
    "type": "object",
    "properties": {
        "functions": {"type": "array", "items": {"type": "string"}},
        "classes": {"type": "array", "items": {"type": "string"}}
    },
    "required": ["functions", "classes"]
})

result = subprocess.run(
    ["claude", "-p", "--output-format", "json",
     "--json-schema", schema,
     "--no-session-persistence",
     "List all functions and classes in this code"],
    input=open("main.py").read(),
    capture_output=True, text=True
)
data = json.loads(result.stdout)
print(data["structured_output"])
```

## JavaScript/TypeScript Patterns

### execSync for Simple Calls
```typescript
import { execSync } from 'child_process';

const result = execSync(
  'claude -p "What is TypeScript?" --output-format json --no-session-persistence',
  { encoding: 'utf-8' }
);
const response = JSON.parse(result);
console.log(response.result);
```

### Anthropic SDK via CC-Bridge
```typescript
import Anthropic from '@anthropic-ai/sdk';

const client = new Anthropic({
  apiKey: 'dummy',
  baseURL: 'http://localhost:8321',
});

// Non-streaming
const message = await client.messages.create({
  model: 'claude-sonnet-4-20250514',
  max_tokens: 1024,
  messages: [{ role: 'user', content: 'Hello!' }],
});
console.log(message.content[0].text);

// Streaming
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
console.log();
```

### Tool Use via CC-Bridge
```typescript
const message = await client.messages.create({
  model: 'claude-sonnet-4-20250514',
  max_tokens: 1024,
  tools: [{
    name: 'get_weather',
    description: 'Get current weather for a city',
    input_schema: {
      type: 'object',
      properties: { city: { type: 'string' } },
      required: ['city']
    }
  }],
  messages: [{ role: 'user', content: 'What is the weather in London?' }],
});

// Handle tool use response
for (const block of message.content) {
  if (block.type === 'tool_use') {
    console.log(`Tool: ${block.name}, Input: ${JSON.stringify(block.input)}`);
    // Send tool_result back...
  }
}
```

## Go Patterns

### CLI Execution (CC-Bridge Pattern)
```go
func executeCLI(ctx context.Context, prompt string, model string) (CLIResponse, error) {
    args := []string{"-p",
        "--no-session-persistence",
        "--dangerously-skip-permissions",
        "--output-format", "json",
        "--model", model,
        prompt,
    }

    cmd := exec.CommandContext(ctx, "claude", args...)
    output, err := cmd.Output()
    if err != nil {
        return CLIResponse{}, fmt.Errorf("cli execution failed: %w", err)
    }

    var resp CLIResponse
    if err := json.Unmarshal(output, &resp); err != nil {
        return CLIResponse{}, fmt.Errorf("parse failed: %w", err)
    }
    return resp, nil
}
```

### Streaming with bufio.Scanner
```go
cmd := exec.CommandContext(ctx, "claude", "-p",
    "--output-format", "stream-json", "--verbose",
    "--include-partial-messages", "--no-session-persistence",
    prompt)
stdout, _ := cmd.StdoutPipe()
cmd.Start()

scanner := bufio.NewScanner(stdout)
for scanner.Scan() {
    var event map[string]interface{}
    json.Unmarshal(scanner.Bytes(), &event)
    if event["type"] == "assistant" {
        msg := event["message"].(map[string]interface{})
        content := msg["content"].([]interface{})
        if len(content) > 0 {
            block := content[len(content)-1].(map[string]interface{})
            if text, ok := block["text"].(string); ok {
                fmt.Print(text)
            }
        }
    }
}
cmd.Wait()
```

## CI/CD Patterns

### GitHub Actions -- Code Review
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
      - name: Review PR
        run: |
          git diff origin/${{ github.base_ref }}...HEAD | claude -p \
            --append-system-prompt "Review this diff. Flag bugs, security issues, performance problems. Output markdown." \
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

### GitLab CI -- Test Analysis
```yaml
analyze-failures:
  stage: test
  script:
    - npm install -g @anthropic-ai/claude-code
    - |
      if ! make test 2>&1 | tee test-output.txt; then
        cat test-output.txt | claude -p \
          --append-system-prompt "Analyze these test failures. Identify root causes and suggest fixes." \
          --model haiku \
          --max-budget-usd 0.10 \
          --no-session-persistence \
          --tools "" \
          > analysis.md
      fi
  artifacts:
    paths: [analysis.md]
    when: on_failure
```

### Pre-Commit Hook
```bash
#!/bin/bash
# .git/hooks/pre-commit
staged_diff=$(git diff --cached)
if [ -n "$staged_diff" ]; then
  result=$(echo "$staged_diff" | claude -p \
    --append-system-prompt "Check for: leaked secrets, obvious bugs, security issues. Reply PASS if clean, or describe problems." \
    --model haiku \
    --max-budget-usd 0.03 \
    --no-session-persistence \
    --tools "")
  if echo "$result" | grep -qiv "PASS"; then
    echo "Issues found:"
    echo "$result"
    exit 1
  fi
fi
```
