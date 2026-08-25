@echo off
rem Folder-agnostic runner: derives the game name from this folder's name, so a
rem copied/renamed fork runs without editing this file (same pattern as
rem snkrx-template / ricochet-template).
cd /d "%~dp0.."
for %%I in ("%~dp0.") do set "GAME=%%~nxI"
"%~dp0anchor.exe" "%GAME%"
