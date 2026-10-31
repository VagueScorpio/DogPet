# RT-04: `starve_grace_intervals` ≤ 0 kills the dog instantly, forever

Severity: High
Location: `scripts/life_model.gd:143-148`; missing floors in
`scripts/care_settings.gd:82-93`

## The finding

```gdscript
if hunger_is_critical:
	starving_seconds += seconds
else:
	starving_seconds = 0.0
var grace: float = hunger_interval * _number(config, "starve_grace_intervals", 1.0)
if starving_seconds >= grace:
	_die(Cause.STARVATION, now_unix)
```

With `grace` at `0.0`, `starving_seconds` is also `0.0` — the line above sets it
there for a dog that is *not* hungry — and `0.0 >= 0.0` is true. A perfectly fed
dog dies of starvation on the first processed frame.

Proven in `redteam/tests/probe_c_numbers.gd`:

```
not hungry at all, grace 0 -> died: true alive: false
negative grace -> died: true
```

And it does not stop. `start_new_pet` calls `life.reset()`, which zeroes
`starving_seconds` again, so the next frame kills the new dog too — with a fresh
record appended to `history.json` each time. Real play becomes unplayable with
no indication why, and the scoreboard fills with one-frame dogs.

`settings.json` is meant to be hand-edited: `CLAUDE.md` §6.2 puts the numbers
there "so they can be tuned without code changes". `CareSettings` already floors
the two tunables where a zero would misbehave — `MIN_REMINDER_SECONDS` and
`MIN_ACTION_SECONDS`, each with a comment explaining the damage — but the
`real_play` block has no floors at all, and `Settings.real_play()` hands the
dictionary to `LifeModel` exactly as the file gave it.

## What needs to be fixed

Two things, at two levels:

1. The settings layer should not be able to pass `LifeModel` a grace period that
   means "kill it now", in the same way it already cannot pass a zero reminder
   gap or a negative action length.
2. `LifeModel` should not treat a nonsensical grace as an instruction to kill
   the dog, whatever it is handed. It is the one model in this app where being
   wrong costs somebody their pet, and it should not depend on its caller for
   that.

## How it should be fixed, and why that way

### The floors

Add to `CareSettings`, in the same shape and spirit as the two that are already
there, and a `real_play_from(data)` that applies them. `Settings.real_play()`
returns that instead of the raw dictionary, so every reader gets clamped
numbers and no caller has to remember.

Which numbers get a floor is decided by what a zero actually does, not by
tidiness:

- **`starve_grace_intervals` — floored.** Zero means instant death. This is the
  defect.
- **`age_day_intervals` — floored.** Zero makes `seconds / (hunger_interval * 0)`
  divide by zero, so `age_days` becomes infinity and stays there, which is RT-09's
  "-9223372036854775808 days old" on the scoreboard.
- **`vet_visit_heals` — floored.** Zero means `treat()` takes nothing off the
  sickness bar and returns false forever: the dog is ill, the vet does nothing,
  and it dies with no recourse. As unwinnable as the grace bug.
- **`sickness_rise_intervals` — left alone, deliberately.** Every use already
  guards it (`if to_fatal > 0.0` in `advance`, `if to_fatal <= 0.0: return 0.0`
  in `seconds_to_fatal`), so zero or negative degrades safely: an illness simply
  never progresses. Flooring it would *introduce* a death where there was none,
  which is the wrong direction to be wrong in.
- **`illness_mean_intervals` — left alone**, for the same reason: `if mean > 0.0`
  guards it, and zero means the dog never falls ill. Harmless.

So: floors where a zero produces a wrong or fatal outcome, nothing where a zero
is already handled and merely switches a feature off. That also means the fix
cannot take away a setting somebody was using on purpose to disable illness.

### The model guard

In `LifeModel.advance`, skip the starvation check when `grace <= 0.0`, copying
the shape `seconds_to_fatal` already uses one screen above it. With the floors in
place this should never fire; it is there so that the model cannot be talked into
killing the dog by a caller's mistake.

Verification plan: re-run `probe_c_numbers.gd` and confirm a fed dog with a zero
or negative grace survives; add cases to `tests/test_life.gd`, which is the suite
the project itself calls the one that matters most.

---

## What was fixed

`scripts/care_settings.gd`, `scripts/settings.gd`, `scripts/life_model.gd`,
`tests/test_life.gd`.

### Added — floors in `CareSettings`

