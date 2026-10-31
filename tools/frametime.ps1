# Measures frame time at full slice load in four views, one with a side screen open, windowed, on this PC's GPU.
# Cannot run headless. Refuses to run during a GPU hold. Exit code 0 means every view met the target.
# Results are written to tools/output/.

param(
    [string]$Size = '1920x1080',
    [int]$Warmup = 4000,
    [int]$Samples = 8000,
    [int]$Speed = 8,
    [int]$Rocks = 6000,
    [string]$Scenario = 'stub_load'
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

$outDir = Join-Path $projectRoot 'tools\output'
New-Item -ItemType Directory -Force $outDir | Out-Null

$views = @(
    @{ Name = 'close'; Args = @('--zoom=40') },
    @{ Name = 'field'; Args = @('--zoom=3500', '--pitch=-0.3') },
    @{ Name = 'map'; Args = @('--map=1') },
    @{ Name = 'fit'; Args = @('--zoom=40', '--fit=none', '--fit-delay=5') }
)

& $godot --headless --path $projectRoot --import | Out-Null

$failed = 0
foreach ($view in $views) {
    $outFile = Join-Path $outDir "frametime_$($view.Name).json"
    if (Test-Path $outFile) { Remove-Item $outFile }
    $ErrorActionPreference = 'Continue'
    & cmd /c "`"$godot`" --path `"$projectRoot`" --resolution $Size -- --scenario=$Scenario --rocks=$Rocks --speed=$Speed --warmup=$Warmup --samples=$Samples --frametime=$($outFile -replace '\\', '/') $($view.Args -join ' ') 2>&1" | Out-Null
    $code = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if (-not (Test-Path $outFile)) {
        Write-Output "$($view.Name): no result written (exit $code)"
        $failed += 1
        continue
    }
    $result = Get-Content $outFile -Raw | ConvertFrom-Json
    $verdict = if ($result.passed) { 'PASS' } else { 'FAIL' }
    if (-not $result.passed) { $failed += 1 }
    Write-Output ("{0,-6} {1}  avg {2:N2} ms ({3:N0} fps)  p95 {4:N2}  p99 {5:N2}  worst {6:N2}" -f `
        $view.Name, $verdict, $result.average_ms, $result.average_fps, $result.p95_ms, $result.p99_ms, $result.worst_ms)
    Write-Output "       ship time: $($result.ship_op_share | ConvertTo-Json -Compress), rocks: $($result.decorative_rocks)"
}
if ($failed -gt 0) { exit 5 }
