# Config access shared by the Windows panel and the tray icon.
#
# Both write the same file wilhelm-alert.js reads, so the key names, the
# preserve-other-keys rewrite and the volume clamp live here once instead of
# drifting apart in two places.
#
# Dot-sourced, never run:  . (Join-Path $Root 'app\Config.ps1')

function Get-ConfigPath {
    $base = if ($env:APPDATA) { $env:APPDATA } else { Join-Path $env:USERPROFILE 'AppData\Roaming' }
    Join-Path $base 'wilhelm-alert\config'
}

function Get-ConfigValue {
    param([string]$Key, [string]$Default)
    $path = Get-ConfigPath
    if (-not (Test-Path -LiteralPath $path)) { return $Default }
    foreach ($line in Get-Content -LiteralPath $path -ErrorAction SilentlyContinue) {
        if ($line -match "^\s*$Key\s*=\s*(\S+)") { return $Matches[1] }
    }
    return $Default
}

function Set-ConfigValue {
    param([string]$Key, [string]$Value)
    $path = Get-ConfigPath
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null

    $lines = @()
    if (Test-Path -LiteralPath $path) {
        # Keep any other keys the user set by hand, such as an absolute sound path.
        $lines = @(Get-Content -LiteralPath $path | Where-Object { $_ -notmatch "^\s*$Key\s*=" })
    }
    $lines += "$Key=$Value"
    Set-Content -LiteralPath $path -Value $lines -Encoding UTF8
}

function Get-ConfiguredMode { Get-ConfigValue -Key 'mode' -Default 'light' }

function Set-ConfiguredMode {
    param([string]$Mode)
    Set-ConfigValue -Key 'mode' -Value $Mode
}

# Anything unparseable or out of range reads as full volume, matching how
# wilhelm-alert.js falls back rather than refusing to make a noise.
function Get-ConfiguredVolume {
    $parsed = 0
    $raw = Get-ConfigValue -Key 'volume' -Default '100'
    if ([int]::TryParse($raw, [ref]$parsed) -and $parsed -ge 0 -and $parsed -le 100) {
        return $parsed
    }
    return 100
}

function Set-ConfiguredVolume {
    param([int]$Volume)
    Set-ConfigValue -Key 'volume' -Value $Volume
}
