# Multi-Perspective Debate Engine -- Walkthrough

## Introduction

This document is an annotated walkthrough of the Multi-Perspective Debate Engine, a
multi-agent system that takes a topic, spawns five AI "debaters" with distinct
perspectives, and then feeds their structured arguments to a Moderator agent that
synthesizes a balanced analysis.

The five perspectives are: **Optimist**, **Skeptic**, **Historian**, **Futurist**, and
**Practitioner**. Each runs as an independent `claude -p` invocation with its own system
prompt, producing validated JSON output. The Moderator receives all five outputs and
produces a final synthesis -- either streamed in real time or as structured JSON.

**Why this example matters:** It demonstrates the core techniques from the
[cc-cli-skill skill](../../SKILL.md) in a realistic multi-agent pipeline:

- Batch processing with parallel execution
- Structured output via `--json-schema`
- Streaming with NDJSON event parsing
- System prompts for agent personas
- Cost tracking across multiple calls

**Two implementations** are provided side by side:

- `debate.sh` -- raw `claude -p` with Bash, no dependencies beyond the CLI
- `debate.py` -- Anthropic Python SDK via [CC-Bridge](../../guides/build-bridge.md)

---

## Architecture

```
                    +---------------+
                    |    Topic      |
                    | (user input)  |
                    +-------+-------+
                            |
           +----------------+----------------+
           |        |        |       |       |
      +----v---+ +--v----+ +v------+ +v-----+ +v-----------+
      |Optimist| |Skeptic| |Histor.| |Futur.| |Practitioner|
      |claude-p| |claude-p| |claude-p| |claude-p| |claude -p  |
      +----+---+ +--+----+ ++------+ ++-----+ ++-----------+
           |        |        |       |       |
           +--------+--------+-------+-------+
                            |
                    +-------v-------+
                    |   Moderator   |
                    |   claude -p   |
                    +-------+-------+
                            |
                    +-------v-------+
                    |    Output     |
                    | (JSON/stream) |
                    +---------------+
```

Each perspective agent runs independently and can be parallelized. In the Bash version
they run as background jobs (`&`). In the Python version they run sequentially by default
(the sync SDK client), though you could wrap them in a `ThreadPoolExecutor` for true
parallelism.

The Moderator receives the concatenated JSON from all five perspectives and produces
either a streaming text synthesis or a structured JSON synthesis, depending on the
`--stream` flag.

---

## Part 1: Bash Version (`debate.sh`)

### 1.1 Setting Up Perspective Prompts

```bash
OPTIMIST="You are The Optimist. Focus on potential benefits, opportunities, and positive outcomes. Be enthusiastic but back up claims with reasoning."
SKEPTIC="You are The Skeptic. Identify risks, flaws, unintended consequences, and counterarguments. Be rigorous but fair."
HISTORIAN="You are The Historian. Draw parallels from history, cite precedents, and show what we can learn from similar past situations."
FUTURIST="You are The Futurist. Project long-term implications, emerging trends, and second-order effects. Think 10-50 years ahead."
PRACTITIONER="You are The Practitioner. Focus on real-world implementation, practical challenges, costs, and what actually works on the ground."
```

**Technique:** These strings are passed to `--append-system-prompt`, which adds them to
Claude's default system prompt rather than replacing it. This gives each agent a unique
persona while preserving Claude's baseline behavior (helpfulness, safety, tool awareness).

If you used `--system-prompt` instead, it would fully override the defaults -- usually not
what you want for persona injection.

**Reference:** [guides/automate-cli.md -- System Prompt Customization](../../guides/automate-cli.md)

### 1.2 Defining JSON Schemas

```bash
PERSPECTIVE_SCHEMA='{"type":"object","properties":{"perspective":{"type":"string"},"position":{"type":"string","description":"One-sentence thesis"},"arguments":{"type":"array","items":{"type":"string"},"description":"3 key arguments"},"evidence":{"type":"array","items":{"type":"string"},"description":"2 supporting points or examples"},"concession":{"type":"string","description":"One thing the other side gets right"}},"required":["perspective","position","arguments","evidence","concession"]}'
```

**Technique:** The `--json-schema` flag forces Claude to produce validated structured
output conforming to the provided JSON Schema. Every perspective agent uses the same
schema with five fields: `perspective`, `position`, `arguments`, `evidence`, and
`concession`. This ensures uniform output across all agents, making downstream aggregation
straightforward.

