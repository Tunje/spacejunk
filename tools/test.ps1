# Imports the project, then runs all GUT tests headless. Exit code 0 means every test passed.
# Refuses to run during a GPU hold, because any Godot process can corrupt pipeline output.
# -Quick skips tests/slow, the long shared runs, for use while working. Run the full suite before
# reporting a task, and always before a merge: only it proves the whole chain.

param([switch]$Quick)

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

& $godot --headless --path $projectRoot --import | Out-Null

# GUT skips a test file it cannot parse and still reports success, so check for that here.
$ErrorActionPreference = 'Continue'
$config = if ($Quick) { ' -gconfig=res://.gutconfig.quick.json' } else { '' }
$output = & cmd /c "`"$godot`" --headless --path `"$projectRoot`" -s addons/gut/gut_cmdln.gd$config 2>&1"
$gutExit = $LASTEXITCODE
$output

if ($gutExit -ne 0) {
    exit $gutExit
}
$scriptErrors = @($output | Select-String 'SCRIPT ERROR').Count
if ($scriptErrors -gt 0) {
    Write-Output "FAILED: $scriptErrors script errors in the test run."
    exit 4
}
$testFiles = @(Get-ChildItem (Join-Path $projectRoot 'tests') -Recurse -Filter 'test_*.gd')
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
