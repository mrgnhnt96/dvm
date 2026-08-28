# LEDGER

Reference knowledge for this project. **Not a gate.** It informs hypotheses; it never blocks them.

The failure mode this file has a name for: *ledger rot* — a confidently-wrong RULED-OUT permanently
fencing off the right answer. So every entry carries its **source path** and its **date**, and
RULED-OUT means *we read the thing and it said no*, never *we tried once and it didn't work*.

Three buckets. Append as you learn.

---

## VERIFIED

_Things we read at the pinned version, by hand, and confirmed. Each with a source path + date._

- **Claude Code exposes subscription rate limits in the statusline stdin JSON**:
  `rate_limits.five_hour` / `.seven_day`, each `{used_percentage: 0–100, resets_at: unix epoch}`.
  Subscriber-only (Pro/Max), appears after the first API response, each window independently absent.
  Source: https://code.claude.com/docs/en/statusline.md ("Available data" table + example payload),
  read 2026-07-29. This is the tap `game_loop statusline` builds on.
- **statusLine config keys**: `{type: "command", command, refreshInterval (min 1s), padding}`;
  event-driven runs debounced at 300ms, `refreshInterval` adds a timer for idle periods. Same source,
  2026-07-29.
- **A fresh Claude Code session costs ~31.5k INPUT tokens before it answers anything, and ~24k of
  that is irreducible**: measured at 2.1.223 with `claude -p "reply with the single word ok"
  --output-format json`, in a directory with no CLAUDE.md and no game_loop, so this is the HOST's
  floor and not ours. Three readings, each the full input (cache creation + cache read + input):

      5 MCP servers loaded, all tools    31,547
      --strict-mcp-config (no MCP)       30,323   -1,224   (MCP schemas are ~4%)
      ...and 13 built-in tools disabled  24,377   -7,170   (tool definitions are ~19%)

  So the decomposition is roughly 24k base preamble + 6k tool definitions + 1k MCP schemas. A
  project's own CLAUDE.md adds on top of all three. Nothing amortises any of it across spawns,
  because each spawn is a new session — the 19,051 cache READ in the baseline is a warm cache from
  a previous run, and it still counts as input.

  This is the number under the recommendation NOT to poll usage by spawning sessions: even stripped
  to the bone a probe costs ~24k input tokens, so one probe per 15 minutes is ~490k input tokens per
  5-hour window spent purely observing. Measured 2026-08-05.

  What this does NOT establish: how a subscription's 5-hour window weights input against output, or
  whether cache reads are discounted against it. The probe's cost is measured; the fraction of a
  window it consumes is not. Nor does it establish that the ~24k floor is constant across models or
  releases — it is one reading at one version.

## RULED-OUT

_Things we read the source for and confirmed are NOT the case. Not "tried once and it didn't work."_

- **Hook payloads carry rate-limit data** — they don't (no field on any event; an `OnRateLimit` hook
  is an open feature request: anthropics/claude-code#34817). Checked 2026-07-29.
- **A headless `claude usage` / `--usage` flag exists** — it doesn't; open requests
  anthropics/claude-code#44328, #40395, #39141. A rate-limited `claude -p` exits 1 with an
  undocumented message and no reset timestamp. Checked 2026-07-29.