```gdscript
## Floors under the Real play numbers where a zero or a negative does more than
## misbehave - the same reasoning as MIN_REMINDER_SECONDS above, and the same
## reason: settings.json is meant to be edited by hand, so it has to survive
## being edited badly.
##
## A starve grace of zero is the worst of them. starving_seconds is zero for a
## dog that is not hungry, and "0 >= 0" is true, so a fed dog died of
## starvation on the first frame - and again on the first frame after the
## owner started another one, with a record in history.json each time.
const MIN_STARVE_GRACE_INTERVALS := 0.1
## A zero here divides by zero and makes the dog's age infinite.
const MIN_AGE_DAY_INTERVALS := 0.1
## A vet that heals nothing leaves an ill dog with no way back.
const MIN_VET_VISIT_HEALS := 1.0
```

and the accessor that applies them:

```gdscript
## The Real play tuning numbers, with floors applied.
##
## sickness_rise_intervals and illness_mean_intervals are deliberately not
## floored: every use of them is already guarded against zero, where they
## simply mean "illnesses never progress" and "the dog never falls ill". A
## floor there would introduce a death rather than prevent one.
static func real_play_from(from: Dictionary) -> Dictionary:
	var tuning: Dictionary = from.get("real_play", {}).duplicate()
	tuning["starve_grace_intervals"] = maxf(
		MIN_STARVE_GRACE_INTERVALS, _number(tuning, "starve_grace_intervals", 1.0))
	tuning["age_day_intervals"] = maxf(
		MIN_AGE_DAY_INTERVALS, _number(tuning, "age_day_intervals", 2.0))
	tuning["vet_visit_heals"] = maxf(
		MIN_VET_VISIT_HEALS, _number(tuning, "vet_visit_heals", 60.0))
	return tuning
```

A `_number` helper was added here too, mirroring `LifeModel._number`, so a
hand-edited file that puts a String where a number belongs falls back to the
default rather than becoming `0.0` through `float()`.

The dictionary is `duplicate()`d rather than clamped in place, so clamping for a
read does not quietly rewrite `Settings.data` and get saved back over the
owner's own file.

### Changed — `Settings.real_play`

```gdscript
func real_play() -> Dictionary:
	return CareSettings.real_play_from(data)
```

### Changed — `LifeModel.advance`

```gdscript
	var grace: float = hunger_interval * _number(config, "starve_grace_intervals", 1.0)
	# A grace of zero or less is not an instruction to kill the dog, it is a
	# broken setting. CareSettings floors it before it ever gets here; this is
	# so that a caller's mistake cannot do it either. Same shape as the
	# to_fatal guard in seconds_to_fatal above.
	if grace > 0.0 and starving_seconds >= grace:
```

## Test result after the fix

`redteam/tests/probe_c_numbers.gd`, the section that proved the bug:

```
--- LifeModel: a zero starve grace in settings.json ---
not hungry at all, grace 0 -> died: false alive: true
negative grace -> died: false
--- and through the settings layer ---
settings.json asking for grace 0 -> CareSettings gives 0.1
settings.json asking for grace -5 -> CareSettings gives 0.1
a fed dog with that settings file survives: true
a starving dog still dies on time: true
```

Before the fix the first two lines read `died: true`.

`tests/test_life.gd` gained `_test_broken_tuning()` — **16 checks**: a zero and
a negative grace through the model itself, the three floors, a fed dog living an
hour under a zeroed settings file with a finite age, a genuinely starving dog
still dying of starvation, a word and a `null` where numbers belong, the two
numbers deliberately left unfloored and a dog that therefore never falls ill,
the shipped defaults passing through unchanged, and a check that reading them
did not rewrite `DEFAULTS` in place. All pass.

The existing starvation tests are untouched and still pass, which is the part
that matters: a dog that really is starving still dies after exactly one care
interval. `test_life` went 85 → 101.

Whole suite at the time: **686 checks, 0 failures.** After all nine remaining
findings were fixed it stands at 760.

## How it relates to the rest of the app

- **`LifeModel.advance`** — the fixed code, and the only place a dog dies of
  starvation.
- **`CareSettings.real_play_from`** (new) — the floors, beside the two that
  already existed for the reminder gap and the action length.
- **`Settings.real_play`** — now returns the floored numbers. Its callers get
  the fix for free: `Needs._advance_life`, `Needs.take_to_vet`,
  `Settings.starve_grace_seconds`, `NeedsBar._refresh_sickness`.
- **`Settings.starve_grace_seconds`** — reads
  `real_play().get("starve_grace_intervals")`, so it now reports the floored
  figure and the countdown on screen agrees with when the dog will actually die.
- **`LifeModel.seconds_to_fatal` / `starving_fraction`** — already guarded their
  own divisors correctly; they are the shape the new guard copies.
- **`Needs._catch_up_life`** — the offline path, which uses the same `advance`.
  A zero grace would have killed the dog during catch-up too; fixed by the same
  change. RT-07 (no cap on how long a catch-up may be) is a different finding
  and still open.
- **`CareSettings.merge_into`** — unchanged. It still accepts any float for
  these keys, which is right: the file is allowed to say anything, and the
  floors decide what is used.
