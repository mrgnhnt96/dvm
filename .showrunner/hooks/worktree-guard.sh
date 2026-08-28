#!/usr/bin/env bash
# The PreToolUse entrypoint for the worktree lease guard.
#
# TRACKED ON PURPOSE, AND MACHINE-AGNOSTIC ON PURPOSE — those two facts are the whole reason
# this file exists rather than a hook command in .claude/settings.json naming the binary
# directly. `.claude/settings.json` is tracked, so it crosses into every worktree, but the
# COMMAND it names has to resolve on the other side, and both obvious spellings fail there:
#
#   "$CLAUDE_PROJECT_DIR"/.showrunner/bin/showrunner
#       In a worktree, CLAUDE_PROJECT_DIR is the WORKTREE (verified, WL-01), and .showrunner/
#       is runtime state that `git worktree add` does not carry — it copies TRACKED files
#       only. Dead on arrival in exactly the place the guard is for.
#
#   an absolute path to this machine's checkout, baked into the tracked file
#       Resolves here and is wrong in every other clone. (Not spelled out even as an example:
#       this repo is public and a tracked file carrying somebody's home directory is a rule a
#       stranger inherits — the suite scans for exactly that, and caught this comment.)
#
# So the tracked thing is this shim, which resolves the MAIN checkout at run time the same way
# util.main_checkout does — via --git-common-dir, whose value is the main checkout's .git even
# when called from inside a linked worktree.
#
# FAIL OPEN, NEVER IN SILENCE. When no binary can be found this ALLOWS the tool call and says
# so. A PreToolUse hook that exits non-zero blocks every Write/Edit/Bash including the one
# that would repair it, so hard-failing on our own plumbing would lock the repo against its
# own fix. But allowing without a word is indistinguishable from a guard that ran and was
# content, which is how a rail goes quiet exactly where it is blind — so the allow announces
# itself, `showrunner doctor` reports the absence as an error, and `worktree enter` says one
# line into agent context when the guard is inert.
#
# Keep this file trivially correct. All real logic lives in `showrunner worktree guard`.
set -u

notice() {
  # additionalContext is what actually reaches the agent on an allow. Fixed strings only —
  # this is the piece that must never itself be the thing that breaks.
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$1"
  exit 0
}

# CWD IS WHERE THE SHELL STANDS; IT IS NOT WHAT THE COMMAND WRITES. Resolving only from cwd
# made this guard strongest exactly where it is least needed — already inside the repo — and
# absent exactly where a stray absolute path is most likely, which is a scratch directory.
# Working from a scratchpad is the ordinary shape of orchestration, not a mistake, and a
# consumer reported DOZENS of unchecked calls in one session from precisely that.
#
# So when cwd cannot answer, ask the HARNESS. CLAUDE_PROJECT_DIR is the session's own notion of
# where it is working and is set for every hook invocation; in a worktree it is the WORKTREE,
# which is the answer this guard wants. Failing open is now what happens when BOTH cannot
# answer, rather than when the shell happens to be standing somewhere else.
anchor="$PWD"
common="$(git rev-parse --git-common-dir 2>/dev/null)" || common=""
if [ -z "$common" ] && [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  common="$(git -C "$CLAUDE_PROJECT_DIR" rev-parse --git-common-dir 2>/dev/null)" || common=""
  [ -n "$common" ] && anchor="$CLAUDE_PROJECT_DIR"
fi
if [ -z "$common" ]; then
  notice "⚠ THE WORKTREE GUARD DID NOT RUN — neither the working directory nor CLAUDE_PROJECT_DIR resolves to a git repository, so this tool call was ALLOWED WITHOUT BEING CHECKED. A worktree held by another live session is NOT protected. Check: showrunner doctor"
fi

# --git-common-dir answers relatively (\".git\") when the cwd is the repo root, so resolve it
# against the ANCHOR it was computed in before taking its parent. Skipping this made the root's
# parent the repo — and using $PWD here after resolving via CLAUDE_PROJECT_DIR would reintroduce
# the same bug from the other direction.
case "$common" in
  /*) ;;
   *) common="$anchor/$common" ;;
esac
root="$(cd "$(dirname "$common")" 2>/dev/null && pwd)" || root=""

# THE SAME ORDER brief.sr_bin resolves in, and deliberately not a second resolver: a
# self-vendored PINNED copy first (see .showrunner_self — code a mid-edit cannot break), then
# the installed copy a consumer has, then bin/showrunner for the repo that IS showrunner and
# never runs its own installer. Two resolvers that disagree about which binary is real is a
# failure nobody would see until they disagreed.
for candidate in "$root/.showrunner_self/bin/showrunner" \
                 "$root/.showrunner/bin/showrunner" \
                 "$root/bin/showrunner"; do
  if [ -x "$candidate" ]; then
    # NOT `exec`, AND THAT IS THE FIX. A binary that is FOUND and BROKEN — one syntax error
    # anywhere under lib/showrunner/ kills every verb at import — exited 1 with EMPTY stdout,
    # which is neither a deny (2) nor a loud allow. So editing this tool silently disarmed its
    # own guard, and the "fails open, never in silence" property below only ever covered the
    # binary being MISSING. Measured, not reasoned: a one-line syntax error reproduced it.
    out="$((cd "$root" && "$candidate" worktree guard) 2>/tmp/.sr-guard-err.$$)"; rc=$?
    err="$(cat /tmp/.sr-guard-err.$$ 2>/dev/null)"; rm -f /tmp/.sr-guard-err.$$
    if [ "$rc" = 0 ]; then
      printf '%s\n' "$out"
      exit 0
    fi
    if [ "$rc" = 2 ]; then
      printf '%s\n' "$err" >&2          # the refusal's reason, on the channel a denial uses
      exit 2
    fi
    notice "⚠ THE WORKTREE GUARD DID NOT RUN — $candidate exited $rc instead of answering, so this tool call was ALLOWED WITHOUT BEING CHECKED. That is what a half-edited showrunner looks like from here: one syntax error under lib/showrunner/ kills every verb at import. A worktree held by another live session is NOT protected right now. First line: $(printf '%s' "$err" | head -1)"
  fi
done

notice "⚠ THE WORKTREE GUARD DID NOT RUN — no showrunner binary was found (looked for .showrunner/bin/showrunner and bin/showrunner under the main checkout), so this tool call was ALLOWED WITHOUT BEING CHECKED. A worktree held by another live session is NOT protected. Check: showrunner doctor"
