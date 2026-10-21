@echo off
setlocal
cd /d "%~dp0"
start "" "%~dp0Player.exe" "--script=portable_config/launch-torrserver.lua"
