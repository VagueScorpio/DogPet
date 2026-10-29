<#
.SYNOPSIS
    Builds the shipped DogPet zip: DogPet.exe plus a loose assets folder.

.DESCRIPTION
    Runs the headless tests, exports the Windows build, copies assets/ in
    beside the exe, writes the README the player sees, and zips the lot.

    The zip is deliberately plain: unzip it anywhere and run the exe. There
    is no installer and nothing is written outside the folder, which is why
    assets/ travels loose rather than being baked into the exe.

.PARAMETER GodotPath
    The Godot executable. Defaults to "godot" on the PATH.

.PARAMETER SkipTests
    Skip the headless test suites. They take a few seconds and have caught
    real bugs, so this is here for when you already ran them.

.EXAMPLE
    .\tools\build.ps1
    .\tools\build.ps1 -GodotPath "C:\Godot\Godot_v4.7.2-stable_win64.exe"
#>

[CmdletBinding()]
param(
    [string] $GodotPath = "godot",
    [switch] $SkipTests
)

$ErrorActionPreference = "Stop"

# --- Where everything is -------------------------------------------------

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$BuildRoot   = Join-Path $ProjectRoot "build"
$AssetsDir   = Join-Path $ProjectRoot "assets"

function Write-Step([string] $Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Fail([string] $Message) {
    Write-Host ""
    Write-Host "BUILD FAILED: $Message" -ForegroundColor Red
    exit 1
}

# --- Check we can actually build ----------------------------------------

Write-Step "Checking Godot"

$godot = (Get-Command $GodotPath -ErrorAction SilentlyContinue)
if (-not $godot) { Fail "Could not find Godot at '$GodotPath'. Pass -GodotPath with the full path to the Godot executable." }
$GodotExe = $godot.Source

$version = & $GodotExe --version 2>&1 | Select-Object -First 1
Write-Host "    $GodotExe"
Write-Host "    $version"

# The templates are a separate download and are the usual reason a first
# build fails, so say so plainly rather than letting Godot's error through.
# Godot makes this folder whether or not anything is in it, so look for an
# actual template rather than just the folder.
$templateRoot = Join-Path $env:APPDATA "Godot\export_templates"
$haveTemplate = $false
if (Test-Path $templateRoot) {
    $haveTemplate = @(Get-ChildItem -Path $templateRoot -Recurse -File -Filter "windows_release_x86_64.exe" -ErrorAction SilentlyContinue).Count -gt 0
}
if (-not $haveTemplate) {
    Fail @"
No Godot export templates are installed, so there is nothing to build an
.exe from. In the Godot editor:

    Editor  ->  Manage Export Templates...  ->  Download and Install

Then run this script again.
"@
}

# --- The version the build is called after -------------------------------

Write-Step "Reading the version"

$projectFile = Join-Path $ProjectRoot "project.godot"
$versionLine = Select-String -Path $projectFile -Pattern '^config/version="(.+)"$' | Select-Object -First 1
if (-not $versionLine) { Fail "No config/version found in project.godot." }
$AppVersion = $versionLine.Matches[0].Groups[1].Value
Write-Host "    DogPet v$AppVersion"

$StageName = "DogPet-v$AppVersion"
$StageDir  = Join-Path $BuildRoot $StageName
$ZipPath   = Join-Path $BuildRoot "$StageName.zip"

# --- Tests ---------------------------------------------------------------

if (-not $SkipTests) {
    Write-Step "Running the tests"
    $suites = @("test_needs", "test_pets", "test_scenes", "test_notify", "test_packs")

    # Capturing a native program's stderr in Windows PowerShell wraps every
    # line as an error, and with ErrorActionPreference Stop that aborts the
    # build. The tests deliberately provoke engine errors - test_needs feeds
    # a corrupt file to the JSON parser on purpose - so those lines are
    # expected output, not failures. The exit code is what decides.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        foreach ($suite in $suites) {
            $output = & $GodotExe --headless --path $ProjectRoot --script "res://tests/$suite.gd" 2>&1
            $exitCode = $LASTEXITCODE
            $summary = $output | Select-String -Pattern '^\d+ passed, \d+ failed$' | Select-Object -Last 1
            if ($exitCode -ne 0) {
                $output | Select-String -Pattern "^  FAIL" | ForEach-Object {
                    Write-Host "    $_" -ForegroundColor Red
                }
                $ErrorActionPreference = $previous
                Fail "$suite failed."
            }
            Write-Host ("    {0,-14} {1}" -f $suite, $summary)
        }
    }
    finally {
        $ErrorActionPreference = $previous
    }
}

# --- Export --------------------------------------------------------------

Write-Step "Exporting"

if (Test-Path $StageDir) { Remove-Item -Recurse -Force $StageDir }
New-Item -ItemType Directory -Force -Path $StageDir | Out-Null

# Make sure Godot's caches exist before exporting; a fresh clone has none.
& $GodotExe --headless --path $ProjectRoot --import | Out-Null

$ExePath = Join-Path $StageDir "DogPet.exe"
& $GodotExe --headless --path $ProjectRoot --export-release "Windows Desktop" $ExePath
if (-not (Test-Path $ExePath)) { Fail "Godot did not produce $ExePath." }

$exeSize = [math]::Round((Get-Item $ExePath).Length / 1MB, 1)
Write-Host "    DogPet.exe  ($exeSize MB, with the PCK embedded)"

