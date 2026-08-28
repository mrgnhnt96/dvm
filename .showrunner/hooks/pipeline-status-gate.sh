#!/usr/bin/env bash
# PreToolUse(Bash): NOTICE when `$?` is about to read a pipeline's truncator instead of the
# command being judged.
#
# A pipeline's exit status is its LAST command's. `head` and `tail` essentially always succeed,
# so `cmd 2>&1 | head -3; echo "exit=$?"` reports 0 no matter what `cmd` did. The output still
# looks right, which is why reading it carefully does not help.
#
# MEASURED, and the reason this is a gate rather than a note in a file. Across 3,548 Bash
# commands in one session: 23 genuine instances. Re-running the still-reproducible ones with
# and without the pipe, 4 of 7 reported a WRONG status — `showrunner check` 3 read as 0,
# `showrunner campaign` 2 read as 0, `showrunner waiting` 1 read as 0, `llm_chat owed` 2 read
# as 0. One of those false readings became a bug report filed against another team's tool for
# a defect that did not exist.
#
# The sharpest one is showrunner's own. `check` exits 3 on VOID, and its output says why:
# "distinct from 2 (new failures) so a caller that treats non-zero as 'the code is bad' gets a
# code it did not map rather than a wrong answer it will believe." That distinction was argued
# for, implemented, and documented — and then read as 0 by the author of it, through a pipe.
#
# NOTICES, NEVER DENIES. Sometimes the truncator IS the subject (`grep -c … ; [ $? = 0 ]`), and
# a gate that blocks a legitimate shape trains its own bypass. Naming the hazard at the moment
# of use is the whole job.
set -u
payload=$(cat 2>/dev/null || true)

