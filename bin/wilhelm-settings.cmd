@echo off
REM Opens the wilhelm-alert panel on Windows.
REM %~dp0 ends with a backslash, so %~dp0.. is the repo root.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\app\Settings.ps1" -Root "%~dp0.." %*
