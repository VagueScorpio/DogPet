# RT-11: The log rotates only at startup

Severity: Low
Location: `scripts/log.gd:36-38`, `:94-107`

## The finding

`_rotate_if_large` is called once, from `_ready`. `_write` never looks at the
size again. `MAX_BYTES` is 1 MB — a ceiling only ever enforced at launch — and
the whole shape of DogPet is that it is left running in the tray for days.

With Demo Speed on and a need at critical, the reminder path logs steadily; at a
nag a minute plus the autosave traffic the file passes 1 MB in a few hours and
then grows without limit until the app is restarted. Nothing breaks — every
write is an open, append, close — but a tray app left for a fortnight can leave
hundreds of megabytes in the owner's `saves/` folder.

## What needs to be fixed

The ceiling should hold while the app is running, not only when it starts.

## How it should be fixed, and why that way

Keep a running byte count in `_write` and rotate when it passes `MAX_BYTES`.

The count is kept rather than the file re-measured, because measuring would
mean a `get_length()` on every line — this script's whole design note is that
it is "deliberately dumb: open the file, append one line, close it", and
stat-ing the file per line would quietly make it the opposite. The count is
seeded from the file's real size in `_ready`, so a restart does not forget what
is already there, and reset on rotation.

One generation of `.old` is kept, exactly as now.

Verification plan: write past the ceiling in a loop and confirm rotation happens
mid-run, that `.old` holds the earlier lines, and that the new log carries on.

---

## What was fixed

`scripts/log.gd`, `tests/test_notify.gd`.

### Changed — a running count, and a rotation check per line

```gdscript
# How many bytes are in the log now, so the ceiling can hold while the app is
# running rather than only when it starts. Counted rather than measured: this
# script appends one line and closes the file, and a get_length() per line
# would quietly make it something else. Seeded from the real size in _ready.
var _bytes: int = 0
```

`_write` adds each line's length and calls `_rotate_if_large()` once the count
is past `MAX_BYTES`; `_rotate_if_large` resets the count to zero when it
rotates, and `_ready` seeds it.

`_rotate_if_large` also no longer re-opens the file to measure it — it takes the
count — so the per-line cost is an integer comparison.

## Test result after the fix

`tests/test_notify.gd` gained 6 checks (62 -> 68) driving a `Log`-shaped
sequence against a scratch file with a small ceiling. `Log` is an autoload that
names `Paths`, so it cannot be loaded in a `--script` run; what is checked is
the rule it now follows:

```
  PASS  the log starts empty
  PASS  writing past the ceiling rotates it
  PASS  the old lines are in the .old file
  PASS  the new log has the newest line
  PASS  the new log is small again
  PASS  a second rotation replaces the previous .old rather than piling up
```

Rotation now happens during the run. Before the fix the same sequence left one
file growing without limit.

Whole suite with all nine fixes in: **760 checks, 0 failures**, up from 637 at
the start of the engagement. The project opens with no script errors.

## How it relates to the rest of the app

- **`Log._write` / `_rotate_if_large` / `_ready`** — the fixed code.
- **`Log.info` / `warn` / `error`** — unchanged; everything in the app logs
  through them.
- **`Paths.log_path`** — unchanged.
- **`Notifier._tick_reminders`** — the heaviest logger in a long tray session,
  and the reason this matters in practice.
- **`CareSettings.MIN_REMINDER_SECONDS`** — the related guard that stops
  reminders firing every frame. Both are about the same long-session failure
  mode, from different directions.
