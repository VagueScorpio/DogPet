# RT-09: Infinities from a save file reach the screen

Severity: Low
Location: `scripts/life_model.gd:239-248`, `:67-74`;
`scripts/needs_text.gd:59-71`; `scripts/pet_history.gd:82-94`

## The finding

`LifeModel.from_dictionary` floors and clamps some fields and not others:
`age_days` gets `maxf(0.0, ...)`, `sickness` gets a proper `clampf`, but
`born_unix` and `died_unix` are taken as they come — and no field is checked for
being finite.

JSON can express an infinity in practice. Godot's parser turns `1e999` into
`inf` (with a warning), and `JSON.stringify` writes `inf` back out as `1e99999`,
so once an infinity is in a save it round-trips and stays there for good.

Confirmed with `redteam/tests/probe_i_misc.gd` and `probe_c_numbers.gd`:

```
format_age(INF)              = -9223372036854775808 days old
format_countdown(INF)        = ~-9223372036854775808m
format_date(1e999)           = 27 Jan -292277022657, 08:29
describe(hostile record)     = A, -9223372036854775808 days old, died of unknown
```

`int(floor(inf))` is undefined and lands on `INT64_MIN`. Nothing crashes and no
state is harmed, but the scoreboard — the memorial feature — prints nonsense,
and it is the kind of nonsense that makes an owner think the app has lost their
dog.

## What needs to be fixed

Numbers read back from a file should be real numbers, and the functions that
turn a number into words should not print rubbish when handed one that is not.

## How it should be fixed, and why that way

Both ends, because either alone leaves a gap.

1. **At the boundary.** The funnels already exist; they just do not check
   finiteness, which is the one property JSON can smuggle through:
   - `LifeModel._number` — add `is_finite`. One place, every field.
   - `NeedsModel.from_dictionary` — add `is_finite`. `clampf` currently absorbs
     an infinity by luck, not by intent, and `NaN` would pass straight through
     it.
   - `CareSettings.merge_into` — add `is_finite` to the float branch, so a
     hand-edited interval of `1e999` does not become the drain rate.

2. **At the last stop before the screen.** `format_age`, `format_countdown`,
   `format_duration` and `format_date` each answer plainly when the number is
   not real, rather than running `int(floor(...))` on it. Defence in depth: the
   boundary checks should mean these never see one, but these are what the owner
   actually reads, and "unknown" is a fine thing for a memorial to say about a
   figure nobody can establish.

Not done: validating `born_unix` / `died_unix` into a plausible date range.
Deliberate — a clock can legitimately be odd, and "unknown" from `format_date`
already covers the unreadable case without this having to decide which years
are allowed.

Verification plan: re-run both probes and confirm the garbage strings are gone;
add pure cases to `test_life.gd`, `test_needs.gd` and `test_history.gd`.

---

## What was fixed

`scripts/life_model.gd`, `scripts/needs_model.gd`, `scripts/care_settings.gd`,
`scripts/needs_text.gd`, `scripts/pet_history.gd`, and the three test suites.

### Changed — the three boundaries

```gdscript
# LifeModel._number, and the same shape in NeedsModel.from_dictionary
static func _number(source: Dictionary, key: String, fallback: float) -> float:
	var raw: Variant = source.get(key, fallback)
	# is_finite as well as the type check: JSON cannot write "inf", but it can
	# write 1e999, which Godot's parser reads as inf - and stringify writes it
	# back out as 1e99999, so an infinity in a save file stays there for ever.
	if (raw is float or raw is int) and is_finite(float(raw)):
		return float(raw)
	return fallback
```

### Changed — the four formatters

Each answers plainly for a number that is not real: `format_age` and
`format_date` return "unknown", `format_countdown` returns "unknown",
`format_duration` returns "an unknown time".

## Test result after the fix

```
format_age(INF)        = unknown        (was "-9223372036854775808 days old")
format_age(1e18)       = unknown        (was "1000000000000000000 days old")
format_countdown(INF)  = unknown        (was "~-9223372036854775808m")
format_duration(INF)   = an unknown time  (was "less than a minute")
format_date(1e999)     = unknown        (was "27 Jan -292277022657, 08:29")
describe(record)       = A, unknown, died of unknown
```

`format_age(1e18)` is now "unknown" too: a finite but absurd figure printed
"1000000000000000000 days old", so the formatters refuse anything past a
plausible span rather than only non-finite values.

A save holding `1e999` for every number now loads as a sane dog rather than an
immortal one. `tests/test_life.gd` gained 7 checks (101 -> 108) and
`tests/test_history.gd` 8 (37 -> 45). All pass.

Whole suite with all nine fixes in: **760 checks, 0 failures**, up from 637 at
the start of the engagement. The project opens with no script errors.

## How it relates to the rest of the app

- **`LifeModel.from_dictionary` / `_number`** — every life field at once.
- **`NeedsModel.from_dictionary`** — the three needs.
- **`CareSettings.merge_into`** — the settings file's numbers. Its
  `real_play_from` already got an `is_finite` `_number` in RT-04; this is the
  same treatment for the rest of the file.
- **`NeedsText.format_countdown` / `format_duration`** — read by the bars, the
  away card and the sickness line.
- **`LifeModel.format_age` / `stage_for`** — read by the scoreboard and the
  death card.
- **`PetHistory.format_date` / `format_lifespan` / `describe`** — the
  scoreboard.
- **`Scoreboard._living_entry` / `_past_entry`** — unchanged; they get sane
  strings now.
- **RT-07**'s `capped_elapsed` rejects a non-finite elapsed for the same reason
  and was done in the same pass.
