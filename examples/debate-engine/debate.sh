#!/usr/bin/env bash
# ============================================================================
# Multi-Perspective Debate Engine
# ============================================================================
# Spawns 5 parallel AI "debaters" with distinct perspectives using claude -p,
# then a moderator synthesizes the debate into a balanced analysis.
#
# Usage:
#   ./debate.sh "Should AI replace teachers?"           # structured JSON output
#   ./debate.sh --stream "Should AI replace teachers?"   # streaming moderator
#   ./debate.sh --model haiku "Quick topic"              # use a specific model
# ============================================================================
set -euo pipefail

# --- Argument Parsing -------------------------------------------------------

STREAM=false
MODEL="sonnet"
TOPIC=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stream)
      STREAM=true
      shift
      ;;
    --model)
      MODEL="$2"
      shift 2
      ;;
    *)
      TOPIC="$1"
      shift
      ;;
  esac
done

if [[ -z "$TOPIC" ]]; then
  echo "Usage: ./debate.sh [--stream] [--model MODEL] \"TOPIC\""
  echo ""
  echo "Options:"
  echo "  --stream    Stream the moderator's synthesis in real time"
  echo "  --model     Model to use (default: sonnet)"
  echo ""
  echo "Example:"
  echo "  ./debate.sh \"Should AI replace teachers?\""
  exit 1
fi

echo ""
echo "============================================"
echo "  MULTI-PERSPECTIVE DEBATE ENGINE"
echo "============================================"
echo "  Topic: $TOPIC"
echo "  Model: $MODEL"
echo "  Stream: $STREAM"
echo "============================================"
echo ""

# --- Perspective System Prompts ----------------------------------------------

OPTIMIST="You are The Optimist. Focus on potential benefits, opportunities, and positive outcomes. Be enthusiastic but back up claims with reasoning."
SKEPTIC="You are The Skeptic. Identify risks, flaws, unintended consequences, and counterarguments. Be rigorous but fair."
HISTORIAN="You are The Historian. Draw parallels from history, cite precedents, and show what we can learn from similar past situations."
FUTURIST="You are The Futurist. Project long-term implications, emerging trends, and second-order effects. Think 10-50 years ahead."
PRACTITIONER="You are The Practitioner. Focus on real-world implementation, practical challenges, costs, and what actually works on the ground."

# --- JSON Schemas ------------------------------------------------------------

PERSPECTIVE_SCHEMA='{"type":"object","properties":{"perspective":{"type":"string"},"position":{"type":"string","description":"One-sentence thesis"},"arguments":{"type":"array","items":{"type":"string"},"description":"3 key arguments"},"evidence":{"type":"array","items":{"type":"string"},"description":"2 supporting points or examples"},"concession":{"type":"string","description":"One thing the other side gets right"}},"required":["perspective","position","arguments","evidence","concession"]}'

SYNTHESIS_SCHEMA='{"type":"object","properties":{"topic":{"type":"string"},"consensus_points":{"type":"array","items":{"type":"string"},"description":"Points most perspectives agree on"},"key_disagreements":{"type":"array","items":{"type":"string"},"description":"Main points of contention"},"synthesis":{"type":"string","description":"Balanced 2-3 paragraph analysis"},"verdict":{"type":"string","description":"Nuanced one-paragraph conclusion"}},"required":["topic","consensus_points","key_disagreements","synthesis","verdict"]}'

# --- Temp Directory ----------------------------------------------------------

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# --- Launch 5 Parallel Perspective Agents ------------------------------------

echo "Launching debaters..."
echo ""

declare -A PERSPECTIVES_MAP
PERSPECTIVES_MAP=(
  [optimist]="$OPTIMIST"
  [skeptic]="$SKEPTIC"
  [historian]="$HISTORIAN"
  [futurist]="$FUTURIST"
  [practitioner]="$PRACTITIONER"
)

for NAME in optimist skeptic historian futurist practitioner; do
  PROMPT="${PERSPECTIVES_MAP[$NAME]}"
  echo "  Spawning $NAME agent..."
  claude -p "Analyze this topic from your unique perspective: $TOPIC" \
    --append-system-prompt "$PROMPT" \
    --output-format json \
    --json-schema "$PERSPECTIVE_SCHEMA" \
    --model "$MODEL" \
    --no-session-persistence \
    --max-budget-usd 0.30 \
    --tools "" \
    > "$TMPDIR/$NAME.json" &
done

echo ""
echo "Waiting for all perspectives..."
wait
echo "All perspectives collected."
echo ""

# --- Collect Perspectives ----------------------------------------------------

PERSPECTIVES=""
for f in "$TMPDIR"/*.json; do
  perspective=$(jq -r '.structured_output | tojson' "$f")
  PERSPECTIVES="$PERSPECTIVES\n$perspective"
done

# --- Build Moderator Prompt --------------------------------------------------

MODERATOR_PROMPT="You are The Moderator. You have received arguments from 5 different perspectives on the topic: '$TOPIC'.

Here are their positions:

$PERSPECTIVES

Synthesize these viewpoints into a balanced analysis. Identify areas of consensus, key disagreements, and provide a nuanced verdict."

# --- Run Moderator -----------------------------------------------------------

if [[ "$STREAM" == true ]]; then
  # Streaming mode: print synthesis in real time
  echo ""
  echo "======================================="
  echo "  MODERATOR'S SYNTHESIS (streaming)"
  echo "======================================="
  echo ""
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
  echo ""
else
  # Structured mode: output full JSON synthesis
  echo ""
  echo "======================================="
  echo "  MODERATOR'S SYNTHESIS"
  echo "======================================="
  echo ""
  claude -p "$MODERATOR_PROMPT" \
    --append-system-prompt "You are a balanced, thoughtful moderator. Synthesize all perspectives fairly." \
    --output-format json \
    --json-schema "$SYNTHESIS_SCHEMA" \
    --model "$MODEL" \
    --no-session-persistence \
    --tools "" | jq '.structured_output'
fi

# --- Cost Summary ------------------------------------------------------------

total_cost=$(cat "$TMPDIR"/*.json | jq -s '[.[].total_cost_usd] | add')
echo ""
echo "Total cost: \$$total_cost"
