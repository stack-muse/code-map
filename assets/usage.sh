#!/usr/bin/env bash
# usage.sh — token usage / cost estimate for the current Claude Code session.
#
# Usage:
#   usage.sh start            -> prints a start marker (ISO8601 UTC timestamp) to stdout
#   usage.sh <start-marker>   -> prints a "## Run cost" markdown table covering everything
#                                 logged (main session + subagents) since that marker
#
# Source of truth: this project's own session transcript under
#   ~/.claude/projects/<encoded-cwd>/*.jsonl
# Each assistant-turn line (main session or subagent/sidechain) carries a "usage" object
# with input/output/cache token counts and the model name, so summing lines with a
# timestamp >= the start marker gives the run's usage.
set -euo pipefail

MODE="${1:-}"

if [[ -z "$MODE" ]]; then
  echo "usage: usage.sh start | usage.sh <start-marker>" >&2
  exit 1
fi

if [[ "$MODE" == "start" ]]; then
  date -u +%Y-%m-%dT%H:%M:%S.000Z
  exit 0
fi

START_MARKER="$MODE"

encode_cwd() {
  # Claude Code's on-disk project-dir convention: replace path separators with "-".
  printf '%s' "$1" | sed 's/\//-/g'
}

PROJECT_DIR_NAME="$(encode_cwd "$PWD")"
TRANSCRIPT_DIR="$HOME/.claude/projects/${PROJECT_DIR_NAME}"

if [[ ! -d "$TRANSCRIPT_DIR" ]]; then
  echo "Usage data is not available: no transcript directory found at $TRANSCRIPT_DIR."
  exit 0
fi

shopt -s nullglob
FILES=("$TRANSCRIPT_DIR"/*.jsonl)
shopt -u nullglob

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "Usage data is not available: no session transcripts found under $TRANSCRIPT_DIR."
  exit 0
fi

python3 - "$START_MARKER" "${FILES[@]}" <<'PYEOF'
import sys, json, datetime

start_marker = sys.argv[1]
files = sys.argv[2:]

def parse_ts(ts):
    try:
        return datetime.datetime.strptime(ts, "%Y-%m-%dT%H:%M:%S.%fZ")
    except ValueError:
        try:
            return datetime.datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ")
        except ValueError:
            return None

start_dt = parse_ts(start_marker)
if start_dt is None:
    print("Usage data is not available: could not parse start marker '%s'." % start_marker)
    sys.exit(0)

# Approximate Anthropic API list prices, USD per million tokens.
# (input, output, cache_write, cache_read) — cache_write assumed at the
# 5-minute ephemeral rate (~1.25x input); this is an estimate, not a bill.
PRICING = {
    "opus":   (15.00, 75.00, 18.75, 1.50),
    "sonnet": (3.00,  15.00, 3.75,  0.30),
    "haiku":  (0.80,  4.00,  1.00,  0.08),
}

def price_for(model):
    m = (model or "").lower()
    for key, prices in PRICING.items():
        if key in m:
            return prices
    return None

totals = {}   # model -> dict of token counters
found_any = False

for path in files:
    try:
        f = open(path, "r", encoding="utf-8")
    except OSError:
        continue
    with f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            if rec.get("type") != "assistant":
                continue
            ts = rec.get("timestamp")
            dt = parse_ts(ts) if ts else None
            if dt is None or dt < start_dt:
                continue
            msg = rec.get("message") or {}
            usage = msg.get("usage")
            model = msg.get("model")
            if not usage or not model:
                continue
            found_any = True
            t = totals.setdefault(model, {"input": 0, "output": 0, "cache_write": 0, "cache_read": 0})
            t["input"] += usage.get("input_tokens", 0) or 0
            t["output"] += usage.get("output_tokens", 0) or 0
            t["cache_write"] += usage.get("cache_creation_input_tokens", 0) or 0
            t["cache_read"] += usage.get("cache_read_input_tokens", 0) or 0

if not found_any:
    print("Usage data is not available: no assistant turns found at or after the start marker.")
    sys.exit(0)

print("## Run cost\n")
print("| Model | Input | Output | Cache write | Cache read | Est. cost (USD) |")
print("|---|---:|---:|---:|---:|---:|")

grand_total = 0.0
any_priced = False
for model, t in sorted(totals.items()):
    prices = price_for(model)
    if prices:
        any_priced = True
        pin, pout, pcw, pcr = prices
        cost = (t["input"] * pin + t["output"] * pout + t["cache_write"] * pcw + t["cache_read"] * pcr) / 1_000_000
        grand_total += cost
        cost_str = f"${cost:,.4f}"
    else:
        cost_str = "not priced"
    print(f"| {model} | {t['input']:,} | {t['output']:,} | {t['cache_write']:,} | {t['cache_read']:,} | {cost_str} |")

if any_priced:
    print(f"\n**Total (estimate): ${grand_total:,.4f}**")
else:
    print("\n**Total (estimate): not available — no known model pricing matched.**")

print("\n_Estimate at API list prices from the session transcript; it does not reflect subscription plans, discounts, or actual billing._")
PYEOF
