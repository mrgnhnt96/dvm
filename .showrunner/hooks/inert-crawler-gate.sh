#!/usr/bin/env bash
# STOP HOOK: refuse the orchestrator's turn-end while a Crawler is alive and inert.
#
# `showrunner waiting` already knows this. Nothing spent it at the one moment it decides
# anything, so an orchestrator would write a "Next: ..." list and walk away from a run that one
# message would restart — and the HUMAN was the one who noticed the stall. Every fact needed to
# prevent that was already computed and printed (#32).
#
# WHY THE EXISTING GATES DO NOT COVER IT, since three of them are adjacent:
#   the harness watchdog  fires on IDLE, which is after the orchestrator already stopped. It
#                         rescues a session that went quiet; it does not refuse the stop.
#   the harness Stop gate refuses a turn-end that asks a question or claims to be continuing.
#                         "I am done for now, here is what is next" is neither, so it passes.
#   a stall gate          asks "did anything move this turn". A turn that read files, published
#                         a page and edited tickets answers yes and still leaves a Crawler inert.
# The unmet question is narrower than all three: IS SOMEBODY WAITING ON A MESSAGE FROM ME.
#
# FAILS OPEN ON EVERY UNKNOWN. No binary, an unparseable answer, an unreadable record — all exit
# 0. A gate that blocks when it cannot see blocks forever the day it breaks, and this one sits on
# the human's own turn-end.
#
# READ --porcelain, NOT the human output. The obvious spelling is
# `waiting 2>/dev/null | grep BLOCKED`, and it CANNOT WORK: `waiting` prints BLOCKED lines to
# STDERR (they are printed on both branches, deliberately), and it exits NON-ZERO precisely when
# it is not waiting — which is the state a blocked Crawler produces. So the natural script
# discards the channel the finding is on and then treats the exit code as "cannot see". Both
# halves fail toward silence. The JSON is a contract; the prose is for a person.
set -u

# HEARTBEAT FIRST — see future-tense-gate.sh for why. Registration and a clean parse are facts
# about a file; only a stamped invocation is a fact about this turn. Written before the fixture
# branch so a test run and a real run both leave the same evidence.
# THE SUITE MUST NOT WRITE THE REPO'S OWN RECORD. The first reading of this heartbeat showed
# 28 stamps per burst for this gate and 13 for its sibling — those were test invocations, not
# turn-ends, because the tests run the hook with no CLAUDE_PROJECT_DIR and it fell back to the
# real checkout. A freshly-run suite then makes every hook look freshly REACHED, which is the
# one thing this file exists to answer. An instrument its own tests can forge measures nothing.
_hb="${SHOWRUNNER_HEARTBEAT:-}"
if [ -z "$_hb" ]; then
  _hb_root="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}"
  [ -n "${_hb_root:-}" ] && [ -d "$_hb_root/.showrunner" ] \
    && _hb="$_hb_root/.showrunner/hook-heartbeat.jsonl"
fi
if [ -n "$_hb" ]; then
  printf '{"hook":"inert-crawler-gate","ts":%s}\n' "$(date +%s)" >> "$_hb" 2>/dev/null || true
fi

FIXTURE="${INERT_CRAWLER_GATE_FIXTURE:-}"      # a recorded --porcelain payload, for testing
SR="${SHOWRUNNER_BIN:-}"

if [ -n "$FIXTURE" ]; then
  [ -r "$FIXTURE" ] || exit 0
  payload="$(cat "$FIXTURE")"
