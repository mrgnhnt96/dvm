# INVARIANTS

The non-negotiables `game_loop stepback` re-injects. This is the template that ships with game_loop —
**edit it to your project's north star.** Keep the general ones (INV1–INV6); add your own as observed
failures demand. Each should earn its place from a real mistake, not from wanting a tidy list — INV7
and INV8 are the worked examples, both added from this project's own logged failures and kept because
they generalise past it. Delete them if they do not fit yours; that is the point of the file.

---

## INV1 — Enforcement lives in tools, never in instructions

A rule the agent has to *remember* is followed only some of the time — long sessions and context
compaction break that promise. A rule a hook *consumes* holds every time.

Test for any guard here: **if the agent ignored every instruction, would this still hold?** If no, it
is not enforcement; it is a wish. This is why the keystone check is always "name a real file that
exists" — the one check prose cannot satisfy.

## INV2 — Read a real file before asserting (THE gate)

Every claim about external reality — a dependency, a harness, another repo — must name the real file
that backs it: `game_loop claim --assert ".." --read <path>`. A research subagent's citation is not a
source; it *finds* the file, it does not *read* it. Cite the file you read.

## INV3 — Everything outside this repo is READ-ONLY

Read other projects, mine them, use their data as fixtures. Never write, never run their tooling,
never deploy. Access is not permission — logged-in accounts, tokens, and an always-on prod connection
are not permission. Enforced by `.game_loop/bin/guard-writes.sh`, not by this paragraph, because a
paragraph exactly like it is the kind of thing that already fails.

## INV4 — No gate without a logged, observed failure

Ceremony has a certain cost and a hypothetical benefit. Do not add a rung until `log.jsonl` shows a
real failure that demands it. When tempted, name the entry that justifies it.

## INV5 — A guard must never block its own fix

A guard that blocks the fix it recommends is a guard that gets switched off — and a guard disabled
once is disabled forever. Every guard needs a legitimate path through it. Here the escape hatch is the
*human* (`game_loop authorize`), never an env var, because an advertised bypass is a bypass.

## INV6 — ENCODE, don't remember; and state what a guard misses

A learning is a bug in the harness with a countdown. Its deliverable is an **artifact**, not a
sentence: `game_loop harden --learning ".." --artifact <real path> --mechanism ".." --rung N`. Take the
highest rung that applies — **1 IMPOSSIBLE · 2 LOUD · 3 CHECKED · 4 AUTOMATED · 5 VISIBLE · 6

And a rung is only as high as its own ENABLING CONDITION. Rung 3 is CHECKED only if the
check's enabling condition sits outside the agent's reach: a guard gated on a file the agent
can write is an off switch, and it gets flipped at the moment the agent is most stuck. Two
consumer guards opened `grep -qi '^lead' .game_loop/seat || exit 0`; the seat said `worker` for
sixteen hours while both guards ran, returned 0, and let through exactly what they existed to
refuse. DERIVE the condition from something observable instead of declaring it in state.
doc/memory** (last resort). And a guard that overstates its reach buys false confidence: say what it
does *not* catch, in the guard itself. Silence from a guard is not evidence of safety.

**Writing a rule does not install it, and the author is not exempt.** The intuition is that whoever
just articulated a rule is the last person who would break it; the evidence runs the other way, and
it is worth knowing because it removes the excuse that the next violation was carelessness. Two
agents on one afternoon: one hardened "pair every non-event assertion with the case that fires", then
shipped a coverage tool that inspected 6 of 30 candidates — the same default-to-unprotected shape it
had fixed elsewhere and filed as an issue against someone else. The other wrote "test traffic belongs
in its own room", then tested in a shared one for six more hours. Both rules were right, both authors
believed them, neither was protected by having written them. That is the case FOR the artifact, made
by the people most convinced already. Take the rung honestly — and when the honest rung is 6, say so
rather than dressing a paragraph as enforcement.

## INV7 — A sum is not a distribution

An aggregate hides its own shape, and a run optimizing against one will read structure into a single
outlier. Before stating an effect derived from a **total, a mean, or a percentage**, show the per-event
values — and when one event carries most of the total, explain it or exclude it *with the reason on the
record*, because an exclusion nobody wrote down gets rediscovered.

The failure: 1066.7 units of damage against 0.0 read as a total elimination and was written up as a
finding. One event of thirty carried 96% of it, and it was an artifact already identified and dismissed
earlier in the same session. Corrected: 1.5 per event against 0 — no effect at that sample size. Nothing
about the totals revealed this; only printing the per-event values did, and the same event produced
three findings before anyone did. Enforced by `claim --metric --aggregate`, not by this paragraph.

## INV8 — A pass that is silence proves nothing on its own

A check whose success looks like *nothing happening* cannot tell being **satisfied** from **never
having run**. That is one shape, not three: a guard that goes quiet when it permits, a path that is
never examined, an observation that comes back empty. Each is satisfied by a producer that has
stopped working, and the tell is identical to the one it gives when everything is fine.

The asymmetry is the useful half: **a refusal cannot be produced by absence** — it takes a working
check to say no — so the blocking half of any rail validates itself, and it is the permissive half
that needs a second bit. Choose that bit by what the check has on its happy path: a **reason** if it
speaks, a **mark it advances** if it is silent, a **positive control** if it is a pure observation.
And when you assert that something did *not* happen, pair it in the same observation with the case
where it *does*. That costs one extra capture while writing and cannot be retrofitted cheaply.

Find them by **mutation**: neuter the producer — make the guard permit everything, the detector find
nothing, the validator have no opinions — and see what still passes. It manufactures the absence you
cannot otherwise observe, and what survives is what was never being checked.

**A mutant that CRASHES the suite is protected, not unprotected — read the verdict carefully.** The
run exits non-zero and goes red, so the defence worked; what failed is the *measurement*, because a
crash ends the run and every assertion behind it never printed. Those two findings look identical in
a summary and are worth opposite amounts: recovering a crashed producer buys you a **number**, not
safety, and reporting it as a closed hole overstates the work. Fix the crash to learn how strongly
the thing was already defended — then say which of the two you found.

The crash itself has a shape worth naming, because fixing it once does not fix it. **A crash exposes
only the FIRST site of its kind.** Every identically-shaped site behind it was never reached, so it
never earned a guard — which means patching the site that crashed leaves its neighbours in exactly
the state that produced the crash, and the next run stops a few lines later. A guard you have to
remember per site therefore lands where the danger is already spent and never where it is live. Do
not guard the site; supply a helper the dangerous shape cannot be written without.

The failure, three times in one session: a syntax error made the write guard allow everything with no
output at all, so "outside this repo is read-only" stopped being enforced and nothing said so.
Sixteen permissive assertions passed against a guard mutated to check nothing. Four producers that
report by staying silent were barely tested — one of them noticed by a single assertion out of 431.
None of it was visible while every suite was green.

---

**The outside view outranks my attachment.** The human and fresh review subagents are the real
outside view. When they disagree with me, they are probably right; update rather than defend.
