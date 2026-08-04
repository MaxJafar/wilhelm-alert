# Creates a Start Menu shortcut for the panel, so it's searchable from the
# Windows key instead of living behind a cd and a script.
#
#   wilhelm-app.ps1 [-Uninstall] [-NoOpen]

param(
    [string]$Root = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
    [switch]$Uninstall,
    [switch]$NoOpen
)

$ErrorActionPreference = 'Stop'

$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$shortcutPath = Join-Path $startMenu 'Wilhelm Alert.lnk'

if ($Uninstall) {
    if (Test-Path -LiteralPath $shortcutPath) {
        Remove-Item -LiteralPath $shortcutPath -Force
        Write-Output "Removed $shortcutPath"
    } else {
        Write-Output 'No shortcut to remove.'
    }
    exit 0
}

$launcher = Join-Path $Root 'bin\wilhelm-settings.cmd'
if (-not (Test-Path -LiteralPath $launcher)) {
    Write-Output "wilhelm-app: missing $launcher"
    exit 1
}

New-Item -ItemType Directory -Force -Path $startMenu | Out-Null

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)

# Point at powershell directly rather than the .cmd, so launching it doesn't
# flash a console window on the way to the panel.
$shortcut.TargetPath = 'powershell.exe'
$shortcut.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Root\app\Settings.ps1`" -Root `"$Root`""
$shortcut.WorkingDirectory = $Root
$shortcut.Description = 'When agents finish, they scream.'

# .lnk wants an .ico; the faces are PNGs, so only set an icon if one exists.
$icon = Join-Path $Root 'assets\app-icon.ico'
if (Test-Path -LiteralPath $icon) { $shortcut.IconLocation = $icon }

$shortcut.Save()

Write-Output "Installed $shortcutPath"
Write-Output 'Open it from the Start Menu - press Windows and type "wilhelm".'

if (-not $NoOpen) {
    Start-Process -FilePath 'powershell' `
        -ArgumentList @('-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass',
                        '-File', "`"$Root\app\Settings.ps1`"", '-Root', "`"$Root`"") `
        -WorkingDirectory $Root
}
exit 0
