#!/usr/bin/env bash
# game_loop's waiting probe, answered from showrunner's campaign record.
#
# THE QUESTION THE WATCHDOG IS ASKING: is this session legitimately waiting on work it dispatched,
# or has it gone quiet with nothing outstanding? An orchestrator that fanned Crawlers into
# worktrees is idle for long stretches BY DESIGN, and a watchdog that rings through that is one
# somebody turns off. showrunner already knows the answer — a live Crawler PID or an explicit
# park — so this is a translation, not a judgement.
#
# THE TRANSCRIPT IS THE WRONG SIGNAL and this deliberately does not look at it. The orchestrator's
# transcript is quiet precisely WHILE it waits; that is the state being recognised, not something
# that distinguishes it from a stall. What is live is the children's artifacts, which is what the
# campaign record holds.
#
# TWO EXIT CONTRACTS MEET HERE, and they do not line up. game_loop's is:
#     0  waiting          stay quiet
#     1  not waiting      ring
#     *  COULD NOT TELL   ring, AND report this probe as FAILING
# showrunner's `waiting` grew a third code of its own (#35):
#     0  waiting     1  not waiting     3  a Crawler is BLOCKED (alive and inert)
# Passing showrunner's 3 through unmapped would be read as "could not tell" and would mark this
# probe FAILING for as long as a Crawler stays blocked — which is a working probe reporting a
# true state, described as broken. 3 maps to 1: there IS work outstanding, ring, and it is an
# ANSWER rather than a failure to answer.
set -u

# A CRAWLER IS NOT AN ORCHESTRATOR. .game_loop/config.local.json is copied into every worktree by
# harness.provision, so this probe runs inside each Crawler too — and a Crawler answering
# "waiting" because its SIBLINGS are alive would silence its own watchdog with somebody else's
# liveness, which is the disarm-by-proxy this whole seam exists to avoid. A Crawler dispatches
# nothing, so the honest answer for one is always "not waiting".
common="$(git rev-parse --git-common-dir 2>/dev/null)" || exit 2
case "$common" in /*) ;; *) common="$PWD/$common" ;; esac
root="$(cd "$(dirname "$common")" 2>/dev/null && pwd)" || exit 2
top="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 2
[ "$(cd "$top" && pwd)" = "$root" ] || exit 1

# Resolved explicitly: a hook's PATH is not a shell's, and a probe that bails because a binary was
# not on PATH exits non-zero with nothing to say — which reads as "there is work" and is the
# failure game_loop reported spending five rounds on.
SR=""
# A self-vendored PIN first: showrunner develops itself, so this would otherwise run the
# very code being edited, and one syntax error under lib/showrunner/ kills every verb.
for candidate in "$root/.showrunner_self/bin/showrunner" \
                 "$root/.showrunner/bin/showrunner" "$root/bin/showrunner"; do
  [ -x "$candidate" ] && { SR="$candidate"; break; }
done
[ -n "$SR" ] || { echo "no showrunner binary under $root — cannot tell" >&2; exit 2; }

# Every line below goes to STDOUT, deliberately. The harness RECORDS a probe's stdout as the
# `detail` of its last run, so stdout is the only channel on which this script can say, after
# the fact, that it was the thing that answered. Until this was added every word here went to
# stderr and the recorded detail was the empty string: the watchdog's own record could not
# distinguish "showrunner's probe ran and found nobody waiting" from "something ran". That is
# this repo's own recurring defect -- the finding on one channel, the recorded value on another
# -- landing on the script whose entire job is to be believed later.
"$SR" waiting >/dev/null 2>&1
case "$?" in
  0) echo "showrunner: WAITING on live dispatched work"; exit 0 ;;
  1) echo "showrunner: NOT WAITING — nothing outstanding"; exit 1 ;;
  3) msg="a Crawler is BLOCKED — alive and inert, needs a message not time"
     # BOTH channels, and neither is redundant: stderr is what makes the RING actionable to the
     # human it wakes, stdout is what the harness stores so the record says what was found. An
     # earlier version of this change moved the line to stdout and silently took the stderr
     # reason away -- the companion rule, broken on the commit that was enforcing it.
     echo "showrunner: $msg"
     echo "$msg" >&2
     exit 1 ;;
  *) echo "showrunner: waiting returned an unmapped code — cannot tell" >&2; exit 2 ;;
esac
