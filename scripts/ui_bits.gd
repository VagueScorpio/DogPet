class_name UiBits
extends RefCounted
## The small pieces the panels are built out of: a heading, a dimmed line of
## explanation, a row, a button, and a duration said plainly.
##
## These are the house style rather than anything clever, and they were
## sitting inside SettingsPanel where nothing else could reach them. The
## Scoreboard and the credits list still build their own labels by hand;
## they can come through here too.
##
## Static on purpose: a builder that needs no state should not need an
## instance either.

## The fill and border the full-screen panels share: the settings screen, the
## instructions and the scoreboard. The cards that sit over the window have
## their own colours, because they are meant to read as something on top
## rather than as the screen itself.
const PANEL_FILL := Color(0.13, 0.14, 0.18)
const PANEL_BORDER := Color(1, 1, 1, 0.15)


## The frame a panel or a card is drawn in: a flat fill, a hairline border and
## rounded corners.
##
## Godot's default panel is translucent, which left whatever was behind
## showing through the text on top of it. Six screens were each assembling
## this by hand.
static func panel_style(fill: Color, border: Color, corner: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(corner)
	return style


## Plain text at a given size, and a colour if it wants one.
##
## The colour override is only applied when one is asked for, so a heading
## with no colour is exactly the label it always was - the theme's own colour
## rather than an explicit white.
static func heading(text: String, size: int, colour: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	if colour != Color.WHITE:
		label.add_theme_color_override("font_color", colour)
	return label


## A quieter line, for explaining what a setting does.
##
## Wrapping is right for a paragraph and wrong for a table cell or a short
## row label, which will shrink to one character per line given the chance.
static func dim(
	text: String, size: int, min_width: float = 0.0, wrap: bool = true,
	colour: Color = Color(1, 1, 1, 0.6)
) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if min_width > 0.0:
		label.custom_minimum_size = Vector2(min_width, 0)
	return label


## A horizontal row, already added to its parent.
static func row(parent: Control) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	parent.add_child(line)
	return line


static func button(text: String, action: Callable) -> Button:
	var pressable := Button.new()
	pressable.text = text
	pressable.pressed.connect(action)
	return pressable


## "40 min", "3 h", "45 s" - whichever reads most plainly.
##
## `compact` drops the space and shortens the unit, for the care menu, where
## three of these sit side by side on one line: "40m / 45m / 50m".
static func duration(seconds: float, compact: bool = false) -> String:
	if seconds < 60.0:
		return ("%ds" if compact else "%d s") % roundi(seconds)
	if seconds < 3600.0:
		return ("%dm" if compact else "%d min") % roundi(seconds / 60.0)
	var hours: float = seconds / 3600.0
	if is_equal_approx(hours, roundf(hours)):
		return ("%dh" if compact else "%d h") % roundi(hours)
	return ("%.1fh" if compact else "%.1f h") % hours


## "7 days old (Young)", or "newborn (Puppy)" for one just started.
##
## The number itself is LifeModel's to format; this only joins it to the life
## stage. One wording in one place, so the header on the main screen and the
## Scoreboard's entry for the living dog cannot drift apart.
static func age_line(days: float, stage: String) -> String:
	return "%s (%s)" % [LifeModel.format_age(days), stage]
