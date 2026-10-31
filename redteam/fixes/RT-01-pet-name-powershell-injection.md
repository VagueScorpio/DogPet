# RT-01: PowerShell code execution via the pet name

Severity: Critical
Location: `scripts/notifier.gd:224-261` (`_toast_script`, `_xml_escape`, `_file_uri`)

## The finding

`Notifier._toast_script` builds the notification script as **text** and
substitutes the pet's name into it with GDScript's `String.replace`:

```gdscript
$doc.LoadXml(@"
<toast>...<text>{TITLE}</text>...</toast>
"@)
""".replace("{TITLE}", _xml_escape(title))
```

`@"` … `"@` is PowerShell's *expandable* here-string, and because the
substitution happens in GDScript the name is physically in the script source
before PowerShell parses it. So `$(...)` inside a pet name is a subexpression
PowerShell evaluates and runs. `_xml_escape` covers `&`, `<`, `>`, `"` and `'`
— the right escaping for the wrong parser, because two parsers read that text in
sequence: PowerShell's here-string expander first, `XmlDocument.LoadXml` second.

Proven with `redteam/tests/probe_d_injection.gd`: a pet name of
`$(Set-Content -Path <...>/rt_marker.txt -Value pwned-via-pet-name; Rex)` wrote
the marker file.

The name reaches here from three places, only the first of which is the owner:
the rename dialog and Settings, `pet_name` in `saves/pet.json` (a save file
people can pass around), and — for the icon variant, via `_file_uri` — the tray
icon filename in an **imported pack's** `ui.json`.

## What needs to be fixed

No byte of the title, the body or the icon path may end up as part of the
PowerShell script's source text. That is the whole defect; escaping it better
is not a fix, because the next parser down the line always disagrees about what
needs escaping.

## How it should be fixed, and why that way

Two changes, both of which remove interpolation rather than add escaping:

1. **Carry the three values as data, not as source.** Base64-encode each in
   GDScript and have the script decode them with
   `[Convert]::FromBase64String`, holding the base64 in *single*-quoted
   PowerShell strings. Base64's alphabet is `A-Za-z0-9+/=`, so an attacker's
   bytes cannot terminate the literal, and a single-quoted PowerShell string
   does not expand `$` in any case. This is the same reasoning that makes the
   existing `-EncodedCommand` sound — the author had the right idea and applied
   it one level too high up, protecting the shell argument while leaving the
   script it carries open.

2. **Build the XML through the DOM instead of by string substitution.** Load a
   fixed, value-free template, then attach each value with
   `$doc.CreateTextNode(...)` and `$image.SetAttribute(...)`. WinRT's
   `XmlDocument` escapes text nodes and attribute values itself, so the XML
   layer stops needing hand-written escaping at all.

Together these mean the script text is a constant: every untrusted byte arrives
as base64 and is only ever handled as a value.

`_xml_escape` then has nothing left to do and goes. `_file_uri` keeps its
backslash conversion — a `file:///` URI genuinely needs forward slashes — but
loses the `%20` substitution, because `SetAttribute` no longer cares about
spaces and percent-encoding only the space while leaving every other special
character alone was never right.

Deliberately **not** done: filtering `$` or backticks out of pet names at
`Needs.set_pet_name`. The report offered it as defence in depth, but it would
reject names that are perfectly reasonable and, after this fix, perfectly safe
— "Mr. $parkles" should keep working. Closing the hole where it actually is
leaves the owner's choice of name alone.

Verification plan: re-run `probe_d_injection.gd` against the new script shape
and confirm no marker file appears and the payload survives as inert text; then
show a real toast to confirm notifications still work, including the icon.

---

## What was fixed

`scripts/notifier.gd`. Net effect: 8 lines of escaping replaced by 14 lines of
DOM building, and the script template no longer has a `{TITLE}` in it.

### `_toast_script` — before

