# Saves the image currently on your clipboard as the face for an agent.
# Windows counterpart of bin/wilhelm-face.
#
#   wilhelm-face.ps1 claude     # copy the image, then run this

param(
    [string]$Root = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
    [Parameter(Position = 0)][string]$Name
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

if (-not $Name) {
    Write-Output 'usage: wilhelm-face.ps1 <claude|codex|cursor|antigravity|openclaw|any-name>'
    Write-Output '  Copy an image to the clipboard first, then run this.'
    exit 2
}

$assets = Join-Path $Root 'assets'
New-Item -ItemType Directory -Force -Path $assets | Out-Null
$out = Join-Path $assets "scream-$Name.png"

# Clipboard access needs STA; PowerShell defaults to MTA when run with -File.
$image = $null
$thread = [System.Threading.Thread]::new([System.Threading.ThreadStart]{
    $script:clipImage = [System.Windows.Forms.Clipboard]::GetImage()
})
$thread.SetApartmentState([System.Threading.ApartmentState]::STA)
$thread.Start()
$thread.Join()
$image = $script:clipImage

if (-not $image) {
    Write-Output 'wilhelm-face: no image on the clipboard.'
    Write-Output '  Right-click the image, Copy, then run this again.'
    exit 1
}

# The overlay renders at 300px, so anything huge is pure weight - and this
# file is copied into every agent's plugin cache on each update.
$maxEdge = 1024
if ($image.Width -gt $maxEdge -or $image.Height -gt $maxEdge) {
    $scale = [Math]::Min($maxEdge / $image.Width, $maxEdge / $image.Height)
    $width = [int]($image.Width * $scale)
    $height = [int]($image.Height * $scale)
    $resized = New-Object System.Drawing.Bitmap($width, $height)
    $graphics = [System.Drawing.Graphics]::FromImage($resized)
    $graphics.InterpolationMode = 'HighQualityBicubic'
    $graphics.DrawImage($image, 0, 0, $width, $height)
    $graphics.Dispose()
    $image.Dispose()
    $image = $resized
    Write-Output "Scaled down to ${maxEdge}px"
}

$image.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$image.Dispose()

$size = [Math]::Round((Get-Item -LiteralPath $out).Length / 1KB)
Write-Output "Saved ${size}K -> assets\scream-$Name.png"

# Any other file with this basename would shadow the new one, since the alert
# takes the first extension it finds.
Get-ChildItem -LiteralPath $assets -Filter "scream-$Name.*" |
    Where-Object { $_.FullName -ne $out } |
    ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Force
        Write-Output "Removed older $($_.Name)"
    }
exit 0
