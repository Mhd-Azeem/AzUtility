Add-Type -AssemblyName System.Drawing
$azRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$azAssets = Join-Path $azRoot 'assets/icons'
New-Item -ItemType Directory -Force $azAssets | Out-Null
$azBitmap = [Drawing.Bitmap]::new(256, 256)
$azGraphics = [Drawing.Graphics]::FromImage($azBitmap)
$azGraphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
$azGraphics.Clear([Drawing.ColorTranslator]::FromHtml('#091425'))
$azPen = [Drawing.Pen]::new([Drawing.ColorTranslator]::FromHtml('#58BDFE'), 7)
$azGraphics.DrawPolygon($azPen, [Drawing.Point[]]@([Drawing.Point]::new(128,18),[Drawing.Point]::new(230,76),[Drawing.Point]::new(230,180),[Drawing.Point]::new(128,238),[Drawing.Point]::new(26,180),[Drawing.Point]::new(26,76)))
$azFont = [Drawing.Font]::new('Segoe UI', 76, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
$azBrush = [Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml('#F3F7FF'))
$azFormat = [Drawing.StringFormat]::new()
$azFormat.Alignment = [Drawing.StringAlignment]::Center
$azFormat.LineAlignment = [Drawing.StringAlignment]::Center
$azGraphics.DrawString('AZ', $azFont, $azBrush, [Drawing.RectangleF]::new(0,0,256,256), $azFormat)
$azBitmap.Save((Join-Path $azAssets 'az-utility.png'), [Drawing.Imaging.ImageFormat]::Png)
$azSizes = @{'mdpi'=48; 'hdpi'=72; 'xhdpi'=96; 'xxhdpi'=144; 'xxxhdpi'=192}
foreach ($azDensity in $azSizes.Keys) {
    $azFolder = Join-Path $azRoot "android/app/src/main/res/mipmap-$azDensity"
    New-Item -ItemType Directory -Force $azFolder | Out-Null
    $azScaled = [Drawing.Bitmap]::new($azBitmap, $azSizes[$azDensity], $azSizes[$azDensity])
    $azScaled.Save((Join-Path $azFolder 'ic_launcher.png'), [Drawing.Imaging.ImageFormat]::Png)
    $azScaled.Dispose()
}
$azPng = [IO.File]::ReadAllBytes((Join-Path $azAssets 'az-utility.png'))
$azIcon = Join-Path $azRoot 'windows/runner/resources/app_icon.ico'
$azWriter = [IO.BinaryWriter]::new([IO.File]::Create($azIcon))
$azWriter.Write([uint16]0); $azWriter.Write([uint16]1); $azWriter.Write([uint16]1)
$azWriter.Write([byte]0); $azWriter.Write([byte]0); $azWriter.Write([byte]0); $azWriter.Write([byte]0)
$azWriter.Write([uint16]1); $azWriter.Write([uint16]32); $azWriter.Write([uint32]$azPng.Length); $azWriter.Write([uint32]22); $azWriter.Write($azPng)
$azWriter.Dispose(); $azGraphics.Dispose(); $azBitmap.Dispose(); $azPen.Dispose(); $azBrush.Dispose(); $azFont.Dispose(); $azFormat.Dispose()
