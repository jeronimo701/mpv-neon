@echo off
setlocal
cd /d "%~dp0"
start "" "%~dp0mpv-neon.exe" "--script=portable_config/launch-torrserver.lua"