else
  common="$(git rev-parse --git-common-dir 2>/dev/null)" || exit 0
  case "$common" in /*) ;; *) common="$PWD/$common" ;; esac
  root="$(cd "$(dirname "$common")" 2>/dev/null && pwd)" || exit 0

  # THIS IS THE ORCHESTRATOR'S GATE, AND ONLY THE ORCHESTRATOR'S. `.claude/settings.json` is
  # tracked, so the registration crosses into every Crawler worktree — and a Crawler refused at
  # its own turn-end because a SIBLING is inert would be a gate demanding an action it cannot
  # take: it has no channel to its siblings and no authority to reap them. So a session standing
  # in a linked worktree is not this gate's business. Same jurisdiction rule the lease uses:
  # the main checkout is where the orchestrator lives.
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
  [ "$(cd "$top" && pwd)" = "$root" ] || exit 0

  if [ -z "$SR" ]; then
    # A self-vendored PIN first: showrunner develops itself, so this would otherwise run the
# very code being edited, and one syntax error under lib/showrunner/ kills every verb.
for candidate in "$root/.showrunner_self/bin/showrunner" \
                 "$root/.showrunner/bin/showrunner" "$root/bin/showrunner"; do
      [ -x "$candidate" ] && { SR="$candidate"; break; }
    done
  fi
  # ALLOWED WITHOUT BEING CHECKED, said out loud. Below this line every exit 0 means "no Crawler
  # is inert"; above it, the ones that could not TELL. Those two produced identical output --
  # silence and an allow -- which is the collapse this repo already refuses elsewhere: an allow
  # nobody is told about is indistinguishable from a guard that ran and was content. The
  # jurisdiction exits above stay silent deliberately: not applying is not the same as not
  # knowing, and narrating every non-event trains a reader to skim the one that matters.
  [ -n "$SR" ] || {
    echo "inert-Crawler gate: ALLOWED WITHOUT BEING CHECKED — no showrunner binary under $root." >&2
    exit 0
  }
  # Exit code deliberately ignored: `waiting` returns 1 for "not waiting", which is the ordinary
  # state AND the state a blocked Crawler produces. The payload is the answer, not the code.
  payload="$("$SR" waiting --porcelain 2>/dev/null)" || true
fi

[ -n "$payload" ] || {
  echo "inert-Crawler gate: ALLOWED WITHOUT BEING CHECKED — \`waiting --porcelain\` produced no" >&2
  echo "payload, so nothing was compared. This is not 'no Crawler is blocked'." >&2
  exit 0
}

blocked="$(printf '%s' "$payload" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    # Unparseable is UNKNOWN, and unknown allows — but it says so, or "could not read the
    # answer" and "the answer was no blocked Crawlers" leave through the same door.
    print("inert-Crawler gate: ALLOWED WITHOUT BEING CHECKED — the waiting payload did not "
          "parse", file=sys.stderr)
    sys.exit(0)
for c in d.get("blocked_crawlers") or []:
    # NAME WHOSE LEAF IT IS. This gate fires in whichever session is nearest, which in a
    # checkout running more than one campaign is routinely not the owner — hooks read the
    # DEFAULT campaign regardless of which one your session works. Telling a stranger to
    # message a Crawler they never briefed, and offering them a reap over work they have no
    # context on, is handing the controls to the one party who cannot use them safely.
    owner = c.get("actor") or "?"
    sess = c.get("claim_session") or "?"
    print("  %s (%s) — %s" % (c.get("crawler"), c.get("leaf"), c.get("why")))
    print("      claimed by %s, session %s" % (owner, sess))
' 2>/dev/null)" || exit 0

[ -n "$blocked" ] || exit 0

{
  echo "STOP REFUSED — a Crawler is ALIVE AND DOING NOTHING. It needs a message, not time."
  echo
  printf '%s\n' "$blocked"
  echo
  echo "Ending your turn here leaves it inert until a human notices the run has stalled."
  echo "That has happened; it is why this gate exists."
  echo
  echo "THE TREE WAS ASKED. A Crawler whose worktree shows a commit or a tracked-file change"
  echo "since the block was recorded is NOT listed above — it is working without a channel to"
  echo "report on, and this gate releases for it. The ones named here showed neither, so the"
  echo "block report and the tree agree."
  echo
  echo "IF THE ACTOR NAMED ABOVE IS NOT YOU, THIS IS NOT YOURS TO FIX. Tell them. You were not"
  echo "the one who briefed it, and you do not have the context its work needs — this gate fires"
  echo "in whichever session is nearest, not in the one that owns the leaf."
  echo
  echo "  MESSAGE IT — if it IS yours: it was refused at its own turn-end and is waiting to be"
  echo "  told what next. Its channel and identity are in the campaign record"
  echo "  (\`showrunner status\`), and \`showrunner show <leaf>\` names its actor and session."
  echo
  echo "  OR PARK IT — the non-destructive exit, and the right one if the Crawler is not yours."
  echo "  A parked leaf is accounted for: it keeps its claim, keeps its tree, and stops blocking"
  echo "  this gate. Use it when you cannot fix the stall yourself:"
  echo "      showrunner park <leaf> --reason \"not mine to restart — <owner> must\""
  echo
  echo "  OR REAP IT — a block can mean GONE rather than waiting, and an agent that cannot tell"
  echo "  the difference will sit re-messaging a corpse:"
  echo "      showrunner reap            # what it would do"
  echo "      showrunner reap --apply    # release the leaf and surface the tree"
  echo
  echo "REAP IS THE DESTRUCTIVE ONE, and it is the wrong reach for a Crawler you do not own: it"
  echo "surfaces a tree that may hold somebody else's only copy of an hour's work. If this gate"
  echo "fired in a checkout running more than one campaign, the inert Crawler may not be yours"
  echo "at all — hooks read the DEFAULT campaign regardless of which one your session works."
  echo "Park it and tell its owner. Do not reap another agent's tree to end your turn."
  echo
  echo "Commit anything outstanding before reaping — a Crawler's work is uncommitted more often"
  echo "than not at the moment it blocks."
} >&2
exit 2
