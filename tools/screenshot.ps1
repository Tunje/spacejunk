# Runs the client windowed, saves one rendered frame and quits. Needs a GPU, so it cannot run headless.
# Refuses to run during a GPU hold. Extra arguments are passed to the client after `--`.
# Example: tools/screenshot.ps1 -Name shell -Frames 60

param(
    [string]$Name = 'client',
    [int]$Frames = 30,
    [string]$Size = '1600x900',
    [string[]]$ClientArgs = @()
)

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

$outDir = Join-Path $projectRoot 'screenshots'
New-Item -ItemType Directory -Force $outDir | Out-Null
$outFile = Join-Path $outDir "$Name.png"
if (Test-Path $outFile) { Remove-Item $outFile }

& $godot --headless --path $projectRoot --import | Out-Null
& $godot --path $projectRoot --resolution $Size -- "--shot=$($outFile -replace '\\', '/')" "--frames=$Frames" @ClientArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if (-not (Test-Path $outFile)) {
    Write-Output "No screenshot was written to $outFile"
    exit 1
}
Write-Output "Saved $outFile"