A second schema, `SYNTHESIS_SCHEMA`, defines the Moderator's output with fields for
`consensus_points`, `key_disagreements`, `synthesis`, and `verdict`.

**Reference:** [reference/json-schemas.md -- Structured Output](../../reference/json-schemas.md)

### 1.3 Parallel Execution

```bash
for NAME in optimist skeptic historian futurist practitioner; do
  PROMPT="${PERSPECTIVES_MAP[$NAME]}"
  claude -p "Analyze this topic from your unique perspective: $TOPIC" \
    --append-system-prompt "$PROMPT" \
    --output-format json \
    --json-schema "$PERSPECTIVE_SCHEMA" \
    --model "$MODEL" \
    --no-session-persistence \
    --tools "" \
    > "$TMPDIR/$NAME.json" &
done

wait
```

**Technique:** Bash `&` runs each `claude -p` call as a background job. The `wait`
builtin blocks until all five jobs complete. This is the simplest form of parallel agent
execution -- no framework, no queue, just the shell's built-in job control.

**Key flags per agent:**

| Flag | Purpose |
|------|---------|
| `--output-format json` | Returns a JSON object with `.result`, `.structured_output`, `.total_cost_usd` |
| `--json-schema` | Validates output against the schema; result lands in `.structured_output` |
| `--no-session-persistence` | Stateless -- no session file written to disk (critical for batch jobs) |
| `--tools ""` | Disables all tool access -- pure LLM reasoning, no file system or shell |
| `--model sonnet` | Model selection using the short alias (equivalent to `claude-sonnet-4-20250514`) |

**Reference:** [guides/automate-cli.md](../../guides/automate-cli.md), [reference/print-mode-flags.md](../../reference/print-mode-flags.md)

### 1.4 Collecting Structured Output

```bash
PERSPECTIVES=""
for f in "$TMPDIR"/*.json; do
  perspective=$(jq -r '.structured_output | tojson' "$f")
  PERSPECTIVES="$PERSPECTIVES\n$perspective"
done
```

**Technique:** When you use `--json-schema`, the validated data appears in the
`.structured_output` field of the JSON response. This is separate from `.result`, which
contains the free-text response. The `jq` command extracts the structured data and
re-serializes it for inclusion in the Moderator's prompt.

**Gotcha:** A common mistake is reading `.result` when you meant `.structured_output`.
The `.result` field still exists and contains text, but the schema-validated JSON is
always in `.structured_output`.

**Reference:** [reference/json-schemas.md -- CLI JSON Output](../../reference/json-schemas.md)

### 1.5 Moderator -- Streaming Mode

```bash
claude -p "$MODERATOR_PROMPT" \
  --append-system-prompt "You are a balanced, thoughtful moderator. Synthesize all perspectives fairly." \
  --output-format stream-json \
  --verbose \
  --include-partial-messages \
  --model "$MODEL" \
  --no-session-persistence \
  --tools "" | \
  while read -r line; do
    text=$(echo "$line" | jq -r 'select(.type=="assistant") | .message.content[-1].text // empty' 2>/dev/null)
    [ -n "$text" ] && printf "%s" "$text"
  done
```

**Technique:** The "holy trinity" of streaming flags:

1. `--output-format stream-json` -- emits NDJSON (one JSON object per line)
2. `--verbose` -- **required** for `stream-json` to work (this is a critical gotcha!)
3. `--include-partial-messages` -- enables token-level granularity

Without `--verbose`, `stream-json` will error or produce no events. Without
`--include-partial-messages`, you only receive complete messages (not incremental tokens).

The `while read` loop processes each NDJSON line, filtering for events where
`.type == "assistant"` and extracting the latest text content. The `printf "%s"` (no
newline) prints tokens as they arrive, producing a real-time streaming effect.

**Reference:** [reference/streaming-events.md -- CLI stream-json Events](../../reference/streaming-events.md)

### 1.6 Moderator -- Structured Mode

```bash
claude -p "$MODERATOR_PROMPT" \
  --append-system-prompt "You are a balanced, thoughtful moderator. Synthesize all perspectives fairly." \
  --output-format json \
  --json-schema "$SYNTHESIS_SCHEMA" \
  --model "$MODEL" \
  --no-session-persistence \
  --tools "" | jq '.structured_output'
```

