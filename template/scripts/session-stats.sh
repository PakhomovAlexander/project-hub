#!/usr/bin/env bash
# session-stats.sh — where does the agent harness actually cost this hub?
#
# Parses this project's LOCAL Claude Code transcripts (<config-dir>/projects/<slug>/,
# where <config-dir> is $CLAUDE_CONFIG_DIR, ~/.claude, or ~/.config/claude)
# and prints aggregate numbers: requests + peak context + span per session, spend
# decomposition (cache read / cache write / output / fresh input), cost by context
# band, idle-resume cache rewrites, permission-gate hit rate with a read-only vs
# mutating split, tool-error classes, and repeated identical Bash commands. Use it
# to decide which harness knobs are worth turning — and to check, after a change,
# whether the change helped.
#
#   scripts/session-stats.sh                 # this checkout's transcripts
#   scripts/session-stats.sh <dir|file>...   # explicit transcript dirs / .jsonl files
#                                            # (worktrees log under their own path slug)
#
# Reads transcripts, prints aggregates, writes nothing, uploads nothing. The
# transcript format is an undocumented Claude Code internal that shifts between
# versions — treat the numbers as approximate, and expect a parse-failure count
# when the format drifts. Sessions from other agents/harnesses aren't covered.
# Needs python3 (stdlib only).
set -u

HUB="$(cd -- "$(dirname -- "$0")/.." >/dev/null 2>&1 && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "session-stats: python3 is required" >&2; exit 2; }

if [ "$#" -eq 0 ]; then
  slug="$(printf '%s' "$HUB" | tr '/.' '--')"
  default_dir=""
  for base in "${CLAUDE_CONFIG_DIR:-}" "$HOME/.claude" "$HOME/.config/claude"; do
    if [ -n "$base" ] && [ -d "$base/projects/$slug" ]; then
      default_dir="$base/projects/$slug"
      break
    fi
  done
  if [ -z "$default_dir" ]; then
    echo "session-stats: no transcripts found for this checkout (projects/$slug)" >&2
    echo "  Looked under: \$CLAUDE_CONFIG_DIR, ~/.claude, ~/.config/claude." >&2
    echo "  Worktrees and moved checkouts log under their own path slug — pass the dir:" >&2
    echo "    scripts/session-stats.sh <config-dir>/projects/<slug>" >&2
    exit 1
  fi
  set -- "$default_dir"
fi

exec python3 - "$HUB/.claude/hooks/ask-before-risky-commands.sh" "$@" <<'PY'
import json, os, re, statistics, sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except AttributeError:
    pass

hook_path, targets = sys.argv[1], sys.argv[2:]

# ---- transcript files -----------------------------------------------------------
files = []
for t in targets:
    if os.path.isdir(t):
        files += sorted(os.path.join(t, f) for f in os.listdir(t) if f.endswith(".jsonl"))
    elif os.path.isfile(t):
        files.append(t)
    else:
        print(f"session-stats: skipping (not found): {t}", file=sys.stderr)
files = [f for f in files if os.path.getsize(f) > 0]
if not files:
    print("session-stats: no .jsonl transcripts found", file=sys.stderr)
    sys.exit(1)

# ---- gate families: read the hub's own watchlist so the stats match the gate ----
DEFAULT_FAMILIES = "aws|gcloud|az|kubectl|helm|terraform|terragrunt"
families = DEFAULT_FAMILIES
try:
    with open(hook_path, encoding="utf-8", errors="replace") as fh:
        m = re.search(r'^RISKY_WORDS="([^"]+)"', fh.read(), re.M)
        if m:
            families = m.group(1)
except OSError:
    pass