```gdscript
	var image_tag: String = ""
	if not icon.is_empty():
		image_tag = "<image placement=\"appLogoOverride\" src=\"file:///%s\"/>" % _file_uri(icon)

	return """$ErrorActionPreference = 'SilentlyContinue'
...
$doc.LoadXml(@"
<toast><visual><binding template="ToastGeneric"><text>{TITLE}</text><text>{BODY}</text>{IMAGE}</binding></visual></toast>
"@)
$toast = New-Object Windows.UI.Notifications.ToastNotification $doc
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('{APPID}').Show($toast)
""".replace("{TITLE}", _xml_escape(title)) \
   .replace("{BODY}", _xml_escape(body)) \
   .replace("{IMAGE}", image_tag) \
   .replace("{APPID}", POWERSHELL_APP_ID)
```

### `_toast_script` — after

```gdscript
	return """$ErrorActionPreference = 'SilentlyContinue'
...
$title = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('{TITLE}'))
$body = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('{BODY}'))
$icon = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('{ICON}'))
$doc = New-Object Windows.Data.Xml.Dom.XmlDocument
$doc.LoadXml('<toast><visual><binding template="ToastGeneric"><text></text><text></text></binding></visual></toast>')
$texts = $doc.GetElementsByTagName('text')
$texts.Item(0).AppendChild($doc.CreateTextNode($title)) | Out-Null
$texts.Item(1).AppendChild($doc.CreateTextNode($body)) | Out-Null
if ($icon -ne '') {
	$image = $doc.CreateElement('image')
	$image.SetAttribute('placement', 'appLogoOverride')
	$image.SetAttribute('src', 'file:///' + $icon)
	$doc.GetElementsByTagName('binding').Item(0).AppendChild($image) | Out-Null
}
$toast = New-Object Windows.UI.Notifications.ToastNotification $doc
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('{APPID}').Show($toast)
""".replace("{TITLE}", _base64(title)) \
   .replace("{BODY}", _base64(body)) \
   .replace("{ICON}", _base64(_file_uri(icon))) \
   .replace("{APPID}", POWERSHELL_APP_ID)
```

The only three substitutions left are base64, and `{APPID}` which is a constant
in this file.

### `_xml_escape` removed, `_base64` added

```gdscript
# The one way a value is allowed into the script: as base64, inside a
# single-quoted PowerShell string. Base64 is only A-Za-z0-9+/=, so nothing an
# attacker writes can end the literal, and a single-quoted string does not
# expand $ anyway. The script text itself stays a constant.
#
# An empty string is answered directly: raw_to_base64 pushes an engine error
# when handed nothing, and nothing is perfectly normal here - there may be no
# icon, and a body is sometimes left blank.
static func _base64(text: String) -> String:
	if text.is_empty():
		return ""
	return Marshalls.raw_to_base64(text.to_utf8_buffer())
```

That empty-string guard was not in the plan. The first run of the probe against
the new code caught it:

```
ERROR: Condition "ret.is_empty()" is true. Returning: ret
   at: raw_to_base64 (core/core_bind.cpp:1352)
   GDScript backtrace (most recent call first):
       [0] _base64 (res://scripts/notifier.gd:271)
```

`Marshalls.raw_to_base64` pushes an engine error when handed an empty buffer,
and empty is ordinary here — there may be no tray icon (`AssetLibrary.ui` is
null, or `assets/ui` has nothing usable), and `NotificationRules.body_for`
returns `""` for anything that is not one of the three needs. Left alone it
would have put an error in the log on every notification. The output was
already correct — PowerShell's `FromBase64String('')` gives an empty array —
so this was noise rather than breakage, but it was noise I introduced.

`_xml_escape` is gone: `CreateTextNode` and `SetAttribute` do that job in the
DOM, where it belongs. Nothing else called it (checked across `scripts/` and
`tests/`).

### `_file_uri` simplified

