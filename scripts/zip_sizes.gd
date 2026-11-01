class_name ZipSizes
extends RefCounted
## How big each entry in a zip claims to be, read without decompressing it.
##
## ZIPReader in this Godot build will not say - it offers open, close,
## get_files, read_file, file_exists and get_compression_level, and nothing
## about size. So the figures are read out of the zip's own central directory
## here, with FileAccess, before anything is handed to ZIPReader.
##
## Why a declared size is worth trusting for this purpose, when a zip's
## metadata is otherwise only a claim: ZIPReader.read_file asks minizip for the
## entry's uncompressed size, resizes its buffer to exactly that, and reads at
## most that many bytes. The declaration therefore *is* the allocation. A zip
## that under-declares cannot make Godot allocate more than it said; it only
## gets a truncated read. So refusing an entry that declares too much really
## does bound the memory, which is what PackArchive needs of it.
##
## Nothing here touches a node or an autoload, so the tests can drive it.

## The four-byte marker that starts a central-directory record. The end-of-
## directory marker is compared byte by byte in _find_eocd instead.
const CENTRAL_SIGNATURE := 0x02014b50

## An End of Central Directory record is 22 bytes plus a comment of up to
## 65535, so it cannot start further back than this from the end of the file.
const EOCD_MIN_BYTES := 22
const MAX_COMMENT_BYTES := 65535

## A fixed central-directory record is 46 bytes before its variable-length
## name, extra field and comment.
const CENTRAL_FIXED_BYTES := 46

## What a 32-bit size field holds when the real figure has been moved into a
## Zip64 extra field, and what the entry count holds when there are too many
## to express. Either way this refuses the zip rather than chasing the figure.
const ZIP64_SIZE_MARKER := 0xFFFFFFFF
const ZIP64_COUNT_MARKER := 0xFFFF


## Measure a zip.
##
## Returns {"sizes": {entry_name: bytes}, "total": int, "problem": String}.
## A non-empty "problem" means the zip could not be measured, and the caller
## should refuse it rather than read it: a size that cannot be established is
## the whole reason this exists.
static func read(zip_path: String) -> Dictionary:
	var out: Dictionary = {"sizes": {}, "total": 0, "problem": ""}

	var file: FileAccess = FileAccess.open(zip_path, FileAccess.READ)
	if file == null:
		out["problem"] = "that file could not be opened"
		return out
	# Zip stores every number little-endian, which is FileAccess's default,
	# but say so rather than rely on it.
	file.big_endian = false

	var length: int = file.get_length()
	if length < EOCD_MIN_BYTES:
		file.close()
		out["problem"] = "that file is too small to be a zip"
		return out

	var eocd: int = _find_eocd(file, length)
	if eocd < 0:
		file.close()
		out["problem"] = "the zip has no readable index"
		return out

	file.seek(eocd + 10)
	var count: int = file.get_16()
	file.seek(eocd + 12)
	var directory_bytes: int = file.get_32()
	file.seek(eocd + 16)
	var directory_at: int = file.get_32()

	# Zip64 is for archives past 4 GB or past 65535 entries. A pet or a room is
	# neither, so this refuses rather than growing a second parser for it.
	if (count == ZIP64_COUNT_MARKER
			or directory_at == ZIP64_SIZE_MARKER
			or directory_bytes == ZIP64_SIZE_MARKER):
		file.close()
		out["problem"] = "the zip is in the zip64 format, which packs do not need"
		return out

	if directory_at < 0 or directory_at + directory_bytes > length:
		file.close()
		out["problem"] = "the zip's index points outside the file"
		return out

	var sizes: Dictionary = {}
	var total: int = 0
	var at: int = directory_at
	for _index in count:
		if at + CENTRAL_FIXED_BYTES > length:
			file.close()
			out["problem"] = "the zip's index is cut short"
			return out
		file.seek(at)
		if file.get_32() != CENTRAL_SIGNATURE:
			file.close()
			out["problem"] = "the zip's index is not in the expected shape"
			return out

		file.seek(at + 24)
		var uncompressed: int = file.get_32()
		file.seek(at + 28)
		var name_bytes: int = file.get_16()
		file.seek(at + 30)
		var extra_bytes: int = file.get_16()
		file.seek(at + 32)
		var comment_bytes: int = file.get_16()

		if uncompressed == ZIP64_SIZE_MARKER:
			file.close()
			out["problem"] = "an entry's size is only given in zip64 form"
			return out

		file.seek(at + CENTRAL_FIXED_BYTES)
		var name: String = file.get_buffer(name_bytes).get_string_from_utf8()
		if name.is_empty() and name_bytes > 0:
			file.close()
			out["problem"] = "an entry's name could not be read"
			return out

		# Folder entries are listed with a size of zero and nothing to read.
		sizes[name] = uncompressed
		total += uncompressed
		at += CENTRAL_FIXED_BYTES + name_bytes + extra_bytes + comment_bytes

	file.close()
	out["sizes"] = sizes
	out["total"] = total
	return out


## What one entry claims to be, or -1 when the zip did not list it.
##
## ZIPReader.get_files() reports entries with forward slashes; a zip written on
## Windows may have stored backslashes, so both spellings are tried.
static func size_of(sizes: Dictionary, entry: String) -> int:
	if sizes.has(entry):
		return int(sizes[entry])
	var slashed: String = entry.replace("\\", "/")
	for name in sizes.keys():
		if str(name).replace("\\", "/") == slashed:
			return int(sizes[name])
	return -1


## "600.0 MB", "256.0 KB", "512 bytes" - for saying why something was refused.
static func describe_bytes(bytes: int) -> String:
	if bytes < 1024:
		return "%d bytes" % bytes
	if bytes < 1024 * 1024:
		return "%.1f KB" % (bytes / 1024.0)
	return "%.1f MB" % (bytes / 1048576.0)


# Walk back from the end of the file looking for the End of Central Directory
# marker. It sits 22 bytes from the end unless the zip carries a comment, which
# can be up to 65535 bytes, so that is how far back this looks. Searching from
# the end rather than the start is what the format requires: the fixed part is
# at the end and everything else is found from it.
static func _find_eocd(file: FileAccess, length: int) -> int:
	var window: int = mini(length, MAX_COMMENT_BYTES + EOCD_MIN_BYTES)
	var from: int = length - window
	file.seek(from)
	var tail: PackedByteArray = file.get_buffer(window)
	# Latest match wins: a zip holding another zip's bytes as data could carry
	# an earlier marker that is not the real one.
	var at: int = tail.size() - EOCD_MIN_BYTES
	while at >= 0:
		if (tail[at] == 0x50 and tail[at + 1] == 0x4b
				and tail[at + 2] == 0x05 and tail[at + 3] == 0x06):
			return from + at
		at -= 1
	return -1
