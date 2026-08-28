#!/usr/bin/env bash
# Dispatches to the CENTRAL write guard (this repo is wired via `install.sh --central`). Tracked in
# git — must stay machine-agnostic, no baked path.
#
# FAILS OPEN, NEVER IN SILENCE — same posture and same reasoning as the real guard-writes.sh's own
# fail-open-on-parse-error shim (INV5): this hook is matched on Write|Edit|NotebookEdit|Bash, the
# tools that could REPAIR a missing central install, so blocking here would block its own fix.
# Allowing without a word would be indistinguishable from a guard that ran and was content, so this
# allows AND says so.
central="${GAME_LOOP_CENTRAL:-$HOME/.claude/game_loop-central}/.game_loop"
if [ -x "$central/bin/guard-writes.sh" ]; then
  GAME_LOOP_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" exec "$central/bin/guard-writes.sh"
fi
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"⚠ THE WRITE GUARD IS NOT RUNNING — no central game_loop install found (this repo is wired via install.sh --central), so this tool call was ALLOWED WITHOUT BEING CHECKED.\n\nINV3 (everything outside this repo is READ-ONLY) is NOT enforced until the central install is reachable again. Silence from this guard is not evidence of safety right now — it is evidence the guard is absent.\n\nThis fails OPEN on purpose (INV5): a PreToolUse hook that exits non-zero blocks every Write/Edit/Bash, including the one that would fix this. Set GAME_LOOP_CENTRAL, or populate the central install: game_loop self --pin <ref> --dest <path>."}}'
exit 0
