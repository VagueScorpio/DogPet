class_name PackLinks
extends RefCounted
## Deciding which of a pack's links are safe to follow.
##
## A pack's own JSON says where its licence and source links point, and a pack
## is a file people download and pass to each other. OS.shell_open - which is
## what a clicked link ends up calling - will open a document, launch an
## executable, resolve a bare command name off the PATH, or hand the string to
## any protocol handler Windows happens to know. So "licence_url" is not a
## promise, it is a claim, and it has to be checked before it is acted on.
##
## Kept apart from CreditsList, which builds the labels and the buttons, for
## the same reason NotificationRules is kept apart from Notifier: this is a
## rule worth testing, and CreditsList cannot be tested headlessly because it
## names the AssetLibrary autoload, which a --script run compiles before the
## autoloads have names. Nothing here touches a node or an autoload.

## The only two schemes that belong in a credit.
const WEB_SCHEMES: PackedStringArray = ["http://", "https://"]


## The URL if it is a plain web address, or "" if it is anything else.
##
## An allow-list rather than a list of dangerous schemes: which schemes are
## dangerous depends on what is installed on the owner's machine, and this
## cannot know that. Everything that is not obviously a web page is refused,
## and the caller shows it as text instead - so a credit stays readable, which
## some of the licences DogPet ships under actually require, without the
## owner being one click away from running whatever a pack names.
static func web_url(raw: String) -> String:
	var url: String = raw.strip_edges()
	var lower: String = url.to_lower()
	var scheme: String = ""
	for candidate in WEB_SCHEMES:
		if lower.begins_with(candidate):
			scheme = candidate
			break
	# No scheme, or nothing after it, means there is nothing to open.
	if scheme.is_empty() or url.length() == scheme.length():
		return ""
	# A URL has no business holding a space, a tab, a newline or a control
	# character. One that does is either a mistake or an attempt at something.
	for index in url.length():
		if url.unicode_at(index) <= 32:
			return ""
	return url


## True when this link can be shown as a button rather than as plain text.
static func is_web_url(raw: String) -> bool:
	return not web_url(raw).is_empty()
