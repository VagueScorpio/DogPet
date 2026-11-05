class_name ImageLimits
extends RefCounted
## How large an image from assets/ is allowed to be, and how to find that
## out without decoding it first.
##
## A PNG's pixel count has little to do with its file size: a 200-megapixel
## sprite sheet can zip down to a couple of megabytes and then ask for most
## of a gigabyte the moment it is decoded. assets/ is a folder the owner is
## invited to drop their own art into, so the size is read out of the file's
## header and an enormous one is refused rather than allocated and then
## thought better of.
##
## Pure on purpose: no nodes, no autoloads, nothing to log to. PetLoader does
## the warning and the refusing; this only answers the question. That is also
## what lets the headless tests ask it directly, because a script that names
## an autoload cannot be compiled by a --script run at all.

## The most pixels this app will decode out of one image.
##
## 8192 x 4096, which is about 128 MB once it is in memory as RGBA8 - far
## more than any room or sprite sheet needs, and small enough not to matter.
const MAX_PIXELS := 33554432

## The longest side a picture this app builds may have.
##
## MAX_PIXELS is about memory. This is about the graphics card, which is a
## different limit and a nastier one: a texture wider than the driver allows
## is not refused with an error anybody sees. It comes back blank, or black,
## or not at all, and the dog simply is not there.
##
## It bites on strips rather than on anything downloaded, because a strip is
## as wide as all its frames put together: twenty-one hand-painted frames at
## 300 pixels each come to 6300, and sixty would come to 18000.
##
## 8192 because this is a Windows desktop app on the Compatibility renderer,
## where every GPU that can run Godot 4 at all reports at least that. The
## figures the standards actually guarantee - 1024 for desktop GL, 2048 for
## GL ES - are far below anything sold this century, and holding good art to
## them would mean shrinking it for a machine nobody has.
const MAX_TEXTURE_SIDE := 8192

## The first eight bytes of every PNG ever written.
const PNG_SIGNATURE: Array[int] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

## How much of the file has to be read to learn its size.
const HEADER_BYTES := 24

## The largest side this will report.
##
## Vector2i holds 32-bit components, so a PNG declaring 4294967295 wide used to
## wrap round to -1 and be mistaken for "size unknown" - which is_too_large
## treats as never too large, so the one file the guard existed to refuse went
## straight to the decoder.
##
## Saturating is honest rather than clever: the file really is at least this
## big, the figure stays positive so it still reads as known, and is_too_large
## refuses it immediately. Vector2i.ZERO keeps meaning "could not be read".
const MAX_SIDE := 0x7FFFFFFF


## True for a size with more pixels than this app will decode.
##
## A zero or negative size means "not known" - an unreadable file, or one
## that is not a PNG - and is never too large, because refusing a file on
## the strength of not having understood it would mean refusing every format
## this does not read the header of.
static func is_too_large(size: Vector2i) -> bool:
	if size.x <= 0 or size.y <= 0:
		return false
	return size.x * size.y > MAX_PIXELS


## True for a size with a side longer than a texture may be.
##
## Unlike is_too_large this is not a refusal: a strip that comes out too
## wide is shrunk until it fits, because the alternative is art that looks
## right in the folder and is invisible in the app.
static func is_too_wide(size: Vector2i) -> bool:
	return size.x > MAX_TEXTURE_SIDE or size.y > MAX_TEXTURE_SIDE


## A PNG's dimensions, read from its first 24 bytes. Zero when the file is
## missing, too short, or not a PNG at all.
##
## Every PNG begins with the signature above, followed by the IHDR chunk:
## four bytes of length, "IHDR", then the width and the height as big-endian
## 32-bit numbers. That is all this needs, and reading it costs nothing next
## to decoding the picture.
static func png_size_from_header(path: String) -> Vector2i:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Vector2i.ZERO
	var header: PackedByteArray = file.get_buffer(HEADER_BYTES)
	file.close()
	if header.size() < HEADER_BYTES:
		return Vector2i.ZERO

	for index in PNG_SIGNATURE.size():
		if header[index] != PNG_SIGNATURE[index]:
			return Vector2i.ZERO

	# Clamped on the way into the Vector2i, not after: past 2^31 the component
	# would already have wrapped negative and the size would read as unknown.
	return Vector2i(
		mini(_big_endian_u32(header, 16), MAX_SIDE),
		mini(_big_endian_u32(header, 20), MAX_SIDE)
	)


## A one-line reason for the log, for a size that has been refused.
static func describe(path: String, size: Vector2i) -> String:
	return "Skipping %s: %d x %d is more than the %d pixels this app will load." % [
		path.get_file(), size.x, size.y, MAX_PIXELS,
	]


# PackedByteArray.decode_u32 reads little-endian, and PNG is big-endian.
static func _big_endian_u32(bytes: PackedByteArray, at: int) -> int:
	return (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3]
