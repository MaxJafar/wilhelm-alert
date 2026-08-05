# The wilhelm-alert tray icon for Windows: the panel, the test and the two
# settings worth changing in a hurry, without opening anything.
#
# WinForms rather than WPF purely because NotifyIcon lives there. It ships
# with Windows like everything else here, so there is still nothing to build.
#
#   powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File Tray.ps1 -Root C:\path\to\wilhelm

param(
    [string]$Root = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
    # Same thing the menu's checkbox does, for anyone wiring this up from a
    # script or an installer instead of a right click.
    [switch]$EnableStartup,
    [switch]$DisableStartup
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

. (Join-Path $Root 'app\Config.ps1')

$iconPath   = Join-Path $Root 'assets\app-icon.ico'
$trayScript = Join-Path $Root 'app\Tray.ps1'
$panel      = Join-Path $Root 'app\Settings.ps1'
$alert      = Join-Path $Root 'bin\wilhelm-alert.js'
$powershell = (Get-Command powershell).Source

# ------------------------------------------------------------------ startup

function Get-StartupLink {
    Join-Path ([Environment]::GetFolderPath('Startup')) 'Wilhelm Alert.lnk'
}

function Test-StartupEnabled { Test-Path -LiteralPath (Get-StartupLink) }

function Enable-Startup {
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut((Get-StartupLink))
    $link.TargetPath = $powershell
    $link.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$trayScript`" -Root `"$Root`""
    $link.WorkingDirectory = $Root
    $link.WindowStyle = 7   # minimised, so the host window never takes focus
    $link.Description = 'Wilhelm Alert tray icon'
    if (Test-Path -LiteralPath $iconPath) { $link.IconLocation = $iconPath }
    $link.Save()
}

function Disable-Startup {
    Remove-Item -LiteralPath (Get-StartupLink) -Force -ErrorAction SilentlyContinue
}

# Handled before the icon goes up, so these are a one-shot switch rather than
# something that also leaves a tray icon behind.
if ($EnableStartup -or $DisableStartup) {
    if ($EnableStartup) { Enable-Startup } else { Disable-Startup }
    Write-Output "Start with Windows: $(if (Test-StartupEnabled) { 'on' } else { 'off' })"
    Write-Output (Get-StartupLink)
    exit 0
}

# One icon, however many times this gets launched. Startup and a stray double
# click otherwise leave two identical icons that both have to be quit.
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\wilhelm-alert-tray', [ref]$createdNew)
if (-not $createdNew) { exit 0 }

# ------------------------------------------------------------------ actions

function Start-Hidden {
    param([string]$FilePath, [string[]]$Arguments)
    Start-Process -FilePath $FilePath -ArgumentList $Arguments `
        -WindowStyle Hidden -WorkingDirectory $Root
}

function Open-Panel {
    Start-Hidden -FilePath $powershell -Arguments @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$panel`"", '-Root', "`"$Root`"")
}

function Invoke-TestAlert {
    # Read the config rather than caching: the panel may have changed either of
    # these since this process started.
    Start-Hidden -FilePath 'node' -Arguments @(
        "`"$alert`"", '--force', '--mode', (Get-ConfiguredMode), '--volume', (Get-ConfiguredVolume))
}

# -------------------------------------------------------------------- icon

$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = if (Test-Path -LiteralPath $iconPath) {
    New-Object System.Drawing.Icon $iconPath
} else {
    [System.Drawing.SystemIcons]::Application
}
$notify.Visible = $true

# NotifyIcon.Text is capped at 63 characters, which this stays well inside.
function Update-Tooltip {
    $volume = Get-ConfiguredVolume
    $loudness = if ($volume -eq 0) { 'muted' } else { "$volume%" }
    $notify.Text = "Wilhelm Alert - $(Get-ConfiguredMode), $loudness"
}
Update-Tooltip

# -------------------------------------------------------------------- menu

$menu = New-Object System.Windows.Forms.ContextMenuStrip

function Add-MenuItem {
    param(
        [System.Windows.Forms.ToolStripItemCollection]$Into,
        [string]$Text,
        [scriptblock]$OnClick,
        [switch]$Default
    )
    $item = New-Object System.Windows.Forms.ToolStripMenuItem $Text
    if ($OnClick) { $item.Add_Click($OnClick) }
    if ($Default) { $item.Font = New-Object System.Drawing.Font $item.Font, ([System.Drawing.FontStyle]::Bold) }
    $Into.Add($item) | Out-Null
    $item
}

$openItem = Add-MenuItem -Into $menu.Items -Text 'Open the panel' -Default -OnClick { Open-Panel }
Add-MenuItem -Into $menu.Items -Text 'Test the alert' -OnClick { Invoke-TestAlert } | Out-Null
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

$modeItem = Add-MenuItem -Into $menu.Items -Text 'Mode'
$modeItems = @{}
foreach ($mode in @(
    @{ Id = 'light';  Label = 'Light - just the scream' },
    @{ Id = 'middle'; Label = 'Middle - scream and popup' },
    @{ Id = 'turbo';  Label = 'Turbo - popup shakes itself apart' }
)) {
    $id = $mode.Id
    $modeItems[$id] = Add-MenuItem -Into $modeItem.DropDownItems -Text $mode.Label -OnClick {
        Set-ConfiguredMode -Mode $id
        Update-Tooltip
    }.GetNewClosure()
}

$volumeItem = Add-MenuItem -Into $menu.Items -Text 'Volume'
$volumeItems = @{}
foreach ($step in @(
    @{ Value = 0;   Label = 'Muted - popup only' },
    @{ Value = 25;  Label = '25%' },
    @{ Value = 50;  Label = '50%' },
    @{ Value = 75;  Label = '75%' },
    @{ Value = 100; Label = 'Full' }
)) {
    $value = $step.Value
    $volumeItems[$value] = Add-MenuItem -Into $volumeItem.DropDownItems -Text $step.Label -OnClick {
        Set-ConfiguredVolume -Volume $value
        Update-Tooltip
    }.GetNewClosure()
}

$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$startupItem = Add-MenuItem -Into $menu.Items -Text 'Start with Windows' -OnClick {
    if (Test-StartupEnabled) { Disable-Startup } else { Enable-Startup }
}
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
Add-MenuItem -Into $menu.Items -Text 'Quit' -OnClick {
    [System.Windows.Forms.Application]::Exit()
} | Out-Null

# The panel writes the same config file, so the ticks are worked out when the
# menu opens rather than being remembered from whenever this last set them.
$menu.Add_Opening({
    $mode = Get-ConfiguredMode
    foreach ($id in $modeItems.Keys) { $modeItems[$id].Checked = ($id -eq $mode) }
    $volume = Get-ConfiguredVolume
    foreach ($value in $volumeItems.Keys) { $volumeItems[$value].Checked = ($value -eq $volume) }
    $startupItem.Checked = Test-StartupEnabled
    Update-Tooltip
})

$notify.ContextMenuStrip = $menu
$notify.Add_MouseDoubleClick({ Open-Panel })

# Windows 11 files every new tray icon into the overflow, so say where it went
# once rather than leaving it to be discovered.
$greeted = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'wilhelm-alert\tray-greeted'
if (-not (Test-Path -LiteralPath $greeted)) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $greeted) | Out-Null
    Set-Content -LiteralPath $greeted -Value 'shown' -Encoding UTF8
    $notify.BalloonTipTitle = 'Wilhelm Alert is in your tray'
    $notify.BalloonTipText = 'Look under the hidden icons arrow. Drag it onto the taskbar to keep it out.'
    $notify.ShowBalloonTip(6000)
}

try {
    [System.Windows.Forms.Application]::Run()
} finally {
    # Without this the icon sits there as a ghost until something makes Windows
    # repaint the notification area.
    $notify.Visible = $false
    $notify.Dispose()
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