# --- The loose assets folder --------------------------------------------

Write-Step "Copying assets"

$StageAssets = Join-Path $StageDir "assets"
Copy-Item -Recurse -Path $AssetsDir -Destination $StageAssets

# .gdignore only exists to keep the Godot editor out of this folder during
# development; the player has no use for it. _backup holds packs the app
# replaced on import and is nobody else's business.
Get-ChildItem -Path $StageAssets -Recurse -Force -Filter ".gdignore" | Remove-Item -Force
$stagedBackup = Join-Path $StageAssets "_backup"
if (Test-Path $stagedBackup) { Remove-Item -Recurse -Force $stagedBackup }

$assetCount = (Get-ChildItem -Path $StageAssets -Recurse -File).Count
Write-Host "    $assetCount files"

# --- The README the player reads ----------------------------------------

Write-Step "Writing README.txt"

$creditsPath = Join-Path $AssetsDir "CREDITS.txt"
$credits = if (Test-Path $creditsPath) { Get-Content $creditsPath -Raw } else { "(no credits file found)" }

$titleLine = "DOGPET v$AppVersion"
$titleRule = "=" * $titleLine.Length

$readme = @"
$titleLine
$titleRule

A little dog that lives in its own window. It gets hungry, bored and
restless whether or not the app is open, so it will have been waiting for
you when you come back.


HOW TO RUN IT
-------------

Double-click DogPet.exe.

Nothing is installed and nothing is written outside this folder. To get rid
of DogPet, delete the folder.

Keep DogPet.exe and the assets folder together. The app reads all its art
from assets/ as it runs, which is what lets you change the dog and the
rooms without rebuilding anything.


LOOKING AFTER THE DOG
---------------------

Three needs, all of which keep moving while the app is closed:

  Hunger      rises.  A full bar means starving.   Fix it with Feed.
  Happiness   falls.  An empty bar means miserable. Fix it with Play.
  Energy      rises.  A full bar means restless.    Fix it with Walk.

The dog never dies and never runs away. It just gets sad until you help.

How fast all this happens is up to you: open Settings and pick Frequent,
Moderate or Long. There is also a Demo Speed toggle that runs everything in
under a minute, for when you want to see what happens without waiting.

Time you spend away is always caught up at the real setting, never at Demo
speed - otherwise one demo session would max every bar the moment you
reopened the app.


THE TRAY
--------

Closing the window tucks DogPet into the system tray rather than quitting
it, and the needs carry on. Click the tray icon to bring it back, or
right-click it for a menu. While it is out of the way DogPet drops to a
very low frame rate, so leaving it running costs almost nothing.

It will tell you with a Windows notification when the dog needs something.
Those arrive from "Windows PowerShell" - that is expected. DogPet installs
nothing, so it has no registered name of its own to announce itself with.

You can turn notifications off, or pause them for an hour, in Settings.


WHERE YOUR SAVES ARE
--------------------

In the saves folder, next to the exe. It is made the first time you run.

If you put DogPet somewhere Windows will not let it write - Program Files,
for instance - it falls back to your user data folder and tells you on
screen where the saves went. Settings > About always shows the real paths.


CHANGING THE ART
----------------

Everything the app draws is in the assets folder, in ordinary folders with
ordinary PNG and GLB files. Have a look at assets/README.txt for how to add
your own dog or build a new room.

In short:

  assets/pets/<any name>/     one folder per pet, with a pet.json
  assets/scenes/<any name>/   one folder per room, with a scene.json
  assets/ui/                  the icons

After changing anything, use Settings > Assets > Reload, or restart.

Settings > Assets can also export a pet or a room as a .zip to give to
somebody, and import one you were given. Importing never overwrites
anything without asking, and keeps a copy of whatever it replaces in
assets/_backup.

If assets/ goes missing entirely, DogPet falls back to a copy of the pug
and the four rooms kept inside the exe, and says so. It will not refuse to
start.


CREDITS
-------

The art is not all under the same licence, and some of it requires that the
credit stays visible. These credits are also in Settings > About.

$credits

The licence files are in assets/licenses/. Please keep them.

DogPet's own code is MIT licensed. Source: https://github.com/VagueScorpio/DogPet
"@

# Windows PowerShell's -Encoding UTF8 writes a byte order mark, which shows
# up as a stray character on the first line in plenty of editors. Write it
# without one. CRLF so it reads properly in Notepad.
$readmeText = ($readme -replace "`r?`n", "`r`n")
[System.IO.File]::WriteAllText(
    (Join-Path $StageDir "README.txt"),
    $readmeText,
    (New-Object System.Text.UTF8Encoding($false))
)

# --- Zip -----------------------------------------------------------------

Write-Step "Zipping"

if (Test-Path $ZipPath) { Remove-Item -Force $ZipPath }
Compress-Archive -Path (Join-Path $StageDir "*") -DestinationPath $ZipPath -CompressionLevel Optimal

$zipSize = [math]::Round((Get-Item $ZipPath).Length / 1MB, 1)

Write-Host ""
Write-Host "Built DogPet v$AppVersion" -ForegroundColor Green
Write-Host "    $ZipPath"
Write-Host "    $zipSize MB"
Write-Host ""
Write-Host "Unzip it somewhere and run DogPet.exe."
Write-Host ""
