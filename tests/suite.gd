extends SceneTree
## The scaffolding every test suite shares: the two counters, the PASS and
## FAIL lines, the float comparison, and the closing tally.
##
## Pulled out because all eight suites carried a byte-identical copy of it.
##
## What this prints is a contract, not a convenience. tools/build.ps1 decides
## whether a release may proceed by grepping "^  FAIL" and
## "^\d+ passed, \d+ failed", and it reads the exit code to tell a failing
## suite from a crashed one. None of these strings may change.
##
## Extended by path rather than by a class_name: a --script run is compiled
## before the editor's class cache is available, which is the same reason the
## pure model classes are reached by preload.

var _passed: int = 0
var _failed: int = 0

# Kept so _report can underline with a rule of the same width the title used.
var _title: String = ""


## The suite's heading. The rule underneath is the title's own width.
func _open(title: String) -> void:
	_title = title
	print("")
	print(title)
	print("=".repeat(title.length()))


## A heading above the next group of checks.
func _begin(section: String) -> void:
	print("")
	print(section)


## One check. The only place PASS and FAIL are ever printed.
func _ok(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("  PASS  " + label)
	else:
		_failed += 1
		print("  FAIL  " + label)


## One check on a float, with both numbers shown when it fails - which is
## what makes a drift of a hundredth diagnosable rather than just red.
func _close(label: String, got: float, want: float, tolerance: float = 0.01) -> void:
	if absf(got - want) <= tolerance:
		_ok(label, true)
	else:
		_ok(label, false)
		print("          got %.4f, wanted %.4f" % [got, want])


## The tally, and the exit code the build script reads.
func _report() -> void:
	print("")
	print("=".repeat(_title.length()))
	print("%d passed, %d failed" % [_passed, _failed])
	print("TESTS FAILED" if _failed > 0 else "All good.")
	quit(1 if _failed > 0 else 0)