cmd=$(printf '%s' "$payload" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if (d.get("tool_name") or "") != "Bash":
    sys.exit(0)
sys.stdout.write((d.get("tool_input") or {}).get("command") or "")
' 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0

verdict=$(printf '%s' "$cmd" | CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}" python3 -c '
import os, re, sys
cmd = sys.stdin.read()

# WHAT IS BEING THROWN AWAY, not merely THAT something is. Asked by the game_loop auditor:
# should this scale with the exit vocabulary of the SUBJECT? A tool answering 0/1 loses one
# bit; `showrunner check` answering 0/1/2/3 loses the distinction it was built for.
#
# NO APOSTROPHE MAY APPEAR ANYWHERE IN THIS BLOCK, in code or in prose. It is the body of a
# single-quoted shell string, so ONE of them ends the string and bash then hits EOF looking
# for the close. This happened twice while writing these comments — the second time in the
# comment warning about it, which contained three. A PreToolUse gate that fails to parse
# blocks every Bash call, so the breakage announced itself loudly; the same mistake in a Stop
# hook would simply stop guarding and say nothing.
#
# MEASURED BEFORE BUILDING. Exactly TWO showrunner verbs document a graded vocabulary — but
# those two were HALF the wrong readings in the corpus (`check` 3 read as 0, `waiting` 1 read
# as 0). Too few to justify a severity ladder; over-represented enough in the damage to be
# worth naming. So the notice gets sharper for them and the gate stays one severity.
#
# DERIVED FROM THE DOC, never enumerated here. If a third verb becomes graded, this finds it
# with no edit; a list in this file would silently go stale, which is the enumeration defect
# this repo keeps hitting. A consumer without llms.txt simply gets the generic notice.
def graded():
    root = os.environ.get("CLAUDE_PROJECT_DIR") or "."
    try:
        with open(os.path.join(root, "llms.txt")) as fh:
            txt = fh.read()
    except OSError:
        return {}
    out = {}
    for m in re.finditer(r"^showrunner\s+([a-z-]+)[^#\n]*#(.*exit.*)$", txt, re.I | re.M):
        note = m.group(2).strip()
        if len(set(re.findall(r"\b([0-9])\b", note))) >= 2:
            out.setdefault(m.group(1), note)
    return out
# THE REMEDY HAS THE DEFECT, ON THIS HOST. `pipefail` works in bash and zsh. `PIPESTATUS`
# does NOT: zsh spells it `pipestatus` and indexes from 1, so `${PIPESTATUS[0]}` in zsh is
# THE EMPTY STRING. Measured here:
#
#     zsh:   true | false ; PIPESTATUS[0]=[]   pipestatus[1]=[0]  pipestatus[2]=[1]
#     bash:  true | false ; PIPESTATUS[0]=[0]  PIPESTATUS[1]=[1]
#
# And it fails WORSE than the defect it fixes. `$?` after a pipeline gives a real number about
# the wrong command; the bash idiom under zsh gives nothing at all, which renders as `exit=`
# and reads as neither pass nor fail. The identity element, inside the cure.
#
# This gate used to silence on the mere presence of the word, so an author following its own
# printed advice on a zsh host got an empty status AND no warning. Reported by the game_loop
# auditor, reproduced here before acting.
_shell = os.path.basename(os.environ.get("SHELL") or "")
if re.search(r"pipefail", cmd):
    sys.exit(0)
if re.search(r"\bpipestatus\b", cmd):
    sys.exit(0)                       # the zsh spelling; correct wherever it appears
# AN EXPANSION, NOT A MENTION. The first version fired on `grep -n "PIPESTATUS" test/run.py`,
# because the bare word appears in it. That is text ABOUT the construct, not a use of it — the
# same artifact class this file already documents for its other arm. Requiring the `$` means a
# grep pattern, a comment and a doc string all pass, while every real use is caught.
_EXPANSION = r"\$\{?PIPESTATUS\b"
_bad_remedy = bool(re.search(_EXPANSION, cmd)) and "zsh" in _shell
if re.search(_EXPANSION, cmd) and not _bad_remedy:
    sys.exit(0)                       # bash spelling on a non-zsh host is a real remedy
# A command using ${PIPESTATUS[0]} contains no `$?` at all, so the arm below never reaches it.
# This is its own finding with its own text, because the cause differs: that one is about whose
# exit code you are believing, this one is about a remedy that yields nothing on this host.
if _bad_remedy:
    print("@@ZSH@@" + next((l.strip()[:110] for l in cmd.split("\n")
                            if re.search(_EXPANSION, l)), cmd.strip()[:110]))
    sys.exit(0)
TRUNCATORS = r"\b(head|tail|grep|wc|cat|sed|cut|uniq|sort)\b"
hits = []
for line in cmd.split("\n"):
    s = line.strip()
    if "|" not in s or "$?" not in s:
        continue
    # A line that is TEXT about the pattern — a heredoc body, a comment — is not a command.
    # Left in because the detector that matched its own source is the same defect one layer up.
    if s.startswith(("#", ">", "*")):
        continue
    segs = re.split(r";|&&|\|\|", s)
    for i, seg in enumerate(segs):
        if "$?" not in seg:
            continue
        subject = seg if "|" in seg else (segs[i - 1] if i else "")
        if "|" not in subject:
            continue
        last = subject.rsplit("|", 1)[1]
        if re.search(TRUNCATORS, last):
            hits.append(subject.strip()[:110])
if hits:
    print("\n".join(dict.fromkeys(hits)))
    g = graded()
    for verb, note in g.items():
        if re.search(r"showrunner\s+" + re.escape(verb) + r"\b", cmd):
            # A PRINTABLE SENTINEL, not \x00. Command substitution STRIPS null bytes, so the
            # marker vanished between the two python blocks and the stakes silently never
            # rendered — the enrichment looked wired and produced nothing.
            print("@@STAKES@@%s answers %s" % (verb, note))
' 2>/dev/null) || exit 0

[ -n "$verdict" ] || exit 0

printf '%s\n' "$verdict" | python3 -c '
# `os` IS IMPORTED HERE BECAUSE THE MESSAGE READS $SHELL. The first version of this patch used
# os.path.basename without importing os: NameError, no stdout, gate silently answers nothing —
# inside the change that fixes a remedy which silently yields nothing. Caught by running it.
import json, os, sys
raw = [l for l in sys.stdin.read().split("\n") if l.strip()]
MARK, ZSH = "@@STAKES@@", "@@ZSH@@"
zsh_hits = [l[len(ZSH):] for l in raw if l.startswith(ZSH)]
lines = [l for l in raw if not l.startswith(MARK) and not l.startswith(ZSH)]
stakes = [l[len(MARK):] for l in raw if l.startswith(MARK)]
if zsh_hits:
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
        "additionalContext":
            "⚠ `${PIPESTATUS[...]}` IS EMPTY IN ZSH, AND THIS HOST RUNS ZSH.\n\n  "
            + "\n  ".join(zsh_hits)
            + "\n\nzsh spells the array `pipestatus` and indexes it FROM 1, so the bash form "
              "expands to the empty string. Measured here: after `true | false`, "
              "`${PIPESTATUS[0]}` is `` and `${pipestatus[1]}` is `0`.\n\n"
              "This fails WORSE than the bug it fixes. Reading `$?` after a pipeline gives a "
              "real number about the wrong command; this gives nothing at all, which renders "
              "as `exit=` and reads as neither pass nor fail.\n\n"
              "Use `${pipestatus[1]}`, or `set -o pipefail`, or capture with no pipe at all: "
              "`cmd > /tmp/o 2>&1; rc=$?`."}}))
    sys.exit(0)
msg = ("⚠ `$?` HERE IS THE TRUNCATOR'"'"'S STATUS, NOT THE COMMAND'"'"'S. A pipeline exits with its "
       "LAST command, and head/tail/grep essentially always succeed — so this reports 0 whatever "
       "the real command did, and the output still looks correct.\n\n  "
       + "\n  ".join(lines)
       + "\n\nCapture it without a pipe (`cmd > /tmp/o 2>&1; rc=$?`), or `set -o pipefail`, or "
       + ("`${pipestatus[1]}` — this host runs zsh, where `${PIPESTATUS[0]}` is THE EMPTY "
          "STRING: zsh spells the array `pipestatus` and indexes it from 1, so the bash idiom "
          "here fails worse than the bug, giving you nothing instead of the wrong number."
          if "zsh" in os.path.basename(os.environ.get("SHELL") or "")
          else "`${PIPESTATUS[0]}` (bash) / `${pipestatus[1]}` (zsh — different name, indexed "
               "from 1).")
       + " Measured on this repo: 4 of 7 reproducible instances reported a "
         "wrong status, and `showrunner check`'"'"'s deliberate exit 3 (VOID — nothing was "
         "compared) read as 0.")
if stakes:
    msg += ("\n\nWHAT THIS PARTICULAR COMMAND THROWS AWAY:\n  "
            + "\n  ".join(stakes)
            + "\n\nEvery one of those collapses to 0 through the pipe.")
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                         "additionalContext": msg}}))
'
exit 0
