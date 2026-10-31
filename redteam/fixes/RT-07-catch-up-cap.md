# RT-07: No cap on catch-up, so a clock jump kills the pet

Severity: Medium
Location: `scripts/needs.gd:90-104`; `scripts/needs_model.gd:160-170`

## The finding

```gdscript
static func elapsed_between(then_unix: float, now_unix: float) -> float:
	return maxf(now_unix - then_unix, 0.0)
```

The comment above it names the right hazards — daylight saving, a corrected
system time, a dead CMOS battery — and then handles only the backwards case. A
clock that jumps **forward** produces an arbitrarily large `elapsed`, which
flows into `model.catch_up` and `_catch_up_life` with no ceiling. In Real play
the starving clock then runs for that whole stretch and the dog dies before the
window has opened.

A dead CMOS battery typically reads 2099 or similar rather than 1970, so the
forward jump is the *more* likely of the two faults — and it is the one not
handled.

The same path also produces a `NaN`. With an infinite `elapsed`,
`_catch_up_life` computes `well_fed_for = elapsed - starving_for` = `inf - inf`,
and `NaN > 0.0` is false, so the well-fed leg of the absence is silently
skipped. Confirmed in `redteam/tests/probe_c_numbers.gd` (`is_nan: true`).

## What needs to be fixed

An absence longer than any plausible absence should be treated as a broken
clock: clamped, said out loud, and not allowed to be the reason a pet died. And
a non-finite elapsed should not reach the life model at all.

## How it should be fixed, and why that way

A cap in `Needs._ready`, with the arithmetic in `NeedsModel` so it can be tested:

```gdscript
## Longer than this and a broken clock is likelier than a real absence.
const MAX_CATCH_UP_SECONDS := 2592000.0   # 30 days
```

Thirty days is chosen so that **nothing about the intended design changes.** The
longest care interval is 12 hours, so 30 days still maxes every bar, and it is
still far past any grace period, so a dog genuinely left for a month in Real
play still starves. The cap only bites where the number was never real.

The clamp is applied where `elapsed` is first worked out, so every consumer —
the needs drain, the life model, the "While you were away" card — sees the same
figure and they cannot disagree about how long the owner was gone. When it
bites, it is logged and said on the away card, which already exists and is
exactly the right place to tell the owner the time away looked wrong.

`NeedsModel.capped_elapsed` holds the arithmetic, pure and testable, in the same
spirit as `elapsed_between` beside it. It also rejects a non-finite value, which
is what stops the `NaN`.

Deliberately not done: trying to *detect* a clock jump by other means (storing a
monotonic counter, comparing against file timestamps). It would be guesswork
with its own failure modes, and the thing that actually matters is simply not
letting an absurd number be acted on.

Verification plan: an integration scenario that boots with a save from a year in
the "past" in Real play and confirms the dog is alive and the cap was reported;
plus pure cases in `test_needs.gd`.

---

## The plan above was wrong, and the test proved it

The cap alone does not fix the finding. I implemented it, wrote the integration
scenario, and it failed:

```
clock_jumped_forward
  FAIL  the dog is still alive after a year-long absence
  FAIL  so there is no death card
  PASS  the absence was capped rather than acted on in full
  PASS  the owner is told the clock looked wrong
```

