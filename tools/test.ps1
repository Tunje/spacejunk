# Imports the project, then runs all GUT tests headless. Exit code 0 means every test passed.
# Refuses to run during a GPU hold, because any Godot process can corrupt pipeline output.
# -Quick skips tests/slow, the long shared runs, for use while working. Run the full suite before
# reporting a task, and always before a merge: only it proves the whole chain.
# -Playthrough runs only tests/playthrough, the client playing the new start through research
# (D31), which the other modes skip. Run it before merging anything that touches the new
# start's UI, its snapshots or the order and jobs panels.

param([switch]$Quick, [switch]$Playthrough)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path $PSScriptRoot -Parent
$holdFile = 'C:\Users\simon\PROGRAMING\newmanprobe-wt\GPU_HOLD'
if (Test-Path $holdFile) {
    Write-Output "GPU hold active, Godot must not run: $(Get-Content $holdFile -Raw)"
    exit 3
}

$godot = $env:GODOT
if (-not $godot) {
    $godot = 'C:\Users\simon\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
}
if (-not (Test-Path $godot)) {
    Write-Output "Godot not found at $godot. Set the GODOT environment variable."
    exit 2
}

# Godot logs import hiccups, such as a file briefly locked while a .import file is
# replaced, to stderr and carries on. Under 'Stop' PowerShell made that fatal and ended
# the gate mid-import, so the import runs under 'Continue'; a real failure still fails
# the GUT run below.
$ErrorActionPreference = 'Continue'
& $godot --headless --path $projectRoot --import 2>&1 | Out-Null
$ErrorActionPreference = 'Stop'

# GUT skips a test file it cannot parse and still reports success, so check for that here.
$ErrorActionPreference = 'Continue'
# The full run lists every tests folder but tests/playthrough, and the smoke test at the top.
$full = ' -gdir=res://tests/bot,res://tests/client,res://tests/sim,res://tests/slow,res://tests/tools -gtest=res://tests/test_smoke.gd'
$config = if ($Playthrough) { ' -gdir=res://tests/playthrough' } elseif ($Quick) { ' -gconfig=res://.gutconfig.quick.json' } else { $full }
# GUT's JUnit report gives each file's time, for the slow-file warning below.
$junit = Join-Path ([System.IO.Path]::GetTempPath()) "newmanprobe-gut-$PID.xml"
# Each run gets its own user:// folder. Godot puts user:// under %APPDATA%, and every
# worktree has the same project name, so runs side by side would share save slots and
# load each other's saves. The import above keeps the real APPDATA and its editor settings.
$userData = Join-Path ([System.IO.Path]::GetTempPath()) "newmanprobe-user-$PID-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
New-Item -ItemType Directory -Path $userData -Force | Out-Null
$realAppData = $env:APPDATA
$env:APPDATA = $userData
try {
    $output = & cmd /c "`"$godot`" --headless --path `"$projectRoot`" -s addons/gut/gut_cmdln.gd$config -gjunit_xml_file=`"$junit`" 2>&1"
    $gutExit = $LASTEXITCODE
} finally {
    $env:APPDATA = $realAppData
    Remove-Item $userData -Recurse -Force -ErrorAction SilentlyContinue
}
$output

# A warning, never a failure: any test file over 20 s, so the gate's time doesn't creep up unseen.
try {
    if (Test-Path $junit) {
        $report = [xml](Get-Content $junit -Raw)
        foreach ($suite in $report.SelectNodes('//testsuite')) {
            $seconds = [double]$suite.time
            if ($seconds -gt 20) {
                Write-Output ("SLOW: {0} took {1:N0} s, over the 20 s per file guide" -f $suite.name, $seconds)
            }
        }
        Remove-Item $junit -ErrorAction SilentlyContinue
    }
} catch {
    Write-Output "Note: could not read the test timing report: $_"
}

if ($gutExit -ne 0) {
    exit $gutExit
}
$scriptErrors = @($output | Select-String 'SCRIPT ERROR').Count
if ($scriptErrors -gt 0) {
    Write-Output "FAILED: $scriptErrors script errors in the test run."
    exit 4
}
$testFiles = @(Get-ChildItem (Join-Path $projectRoot 'tests') -Recurse -Filter 'test_*.gd')
if ($Playthrough) {
    $testFiles = @($testFiles | Where-Object { $_.Directory.Name -eq 'playthrough' })
} else {
    $testFiles = @($testFiles | Where-Object { $_.Directory.Name -ne 'playthrough' })
}
if ($Quick) {
    $testFiles = @($testFiles | Where-Object { $_.Directory.Name -ne 'slow' })
}
$expected = $testFiles.Count
$ranLine = $output | Select-String 'Scripts\s+(\d+)' | Select-Object -Last 1
$ran = if ($ranLine) { [int]$ranLine.Matches[0].Groups[1].Value } else { -1 }
if ($ran -ne $expected) {
    Write-Output "FAILED: GUT ran $ran test scripts, but tests/ holds $expected."
    exit 4
}
exit 0
