@echo off
REM Puts the wilhelm-alert icon in the Windows notification area.
REM %~dp0 ends with a backslash, so %~dp0.. is the repo root.
REM start /b so the console this was launched from is free again immediately.
start "" /b powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0..\app\Tray.ps1" -Root "%~dp0.." %*