fam_re = re.compile(r"(?<![\w./-])(?:%s)(?![\w-])" % "|".join(map(re.escape, families.split("|"))))
# Verb heuristics for the split (regex-classified — treat the split as ±10%).
MUT_RE = re.compile(
    r"(?<![\w-])(delete|destroy|apply|create|scale|patch|edit|drain|cordon|uncordon|taint"
    r"|rollout|restart|upgrade|install|uninstall|rollback|import|rm|mv|cp|sync|exec|attach"
    r"|label|annotate|expose|terminate|reboot|start|stop|kill|push|put|set"
    r"|create-[\w-]+|delete-[\w-]+|update-[\w-]+|put-[\w-]+|terminate-[\w-]+)(?![\w-])")
RO_RE = re.compile(
    r"(?<![\w-])(get|describe|list|ls|show|status|plan|template|output|validate|fmt|graph"
    r"|providers|logs|top|explain|history|search|version|diff|api-resources|can-i|wait"
    r"|get-[\w-]+|describe-[\w-]+|list-[\w-]+|head-[\w-]+)(?![\w-])|--dry-run")

ERROR_CLASSES = [
    ("file-not-read (Read before Edit/Write)", re.compile(r"has not been read yet", re.I)),
    ("edit-string-mismatch", re.compile(r"(string to replace|old_string|not found in file)", re.I)),
    ("timeout", re.compile(r"timed out", re.I)),
    ("permissions", re.compile(r"(permission denied|eacces|eperm|operation not permitted)", re.I)),
    ("missing path", re.compile(r"(no such file|does not exist|not a directory)", re.I)),
    ("rejected / aborted by user", re.compile(r"(doesn.t want to proceed|aborted|interrupt|rejected)", re.I)),
]

TS_RE = re.compile(r"(.*T\d\d:\d\d:\d\d)(\.\d+)?(.*)$")
def parse_ts(s):
    from datetime import datetime
    if not isinstance(s, str) or "T" not in s:
        return None
    s = s.strip()
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    m = TS_RE.match(s)
    if m:
        s = m.group(1) + (m.group(2) or "")[:7] + (m.group(3) or "")
    try:
        return datetime.fromisoformat(s).timestamp()
    except ValueError:
        return None

def n(x):
    return x if isinstance(x, int) else 0

BANDS = [(100_000, "<100k"), (200_000, "100–200k"), (400_000, "200–400k"),
         (600_000, "400–600k"), (float("inf"), "≥600k")]
# Cost in base-price units, relative to fresh input for the same model:
# cache write 1.25x, cache read 0.1x, output 5x. Model-independent ratios.
def cost(inp, cw, cr, out):
    return inp + 1.25 * cw + 0.1 * cr + 5.0 * out

sessions = []            # per non-agent file: dict of stats
tot = dict(inp=0, cw=0, cr=0, out=0)
band_req = {}; band_cost = {}
idle = dict(count=0, cw=0); nonidle = dict(count=0, cw=0)
side_requests = 0
tool_calls = 0
bash_cmds = {}           # command -> count
gate_hits = dict(ro=0, mut=0, unk=0)
bash_total = 0
err_class = {}; err_total = 0
human_turns = 0
parse_fail = 0

