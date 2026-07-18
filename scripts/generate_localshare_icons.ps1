[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

$workspace = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$androidRes = Join-Path $workspace 'app\android\app\src\main\res'
$windowsIcon = Join-Path $workspace 'app\windows\runner\resources\app_icon.ico'
$sharedImageRoot = Join-Path $workspace 'app\assets\img'
$trayIcon = Join-Path $sharedImageRoot 'logo.ico'

function New-RoundedRectanglePath {
    param(
        [Parameter(Mandatory = $true)]
        [System.Drawing.RectangleF]$Bounds,

        [Parameter(Mandatory = $true)]
        [float]$Radius
    )

    $diameter = $Radius * 2
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc($Bounds.Left, $Bounds.Top, $diameter, $diameter, 180, 90)
    $path.AddArc($Bounds.Right - $diameter, $Bounds.Top, $diameter, $diameter, 270, 90)
    $path.AddArc($Bounds.Right - $diameter, $Bounds.Bottom - $diameter, $diameter, $diameter, 0, 90)
    $path.AddArc($Bounds.Left, $Bounds.Bottom - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

function Add-NavigationMark {
    param(
        [Parameter(Mandatory = $true)]
        [System.Drawing.Graphics]$Graphics,

        [Parameter(Mandatory = $true)]
        [int]$Size,

        [Parameter(Mandatory = $true)]
        [float]$Inset,

        [System.Drawing.Color]$Color = [System.Drawing.Color]::White
    )

    $left = $Size * $Inset
    $top = $Size * $Inset
    $extent = $Size * (1 - 2 * $Inset)
    $points = [System.Drawing.PointF[]]@(
        [System.Drawing.PointF]::new($left + $extent * 0.08, $top + $extent * 0.08),
        [System.Drawing.PointF]::new($left + $extent * 0.94, $top + $extent * 0.47),
        [System.Drawing.PointF]::new($left + $extent * 0.58, $top + $extent * 0.59),
        [System.Drawing.PointF]::new($left + $extent * 0.47, $top + $extent * 0.94)
    )
    $mark = New-Object System.Drawing.Drawing2D.GraphicsPath
    try {
        $mark.AddPolygon($points)
        $brush = New-Object System.Drawing.SolidBrush $Color
        try {
            $Graphics.FillPath($brush, $mark)
        } finally {
            $brush.Dispose()
        }
    } finally {
        $mark.Dispose()
    }
}

function New-LocalShareBitmap {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Size,

        [switch]$ForegroundOnly,

        [System.Drawing.Color]$MarkColor = [System.Drawing.Color]::White
    )

    $bitmap = New-Object System.Drawing.Bitmap $Size, $Size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $bitmap.SetResolution(96, 96)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

        if ($ForegroundOnly) {
            Add-NavigationMark -Graphics $graphics -Size $Size -Inset 0.255 -Color $MarkColor
        } else {
            $padding = [float]($Size * 0.055)
            $bounds = [System.Drawing.RectangleF]::new(
                $padding,
                $padding,
                $Size - 2 * $padding,
                $Size - 2 * $padding
            )
            $shape = New-RoundedRectanglePath -Bounds $bounds -Radius ([float]($Size * 0.235))
            try {
                $start = [System.Drawing.ColorTranslator]::FromHtml('#0F766E')
                $end = [System.Drawing.ColorTranslator]::FromHtml('#5965A8')
                $gradient = New-Object System.Drawing.Drawing2D.LinearGradientBrush (
                    $bounds,
                    $start,
                    $end,
                    35.0
                )
                try {
                    $graphics.FillPath($gradient, $shape)
                } finally {
                    $gradient.Dispose()
                }

                $highlightBounds = [System.Drawing.RectangleF]::new(
                    $Size * 0.17,
                    $Size * 0.12,
                    $Size * 0.64,
                    $Size * 0.28
                )
                $highlight = New-Object System.Drawing.Drawing2D.LinearGradientBrush (
                    $highlightBounds,
                    [System.Drawing.Color]::FromArgb(45, 255, 255, 255),
                    [System.Drawing.Color]::FromArgb(0, 255, 255, 255),
                    90.0
                )
                try {
                    $oldClip = $graphics.Clip
                    try {
                        $graphics.SetClip($shape)
                        $graphics.FillEllipse($highlight, $highlightBounds)
                    } finally {
                        $graphics.Clip = $oldClip
                        $oldClip.Dispose()
                    }
                } finally {
                    $highlight.Dispose()
                }
            } finally {
                $shape.Dispose()
            }
            Add-NavigationMark -Graphics $graphics -Size $Size -Inset 0.235 -Color $MarkColor
        }
    } finally {
        $graphics.Dispose()
    }
    return $bitmap
}

function Save-Png {
    param(
        [Parameter(Mandatory = $true)]
        [System.Drawing.Bitmap]$Bitmap,

        [Parameter(Mandatory = $true)]
        [string]$LiteralPath
    )

    $parent = [System.IO.Path]::GetDirectoryName($LiteralPath)
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        throw "Icon output directory is missing: $parent"
    }
    $Bitmap.Save($LiteralPath, [System.Drawing.Imaging.ImageFormat]::Png)
}

