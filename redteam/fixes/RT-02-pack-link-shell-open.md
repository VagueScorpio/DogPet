# RT-02: Arbitrary program launch from a pack's licence link

Severity: Critical
Location: `scripts/credits_list.gd:128-134` (`_link`), used by `_entry_block`

## The finding

```gdscript
static func _link(text: String, url: String) -> LinkButton:
	...
	button.pressed.connect(func() -> void: OS.shell_open(url))
```

`url` is `license_url` or `source_url` taken straight out of a pack's
`pet.json` or `scene.json`. `PetPack.from_dictionary:86-87` and
`ScenePack.from_dictionary:89-90` only `str().strip_edges()` them, and nothing
between the file and the OS checks what sort of string it is.

`OS.shell_open` on Windows is `ShellExecuteW`, which will open a document,
launch an executable, resolve a bare command name off the `PATH`, or hand the
string to any registered protocol handler. The button's visible text is the
*licence name* ("CC-BY 3.0"), so a hostile pack shows an entirely ordinary
licence link.

Proven with `redteam/tests/probe_e_shell_open.gd`: a `license_url` pointing at
a `.cmd` file ran it. Variants needing no file on disk include `calc.exe` (off
the `PATH`) and `\\attacker\share\payload.exe` (an executable on a remote SMB
share).

The route is: import a pack someone sent you, open Settings → About, click the
link beside its credit.

## What needs to be fixed

Only a plain web address may ever reach `OS.shell_open` from pack data.

There is a competing requirement that has to be respected, and it is the whole
reason this screen exists: **the credit and its licence URI are a licence
obligation.** `CLAUDE.md` §8 and the header comment on `CreditsList` both say
so — the default pug is CC-BY 3.0 and its credit must stay visible. So the fix
must not simply drop a URL it dislikes; hiding the licence URI would trade a
security hole for a licensing one. A refused URL has to stay on screen, just
not be clickable.

## How it should be fixed, and why that way

One new validator and a changed `_entry_block`:

1. `web_url(raw)` returns the string only when it begins with `http://` or
   `https://` (case-insensitively, after trimming) and contains no whitespace
   or control characters; otherwise `""`. An allow-list of two schemes, not a
   deny-list of dangerous ones — a deny-list would have to anticipate every
   protocol handler installed on the owner's machine, which is not knowable.
2. `_entry_block` makes a `LinkButton` only when `web_url` returns something.
   When it refuses, the URL is shown as a plain dimmed `Label` instead, so the
   information survives, the owner can read exactly what the pack claimed, and
   nothing fires on a click.

The guard goes here, at the `shell_open` call, rather than in `PetPack` /
`ScenePack`. That is deliberate: this is the only place a pack's URL is ever
acted on, so one check here covers it completely, whereas validating at load
time would leave the dangerous call itself unguarded for any future caller.
Validating in the pack loaders as well — so a refusal lands in `problems` and
the log — is worth doing, but it is an addition, not this fix, and it would
mean touching `PetPack`, `ScenePack` and their two test suites.

Verification plan: re-run `probe_e_shell_open.gd` and confirm the payload is no
longer launched, then check that an ordinary `https://` credit still produces a
working link and that a refused URL is still displayed.

---

## What was fixed

`scripts/pack_links.gd` (new), `scripts/credits_list.gd`, `tests/test_packs.gd`.

### Where the rule ended up, and why it moved

The plan above put `web_url` in `CreditsList`. Writing the verification probe
proved that wrong: `CreditsList` cannot be loaded in a `--script` run at all,
because `gather()` names the `AssetLibrary` autoload and a `--script` run is
compiled before the autoloads have names.

```
SCRIPT ERROR: Compile Error: Identifier not found: AssetLibrary
   at: GDScript::reload (res://scripts/credits_list.gd:41)
```

So a security rule living there could never be tested — and this project's own
convention exists for precisely that reason. `NeedsModel`, `LifeModel`,
`NotificationRules`, `CareSettings`, `ActionPlan` and `ImageLimits` are each a
pure, node-free, autoload-free class split out of the thing that uses them,
with `ImageLimits` saying so outright: "a script that names an autoload cannot
be compiled by a `--script` run at all".

The rule therefore went into a new `scripts/pack_links.gd` (`class_name
PackLinks`), in the same shape as those. `CreditsList` stays what it was: the
thing that builds the labels and the buttons.

### Added — `scripts/pack_links.gd`

```gdscript
class_name PackLinks
extends RefCounted

## The only two schemes that belong in a credit.
const WEB_SCHEMES: PackedStringArray = ["http://", "https://"]

static func web_url(raw: String) -> String:
	var url: String = raw.strip_edges()
	var lower: String = url.to_lower()
	var scheme_ok: bool = false
	for scheme in WEB_SCHEMES:
		if lower.begins_with(scheme):
			scheme_ok = true
			break
	if not scheme_ok:
		return ""
	# There has to be something after the scheme, or there is nothing to open.
	for scheme in WEB_SCHEMES:
		if lower == scheme:
			return ""
	# A URL has no business holding a space, a tab, a newline or a control
	# character. One that does is either a mistake or an attempt at something.
	for index in url.length():
		if url.unicode_at(index) <= 32:
			return ""
	return url

static func is_web_url(raw: String) -> bool:
	return not web_url(raw).is_empty()
```

An allow-list of the two schemes that belong in a credit, not a deny-list of
dangerous ones: which schemes are dangerous depends on what is installed on the
owner's machine, and this cannot know that.