- **`anthropic-ratelimit-unified-*` response headers are readable by harness code** — they exist
  API-side but Claude Code does not persist them anywhere scripts can reach (open request:
  anthropics/claude-code#55333). The statusline fields are the client-side derivative of these
  headers and the only exposed form. Checked 2026-07-29.
- **The per-model weekly (Opus) limit is in the statusline payload** — it isn't; only `five_hour`
  and `seven_day` windows exist there (statusline.md, 2026-07-29). The limit machinery therefore
  cannot see it; a run can still die on it unwarned.
- **Anything game_loop passes to `saggar agent` names the saggar terminal** — it doesn't, and this
  repo asserted the opposite in two places until it was measured: `docs/how-it-works.md` said
  "saggar names the terminal from the task, so `--task`/`--title` do not reach it either — the
  terminal ends up named after the prompt", and `successor_cfg`'s docstring said the same.

  What saggar displays is `session_name` out of **Claude Code's own status-line payload**, which
  `~/.saggar/claude-status-bridge.sh` mirrors verbatim into
  `~/.saggar/chat-info/<SAGGAR_SESSION>.json` — Claude's auto-generated *conversation title*, not a
  string saggar or this verb supplies. The bridge is 14 lines and passes the payload through
  unchanged; there is no field for a caller to fill. Two live handovers on 2026-08-25 (sibling repo,
  the `handoff` skill's port of this verb) both came out named `HANDOFF-<timestamp> continuation` —
  the second one *after* its prompt led with the subject `confirm saggar names the terminal from the
  subject line`. Three `chat-info` payloads on this machine agreed: `Handoff saggar support`,
  `DELEGATION-dodgeball implementation`, `DELEGATION-barbell` — each traceable to a document's name,
  none to a task string.

  **CORRECTED 2026-08-25, by two more live handovers.** "It keys off the filename" was the reading
  those four supported and it was too narrow. In override_canvas a successor came out
  **"Game loop implementation"** while merging a Flutter branch — not the filename (`HANDOFF.md`)
  but the `.game_loop/…` PATH, which was the only content its prompt had, because its subject was
  the contentless `session 6acce140`. A fourth handover, run deliberately to re-read this entry,
  led with the subject `session verify-e2e` and produced the terminal name **"Verify e2e"** — the
  SUBJECT, not the filename. So the titler reads the PROMPT, and the path wins only when the
  subject offers it nothing better. That is a mechanism with a lever in it, and the lever is the
  subject line — which is why a heading that is only a session id is now refused as one.

  **Why this one was worth an entry.** Nothing was broken by the wrong version; the cost was that it
  was *load-bearing in the wrong direction*. It made "route `--title` through to saggar somehow"
  look like an unfinished feature rather than an impossibility, and it was the justification a
  subject line would most naturally have reached for — "it names the terminal" — which is a reason
  that does not exist. The subject line earns its place by being **read** (the successor's opening
  message, the printed command, the `about` report line) — and, as the correction above shows, by
  being the best content the titler has to work with. The handoff file's PATH is what it falls back
  to when the subject says nothing.

  Source: `~/.saggar/claude-status-bridge.sh` and `~/.saggar/chat-info/*.json`, read 2026-08-25.
  Filed as a claim the same day with both probes (`--task`/`--title`, and the subject line).

  **CLOSED 2026-08-27 — and the entry inverted twice, which is the whole lesson.** saggar shipped
  `saggar agent --title <title>` on 2026-08-26; four live terminals that day showed titled ones
  reading back their exact string from `saggar list --json` while untitled ones stayed at saggar's
  default `Terminal`. The impossibility was gone. What replaced it was worse than a wrong belief:
  a **correct** one that nothing acted on. This repo rewrote the printed block to say "NOT SET FROM
  HERE — and that is OUR gap now", rewrote its comments, rewrote its test to assert that sentence —
  and left `_saggar_agent` calling `[saggar, agent, claude, prompt]`. Every handover for a day
  opened a terminal named `Terminal` underneath an accurate paragraph explaining why it would.

  The human found it, not the harness: *"I thought that we had updated saggar to use the --title
  with the new tab? I'm just getting Terminal now."* Nothing in the checkout could have found it,
  because the test asserted the STDOUT and the gap was in the ARGV. That is the transferable part —
  a test that reads the explanation of a call cannot see the call. `test/run.py`'s fake `saggar`
  now records `"$@"` to a file, and the assertions are on that list: `--title`, a value, and a `--`
  before the task. Source: `saggar --help` at `~/.local/bin/saggar`, read 2026-08-27.

  **EXERCISED the same day, and one instrument lied on the way.** `--cwd` was wired in the same
  pass, then both flags were put through a live probe: `saggar agent claude --title "GL | flag
  probe" --cwd /tmp -- <task>`, run FROM this repo so the caller's project and `--cwd` disagree.
  saggar invoked `claude --session-id <minted> --name "GL | flag probe" -- <task>` with its process
  cwd at `/private/tmp`; the control — a terminal opened by the old call in another repo the same
  hour — read `--name Terminal` with cwd the caller's project. So `--title` becomes claude's own
  `--name`, and `--cwd` places the session. Effector `saggar-agent-flags`.

  The lie: `saggar list --json` reports `projectPath`, and for the probe it read *this repo*, not
  `/tmp` — which is exactly what "--cwd was ignored" looks like. It is not the process's directory;
  it is the saggar PROJECT the terminal is docked under, which stays the caller's either way. The
  answer came from `lsof -a -p <pid> -d cwd`. A session that reached for the obvious JSON field
  would have removed a flag that works, and would have had a screenshot to justify it.

  **`status.kind` lies in the same shape**, found while answering whether a successor could close
  its predecessor's terminal. `saggar list --json` reported the probe as `{"kind": "idle"}` and
  `saggar close` refused it — *"GL | flag probe is still running"*, exit 1. `idle` there means the
  agent is not generating; `close`'s "idle terminal" means no live process in it. Killing the
  claude process made the same call succeed (`closed GL | flag probe`, exit 0). Two fields in one
  JSON document, both answering a neighbouring question rather than the one asked.

  **THE SAME SHAPE A FOURTH TIME, and this one had a workaround already half-built.** Closing a
  predecessor's terminal needs the terminal's id, and `SAGGAR_SESSION` is the obvious candidate:
  it names a terminal, it keys `~/.saggar/presence/<id>.json`, and `in_saggar()` already reads it.
  It is a DIFFERENT UUID from the one saggar's CLI resolves. Measured in a live terminal:
  `SAGGAR_SESSION=84F15D66`, `saggar read 84F15D66` → "no terminal matching"; the addressable id
  was `B80719A7`, and `saggar read B80719A7` returned that terminal's own tail. `~/.saggar/
  sessions.json` is keyed by the first, `saggar list --json` by the second, and no document holds
  both. A terminal learns its real id by ASKING: `saggar read --json` with no id defaults to this
  terminal and returns `{id, name, projectName}`.

  It cost a live A→B chain to find, and the code was already written on the wrong id. What caught
  it was not a test — it was the verdict the retire path recorded when `saggar close` answered
  "no terminal matching <SAGGAR_SESSION>", because that path was built to write down what happened
  instead of assuming it worked. The claim gate then refused the first filing of the finding for
  being a SET claim with one member, which is exactly what it was: the tell it names — "you start
  building a workaround" — was true at that moment.

  **AND A TIMING NOBODY WOULD GUESS, from the same chain.** The generated handoff is written by the
  Stop gate and nowhere else, so a session that has not finished a turn has NO handoff — and
  handing over inside the first turn is precisely what a freshly spawned one-job session does. A
  ran `checkpoint` then `successor` in one turn and was refused. The refusal's own advice ("run
  `checkpoint --notes`") could not have worked: checkpoint records notes for the NEXT generation
  rather than generating one. `successor` now writes the floor itself, which is the stance its own
  docstring already took about the generated handoff it accepts.

  **The prefix went too, on the user's instruction (2026-08-27).** A saggar terminal is titled
  `<task>` with no `<R> | `: saggar groups terminals under the project's own folder and prints its
  name above them, so the initial re-states the folder in four characters, spent at the front —
  the end truncation eats first. Warp keeps it, because a Warp window is one flat row of tabs from
  every repo at once and the initial is the only thing telling two of them apart. The assertion is
  on the SHAPE (`^[A-Za-z0-9?] \| `), not on one repo's letter.

## OPEN

_Questions still outstanding. What would close each one._

- **Does showrunner still have no usage or session-size awareness on the spawn path?** Verified
  2026-08-25 by reading showrunner's own source, and it is load-bearing: #106's spawn brake lives on
  game_loop's limitgate *because* of this, and it would be the wrong place if showrunner ever grew
  the awareness itself. What was read — `lib/showrunner/harness.py:86` is the tree's only occurrence
  of `limits.json`, an ignore-list entry naming files not copied into a worktree; and `cmd_spawn`
  (`lib/showrunner/cli.py:1416`, 104 lines) mentions limits, usage, tokens and threshold zero times.
  So "showrunner kept going after game_loop said the limit was hit" was never two tools disagreeing:
  nothing was ever asking showrunner to stop.

  **Filed as a QUESTION rather than a claim, because there is nowhere else to put it.**
  `claims.json` carries one subject block and version-compares every block against the running
  Claude Code build, so a showrunner entry would read as permanently stale against a release number
  — #107. Until that is decided this fact lives here and in one docstring, which means **nothing
  will notice when it stops being true**. Closed by: re-reading those two paths, or by #107 making
  the registry multi-subject so it can go stale loudly instead. Source: the paths above, read at
  showrunner's checkout on this machine, 2026-08-25.

- **A mark set that matches 306 assertions cannot tell a genuine kill from collateral.** The sweep
  distinguishes the two by asking whether a killed assertion's NAME carries one of the producer's
  marks. Measured 2026-08-25 with the AST over 1626 assertion names: `read_probe`'s marks matched
  **306**, `note_line`'s **287**, `remote_has_ref`'s **279** — against floors of 3, 4 and 3. At that
  breadth almost any kill "names this producer's subject", so the check that exists to catch
  collateral was, for those entries, agreeing with everything.

  **The cause is short marks under substring matching, not the matcher.** `"ref"` is inside *refuse,
  refusal, refs, prefer*; `"read"` and `"note"` are in a third of the suite's names. I checked
  whether word-boundary matching was the fix and it is NOT: only 8 marks lose all their matches
  under it, and 7 of those are DELIBERATE STEMS — `refut`, `supersed`, `attach`, `exhaust`,
  `dogfood` — that a boundary rule would break to fix an unrelated problem. Prefix matching keeps
  the stems and does not fix `ref`/`refuse` either. The three offenders were simply bad marks.

  Narrowed to phrases: 306 → 8, 287 → 12, 279 → 18. `note_line`'s was mine, written that morning.

  **Left deliberately**: 32 more entries match ≥20 assertion names against a floor ≤3. Each needs a
  judgement about what that producer's subject actually IS, and doing it in bulk is how a mark set
  becomes decoration. The measurement is here so the next pass is aimed rather than exhaustive.

- **An ABSENCE is the cheapest thing a broken producer gives you, and 15.3% of this suite asks for
  one.** 2026-08-25: `_closing` measured 0 kills, so I wrote six assertions for it and it went to
  ONE. Five of the six were phrased as absences — `"continuing" not in _cl(...)` — and a producer
  neutered to `return ""` satisfies every one of them for free: there is no marker in an empty
  string. The tests passed against a dead function and measured nothing.

  **The rewrite is mechanical and the gain is large.** Pin what SURVIVES alongside what is stripped:
  the last four lines come back AND the opening line does not; the sentence around a quoted marker
  remains AND the marker does not; the present-tense clause is kept AND the past-tense one is
  dropped. Same six assertions, same producer, **1 kill → 5**.

  **Measured population, with the AST rather than a grep** (the instrument rule, applied): 253 of
  1649 `check()` conditions are purely a negation or an emptiness — `not in`, `is not`, `not X`,
  `== ""`. That is 15.3%, and it is a POPULATION, NOT A VERDICT: many are the legitimate negative
  half of a pair, and the sweep is currently green with no producer unprotected. It says where this
  technique would pay, not that those assertions are wrong.

  **Where to spend it**: the producers the sweep reports THIN, since a low floor plus negative
  assertions is exactly the `_closing` shape before the rewrite — `legacy_mandate_warning` (2),
  `watchdog::superseded` (2), `pinned_sha` (2), `watchdog_pid_identity` (2), `_git_sha` (2). Each is
  a candidate for the same 1→5, and each would be a MEASUREMENT rather than an argument.

  One assertion in the rewritten six still cannot flip, and that is correct: it asserts empty input
  returns empty, which a `return ""` neuter satisfies by definition. Said in the entry rather than
  rounded up.

- **A rendered report is not a data structure — and the siblings, named before one of them bites.**
  2026-08-25: computing how many sweep floors were stale, I hand-rolled `^([a-z_][a-z0-9_]*) ->`
  over the sweep's own printed output. It drops every DOTTED producer name, so twelve — `verify.owed`,
  `watchdog.claim_pidfile`, `notify.send` and the rest of the non-`game_loop` files — never entered
  the denominator. Published 49 of 86; the truth is 58 of 98. A short denominator, produced while
  analysing the file whose oldest lesson is the short denominator, by improvising an instrument for a
  measurement that file already performs on its own structure. (lamp-owner's rule: hand-rolling a
  one-off version of a measurement you have tooling for does not skip the tool's overhead, it skips
  the tool's HARDENING.)

  **Siblings enumerated deliberately, including the ones that have never gone wrong**, because a rule
  filed under its one example gets remembered as a fact about that example. Every place this repo
  parses captured output — 13 sites — and why each is sound:

      bin/verify (3)     git --porcelain -uall / --name-only / ls-files. MACHINE formats, chosen for
                         that, and `-uall` carries a comment about why plain --porcelain is wrong here.
      bin/watchdog (2)   same family.
      bin/game_loop (8)  mostly first-line-of-stderr for a message, not a measurement — INCLUDING
                         `_test_count` below, which is one of the eight rather than a fourteenth.
                         (First written as "(6)" with `_test_count` listed apart, which does not add
                         to 13. The total was right and the attribution was not: same defect as the
                         entry it sits in, one paragraph later.)
      _test_count        the real heuristic, and one of game_loop's eight: reads a test runner's
                         human output. There IS no
                         universal structured alternative, and it says so — returns "no recognised
                         test-count line (mocha, pytest, unittest, go, flutter, TAP)" and its caller
                         renders that as COULD NOT TELL rather than as zero.

  So the shipped code has no instance; the only one was my own scratch analysis, where nothing checks
  the number. **The exposure is prose, not code** — and the mechanism is sharper than "prose has no
  tests": *a sentence has no consumer that can disagree with it*. My selector took `verdicts` and
  would have gone on working forever; "49 of 86" had nothing downstream to contradict it. Code that
  consumes a bad measurement usually gets caught. A sentence carrying one just gets believed.

  **THE TRIGGER IS NOT "WHEN CHOOSING AN INSTRUMENT."** That was my first wording and it does not
  fire, because the choice never surfaces as a choice — I was not weighing a regex against
  `stale_low_floors`, I was looking at output. The trigger that is actually observable from outside:
  **when a number is about to leave your hands** — into a commit message, a comment, a status line, a
  reply — ask where it came from, and whether the tool that produced the result would hand you the
  same number from its own structure. `stale_low_floors`, `killers`, `probed_verdict` and `note_line`
  are all at module level so that the answer is yes. If a tool will not hand you one, that is a gap
  in the tool worth fixing rather than routing around.

- **A docstring that makes a DISTINCTION is a claim about its callers, and nothing checks it.**
  Audited 2026-08-25 after writing this defect twice in one day. Fourteen functions across
  `bin/game_loop`, `bin/watchdog` and `bin/verify` have docstrings that assert what a caller must do
  ("callers keep them apart", "callers must treat it as allow, never as nothing happened"). Of the
  ones with a multi-meaning `None` and live callers, **every long-standing one honours its claim** —
  `work_since_last_block` branches on `is False` rather than truthiness, so its unanswerable `None`
  falls through to allow exactly as promised; `_statusline_claim_live`'s caller prints "this cannot
  tell which, and does not pretend to"; `waiting_verdict` implements all four of its stated
  constraints. The two that failed were both mine, both written that day: `_proc_start` said "the
  callers keep them apart" while its only caller mapped `None` to `False`, and a suite gate was
  named "every flag verify.yaml INVOKES" while scanning prose.

  **The correlation is with FRESHNESS, not age.** The prose was not stale documentation of an older
  design — it was a correct description of a design not yet implemented fifteen lines further down.
  So "check the docs against the code" is the wrong drill; the drill is that the CALLER is a
  different artifact from the function, and the moment to check is when you write the caller.

  **SECOND PASS, for the multi-hop variant** (lamp-owner's sharpening: the distinction survives the
  function that makes it and dies where an ABSENT KEY meets a default, one hop downstream). Searched
  `bin/game_loop` and `bin/watchdog` for reads of a persisted optional key with an `or <empty>`
  default: 99 sites, which is the wrong instrument — for most of them absence and empty are the same
  answer, and a missing `mandate` genuinely means no mandate. Narrowed to keys that record
  PROVENANCE or EVIDENCE, where absence ≠ empty by construction: 16 distinct keys. **All sound.**
  `probe_started_at or 0` is right because no claim and an expired claim really are one answer;
  `captured_at or 0` gives a huge age, so no snapshot reads as "a probe is due", the safe direction;
  the claims display already prints `verified_against: null` as "nobody has re-read it". The file
  states the rule itself three lines below one of them: "COULD NOT LOOK. Never folded into 'no
  limits data': a caller that treats them the same reports a broken probe as an account with no
  windows, forever."

  What that establishes is narrow and worth stating as such: **the shipped code handles this; the
  three failures were all in code written in the preceding two days**, and all three are fixed. The
  search was one pattern over two files, so it is evidence about that pattern, not about the class.

  **Both were safe by luck and therefore invisible.** `False` meant "do not signal", every test
  passed, the sweep floor was met. A sentence that is wrong in the SAFE direction has no behavioural
  signature at all, so nothing in this repo can catch it — which is why both were found by a
  sibling's message rather than by the suite. Not encodable as a gate: the general case needs
  reading the claim, and a naive check (flag every docstring saying "never") fires on prose the way
  the connective scan did at 68%. Recorded as a reading habit with a measured population instead.

- **Has the fresh-session token floor doubled, or has this machine's MCP surface grown?** Measured
  2026-08-24 at 2.1.241: a probe spawn's own render carried **63,943 input tokens** (2 fresh, 3,162
  cache-creation, 60,779 cache-read) against the ~31.5k recorded at 2.1.223 for a spawn of the same
  shape. The claim decomposes as ~24k base preamble + ~6k tool definitions + ~1k MCP schemas, and
  **one total cannot apportion the growth** — this machine's MCP surface has also grown since. So
  the headline is stale and the breakdown is unknown; `fresh-session-token-floor` is NOT stamped.
  Closed by: two readings that differ only in surface — one spawn stripped to the bone, one with
  tools and MCP — which separates the host's floor from what this project adds. Source:
  `.game_loop/probe/context-window.json`, recorded by our own limit probe, read 2026-08-24.

- **RESOLVED 2026-08-25 — how to re-read `statusline-config-keys` on a native build.** It DOES
  reproduce. Two things were wrong before, and only one of them was the method.

  **The artifact was wrong.** `bin/claude.exe` is an npm install (now 2.1.243). This session is
  served by a *different installation* — `.vscode/extensions/anthropic.claude-code-2.1.241-darwin-arm64/
  resources/native-binary/claude`, found with `lsof -p <live pid>`. `which claude` does not name the
  running build, and `running_host_version()` already says so in its own docstring: "the first
  obvious answer is wrong". So the earlier search was reading a build nobody here was running.

  **The method was anchored on tokens that move.** The 2.1.223 reading quoted `M().min(1)`; `M` is a
  minified helper name and it is *different in every build* (it is `Je` in 2.1.241, `M` in 2.1.243).
  Searching for it finds nothing and the absence looks like the schema being gone. Anchor on the
  parts the minifier cannot rename — the KEY names and the structural punctuation — and it comes
  straight back:

      grep -ao 'refreshInterval:[a-zA-Z_$]*()\.min([0-9])[^,]\{0,80\}' <binary>
      grep -ao '.\{0,150\}refreshInterval:Je().min(1)' <binary>     # widen once the helper is known

  which recovers the whole object: `statusLine:ye({type:Ct("command"),command:H(),padding:Je().optional(),
  refreshInterval:Je().min(1)...`, plus an independent confirmation of the floor at the consumption
  site (`Math.max(1,t)*1000`).

  **The earlier entry was right to refuse to conclude.** It said what was established was that ONE
  method returned empty, and declined to read that as "the instrument is gone" — and that caution is
  what left the question answerable instead of closed wrong. The generalisation is narrower than
  "search harder": on a minified artifact, **anchor on the identifiers the minifier is forbidden to
  rename**. Object keys crossing a JSON/config boundary are exactly those. Source:
  the extension binary at 2.1.241, read 2026-08-25 via `lsof` on the live pid.

- **Does a Stop hook fire on the turn a rate-limit error kills?** Unconfirmed either way; the park
  design deliberately doesn't depend on it (the watchdog armed by the *previous* turn-end reads
  limits.json before spending its ring budget). Closed by: observing a real limit death with the
  probe payload present.
- **Live-fire the Slack + park path end-to-end** (real workspace, real 5h exhaustion). The fake-server
  suite proves the logic; a real run proves the wiring. Closed by: one observed park → page → reset →
  resume cycle in log.jsonl.
- **Do limit-deaths cluster at a consumption level that ordinary session closures do not?** This is
  the whole of whether #45's usage estimator can ever be built rather than invented. Every turn-end
  already records a `usage_window` reading and nothing compares it to a threshold, on purpose.
  **AND WE NOW KNOW WHY IT IS LIKELY TO STAY OPEN**, which is worth more than the question: the
  population that would settle it does not exist naturally. Asked of a consumer running 18
  concurrent sessions — the right size and the right host — the answer was 43 readings across four
  sessions with **zero labelled limit-deaths**, and that gap is structural rather than a lack of
  digging. Limit protection is inert on editor hosts (no statusline, so no snapshot), and a session
  cannot observe its own death, so every session there reads as an ordinary closure whether it was
  one or not. Producing a positive class would mean staging sessions for the experiment rather than
  instrumenting work someone was doing anyway, and that consumer declined on exactly that ground —
  correctly, since a staged run is a different measurement wearing this one's name.
  Unlabelled, their consumption clusters at 300–440k output tokens per 5h window, which is a
  precondition for a gauge and not evidence for one.
  Closed by: several long unattended runs from a *terminal* host, each labelled died-at-limit or
  closed-deliberately, with their `usage_window` records. Source: issue #60, 2026-08-05.
  **Do not re-derive this by asking another consumer with the same host shape** — the answer will be
  the same one-class sample, and "for want of looking" is a known state rather than a guessed number.
