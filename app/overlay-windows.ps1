# The scream overlay for Windows: a borderless, transparent, topmost WPF
# window that fades in near the corner of the screen and gets out of the way.
#
#   powershell -File overlay-windows.ps1 -Image face.png -Mode turbo -Seconds 2.4

param(
    [Parameter(Mandatory = $true)][string]$Image,
    [string]$Mode = "middle",
    [double]$Seconds = 2.4
)

$ErrorActionPreference = "Stop"

try {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

    if (-not (Test-Path -LiteralPath $Image)) {
        [Console]::Error.WriteLine("wilhelm-overlay: no image at $Image")
        exit 1
    }

    $side = if ($Mode -eq "turbo") { 300 } else { 240 }

    $window = New-Object System.Windows.Window
    $window.WindowStyle = "None"
    $window.AllowsTransparency = $true
    $window.Background = [System.Windows.Media.Brushes]::Transparent
    $window.Topmost = $true
    $window.ShowInTaskbar = $false
    # Never steal focus: the alert must not eat a keystroke mid-type.
    $window.Focusable = $false
    $window.ShowActivated = $false
    $window.Width = $side
    $window.Height = $side
    $window.ResizeMode = "NoResize"

    $border = New-Object System.Windows.Controls.Border
    $border.CornerRadius = New-Object System.Windows.CornerRadius(28)
    $border.ClipToBounds = $true

    $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
    $bitmap.BeginInit()
    $bitmap.UriSource = New-Object System.Uri((Resolve-Path -LiteralPath $Image).Path)
    $bitmap.CacheOption = "OnLoad"
    $bitmap.EndInit()

    $imageControl = New-Object System.Windows.Controls.Image
    $imageControl.Source = $bitmap
    $imageControl.Stretch = "Uniform"
    $border.Child = $imageControl
    $window.Content = $border

    # Bottom-right of the working area, so it clears the taskbar.
    $work = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $margin = 28
    $baseLeft = $work.Right - $side - $margin
    $baseTop = $work.Bottom - $side - $margin
    $window.Left = $baseLeft
    $window.Top = $baseTop

    # Click anywhere to dismiss early.
    $window.Add_MouseDown({ $window.Close() })

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    if ($Mode -eq "turbo") {
        $shakeDuration = 0.62
        $shakeTimer = New-Object System.Windows.Threading.DispatcherTimer
        $shakeTimer.Interval = [TimeSpan]::FromMilliseconds(16)
        $shakeTimer.Add_Tick({
            $elapsed = $stopwatch.Elapsed.TotalSeconds
            if ($elapsed -ge $shakeDuration) {
                $shakeTimer.Stop()
                $window.Left = $baseLeft
                $window.Top = $baseTop
                return
            }
            # Driven oscillation with decay — random offsets read as a glitch,
            # a decaying sine reads as something being physically rattled.
            $progress = $elapsed / $shakeDuration
            $decay = [Math]::Pow(1.0 - $progress, 1.7)
            $amplitude = 34.0 * $decay
            $window.Left = $baseLeft + $amplitude * [Math]::Sin($elapsed * 58.0)
            $window.Top = $baseTop + $amplitude * 0.55 * [Math]::Sin($elapsed * 79.0 + 1.1)
        })
        $shakeTimer.Start()
    }

    $closeTimer = New-Object System.Windows.Threading.DispatcherTimer
    $closeTimer.Interval = [TimeSpan]::FromSeconds($Seconds)
    $closeTimer.Add_Tick({
        $closeTimer.Stop()
        $window.Close()
    })
    $closeTimer.Start()

    $window.Show()
    [System.Windows.Threading.Dispatcher]::Run()
}
catch {
    [Console]::Error.WriteLine("wilhelm-overlay: $_")
    exit 1
}