Same pattern as the perspective agents, but with a different schema. The `SYNTHESIS_SCHEMA`
requires `topic`, `consensus_points`, `key_disagreements`, `synthesis`, and `verdict`
fields. The piped `jq '.structured_output'` extracts and pretty-prints the validated JSON.

### 1.7 Cost Tracking

```bash
total_cost=$(cat "$TMPDIR"/*.json | jq -s '[.[].total_cost_usd] | add')
echo "Total cost: \$$total_cost"
```

**Technique:** Every `--output-format json` response includes a `total_cost_usd` field.
The `jq -s` (slurp) flag reads all JSON files into an array, then `[.[].total_cost_usd] | add`
sums the costs across all five perspective agents.

Note: The streaming moderator does not produce a JSON response with cost data. Only the
perspective agents (run in structured JSON mode) contribute to this total.

---

## Part 2: Python Version (`debate.py`)

### 2.1 CC-Bridge Setup

```python
client = anthropic.Anthropic(api_key="dummy", base_url=args.base_url)
```

**Technique:** Point the official Anthropic Python SDK at a local CC-Bridge server. The
`api_key` can be any non-empty string -- the bridge does not validate it. Authentication
is handled by the local Claude CLI session that the bridge wraps.

**Prerequisite:** CC-Bridge must be running before you start the script. Start it in a
separate terminal with `./ccbridge --port 8321`.

**Reference:** [guides/integrate-sdk.md](../../guides/integrate-sdk.md), [guides/build-bridge.md](../../guides/build-bridge.md)

### 2.2 Perspective Calls

```python
def get_perspective(client, topic, name, system_prompt, model):
    message = client.messages.create(
        model=model,
        max_tokens=1024,
        system=system_prompt,
        messages=[{"role": "user", "content": f"Analyze this topic from your unique perspective: {topic}"}],
        output_format={"type": "json_schema", "schema": PERSPECTIVE_SCHEMA},
    )
    text = message.content[0].text
    return json.loads(text)
```

**Technique:** The SDK's `system` parameter maps to the bridge's `--append-system-prompt`
flag. The `output_format` parameter with `type: "json_schema"` maps to `--json-schema`.

**Key difference from Bash:** In the Python version, the structured JSON is returned
directly in `message.content[0].text` as a JSON string, which you parse with
`json.loads()`. There is no separate `.structured_output` field -- that is a CLI-specific
concept.

**Sequential execution:** The sync SDK client runs perspectives one at a time in a loop.
For true parallelism, wrap the calls in a `concurrent.futures.ThreadPoolExecutor`:

```python
from concurrent.futures import ThreadPoolExecutor

with ThreadPoolExecutor(max_workers=5) as pool:
    futures = {
        name: pool.submit(get_perspective, client, topic, name, prompt, model)
        for name, prompt in PERSPECTIVES.items()
    }
    perspectives = [f.result() for f in futures.values()]
```

### 2.3 Streaming Moderator

```python
with client.messages.stream(
    model=model,
    max_tokens=2048,
    system="You are a balanced, thoughtful moderator. Synthesize all perspectives fairly.",
    messages=[{"role": "user", "content": prompt}],
) as stream:
    for text in stream.text_stream:
        print(text, end="", flush=True)
```

**Technique:** The SDK's `.stream()` context manager and `.text_stream` iterator handle
all SSE parsing automatically. Under the hood, CC-Bridge translates this into
`--output-format stream-json --verbose`, but you never see the raw NDJSON -- the SDK
abstracts it away.

The `flush=True` is important: without it, Python buffers output and you lose the
real-time streaming effect.

**Reference:** [reference/streaming-events.md -- SSE Protocol](../../reference/streaming-events.md)

### 2.4 Structured Moderator

```python
message = client.messages.create(
    model=model,
    max_tokens=2048,
    system="You are a balanced, thoughtful moderator. Synthesize all perspectives fairly.",
    messages=[{"role": "user", "content": prompt}],
    output_format={"type": "json_schema", "schema": SYNTHESIS_SCHEMA},
)
result = json.loads(message.content[0].text)
print(json.dumps(result, indent=2))
```

