# Imports the project, then runs all GUT tests headless. Exit code 0 means every test passed.
# Refuses to run during a GPU hold, because any Godot process can corrupt pipeline output.

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
& $godot --headless --path $projectRoot -s addons/gut/gut_cmdln.gd
exit $LASTEXITCODE
