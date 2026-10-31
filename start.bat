@echo off
rem Double-click to play. Launches the game from this folder in Godot.

set "GAME_GODOT=%GODOT%"
if "%GAME_GODOT%"=="" set "GAME_GODOT=C:\Users\simon\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"

if exist "C:\Users\simon\PROGRAMING\newmanprobe-wt\GPU_HOLD" (
    echo A GPU hold is active, so the game cannot run right now.
    echo Running Godot could damage the 3D models being generated.
    pause
    exit /b 3
)

if not exist "%GAME_GODOT%" (
    echo Godot was not found at:
    echo %GAME_GODOT%
    pause
    exit /b 2
)

start "" "%GAME_GODOT%" --path "%~dp0."