The cap worked exactly as designed and the dog died anyway. Thirty days of
starvation is far past any grace period — one hunger interval, three hours on
Moderate — so clamping a year to a month changes nothing about the outcome. The
reasoning in the plan ("the cap is well past every care interval, so nothing
about the design changes") is true, and it is precisely why the cap is useless
on its own.

There is no cap that fixes this, because the two requirements pull apart:

- to stop a clock jump killing the pet, the cap would have to be **below** one
  grace period;
- to leave a genuine long absence working as designed, it must be **far above**
  one.

So the cap is not the answer by itself. What makes the two reconcilable is that
a catch-up does two different kinds of thing:

- **Reversible:** the needs drain. A maxed bar is one click from fixed.
- **Irreversible:** ageing, illness, death.

The app cannot tell a bad clock from a real year away — it has only
`last_saved_unix` to go on, and that is not a solvable problem. But it can
decline to take an *irreversible* action on a number it does not believe, while
still taking the reversible one. So: past the cap, the needs still drain in full
and the dog still looks neglected, and `_catch_up_life` is skipped entirely —
no ageing, no illness, no starvation death.

Nothing is softened for absences the app does believe, which is everything up to
thirty days. And a dog that really is starving still dies within one grace period
of the owner looking at it, so the stakes of Real play survive.

**This is a behaviour change worth the owner's sign-off**, and the one thing in
this pass I would not merge without it. `CLAUDE.md` §6.3 records that starvation
during the offline catch-up was the owner's explicit choice. This does not undo
that — it holds for every absence under thirty days — but a dog genuinely left
for forty days now survives to be looked at rather than being found dead. If the
owner would rather keep death at any length, the fix reduces to deleting one
`if` and its block in `Needs._ready`; the cap and the `NaN` guard can stay.

> **Signed off by the owner, 2026-10-31: keep it.** The bound is now part of the
> spec rather than only of the code — `CLAUDE.md` §6.3 records it alongside the
> original choice it qualifies, so the two cannot drift apart. Shipped in v1.25.

## What was fixed

`scripts/needs_model.gd`, `scripts/needs.gd`, `scripts/away_card.gd`,
`tests/test_needs.gd`, `tests/test_integration.gd`.

### Added — `NeedsModel.capped_elapsed`

```gdscript
## The elapsed time to actually act on, given what the clock said.
##
## An absence is capped because a very long one is far more likely to be a
## broken clock than a real absence - a dead CMOS battery usually reads 2099,
## not 1970, so the forward jump is the likelier fault and was the unhandled
## one. The cap is well past every care interval, so a real month away still
## maxes every bar and still starves a dog in Real play; it only bites where
## the number was never real in the first place.
##
## A non-finite elapsed is treated as no time at all. It arrives from a save
## holding 1e999, which JSON parses as inf, and it used to make the offline
## starvation maths produce inf - inf = NaN.
static func capped_elapsed(elapsed: float, limit: float) -> float:
	if not is_finite(elapsed) or elapsed <= 0.0:
		return 0.0
	return minf(elapsed, limit)
```

### Changed — `Needs._ready`, the part that actually fixes it

```gdscript
		model.catch_up(elapsed, Settings.catch_up_intervals())
		# Ageing, illness and death are the irreversible half of a catch-up,
		# and they are skipped entirely when the clock cannot be believed.
		# ... A maxed bar is one click from fixed, so the needs still drain and
		# a dog left a long time still looks neglected. A death cannot be
		# undone, so an elapsed time this app does not believe is not allowed
		# to cause one.
		if not clock_looks_wrong:
			_catch_up_life(elapsed, float(before.get(String(NeedsModel.HUNGER), 0.0)))
```

The raw figure is also capped once, immediately, and the fact recorded for the
card:

```gdscript
	var reported: float = NeedsModel.elapsed_between(...)
	elapsed = NeedsModel.capped_elapsed(reported, MAX_CATCH_UP_SECONDS)
	var clock_looks_wrong: bool = reported > elapsed
	if clock_looks_wrong:
		Log.warn("The last save is dated %s ago, which is longer than this app will catch up. Treating it as %s - the system clock has probably moved." % [
			NeedsText.format_duration(reported), NeedsText.format_duration(elapsed),
		])
```

and `_away_summary` carries `clock_looks_wrong` so the card can say so.

### Changed — `AwayCard.show_summary`

One extra line on the card when the cap bit, so the owner is told rather than
left wondering why a year away cost them only a month of hunger.

## Test result after the fix

`tests/test_needs.gd` gained 8 pure checks: 0 s, a normal hour, exactly the cap,
past the cap, a year, infinity, negative infinity, and `NaN`.

`tests/test_needs.gd` gained 13 pure checks (157 -> 170): 0 s, an hour, a week, exactly the
cap, one second past it, a year, a negative, `INF`, `-INF`, `NaN`, and three
confirming that a clamped absence still maxes all three bars.

`tests/test_integration.gd` gained a `clock_jumped_forward` scenario — a real
cold launch in Real play, from a well-fed save dated a year back:

```
clock_jumped_forward
  PASS  the dog is still alive after a year-long absence
  PASS  so there is no death card
  PASS  and the care buttons still work
  PASS  the absence was capped rather than acted on in full
  PASS  the owner is told the clock looked wrong
  PASS  hunger is still maxed
  PASS  happiness is still bottomed
  PASS  saves never left the sandbox
```

Before the fix the first three failed: the dog had starved during the catch-up
and the window came up on the death card with every button locked. The last two
are what says the fix did not simply switch the catch-up off — the dog is in a
dreadful state, it just is not dead.

Checked that nothing changed where it should not: `_test_catch_up`'s 3-day case
and the existing `_test_catch_up_ignores_demo` are untouched, and the whole
`test_life` starvation section still passes, including the offline-starvation
split.

Whole suite with all nine fixes in: **760 checks, 0 failures**, up from 637 at
the start of the engagement. The project opens with no script errors.

## How it relates to the rest of the app

- **`NeedsModel.capped_elapsed`** (new) — the arithmetic, pure and tested.
- **`NeedsModel.elapsed_between`** — unchanged; still the thing that stops a
  backwards clock healing the dog for free.
- **`Needs._ready`** — applies the cap once, so every consumer agrees.
- **`Needs._catch_up_life`** — gets the capped figure, so the `inf - inf = NaN`
  cannot arise. The starvation split itself is unchanged.
- **`NeedsModel.catch_up` / `drain`** — unchanged, and still take any figure
  they are given; the cap is a policy decision and belongs with the caller.
- **`AwayCard.show_summary`** — says when the clock looked wrong.
- **`LifeModel.advance`** — the thing that was killing the dog. Unchanged here;
  RT-04 fixed its own guard.
- **RT-09** overlaps slightly: `capped_elapsed` rejecting a non-finite value is
  the same family as the `is_finite` checks added there.