`CreditsList` reaches it by `preload` rather than by its `class_name`, the same
way `CareSettings` reaches `NeedsModel` — a newly added script is not in the
editor-generated class cache until the editor rescans, and a headless build
should not have to wait for that. Using the `class_name` broke
`--headless --quit` until this was changed:

```
SCRIPT ERROR: Parse Error: Identifier "PackLinks" not declared in the current scope.
ERROR: Failed to load script "res://scripts/settings_panel.gd" with error "Compilation failed".
```

### Changed — `_entry_block`

Before, the licence and source branches called `_link` with whatever the pack
said. Now each asks `web_url` first and falls back to a plain label:

```gdscript
	var licence_url: String = PackLinks.web_url(str(entry["license_url"]))
	if not licence_url.is_empty():
		var label: String = str(entry["license"])
		links.add_child(_link(
			label if not label.is_empty() else "Licence", licence_url
		))
		any = true
	elif not str(entry["license"]).is_empty():
		links.add_child(_plain(str(entry["license"])))
		any = true
	# A licence URI that is not a web address still has to be readable: showing
	# it is a condition of some of the licences this screen exists to satisfy.
	if licence_url.is_empty() and not str(entry["license_url"]).strip_edges().is_empty():
		links.add_child(_plain(str(entry["license_url"])))
		any = true

	var source_url: String = PackLinks.web_url(str(entry["source_url"]))
	if not source_url.is_empty():
		links.add_child(_link("Source", source_url))
		any = true
	elif not str(entry["source_url"]).strip_edges().is_empty():
		links.add_child(_plain(str(entry["source_url"])))
		any = true
```

### Added — `_plain`

```gdscript
# A URL shown but not armed, in the same quiet style as the rest of the block.
static func _plain(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	return label
```

`_link` itself is unchanged — it is now only ever handed a validated URL.

### Added — a permanent regression test

`tests/test_packs.gd` gained `_test_pack_links()`, 17 checks, sitting beside the
zip-slip section it is the sibling of ("The other nasty case"). The red team
probe proves the break is closed today; this is what stops it reopening.

## Test result after the fix

`redteam/tests/probe_e_shell_open.gd`, rewritten to preload `PackLinks` (it
cannot preload `CreditsList`, which is the point above):

```
license_url kept verbatim by the pack loader: true
web_url refuses it: true
the link is never armed, so there is nothing to click
marker exists: false

--- and the shipped pug pack still links properly ---
  license_url allowed: true    https://creativecommons.org/licenses/by/3.0/
  source_url allowed:  true    https://poly.pizza/m/3nFZQW8yojl
```

Before the fix this same probe printed `marker exists: true`, the pack having
launched a program. The real pug credit's links are read from the actual
`assets/pets/pug_3d/pet.json` and both still pass, so the shipped pack's
attribution works exactly as before.

`tests/test_packs.gd`, all 17 new checks passing:

```
Only plain web addresses become clickable links
  PASS  allowed: https://creativecommons.org/licenses/by/3.0/
  PASS  allowed: https://poly.pizza/m/3nFZQW8yojl
  PASS  allowed: http://example.com/licence.txt
  PASS  the scheme is matched whatever its case
  PASS  surrounding whitespace is trimmed rather than refused
  PASS  refused: calc.exe
  PASS  refused: C:/Windows/System32/calc.exe
  PASS  refused: file:///C:/Windows/System32/calc.exe
  PASS  refused: \\host\share\p.exe
  PASS  refused: ms-settings:
  PASS  refused: javascript:alert(1)
  PASS  refused: pack.zip
  PASS  refused: (blank)          [empty string]
  PASS  refused: (blank)          [whitespace only]
  PASS  refused: https://         [nothing to open]
  PASS  refused: https://example.com/a b
  PASS  refused: https://example.com/a\ncalc.exe
```

Whole suite afterwards: **654 checks, 0 failures** (test_packs 56 → 73), and
`godot --headless --path . --quit` reports no script errors. The integration
suite's `panels_build` scenario builds the real Settings screen — including the
About section and this credits block — with the real autoloads, and passes.

## How it relates to the rest of the app

- **`PackLinks`** (new) — the rule, pure and testable. Follows the pattern of
  `NotificationRules`, `ActionPlan`, `ImageLimits` and `CareSettings`.
- **`CreditsList._entry_block` / `_link`** — the fixed code. `_link` is now
  only reachable with a validated URL, and says so in a comment.
- **`SettingsPanel._build_about:294`** — the only caller of
  `CreditsList.build_into`. Unchanged; it gets the same block, with any
  non-web URL rendered as text.
- **`PetPack.license_url` / `source_url`, `ScenePack.license_url` /
  `source_url`** — still stored verbatim. That is fine now that nothing acts
  on them unchecked, and it keeps the loaders' job to parsing. Flagged above as
  a worthwhile addition rather than part of this fix.
- **`Paths.open_in_file_manager:104`** — the app's other `OS.shell_open` call,
  on `Paths.assets_dir` or `Paths.saves_dir`. App-controlled, never from pack
  data, left alone.
- **`SettingsPanel._build_about`'s folder `LinkButton`s** — same thing: they
  call `Paths.open_in_file_manager` on the app's own folders.
- **`PackArchive.inspect`** — validates a pack's *paths* on import but never
  looked at its URLs; it still does not, because by the time a URL matters the
  pack is already installed and the guard above covers every reader.
- **RT-03** (zip bomb) is in the same import path and is not addressed here.
