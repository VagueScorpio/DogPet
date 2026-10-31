# RT-12: `saves/notify.vbs` is written then executed

Severity: Low (the route is off by default)
Location: `scripts/notifier.gd:206-221`

## The finding

When `notification_launcher` is `"wscript"`, every notification writes
`saves/notify.vbs` and then runs it with `wscript.exe`.

The base64 payload itself is safe — base64's alphabet cannot terminate the
VBScript string literal, which I checked — but the *file* is a script at a
predictable path inside a folder whose permissions depend entirely on where the
owner unzipped the app.

Anyone who can write to `saves/` can replace `notify.vbs` between the `close()`
and the `create_process`, or simply leave a hostile copy there for the next
notification, and have it run as the owner. On a single-user machine that is
nothing. It matters where DogPet is unzipped somewhere several accounts can
reach: a shared folder, a `C:\Tools\DogPet` created by an admin and left
writable by `Users`, a USB stick.

`CLAUDE.md` §7.3 asks for this route as the fallback if a console window ever
flashes, so it is meant to be reachable. It is off by default, which is why this
is Low.

## What needs to be fixed

The helper should not live in a folder that may be shared, should not have a
predictable name, and should not outlive the notification it exists for.

## How it should be fixed, and why that way

Three small changes to `_launch_via_wscript`:

1. **Write it to `OS.get_user_data_dir()`** rather than `Paths.saves_dir`. That
   is under the owner's own `AppData` and is per-user whatever the app folder's
   permissions are. `saves/` is deliberately beside the exe so the app stays
   portable — which is right for saves and wrong for an executable script.
2. **Give it a name nobody can predict**, from `randi()` plus the tick count, so
   a hostile file cannot be sitting at the path in advance.
3. **Delete it afterwards.** `wscript` is launched without waiting, so it
   cannot be removed the instant it is handed over. The leftover is swept up
   instead: once at startup, and again at the start of the next notification,
   so at most one helper exists at a time.

What this does not do is make the window of opportunity zero; a local attacker
who can write to the owner's own `AppData` while the app is running has already
won by other routes. It takes the script out of a folder that may be shared,
which is the part that was actually wrong.

Worth saying plainly: fixing RT-01 mattered far more here. With RT-01 open, this
route carried the same injected script the PowerShell route did.

Verification plan: switch `notification_launcher` to `wscript`, send a test
notification, and confirm the helper is written outside the app folder, named
unpredictably, and gone afterwards.

---

## What was fixed

`scripts/notifier.gd`, `tests/test_notify.gd`.

### Changed — `_launch_via_wscript`

```gdscript
# The helper goes in the owner's own user data folder rather than beside the
# exe. saves/ sits next to the app on purpose, so that unzipping it anywhere
# keeps everything together - right for a save file, wrong for a script this
# then executes: unzip the app somewhere several accounts can reach and
# anyone who can write there can replace the script and have it run as the
# owner. The name is unpredictable so nothing can be waiting at the path, and
# the file is removed once wscript has had it.
func _launch_via_wscript(encoded: String) -> void:
	var vbs_path: String = OS.get_user_data_dir().path_join(
		"%s%d_%d.vbs" % [VBS_PREFIX, Time.get_ticks_usec(), randi()]
	)
```

### Added — sweeping up leftovers

`_sweep_stale_helpers()` removes any `dogpet_notify_*.vbs` lying about. Called
from `_ready` for a previous run's leftovers, and at the start of each
`_launch_via_wscript` for the last notification's.

### The timer I tried first, and why it had to go

The plan said "a short deferred timer". I wrote it as
`get_tree().create_timer(...)` and the probe broke immediately:

```
ERROR: Parameter "data.tree" is null.
   at: get_tree (scene/main/node.h:559)
SCRIPT ERROR: Cannot call method 'create_timer' on a null value.
   [0] _launch_via_wscript (res://scripts/notifier.gd:250)
   [1] send_toast (res://scripts/notifier.gd:203)
```

`Notifier` is an autoload, and `get_tree()` is null before it is in the tree —
and a notification genuinely can be raised from there, which is the whole point
of `_adopt_current_levels` running at startup. A timer was the wrong mechanism
for a job that needs nothing but a folder listing. Sweeping at the start of the
next launch needs no tree, no timer and no lifetime constant, so the
`VBS_LIFETIME_SECONDS` the plan called for does not exist.

This was a defect I introduced, caught by running the probe rather than by
reasoning about it.

## Test result after the fix

`redteam/tests/probe_o_vbs.gd`, with `notification_launcher` set to `wscript`
and `saves/` pointed at a sandbox:

```
after toast 0: 1 helper(s)  ["dogpet_notify_403390_994663396.vbs"]
after toast 1: 1 helper(s)  ["dogpet_notify_417331_245979000.vbs"]
after toast 2: 1 helper(s)  ["dogpet_notify_429541_3220126416.vbs"]

only ever one at a time:   true
each got its own name:     true
none is the old fixed one: true

files in saves/:           []
a file called notify.vbs:  false
where they go instead:     C:/Users/.../AppData/Roaming/Godot/app_userdata/DogPet
after a final sweep:       0 helper(s)
```

Three real toasts appeared. Nothing was written to `saves/`, no two helpers
shared a name, and only one existed at any moment.

One honest note on the method: an earlier run of this probe reported two
consecutive helpers sharing a name, which would have meant the unpredictable
naming was broken. Checked directly — `Time.get_ticks_usec()` and `randi()` both
advance on every call, and three consecutive launches through two different
entry points produce three distinct names — so that reading was a bug in the
throwaway probe, not in the fix. Worth recording rather than quietly dropping.

Whole suite with all nine fixes in: **760 checks, 0 failures**, up from 637 at
the start of the engagement. The project opens with no script errors.

## How it relates to the rest of the app

- **`Notifier._launch_via_wscript`** — the fixed code.
- **`Notifier.send_toast` / `_launch_via_powershell`** — the default route,
  which writes no file at all and is unaffected.
- **`Notifier._toast_script`** — RT-01. That fix is what stops this route
  carrying an injected payload, and matters more than this one.
- **`CareSettings.DEFAULTS["notification_launcher"]`** — still `"powershell"`,
  so this route stays opt-in.
- **`Paths.saves_dir` / `_prepare_saves_dir`** — unchanged. `saves/` keeps
  being portable and beside the exe, which is correct for saves; it simply no
  longer holds anything the app executes.
