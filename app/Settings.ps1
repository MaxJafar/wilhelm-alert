# The wilhelm-alert panel for Windows: pick a mode, hear it, install it.
# WPF via PowerShell — the same toolkit the overlay uses, and it ships with
# Windows, so there is nothing to install and nothing to compile.
#
#   powershell -ExecutionPolicy Bypass -File Settings.ps1 -Root C:\path\to\wilhelm

param(
    [string]$Root = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$RepoUrl = 'https://github.com/MaxJafar/wilhelm-alert'
$RawManifest = 'https://raw.githubusercontent.com/MaxJafar/wilhelm-alert/main/package.json'

$Agents = @(
    @{ Source = 'openclaw';    Title = 'OpenClaw' },
    @{ Source = 'antigravity'; Title = 'Antigravity' },
    @{ Source = 'claude';      Title = 'Claude Code' },
    @{ Source = 'codex';       Title = 'Codex' },
    @{ Source = 'cursor';      Title = 'Cursor' }
)

# ---------------------------------------------------------------- config

function Get-ConfigPath {
    $base = if ($env:APPDATA) { $env:APPDATA } else { Join-Path $env:USERPROFILE 'AppData\Roaming' }
    Join-Path $base 'wilhelm-alert\config'
}

function Get-ConfiguredMode {
    $path = Get-ConfigPath
    if (-not (Test-Path -LiteralPath $path)) { return 'light' }
    foreach ($line in Get-Content -LiteralPath $path -ErrorAction SilentlyContinue) {
        if ($line -match '^\s*mode\s*=\s*(\S+)') { return $Matches[1] }
    }
    return 'light'
}

function Set-ConfiguredMode {
    param([string]$Mode)
    $path = Get-ConfigPath
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null

    $lines = @()
    if (Test-Path -LiteralPath $path) {
        # Keep any other keys the user set by hand, such as an absolute sound path.
        $lines = @(Get-Content -LiteralPath $path | Where-Object { $_ -notmatch '^\s*mode\s*=' })
    }
    $lines += "mode=$Mode"
    Set-Content -LiteralPath $path -Value $lines -Encoding UTF8
}

# ------------------------------------------------------- connection status

function Get-AgentStatus {
    param([string]$Source)
    $home_ = $env:USERPROFILE

    switch ($Source) {
        'claude' {
            $settings = Join-Path $home_ '.claude\settings.json'
            if (-not (Test-Path -LiteralPath $settings)) { return 'notConnected' }
            try {
                $json = Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json
                $enabled = $json.enabledPlugins.'wilhelm-alert@wilhelm-alert-marketplace'
                if ($enabled -eq $true) { return 'connected' }
            } catch { }
            return 'notConnected'
        }
        'codex' {
            $toml = Join-Path $home_ '.codex\config.toml'
            if (-not (Test-Path -LiteralPath $toml)) { return 'notConnected' }
            $text = Get-Content -LiteralPath $toml -Raw
            if ($text -notmatch '\[plugins\."wilhelm-alert@wilhelm-alert-marketplace"\]') {
                return 'notConnected'
            }
            # Codex reports a plugin as enabled while refusing to run its hooks
            # until they are reviewed, so "enabled" alone would be a lie here.
            if ($text -match '\[hooks\.state\."wilhelm-alert@') { return 'connected' }
            return 'needsApproval'
        }
        'cursor' {
            $hooks = Join-Path $home_ '.cursor\hooks.json'
            if ((Test-Path -LiteralPath $hooks) -and
                ((Get-Content -LiteralPath $hooks -Raw) -match 'wilhelm-alert')) {
                return 'connected'
            }
            return 'notConnected'
        }
        'openclaw' {
            $config = Join-Path $home_ '.openclaw\config.json'
            if ((Test-Path -LiteralPath $config) -and
                ((Get-Content -LiteralPath $config -Raw) -match 'wilhelm-alert')) {
                return 'connected'
            }
            return 'notConnected'
        }
        'antigravity' {
            # Antigravity walks up from the workspace looking for .agents, so
            # a hook can live either beside the repo or in the home directory.
            foreach ($candidate in @((Join-Path $Root '.agents\hooks.json'),
                                     (Join-Path $home_ '.agents\hooks.json'))) {
                if ((Test-Path -LiteralPath $candidate) -and
                    ((Get-Content -LiteralPath $candidate -Raw) -match 'wilhelm-alert')) {
                    return 'connected'
                }
            }
            return 'notConnected'
        }
    }
    return 'notConnected'
}

function Get-StatusText {
    param([string]$Status)
    switch ($Status) {
        'connected'     { 'CONNECTED' }
        'needsApproval' { 'APPROVE IT' }
        default         { 'NOT SET UP' }
    }
}

function Get-StatusBrush {
    param([string]$Status)
    switch ($Status) {
        'connected'     { '#4ADE80' }
        'needsApproval' { '#FB923C' }
        default         { '#8B8B93' }
    }
}

# ------------------------------------------------------------------- shell

function Invoke-Capture {
    param([string]$FilePath, [string[]]$Arguments)
    try {
        $info = New-Object System.Diagnostics.ProcessStartInfo
        $info.FileName = $FilePath
        $info.Arguments = ($Arguments -join ' ')
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $info.WorkingDirectory = $Root
        $process = [System.Diagnostics.Process]::Start($info)
        $out = $process.StandardOutput.ReadToEnd() + $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        return $out
    } catch {
        return "failed to run $FilePath : $_"
    }
}

function Test-Command {
    param([string]$Name)
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

# -------------------------------------------------------------------- XAML

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Wilhelm Alert" Height="820" Width="640"
        WindowStartupLocation="CenterScreen" Background="#151517"
        ResizeMode="CanMinimize">
  <Window.Resources>
    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="#F2F2F5"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
    </Style>
    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="#1D1D21"/>
      <Setter Property="BorderBrush" Value="#2E2E34"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="12"/>
      <Setter Property="Padding" Value="12"/>
    </Style>
    <Style x:Key="Section" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#F2F2F5"/>
      <Setter Property="FontSize" Value="15"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="Margin" Value="0,16,0,2"/>
    </Style>
    <Style x:Key="Sub" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#8B8B93"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="Margin" Value="0,0,0,8"/>
    </Style>
    <Style TargetType="Button">
      <Setter Property="Background" Value="#2B2B31"/>
      <Setter Property="Foreground" Value="#F2F2F5"/>
      <Setter Property="BorderBrush" Value="#3A3A42"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="12,5"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}"
                    CornerRadius="7" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <ScrollViewer VerticalScrollBarVisibility="Auto">
    <StackPanel Margin="26,20,26,22">

      <!-- header -->
      <Grid>
        <StackPanel>
          <TextBlock Text="WILHELM ALERT" Foreground="#E84F2E" FontSize="10" FontWeight="Bold"/>
          <TextBlock Text="When agents finish, they scream." FontSize="21" FontWeight="Bold" Margin="0,3,0,0"/>
          <TextBlock Text="One loud little ritual for five coding agents." Style="{StaticResource Sub}" Margin="0,3,0,0"/>
        </StackPanel>
        <Border x:Name="HeaderBadge" HorizontalAlignment="Right" VerticalAlignment="Top"
                Background="#1F2A20" CornerRadius="9" Padding="10,4">
          <TextBlock x:Name="HeaderBadgeText" Text="IDLE" Foreground="#8B8B93" FontSize="10" FontWeight="Bold"/>
        </Border>
      </Grid>

      <!-- roster -->
      <TextBlock Text="Your agent roster" Style="{StaticResource Section}"/>
      <TextBlock Text="Five faces. One shared completion ritual." Style="{StaticResource Sub}"/>
      <UniformGrid x:Name="Roster" Columns="5" Margin="0,0,0,4"/>

      <!-- modes -->
      <TextBlock Text="Choose your volume" Style="{StaticResource Section}"/>
      <TextBlock Text="How much chaos should follow a finished task?" Style="{StaticResource Sub}"/>
      <StackPanel x:Name="ModeList"/>

      <!-- test -->
      <StackPanel Orientation="Horizontal" Margin="0,14,0,0">
        <Button x:Name="TestButton" Content="Test the alert" Background="#E84F2E" BorderBrush="#E84F2E" Padding="18,7"/>
        <TextBlock Text="Saved automatically to your alert config."
                   Style="{StaticResource Sub}" Margin="12,7,0,0"/>
      </StackPanel>

      <!-- install -->
      <TextBlock Text="Install into your agents" Style="{StaticResource Section}"/>
      <TextBlock Text="Keep your local completion hooks one click away." Style="{StaticResource Sub}"/>
      <StackPanel x:Name="InstallList"/>

      <!-- updates -->
      <TextBlock Text="Updates" Style="{StaticResource Section}"/>
      <TextBlock Text="Pull the latest and push it into every agent at once." Style="{StaticResource Sub}"/>
      <Border Style="{StaticResource Card}">
        <Grid>
          <StackPanel>
            <TextBlock x:Name="VersionText" Text="Version" FontSize="13" FontWeight="SemiBold"/>
            <TextBlock x:Name="UpdateDetail" Text="Checking for updates..." Style="{StaticResource Sub}" Margin="0,3,0,0"/>
          </StackPanel>
          <Button x:Name="UpdateButton" Content="Check" HorizontalAlignment="Right" VerticalAlignment="Center" Width="110"/>
        </Grid>
      </Border>

      <!-- status -->
      <Border Background="#1B1512" BorderBrush="#3A241C" BorderThickness="1" CornerRadius="10" Padding="12,8" Margin="0,16,0,0">
        <TextBlock x:Name="StatusText" Text="Ready." Foreground="#C9C9D1" FontSize="11" TextWrapping="Wrap"/>
      </Border>

    </StackPanel>
  </ScrollViewer>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$script:AccentHex = '#E84F2E'

$rosterPanel  = $window.FindName('Roster')
$modeList     = $window.FindName('ModeList')
$installList  = $window.FindName('InstallList')
$statusText   = $window.FindName('StatusText')
$headerBadge  = $window.FindName('HeaderBadgeText')
$versionText  = $window.FindName('VersionText')
$updateDetail = $window.FindName('UpdateDetail')
$updateButton = $window.FindName('UpdateButton')
$testButton   = $window.FindName('TestButton')

function Set-Status { param([string]$Message) $statusText.Text = $Message }

function New-Brush { param([string]$Hex)
    [Windows.Media.BrushConverter]::new().ConvertFromString($Hex)
}

# ------------------------------------------------------------------ roster

$rosterBadges = @{}
$rosterHasFace = @{}

foreach ($agent in $Agents) {
    $facePath = Join-Path $Root ("assets\scream-" + $agent.Source + ".png")
    $hasFace = Test-Path -LiteralPath $facePath
    $rosterHasFace[$agent.Source] = $hasFace

    $card = New-Object Windows.Controls.Border
    $card.Background = New-Brush '#1D1D21'
    $card.BorderBrush = New-Brush '#2E2E34'
    $card.BorderThickness = 1
    $card.CornerRadius = 12
    $card.Margin = '0,0,7,0'
    $card.Padding = '5,8,5,8'

    $stack = New-Object Windows.Controls.StackPanel

    $imageBorder = New-Object Windows.Controls.Border
    $imageBorder.Background = New-Brush $(if ($hasFace) { '#000000' } else { '#232327' })
    $imageBorder.CornerRadius = 8
    $imageBorder.Height = 58
    if ($hasFace) {
        $image = New-Object Windows.Controls.Image
        $bitmap = New-Object Windows.Media.Imaging.BitmapImage
        $bitmap.BeginInit()
        $bitmap.UriSource = New-Object Uri($facePath)
        $bitmap.CacheOption = 'OnLoad'
        $bitmap.EndInit()
        $image.Source = $bitmap
        $image.Stretch = 'Uniform'
        $image.Margin = '3'
        $imageBorder.Child = $image
    } else {
        # An empty black square reads as a broken image; a dim placeholder
        # glyph plus the red MISSING badge below says "no face yet" instead.
        $placeholder = New-Object Windows.Controls.TextBlock
        $placeholder.Text = '?'
        $placeholder.FontSize = 22
        $placeholder.FontWeight = 'Bold'
        $placeholder.Foreground = New-Brush '#4A4A52'
        $placeholder.HorizontalAlignment = 'Center'
        $placeholder.VerticalAlignment = 'Center'
        $imageBorder.Child = $placeholder
    }
    $stack.Children.Add($imageBorder) | Out-Null

    $name = New-Object Windows.Controls.TextBlock
    $name.Text = $agent.Title
    $name.FontSize = 10
    $name.FontWeight = 'Bold'
    $name.Foreground = New-Brush '#F2F2F5'
    $name.HorizontalAlignment = 'Center'
    $name.Margin = '0,5,0,0'
    $name.TextTrimming = 'CharacterEllipsis'
    $stack.Children.Add($name) | Out-Null

    $badge = New-Object Windows.Controls.TextBlock
    $badge.FontSize = 8
    $badge.FontWeight = 'Bold'
    $badge.HorizontalAlignment = 'Center'
    $badge.Margin = '0,2,0,0'
    $stack.Children.Add($badge) | Out-Null
    $rosterBadges[$agent.Source] = $badge

    $card.Child = $stack
    $rosterPanel.Children.Add($card) | Out-Null
}

# ------------------------------------------------------------------- modes

$modes = @(
    @{ Id = 'light';  Title = 'Light';  Detail = 'Just the scream.';                          Badge = 'QUIET' },
    @{ Id = 'middle'; Title = 'Middle'; Detail = 'The scream, plus the model screaming back.'; Badge = 'POPULAR' },
    @{ Id = 'turbo';  Title = 'Turbo';  Detail = 'The popup shakes itself apart.';             Badge = 'CHAOTIC' }
)

$modeRadios = @{}
$modeUi = @{}
$currentMode = Get-ConfiguredMode

# Repaints every mode card from whichever radio is checked, mirroring the
# accent card + filled indicator the macOS panel draws for the selection.
function Update-ModeSelection {
    foreach ($id in $modeRadios.Keys) {
        $selected = [bool]$modeRadios[$id].IsChecked
        $ui = $modeUi[$id]
        $ui.Wrapper.Background = New-Brush $(if ($selected) { '#2A1710' } else { '#1D1D21' })
        $ui.Wrapper.BorderBrush = New-Brush $(if ($selected) { $script:AccentHex } else { '#2E2E34' })
        $ui.Wrapper.BorderThickness = $(if ($selected) { 1.5 } else { 1 })
        $ui.Title.Foreground = New-Brush $(if ($selected) { $script:AccentHex } else { '#F2F2F5' })
        $ui.BadgeText.Foreground = New-Brush $(if ($selected) { $script:AccentHex } else { '#8B8B93' })
        $ui.Indicator.Fill = New-Brush $(if ($selected) { $script:AccentHex } else { '#1D1D21' })
        $ui.Indicator.Stroke = New-Brush $(if ($selected) { $script:AccentHex } else { '#4A4A52' })
        $ui.Dot.Visibility = $(if ($selected) { 'Visible' } else { 'Collapsed' })
    }
}

foreach ($mode in $modes) {
    # The card itself toggles the radio, so the radio chrome stays hidden and
    # the whole rounded row is the hit target. The radio still owns the
    # grouping and the checked state.
    $radio = New-Object Windows.Controls.RadioButton
    $radio.GroupName = 'mode'
    $radio.Tag = $mode.Id
    $radio.Visibility = 'Collapsed'
    $radio.IsChecked = ($mode.Id -eq $currentMode)

    $row = New-Object Windows.Controls.Grid

    # Selection indicator: a ring that fills with the accent when active.
    $indicator = New-Object Windows.Shapes.Ellipse
    $indicator.Width = 15
    $indicator.Height = 15
    $indicator.StrokeThickness = 1.2
    $indicator.HorizontalAlignment = 'Left'
    $indicator.VerticalAlignment = 'Top'
    $indicator.Margin = '2,1,0,0'
    $dot = New-Object Windows.Shapes.Ellipse
    $dot.Width = 5
    $dot.Height = 5
    $dot.Fill = New-Brush '#FFFFFF'
    $dot.HorizontalAlignment = 'Left'
    $dot.VerticalAlignment = 'Top'
    $dot.Margin = '7,6,0,0'
    $dot.IsHitTestVisible = $false
    $row.Children.Add($indicator) | Out-Null
    $row.Children.Add($dot) | Out-Null

    $left = New-Object Windows.Controls.StackPanel
    $left.Margin = '26,0,0,0'

    $title = New-Object Windows.Controls.TextBlock
    $title.Text = $mode.Title
    $title.FontSize = 13
    $title.FontWeight = 'SemiBold'
    $title.Foreground = New-Brush '#F2F2F5'
    $left.Children.Add($title) | Out-Null

    $detail = New-Object Windows.Controls.TextBlock
    $detail.Text = $mode.Detail
    $detail.FontSize = 11
    $detail.Foreground = New-Brush '#8B8B93'
    $left.Children.Add($detail) | Out-Null
    $row.Children.Add($left) | Out-Null

    $badgeText = New-Object Windows.Controls.TextBlock
    $badgeText.Text = $mode.Badge
    $badgeText.FontSize = 9
    $badgeText.FontWeight = 'Bold'
    $badgeText.Foreground = New-Brush '#8B8B93'
    $badgeText.HorizontalAlignment = 'Right'
    $badgeText.VerticalAlignment = 'Top'
    $row.Children.Add($badgeText) | Out-Null

    $wrapper = New-Object Windows.Controls.Border
    $wrapper.Background = New-Brush '#1D1D21'
    $wrapper.BorderBrush = New-Brush '#2E2E34'
    $wrapper.BorderThickness = 1
    $wrapper.CornerRadius = 12
    $wrapper.Padding = '12,10,14,10'
    $wrapper.Margin = '0,0,0,8'
    $wrapper.Cursor = 'Hand'
    $wrapper.Child = $row

    $wrapper.Add_MouseLeftButtonUp({
        param($sender, $eventArgs)
        $radio = $sender.Tag
        $radio.IsChecked = $true
        $eventArgs.Handled = $true
    })

    $wrapper.Tag = $radio

    $radio.Add_Checked({
        $selected = $this.Tag
        Set-ConfiguredMode -Mode $selected
        Set-Status "Mode set to $selected. Saved to $(Get-ConfigPath)"
        Update-ModeSelection
    }.GetNewClosure())

    $modeRadios[$mode.Id] = $radio
    $modeUi[$mode.Id] = @{ Wrapper = $wrapper; Indicator = $indicator; Dot = $dot; Title = $title; BadgeText = $badgeText }
    $modeList.Children.Add($wrapper) | Out-Null
}

Update-ModeSelection

# ----------------------------------------------------------------- install

$installRows = @{}

function New-InstallRow {
    param([string]$Source, [string]$Title, [string]$Detail)

    $card = New-Object Windows.Controls.Border
    $card.Background = New-Brush '#1D1D21'
    $card.BorderBrush = New-Brush '#2E2E34'
    $card.BorderThickness = 1
    $card.CornerRadius = 12
    $card.Padding = '12,10,12,10'
    $card.Margin = '0,0,0,7'

    $grid = New-Object Windows.Controls.Grid
    $copy = New-Object Windows.Controls.StackPanel
    $copy.Margin = '54,0,0,0'

    $name = New-Object Windows.Controls.TextBlock
    $name.Text = $Title
    $name.FontSize = 13
    $name.FontWeight = 'SemiBold'
    $name.Foreground = New-Brush '#F2F2F5'
    $copy.Children.Add($name) | Out-Null

    # NB: the local is not $detail — that would collide with the $Detail
    # param, since PowerShell variable names are case-insensitive.
    $detailText = New-Object Windows.Controls.TextBlock
    $detailText.Text = $Detail
    $detailText.FontSize = 11
    $detailText.Foreground = New-Brush '#8B8B93'
    $copy.Children.Add($detailText) | Out-Null
    $grid.Children.Add($copy) | Out-Null

    $facePath = Join-Path $Root ("assets\scream-$Source.png")
    if (Test-Path -LiteralPath $facePath) {
        $faceBorder = New-Object Windows.Controls.Border
        $faceBorder.Background = New-Brush '#000000'
        $faceBorder.CornerRadius = 8
        $faceBorder.Width = 44
        $faceBorder.Height = 44
        $faceBorder.HorizontalAlignment = 'Left'
        $faceBorder.VerticalAlignment = 'Center'
        $image = New-Object Windows.Controls.Image
        $bitmap = New-Object Windows.Media.Imaging.BitmapImage
        $bitmap.BeginInit()
        $bitmap.UriSource = New-Object Uri($facePath)
        $bitmap.CacheOption = 'OnLoad'
        $bitmap.EndInit()
        $image.Source = $bitmap
        $image.Stretch = 'Uniform'
        $image.Margin = '3'
        $faceBorder.Child = $image
        $grid.Children.Add($faceBorder) | Out-Null
    }

    $right = New-Object Windows.Controls.StackPanel
    $right.Orientation = 'Horizontal'
    $right.HorizontalAlignment = 'Right'
    $right.VerticalAlignment = 'Center'

    $badge = New-Object Windows.Controls.TextBlock
    $badge.FontSize = 10
    $badge.FontWeight = 'Bold'
    $badge.VerticalAlignment = 'Center'
    $badge.Margin = '0,0,10,0'
    $right.Children.Add($badge) | Out-Null

    $button = New-Object Windows.Controls.Button
    $button.Content = 'Install'
    $button.Width = 110
    $button.Tag = $Source
    $right.Children.Add($button) | Out-Null

    $grid.Children.Add($right) | Out-Null
    $card.Child = $grid

    $installRows[$Source] = @{ Badge = $badge; Button = $button }
    $installList.Children.Add($card) | Out-Null
    return $button
}

$claudeButton = New-InstallRow -Source 'claude' -Title 'Claude Code' -Detail 'Install or refresh the Claude plugin.'
$codexButton  = New-InstallRow -Source 'codex'  -Title 'Codex'       -Detail 'Install or refresh the Codex plugin.'
# '~/.cursor' would render as a literal tilde here — Windows config lives at
# %USERPROFILE%, so name the directory the user would actually open.
$cursorHooksHint = Join-Path $env:USERPROFILE '.cursor\hooks.json'
$cursorButton = New-InstallRow -Source 'cursor' -Title 'Cursor'      -Detail "Add the stop hook to $cursorHooksHint."

# ------------------------------------------------------------- refreshing

function Update-Statuses {
    $connected = 0
    foreach ($agent in $Agents) {
        $state = Get-AgentStatus -Source $agent.Source
        if ($state -eq 'connected') { $connected++ }

        $badge = $rosterBadges[$agent.Source]
        if ($badge) {
            if ($rosterHasFace[$agent.Source]) {
                $badge.Text = Get-StatusText $state
                $badge.Foreground = New-Brush (Get-StatusBrush $state)
            } else {
                # No face asset: the connection state is less useful than
                # saying the popup has nothing to show for this agent.
                $badge.Text = 'MISSING'
                $badge.Foreground = New-Brush '#F87171'
            }
        }

        $row = $installRows[$agent.Source]
        if ($row) {
            $row.Badge.Text = Get-StatusText $state
            $row.Badge.Foreground = New-Brush (Get-StatusBrush $state)
            $row.Button.Content = if ($state -eq 'notConnected') { 'Install' } else { 'Update' }
        }
    }

    $headerBadge.Text = if ($connected -eq 0) { 'IDLE' } else { "$connected LIVE" }
    $headerBadge.Foreground = New-Brush $(if ($connected -eq 0) { '#8B8B93' } else { '#4ADE80' })
}

# --------------------------------------------------------------- handlers

$testButton.Add_Click({
    $selected = 'light'
    foreach ($key in $modeRadios.Keys) {
        if ($modeRadios[$key].IsChecked) { $selected = $key }
    }
    $alert = Join-Path $Root 'bin\wilhelm-alert.js'
    Start-Process -FilePath 'node' -ArgumentList @("`"$alert`"", '--force', '--mode', $selected) `
        -WindowStyle Hidden -WorkingDirectory $Root
    Set-Status "Testing $selected..."
})

$claudeButton.Add_Click({
    if (-not (Test-Command 'claude')) { Set-Status 'Could not find `claude` on your PATH.'; return }
    Set-Status 'Installing into Claude Code...'
    Invoke-Capture -FilePath 'claude' -Arguments @('plugin', 'marketplace', 'add', './') | Out-Null
    $out = Invoke-Capture -FilePath 'claude' -Arguments @('plugin', 'install', 'wilhelm-alert@wilhelm-alert-marketplace')
    if ($out -match 'already installed') {
        $out = Invoke-Capture -FilePath 'claude' -Arguments @('plugin', 'update', 'wilhelm-alert@wilhelm-alert-marketplace')
    }
    Update-Statuses
    Set-Status (($out -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 1))
})

$codexButton.Add_Click({
    if (-not (Test-Command 'codex')) { Set-Status 'Could not find `codex` on your PATH.'; return }
    Set-Status 'Installing into Codex...'
    Invoke-Capture -FilePath 'codex' -Arguments @('plugin', 'marketplace', 'add', '.') | Out-Null
    Invoke-Capture -FilePath 'codex' -Arguments @('plugin', 'add', 'wilhelm-alert@wilhelm-alert-marketplace') | Out-Null
    Update-Statuses
    Set-Status 'Installed. Now start `codex` in a terminal and approve the hook review - it will not fire until you do.'
})

$cursorButton.Add_Click({
    $hooksPath = Join-Path $env:USERPROFILE '.cursor\hooks.json'
    $command = "node `"$(Join-Path $Root 'bin\wilhelm-alert.js')`" --source cursor"

    $root = [ordered]@{ version = 1; hooks = [ordered]@{} }
    if (Test-Path -LiteralPath $hooksPath) {
        try {
            # Merge rather than overwrite: this file very likely holds hooks
            # the user cares about.
            $existing = Get-Content -LiteralPath $hooksPath -Raw | ConvertFrom-Json
            $root = [ordered]@{}
            foreach ($property in $existing.PSObject.Properties) { $root[$property.Name] = $property.Value }
            if (-not $root.Contains('version')) { $root['version'] = 1 }
        } catch { }
    }

    $hooks = [ordered]@{}
    if ($root['hooks']) {
        foreach ($property in $root['hooks'].PSObject.Properties) { $hooks[$property.Name] = $property.Value }
    }
    $stop = @()
    if ($hooks['stop']) {
        $stop = @($hooks['stop'] | Where-Object { $_.command -notmatch 'wilhelm-alert' })
    }
    $stop += [ordered]@{ command = $command }
    $hooks['stop'] = $stop
    $root['hooks'] = $hooks

    try {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $hooksPath) | Out-Null
        ($root | ConvertTo-Json -Depth 12) | Set-Content -LiteralPath $hooksPath -Encoding UTF8
        Update-Statuses
        Set-Status "Added the stop hook to $hooksPath - restart Cursor."
    } catch {
        Set-Status "Couldn't write hooks.json: $_"
    }
})

# ---------------------------------------------------------------- updates

function Get-LocalVersion {
    try {
        (Get-Content -LiteralPath (Join-Path $Root 'package.json') -Raw | ConvertFrom-Json).version
    } catch { 'unknown' }
}

$script:PendingVersion = $null
$script:UpdatePoll = $null

function Apply-UpdateCheck {
    param([string]$Remote)

    $local = Get-LocalVersion
    $versionText.Text = "Version $local"

    $parsed = $null
    if ($Remote) {
        try { $parsed = [version]$Remote } catch { $parsed = $null }
    }

    if (-not $parsed) {
        $script:PendingVersion = $null
        $updateButton.Content = 'Check'
        $updateDetail.Text = "Couldn't reach GitHub. Check again later."
        $updateDetail.Foreground = New-Brush '#8B8B93'
        return
    }

    if ($parsed -gt [version]$local) {
        $script:PendingVersion = $Remote
        $updateDetail.Text = "Version $Remote is available."
        $updateDetail.Foreground = New-Brush '#4ADE80'
        $updateButton.Content = 'Update'
    } else {
        $script:PendingVersion = $null
        $updateDetail.Text = "You're on the latest version."
        $updateDetail.Foreground = New-Brush '#8B8B93'
        $updateButton.Content = 'Check'
    }
}

function Check-ForUpdate {
    # The web call runs in a background runspace: this reaches out to GitHub,
    # and a slow or dead network must never freeze the window. The result is
    # applied by the dispatcher timer when the fetch lands.
    $versionText.Text = "Version $(Get-LocalVersion)"
    # One fetch at a time: the startup check is usually still in flight when an
    # impatient click arrives, and overwriting the handle would strand it.
    if ($script:UpdatePoll) { return }
    $rs = [powershell]::Create()
    $rs.AddScript({
        param($Url)
        try {
            $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 10
            ($response.Content | ConvertFrom-Json).version
        } catch { '' }
    }).AddParameter('Url', $RawManifest) | Out-Null
    $script:UpdatePoll = @{ Runspace = $rs; Handle = $rs.BeginInvoke() }
}

$updateButton.Add_Click({
    if (-not $script:PendingVersion) {
        $updateDetail.Text = 'Checking...'
        Check-ForUpdate
        return
    }

    $updateButton.IsEnabled = $false
    $updateButton.Content = 'Updating'
    $updateDetail.Text = 'Updating...'
    Set-Status 'Pulling the latest and refreshing every agent...'

    $updater = Join-Path $Root 'bin\wilhelm-update.ps1'
    $out = Invoke-Capture -FilePath 'powershell' `
        -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$updater`"", '-Root', "`"$Root`"")

    $updateButton.IsEnabled = $true
    if ($out -match 'Uncommitted changes') {
        # Nothing was replaced, so the offered update is still pending: keep it
        # on the button rather than making them check for it all over again.
        $updateButton.Content = 'Update'
        $updateDetail.Text = "Version $script:PendingVersion is available."
        Set-Status 'Update stopped: you have uncommitted changes in the repo.'
    } else {
        $script:PendingVersion = $null
        $updateButton.Content = 'Check'
        Set-Status (($out -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 1))
        # The panel is still running the scripts this update just replaced, so
        # re-checking here would only overwrite this with "you're on the
        # latest" — true, and far less useful than saying to reopen.
        $versionText.Text = "Version $(Get-LocalVersion)"
        $updateDetail.Text = 'Updated - close and reopen to load it.'
        $updateDetail.Foreground = New-Brush '#4ADE80'
    }
    Update-Statuses
})

# ------------------------------------------------------------------ start

$window.Add_Activated({ Update-Statuses })

# Polls the background update check and applies whatever it fetched. Ticking
# on the dispatcher keeps the UI marquee-responsive while the request runs.
$updateTimer = New-Object Windows.Threading.DispatcherTimer
$updateTimer.Interval = [TimeSpan]::FromMilliseconds(250)
$updateTimer.Add_Tick({
    $poll = $script:UpdatePoll
    if ($poll -and $poll.Handle.IsCompleted) {
        $remote = ($poll.Runspace.EndInvoke($poll.Handle) | Select-Object -First 1)
        $poll.Runspace.Dispose()
        $script:UpdatePoll = $null
        Apply-UpdateCheck -Remote $remote
    }
})
$updateTimer.Start()

$window.Add_Closed({
    $updateTimer.Stop()
    # Disposing a runspace mid-request throws, and the fetch is still running
    # whenever the window is closed inside the request timeout.
    if ($script:UpdatePoll) {
        try { $script:UpdatePoll.Runspace.Stop() } catch { }
        try { $script:UpdatePoll.Runspace.Dispose() } catch { }
    }
})

Update-Statuses
Check-ForUpdate

if (-not (Test-Path -LiteralPath (Join-Path $Root 'sounds'))) {
    Set-Status "Warning: no sounds folder at $Root"
}

$window.ShowDialog() | Out-Null
