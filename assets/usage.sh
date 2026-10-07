#!/usr/bin/env bash
# usage.sh — token usage / cost estimate for the current agent session.
#
# Usage:
#   usage.sh [--agent claude|codex|cursor] start
#       -> prints a start marker (ISO8601 UTC timestamp) to stdout
#   usage.sh [--agent claude|codex|cursor] <start-marker>
#       -> prints a "## Run cost" markdown table covering everything logged since that marker
#
# --agent defaults to claude. Sources of truth:
#   claude: this project's session transcripts under ~/.claude/projects/<encoded-cwd>/*.jsonl.
#           Each assistant-turn line (main session or subagent/sidechain) carries a "usage"
#           object with input/output/cache token counts and the model name.
#   codex:  session rollouts under ~/.codex/sessions/**/rollout-*.jsonl. "token_count" events
#           carry a cumulative total_token_usage; the run's usage is the last total after the
#           marker minus the last total before it, per session file.
#   cursor: no local per-run usage is available; prints a one-line notice.
set -euo pipefail

AGENT="claude"
if [[ "${1:-}" == "--agent" ]]; then
  AGENT="${2:-}"
  shift 2 || true
fi

MODE="${1:-}"

case "$AGENT" in
  claude|codex) ;;
  cursor)
    echo "Usage data is not available for Cursor: it does not expose per-run token usage locally."
    exit 0
    ;;
  *)
    echo "usage.sh: unknown agent '$AGENT' (expected claude, codex or cursor)" >&2
    exit 1
    ;;
esac

if [[ -z "$MODE" ]]; then
  echo "usage: usage.sh [--agent claude|codex|cursor] start | usage.sh [--agent claude|codex|cursor] <start-marker>" >&2
  exit 1
fi

if [[ "$MODE" == "start" ]]; then
  date -u +%Y-%m-%dT%H:%M:%S.000Z
  exit 0
fi

START_MARKER="$MODE"

if [[ "$AGENT" == "claude" ]]; then
  PROJECTS_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"

  encode_cwd() {
    # Claude Code's on-disk project-dir convention: every character other than a
    # letter or digit becomes "-" (so "/a b/c.d" -> "-a-b-c-d").
    printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'
  }

  TRANSCRIPT_DIR="$PROJECTS_DIR/$(encode_cwd "$PWD")"

  if [[ ! -d "$TRANSCRIPT_DIR" ]]; then
    # Fallback for names the rule above does not reproduce (e.g. very long paths):
    # find a transcript whose recorded cwd is this directory.
    match="$(find "$PROJECTS_DIR" -mindepth 2 -maxdepth 2 -name '*.jsonl' -exec grep -lF "\"cwd\":\"$PWD\"" {} + 2>/dev/null | head -1 || true)"
    [[ -n "$match" ]] && TRANSCRIPT_DIR="$(dirname "$match")"
  fi

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
else
  # Codex keeps every session it has ever run, so the rollout files are listed inside
  # Python rather than passed as arguments (which could exceed the argument-length limit).
  SESSIONS_DIR="${CODEX_HOME:-$HOME/.codex}/sessions"
  if [[ ! -d "$SESSIONS_DIR" ]]; then
    echo "Usage data is not available: no Codex session rollouts found under $SESSIONS_DIR."
    exit 0
  fi
  FILES=("$SESSIONS_DIR")
fi

python3 - "$AGENT" "$START_MARKER" "${FILES[@]}" <<'PYEOF'
import sys, json, datetime, os

agent = sys.argv[1]
start_marker = sys.argv[2]
files = sys.argv[3:]

if agent == "codex":
    sessions_dir = files[0]
    files = []
    for root, _, names in os.walk(sessions_dir):
        files.extend(os.path.join(root, n) for n in names
                     if n.startswith("rollout-") and n.endswith(".jsonl"))
    if not files:
        print("Usage data is not available: no Codex session rollouts found under %s." % sessions_dir)
        sys.exit(0)

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

def records(path):
    try:
        f = open(path, "r", encoding="utf-8")
    except OSError:
        return
    with f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue

def add(model, inp, out, cache_write, cache_read):
    t = totals.setdefault(model, {"input": 0, "output": 0, "cache_write": 0, "cache_read": 0})
    t["input"] += inp
    t["output"] += out
    t["cache_write"] += cache_write
    t["cache_read"] += cache_read

def collect_claude(path):
    global found_any
    for rec in records(path):
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
        add(model,
            usage.get("input_tokens", 0) or 0,
            usage.get("output_tokens", 0) or 0,
            usage.get("cache_creation_input_tokens", 0) or 0,
            usage.get("cache_read_input_tokens", 0) or 0)

def collect_codex(path):
    # token_count totals are cumulative per session, so the run's usage is the last
    # total after the marker minus the last total before it.
    global found_any
    if datetime.datetime.fromtimestamp(os.path.getmtime(path), datetime.timezone.utc).replace(tzinfo=None) < start_dt:
        return
    model = "codex (model not recorded)"
    before = after = None
    for rec in records(path):
        payload = rec.get("payload") or {}
        if rec.get("type") == "turn_context" and payload.get("model"):
            model = payload["model"]
            continue
        if payload.get("type") != "token_count":
            continue
        total = (payload.get("info") or {}).get("total_token_usage")
        ts = rec.get("timestamp")
        dt = parse_ts(ts) if ts else None
        if not total or dt is None:
            continue
        if dt < start_dt:
            before = total
        else:
            after = total
    if after is None:
        return
    def delta(key):
        return max((after.get(key, 0) or 0) - ((before or {}).get(key, 0) or 0), 0)
    cached = delta("cached_input_tokens")
    found_any = True
    # OpenAI input_tokens includes the cached part; report it separately as cache read.
    add(model, max(delta("input_tokens") - cached, 0), delta("output_tokens"), 0, cached)

for path in files:
    if agent == "codex":
        collect_codex(path)
    else:
        collect_claude(path)

if not found_any:
    print("Usage data is not available: no %s found at or after the start marker." % ("Codex token counts" if agent == "codex" else "assistant turns"))
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
