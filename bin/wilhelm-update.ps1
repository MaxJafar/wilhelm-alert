# Pulls the latest wilhelm-alert and re-lands it everywhere it's installed.
# Windows counterpart of bin/wilhelm-update.
#
#   powershell -ExecutionPolicy Bypass -File wilhelm-update.ps1 [-Check]
#
# Refuses to touch a dirty working tree. Losing someone's uncommitted work to
# a convenience button is not a trade worth making.

param(
    [string]$Root = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
    [switch]$Check
)

$ErrorActionPreference = 'Continue'
$RawManifest = 'https://raw.githubusercontent.com/MaxJafar/wilhelm-alert/main/package.json'

function Get-LocalVersion {
    try {
        (Get-Content -LiteralPath (Join-Path $Root 'package.json') -Raw | ConvertFrom-Json).version
    } catch { '' }
}

function Get-RemoteVersion {
    try {
        $response = Invoke-WebRequest -Uri $RawManifest -UseBasicParsing -TimeoutSec 10
        ($response.Content | ConvertFrom-Json).version
    } catch { $null }
}

$local = Get-LocalVersion
$remote = Get-RemoteVersion

if ($Check) {
    if (-not $remote) { 'offline' }
    elseif ([version]$remote -gt [version]$local) { "update $remote" }
    else { "current $local" }
    exit 0
}

Write-Output "Local $local$(if ($remote) { ", latest $remote" })"

# ---------------------------------------------------------------- pull

if (Test-Path -LiteralPath (Join-Path $Root '.git')) {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Output 'git is not on PATH, so there is nothing to pull.'
    } else {
        $dirty = & git -C $Root status --porcelain 2>$null
        if ($dirty) {
            Write-Output 'Uncommitted changes here - not pulling. Commit or stash first, then retry.'
            $dirty | ForEach-Object { Write-Output "  $_" }
            exit 1
        }

        $branch = (& git -C $Root rev-parse --abbrev-ref HEAD 2>$null)
        if ($branch -eq 'HEAD') {
            Write-Output 'Detached HEAD - not pulling. Check out a branch first.'
            exit 1
        }

        Write-Output "Pulling $branch..."
        & git -C $Root pull --ff-only 2>&1 | ForEach-Object { Write-Output "  $_" }
        if ($LASTEXITCODE -ne 0) {
            Write-Output 'Pull failed. Resolve it in the repo, then retry.'
            exit 1
        }
        $local = Get-LocalVersion
    }
} else {
    Write-Output 'Not a git checkout, so there is nothing to pull - refreshing what is installed.'
}

# Nothing to compile on Windows: the overlay and this panel are both scripts.

# -------------------------------------------------------- agent plugins

if (Get-Command claude -ErrorAction SilentlyContinue) {
    Write-Output 'Claude Code...'
    & claude plugin marketplace update wilhelm-alert-marketplace 2>&1 | Out-Null
    $out = & claude plugin update wilhelm-alert@wilhelm-alert-marketplace 2>&1
    ($out | Select-Object -Last 1) | ForEach-Object { Write-Output "  $_" }
}

if (Get-Command codex -ErrorAction SilentlyContinue) {
    Write-Output 'Codex...'
    & codex plugin marketplace upgrade 2>&1 | Out-Null
    $out = & codex plugin add wilhelm-alert@wilhelm-alert-marketplace 2>&1
    ($out | Select-Object -Last 1) | ForEach-Object { Write-Output "  $_" }
}

Write-Output ''
Write-Output "Now on $local."
Write-Output 'Restart Claude Code to load it. Codex will ask you to approve the hook again'
Write-Output 'if hooks/hooks.json changed - its trust is a hash of the hook.'
exit 0
