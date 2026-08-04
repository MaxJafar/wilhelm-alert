@echo off
REM Puts "Wilhelm Alert" in the Start Menu so the panel is searchable instead
REM of living behind a cd and a script. The Windows counterpart of the macOS
REM .app bundle.
REM
REM   wilhelm-app              install the shortcut and open the panel
REM   wilhelm-app --uninstall  remove the shortcut
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0wilhelm-app.ps1" -Root "%~dp0.." %*
