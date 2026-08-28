#!/usr/bin/env bash
# Dispatches to the CENTRAL MCP guard (this repo is wired via `install.sh --central`). Tracked in
# git — must stay machine-agnostic, no baked path.
#
# FAILS CLOSED — the opposite posture from guard-writes.sh, and deliberately: this hook is matched on
# mcp__.* only, never on the tools that would fix a missing central install, so the INV5 hazard that
# forces the write guard open does not apply here. What is on the other side of an unguarded MCP call
# can be irreversible — a DELETE FROM, a send, a force-push.
central="${GAME_LOOP_CENTRAL:-$HOME/.claude/game_loop-central}/.game_loop"
if [ -x "$central/bin/guard-mcp.sh" ]; then
  GAME_LOOP_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" exec "$central/bin/guard-mcp.sh"
fi
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: the MCP guard cannot run — no central game_loop install found (this repo is wired via install.sh --central).\n\nThis guard fails CLOSED, unlike the write guard: an MCP call can be irreversible and a missing guard is not gating anything. Nothing else is blocked — Write, Edit and Bash are untouched. Set GAME_LOOP_CENTRAL, or populate the central install: game_loop self --pin <ref> --dest <path>."}}'
exit 0