Same pattern as the perspective calls -- uses `output_format` with the synthesis schema,
then parses the JSON text response. The `json.dumps(result, indent=2)` pretty-prints the
final synthesis to stdout.

---

## Comparison

| Aspect | Bash (`debate.sh`) | Python (`debate.py`) |
|--------|-------------------|---------------------|
| **Dependencies** | None (just Claude CLI + jq) | `anthropic` pip package + CC-Bridge |
| **Parallel execution** | Native (`&` + `wait`) | Sequential (or `ThreadPoolExecutor`) |
| **Streaming** | Manual NDJSON parsing | SDK handles it (`stream.text_stream`) |
| **JSON extraction** | `jq '.structured_output'` | `json.loads(message.content[0].text)` |
| **Error handling** | Minimal (`set -euo pipefail`) | Python exceptions + try/except |
| **Cost tracking** | Built-in (`total_cost_usd` field) | Not available via SDK response |
| **Model names** | Short aliases (`sonnet`) | Full identifiers (`claude-sonnet-4-20250514`) |
| **Best for** | Scripts, CI/CD, quick experiments | Applications, larger projects |

**When to use which:** Use Bash for quick automation, pipelines, and CI/CD where you want
zero dependencies. Use Python when building applications, when you need better error
handling and composability, or when you are already working in a Python codebase.

---

## cc-cli-skill Techniques Demonstrated

This table maps every technique used in the debate engine back to the cc-cli-skill skill
reference files.

| Technique | Bash Flag / Pattern | Python SDK Equivalent | cc-cli-skill Reference |
|-----------|--------------------|-----------------------|-----------------|
| Non-interactive mode | `claude -p` | SDK `client.messages.create()` | [SKILL.md](../../SKILL.md) |
| System prompts | `--append-system-prompt` | `system=` parameter | [guides/automate-cli.md](../../guides/automate-cli.md) |
| JSON output | `--output-format json` | Default SDK response | [reference/print-mode-flags.md](../../reference/print-mode-flags.md) |
| Structured output | `--json-schema` | `output_format={"type": "json_schema", ...}` | [reference/json-schemas.md](../../reference/json-schemas.md) |
| Streaming | `--output-format stream-json --verbose` | `client.messages.stream()` | [reference/streaming-events.md](../../reference/streaming-events.md) |
| Token streaming | `--include-partial-messages` | `stream.text_stream` | [reference/streaming-events.md](../../reference/streaming-events.md) |
| Model selection | `--model sonnet` | `model=` parameter | [reference/print-mode-flags.md](../../reference/print-mode-flags.md) |
| Stateless mode | `--no-session-persistence` | N/A (bridge handles it) | [guides/automate-cli.md](../../guides/automate-cli.md) |
| Disable tools | `--tools ""` | N/A | [guides/automate-cli.md](../../guides/automate-cli.md) |
| Parallel agents | `&` + `wait` | `ThreadPoolExecutor` | [reference/code-snippets.md](../../reference/code-snippets.md) |
| CC-Bridge SDK | N/A | `base_url="http://localhost:8321"` | [guides/integrate-sdk.md](../../guides/integrate-sdk.md) |

---

## Running It Yourself

### Bash Version

```bash
# Prerequisites: Claude CLI installed and authenticated
claude auth status

# Run with structured JSON output (default)
./debate.sh "Should social media be regulated?"

# Run with streaming synthesis
./debate.sh --stream "Is remote work better than office work?"

# Use a cheaper model for testing
./debate.sh --model haiku "Quick test topic"
```

### Python Version

```bash
# Prerequisites: CC-Bridge running + anthropic package installed
pip install anthropic

# Start CC-Bridge in another terminal (see guides/build-bridge.md)
./ccbridge --port 8321

# Run with structured JSON output (default)
python debate.py "Should social media be regulated?"

# Run with streaming synthesis
python debate.py --stream "Is remote work better than office work?"

# Point at a different bridge URL
python debate.py --base-url http://localhost:9000 "Some topic"
```

### Expected Cost

- 5 perspective agents + 1 moderator = 6 `claude -p` calls per debate
- With Sonnet: approximately $0.70-1.00 per debate
- With Haiku: approximately $0.10-0.15 per debate
- Use `--max-budget-usd` on individual agents if you want to cap costs (see [guides/automate-cli.md](../../guides/automate-cli.md))
