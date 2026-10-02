# Test Triage: Scaffolding and Over-Pinned Tests

Log for the 2026-10-02 work on `test-driven-development` and `writing-good-tests.md`.
Commits: `9a62858` (skill text), `e9ea0ad` (Stop hook), `0bb24b9` (this note).

## Start here next time

1. **This is iteration 2 of a thread.** `b1d9716` ("handle brittle tests")
   added the `SCAFFOLD:` marker and triage gate. That session's own notes
   already predicted this failure — *"nothing enforces it... prose an agent
   can skip."* Read it before designing anything.
2. **Try the repo's own eval harness first.** `evals/` is not cloned in this
   checkout; AGENTS.md says skill-behavior evals live in
   `superpowers-evals`, cloned to `evals/`, where **Drill** drives real tmux
   sessions and judges compliance with an LLM verifier. Clone it before
   hand-rolling sandboxes — this session spent 30 subagent runs on
   essentially what Drill exists to do.
3. **Edits are live.** `~/.agents/skills/<skill>` is a symlink into this
   repo, so a skill change takes effect in every harness immediately.
   Dispatch test subagents *after* the edit. Never edit mid-run — it
   contaminates a baseline still being generated. (Hit this; had to hold
   edits between RED and re-verify.)
4. **Terminology, already settled:** "flaky" in this project means
   over-pinned change detectors, not nondeterministic tests. Don't re-ask.
5. **Git hygiene.** The working tree carries unrelated pre-existing
   modifications (`README.md`, `executing-plans`, `subagent-driven-development`,
   `using-git-worktrees`, `writing-plans`, `test-worktree-native-preference.sh`).
   Stage files explicitly; never `git add -A`.
6. **The marker's wording lives in three files** — `writing-good-tests.md`,
   `test-driven-development/SKILL.md`, `finishing-a-development-branch/SKILL.md`.
   Change one, change all three.

## Problem

Strict TDD was producing tests that were useful only during the edit:
wiring assertions, immediately-green pins of behavior the change
*preserved*, and over-pinned change detectors. Agents kept them, and the
suite became a maintenance toll.

## Root cause: misclassification, not laziness

The first baseline was instructive. The agent did run triage and named a
break for every test — then kept four plumbing tests. `"It fails if I
delete the line I just added"` **is a break**, so `"name the break"` was
trivially satisfiable by describing your own edit in reverse.

So the fix is not a stronger admonition. It is a **falsifiable
predicate** the agent cannot rationalize past.

## The rule, as it now reads

From `writing-good-tests.md` → Triage Before Completion:

- **Scaffolding:** if the only production change that fails the test is
  reverting or inverting the lines you just added, it is scaffolding.
- **Naming a break is necessary, not sufficient.** RED means the test
  failed against production code you had not yet changed. A mutation you
  introduce afterwards is not a RED.
- **Characterization carve-out:** a first-run test may be kept when it
  pins behavior the change does not touch, proven by mutating *that*
  code and reverting byte-identical. The mutation must land outside the
  change's blast radius — a different function or file.
- **Boundary-contract carve-out:** only for a contract the change
  *alters* (so the test goes RED). A contract the change *preserves*
  never goes RED, so it is characterization.

## The loophole chain — each one cost an iteration

This is the part worth remembering. Every rule I added created a new
door, and only pressure testing found them.

| # | Escape route | Observed | Closed by |
|---|---|---|---|
| 1 | Absolute "first-run → delete" made coverage work impossible | kept 13 tests via a mutation matrix | authorship scoping |
| 2 | Mutated a pre-existing string *inside the edit's blast radius*, called it characterization | 2/2 reps kept the pin | blast-radius rule |
| 3 | Switched to the boundary carve-out for a contract the change *preserved* | 2/2 reps kept the pin | "boundary = contract you alter" |
| 4 | Mutated its own `if (true)` and called it "a wrong-branch bug, not a revert" | kept the pin | "a mutation you introduce is not a RED" |

After all four were closed: iterations 4–6 went 15/15, and the
*legitimate* path got stronger, not weaker.

## Agent behaviour worth knowing

- **Writers rationalize; classifiers don't.** Three cold reps classified
  a 5-test set 15/15 correctly. The agent that *wrote* the same test kept
  it (sunk cost). Test with the agent doing real work, not a quiz.
- Agents reach for correct patterns unprompted once the predicate is
  clear: fake clocks to kill flaky timer tests, folding would-be
  first-run cases into a table that as a whole goes RED, deleting their
  own unreachable tests, declining to pin incidental crashes.
- **Zero markers were written in the final two iterations.** Agents now
  prevent scaffolding at write time rather than mark and clean up. The
  marker is a backstop, not the mechanism — so the hook rarely fires.

## Simulation method (reuse this)

Prefer Drill (see [Start here](#start-here-next-time)). If hand-rolling:

- **One sandbox directory per rep.** Two agents sharing a dir race and
  contaminate each other. Cost two wasted dispatch rounds.
- 5 probes per iteration; separate the "should delete" probes from the
  "should keep" regression probes.
- Give the hook script to the repo too: run it against the repo itself,
  not just fixtures. The self-flag bug below was invisible to the 9
  fixture tests.
- **Verify on disk, don't trust the report.** `ls test/`, `grep -rn
  'SCAFFOLD:'`, `node --test` per sandbox.
- A classification micro-test with known ground truth is cheap and
  catches wording problems before full scenarios.

## Hook notes

`hooks/check-scaffolding` (Claude Code `Stop`). Two scoping traps:

1. Scope to **changed** test files, not the repo. A repo-wide grep flags
   the skill docs that describe the marker.
2. Anchor the marker to a **comment position**:
   `^[[:space:]]*(//|/\*|\*|#|--)[[:space:]]*SCAFFOLD:`
   A bare substring match flags any file that writes the marker into a
   fixture or a `printf` — including the hook's own test file. That bug
   was live: the hook blocked on this repo.

Harness coverage: Claude Code declares `SessionStart` + `Stop`; Cursor
declares `sessionStart` only; Codex/pi/opencode declare nothing, so the
skill's grep remains their only gate.

## Open risks

- **Compaction.** The gate lives in a reference file the agent must read
  at completion. `SessionStart` injects only `using-superpowers`. Long
  sessions that compact could drop it. Untested.
- **The grep is self-report.** An agent can claim it ran without running
  it; early reps did exactly that.
- **Deliberate strictness.** The rule deletes a first-run pin even when it
  guards a contract you were told not to break, leaving that contract
  protected by construction and manual check only. Four reps flagged this
  tradeoff unprompted. Revisit if it bites.
- **Upstream.** The text commit is the portable part; the Stop hook is
  Claude-Code-only enforcement and is not an upstream candidate for core.

## Files touched

```
skills/test-driven-development/writing-good-tests.md   predicate + both carve-outs
skills/test-driven-development/SKILL.md                rationalization rows, red flags, checklist
skills/finishing-a-development-branch/SKILL.md         Step 1.5 uses the shared predicate
hooks/check-scaffolding                                Stop hook (new)
hooks/hooks.json                                       Stop wiring
tests/hooks/test-check-scaffolding.sh                  11 tests (new)
```