```gdscript
# A file:// URI wants forward slashes whatever Windows hands us. Spaces used
# to be percent-encoded here; they no longer need to be, because the path goes
# in through SetAttribute rather than into XML by hand.
static func _file_uri(path: String) -> String:
	return path.replace("\\", "/")
```

## Test result after the fix

`redteam/tests/probe_d_injection.gd` was updated to drive the real
`Notifier._toast_script` shape as it now stands, rather than a copy of the old
one, so it cannot drift:

```
--- the XML PowerShell actually produced ---
<toast><visual><binding template="ToastGeneric"><text>$(Set-Content -Path
.../rt_marker.txt -Value pwned-via-pet-name; Rex) is starving!</text>
<text>Time to feed.</text></binding></visual></toast>
--- marker exists: false ---
```

The payload is still there, in full, as **text** — which is correct; a dog may
legitimately be called anything, and the name should display as written. It is
no longer executed. Before the fix this same probe printed
`marker exists: true` and an empty `<text>` element, the subexpression having
been consumed by PowerShell.

Also checked:

- The `<`, `&`, `>`, `"` and `'` characters a name might contain are escaped by
  the DOM (`&lt;&amp;&gt;"'` in the produced XML), so the one thing
  `_xml_escape` was right about is still handled.
- A real toast was raised, with the tray icon showing, and PowerShell reported
  no error — so this is not a fix that quietly stops notifications working.
- The `wscript` route (`notification_launcher: "wscript"`) carries the same
  script and is fixed by the same change.
- No engine errors or warnings in the log for an empty body or a missing icon,
  after the guard above.

### The non-ASCII scare

`probe_j_toast_live.gd` printed the built XML and "Bíscuit" came back as
"B¡scuit", which looked like the base64 round-trip mangling the name. It was
not: that probe reads PowerShell's stdout, and the codepage it uses for the
console is not UTF-8.

`redteam/tests/probe_k_encoding.gd` settles it by asking PowerShell to report
the decoded title's **code points**, which no codepage can distort:

```
name in Godot:             Bíscuit 日本 ok
code points in Godot:      66,237,115,99,117,105,116,32,26085,26412,32,111,107
code points in PowerShell: 66,237,115,99,117,105,116,32,26085,26412,32,111,107
they match: true
```

Identical, Japanese included. The name arrives in PowerShell intact; only the
probe's own printout was lying. Worth having chased down — a fix that quietly
mangled every accented dog name would have been a poor trade for closing an
injection.

### The whole suite

**654 checks, 0 failures** after both Criticals were fixed (`test_needs` 157,
`test_pets` 105, `test_scenes` 88, `test_life` 85, `test_packs` 73,
`test_notify` 62, `test_integration` 47, `test_history` 37), and
`godot --headless --path . --quit` reports no script errors.

## How it relates to the rest of the app

- **`Notifier.send_toast` / `_launch_via_powershell` / `_launch_via_wscript`** —
  all three take the script from `_toast_script`, so all three are fixed here.
  No change was needed in them.
- **`Notifier.announce` / `deliver` / `send_test`** — unchanged. Titles still
  come from `NotificationRules.title_for`, which still interpolates the pet
  name into a GDScript string; that is fine, because the result is now data.
- **`Needs.set_pet_name` / `start_new_pet`, `Needs._ready:87`** — still accept
  any name, including one out of a `pet.json` someone sent. Intentional: see
  above.
- **`Tray.hide_to_tray:107`** — sends the pet name through `send_toast` for the
  one-time tray notice. Same path, same fix.
- **`UiPack.tray_icon_path` / `tray_alert_path`** — the icon filename out of an
  imported `ui.json` was the second way in. Now goes through `SetAttribute`.
- **`Banner.show_message`** — the in-app route for the same messages. Never
  touched PowerShell, was never affected.
- **RT-12** (`saves/notify.vbs`) is a separate finding about *where* the helper
  script lives and is not addressed here; with RT-01 closed it no longer
  carries an injected payload, which was the part that mattered.