function Get-PngBytes {
    param(
        [Parameter(Mandatory = $true)]
        [System.Drawing.Bitmap]$Bitmap
    )

    $stream = New-Object System.IO.MemoryStream
    try {
        $Bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
        return $stream.ToArray()
    } finally {
        $stream.Dispose()
    }
}

function Save-MultiSizeIco {
    param(
        [Parameter(Mandatory = $true)]
        [int[]]$Sizes,

        [Parameter(Mandatory = $true)]
        [string]$LiteralPath
    )

    $images = New-Object System.Collections.Generic.List[object]
    foreach ($size in $Sizes) {
        $bitmap = New-LocalShareBitmap -Size $size
        try {
            $images.Add([pscustomobject]@{
                Size = $size
                Bytes = Get-PngBytes -Bitmap $bitmap
            })
        } finally {
            $bitmap.Dispose()
        }
    }

    $stream = New-Object System.IO.MemoryStream
    $writer = New-Object System.IO.BinaryWriter $stream
    try {
        $writer.Write([uint16]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]$images.Count)

        $offset = 6 + 16 * $images.Count
        foreach ($image in $images) {
            $dimension = if ($image.Size -ge 256) { 0 } else { $image.Size }
            $writer.Write([byte]$dimension)
            $writer.Write([byte]$dimension)
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([uint16]1)
            $writer.Write([uint16]32)
            $writer.Write([uint32]$image.Bytes.Length)
            $writer.Write([uint32]$offset)
            $offset += $image.Bytes.Length
        }
        foreach ($image in $images) {
            $writer.Write([byte[]]$image.Bytes)
        }
        $writer.Flush()
        [System.IO.File]::WriteAllBytes($LiteralPath, $stream.ToArray())
    } finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

$legacySizes = [ordered]@{
    'mipmap-mdpi' = 48
    'mipmap-hdpi' = 72
    'mipmap-xhdpi' = 96
    'mipmap-xxhdpi' = 144
    'mipmap-xxxhdpi' = 192
}
$foregroundSizes = [ordered]@{
    'mipmap-mdpi' = 108
    'mipmap-hdpi' = 162
    'mipmap-xhdpi' = 216
    'mipmap-xxhdpi' = 324
    'mipmap-xxxhdpi' = 432
}

foreach ($entry in $legacySizes.GetEnumerator()) {
    $directory = Join-Path $androidRes $entry.Key
    $bitmap = New-LocalShareBitmap -Size $entry.Value
    try {
        Save-Png -Bitmap $bitmap -LiteralPath (Join-Path $directory 'ic_launcher.png')
        if ($entry.Key -eq 'mipmap-xxxhdpi') {
            Save-Png -Bitmap $bitmap -LiteralPath (Join-Path $directory 'ic_launcher_round.png')
        }
    } finally {
        $bitmap.Dispose()
    }
}

foreach ($entry in $foregroundSizes.GetEnumerator()) {
    $directory = Join-Path $androidRes $entry.Key
    $bitmap = New-LocalShareBitmap -Size $entry.Value -ForegroundOnly
    try {
        Save-Png -Bitmap $bitmap -LiteralPath (Join-Path $directory 'ic_launcher_foreground.png')
        Save-Png -Bitmap $bitmap -LiteralPath (Join-Path $directory 'ic_launcher_monochrome.png')
    } finally {
        $bitmap.Dispose()
    }
}

Save-MultiSizeIco -Sizes @(16, 20, 24, 32, 40, 48, 64, 128, 256) -LiteralPath $windowsIcon

$sharedLogoSizes = [ordered]@{
    'logo-32.png' = 32
    'logo-128.png' = 128
    'logo-256.png' = 256
    'logo-512.png' = 512
}
foreach ($entry in $sharedLogoSizes.GetEnumerator()) {
    $bitmap = New-LocalShareBitmap -Size $entry.Value
    try {
        Save-Png -Bitmap $bitmap -LiteralPath (Join-Path $sharedImageRoot $entry.Key)
    } finally {
        $bitmap.Dispose()
    }
}

$whiteMark = New-LocalShareBitmap -Size 32 -ForegroundOnly
try {
    Save-Png -Bitmap $whiteMark -LiteralPath (Join-Path $sharedImageRoot 'logo-32-white.png')
} finally {
    $whiteMark.Dispose()
}

$blackMark = New-LocalShareBitmap `
    -Size 32 `
    -ForegroundOnly `
    -MarkColor ([System.Drawing.Color]::Black)
try {
    Save-Png -Bitmap $blackMark -LiteralPath (Join-Path $sharedImageRoot 'logo-32-black.png')
} finally {
    $blackMark.Dispose()
}

Save-MultiSizeIco `
    -Sizes @(16, 20, 24, 32, 40, 48, 64, 128, 256) `
    -LiteralPath $trayIcon

Write-Output 'LocalShare Android, Windows, and shared tray icons were generated successfully.'
