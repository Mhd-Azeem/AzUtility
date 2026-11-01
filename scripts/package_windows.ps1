$ErrorActionPreference = 'Stop'
$azBundle = Join-Path $PSScriptRoot '../build/windows/x64/runner/Release'
$azVsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
if (Test-Path -LiteralPath $azVsWhere) {
    $azVsRoot = & $azVsWhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    $azCrtFolders = Get-ChildItem -Path (Join-Path $azVsRoot 'VC/Redist/MSVC/*/x64/Microsoft.VC*.CRT') -Directory | Sort-Object FullName -Descending
    if ($azCrtFolders.Count -gt 0) { Copy-Item -Path (Join-Path $azCrtFolders[0].FullName '*.dll') -Destination $azBundle -Force }
}
foreach ($azRequired in @('AZUtility.exe', 'flutter_windows.dll', 'vcruntime140.dll', 'msvcp140.dll', 'data/icudtl.dat', 'data/flutter_assets', 'data/app.so')) {
    if (-not (Test-Path -LiteralPath (Join-Path $azBundle $azRequired))) { throw "Missing runtime component: $azRequired" }
}
$azDist = Join-Path $PSScriptRoot '../dist'
New-Item -ItemType Directory -Force $azDist | Out-Null
$azName = 'AZUtility-v1.0.0-windows-x64.zip'
Compress-Archive -Path (Join-Path $azBundle '*') -DestinationPath (Join-Path $azDist $azName) -Force
$azHash = (Get-FileHash -Algorithm SHA256 (Join-Path $azDist $azName)).Hash.ToLowerInvariant()
"$azHash  $azName" | Set-Content (Join-Path $azDist 'SHA256SUMS-windows.txt')
'Windows executable is unsigned. Extract the entire ZIP and keep all companion files together.' | Set-Content (Join-Path $azDist 'WINDOWS-SIGNING.txt')