for path in files:
    base = os.path.basename(path)
    is_agent_file = base.startswith("agent-")
    s = dict(id=base[:8], req=0, side=0, peak=0, first=None, last=None, humans=0)
    prev_ts = None
    with open(path, encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            raw = raw.strip()
            if not raw:
                continue
            try:
                obj = json.loads(raw)
            except ValueError:
                parse_fail += 1
                continue
            typ = obj.get("type")
            sidechain = is_agent_file or obj.get("isSidechain") is True
            ts = parse_ts(obj.get("timestamp"))
            if ts is not None:
                s["first"] = ts if s["first"] is None else min(s["first"], ts)
                s["last"] = ts if s["last"] is None else max(s["last"], ts)
            msg = obj.get("message") or {}
            content = msg.get("content")

            if typ == "assistant":
                u = msg.get("usage") or {}
                inp, cw = n(u.get("input_tokens")), n(u.get("cache_creation_input_tokens"))
                cr, out = n(u.get("cache_read_input_tokens")), n(u.get("output_tokens"))
                ctx = inp + cw + cr
                tot["inp"] += inp; tot["cw"] += cw; tot["cr"] += cr; tot["out"] += out
                c = cost(inp, cw, cr, out)
                for lim, name in BANDS:
                    if ctx < lim:
                        band_req[name] = band_req.get(name, 0) + 1
                        band_cost[name] = band_cost.get(name, 0.0) + c
                        break
                if sidechain:
                    s["side"] += 1; side_requests += 1
                else:
                    s["req"] += 1
                    s["peak"] = max(s["peak"], ctx)
                    if ts is not None:
                        if prev_ts is not None:
                            bucket = idle if ts - prev_ts > 3600 else nonidle
                            bucket["count"] += 1; bucket["cw"] += cw
                        prev_ts = ts
                if isinstance(content, list):
                    for item in content:
                        if not isinstance(item, dict) or item.get("type") != "tool_use":
                            continue
                        tool_calls += 1
                        if item.get("name") == "Bash":
                            cmd = (item.get("input") or {}).get("command")
                            if isinstance(cmd, str) and cmd:
                                bash_total += 1
                                bash_cmds[cmd] = bash_cmds.get(cmd, 0) + 1
                                if fam_re.search(cmd):
                                    if MUT_RE.search(cmd):
                                        gate_hits["mut"] += 1
                                    elif RO_RE.search(cmd):
                                        gate_hits["ro"] += 1
                                    else:
                                        gate_hits["unk"] += 1

            elif typ == "user" and not obj.get("isMeta"):
                if isinstance(content, str):
                    if not sidechain and content and not content.startswith(("<", "Caveat:")):
                        human_turns += 1; s["humans"] += 1
                elif isinstance(content, list):
                    has_result = False; has_text = False; text = ""
                    for item in content:
                        if not isinstance(item, dict):
                            continue
                        if item.get("type") == "tool_result":
                            has_result = True
                            if item.get("is_error"):
                                err_total += 1
                                body = item.get("content")
                                if isinstance(body, list):
                                    body = " ".join(str(p.get("text", "")) for p in body
                                                    if isinstance(p, dict))
                                blob = body if isinstance(body, str) else ""
                                for name, rx in ERROR_CLASSES:
                                    if rx.search(blob):
                                        err_class[name] = err_class.get(name, 0) + 1
                                        break
                                else:
                                    err_class["other"] = err_class.get("other", 0) + 1
                        elif item.get("type") == "text":
                            has_text = True; text = item.get("text") or ""
                    if (has_text and not has_result and not sidechain
                            and not text.startswith(("<", "Caveat:"))):
                        human_turns += 1; s["humans"] += 1
    if not is_agent_file:
        sessions.append(s)

# ---- report ---------------------------------------------------------------------
def pct(a, b):
    return f"{100.0 * a / b:.0f}%" if b else "—"
def kfmt(v):
    return f"{round(v / 1000)}k"
def units(u):
    return f"{u / 1e6:.1f}M" if u >= 1e6 else f"{u / 1e3:.0f}k"
def span_fmt(sec):
    return f"{sec / 3600:.1f}h" if sec < 48 * 3600 else f"{sec / 86400:.1f}d"

requests = sum(s["req"] for s in sessions)
print(f"session-stats — {len(files)} transcript file(s) from: {', '.join(targets)}")

print("\n==> sessions")
print(f"  {'session':10} {'requests':>8} {'subagent':>8} {'peak-ctx':>8} {'span':>7} {'human':>6}")
shown = sorted(sessions, key=lambda s: -s["req"])[:12]
for s in shown:
    span = (s["last"] - s["first"]) if s["first"] is not None else 0
    print(f"  {s['id']:10} {s['req']:>8} {s['side']:>8} {kfmt(s['peak']):>8}"
          f" {span_fmt(span):>7} {s['humans']:>6}")
if len(sessions) > len(shown):
    print(f"  … and {len(sessions) - len(shown)} more sessions (sorted by requests)")
spans = [s["last"] - s["first"] for s in sessions if s["first"] is not None and s["last"] > s["first"]]
med = f"median session span {span_fmt(statistics.median(spans))}" if spans else "no timestamps"
print(f"  totals: {len(sessions)} sessions · {requests} requests"
      f" (+{side_requests} subagent) · {human_turns} human turns · {med}")
if human_turns:
    print(f"  per human turn: {tool_calls / human_turns:.1f} tool calls,"
          f" {(requests + side_requests) / human_turns:.1f} requests")

u_in, u_cw = tot["inp"], 1.25 * tot["cw"]
u_cr, u_out = 0.1 * tot["cr"], 5.0 * tot["out"]
u_all = u_in + u_cw + u_cr + u_out
print("\n==> spend decomposition (base-price units: fresh 1x · cache-write 1.25x ·"
      " cache-read 0.1x · output 5x)")
print(f"  cache reads {units(u_cr)} ({pct(u_cr, u_all)}) · cache writes {units(u_cw)}"
      f" ({pct(u_cw, u_all)}) · output {units(u_out)} ({pct(u_out, u_all)})"
      f" · fresh input {units(u_in)} ({pct(u_in, u_all)})")
hit_base = tot["cr"] + tot["cw"] + tot["inp"]
print(f"  cache hit rate {pct(tot['cr'], hit_base)} of input tokens"
      f" ({units(tot['cr'])} of {units(hit_base)})")

print("\n==> requests and cost by context size")
all_cost = sum(band_cost.values())
all_req = sum(band_req.values())
for _, name in BANDS:
    if name in band_req:
        print(f"  {name:>9}: {band_req[name]:>6} requests ({pct(band_req[name], all_req)})"
              f" · {pct(band_cost[name], all_cost)} of cost")

print("\n==> idle resumes (>60 min between requests in one session)")
if idle["count"]:
    avg_i = idle["cw"] / idle["count"]
    avg_n = (nonidle["cw"] / nonidle["count"]) if nonidle["count"] else 0.0
    print(f"  {idle['count']} idle-resume requests · avg cache-write {kfmt(avg_i)} tokens each"
          f" (vs {kfmt(avg_n)} otherwise) — an expired cache prefix is rewritten on resume")
else:
    print("  none observed")

print(f"\n==> permission-gate families ({families})")
gated = sum(gate_hits.values())
print(f"  Bash calls: {bash_total} · matching a gated family: {gated} ({pct(gated, bash_total)})")
if gated:
    print(f"  of those — read-only: {gate_hits['ro']} ({pct(gate_hits['ro'], gated)})"
          f" · mutating: {gate_hits['mut']} · unclassified: {gate_hits['unk']}"
          f"   [verb-regex split — treat as ±10%]")

print(f"\n==> tool errors ({err_total})")
for name, count in sorted(err_class.items(), key=lambda kv: -kv[1]):
    print(f"  {count:>5}  {name}")
if not err_class:
    print("  none")

print("\n==> repeated identical Bash commands")
redundant = sum(c - 1 for c in bash_cmds.values() if c > 1)
print(f"  {redundant} redundant re-runs across {bash_total} Bash calls")
top = sorted(((c, cmd) for cmd, c in bash_cmds.items() if c >= 3), reverse=True)[:10]
for c, cmd in top:
    flat = cmd.replace("\n", "⏎")
    if len(flat) > 90:
        flat = flat[:89] + "…"
    print(f"  {c}× {flat}")

if parse_fail:
    print(f"\nnote: {parse_fail} transcript line(s) failed to parse — the format is an"
          " undocumented Claude Code internal; expect drift between versions.")
print("\nAggregates from local transcripts only — nothing was written or uploaded.")
PY
