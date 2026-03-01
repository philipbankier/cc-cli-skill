#!/usr/bin/env python3
"""
Multi-Perspective Debate Engine (Python + CC-Bridge)

Spawns 5 AI debaters with distinct perspectives, then a moderator
synthesizes the debate. Uses the Anthropic SDK pointed at a local
CC-Bridge server.

Requires:
  - CC-Bridge running (default: http://localhost:8321)
  - pip install anthropic
"""

import argparse
import asyncio
import json
import sys
import anthropic


# --- Perspectives ---

PERSPECTIVES = {
    "optimist": "You are The Optimist. Focus on potential benefits, opportunities, and positive outcomes. Be enthusiastic but back up claims with reasoning.",
    "skeptic": "You are The Skeptic. Identify risks, flaws, unintended consequences, and counterarguments. Be rigorous but fair.",
    "historian": "You are The Historian. Draw parallels from history, cite precedents, and show what we can learn from similar past situations.",
    "futurist": "You are The Futurist. Project long-term implications, emerging trends, and second-order effects. Think 10-50 years ahead.",
    "practitioner": "You are The Practitioner. Focus on real-world implementation, practical challenges, costs, and what actually works on the ground.",
}


# --- JSON Schemas ---

PERSPECTIVE_SCHEMA = {
    "type": "object",
    "properties": {
        "perspective": {"type": "string"},
        "position": {"type": "string", "description": "One-sentence thesis"},
        "arguments": {"type": "array", "items": {"type": "string"}, "description": "3 key arguments"},
        "evidence": {"type": "array", "items": {"type": "string"}, "description": "2 supporting points"},
        "concession": {"type": "string", "description": "One thing the other side gets right"},
    },
    "required": ["perspective", "position", "arguments", "evidence", "concession"],
}

SYNTHESIS_SCHEMA = {
    "type": "object",
    "properties": {
        "topic": {"type": "string"},
        "consensus_points": {"type": "array", "items": {"type": "string"}},
        "key_disagreements": {"type": "array", "items": {"type": "string"}},
        "synthesis": {"type": "string", "description": "Balanced 2-3 paragraph analysis"},
        "verdict": {"type": "string", "description": "Nuanced one-paragraph conclusion"},
    },
    "required": ["topic", "consensus_points", "key_disagreements", "synthesis", "verdict"],
}


# --- Core Functions ---

def get_perspective(client, topic, name, system_prompt, model):
    """Get a single perspective's structured response."""
    print(f"  Spawning {name} agent...", file=sys.stderr)
    message = client.messages.create(
        model=model,
        max_tokens=1024,
        system=system_prompt,
        messages=[{"role": "user", "content": f"Analyze this topic from your unique perspective: {topic}"}],
        output_format={"type": "json_schema", "schema": PERSPECTIVE_SCHEMA},
    )
    # Extract the JSON from the text response
    text = message.content[0].text
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return {"perspective": name, "position": text, "arguments": [], "evidence": [], "concession": ""}


def run_moderator_streaming(client, topic, perspectives, model):
    """Run the moderator with streaming output."""
    perspectives_text = "\n\n".join(json.dumps(p, indent=2) for p in perspectives)
    prompt = f"""You have received arguments from 5 different perspectives on: '{topic}'

Here are their positions:

{perspectives_text}

Synthesize these viewpoints into a balanced analysis. Identify areas of consensus, key disagreements, and provide a nuanced verdict."""

    print("\n═══════════════════════════════════════", file=sys.stderr)
    print("  MODERATOR'S SYNTHESIS (streaming)", file=sys.stderr)
    print("═══════════════════════════════════════\n", file=sys.stderr)

    with client.messages.stream(
        model=model,
        max_tokens=2048,
        system="You are a balanced, thoughtful moderator. Synthesize all perspectives fairly.",
        messages=[{"role": "user", "content": prompt}],
    ) as stream:
        for text in stream.text_stream:
            print(text, end="", flush=True)
    print()


def run_moderator_structured(client, topic, perspectives, model):
    """Run the moderator with structured JSON output."""
    perspectives_text = "\n\n".join(json.dumps(p, indent=2) for p in perspectives)
    prompt = f"""You have received arguments from 5 different perspectives on: '{topic}'

Here are their positions:

{perspectives_text}

Synthesize these viewpoints into a balanced analysis."""

    message = client.messages.create(
        model=model,
        max_tokens=2048,
        system="You are a balanced, thoughtful moderator. Synthesize all perspectives fairly.",
        messages=[{"role": "user", "content": prompt}],
        output_format={"type": "json_schema", "schema": SYNTHESIS_SCHEMA},
    )
    text = message.content[0].text
    try:
        result = json.loads(text)
    except json.JSONDecodeError:
        result = {"topic": topic, "synthesis": text, "verdict": "", "consensus_points": [], "key_disagreements": []}
    print(json.dumps(result, indent=2))


def main():
    parser = argparse.ArgumentParser(description="Multi-Perspective Debate Engine (CC-Bridge)")
    parser.add_argument("topic", help="The debate topic or question")
    parser.add_argument("--stream", action="store_true", help="Stream the moderator's synthesis")
    parser.add_argument("--model", default="claude-sonnet-4-20250514", help="Model to use")
    parser.add_argument("--base-url", default="http://localhost:8321", help="CC-Bridge URL")
    args = parser.parse_args()

    client = anthropic.Anthropic(api_key="dummy", base_url=args.base_url)

    print(f"\n🎭 Multi-Perspective Debate Engine", file=sys.stderr)
    print(f"   Topic: {args.topic}", file=sys.stderr)
    print(f"   Model: {args.model}", file=sys.stderr)
    print(f"   Bridge: {args.base_url}\n", file=sys.stderr)

    # --- Phase 1: Gather perspectives (sequential since SDK client is sync) ---
    # Note: For true parallelism, use ThreadPoolExecutor or httpx async client
    print("Phase 1: Gathering perspectives...", file=sys.stderr)
    perspectives = []
    for name, system_prompt in PERSPECTIVES.items():
        result = get_perspective(client, args.topic, name, system_prompt, args.model)
        perspectives.append(result)
    print(f"\n  All {len(perspectives)} perspectives collected.\n", file=sys.stderr)

    # --- Phase 2: Moderator synthesis ---
    print("Phase 2: Moderator synthesizing...", file=sys.stderr)
    if args.stream:
        run_moderator_streaming(client, args.topic, perspectives, args.model)
    else:
        run_moderator_structured(client, args.topic, perspectives, args.model)


if __name__ == "__main__":
    main()
